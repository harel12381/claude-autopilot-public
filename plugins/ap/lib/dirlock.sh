# shellcheck shell=bash
# The folder lock of ap-git-sync and ap-run. Loaded with `source`; it only defines functions.
#
# A lock is a folder: mkdir makes one or fails, in one step. In it, the file owner holds one line,
# "<pid> <text>".
#
# A lock whose process is gone (or a zombie) was left by a killed run: it is taken over. So is a lock older than
# its age limit (a run that hangs), when the caller gives one, and a lock with no owner for 60 s (a
# run killed between mkdir and writing its owner). One run at a time judges a lock (the
# <lock>.takeover folder), and looks at its owner again before removing it, so a lock taken
# meanwhile is never removed. $BASHPID is the owner: take and free a lock in the same process.

# shellcheck source=plugins/ap/lib/proc-tree.sh
source "$(dirname "${BASH_SOURCE[0]}")/proc-tree.sh" # pid_runs

# lock: its owner line, empty while it is written or once the lock is gone (never a failure: a
# caller with set -e would stop there)
dirlock_owner() { cat "$1/owner" 2>/dev/null || true; }

dirlock_mtime() { # path: its time in seconds since 1970 (GNU stat, then BSD stat), else now
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo "$EPOCHSECONDS"
}

dirlock_dead() { # lock, age limit in s (0: none): true when nobody holds it any more
  local o pid age
  o=$(dirlock_owner "$1"); pid=${o%% *}
  age=$(( EPOCHSECONDS - $(dirlock_mtime "$1") ))
  { [ -n "$pid" ] && ! pid_runs "$pid"; } || { [ -z "$pid" ] && [ $age -gt 60 ]; } \
    || { [ "$2" -gt 0 ] && [ $age -gt "$2" ]; }
}

dirlock_try() { # lock, owner text, age limit: 0 when this process holds it now
  if ! mkdir "$1" 2>/dev/null; then
    if dirlock_dead "$1" "$3" && mkdir "$1.takeover" 2>/dev/null; then
      if [ -d "$1" ] && dirlock_dead "$1" "$3"; then
        echo "Took over ${1##*/}, left by a run that ended or hangs: $(dirlock_owner "$1")"
        rm -rf "$1"
      fi
      rmdir "$1.takeover"
      mkdir "$1" 2>/dev/null || return 1 # a lock just taken over is taken at once
    else
      # Left by a run killed while it judged.
      [ -d "$1.takeover" ] && [ -n "$(find "$1.takeover" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rm -rf "$1.takeover"
      return 1
    fi
  fi
  echo "$BASHPID $2" >"$1/owner"
}

# lock, owner text, age limit, seconds between tries, words: waits until this process holds it.
# While it waits, it says once "<words> <the owner's text>" (on stdout, as the takeover).
dirlock_take() {
  local said=0 o
  until dirlock_try "$1" "$2" "$3"; do
    o=$(dirlock_owner "$1")
    if [ $said = 0 ] && [ -n "$o" ]; then echo "$5 ${o#* }"; said=1; fi
    sleep "$4"
  done
}

dirlock_free() { # lock: removes it when this process holds it
  local o; o=$(dirlock_owner "$1")
  [ "${o%% *}" = "$BASHPID" ] && rm -rf "$1"
  return 0
}
