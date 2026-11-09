# shellcheck shell=bash
# The wait of the scripts' tests: for a state (a file is there, a process is gone), never for a
# fixed time, which ends too early on a busy computer. Loaded with `source`; it only defines a
# function.

# wait_until <seconds> <command...>: runs the command every 0.2 s until it succeeds (0). Once the
# seconds have passed (counted by the clock, so a slow command does not stretch them), it tries a
# last time and returns that try's code. Each caller says what failed:
# `wait_until 30 test -e "$f" || fail ...`.
wait_until() {
  local end=$((SECONDS + $1))
  shift
  while [ "$SECONDS" -lt "$end" ]; do
    "$@" && return 0
    sleep 0.2
  done
  "$@"
}
