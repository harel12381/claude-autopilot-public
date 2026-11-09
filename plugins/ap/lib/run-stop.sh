# shellcheck shell=bash
# The time a run must stop at (the stop-in command of a run). Loaded with `source` by ap-run,
# after run-dir.sh; it defines run_stop, which takes ap-run's stop-* commands:
#
#   ap-run stop-in <run> <minutes>  # the run stops in that many minutes
#   ap-run stop-left <run>          # none | up | <minutes left> of <minutes>
#   ap-run stop-wait <run>          # waits for that time: up | again | cancelled
#   ap-run stop-clear <run>         # another stop replaced stop-in
#
# The manager is woken only by an event, so it runs `stop-wait` in the background: it sleeps until
# that time, or at most 100 minutes (a background command may run 2 hours), then says what
# `stop-left` says: `up` (stop now), `again` (not yet: run it again) or `cancelled` (a newer stop
# cleared it). A newer stop-in makes the manager stop the old wait itself. The end of a run
# (`ap-run end`) clears the time too.
#
# The time is in <.git>/ap-autopilot/stop-<run>: "<when stop-in ran> <when the run stops>", in
# seconds since 1970.

STOP_MINUTE=60
STOP_WAIT_MAX=${AP_RUN_WAIT_MAX:-6000} # stop-wait's longest wait, in seconds

stop_left() { # run id: where the run is in its stop-in time (see the top)
  local from to
  read -r from to 2>/dev/null <"$(stop_file "$1")" && [ -n "$to" ] || { echo none; return; }
  if [ "$EPOCHSECONDS" -ge "$to" ]; then echo up
  else echo "$(((to - EPOCHSECONDS + STOP_MINUTE - 1) / STOP_MINUTE)) of $(((to - from) / STOP_MINUTE))"; fi
}

run_stop() { # ap-run's arguments, from stop-in, stop-left, stop-wait or stop-clear on
  local min to wait
  case "$1" in
    stop-in)
      [ $# = 3 ] || usage
      case $3 in '' | *[!0-9]*) usage ;; esac
      min=$((10#$3)) # 08 is 8, not a bad octal number
      [ "$min" -gt 0 ] || usage
      alive "$2"
      locked "stop-in $2" # not while the run's end clears it
      to=$((EPOCHSECONDS + min * STOP_MINUTE))
      echo "$EPOCHSECONDS $to" >"$(stop_file "$2")"
      echo "the run $2 stops at $(printf '%(%H:%M)T' "$to")" ;;
    stop-left)
      [ $# = 2 ] || usage
      stop_left "$2" ;;
    stop-wait)
      [ $# = 2 ] || usage
      read -r _ to 2>/dev/null <"$(stop_file "$2")" || { echo cancelled; return 0; }
      wait=$((to - EPOCHSECONDS)); [ "$wait" -le "$STOP_WAIT_MAX" ] || wait=$STOP_WAIT_MAX
      [ "$wait" -le 0 ] || sleep "$wait"
      case $(stop_left "$2") in up) echo up ;; none) echo cancelled ;; *) echo again ;; esac ;;
    stop-clear)
      [ $# = 2 ] || usage
      rm -f "$(stop_file "$2")" ;;
    *) usage ;;
  esac
}
