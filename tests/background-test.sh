#!/usr/bin/env bash
# Tests ap-background with a small tree of native programs (a python that starts another
# python, as a dev server starts its compiler):
#   - when the shell that started it is killed (as an agent stops a background task), the whole
#     tree stops within a few seconds;
#   - when it is stopped itself (TERM), the whole tree stops;
#   - a command that ends by itself ends it, with the command's exit code;
#   - stop_tree of a process that is gone already says nothing.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export AP_BACKGROUND_WATCH_S=1

fails=0
fail() { echo "background-test: $*"; fails=$((fails + 1)); }

PY=
for p in python3 python; do "$p" -c 'import subprocess' >/dev/null 2>&1 && { PY=$p; break; }; done
[ -n "$PY" ] || { echo "background-test: needs Python 3 (python3 or python) for its program tree" >&2; exit 1; }

# Writes "<its pid> <its child's pid>" (the operating system's ids: Windows ones on Windows) and
# waits, as its child does.
cat >"$T/tree.py" <<'EOF'
import os, subprocess, sys, time
kid = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
with open(sys.argv[1] + ".tmp", "w") as f:
    f.write(f"{os.getpid()} {kid.pid}\n")
os.replace(sys.argv[1] + ".tmp", sys.argv[1])
time.sleep(120)
EOF
WIN=; command -v cygpath >/dev/null && WIN=1
running() { # pids files: those of their pids that still run (one process list for all)
  local list pid
  # On Windows the Windows ids of every process, from Git Bash's own list (`ps -W`, its 4th column;
  # a status letter may come first), which is quick also on a busy computer.
  if [ -n "$WIN" ]; then list=$(ps -W | awk 'NR > 1 { if ($1 !~ /^[0-9]+$/) { $1 = ""; $0 = $0 } print $4 }')
  else list=$(ps -eo pid=,stat= | awk '$2 !~ /^Z/ { print $1 }'); fi # a zombie has ended
  for pid in $(cat "$@"); do grep -qx " *$pid" <<<"$list" && echo "$pid"; done
}
start() { # pids file, the stop: starts a tree through ap-background the way the stop needs
  # `; :` keeps bash from replacing itself with the script, so the shell is its parent.
  if [ "$2" = shell ]; then bash -c "ap-background $PY '$T/tree.py' '$1'; :" >"$1.out" 2>&1 &
  else ap-background "$PY" "$T/tree.py" "$1" >"$1.out" 2>&1 &
  fi
  echo $! >"$1.top"
}
started() { # pids file: waits until the tree runs
  wait_until 30 test -s "$1" && return 0
  fail "the tree did not start: $(cat "$1.out")"; return 1
}

# 1. The shell is killed, as an agent stops a background task. 2. It is stopped itself (TERM).
# Both at once: each tree then has 20 s to stop.
start "$T/shell" shell; start "$T/TERM" TERM
for how in shell TERM; do
  started "$T/$how" || continue
  top=$(cat "$T/$how.top")
  if [ $how = shell ]; then kill -9 "$top"; else kill -TERM "$top"; fi
  wait "$top" 2>/dev/null # without the shell's "Killed" line
done
files=(); for how in shell TERM; do [ -s "$T/$how" ] && files+=("$T/$how"); done
left=
for _ in $(seq 40); do
  [ ${#files[@]} = 0 ] && break
  left=$(running "${files[@]}"); [ -z "$left" ] && break
  sleep 0.5
done
if [ -n "$left" ]; then
  fail "a tree still runs after its stop: $(echo $left)"
  for pid in $left; do if [ -n "$WIN" ]; then taskkill //F //T //PID "$pid" >/dev/null 2>&1; else kill -9 "$pid"; fi; done
fi

# 3. The command ends by itself, with its exit code; nothing waits on the watcher.
if command -v timeout >/dev/null; then timeout 20 ap-background bash -c 'exit 7'; else ap-background bash -c 'exit 7'; fi
rc=$?
[ $rc = 7 ] || fail "a command that ended with 7 gave $rc"

ap-background 2>"$T/err" && fail "no command passed"
grep -q "usage: ap-background" "$T/err" || fail "the usage does not name ap-background: $(cat "$T/err")"

# lib/proc-tree.sh: a process that is gone already is stopped without a word (Git Bash's ps has
# no -o, so the way to list the processes must not depend on that process).
# shellcheck source=plugins/ap/lib/proc-tree.sh
( source "$ROOT/plugins/ap/lib/proc-tree.sh"; bash -c 'exit 0' & gone=$!; wait $gone; stop_tree $gone ) 2>"$T/err"
[ ! -s "$T/err" ] || fail "stop_tree of a process that is gone said: $(cat "$T/err")"

if [ $fails = 0 ]; then echo "ap-background: ok"; else exit 1; fi
