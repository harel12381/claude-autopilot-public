#!/usr/bin/env bash
# Tests ap-check in a throwaway repository (tests/check-fake.sh), its parts and its locks:
#   - --list names every part and its steps; an unknown part, or a broken check_parts: exit 2;
#   - a part's steps run in its dir;
#   - a part that passed is skipped, until one of its inputs changes (uncommitted, a new file
#     too), its commands or its version; another part's change does not check it again; --force
#     checks it again;
#   - light steps of two runs run at the same time; one part never runs twice at once (not even
#     its light steps beside its heavy ones); a run that waited for a part that passed meanwhile
#     skips it;
#   - heavy steps of two runs never run at the same time, and light steps run beside them;
#   - with too little free memory, a run takes the heavy lock for all its steps;
#   - a lock left by a killed run is taken over;
#   - light first: when the light steps fail, no heavy step runs.
# tests/check-failures-test.sh tests what ap-check does when a step fails or hangs.
#
#   bash tests/check-test.sh     # exit 0 when every case passed (a minute or two)
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/check-fake.sh
source "$(dirname "$0")/check-fake.sh"

# The list, and wrong arguments.
(cd "$R" && ap-check --list) >"$T/list" 2>&1 || fail "--list failed: $(cat "$T/list")"
for p in a b h m r; do grep -qE "^$p " "$T/list" || fail "--list does not name $p: $(cat "$T/list")"; done
grep -E '^m ' "$T/list" | grep -q 'light first, then heavy' || fail "--list does not say m's light steps come first: $(cat "$T/list")"
(cd "$R" && ap-check nope) >"$T/x" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "unknown part: nope" "$T/x" || fail "an unknown part: exit $rc, $(cat "$T/x")"
cp "$R/.claude/ap.json" "$T/ap.json"
write_config "$R" '{ "repo": "o/n", "check_parts": [ { "name": "x", "inputs": ["a"] } ] }'
(cd "$R" && ap-check) >"$T/x" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "part x: it needs a light or a heavy command" "$T/x" || fail "a part with no command: exit $rc, $(cat "$T/x")"
write_config "$R" '{ "repo": "o/n", "check_options": { "light_min": 1 }, "check_parts": [ { "name": "x", "inputs": ["a"], "light": "true" } ] }'
(cd "$R" && ap-check) >"$T/x" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "check_options: unknown keys light_min" "$T/x" || fail "an unknown key in check_options: exit $rc, $(cat "$T/x")"
write_config "$R" '{ "repo": "o/n" }'
(cd "$R" && ap-check) >"$T/x" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "no check_parts" "$T/x" || fail "no check_parts: exit $rc, $(cat "$T/x")"
cp "$T/ap.json" "$R/.claude/ap.json"
write_config "$R" "$(sed 's/"inputs": \["a"\]/"inputs": ["gone"]/' "$T/ap.json")"
(cd "$R" && ap-check a) >"$T/x" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "gone" "$T/x" || fail "an input that is not there: exit $rc, $(cat "$T/x")"
cp "$T/ap.json" "$R/.claude/ap.json"

# The cache: passed parts are skipped until their inputs change.
begin; check a a b h m r; wait
[ "$(rc a)" = 0 ] || fail "the first run did not pass: $(out a)"
for s in a/light b/light h/heavy m/light m/heavy r/light; do ran $s || fail "$s did not run: $(cat "$EV")"; done
[ "$(cat "$T/m-light.dir")/$(cat "$T/a-light.dir")" = "m/repo" ] || fail "the steps did not run in their dir"
begin; check b; wait
for p in a b h m r; do grep -q "^$p: passed before ([^,]*, [0-9-]* [0-9:]*), skipped" "$T/b.out" || fail "$p was checked again: $(out b)"; done
[ -s "$EV" ] && fail "a step ran in a run where every part had passed: $(cat "$EV")"
[ "$(rc b)" = 0 ] || fail "a run of parts that all passed before did not exit 0"
begin; echo y >"$R/a/code"; check c; wait
grep -q "^a: passed (" "$T/c.out" && grep -q "^b: passed before ([^,]*, [0-9-]* [0-9:]*), skipped" "$T/c.out" ||
  fail "an uncommitted change of a did not check only a again: $(out c)"
begin; echo y >"$R/shared.txt"; check d; wait
grep -q "^h: passed (" "$T/d.out" && grep -q "^a: passed before ([^,]*, [0-9-]* [0-9:]*), skipped" "$T/d.out" ||
  fail "a change of shared.txt did not check only h again: $(out d)"
begin; echo new >"$R/a/new-file"; check e a; wait
grep -q "^a: passed (" "$T/e.out" || fail "a new file in a did not check a again: $(out e)"
begin; check f --force a; wait
grep -q "^a: passed (" "$T/f.out" || fail "--force did not check a again: $(out f)"
begin; write_config "$R" "$(sed 's/fake.sh b light/fake.sh b light --new/' "$T/ap.json")"; check g a b; wait
grep -q "^b: passed (" "$T/g.out" && grep -q "^a: passed before ([^,]*, [0-9-]* [0-9:]*), skipped" "$T/g.out" ||
  fail "a change of b's command did not check only b again: $(out g)"
begin; write_config "$R" "$(sed 's/"name": "a", /"name": "a", "version": 2, /' "$T/ap.json")"; check h a b; wait
grep -q "^a: passed (" "$T/h.out" && grep -q "^b: passed before ([^,]*, [0-9-]* [0-9:]*), skipped" "$T/h.out" ||
  fail "a new version of a did not check a again, or b, back as it passed before, was checked again: $(out h)"
cp "$T/ap.json" "$R/.claude/ap.json"

# Light steps of two runs at the same time; one part never twice at once.
begin; export FAKE_MEET="a/light b/light"; check a --force a; check b --force b; wait
overlap a/light b/light || fail "light steps of two runs did not run at the same time: $(cat "$EV")"
begin; export FAKE_SLEEP=2; check a --force a; check b --force a; wait
[ "$(awk '$1 == "a/light" {print $2}' "$EV" | tr '\n' ' ')" = "start end start end " ] ||
  fail "two runs of one part ran at the same time: $(cat "$EV")"
begin; export FAKE_SLEEP=2; check a --force m; check b --force m; wait
[ "$(awk '$1 ~ /^m\// {print $1, $2}' "$EV" | tr '\n' ' ')" = "m/light start m/light end m/heavy start m/heavy end m/light start m/light end m/heavy start m/heavy end " ] ||
  fail "two runs of m ran at the same time: $(cat "$EV")"
# Without --force, the second run waits for the first, which passes it meanwhile: the first's step
# waits at a gate until the second waits for its lock; then the part's cache file is there before
# the lock is free, and the second skips it whenever it looks.
begin; echo z >"$R/b/code"; FAKE_GATE=$T/gate check a b
wait_until 60 grep -q "^b/light start" "$EV" || fail "the first run of b did not start: $(out a)"
check b b
wait_until 60 grep -q "waiting for the check" "$T/b.out" || fail "the second run of b did not wait for the first: $(out b)"
touch "$T/gate"; wait; rm -f "$T/gate"
[ "$(starts b/light)" = 1 ] && grep -q "^b: passed in another run meanwhile ([^,]*, [0-9-]* [0-9:]*), skipped" "$T/b.out" ||
  fail "a part that passed in another run meanwhile was checked again: $(out a; out b)"
# A light-only part's lock is freed when its light steps end, not when the run's heavy steps end:
# run a checks a and h (h's heavy step waits at a gate); run b, started after, checks a, and ends
# while h's heavy step still runs.
begin; FAKE_GATE=$T/gate FAKE_GATED=h/heavy check a --force a h
wait_until 60 eval 'grep -q "^a/light end" "$EV" && grep -q "^h/heavy start" "$EV"' || fail "run a did not get to h's heavy step: $(out a)"
check b --force a
wait_until 300 test -s "$T/b.rc" || fail "run b waited for a's lock until run a's heavy step ended: $(out b)"
grep -q "^h/heavy end" "$EV" && fail "h's heavy step ended before run b did: $(cat "$EV")"
touch "$T/gate"; wait; rm -f "$T/gate"
[ "$(rc a)$(rc b)" = 00 ] || fail "the runs of a light part beside a heavy one failed: $(out a; out b)"

# Heavy steps of two runs never at the same time; light steps beside them.
begin; export FAKE_SLEEP=2 FAKE_MEET="h/heavy m/light"; check a --force h; check b --force m; wait
overlap h/heavy m/heavy && fail "heavy steps of two runs ran at the same time: $(cat "$EV")"
ran h/heavy && ran m/heavy || fail "a heavy step did not run: $(cat "$EV")"
overlap h/heavy m/light || fail "m's light steps did not run beside h's heavy ones: $(cat "$EV")"
grep -q unlocked "$EV" && fail "a heavy step ran without the heavy lock"
[ "$(rc a)$(rc b)" = 00 ] || fail "a run failed: $(out a; out b)"

# Too little free memory: light steps take the heavy lock.
begin; config '"light_min_mb": 99999999'; export FAKE_SLEEP=2
check a --force a; check b --force b; check c --force h; wait
overlap a/light b/light && fail "light steps ran at the same time with too little memory"
overlap a/light h/heavy && fail "a light step ran beside a heavy one with too little memory"
overlap b/light h/heavy && fail "a light step ran beside a heavy one with too little memory"
grep -q "every step of this run under the heavy lock" "$T/c.out" || fail "a run with heavy steps and little memory did not say so: $(out c)"
# Alone, with light steps only, the heavy lock changes nothing: no word about it.
begin; check a --force a; wait
grep -q "every step of this run under the heavy lock" "$T/a.out" && fail "a run alone with light steps only spoke of the heavy lock: $(out a)"
[ "$(rc a)" = 0 ] || fail "a run alone with little memory failed: $(out a)"
config

# A lock left by a run that was killed.
begin; mkdir "$LOCK"; echo "$(bash -c 'echo $$') /killed/run (since 00:00)" >"$LOCK/owner"
check a --force h; wait
grep -q "Took over ap-check.lock" "$T/a.out" && [ "$(rc a)" = 0 ] || fail "a dead run's lock was not taken over: $(out a)"
[ -d "$LOCK" ] && fail "the heavy lock was left behind"

# Light first: the light steps fail, no heavy step, and the part is not remembered as passed.
begin; echo f >"$R/m/code"; FAKE_FAIL=m/light check a m; wait
[ "$(rc a)" = 1 ] || fail "a failing light step did not fail the run: $(out a)"
ran m/heavy && fail "a heavy step ran after the light steps failed"
begin; check b m; wait
ran m/light || fail "a part that failed was remembered as passed: $(out b)"

passed_all
