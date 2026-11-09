#!/usr/bin/env bash
# Tests ap-check-branch in a throwaway repository with an origin, and a fake check (set in a
# temporary .claude/ap.json) that writes down where it ran and fails when the branch has a file
# `fail`:
#   - the check runs in the folder check-<branch> on origin/<branch>, the exit code is the
#     check's, and the folder is gone afterwards, also when the check fails;
#   - the main checkout stays on its branch, with no change;
#   - a `/` in the branch name becomes `-` in the folder's name;
#   - a folder that an earlier check left is removed first;
#   - a left folder that cannot be deleted (a file still in use) is named, the check does not
#     run, and the exit is 90; on Windows a build or test tool still running there is stopped
#     first, and then the folder goes;
#   - hooks.check_setup runs first, in the same folder; when it fails, exit 91 and no check;
#   - a branch with its own .claude/ap.json runs its own check and setup, not main's;
#   - no `check` set, no origin/<branch>, or no branch given: exit 90.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
HOLDERS=() # the processes that hold a file open, stopped at the end
stop_holder() { kill "$1" 2>/dev/null || taskkill //F //PID "$1" >/dev/null 2>&1 || true; }
trap 'for p in "${HOLDERS[@]}"; do stop_holder "$p"; done; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
FAILED=0
fail() { echo "check-branch-test: $*" >&2; FAILED=1; }
g init -q --bare -b develop "$T/origin.git" || exit 1
g clone -q "$T/origin.git" "$T/main" 2>/dev/null || exit 1
M=$T/main
echo ".claude/" >>"$M/.git/info/exclude"
g -C "$M" commit -q --allow-empty -m init && g -C "$M" push -q origin HEAD:develop || exit 1
for b in good fix/1-slash; do g -C "$M" push -q origin HEAD:"$b" || exit 1; done
g -C "$M" switch -q -c bad && touch "$M/fail" && g -C "$M" add fail && g -C "$M" commit -q -m bad &&
  g -C "$M" push -q origin bad && g -C "$M" switch -q develop || exit 1
g -C "$M" fetch -q origin || exit 1

mkdir "$T/tools"
cat >"$T/tools/check.sh" <<EOF
echo "check \$(basename "\$PWD")" >>"$T/calls"
[ ! -f fail ] || exit 5
EOF
cat >"$T/tools/setup.sh" <<EOF
echo "setup \$(basename "\$PWD")" >>"$T/calls"
exit \$(cat "$T/setup-rc" 2>/dev/null || echo 0)
EOF
CONFIG='"repo": "o/n", "owner": "O", "main_branch": "develop"'
write_config "$M" "{ $CONFIG, \"check\": \"bash $T/tools/check.sh\" }"
run() { : >"$T/calls"; (cd "$M" && ap-check-branch "$@" >"$T/out" 2>"$T/err"); }
called() { grep -qxF -- "$1" "$T/calls" 2>/dev/null; }
gone() { # folder name: removed as a folder and as a worktree
  [ ! -e "$M/.claude/worktrees/$1" ] || fail "the folder $1 is still there after the check"
  git -C "$M" worktree list | grep -q "/$1 " && fail "git still lists the worktree $1"
  return 0
}

run good; rc=$?
[ $rc = 0 ] || fail "a passing check: exit $rc ($(cat "$T/err"))"
called "check check-good" || fail "the check did not run in check-good: $(cat "$T/calls")"
tail -1 "$T/out" | grep -q "good: the check passed" || fail "the last line does not say it passed: $(cat "$T/out")"
gone check-good
[ "$(git -C "$M" branch --show-current)" = develop ] || fail "the main checkout left its branch"
[ -z "$(git -C "$M" status --short)" ] || fail "the main checkout has changes: $(git -C "$M" status --short)"

run bad; rc=$?
[ $rc = 5 ] || fail "a failing check: exit $rc, not the check's 5"
tail -1 "$T/out" | grep -q "bad: the check failed (exit 5)" || fail "the last line does not say it failed: $(cat "$T/out")"
gone check-bad

run fix/1-slash; rc=$?
[ $rc = 0 ] && called "check check-fix-1-slash" || fail "a branch with a /: exit $rc, $(cat "$T/calls")"
gone check-fix-1-slash

# A check that a stop cut off left its worktree, and one more left only a folder.
g -C "$M" worktree add -q --detach "$M/.claude/worktrees/check-good" origin/good || exit 1
run good; rc=$?
[ $rc = 0 ] || fail "a left worktree check-good stopped the next check: exit $rc ($(cat "$T/err"))"
grep -q "removing the folder check-good" "$T/out" || fail "it does not say it removed the left folder: $(cat "$T/out")"
gone check-good
mkdir -p "$M/.claude/worktrees/check-bad" && touch "$M/.claude/worktrees/check-bad/left"
run bad; rc=$?
[ $rc = 5 ] || fail "a left folder check-bad (no worktree) stopped the next check: exit $rc ($(cat "$T/err"))"
gone check-bad

# A left folder that cannot be deleted. On Windows: a program of its own runs there (a tool:
# stopped, then the folder goes), and another program holds a file (not stopped: it may be an
# editor). Elsewhere a folder that cannot be written to stands in for the held file.
W=$M/.claude/worktrees
WIN=0; command -v powershell.exe >/dev/null && command -v cygpath >/dev/null && WIN=1
if [ $WIN = 1 ]; then
  mkdir -p "$W/check-good" && cp /usr/bin/sleep.exe "$W/check-good/sleep.exe" || fail "could not copy sleep.exe"
  "$W/check-good/sleep.exe" 300 &
  HOLDERS+=("$!")
  run good; rc=$?
  [ $rc = 0 ] || fail "a left folder where a tool still runs: exit $rc ($(cat "$T/err"))"
  grep -q "stopped what still ran in check-good: .*sleep" "$T/out" || fail "it does not say it stopped the tool: $(cat "$T/out")"
  gone check-good
fi
if [ $WIN = 1 ] || [ "$(id -u)" != 0 ]; then
  mkdir -p "$W/check-good/held" && echo x >"$W/check-good/held/f.txt"
  if [ $WIN = 1 ]; then
    rm -f "$T/holder"
    powershell.exe -NoProfile -Command "\$f = [IO.File]::Open('$(cygpath -w "$W/check-good/held/f.txt")', 'Open', 'Read', 'None'); [IO.File]::WriteAllText('$(cygpath -w "$T/holder")', \$PID); Start-Sleep 300" &
    wait_until 30 test -s "$T/holder" || fail "the holder of f.txt did not start in 30 s"
    HOLDERS+=("$(<"$T/holder")")
  else chmod a-w "$W/check-good/held"; fi
  run good; rc=$?
  [ $rc = 90 ] || fail "a left folder still in use: exit $rc, not 90"
  grep -q "could not delete the folder .*check-good: a file in it is still in use" "$T/err" ||
    fail "a left folder still in use is not named: $(cat "$T/err")"
  called "check check-good" && fail "the check ran while a left folder could not be deleted"
  [ $WIN = 0 ] || grep -q "(by .*powershell" "$T/err" || fail "the program that holds the file is not named: $(cat "$T/err")"
  if [ $WIN = 1 ]; then
    stop_holder "${HOLDERS[-1]}"
    wait_until 30 eval '{ : >>"$W/check-good/held/f.txt"; } 2>/dev/null' || fail "f.txt is still held 30 s after its holder was stopped"
  else chmod u+w "$W/check-good/held"; fi
  run good; rc=$?
  [ $rc = 0 ] || fail "once the file was free, the left folder still stopped the check: exit $rc ($(cat "$T/err"))"
  gone check-good
fi

# hooks.check_setup: first, in the same folder; a failing one stops before the check.
write_config "$M" "{ $CONFIG, \"check\": \"bash $T/tools/check.sh\", \"hooks\": { \"check_setup\": \"bash $T/tools/setup.sh\" } }"
run good; rc=$?
[ $rc = 0 ] || fail "with a setup: exit $rc ($(cat "$T/err"))"
[ "$(cat "$T/calls")" = $'setup check-good\ncheck check-good' ] || fail "the setup did not run first, in check-good: $(cat "$T/calls")"
echo 3 >"$T/setup-rc"
run good; rc=$?
[ $rc = 91 ] || fail "a failing setup: exit $rc, not 91"
called "check check-good" && fail "the check ran after its setup failed"
gone check-good
rm "$T/setup-rc"

# A branch with its own .claude/ap.json is checked with its own check and setup, not main's.
cat >"$T/tools/own.sh" <<EOF
echo "own \$(basename "\$PWD")" >>"$T/calls"
EOF
g -C "$M" switch -q -c own && mkdir -p "$M/.claude" &&
  echo "{ $CONFIG, \"check\": \"bash $T/tools/own.sh\", \"hooks\": { \"check_setup\": \"bash $T/tools/own.sh\" } }" >"$M/.claude/ap.json" &&
  g -C "$M" add -f .claude/ap.json && g -C "$M" commit -q -m own && g -C "$M" push -q origin own &&
  g -C "$M" switch -q develop && g -C "$M" fetch -q origin || exit 1
write_config "$M" "{ $CONFIG, \"check\": \"bash $T/tools/check.sh\" }"
run own; rc=$?
[ $rc = 0 ] || fail "a branch with its own settings: exit $rc ($(cat "$T/err"))"
[ "$(cat "$T/calls")" = $'own check-own\nown check-own' ] || fail "the branch's own check and setup did not run: $(cat "$T/calls")"
gone check-own

# What it cannot do.
run no-such-branch; rc=$?
[ $rc = 90 ] && grep -q "no origin/no-such-branch" "$T/err" || fail "an unknown branch: exit $rc, $(cat "$T/err")"
write_config "$M" "{ $CONFIG }"
run good; rc=$?
[ $rc = 90 ] && grep -q "no check set" "$T/err" || fail "no check set: exit $rc, $(cat "$T/err")"
run; rc=$?
[ $rc = 90 ] || fail "no branch: exit $rc, not 90"

[ "$FAILED" = 0 ] && echo "check-branch: ok"
exit "$FAILED"
