#!/usr/bin/env bash
# Tests ap-run in a throwaway repository with slot worktrees, and fake project hooks (set in a
# temporary .claude/ap.json) that only write down how and where they were called:
#   - the end of a run removes only the worktrees it holds, with their previews; a slot that a newer
#     run took over stays, and so do that run's previews and young test runs;
#   - a worktree with work that is not committed is never removed;
#   - with no other run going on, the end stops every slot preview and every test run, and
#     removes the check worktrees (check-*) a check left; while another run goes on, it keeps them;
#   - the end stops the test runs before it removes the worktrees, and a file still in use does
#     not leave a worktree half removed: its holder is stopped, or the folder is named, and the
#     next `hold` of that slot deletes it; a folder git does not know, that no end left, is never
#     deleted;
#   - a run not seen for 12 hours (its manager session was closed) does not go on; `alive` makes
#     a run that still works (one helper at a time, no slots) go on;
#   - hold names an unknown run as an error, and warns when it takes a slot over;
#   - the next worktree of a slot's queue (ap-1b): held and removed like ap-1; hold keeps the
#     issue open in a worktree (issue-<s>) until free, a new hold or the end;
#   - cleanup: --older-than 90 while another run goes on, a caller's --older-than goes through
#     once, and the hook's exit code (3: the disk is low) comes back, also from end;
#   - with no hooks set, every step still works and says there is nothing to do;
#   - the stop-in commands work through ap-run (tests/run-stop-test.sh tests them), and end
#     clears the stop-in time.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
HOLDERS=() # the processes that hold a file open, stopped at the end
stop_holder() { # pid: of Git Bash, or of Windows
  kill "$1" 2>/dev/null || taskkill //F //PID "$1" >/dev/null 2>&1 || true
}
trap 'for p in "${HOLDERS[@]}"; do stop_holder "$p"; done; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
FAILED=0
fail() { echo "run-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b develop "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
common=$(git -C "$M" rev-parse --path-format=absolute --git-common-dir)
# .claude/ap.json is the project's own file here, not work in a worktree.
echo ".claude/" >>"$common/info/exclude"
for s in 1 2 3; do g -C "$M" worktree add -q "$M/.claude/worktrees/ap-$s" -b "b$s" || exit 1; done
mkdir "$T/tools"
for t in preview-slot agent-cleanup; do
  printf '#!/usr/bin/env bash\necho "%s $(basename "$PWD")${*:+ $*}" >>"%s/calls"\n' "$t" "$T" >"$T/tools/$t.sh"
done
# The worktrees there while the test runs were stopped (before they are removed), and the exit
# code the test asks for.
cat >>"$T/tools/agent-cleanup.sh" <<EOF
echo \$(ls "$M/.claude/worktrees") >>"$T/trees"
exit \$(cat "$T/rc" 2>/dev/null || echo 0)
EOF
P="bash $T/tools/preview-slot.sh"
HOOKS="{ \"repo\": \"o/n\", \"owner\": \"O\", \"main_branch\": \"develop\", \"hooks\": {
  \"previews_clear\": \"$P clear\",
  \"slot_release\": \"$P stop && $P release\",
  \"cleanup\": \"bash $T/tools/agent-cleanup.sh\" } }"
write_config "$M" "$HOOKS"
run() { (cd "$M" && ap-run "$@" >"$T/out" 2>"$T/err"); }
called() { grep -qxF -- "$1" "$T/calls" 2>/dev/null; }

run start && A=$(<"$T/out") || fail "start failed: $(cat "$T/err")"
run hold "$A" 1 && run hold "$A" 2 || fail "hold failed: $(cat "$T/err")"
run hold no-such-run 1 && fail "hold took a slot for a run that was never started"
run start && B=$(<"$T/out")
[ "$A" != "$B" ] || fail "two runs got the same id: $A"
run hold "$B" 2 || fail "the new run could not take slot 2"
grep -q "held by the run $A" "$T/err" || fail "taking over a slot of a run that goes on gives no warning: $(cat "$T/err")"
run others "$A"; [ "$(<"$T/out")" = "$B" ] || fail "others of $A: '$(<"$T/out")', not $B"

# The queue's next worktree of slot 1, and the issue open in each worktree.
g -C "$M" worktree add -q "$M/.claude/worktrees/ap-1b" -b b1b || exit 1
run hold "$A" 1b 47 || fail "hold of the queue's worktree 1b failed: $(cat "$T/err")"
[ "$(cat "$common/ap-autopilot/issue-1b" 2>/dev/null)" = 47 ] || fail "hold 1b 47 did not keep issue 47 open in ap-1b"
grep -q "slot 1b: held by the run $A, issue #47" "$T/out" || fail "hold does not name the issue: $(cat "$T/out")"
for bad in 1bb b x1 1B "1 2"; do run hold "$A" "$bad" && fail "hold took the slot '$bad'"; done
run hold "$A" 1 5 abc && fail "hold took the issue 'abc'"
run hold "$A" 1 x && fail "hold took the issue 'x'"
run free "$B" 1b && fail "free of a slot that another run holds passed"
run free "$A" 1b || fail "free failed: $(cat "$T/err")"
[ -e "$common/ap-autopilot/issue-1b" ] && fail "free left the issue open in ap-1b"
run hold "$A" 1b 48 && run hold "$A" 1b && [ ! -e "$common/ap-autopilot/issue-1b" ] ||
  fail "a hold with no issue did not clear the issue of the last helper"
run hold "$A" 1b 49

# The old run ends while the new one works in ap-2.
g -C "$M" worktree add -q --detach "$M/.claude/worktrees/check-left" || exit 1
: >"$T/calls" >"$T/trees"
run end "$A" || fail "end failed: $(cat "$T/err")"
[ -d "$M/.claude/worktrees/check-left" ] || fail "the end of a run removed a check worktree while another run goes on"
[ -d "$M/.claude/worktrees/ap-1" ] && fail "the end of a run did not remove its own worktree ap-1"
[ -d "$M/.claude/worktrees/ap-1b" ] && fail "the end of a run did not remove the queue's worktree ap-1b"
[ -e "$common/ap-autopilot/issue-1b" ] && fail "the end of a run left the issue open in ap-1b"
called "preview-slot ap-1b stop" || fail "the preview of ap-1b was not stopped: $(cat "$T/calls")"
[ -d "$M/.claude/worktrees/ap-2" ] || fail "the end of a run removed ap-2, which a newer run holds"
called "preview-slot ap-1 stop" && called "preview-slot ap-1 release" || fail "the preview of ap-1 was not stopped: $(cat "$T/calls")"
grep -q "ap-2" "$T/calls" && fail "the end of a run touched the preview of ap-2, which a newer run holds"
called "preview-slot main clear" && fail "the end of a run stopped every slot preview while another run goes on"
called "agent-cleanup main --older-than 90" || fail "with another run going on, the cleanup was not --older-than 90: $(cat "$T/calls")"
head -1 "$T/trees" | grep -qw "ap-1" || fail "the end removed ap-1 before it stopped the test runs: $(cat "$T/trees")"
tail -1 "$T/out" | grep -qxF "other runs: $B" || fail "the end does not name the run that goes on: $(cat "$T/out")"

# The last run ends: a worktree with work not committed stays; then everything is cleaned up.
run hold "$B" 3
echo work >"$M/.claude/worktrees/ap-3/new.txt" && g -C "$M/.claude/worktrees/ap-3" add new.txt
: >"$T/calls" >"$T/trees"
run end "$B" || fail "the end of the last run failed: $(cat "$T/err")"
[ -d "$M/.claude/worktrees/check-left" ] && fail "the end of the last run kept the check worktree check-left"
git -C "$M" worktree list | grep -q "/check-left " && fail "git still lists check-left after the end of the last run"
grep -q "removed the check worktree check-left" "$T/out" || fail "the end does not say it removed check-left: $(cat "$T/out")"
[ -d "$M/.claude/worktrees/ap-2" ] && fail "the last run's end did not remove ap-2"
[ -f "$M/.claude/worktrees/ap-3/new.txt" ] || fail "a worktree with work not committed was removed"
grep -q "kept the worktree ap-3: .*not committed" "$T/err" || fail "a kept worktree is not named with its reason: $(cat "$T/err")"
called "preview-slot main clear" && called "agent-cleanup main" || fail "with no other run, the end did not clean up everything: $(cat "$T/calls")"
head -1 "$T/trees" | grep -qw "ap-2" || fail "the last run's end removed ap-2 before it stopped the test runs: $(cat "$T/trees")"
grep -q "ap-[23]" "$T/calls" && fail "with no other run, the end stopped slot previews one by one as well as with clear"
tail -1 "$T/out" | grep -qxF "other runs: none" || fail "the end does not say no other run goes on: $(cat "$T/out")"

# A run whose manager session was closed 13 hours ago does not go on; alive makes it go on.
run start && C=$(<"$T/out") && run start && D=$(<"$T/out")
backdate "$common/ap-autopilot/run-$C" $((13 * 60))
run others "$D"; [ -z "$(<"$T/out")" ] || fail "a run not seen for 13 hours still goes on: $(<"$T/out")"
run list; grep -q "run $C .*not seen for 12 hours" "$T/out" || fail "list does not show the old run as not seen: $(cat "$T/out")"
run alive "$C" || fail "alive failed: $(cat "$T/err")"
run others "$D"; [ "$(<"$T/out")" = "$C" ] || fail "a run that said alive does not go on: '$(<"$T/out")'"
run alive no-such-run && fail "alive passed for a run that was never started"
# stop-previews while another run goes on: only this run's slot.
run hold "$D" 3 && : >"$T/calls" && run stop-previews "$D"
called "preview-slot ap-3 stop" && ! called "preview-slot main clear" || fail "stop-previews with another run going on: $(cat "$T/calls")"
# cleanup: --older-than 90 while another run goes on; the caller's own --older-than goes through
# once; the full cleanup when no other run goes on; the hook's exit code comes back.
: >"$T/calls" && run cleanup "$D" --min-free-gb 5
called "agent-cleanup main --min-free-gb 5 --older-than 90" || fail "cleanup with another run going on: $(cat "$T/calls")"
: >"$T/calls" && run cleanup "$D" --older-than 30 --min-free-gb 5
called "agent-cleanup main --older-than 30 --min-free-gb 5" || fail "a caller's --older-than did not go through once: $(cat "$T/calls")"
echo 3 >"$T/rc"; run cleanup "$D"; rc=$?; rm "$T/rc"
[ $rc = 3 ] || fail "cleanup did not give the hook's exit code 3 (low disk): $rc"
run start && E=$(<"$T/out") && run end "$C" && run end "$E"
: >"$T/calls" && run cleanup "$D" --min-free-gb 5
called "agent-cleanup main --min-free-gb 5" || fail "cleanup with no other run: $(cat "$T/calls")"
: >"$T/calls" && run cleanup "$D" --older-than 30
called "agent-cleanup main --older-than 30" || fail "a caller's --older-than with no other run: $(cat "$T/calls")"
# start deletes the files of runs not seen for 24 hours.
backdate "$common/ap-autopilot/run-$C" $((25 * 60))
run start; run list; grep -q "run $C " "$T/out" && fail "start kept a run not seen for 25 hours"

# A file in a worktree is still in use when the run ends. Windows cannot delete it, and git
# fails half way: the worktree is gone from its list, the folder is not. On Windows: in ap-4 a
# program in the folder runs (stopped), in ap-5 another program names the folder (not stopped:
# it may be an editor). Elsewhere a file in use can be deleted, so a folder that cannot be
# written to stands in for ap-5.
WIN=0; command -v powershell.exe >/dev/null && command -v cygpath >/dev/null && WIN=1
W=$M/.claude/worktrees
echo "build/" >>"$common/info/exclude"
run start && H=$(<"$T/out")
for s in 4 5; do
  g -C "$M" worktree add -q "$W/ap-$s" -b "b$s" && mkdir "$W/ap-$s/build" && echo x >"$W/ap-$s/build/f.txt"
  run hold "$H" "$s"
done
if [ $WIN = 1 ]; then
  cp /usr/bin/sleep.exe "$W/ap-4/build/sleep.exe" || fail "could not copy sleep.exe"
  "$W/ap-4/build/sleep.exe" 300 &
  HOLDERS+=("$!")
  rm -f "$T/holder"
  powershell.exe -NoProfile -Command "\$f = [IO.File]::Open('$(cygpath -w "$W/ap-5/build/f.txt")', 'Open', 'Read', 'None'); [IO.File]::WriteAllText('$(cygpath -w "$T/holder")', \$PID); Start-Sleep 300" &
  wait_until 30 test -s "$T/holder" || fail "the holder of f.txt did not start in 30 s"
  HOLDERS+=("$(<"$T/holder")")
elif [ "$(id -u)" != 0 ]; then chmod a-w "$W/ap-5/build"; fi
run end "$H"
if [ $WIN = 1 ]; then
  [ -d "$W/ap-4" ] && fail "a worktree where a program of its own still runs was not removed: $(cat "$T/err")"
  grep -q "stopped what still ran in ap-4: .*sleep" "$T/out" || fail "the end does not say which process it stopped: $(cat "$T/out")"
fi
if [ $WIN = 1 ] || [ "$(id -u)" != 0 ]; then
  grep -q "kept the folder ap-5: .*still in use" "$T/err" || fail "a folder still in use is not named: $(cat "$T/err")"
  [ $WIN = 0 ] || grep -q "kept the folder ap-5: .*powershell.exe" "$T/err" || fail "the process that names the folder is not named: $(cat "$T/err")"
  [ $WIN = 0 ] || ! grep -q "stopped .*powershell" "$T/out" || fail "the end stopped a program that is no build or test tool"
  run start && G=$(<"$T/out")
  run hold "$G" 5 && fail "hold took slot 5 while the folder left there is still in use"
  if [ $WIN = 1 ]; then
    # Windows lets go of the file a moment after the holder ends: waited for, not timed.
    stop_holder "${HOLDERS[1]}"
    wait_until 30 eval '{ : >>"$W/ap-5/build/f.txt"; } 2>/dev/null' ||
      fail "f.txt is still held 30 s after its holder was stopped"
  else chmod u+w "$W/ap-5/build"; fi
  run hold "$G" 5 || fail "hold did not delete the folder left in slot 5: $(cat "$T/err")"
  [ -d "$W/ap-5" ] && fail "hold left the folder of slot 5, which git no longer knows"
fi
# A folder git does not know, that no end left: hold deletes nothing, and takes no slot.
mkdir -p "$W/ap-6" && echo mine >"$W/ap-6/notes.txt"
run start && G=$(<"$T/out")
run hold "$G" 6 && fail "hold took slot 6, where a folder git does not know is"
[ -f "$W/ap-6/notes.txt" ] || fail "hold deleted a folder that no end of a run left"

# No hooks set: every step works, says there is nothing to do, and calls nothing.
write_config "$M" '{ "repo": "o/n", "owner": "O", "main_branch": "develop" }'
g -C "$M" worktree add -q "$W/ap-7" -b b7 || fail "could not add ap-7"
run start && N=$(<"$T/out") && run hold "$N" 7 && : >"$T/calls"
run cleanup "$N" || fail "cleanup with no hook failed: $(cat "$T/err")"
grep -q "no hooks.cleanup" "$T/out" || fail "cleanup with no hook does not say so: $(cat "$T/out")"
run end "$N" || fail "end with no hooks failed: $(cat "$T/err")"
grep -q "no hooks.slot_release" "$T/out" || fail "end with no previews hook (other runs go on) does not say so: $(cat "$T/out")"
[ -d "$W/ap-7" ] && fail "end with no hooks did not remove ap-7"
[ -s "$T/calls" ] && fail "a hook ran that is not set: $(cat "$T/calls")"
write_config "$M" "$HOOKS"

# The cleanup's exit code 3 (low disk) comes back from end too.
run start && N=$(<"$T/out")
echo 3 >"$T/rc"; run end "$N"; rc=$?; rm "$T/rc"
[ $rc = 3 ] || fail "end did not give the cleanup's exit code 3: $rc"

# The stop-in commands, through ap-run as the manager runs them; end clears the time.
run start && S=$(<"$T/out")
run stop-in "$S" 08 && run stop-left "$S"; [ "$(<"$T/out")" = "8 of 8" ] || fail "stop-in: '$(<"$T/out")' $(cat "$T/err")"
run stop-in "$S" x && fail "stop-in took 'x' minutes"
run end "$S" && run stop-wait "$S"; [ "$(<"$T/out")" = cancelled ] || fail "end left the stop-in time: '$(<"$T/out")'"

[ $FAILED = 0 ] && echo "ap-run: ok"
exit $FAILED
