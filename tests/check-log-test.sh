#!/usr/bin/env bash
# Tests the log of ap-check (lib/check-log.sh) in a throwaway repository (tests/check-fake.sh):
#   - every run adds one line per part asked for, with 16 fields: passed, failed, skipped (passed
#     before), hung, and why a part ran again (retry);
#   - the kind of run: a helper's own check (branch), the check at a merge turn (merge: HEAD
#     merges the main branch in), a commit of the main branch (main); and whether the tree had
#     changes that are not committed;
#   - the manager's check in a folder of its own (AP_CHECK_KIND=fresh), and the check of a batch
#     and of its halves (AP_CHECK_KIND, AP_CHECK_BATCH): their kind and how
#     many pull requests they merge; in a slot worktree, how many issues the slot's other worktrees
#     had open (ap-run's issue-<s> files);
#   - the wait for another run's heavy lock is kept;
#   - `ap-check --stats` counts the runs, failures and times per part and kind, leaves out a
#     broken line, reads a line of 14 fields (written before fields 15 and 16), and says the time
#     the batches and the queues saved.
#
#   bash tests/check-log-test.sh  # exit 0 when every case passed (a minute or two)
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/check-fake.sh
source "$(dirname "$0")/check-fake.sh"
LOG=$COMMON/ap-check-log.tsv
field() { awk -F'\t' -v p="$1" -v n="$2" '$2 == p {v = $n} END {print v}' "$LOG"; } # part, field: of its last line
lines() { wc -l <"$LOG" | tr -d ' '; }
rgit() { g -C "$R" "$@"; } # git in the test repository

# One part passes, another fails: a line for each, also for the one that failed.
rgit switch -q -c feature/1-x
begin; FAKE_SLEEP=1 FAKE_FAIL=b/light check a --force a b; wait
[ "$(rc a)" = 1 ] || fail "a failing part did not fail the run: $(out a)"
[ "$(lines)" = 2 ] || fail "a run of two parts did not add two lines: $(cat "$LOG")"
bad=$(awk -F'\t' 'NF != 16' "$LOG"); [ -z "$bad" ] || fail "a line without 16 fields: $bad"
[ "$(field a 3)" = passed ] && [ "$(field b 3)" = failed ] || fail "the results are wrong: $(cat "$LOG")"
[ "$(field a 4)" -ge 1 ] || fail "the time its steps took is missing: $(cat "$LOG")"
[ "$(field a 7)/$(field a 8)/$(field a 10)/$(field a 11)/$(field a 14)/$(field a 15)/$(field a 16)" = branch/feature/1-x/0/repo/force/-/- ] ||
  fail "a helper's own check is not told apart: $(cat "$LOG")"
[ "$(field a 9)" = "$(rgit rev-parse HEAD | cut -c1-10)" ] || fail "the commit is wrong: $(cat "$LOG")"
[ "$(field a 12)" = "$(field b 12)" ] || fail "the lines of one run have different run ids: $(cat "$LOG")"
[[ $(field a 1) =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{4}$ ]] || fail "the time is not like 2026-11-01T10:20:30+0200: $(field a 1)"

# A part that passed before is skipped, and a change not committed shows.
begin; check a a; wait
[ "$(field a 3)/$(field a 14)" = skipped/- ] || fail "a part that passed before is not skipped in the log: $(cat "$LOG")"
echo y >"$R/a/code"; check a a; wait
[ "$(field a 3)/$(field a 10)" = passed/1 ] || fail "a change not committed does not show: $(cat "$LOG")"
rgit commit -qam change

# A retry, and a step that hangs.
begin; FAKE_FAIL=r/light FAKE_SAY=RETRY-ME check a --force r; wait
[ "$(field r 3)/$(field r 6)" = passed/retry ] || fail "a part that passed on its retry is not logged so: $(cat "$LOG")"
begin; config '"light_min_mb": 0, "step_limit_min": 0.02'
(cd "$R" && FAKE_SLEEP=300 limited 120 ap-check --force b >"$T/a.out" 2>&1); config
[ "$(field b 3)" = hung ] || fail "a step that hung is not logged as hung: $(cat "$LOG")"

# The check at a merge turn: main merged into the branch. And a commit of main itself.
rgit branch -q -f main HEAD~1
rgit switch -q main; echo z >"$R/h/code"; rgit commit -qam "on main"
rgit switch -q feature/1-x; rgit merge -q --no-edit main
begin; check a --force a; wait
[ "$(field a 7)" = merge ] || fail "a merge of main is not kind merge: $(cat "$LOG")"
rgit switch -q main
begin; check a --force a; wait
[ "$(field a 7)/$(field a 8)" = main/main ] || fail "a commit of main is not kind main: $(cat "$LOG")"
rgit switch -q --detach main
begin; check a --force a; wait
[ "$(field a 7)/$(field a 8)" = main/- ] || fail "a detached commit of main is not kind main: $(cat "$LOG")"

# A batch of 3 pull requests, and a check of its first 2 to find which one breaks it.
begin; AP_CHECK_KIND=batch AP_CHECK_BATCH=3 check a --force a; wait
[ "$(field a 7)/$(field a 15)" = batch/3 ] || fail "the check of a batch is not kind batch with its size: $(tail -1 "$LOG")"
begin; AP_CHECK_KIND=bisect AP_CHECK_BATCH=2 check a --force a; wait
[ "$(field a 7)/$(field a 15)" = bisect/2 ] || fail "a check of a batch's half is not kind bisect: $(tail -1 "$LOG")"
begin; AP_CHECK_KIND=fresh AP_CHECK_BATCH=2 check a --force a; wait
[ "$(field a 7)/$(field a 15)" = fresh/- ] || fail "the manager's check in a folder of its own is not kind fresh: $(tail -1 "$LOG")"
begin; AP_CHECK_KIND=other AP_CHECK_BATCH=2 check a --force a; wait
[ "$(field a 7)/$(field a 15)" = main/- ] || fail "an unknown AP_CHECK_KIND was taken: $(tail -1 "$LOG")"

# A slot worktree: the issues open in the slot's other worktrees (ap-1b of ap-1, and ap-1 of ap-1b).
W=$T/wt; mkdir "$W"
rgit worktree add -q "$W/ap-1" -b feature/2-y main && rgit worktree add -q "$W/ap-1b" -b feature/3-z main || exit 1
mkdir -p "$COMMON/ap-autopilot" && echo 2 >"$COMMON/ap-autopilot/issue-1" && echo 3 >"$COMMON/ap-autopilot/issue-1b"
echo 9 >"$COMMON/ap-autopilot/issue-2" # another slot: not counted
begin; (cd "$W/ap-1" && ap-check --force a >"$T/q.out" 2>&1) || fail "the check in ap-1 failed: $(cat "$T/q.out")"
[ "$(field a 11)/$(field a 16)" = ap-1/1 ] || fail "ap-1 does not count the issue open in ap-1b: $(tail -1 "$LOG")"
rm "$COMMON/ap-autopilot/issue-1b"
begin; (cd "$W/ap-1b" && ap-check --force a >"$T/q.out" 2>&1) || fail "the check in ap-1b failed: $(cat "$T/q.out")"
[ "$(field a 11)/$(field a 16)" = ap-1b/1 ] || fail "ap-1b does not count the issue open in ap-1: $(tail -1 "$LOG")"
rm "$COMMON/ap-autopilot/issue-1"
begin; (cd "$W/ap-1" && ap-check --force a >"$T/q.out" 2>&1)
[ "$(field a 16)" = 0 ] || fail "ap-1 counts an issue while none is open in its slot's other worktrees: $(tail -1 "$LOG")"
rm -rf "$COMMON/ap-autopilot"

# The summary: per part and kind, and per whole run.
printf 'broken\tline\n' >>"$LOG" # two runs that wrote at the same moment: left out
# A line of 14 fields, from before fields 15 and 16: a branch check of part x.
printf '2026-11-01T10:00:00+0200\tx\tpassed\t5\t0\t-\tbranch\tf/1\tabc\t0\trepo\told-1\t7\t-\n' >>"$LOG"
(cd "$R" && ap-check --stats) >"$T/stats" 2>&1 || fail "--stats failed: $(cat "$T/stats")"
row() { awk -v p="$1" -v k="$2" '$1 == p && $2 == k {print $3, $4, $5, $6, $7}' "$T/stats"; } # runs failed hung again skipped
[ "$(row a branch)" = "5 0 0 0 1" ] || fail "the a row of branch is wrong: $(cat "$T/stats")"
[ "$(row a main)" = "3 0 0 0 0" ] || fail "the a row of main is wrong: $(cat "$T/stats")"
[ "$(row a batch)" = "1 0 0 0 0" ] && [ "$(row a bisect)" = "1 0 0 0 0" ] || fail "the batch rows are wrong: $(cat "$T/stats")"
[ "$(row x branch)" = "1 0 0 0 0" ] || fail "a line of 14 fields is not read: $(cat "$T/stats")"
[ "$(row b branch)" = "2 1 1 0 0" ] || fail "the b row is wrong: $(cat "$T/stats")"
[ "$(row r branch)" = "1 0 0 1 0" ] || fail "the r row is wrong: $(cat "$T/stats")"
[ "$(awk '$1 == "merge" && NF == 4 {print $2, $3}' "$T/stats")" = "1 0" ] || fail "the merge runs are wrong: $(cat "$T/stats")"
grep -qE "^  merges in batches: 3 pull requests in 1 batches, 2 checks \(1 to find which one broke a batch\), [0-9]+ s; a merge-turn check for each \([0-9]+ s on average, since then\) takes [0-9]+ s: saved about -?[0-9]+ min$" "$T/stats" ||
  fail "the time the batches saved is not said: $(cat "$T/stats")"
grep -qE "^  the queues: 2 checks \([0-9]+ s\) ran while their slot had another issue open: saved at least [0-9]+ min$" "$T/stats" ||
  fail "the time the queues saved is not said: $(cat "$T/stats")"
# A window with batches but no merge-turn check: one merge-turn check costs what the whole log says.
since=$(awk -F'\t' '$7 == "batch" {print $1}' "$LOG")
(cd "$R" && ap-check --stats "$since") >"$T/stats1"
grep -q "s on average, in the whole log) takes" "$T/stats1" ||
  fail "--stats since the batch does not compare with the merge-turn checks of the whole log: $(cat "$T/stats1")"
# The log of fake times: 2 merge-turn checks of 400 s; a batch of 4 in 300 s and a check of a half
# in 200 s; a queue check of 600 s: 4 x 400 - 500 = 1100 s saved (18 min), and at least 10 min.
LOG2=$T/log2.tsv; mv "$LOG" "$LOG2"
n=0; for l in "merge 400 - -" "merge 400 - -" "batch 300 4 -" "bisect 200 2 -" "branch 600 - 1" "branch 50 - 0"; do
  read -r k s b o <<<"$l"
  printf '2026-11-02T10:00:00+0200\tx\tpassed\t1\t0\t-\t%s\t-\tabc\t0\tap-1\t%s\t%s\t-\t%s\t%s\n' "$k" "r$((n += 1))" "$s" "$b" "$o" >>"$LOG"
done
(cd "$R" && ap-check --stats) >"$T/stats2"
grep -qF "merges in batches: 4 pull requests in 1 batches, 2 checks (1 to find which one broke a batch), 500 s; a merge-turn check for each (400 s on average, since then) takes 1600 s: saved about 18 min" "$T/stats2" ||
  fail "the batch's saved time is wrong: $(cat "$T/stats2")"
grep -qF "the queues: 1 checks (600 s) ran while their slot had another issue open: saved at least 10 min" "$T/stats2" ||
  fail "the queue's saved time is wrong: $(cat "$T/stats2")"
mv "$LOG2" "$LOG"
(cd "$R" && ap-check --stats 2999-01-01) | grep -q '^a ' && fail "--stats with a date counted older runs"
bad=$(cd "$R" && ap-check --stats 20261101 2>&1) && fail "--stats took a date it cannot compare: $bad"
rm "$LOG"; (cd "$R" && ap-check --stats) | grep -q "No checks in the log yet" || fail "--stats without a log did not say so"

# The wait for another run's heavy lock is kept, also when little memory is free.
begin; mkdir "$LOCK"; echo "$$ the test (since 00:00)" >"$LOCK/owner" # held by this test
config '"light_min_mb": 99999999'; check b --force a
wait_until 60 grep -q "waiting for the check" "$T/b.out"; sleep 2; rm -rf "$LOCK"; wait; config
[ "$(field a 5)" -ge 2 ] || fail "the wait for the heavy lock is not in the log: $(cat "$LOG")"

passed_all
