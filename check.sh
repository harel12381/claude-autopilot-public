#!/usr/bin/env bash
# The repository's own check: every script and test is valid bash (bash -n), shellcheck finds
# nothing (when it is installed), and every test passes (tests/run.sh). Exit 0: all passed.
#
#   bash check.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2
files=(check.sh plugins/ap/bin/* plugins/ap/lib/*.sh tests/*.sh)

for f in "${files[@]}"; do
  bash -n "$f" || { echo "check.sh: $f is not valid bash" >&2; exit 1; }
done
echo "check.sh: bash -n: ok (${#files[@]} files)"

if command -v shellcheck >/dev/null; then
  shellcheck -x -s bash "${files[@]}" || { echo "check.sh: shellcheck found problems" >&2; exit 1; }
  echo "check.sh: shellcheck: ok"
else
  echo "check.sh: shellcheck is not installed: skipped"
fi

bash tests/run.sh || exit
echo "check.sh: passed"
