#!/usr/bin/env bash
# Tests ap-brief in a throwaway repository with a .claude/ap.json:
#   - each of the four briefs is written to <common .git>/ap-autopilot/briefs/, with no <WORD>
#     left, except the words the agent fills in itself (<PR> in the helper's, <M> in the retro's);
#   - every path it fills in has only / (bash, which the agents use, drops a \);
#   - the values come from the settings and the command line: repo, owner, main branch, check,
#     the run, the issues (with and without #), the pull request;
#   - the project's own part comes after the plugin's brief, under its line;
#   - with a board, the <BOARD> line names it; without one, the line is gone;
#   - a helper of a parallel run gets its slot and worktree lines, --older-than 90 on its cleanup,
#     and the note last;
#   - a word it cannot fill (a reviewer with no --pr, no check set) is an error, and no file is
#     written; an unknown brief or option is an error.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "brief-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b trunk "$M" || exit 1
mkdir -p "$M/.claude/ap"
echo "- Run the tests with make." >"$M/.claude/ap/helper.md"
CONFIG='"repo": "o/n", "owner": "Ada", "main_branch": "trunk", "check": "make check", "briefs": { "helper": ".claude/ap/helper.md" }, "hooks": { "cleanup": "bash clean.sh" }'
write_config "$M" "{ $CONFIG }"
B=$M/.git/ap-autopilot/briefs
run() { (cd "$M" && ap-brief "$@" >"$T/out" 2>"$T/err"); }
left() { # file, words allowed: fails when another <WORD> is left in it
  local w
  w=$(grep -o '<[A-Z][A-Z_]*>' "$1" | sort -u | grep -vxF -f <(printf '%s\n' "${@:2}") | paste -sd' ' -)
  [ -z "$w" ] || fail "${1##*/} still has $w"
}

run helper --run 11 --n "#7"; rc=$?
f=$B/helper-11-7.md
[ $rc = 0 ] && [ -f "$f" ] || fail "helper: exit $rc, no $f ($(cat "$T/err"))"
[ "$(cat "$T/out")" -ef "$f" ] || [[ $(cat "$T/out") == *ap-autopilot/briefs/helper-11-7.md ]] || fail "helper: it printed $(cat "$T/out")"
left "$f" '<PR>'
grep -q 'o/n' "$f" && grep -q 'Ada' "$f" && grep -q 'make check' "$f" && grep -q '#7' "$f" ||
  fail "helper: a value is missing (repo, owner, check or issue)"
grep -q 'trunk' "$f" || fail "helper: the main branch is not filled in"
grep -q 'gh project item-add' "$f" && fail "helper: a board line, with no board set"
grep -q 'bash clean.sh`' "$f" || fail "helper: the cleanup is not filled in"
grep -q '[/\\]docs' "$f" || fail "helper: the docs folder is not filled in"
grep -q '\\docs\|\\ap-autopilot' "$f" && fail "helper: a path with a \\: $(grep -m1 '\\docs\|\\ap-autopilot' "$f")"
n=$(grep -n "^\*\*This project's own rules\*\*" "$f" | cut -d: -f1)
[ -n "$n" ] && tail -n +"$n" "$f" | grep -q 'Run the tests with make' || fail "helper: the project's part is not after its line"

write_config "$M" "{ $CONFIG, \"board\": { \"number\": 4, \"owner\": \"ada\" } }"
run helper --run 11 --n 8 --slot 2 --worktree ap-2b --note "Only the README."; rc=$?
f=$B/helper-11-8.md
[ $rc = 0 ] || fail "a parallel helper: exit $rc ($(cat "$T/err"))"
grep -q 'gh project item-add 4 --owner ada' "$f" || fail "the board is not named"
grep -qx 'Your slot is 2.' "$f" && grep -qx 'Your worktree is ap-2b.' "$f" || fail "no slot or worktree line"
grep -q 'bash clean.sh --older-than 90`' "$f" || fail "a parallel helper's cleanup has no --older-than 90"
[ "$(tail -1 "$f")" = "Only the README." ] || fail "the note is not the last line"
run helper --run 11 --n 9 --note "Keep <THIS> word."; rc=$?
[ $rc = 0 ] || fail "a note with a <WORD> in it: exit $rc ($(cat "$T/err"))"

run reviewer --run 11 --n 8 --pr 52; rc=$?
f=$B/reviewer-11-pr52.md
[ $rc = 0 ] || fail "reviewer: exit $rc ($(cat "$T/err"))"
left "$f"
grep -q '52' "$f" || fail "reviewer: the pull request is not filled in"
run planner --run 11 --n "7 8 9"; rc=$?
[ $rc = 0 ] && grep -q '#7 #8 #9' "$B/planner-11-7.md" || fail "planner: exit $rc, or the list is not in it ($(cat "$T/err"))"
left "$B/planner-11-7.md"
run retro --run 11; rc=$?
[ $rc = 0 ] || fail "retro: exit $rc ($(cat "$T/err"))"
left "$B/retro-11.md" '<M>'

# What it cannot fill, or does not know.
rm -rf "$B"
run reviewer --run 11 --n 8; rc=$?
[ $rc = 2 ] && grep -q '<PR>' "$T/err" || fail "a reviewer with no --pr: exit $rc, $(cat "$T/err")"
[ ! -e "$B/reviewer-11-8.md" ] || fail "a brief with a word left was written"
write_config "$M" '{ "repo": "o/n", "owner": "Ada" }'
run helper --run 11 --n 7; rc=$?
[ $rc = 2 ] && grep -q '<CHECK>' "$T/err" || fail "no check set: exit $rc, $(cat "$T/err")"
run nobody --run 11; rc=$?
[ $rc = 2 ] || fail "an unknown brief: exit $rc, not 2"
run helper --run 11 --n 7 --colour red; rc=$?
[ $rc = 2 ] || fail "an unknown option: exit $rc, not 2"
run helper --run 11 --n; rc=$?
[ $rc = 2 ] || fail "--n with no value: exit $rc, not 2"
run helper --run 11 --n 7 --worktree ap-1; rc=$?
[ $rc = 2 ] || fail "--worktree with a slot's own worktree: exit $rc, not 2"

[ "$FAILED" = 0 ] && echo "brief: ok"
exit "$FAILED"
