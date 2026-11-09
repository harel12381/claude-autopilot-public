#!/usr/bin/env bash
# Tests what ap-check does when a step fails or hangs, in a throwaway repository
# (tests/check-fake.sh):
#   - a failing part fails the run, and prints the end of its log; the other parts still pass;
#   - the retry: a failure whose log matches `when` runs the `run` command instead, and its result
#     counts; a failure that does not match runs once; a retry with "heavy": true runs under the
#     heavy lock;
#   - a step that hangs is stopped after its time limit, with what runs under it, and frees the
#     locks;
#   - a run whose shell is stopped stops too, with what runs under it, and frees its lock; its
#     steps know the run (AP_CHECK_RUN);
#   - a run stopped with TERM stops its steps before it frees the heavy lock.
#
#   bash tests/check-failures-test.sh  # exit 0 when every case passed (a minute or two)
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/check-fake.sh
source "$(dirname "$0")/check-fake.sh"

# A failing part: the end of its log, and the others pass.
begin; FAKE_FAIL=a/light FAKE_SAY="the words of the failure" check a --force a b; wait
[ "$(rc a)" = 1 ] || fail "a failing part did not fail the run: $(out a)"
grep -q "^a: FAILED" "$T/a.out" && grep -q "^  the words of the failure" "$T/a.out" && grep -q "^Failed: a$" "$T/a.out" ||
  fail "a failing part did not print the end of its log: $(out a)"
grep -q "^b: passed (" "$T/a.out" || fail "the other part did not pass: $(out a)"

# The retry.
begin; FAKE_FAIL=r/light FAKE_SAY="RETRY-ME: not the code" check a --force r; wait
[ "$(rc a)" = 0 ] && ran r/retry || fail "a failure that matches the retry rule was not retried: $(out a)"
grep -q "r: its light steps' log matches the retry rule: running its retry command instead" "$T/a.out" ||
  fail "the retry was not said: $(out a)"
begin; FAKE_FAIL=r/light FAKE_SAY="a test failed" check a --force r; wait
[ "$(rc a)" = 1 ] || fail "a failure that does not match passed: $(out a)"
ran r/retry && fail "a failure that does not match the rule was retried"
# A retry that fails fails the part.
cat >"$T/fail-retry.sh" <<EOF
echo RETRY-ME; exit 1
EOF
write_config "$R" "$(sed "s|\"run\": \"bash $T/fake.sh r retry\"|\"run\": \"bash $T/fail-retry.sh\"|" "$R/.claude/ap.json")"
begin; FAKE_FAIL=r/light FAKE_SAY=RETRY-ME check a --force r; wait
[ "$(rc a)" = 1 ] && [ "$(starts r/light)" = 1 ] || fail "a retry that failed passed, or ran more than once: $(out a)"
# A retry with "heavy": true runs under the heavy lock: after another run's heavy steps, and
# beside its own run's heavy steps, whose lock it shares (the run keeps it until the retry ends).
config
write_config "$R" "$(sed "s|\"run\": \"bash $T/fake.sh r retry\"|\"run\": \"bash $T/fake.sh r heavy-retry\", \"heavy\": true|" "$R/.claude/ap.json")"
begin; export FAKE_SLEEP=2 FAKE_MEET="h/heavy r/light"
check a --force h; FAKE_FAIL=r/light FAKE_SAY=RETRY-ME check b --force r; wait
[ "$(rc a)$(rc b)" = 00 ] && ran r/heavy-retry || fail "a heavy retry did not pass: $(out a; out b)"
overlap h/heavy r/heavy-retry && fail "a heavy retry ran beside another run's heavy steps: $(cat "$EV")"
begin; export FAKE_SLEEP=2 FAKE_MEET="h/heavy r/light"
(cd "$R" && FAKE_FAIL=r/light FAKE_SAY=RETRY-ME limited 120 ap-check --force h r >"$T/a.out" 2>&1; echo $? >"$T/a.rc") & wait
[ "$(rc a)" = 0 ] && ran r/heavy-retry || fail "a heavy retry in a run with heavy steps did not pass: $(out a)"
grep -q unlocked "$EV" && fail "a heavy retry or step ran without the heavy lock: $(cat "$EV")"
# Two runs that must not wait for each other: run a holds r's lock and its retry wants the heavy
# lock; run b checks h and r. b must not hold the heavy lock while it waits for r's lock. r's light
# step in a waits at a gate until b is either running h's heavy step or waiting for a lock.
begin; export FAKE_SLEEP=1
(cd "$R" && FAKE_GATE=$T/gate FAKE_FAIL=r/light FAKE_SAY=RETRY-ME limited 300 ap-check --force r >"$T/a.out" 2>&1; echo $? >"$T/a.rc") &
wait_until 60 grep -q "^r/light start" "$EV" || fail "run a did not start r's light step: $(out a)"
(cd "$R" && limited 300 ap-check --force h r >"$T/b.out" 2>&1; echo $? >"$T/b.rc") &
wait_until 60 eval 'grep -q "^h/heavy start" "$EV" || grep -q "waiting for the check" "$T/b.out"' || fail "run b did not start: $(out b)"
touch "$T/gate"; wait; rm -f "$T/gate"
[ "$(rc a)$(rc b)" = 00 ] || fail "two runs with a heavy retry waited for each other: exit $(rc a) and $(rc b): $(out a; out b)"
config

# A step that hangs is stopped after its time limit, with what runs under it; the run fails and
# frees m's lock, so the next run does not wait.
begin; rm -f "$T/m-light.pid"; config '"light_min_mb": 0, "step_limit_min": 0.02'
(cd "$R" && FAKE_SLEEP=300 limited 120 ap-check --force m >"$T/a.out" 2>&1; echo $? >"$T/a.rc") & wait
[ "$(rc a)" = 1 ] && grep -q "m: its light steps ran for more than 1 s and were stopped" "$T/a.out" ||
  fail "a step that hangs was not stopped: $(out a)"
step=$(cat "$T/m-light.pid" 2>/dev/null)
[ -n "$step" ] && pid_runs "$step" && { fail "the step that hung still runs"; kill -9 "$step"; }
config
check b --force m; wait
[ "$(rc b)" = 0 ] || fail "the run after a hung one did not pass: $(out b)"
grep -q "waiting for the check" "$T/b.out" && fail "the run after a hung one waited for it: $(out b)"

# The shell that started a run is stopped, as an agent stops a background task: the run stops
# too, with the step under it, and the next run takes its lock at once.
begin; rm -f "$T/h-heavy.pid"
bash -c "cd '$R' && FAKE_SLEEP=300 ap-check --force h >'$T/a.out' 2>&1; :" & shell=$!
wait_until 60 test -s "$T/h-heavy.pid" || fail "the run to stop did not start its step: $(out a)"
kill -9 $shell; wait $shell 2>/dev/null # without the shell's "Killed" line
step=$(cat "$T/h-heavy.pid")
wait_until 30 eval '! pid_runs "$step"' || { fail "the step of a run whose shell was stopped still runs"; kill -9 "$step"; }
grep -qx '[0-9][0-9]*' "$T/h-heavy.run" || fail "a step was not told its run (AP_CHECK_RUN): $(cat "$T/h-heavy.run")"
check b --force h; wait
[ "$(rc b)" = 0 ] || fail "the next run did not pass: $(out b)"
grep -q "waiting for the check" "$T/b.out" && fail "the next run waited for the stopped one: $(out b)"

# The run itself is stopped (TERM): it stops its steps first, then frees the heavy lock, so no
# other run's heavy steps start beside a step that still runs. The step may take
# a moment to end once it was stopped: 2 s for that.
begin; rm -f "$T/h-heavy.pid"
(cd "$R" && AP_CHECK_WATCH_S=0 FAKE_SLEEP=300 exec ap-check --force h >"$T/a.out" 2>&1) & run=$!
wait_until 60 test -s "$T/h-heavy.pid" || fail "the run to stop did not start its step: $(out a)"
step=$(cat "$T/h-heavy.pid")
kill -TERM $run
wait_until 30 test ! -d "$LOCK" || fail "a run stopped with TERM did not free the heavy lock"
wait_until 2 eval '! pid_runs "$step"' || { fail "the heavy lock was free while the step of the stopped run still ran"; kill -9 "$step"; }
wait $run 2>/dev/null

# A job of the run is killed with -9 (as the system does when memory runs out): it leaves no mark
# that it ended. The run still ends, fails those parts and frees their locks.
begin; rm -f "$T"/*.job
(cd "$R" && FAKE_GATE=$T/gate FAKE_GATED="a/light h/heavy" FAKE_JOB=1 limited 120 ap-check --force a h >"$T/a.out" 2>&1; echo $? >"$T/a.rc") &
wait_until 60 eval 'test -s "$T/a-light.job" && test -s "$T/h-heavy.job"' || fail "the jobs to kill did not start: $(out a)"
kill -9 "$(cat "$T/a-light.job")" "$(cat "$T/h-heavy.job")"
wait_until 120 test -s "$T/a.rc" || fail "a run whose jobs were killed did not end"
for s in a-light h-heavy; do # a stopped process may take a moment to end
  wait_until 2 eval '! pid_runs "$(cat "$T/$s.self")"' || fail "the step $s of a killed job still runs after the run ended"
done
[ "$(rc a)" = 1 ] && grep -q "^a: FAILED" "$T/a.out" && grep -q "^h: FAILED" "$T/a.out" ||
  fail "a run whose jobs were killed did not fail their parts: exit $(rc a), $(out a)"
for l in "$LOCK" "$COMMON/ap-check-a.lock" "$COMMON/ap-check-h.lock"; do
  [ -d "$l" ] && fail "a run whose jobs were killed did not free ${l##*/}"
done
touch "$T/gate"; wait; rm -f "$T/gate" # the steps left by the killed jobs end at the gate

passed_all
