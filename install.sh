#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="2.0.0"
readonly DEFAULT_UPSTREAM_REPO="byJoey/Actions-bbr-v3"

UPSTREAM_REPO="${ML_BBRV3_UPSTREAM_REPO:-$DEFAULT_UPSTREAM_REPO}"
SYSCTL_CONF="${ML_BBRV3_SYSCTL_CONF:-/etc/sysctl.d/99-ml-bbrv3.conf}"
CONNECT_TIMEOUT="${ML_BBRV3_CONNECT_TIMEOUT:-10}"
MAX_TIME="${ML_BBRV3_MAX_TIME:-60}"

DRY_RUN=0
YES=0
FORCE_NON_GRUB=0
REQUIRE_CHECKSUMS=0
COMMAND=""
COMMAND_ARG=""
SUDO=()
TMPDIR_CREATED=""

usage() {
  cat <<'EOF'
ml-bbrv3 installer

Usage:
  bash install.sh
  bash install.sh [command] [options]

Commands:
  no command                 Show the interactive menu.
  --latest                  Install or update to the newest matching BBR v3 kernel.
  --install-version TAG     Install a specific upstream release tag.
  --list-versions           List upstream releases for the current CPU architecture.
  --status                  Show BBR and qdisc status.
  --enable QDISC            Enable bbr with fq, fq_pie, or cake.
  --uninstall               Remove joeyblog BBR kernel packages.
  --menu                    Show the interactive menu.
  --help                    Show this help.

Options:
  --dry-run                 Print privileged or destructive commands without running them.
  --yes                     Do not prompt before install, uninstall, or persistent sysctl write.
  --force-non-grub          Allow install when update-grub is missing.
  --require-checksums       Require upstream SHA256 checksum assets.
  --repo OWNER/REPO         Override upstream release repository.
  --sysctl-file PATH        Override persistent sysctl config path.

Examples:
  bash install.sh
  bash install.sh --latest --yes
  bash install.sh --latest --dry-run
  bash install.sh --install-version x86_64-7.0.5
  bash install.sh --enable fq --yes
EOF
}

log() {
  printf '[ml-bbrv3] %s\n' "$*" >&2
}

warn() {
  printf '[ml-bbrv3] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[ml-bbrv3] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TMPDIR_CREATED" && -d "$TMPDIR_CREATED" ]]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}

trap cleanup EXIT

run_cmd() {
  if ((DRY_RUN)); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

run_privileged() {
  if ((${#SUDO[@]})); then
    run_cmd "${SUDO[@]}" "$@"
  else
    run_cmd "$@"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

init_privilege() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=()
  else
    require_cmd sudo
    SUDO=(sudo)
  fi
}

confirm() {
  local prompt="$1"

  if ((YES || DRY_RUN)); then
    log "$prompt"
    return 0
  fi

  local answer
  printf '%s [y/N]: ' "$prompt"
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

ensure_debian_host() {
  command -v apt-get >/dev/null 2>&1 \
    || die "This installer supports Debian/Ubuntu hosts with apt-get only."
}

ensure_dependencies() {
  local missing=()
  local cmd

  for cmd in curl jq dpkg awk sed sysctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  log "Installing missing dependencies: ${missing[*]}"
  run_privileged apt-get update
  run_privileged apt-get install -y "${missing[@]}"
}

normalize_arch() {
  local raw_arch="$1"

  case "$raw_arch" in
    x86_64 | amd64)
      printf 'x86_64\n'
      ;;
    aarch64 | arm64)
      printf 'arm64\n'
      ;;
    *)
      return 1
      ;;
  esac
}

detect_arch() {
  local raw_arch
  raw_arch="$(uname -m)"
  normalize_arch "$raw_arch" \
    || die "Unsupported CPU architecture: $raw_arch. Supported: x86_64, arm64."
}

deb_arch_for() {
  local arch="$1"

  case "$arch" in
    x86_64)
      printf 'amd64\n'
      ;;
    arm64)
      printf 'arm64\n'
      ;;
    *)
      die "Unsupported normalized architecture: $arch"
      ;;
  esac
}

github_releases_api() {
  printf 'https://api.github.com/repos/%s/releases\n' "$UPSTREAM_REPO"
}

fetch_releases() {
  local api_url
  api_url="$(github_releases_api)"

  curl -fsSL \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    --retry 2 \
    --retry-delay 1 \
    "$api_url"
}

select_latest_tag() {
  local arch="$1"

  jq -r --arg arch "$arch" '
    [.[] | select(.tag_name | test("^" + $arch + "-"; "i"))]
    | sort_by(.published_at)
    | last
    | .tag_name // empty
  '
}

list_version_tags() {
  local arch="$1"

  jq -r --arg arch "$arch" '
    [.[] | select(.tag_name | test("^" + $arch + "-"; "i"))]
    | sort_by(.published_at)
    | reverse
    | .[].tag_name
  '
}

collect_deb_asset_urls() {
  local tag="$1"
  local deb_arch="$2"

  jq -r --arg tag "$tag" --arg deb_arch "$deb_arch" '
    .[]
    | select(.tag_name == $tag)
    | .assets[]
    | select(.name | test("^linux-"))
    | select(.name | test("_" + $deb_arch + "\\.deb$"))
    | select(.name | test("-dbg_") | not)
    | .browser_download_url
  '
}

collect_checksum_urls() {
  local tag="$1"

  jq -r --arg tag "$tag" '
    .[]
    | select(.tag_name == $tag)
    | .assets[]
    | select(.name | test("(^SHA256SUMS$|\\.sha256$|\\.sha256sum$|\\.sha256.txt$)"; "i"))
    | .browser_download_url
  '
}

asset_is_allowed() {
  local url="$1"
  local tag="$2"
  local deb_arch="$3"
  local prefix="https://github.com/${UPSTREAM_REPO}/releases/download/${tag}/"
  local name="${url##*/}"

  [[ "$url" == "$prefix"* ]] || return 1
  [[ "$name" == linux-* ]] || return 1
  [[ "$name" == *.deb ]] || return 1
  [[ "$name" == *"_${deb_arch}.deb" ]] || return 1
  [[ "$name" != *"-dbg_"* ]] || return 1
}

make_temp_dir() {
  TMPDIR_CREATED="$(mktemp -d "${TMPDIR:-/tmp}/ml-bbrv3.XXXXXX")"
  printf '%s\n' "$TMPDIR_CREATED"
}

download_file() {
  local url="$1"
  local output="$2"

  curl -fL \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    --retry 2 \
    --retry-delay 1 \
    --output "$output" \
    "$url"

  [[ -s "$output" ]] || die "Downloaded file is empty: $output"
}

download_release_assets() {
  local tag="$1"
  local arch="$2"
  local releases_json="$3"
  local deb_arch tmpdir checksum_urls asset_urls url name
  local checksum_found=0

  deb_arch="$(deb_arch_for "$arch")"
  tmpdir="$(make_temp_dir)"
  log "Using temporary download directory: $tmpdir"

  checksum_urls="$(printf '%s\n' "$releases_json" | collect_checksum_urls "$tag")"
  if [[ -n "$checksum_urls" ]]; then
    checksum_found=1
    while IFS= read -r url; do
      [[ -n "$url" ]] || continue
      name="${url##*/}"
      log "Downloading checksum file: $name"
      download_file "$url" "$tmpdir/$name"
    done <<<"$checksum_urls"
  elif ((REQUIRE_CHECKSUMS)); then
    die "No upstream checksum asset found for $tag."
  else
    warn "No upstream checksum asset found for $tag; enforcing URL and architecture allowlist only."
  fi

  asset_urls="$(printf '%s\n' "$releases_json" | collect_deb_asset_urls "$tag" "$deb_arch")"
  [[ -n "$asset_urls" ]] || die "No matching .deb assets found for $tag and $deb_arch."

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    asset_is_allowed "$url" "$tag" "$deb_arch" \
      || die "Release asset failed allowlist validation: $url"
    name="${url##*/}"
    log "Downloading package: $name"
    download_file "$url" "$tmpdir/$name"
  done <<<"$asset_urls"

  if ((checksum_found)); then
    require_cmd sha256sum
    log "Verifying available SHA256 checksums."
    (
      cd "$tmpdir"
      find . -maxdepth 1 -type f \( -name 'SHA256SUMS' -o -name '*.sha256' -o -name '*.sha256sum' -o -name '*.sha256.txt' \) -print0 \
        | while IFS= read -r -d '' checksum_file; do
          sha256sum -c "${checksum_file#./}" --ignore-missing
        done
    )
  fi

  printf '%s\n' "$tmpdir"
}

ensure_bootloader_supported() {
  if command -v update-grub >/dev/null 2>&1; then
    return 0
  fi

  if ((FORCE_NON_GRUB)); then
    warn "update-grub is missing; proceeding because --force-non-grub was provided."
    return 0
  fi

  die "update-grub was not found. This script targets GRUB systems. Re-run with --force-non-grub only if you know your bootloader handles Debian kernel packages."
}

update_bootloader() {
  if command -v update-grub >/dev/null 2>&1; then
    log "Updating GRUB."
    run_privileged update-grub
    return 0
  fi

  warn "Skipping bootloader update because update-grub is unavailable."
  return 0
}

installed_joeyblog_packages() {
  dpkg -l \
    | awk '$1 ~ /^ii/ && $2 ~ /^linux-/ && $0 ~ /joeyblog/ { print $2 }'
}

install_packages_from_dir() {
  local package_dir="$1"
  local packages=()
  local package

  shopt -s nullglob
  packages=("$package_dir"/linux-*.deb)
  shopt -u nullglob

  ((${#packages[@]} > 0)) || die "No linux-*.deb packages found in $package_dir."

  log "Packages selected for installation:"
  for package in "${packages[@]}"; do
    printf '  - %s\n' "${package##*/}"
  done

  confirm "Install these packages now?" || die "Installation cancelled."

  ensure_bootloader_supported
  run_privileged dpkg -i "${packages[@]}"
  update_bootloader

  log "Kernel packages installed. Reboot into the new kernel when ready."
}

install_tag() {
  local tag="$1"
  local arch releases_json package_dir

  ensure_debian_host
  init_privilege
  ensure_dependencies

  arch="$(detect_arch)"
  [[ "$tag" == "$arch"-* ]] \
    || die "Tag $tag does not match current architecture $arch."

  log "Fetching upstream releases from $UPSTREAM_REPO."
  releases_json="$(fetch_releases)"
  package_dir="$(download_release_assets "$tag" "$arch" "$releases_json")"
  install_packages_from_dir "$package_dir"
}

install_latest() {
  local arch releases_json tag package_dir

  ensure_debian_host
  init_privilege
  ensure_dependencies

  arch="$(detect_arch)"
  log "Fetching upstream releases from $UPSTREAM_REPO."
  releases_json="$(fetch_releases)"
  tag="$(printf '%s\n' "$releases_json" | select_latest_tag "$arch")"
  [[ -n "$tag" ]] || die "No release tag found for architecture $arch."

  log "Latest matching release: $tag"
  package_dir="$(download_release_assets "$tag" "$arch" "$releases_json")"
  install_packages_from_dir "$package_dir"
}

show_versions() {
  local arch releases_json

  ensure_debian_host
  init_privilege
  ensure_dependencies
  arch="$(detect_arch)"
  releases_json="$(fetch_releases)"
  printf '%s\n' "$releases_json" | list_version_tags "$arch"
}

write_sysctl_conf() {
  local algo="$1"
  local qdisc="$2"
  local tmpfile

  tmpfile="$(mktemp "${TMPDIR:-/tmp}/ml-bbrv3-sysctl.XXXXXX")"
  if [[ -r "$SYSCTL_CONF" ]]; then
    sed \
      -e '/^net\.core\.default_qdisc=/d' \
      -e '/^net\.ipv4\.tcp_congestion_control=/d' \
      "$SYSCTL_CONF" >"$tmpfile"
  fi

  {
    printf 'net.core.default_qdisc=%s\n' "$qdisc"
    printf 'net.ipv4.tcp_congestion_control=%s\n' "$algo"
  } >>"$tmpfile"

  run_privileged mkdir -p "$(dirname "$SYSCTL_CONF")"
  run_privileged install -m 0644 "$tmpfile" "$SYSCTL_CONF"
  rm -f "$tmpfile"
}

enable_bbr() {
  local qdisc="$1"

  case "$qdisc" in
    fq | fq_pie | cake)
      ;;
    *)
      die "Unsupported qdisc: $qdisc. Use fq, fq_pie, or cake."
      ;;
  esac

  init_privilege
  require_cmd sysctl

  log "Applying runtime sysctl settings: bbr + $qdisc"
  run_privileged sysctl -w "net.core.default_qdisc=$qdisc"
  run_privileged sysctl -w "net.ipv4.tcp_congestion_control=bbr"

  if confirm "Persist settings to $SYSCTL_CONF?"; then
    write_sysctl_conf "bbr" "$qdisc"
    log "Persistent sysctl settings written to $SYSCTL_CONF."
  else
    warn "Runtime settings were not persisted."
  fi
}

show_status() {
  require_cmd sysctl

  printf 'Kernel: %s\n' "$(uname -r)"
  printf 'Architecture: %s\n' "$(uname -m)"
  printf 'Available TCP congestion controls: %s\n' "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf 'unknown')"
  printf 'Current TCP congestion control: %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf 'unknown')"
  printf 'Current default qdisc: %s\n' "$(sysctl -n net.core.default_qdisc 2>/dev/null || printf 'unknown')"

  if command -v modinfo >/dev/null 2>&1 && modinfo tcp_bbr >/dev/null 2>&1; then
    printf 'tcp_bbr module version: %s\n' "$(modinfo tcp_bbr | awk '/^version:/ { print $2; exit }')"
  else
    printf 'tcp_bbr module info: unavailable or built into the kernel\n'
  fi
}

uninstall_kernel() {
  local packages=()
  local package

  ensure_debian_host
  init_privilege

  while IFS= read -r package; do
    [[ -n "$package" ]] && packages+=("$package")
  done < <(installed_joeyblog_packages)

  if ((${#packages[@]} == 0)); then
    log "No installed joeyblog kernel packages were found."
    return 0
  fi

  log "Packages selected for removal:"
  for package in "${packages[@]}"; do
    printf '  - %s\n' "$package"
  done

  confirm "Remove these packages now?" || die "Uninstall cancelled."

  run_privileged apt-get remove --purge -y "${packages[@]}"
  update_bootloader
  log "Kernel packages removed. Reboot when ready."
}

show_menu() {
  cat <<'EOF'
ml-bbrv3 menu

  1. Install or update BBR v3 (latest)
  2. Install a specific release tag
  3. List release tags for this architecture
  4. Show BBR status
  5. Enable BBR + FQ
  6. Enable BBR + FQ_PIE
  7. Enable BBR + CAKE
  8. Uninstall joeyblog BBR kernel packages
  0. Exit
EOF
}

interactive_menu() {
  local choice tag

  show_menu
  printf 'Enter choice: '
  read -r choice

  case "$choice" in
    1)
      install_latest
      ;;
    2)
      printf 'Enter release tag: '
      read -r tag
      install_tag "$tag"
      ;;
    3)
      show_versions
      ;;
    4)
      show_status
      ;;
    5)
      enable_bbr fq
      ;;
    6)
      enable_bbr fq_pie
      ;;
    7)
      enable_bbr cake
      ;;
    8)
      uninstall_kernel
      ;;
    0)
      exit 0
      ;;
    *)
      die "Invalid menu choice: $choice"
      ;;
  esac
}

set_command() {
  local command="$1"
  local arg="${2:-}"

  if [[ -n "$COMMAND" ]]; then
    die "Only one command can be supplied. Already have $COMMAND, got $command."
  fi

  COMMAND="$command"
  COMMAND_ARG="$arg"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --help | -h)
        usage
        exit 0
        ;;
      --version)
        printf '%s\n' "$SCRIPT_VERSION"
        exit 0
        ;;
      --latest | --install-latest)
        set_command latest
        ;;
      --install-version)
        [[ $# -ge 2 && -n "$2" ]] || die "--install-version requires a tag."
        set_command install-version "$2"
        shift
        ;;
      --list-versions)
        set_command list-versions
        ;;
      --status)
        set_command status
        ;;
      --enable)
        [[ $# -ge 2 && -n "$2" ]] || die "--enable requires fq, fq_pie, or cake."
        set_command enable "$2"
        shift
        ;;
      --uninstall)
        set_command uninstall
        ;;
      --menu)
        set_command menu
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --yes | -y)
        YES=1
        ;;
      --force-non-grub)
        FORCE_NON_GRUB=1
        ;;
      --require-checksums)
        REQUIRE_CHECKSUMS=1
        ;;
      --repo)
        [[ $# -ge 2 && -n "$2" ]] || die "--repo requires OWNER/REPO."
        UPSTREAM_REPO="$2"
        shift
        ;;
      --sysctl-file)
        [[ $# -ge 2 && -n "$2" ]] || die "--sysctl-file requires a path."
        SYSCTL_CONF="$2"
        shift
        ;;
      latest)
        set_command latest
        ;;
      list-versions)
        set_command list-versions
        ;;
      status)
        set_command status
        ;;
      uninstall)
        set_command uninstall
        ;;
      menu)
        set_command menu
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

apply_default_command() {
  if [[ -n "$COMMAND" ]]; then
    return 0
  fi

  COMMAND="menu"
}

main() {
  parse_args "$@"
  apply_default_command

  case "$COMMAND" in
    latest)
      install_latest
      ;;
    install-version)
      install_tag "$COMMAND_ARG"
      ;;
    list-versions)
      show_versions
      ;;
    status)
      show_status
      ;;
    enable)
      enable_bbr "$COMMAND_ARG"
      ;;
    uninstall)
      uninstall_kernel
      ;;
    menu)
      interactive_menu
      ;;
    *)
      die "Internal error: unknown command $COMMAND"
      ;;
  esac
}

if [[ "${ML_BBRV3_TESTING:-0}" != "1" ]]; then
  main "$@"
fi
