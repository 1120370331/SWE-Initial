#!/usr/bin/env sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$repo_root" ]; then
  printf '%s\n' "install-hooks: unable to locate git repository" >&2
  exit 1
fi

git config core.hooksPath "$repo_root/.githooks"

printf '%s\n' "install-hooks: git hooks path set to .githooks"
printf '%s\n' "install-hooks: future hooks placed in .githooks/ will activate automatically"
