#!/usr/bin/env bash
#
# Runs the busted/plenary spec suite headlessly. Wraps
# scripts/minimal_init.lua -- see that file for what it does and why.
#
#   scripts/test.sh                 every spec under lua/github_stats/tests/
#   scripts/test.sh path/to_spec.lua   a single spec file
#
# Env vars (both optional -- see scripts/minimal_init.lua's own fallbacks):
#   LIB_NVIM_DIR      path to a lib.nvim checkout
#   PLENARY_DIR       path to a plenary.nvim checkout

set -euo pipefail

cd "$(dirname "$0")/.."

command -v nvim >/dev/null 2>&1 || {
  printf '\033[31m%s\033[0m\n' "nvim is not on PATH." >&2
  exit 1
}

target="${1:-lua/github_stats/tests/}"

if [[ "$target" == *.lua ]]; then
  cmd="PlenaryBustedFile $target"
else
  cmd="PlenaryBustedDirectory $target { minimal_init = 'scripts/minimal_init.lua', sequential = true }"
fi

exec nvim --clean --headless -u scripts/minimal_init.lua -c "$cmd"
