#!/usr/bin/env bash
# Tests the stop-in time of a run (ap-run stop-in, stop-left, stop-wait, stop-clear) in a
# throwaway repository: stop-left says the minutes left, then up; stop-wait says up at the time,
# again after its longest wait, cancelled when the stop was cleared; stop-in takes only a run that
# was started, and only a whole number of minutes above 0 (08 is 8).
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "run-stop-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b develop "$M" || exit 1
run() { (cd "$M" && ap-run "$@" >"$T/out" 2>"$T/err"); }

# A run, as ap-run start makes one. Where the run is in its time comes from a stop file written
# here with times around now, so no case waits for the clock (a slow start of a process would
# move it).
CD=$(git -C "$M" rev-parse --path-format=absolute --git-common-dir)/ap-autopilot
S=1-test
mkdir -p "$CD" && date '+%F %T' >"$CD/run-$S"
left() { # from, to (seconds from now): what stop-left says
  echo "$((EPOCHSECONDS + $1)) $((EPOCHSECONDS + $2))" >"$CD/stop-$S"
  run stop-left "$S"; cat "$T/out"
}
run stop-left "$S"; [ "$(<"$T/out")" = none ] || fail "stop-left with no stop-in: '$(<"$T/out")'"
[ "$(left -60 600)" = "10 of 11" ] || fail "stop-left 1 of 11 minutes in: '$(<"$T/out")'"
[ "$(left -600 -1)" = up ] || fail "stop-left after the time: '$(<"$T/out")'"
run stop-wait "$S"; [ "$(<"$T/out")" = up ] || fail "stop-wait after the time: '$(<"$T/out")'"
for bad in 0 00 x; do run stop-in "$S" "$bad" && fail "stop-in took '$bad' minutes"; done
run stop-in no-such-run 5 && fail "stop-in took a run that was never started"
run stop-in "$S" 08 || fail "stop-in 08 failed (read as octal?): $(cat "$T/err")"
run stop-left "$S"; [ "$(<"$T/out")" = "8 of 8" ] || fail "stop-in 08: '$(<"$T/out")'"
AP_RUN_WAIT_MAX=0 run stop-wait "$S"; [ "$(<"$T/out")" = again ] || fail "stop-wait after its longest wait: '$(<"$T/out")'"
run stop-clear "$S" && run stop-wait "$S"; [ "$(<"$T/out")" = cancelled ] || fail "stop-wait after stop-clear: '$(<"$T/out")'"
run nothing && fail "an unknown command passed"
grep -q "usage: ap-run" "$T/err" || fail "the usage does not name ap-run: $(cat "$T/err")"

[ $FAILED = 0 ] && echo "ap-run stop-*: ok"
exit $FAILED
