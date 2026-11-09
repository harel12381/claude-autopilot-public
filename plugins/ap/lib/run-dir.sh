# shellcheck shell=bash
# The files of the autopilot runs, for ap-run. Loaded with `source` from inside a git checkout.
# It sets:
#   COMMON  the repository's common .git folder (shared by every worktree)
#   MAIN    the main checkout (the folder of COMMON); the slot worktrees are in its .claude/worktrees/
#   DIR     <COMMON>/ap-autopilot, where the runs' files are (made here)
#   LOCK    the lock that hold, end and stop-in take (dirlock.sh)
#   FRESH_MIN  how long a run goes on with no sign of life (720 minutes: a closed manager session
#           never ends its run)
# and defines usage, alive, going_on, locked, stop_file and remote_branches.

# shellcheck source=plugins/ap/lib/dirlock.sh
source "$(dirname "${BASH_SOURCE[0]}")/dirlock.sh"
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  { echo "ap-run: $PWD is not inside a git repository" >&2; exit 2; }
MAIN=$(dirname "$COMMON")
DIR=$COMMON/ap-autopilot LOCK=$COMMON/ap-autopilot/lock
FRESH_MIN=${AP_RUN_FRESH_MIN:-720}
mkdir -p "$DIR"

usage() {
  echo "usage: ap-run start [--alone] | alive <run> | hold <run> <slot> [<issue>] | free <run> <slot> | others <run> | stop-previews <run>" \
    "| cleanup <run> [args] | end <run> | list | stop-in <run> <minutes> | stop-left <run>" \
    "| stop-wait <run> | stop-clear <run>" >&2
  exit 2
}
alive() { # run id: it goes on (an error when it was never started, or has ended)
  [ -f "$DIR/run-$1" ] || { echo "ap-run: no run $1 (start one with: ap-run start)" >&2; exit 1; }
  touch "$DIR/run-$1"
}
going_on() { # run id: true while the run has not ended and was active in the last FRESH_MIN minutes
  [ -f "$DIR/run-$1" ] && [ -z "$(find "$DIR/run-$1" -mmin +"$FRESH_MIN")" ]
}
locked() { # what for: takes the lock until the script ends
  trap 'dirlock_free "$LOCK"' EXIT
  dirlock_take "$LOCK" "$1 (since $(date +%H:%M:%S))" 600 0.2 "ap-run: waiting for" >&2
}
stop_file() { echo "$DIR/stop-$1"; } # run id: its stop-in time (run-stop.sh)
remote_branches() { # the branches on origin, as the last fetch left them, one per line
  git -C "$MAIN" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -vx HEAD || true
}
