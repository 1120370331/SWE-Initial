#!/usr/bin/env bash
# Quick lookup helper for the .memories directory.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
modules_dir="$(cd "$script_dir/.." && pwd)/modules"

usage() {
  cat <<'EOF'
Usage: sh .memories/scripts/memories-lookup.sh [--list-modules] <module> [keyword...]

Options:
  --list-modules   List available memory modules and exit.
  --help           Show this help message.

Notes:
  - Searches markdown files under a specific module in .memories/modules.
  - Module name is required; use --list-modules to discover available options.
  - Omit keywords to list markdown files for the chosen module.
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
  local module=$1
  local target_dir=$2
  shift 2
  local prefix="${modules_dir%/}/"

  if [ $# -eq 0 ]; then
    local found=false
    local rel
    while IFS= read -r path; do
      found=true
      rel="${path#$prefix}"
      printf '%s\n' "$rel"
    done < <(find "$target_dir" -type f -name "*.md" | sort)
    if [ "$found" = false ]; then
      echo "No markdown files found under module $module."
    fi
    return 0
  fi

  if command -v rg >/dev/null 2>&1; then
    local -a args=()
    for keyword in "$@"; do
      args+=("-e" "$keyword")
    done
    rg --color=always --line-number --ignore-case --fixed-strings "${args[@]}" "$target_dir" || {
      echo "No matches." >&2
      exit 1
    }
    return
  fi

  if command -v grep >/dev/null 2>&1; then
    local -a args=()
    for keyword in "$@"; do
      args+=("-e" "$keyword")
    done
    grep -RIn --color=always -F "${args[@]}" "$target_dir" || {
      echo "No matches." >&2
      exit 1
    }
    return
  fi

  echo "Neither rg nor grep is available. Install one of them to use this script." >&2
  exit 2
}

if [ $# -eq 0 ]; then
  echo "Missing required module argument. Use --list-modules to inspect available modules." >&2
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

module=$1
shift
target_dir="$modules_dir/$module"

if [ ! -d "$target_dir" ]; then
  echo "Memory module not found: $module" >&2
  exit 2
fi

search_memories "$module" "$target_dir" "$@"
