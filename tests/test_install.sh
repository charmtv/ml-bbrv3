#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT_DIR"

export ML_BBRV3_TESTING=1
# shellcheck source=../install.sh
source "$ROOT_DIR/install.sh"

pass() {
  printf 'ok - %s\n' "$*"
}

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$expected" == "$actual" ]] ||
    fail "$label: expected '$expected', got '$actual'"
  pass "$label"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  [[ "$haystack" == *"$needle"* ]] ||
    fail "$label: missing '$needle'"
  pass "$label"
}

reset_cli_state() {
  DRY_RUN=0
  YES=0
  FORCE_NON_GRUB=0
  REQUIRE_CHECKSUMS=0
  COMMAND=""
  COMMAND_ARG=""
  UPSTREAM_REPO="$DEFAULT_UPSTREAM_REPO"
  SYSCTL_CONF="/etc/sysctl.d/99-ml-bbrv3.conf"
  SUDO=()
  TMPDIR_CREATED=""
}

test_help() {
  local output
  output="$(ML_BBRV3_TESTING=0 bash "$ROOT_DIR/install.sh" --help)"
  assert_contains "$output" "Usage:" "help includes usage"
  assert_contains "$output" "--dry-run" "help includes dry-run"
  assert_contains "$output" "Show the interactive menu" "help documents menu default"
}

test_default_command() {
  reset_cli_state
  parse_args
  apply_default_command
  assert_eq "menu" "$COMMAND" "no args defaults to menu"
  assert_eq "0" "$YES" "no args keeps prompts"

  reset_cli_state
  parse_args --dry-run
  apply_default_command
  assert_eq "menu" "$COMMAND" "dry-run defaults to menu"
  assert_eq "1" "$DRY_RUN" "dry-run option is preserved"
  assert_eq "0" "$YES" "dry-run keeps prompts"

  reset_cli_state
  parse_args --latest --yes
  apply_default_command
  assert_eq "latest" "$COMMAND" "latest command stays non-menu"
  assert_eq "1" "$YES" "latest command can run non-interactively"

  reset_cli_state
  parse_args --menu
  apply_default_command
  assert_eq "menu" "$COMMAND" "menu command bypasses default install"
  assert_eq "0" "$YES" "menu command keeps prompts"
}

test_arch_mapping() {
  assert_eq "x86_64" "$(normalize_arch x86_64)" "x86_64 maps to x86_64"
  assert_eq "x86_64" "$(normalize_arch amd64)" "amd64 maps to x86_64"
  assert_eq "arm64" "$(normalize_arch aarch64)" "aarch64 maps to arm64"
  assert_eq "arm64" "$(normalize_arch arm64)" "arm64 maps to arm64"

  if normalize_arch riscv64 >/dev/null 2>&1; then
    fail "unsupported arch should fail"
  fi
  pass "unsupported arch fails"

  assert_eq "amd64" "$(deb_arch_for x86_64)" "x86_64 deb arch"
  assert_eq "arm64" "$(deb_arch_for arm64)" "arm64 deb arch"
}

release_fixture() {
  cat <<'JSON'
[
  {
    "tag_name": "x86_64-7.0.3",
    "published_at": "2026-05-04T18:07:13Z",
    "assets": [
      {
        "name": "linux-image-7.0.3-joeyblog-bbrv3_7.0.3-1_amd64.deb",
        "browser_download_url": "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.3/linux-image-7.0.3-joeyblog-bbrv3_7.0.3-1_amd64.deb"
      }
    ]
  },
  {
    "tag_name": "x86_64-7.0.5",
    "published_at": "2026-05-08T12:29:14Z",
    "assets": [
      {
        "name": "linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb",
        "browser_download_url": "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb"
      },
      {
        "name": "linux-image-7.0.5-joeyblog-bbrv3-dbg_7.0.5-1_amd64.deb",
        "browser_download_url": "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3-dbg_7.0.5-1_amd64.deb"
      },
      {
        "name": "SHA256SUMS",
        "browser_download_url": "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/SHA256SUMS"
      }
    ]
  },
  {
    "tag_name": "arm64-7.0.3",
    "published_at": "2026-05-04T16:33:05Z",
    "assets": [
      {
        "name": "linux-image-7.0.3-joeyblog-bbrv3_7.0.3-1_arm64.deb",
        "browser_download_url": "https://github.com/byJoey/Actions-bbr-v3/releases/download/arm64-7.0.3/linux-image-7.0.3-joeyblog-bbrv3_7.0.3-1_arm64.deb"
      }
    ]
  }
]
JSON
}

test_release_selection() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'skip - jq not installed; release JSON tests skipped\n'
    return 0
  fi

  local fixture latest versions assets checksums
  fixture="$(release_fixture)"

  latest="$(printf '%s\n' "$fixture" | select_latest_tag x86_64)"
  assert_eq "x86_64-7.0.5" "$latest" "latest x86_64 tag selected"

  versions="$(printf '%s\n' "$fixture" | list_version_tags x86_64)"
  assert_contains "$versions" "x86_64-7.0.5" "version list includes latest"
  assert_contains "$versions" "x86_64-7.0.3" "version list includes older"

  assets="$(printf '%s\n' "$fixture" | collect_deb_asset_urls x86_64-7.0.5 amd64)"
  assert_contains "$assets" "linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb" "asset list includes non-debug package"
  if [[ "$assets" == *"-dbg_"* ]]; then
    fail "asset list should exclude debug packages"
  fi
  pass "asset list excludes debug packages"

  checksums="$(printf '%s\n' "$fixture" | collect_checksum_urls x86_64-7.0.5)"
  assert_contains "$checksums" "SHA256SUMS" "checksum asset is discovered"
}

test_asset_allowlist() {
  UPSTREAM_REPO="byJoey/Actions-bbr-v3"

  asset_is_allowed \
    "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb" \
    "x86_64-7.0.5" \
    "amd64" ||
    fail "valid asset should pass allowlist"
  pass "valid asset passes allowlist"

  if asset_is_allowed \
    "https://github.com/example/bad/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb" \
    "x86_64-7.0.5" \
    "amd64"; then
    fail "wrong repository should fail allowlist"
  fi
  pass "wrong repository fails allowlist"

  if asset_is_allowed \
    "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3-dbg_7.0.5-1_amd64.deb" \
    "x86_64-7.0.5" \
    "amd64"; then
    fail "debug package should fail allowlist"
  fi
  pass "debug package fails allowlist"
}

test_help
test_default_command
test_arch_mapping
test_release_selection
test_asset_allowlist
