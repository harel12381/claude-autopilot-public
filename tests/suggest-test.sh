#!/usr/bin/env bash
# Tests what `ap-check --suggest` suggests to /ap:setup (lib/suggest.sh):
#   - merge_batch: 1 when the checks before a merge (merge turns and batches) fail 1 in 10 times
#     or more, else 3 (also with no such check in the log);
#   - queue_per_slot: 1 when the memory (under 2 x light_min_mb) or the disk (5 GB and 2 built
#     worktrees for each of 3 slots) is short, 3 when both are plenty (4 x light_min_mb; 11 GB and
#     3 worktrees for each slot) and a helper's check takes 10 minutes or more, else 2;
#   - the size of a built worktree leaves out .git and .claude, and is a slot worktree's when
#     there is one;
#   - `ap-check --suggest` in a throwaway repository: the facts, and both lines, from its log.
#
#   bash tests/suggest-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=plugins/ap/lib/suggest.sh
source "$ROOT/plugins/ap/lib/suggest.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "suggest-test: $*" >&2; FAILED=1; }
is() { [ "$2" = "$3" ] || fail "$1: $2, not $3"; }

is "no checks before a merge" "$(suggest_merge_batch 0 0)" 3
is "7 merge checks, none failed" "$(suggest_merge_batch 7 0)" 3
is "11 merge checks, 1 failed" "$(suggest_merge_batch 11 1)" 3
is "10 merge checks, 1 failed" "$(suggest_merge_batch 10 1)" 1
is "4 merge checks, 2 failed" "$(suggest_merge_batch 4 2)" 1

# memory MB, disk MB, worktree MB, check s, light_min_mb
is "little memory" "$(suggest_queue 5999 999999 1000 900 3000)" 1
is "little disk" "$(suggest_queue 99999 $((5120 + 6 * 1000 - 1)) 1000 900 3000)" 1
is "enough for 2" "$(suggest_queue 6000 $((5120 + 6 * 1000)) 1000 900 3000)" 2
is "plenty, but a short check" "$(suggest_queue 12000 999999 1000 599 3000)" 2
is "plenty, a long check, but not the disk for 3" "$(suggest_queue 12000 $((11264 + 9 * 1000 - 1)) 1000 600 3000)" 2
is "plenty, and a long check" "$(suggest_queue 12000 $((11264 + 9 * 1000)) 1000 600 3000)" 3
is "the memory limit is light_min_mb's" "$(suggest_queue 12000 999999 1000 600 6000)" 2

# The size of a worktree: .git and .claude are left out.
mkdir -p "$T/w/src" "$T/w/.git" "$T/w/.claude" "$T/w/.cache"
head -c $((3 * 1024 * 1024)) /dev/zero >"$T/w/src/big" && head -c $((2 * 1024 * 1024)) /dev/zero >"$T/w/.cache/c"
head -c $((5 * 1024 * 1024)) /dev/zero >"$T/w/.git/pack" && cp "$T/w/.git/pack" "$T/w/.claude/x"
is "the size of a worktree" "$(tree_mb "$T/w")" 5
is "an empty folder" "$(tree_mb "$T/w/src/none" 2>/dev/null)" 0

# ap-check --suggest, with a log of 10 checks before a merge, 1 failed: one at a time.
M=$T/main
g init -q -b main "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
echo ".claude/" >>"$M/.git/info/exclude"
write_config "$M" '{ "repo": "o/n", "owner": "O", "main_branch": "main", "check": "true" }'
LOG=$M/.git/ap-check-log.tsv
line() { printf '2026-11-02T10:00:00+0200\tp\t%s\t1\t0\t-\t%s\t-\tabc\t0\tmain\t%s\t%s\t-\t-\t-\n' "$@" >>"$LOG"; } # result, kind, run, run_s
for i in 1 2 3 4 5 6 7 8 9; do line passed merge "m$i" 100; done
line failed batch b1 100
line passed branch c1 700
line skipped merge s1 1 # a part that passed before: not a check
(cd "$M" && ap-check --suggest) >"$T/out" 2>&1 || fail "ap-check --suggest failed: $(cat "$T/out")"
grep -qx "checks before a merge in the log (merge turns and batches): 10, not passed: 1" "$T/out" || fail "the merge checks are not counted: $(cat "$T/out")"
grep -q "^merge_batch: 1 " "$T/out" || fail "merge_batch is not 1: $(cat "$T/out")"
grep -q "a helper's own check: 700 s on average (1 runs)" "$T/out" || fail "the helper's check is not counted: $(cat "$T/out")"
grep -qE "^queue_per_slot: [123] " "$T/out" || fail "no queue_per_slot line: $(cat "$T/out")"
grep -q "one built worktree: [0-9]* MB (the main checkout)" "$T/out" || fail "the worktree is not the main checkout: $(cat "$T/out")"
mkdir -p "$M/.claude/worktrees/ap-2"
line passed merge m10 100
(cd "$M" && ap-check --suggest) >"$T/out" 2>&1
grep -q "^merge_batch: 3 " "$T/out" || fail "merge_batch is not 3 with 1 failed of 11: $(cat "$T/out")"
grep -q "one built worktree: [0-9]* MB (ap-2)" "$T/out" || fail "a slot worktree is not measured: $(cat "$T/out")"
(cd "$M" && ap-check --suggest x) >/dev/null 2>&1 && fail "--suggest took an argument"

[ "$FAILED" = 0 ] && echo "suggest: ok"
exit "$FAILED"
