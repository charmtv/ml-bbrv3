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
ml-bbrv3 安装器

用法：
  bash install.sh
  bash install.sh [命令] [选项]

命令：
  不带命令                  显示交互菜单。
  --latest                  安装或更新到当前架构匹配的最新版 BBR v3 内核。
  --install-version 标签    安装指定的上游发布标签。
  --list-versions           列出当前 CPU 架构可用的上游发布版本。
  --status                  显示 BBR 和队列算法状态。
  --enable 队列算法         启用 bbr，并使用 fq、fq_pie 或 cake。
  --uninstall               移除 joeyblog BBR 内核包。
  --menu                    显示交互菜单。
  --help                    显示此帮助。

选项：
  --dry-run                 只打印需要提权或有破坏性的命令，不实际执行。
  --yes                     安装、卸载或写入持久化 sysctl 配置前不再询问。
  --force-non-grub          在缺少 update-grub 时仍允许安装。
  --require-checksums       要求上游提供 SHA256 校验和资产。
  --repo 所有者/仓库        覆盖上游发布仓库。
  --sysctl-file 路径        覆盖持久化 sysctl 配置文件路径。

示例：
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
  printf '[ml-bbrv3] 警告：%s\n' "$*" >&2
}

die() {
  printf '[ml-bbrv3] 错误：%s\n' "$*" >&2
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
    printf '[预演]'
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
  command -v "$cmd" >/dev/null 2>&1 || die "缺少必要命令：$cmd"
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
    || die "此安装器只支持带 apt-get 的 Debian/Ubuntu 主机。"
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

  log "正在安装缺失依赖：${missing[*]}"
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
    || die "不支持的 CPU 架构：$raw_arch。支持：x86_64、arm64。"
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
      die "不支持的标准化架构：$arch"
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

  [[ -s "$output" ]] || die "下载文件为空：$output"
}

download_release_assets() {
  local tag="$1"
  local arch="$2"
  local releases_json="$3"
  local deb_arch tmpdir checksum_urls asset_urls url name
  local checksum_found=0

  deb_arch="$(deb_arch_for "$arch")"
  tmpdir="$(make_temp_dir)"
  log "使用临时下载目录：$tmpdir"

  checksum_urls="$(printf '%s\n' "$releases_json" | collect_checksum_urls "$tag")"
  if [[ -n "$checksum_urls" ]]; then
    checksum_found=1
    while IFS= read -r url; do
      [[ -n "$url" ]] || continue
      name="${url##*/}"
      log "正在下载校验和文件：$name"
      download_file "$url" "$tmpdir/$name"
    done <<<"$checksum_urls"
  elif ((REQUIRE_CHECKSUMS)); then
    die "未找到 $tag 的上游校验和资产。"
  else
    warn "未找到 $tag 的上游校验和资产；仅执行 URL 和架构白名单校验。"
  fi

  asset_urls="$(printf '%s\n' "$releases_json" | collect_deb_asset_urls "$tag" "$deb_arch")"
  [[ -n "$asset_urls" ]] || die "未找到匹配 $tag 和 $deb_arch 的 .deb 资产。"

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    asset_is_allowed "$url" "$tag" "$deb_arch" \
      || die "发布资产未通过白名单校验：$url"
    name="${url##*/}"
    log "正在下载软件包：$name"
    download_file "$url" "$tmpdir/$name"
  done <<<"$asset_urls"

  if ((checksum_found)); then
    require_cmd sha256sum
    log "正在校验可用的 SHA256 校验和。"
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
    warn "缺少 update-grub；已提供 --force-non-grub，继续执行。"
    return 0
  fi

  die "未找到 update-grub。此脚本面向 GRUB 系统。只有确认你的引导程序会处理 Debian 内核包时，才使用 --force-non-grub 重新运行。"
}

update_bootloader() {
  if command -v update-grub >/dev/null 2>&1; then
    log "正在更新 GRUB。"
    run_privileged update-grub
    return 0
  fi

  warn "由于 update-grub 不可用，跳过引导更新。"
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

  ((${#packages[@]} > 0)) || die "在 $package_dir 中未找到 linux-*.deb 软件包。"

  log "准备安装的软件包："
  for package in "${packages[@]}"; do
    printf '  - %s\n' "${package##*/}"
  done

  confirm "现在安装这些软件包吗？" || die "安装已取消。"

  ensure_bootloader_supported
  run_privileged dpkg -i "${packages[@]}"
  update_bootloader

  log "内核包已安装。准备好后请重启进入新内核。"
}

install_tag() {
  local tag="$1"
  local arch releases_json package_dir

  ensure_debian_host
  init_privilege
  ensure_dependencies

  arch="$(detect_arch)"
  [[ "$tag" == "$arch"-* ]] \
    || die "标签 $tag 与当前架构 $arch 不匹配。"

  log "正在从 $UPSTREAM_REPO 获取上游发布信息。"
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
  log "正在从 $UPSTREAM_REPO 获取上游发布信息。"
  releases_json="$(fetch_releases)"
  tag="$(printf '%s\n' "$releases_json" | select_latest_tag "$arch")"
  [[ -n "$tag" ]] || die "未找到架构 $arch 对应的发布标签。"

  log "匹配的最新发布版本：$tag"
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
    fq | fq_pie | cake) ;;
    *)
      die "不支持的队列算法：$qdisc。请使用 fq、fq_pie 或 cake。"
      ;;
  esac

  init_privilege
  require_cmd sysctl

  log "正在应用运行时 sysctl 设置：bbr + $qdisc"
  run_privileged sysctl -w "net.core.default_qdisc=$qdisc"
  run_privileged sysctl -w "net.ipv4.tcp_congestion_control=bbr"

  if confirm "将设置持久化到 $SYSCTL_CONF 吗？"; then
    write_sysctl_conf "bbr" "$qdisc"
    log "持久化 sysctl 设置已写入 $SYSCTL_CONF。"
  else
    warn "运行时设置未持久化。"
  fi
}

show_status() {
  require_cmd sysctl

  printf '当前内核：%s\n' "$(uname -r)"
  printf '当前架构：%s\n' "$(uname -m)"
  printf '可用 TCP 拥塞控制算法：%s\n' "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf '未知')"
  printf '当前 TCP 拥塞控制算法：%s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')"
  printf '当前默认队列算法：%s\n' "$(sysctl -n net.core.default_qdisc 2>/dev/null || printf '未知')"

  if command -v modinfo >/dev/null 2>&1 && modinfo tcp_bbr >/dev/null 2>&1; then
    printf 'tcp_bbr 模块版本：%s\n' "$(modinfo tcp_bbr | awk '/^version:/ { print $2; exit }')"
  else
    printf 'tcp_bbr 模块信息：不可用，或已内置到内核中\n'
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
    log "未找到已安装的 joeyblog 内核包。"
    return 0
  fi

  log "准备移除的软件包："
  for package in "${packages[@]}"; do
    printf '  - %s\n' "$package"
  done

  confirm "现在移除这些软件包吗？" || die "卸载已取消。"

  run_privileged apt-get remove --purge -y "${packages[@]}"
  update_bootloader
  log "内核包已移除。准备好后请重启。"
}

show_menu() {
  cat <<'EOF'
ml-bbrv3 菜单

  1. 安装或更新 BBR v3（最新版）
  2. 安装指定发布标签
  3. 列出当前架构可用发布标签
  4. 查看 BBR 状态
  5. 启用 BBR + FQ
  6. 启用 BBR + FQ_PIE
  7. 启用 BBR + CAKE
  8. 卸载 joeyblog BBR 内核包
  0. 退出
EOF
}

interactive_menu() {
  local choice tag

  show_menu
  printf '请输入选项：'
  read -r choice

  case "$choice" in
    1)
      install_latest
      ;;
    2)
      printf '请输入发布标签：'
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
      die "无效菜单选项：$choice"
      ;;
  esac
}

set_command() {
  local command="$1"
  local arg="${2:-}"

  if [[ -n "$COMMAND" ]]; then
    die "只能提供一个命令。当前已有 $COMMAND，又收到 $command。"
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
        [[ $# -ge 2 && -n "$2" ]] || die "--install-version 需要一个标签。"
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
        [[ $# -ge 2 && -n "$2" ]] || die "--enable 需要 fq、fq_pie 或 cake。"
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
        [[ $# -ge 2 && -n "$2" ]] || die "--repo 需要 OWNER/REPO。"
        UPSTREAM_REPO="$2"
        shift
        ;;
      --sysctl-file)
        [[ $# -ge 2 && -n "$2" ]] || die "--sysctl-file 需要一个路径。"
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
        die "未知参数：$1"
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
      die "内部错误：未知命令 $COMMAND"
      ;;
  esac
}

if [[ "${ML_BBRV3_TESTING:-0}" != "1" ]]; then
  main "$@"
fi
