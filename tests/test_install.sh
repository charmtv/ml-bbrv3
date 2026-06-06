#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT_DIR"

export ML_BBRV3_TESTING=1
# shellcheck source=install.sh
source "$ROOT_DIR/install.sh"

pass() {
  printf '通过 - %s\n' "$*"
}

fail() {
  printf '失败 - %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$expected" == "$actual" ]] \
    || fail "$label：期望 '$expected'，实际 '$actual'"
  pass "$label"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  [[ "$haystack" == *"$needle"* ]] \
    || fail "$label：缺少 '$needle'"
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
  assert_contains "$output" "用法：" "帮助包含用法"
  assert_contains "$output" "--dry-run" "帮助包含 dry-run"
  assert_contains "$output" "显示交互菜单" "帮助说明默认进入菜单"
}

test_default_command() {
  reset_cli_state
  parse_args
  apply_default_command
  assert_eq "menu" "$COMMAND" "无参数默认进入菜单"
  assert_eq "0" "$YES" "无参数保留确认提示"

  reset_cli_state
  parse_args --dry-run
  apply_default_command
  assert_eq "menu" "$COMMAND" "dry-run 默认进入菜单"
  assert_eq "1" "$DRY_RUN" "保留 dry-run 选项"
  assert_eq "0" "$YES" "dry-run 保留确认提示"

  reset_cli_state
  parse_args --latest --yes
  apply_default_command
  assert_eq "latest" "$COMMAND" "latest 命令不进入菜单"
  assert_eq "1" "$YES" "latest 命令可无人值守执行"

  reset_cli_state
  parse_args --menu
  apply_default_command
  assert_eq "menu" "$COMMAND" "menu 命令保持菜单入口"
  assert_eq "0" "$YES" "menu 命令保留确认提示"
}

test_arch_mapping() {
  assert_eq "x86_64" "$(normalize_arch x86_64)" "x86_64 映射到 x86_64"
  assert_eq "x86_64" "$(normalize_arch amd64)" "amd64 映射到 x86_64"
  assert_eq "arm64" "$(normalize_arch aarch64)" "aarch64 映射到 arm64"
  assert_eq "arm64" "$(normalize_arch arm64)" "arm64 映射到 arm64"

  if normalize_arch riscv64 >/dev/null 2>&1; then
    fail "不支持的架构应失败"
  fi
  pass "不支持的架构会失败"

  assert_eq "amd64" "$(deb_arch_for x86_64)" "x86_64 deb 架构"
  assert_eq "arm64" "$(deb_arch_for arm64)" "arm64 deb 架构"
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
    printf '跳过 - 未安装 jq，跳过发布 JSON 测试\n'
    return 0
  fi

  local fixture latest versions assets checksums
  fixture="$(release_fixture)"

  latest="$(printf '%s\n' "$fixture" | select_latest_tag x86_64)"
  assert_eq "x86_64-7.0.5" "$latest" "选中最新 x86_64 标签"

  versions="$(printf '%s\n' "$fixture" | list_version_tags x86_64)"
  assert_contains "$versions" "x86_64-7.0.5" "版本列表包含最新版"
  assert_contains "$versions" "x86_64-7.0.3" "版本列表包含旧版本"

  assets="$(printf '%s\n' "$fixture" | collect_deb_asset_urls x86_64-7.0.5 amd64)"
  assert_contains "$assets" "linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb" "资产列表包含非调试包"
  if [[ "$assets" == *"-dbg_"* ]]; then
    fail "资产列表应排除调试包"
  fi
  pass "资产列表已排除调试包"

  checksums="$(printf '%s\n' "$fixture" | collect_checksum_urls x86_64-7.0.5)"
  assert_contains "$checksums" "SHA256SUMS" "发现校验和资产"
}

test_asset_allowlist() {
  UPSTREAM_REPO="byJoey/Actions-bbr-v3"

  asset_is_allowed \
    "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb" \
    "x86_64-7.0.5" \
    "amd64" \
    || fail "有效资产应通过白名单"
  pass "有效资产通过白名单"

  if asset_is_allowed \
    "https://github.com/example/bad/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3_7.0.5-1_amd64.deb" \
    "x86_64-7.0.5" \
    "amd64"; then
    fail "错误仓库应无法通过白名单"
  fi
  pass "错误仓库无法通过白名单"

  if asset_is_allowed \
    "https://github.com/byJoey/Actions-bbr-v3/releases/download/x86_64-7.0.5/linux-image-7.0.5-joeyblog-bbrv3-dbg_7.0.5-1_amd64.deb" \
    "x86_64-7.0.5" \
    "amd64"; then
    fail "调试包应无法通过白名单"
  fi
  pass "调试包无法通过白名单"
}

test_help
test_default_command
test_arch_mapping
test_release_selection
test_asset_allowlist
