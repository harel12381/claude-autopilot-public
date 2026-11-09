#!/usr/bin/env bash
# Runs every test of the scripts (tests/*-test.sh), one after another, and stops at the first
# that fails, with its exit code.
#
#   bash tests/run.sh             # every test
#   bash tests/run.sh notify run  # only tests/notify-test.sh and tests/run-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ $# -gt 0 ]; then
  tests=(); for n in "$@"; do tests+=("$HERE/$n-test.sh"); done
else
  tests=("$HERE"/*-test.sh)
fi
for t in "${tests[@]}"; do
  [ -f "$t" ] || { echo "tests/run.sh: no test $t" >&2; exit 2; }
  echo "== ${t##*/}"
  bash "$t" || { rc=$?; echo "tests/run.sh: ${t##*/} failed (exit $rc)" >&2; exit $rc; }
done
echo "tests/run.sh: all ${#tests[@]} tests passed"
