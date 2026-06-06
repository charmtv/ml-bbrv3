#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
用法：
  bash scripts/generate-checksums.sh /path/to/release-assets

为目标目录中的 linux-*.deb 文件创建或替换 SHA256SUMS。
EOF
}

die() {
  printf '[checksums] 错误：%s\n' "$*" >&2
  exit 1
}

main() {
  if [[ $# -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    [[ $# -eq 1 ]] && exit 0
    exit 1
  fi

  command -v sha256sum >/dev/null 2>&1 || die "缺少必要命令：sha256sum。"

  local target_dir="$1"
  [[ -d "$target_dir" ]] || die "目标目录不存在：$target_dir"

  local resolved_dir
  resolved_dir="$(cd "$target_dir" && pwd -P)"
  [[ -n "$resolved_dir" && "$resolved_dir" != "/" ]] \
    || die "拒绝为不安全目录写入校验和：$resolved_dir"

  shopt -s nullglob
  local packages=("$resolved_dir"/linux-*.deb)
  shopt -u nullglob

  ((${#packages[@]} > 0)) || die "在 $resolved_dir 中未找到 linux-*.deb 文件。"

  (
    cd "$resolved_dir"
    sha256sum linux-*.deb >SHA256SUMS
  )

  printf '已写入 %s\n' "$resolved_dir/SHA256SUMS"
}

main "$@"
