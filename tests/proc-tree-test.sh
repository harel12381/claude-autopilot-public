#!/usr/bin/env bash
# Tests pid_runs (lib/proc-tree.sh), which tells whether a process still runs:
#   - true for a process that runs, false for one that is gone;
#   - false for a zombie (a process that ended, whose parent never reads its exit code, as in a
#     container whose process 1 does not reap orphans), which `kill -0` still finds;
#   - a lock (lib/dirlock.sh) whose owner is a zombie is taken over at once.
# Git Bash on Windows keeps no such zombie: the zombie cases are skipped there.
#
#   bash tests/proc-tree-test.sh  # exit 0 when every case passed
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=plugins/ap/lib/dirlock.sh
source "$ROOT/plugins/ap/lib/dirlock.sh"
T=$(mktemp -d)
parent=
trap '[ -z "$parent" ] || kill "$parent" 2>/dev/null; rm -rf "$T"' EXIT

fails=0
fail() { echo "proc-tree-test: $*"; fails=$((fails + 1)); }

sleep 60 & live=$!
pid_runs "$live" || fail "a process that runs does not run"
kill "$live"; wait "$live" 2>/dev/null
pid_runs "$live" && fail "a process that is gone still runs"

if [ -r /proc/self/winpid ]; then
  echo "proc-tree-test: Git Bash keeps no zombies: the zombie cases are skipped"
else
  # The parent starts a child that ends in a second, and becomes a program that never reaps it.
  bash -c 'sleep 1 & echo $! >"$1"; exec sleep 60' _ "$T/zombie" & parent=$!
  wait_until 10 test -s "$T/zombie" || fail "the zombie's parent did not start"
  zombie=$(cat "$T/zombie")
  wait_until 10 eval '! pid_runs "$zombie"' || fail "a zombie still runs"
  if kill -0 "$zombie" 2>/dev/null; then
    mkdir "$T/lock" && echo "$zombie the run that ended" >"$T/lock/owner"
    out=$(dirlock_try "$T/lock" "the next run" 0) || fail "a lock whose owner is a zombie was not taken over"
    grep -q "^Took over lock" <<<"$out" || fail "the takeover was not said: $out"
  else
    fail "the child was reaped: no zombie was made"
  fi
fi

[ "$fails" = 0 ] || exit 1
echo "proc-tree-test: passed"
