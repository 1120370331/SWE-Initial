#!/usr/bin/env sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

config_path="config/mirror_sync.conf"
if [ ! -f "$config_path" ]; then
  printf '%s\n' "mirror-sync: skip (missing $config_path)" >&2
  exit 0
fi

changed_tmp="$(mktemp)"
cleanup() {
  rm -f "$changed_tmp"
}
trap cleanup EXIT INT TERM

git status --porcelain | while IFS= read -r line; do
  [ "${line}" = "" ] && continue
  path="${line#?? }"
  case "$path" in
    *" -> "*)
      path="${path##* -> }"
      ;;
  esac
  printf '%s\n' "$path"
done >"$changed_tmp"

# If nothing changed, exit quietly.
if [ ! -s "$changed_tmp" ]; then
  exit 0
fi

get_mtime() {
  file="$1"
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
    return 0
  fi
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
    return 0
  fi
  printf '0\n'
}

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  line="$(printf '%s' "$raw_line" | sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue

  # shellcheck disable=SC2086
  set -- $line
  [ "$#" -lt 2 ] && continue

  group_changed=0
  for file in "$@"; do
    if grep -Fx -- "$file" "$changed_tmp" >/dev/null 2>&1; then
      group_changed=1
      break
    fi
  done
  [ "$group_changed" -eq 0 ] && continue

  source_file=""
  source_mtime=0
  for file in "$@"; do
    if [ -f "$file" ]; then
      mtime="$(get_mtime "$file")"
      if [ "$mtime" -ge "$source_mtime" ]; then
        source_file="$file"
        source_mtime="$mtime"
      fi
    fi
  done

  if [ -z "$source_file" ]; then
    for file in "$@"; do
      git add -- "$file" >/dev/null 2>&1 || true
    done
    continue
  fi

  for file in "$@"; do
    if [ "$file" != "$source_file" ]; then
      if [ ! -f "$file" ] || ! cmp -s "$source_file" "$file"; then
        mkdir -p "$(dirname "$file")"
        cat "$source_file" >"$file"
      fi
    fi
    git add -- "$file"
  done

done <"$config_path"
