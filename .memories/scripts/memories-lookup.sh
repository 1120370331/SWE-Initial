#!/usr/bin/env bash
# Quick lookup helper for the .memories directory.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
modules_dir="$(cd "$script_dir/.." && pwd)/modules"

usage() {
  cat <<'EOF'
Usage: sh .memories/scripts/memories-lookup.sh [--list-modules] <keyword> [keyword...]

Options:
  --list-modules   List available memory modules and exit.
  --help           Show this help message.

Notes:
  - Searches all markdown files under .memories/modules.
  - Requires at least one keyword unless --list-modules is used.
EOF
}

list_modules() {
  if [ ! -d "$modules_dir" ]; then
    echo "Memories modules directory not found: $modules_dir" >&2
    exit 2
  fi
  find "$modules_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

search_memories() {
  if [ $# -eq 0 ]; then
    echo "Provide at least one keyword or use --list-modules." >&2
    usage
    exit 2
  fi

  if command -v rg >/dev/null 2>&1; then
    args=()
    for keyword in "$@"; do
      args+=("-e" "$keyword")
    done
    rg --color=always --line-number --ignore-case --fixed-strings "${args[@]}" "$modules_dir" || {
      echo "No matches." >&2
      exit 1
    }
    return
  fi

  if command -v grep >/dev/null 2>&1; then
    args=()
    for keyword in "$@"; do
      args+=("-e" "$keyword")
    done
    grep -RIn --color=always -F "${args[@]}" "$modules_dir" || {
      echo "No matches." >&2
      exit 1
    }
    return
  fi

  echo "Neither rg nor grep is available. Install one of them to use this script." >&2
  exit 2
}

if [ $# -eq 0 ]; then
  usage
  exit 2
fi

case "$1" in
  --help)
    usage
    exit 0
    ;;
  --list-modules)
    list_modules
    exit 0
    ;;
esac

search_memories "$@"
