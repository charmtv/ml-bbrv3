#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage:
  bash scripts/generate-checksums.sh /path/to/release-assets

Creates or replaces SHA256SUMS in the target directory for linux-*.deb files.
EOF
}

die() {
  printf '[checksums] ERROR: %s\n' "$*" >&2
  exit 1
}

main() {
  if [[ $# -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    [[ $# -eq 1 ]] && exit 0
    exit 1
  fi

  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required."

  local target_dir="$1"
  [[ -d "$target_dir" ]] || die "Target directory does not exist: $target_dir"

  local resolved_dir
  resolved_dir="$(cd "$target_dir" && pwd -P)"
  [[ -n "$resolved_dir" && "$resolved_dir" != "/" ]] \
    || die "Refusing to write checksums for an unsafe directory: $resolved_dir"

  shopt -s nullglob
  local packages=("$resolved_dir"/linux-*.deb)
  shopt -u nullglob

  ((${#packages[@]} > 0)) || die "No linux-*.deb files found in $resolved_dir."

  (
    cd "$resolved_dir"
    sha256sum linux-*.deb >SHA256SUMS
  )

  printf 'Wrote %s\n' "$resolved_dir/SHA256SUMS"
}

main "$@"
