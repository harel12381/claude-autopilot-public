#!/usr/bin/env bash
# Tests ap-schedule in a throwaway repository, with a fake `schtasks`, `crontab` and `claude`
# first on PATH (the real scheduler is never touched):
#   - add writes the schedule, its start script and the scheduler's entry: Task Scheduler (daily,
#     or weekly on the days) and cron (the days as numbers); add again replaces it;
#   - the start script goes to the main checkout and starts a background session in bypass
#     permissions that runs `/ap:schedule fire <name>` (run through `now`);
#   - the entry's name has a hash of the checkout's path: a second checkout with the same folder
#     name gets its own entry, and removing one leaves the other;
#   - on Windows the task may run on battery (Set-ScheduledTask through PowerShell); when that
#     fails, add says what to untick;
#   - fire starts the run and prints `run <id>` and the run arguments; while another run goes on
#     it prints that run, exit 3, starts none, and writes it in the log; two fires at once start
#     one run;
#   - list shows each schedule, its entry and its last start; remove drops both;
#   - wrong names, times and days: exit 2; an unknown schedule: exit 1.
#
#   bash tests/schedule-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "schedule-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b main "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
S=$M/.git/ap-schedule

mkdir "$T/bin"
cat >"$T/bin/schtasks" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/schtasks-calls"
case \$1 in
  /Create) tn=\$4; touch "$T/task-\$tn" ;;
  /Query) [ -f "$T/task-\$3" ] ;;
  /Delete) rm "$T/task-\$4" ;;
esac
EOF
cat >"$T/bin/crontab" <<EOF
#!/usr/bin/env bash
if [ "\$1" = -l ]; then cat "$T/crontab" 2>/dev/null; else cat >"$T/crontab"; fi
EOF
cat >"$T/bin/claude" <<EOF
#!/usr/bin/env bash
{ pwd; printf '%s\n' "\$@"; } >"$T/claude-args"
echo "session ab12 started"
EOF
cat >"$T/bin/powershell" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/ps-calls"
[ -z "\${FAKE_PS_FAIL:-}" ]
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
echo "0 1 * * * echo mine" >"$T/crontab"

sched() { (cd "$M" && ap-schedule "$@"); }
code() { local rc=0; sched "$@" >"$T/out" 2>"$T/err" || rc=$?; echo "$rc"; }
runs() { find "$M/.git/ap-autopilot" -name 'run-*' 2>/dev/null | wc -l | tr -d ' '; }
end_runs() { local f; for f in "$M/.git/ap-autopilot"/run-*; do [ -f "$f" ] && (cd "$M" && ap-run end "${f##*/run-}" >/dev/null 2>&1); done; }

# Task Scheduler.
export AP_SCHEDULE_SYSTEM=schtasks
[ "$(code add nightly --at 02:00 -- X2 stop-in 300)" = 0 ] || fail "add: $(cat "$T/err")"
task=$(awk '$1 == "/Create" { print $4; exit }' "$T/schtasks-calls")
[[ $task =~ ^ap-main-[0-9a-f]{6}-nightly$ ]] || fail "add: the task's name has no hash of the checkout: $task"
grep -qF "Set-ScheduledTask -TaskName '$task' -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)" "$T/ps-calls" ||
  fail "add: the task may not run on battery: $(cat "$T/ps-calls" 2>/dev/null)"
grep -q "AC power" "$T/out" && fail "add: it says to untick AC power, though PowerShell set it"
[ "$(FAKE_PS_FAIL=1 code add nightly --at 02:00 -- X2 stop-in 300)" = 0 ] && grep -q 'untick "Start the task only if the computer is on AC power"' "$T/out" ||
  fail "add with no PowerShell: it does not say what to untick: $(cat "$T/out")"

# A second checkout with the same folder name: its own entry, and removing it leaves ours.
M2=$T/other/main
g init -q -b main "$M2" && g -C "$M2" commit -q --allow-empty -m init || exit 1
(cd "$M2" && ap-schedule add nightly --at 02:00 -- X1 >/dev/null) || fail "second checkout: add failed"
task2=$(awk '$1 == "/Create" { t = $4 } END { print t }' "$T/schtasks-calls")
[ "$task2" != "$task" ] && [[ $task2 =~ ^ap-main-[0-9a-f]{6}-nightly$ ]] || fail "second checkout: the same entry $task2"
(cd "$M2" && ap-schedule remove nightly >/dev/null) || fail "second checkout: remove failed"
[ -e "$T/task-$task" ] && [ ! -e "$T/task-$task2" ] || fail "second checkout: remove took the wrong entry"
grep -q "^/Create /F /TN $task /SC DAILY /ST 02:00 /TR " "$T/schtasks-calls" || fail "add: not a daily task: $(cat "$T/schtasks-calls")"
grep -qE 'ap-schedule.nightly\.sh' "$T/schtasks-calls" || fail "add: the task does not run the start script: $(cat "$T/schtasks-calls")"
[ "$(sed -n 2p "$S/nightly.conf")" = "X2 stop-in 300" ] || fail "add: the run arguments are not kept: $(cat "$S/nightly.conf")"
[ "$(code add nightly --at 03:30 --days mon,fri -- bugs)" = 0 ] || fail "add again: $(cat "$T/err")"
grep -q "^/Create /F /TN $task /SC WEEKLY /D MON,FRI /ST 03:30 " "$T/schtasks-calls" || fail "add again: not weekly on MON,FRI: $(cat "$T/schtasks-calls")"
[ "$(sed -n 2p "$S/nightly.conf")" = "bugs" ] || fail "add again: the arguments were not replaced"

# The start script, run as the scheduler would.
[ "$(code now nightly)" = 0 ] || fail "now: $(cat "$T/err")"
want=$(printf '%s\n' "$(cd "$M" && pwd)" --bg --permission-mode bypassPermissions -n "ap: nightly" "/ap:schedule fire nightly")
[ "$(cat "$T/claude-args" 2>/dev/null)" = "$want" ] || fail "now: claude got: $(cat "$T/claude-args" 2>/dev/null)"
grep -q "session ab12 started" "$S/nightly.log" || fail "now: the session's words are not in the log"

# fire: the arguments, or the run that goes on.
[ "$(code fire nightly)" = 0 ] || fail "fire: $(cat "$T/out") $(cat "$T/err")"
run=$(sed -n 's/^run //p' "$T/out")
[ -n "$run" ] && [ -f "$M/.git/ap-autopilot/run-$run" ] && [ "$(sed -n 2p "$T/out")" = bugs ] ||
  fail "fire: no run started, or not its arguments: $(cat "$T/out")"
[ "$(code fire nightly)" = 3 ] && [ "$(cat "$T/out")" = "$run" ] || fail "fire beside a run: $(cat "$T/out") $(cat "$T/err")"
[ "$(runs)" = 1 ] || fail "fire beside a run: it started a second run"
grep -q "not started: another run goes on ($run)" "$S/nightly.log" || fail "fire beside a run: not in the log"
end_runs
# Two fires at once: one run starts, the other says it goes on.
(cd "$M" && ap-schedule fire nightly >"$T/f1" 2>&1; echo $? >"$T/f1.rc") &
(cd "$M" && ap-schedule fire nightly >"$T/f2" 2>&1; echo $? >"$T/f2.rc") &
wait
[ "$(cat "$T/f1.rc" "$T/f2.rc" | sort | paste -sd' ' -)" = "0 3" ] && [ "$(runs)" = 1 ] ||
  fail "two fires at once: exits $(cat "$T/f1.rc" "$T/f2.rc" | paste -sd' ' -), $(runs) runs: $(cat "$T/f1" "$T/f2")"
end_runs

[ "$(code list)" = 0 ] && grep -qE "^nightly	03:30 mon,fri	/ap:run bugs	entry set	last start [0-9]{4}-" "$T/out" ||
  fail "list: $(cat "$T/out") $(cat "$T/err")"
[ "$(code remove nightly)" = 0 ] || fail "remove: $(cat "$T/err")"
[ ! -e "$T/task-$task" ] && [ ! -e "$S/nightly.conf" ] || fail "remove: the task or the schedule is still there"
[ "$(code list)" = 0 ] && grep -qx "no schedules" "$T/out" || fail "list after remove: $(cat "$T/out")"

# cron.
export AP_SCHEDULE_SYSTEM=cron
[ "$(code add weekdays --at 02:05 --days mon,tue,sun -- X3)" = 0 ] || fail "cron add: $(cat "$T/err")"
grep -qx "0 1 \* \* \* echo mine" "$T/crontab" || fail "cron add: the owner's own line is gone: $(cat "$T/crontab")"
grep -qE "^5 2 \* \* 1,2,0 bash -l .*weekdays\.sh # ap-main-[0-9a-f]{6}-weekdays$" "$T/crontab" || fail "cron add: $(cat "$T/crontab")"
[ "$(code add daily --at 23:00 -- )" = 0 ] || fail "cron add daily: $(cat "$T/err")"
grep -qE "^0 23 \* \* \* bash -l .*daily\.sh # ap-main-[0-9a-f]{6}-daily$" "$T/crontab" || fail "cron add daily: $(cat "$T/crontab")"
[ "$(code remove weekdays)" = 0 ] || fail "cron remove: $(cat "$T/err")"
grep -q weekdays "$T/crontab" && fail "cron remove: the line is still there: $(cat "$T/crontab")"
[ "$(grep -c . "$T/crontab")" = 2 ] || fail "cron remove: other lines changed: $(cat "$T/crontab")"

# Wrong use.
for bad in "add Night --at 02:00 -- X2" "add n --at 2:00 -- X2" "add n --at 02:00 --days monday -- X2" \
  "add n --at 02:00 X2" "fire" "list x"; do
  # shellcheck disable=SC2086
  [ "$(code $bad)" = 2 ] || fail "wrong use is not exit 2: $bad"
done
[ "$(code fire nothing)" = 1 ] || fail "an unknown schedule is not exit 1"

[ "$FAILED" = 0 ] && echo "ap-schedule: ok"
exit "$FAILED"
