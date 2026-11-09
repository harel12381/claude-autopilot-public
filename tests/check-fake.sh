# shellcheck shell=bash
# The throwaway repository that the tests of ap-check run it in (check-test.sh,
# check-failures-test.sh, check-log-test.sh, deploy-test.sh). Loaded with `source` after lib.sh:
# it makes the repository $R in a new temp folder $T (deleted on exit), its .claude/ap.json with
# these parts, and the helpers the cases use. Each step is the fake below, which writes when it
# starts and ends.
#
#   a, b   light steps only (inputs a/, b/)
#   h      heavy steps only (inputs h/ and shared.txt)
#   m      light and heavy steps, light first (inputs m/)
#   r      light steps only, with a retry: a log with RETRY-ME runs `fake.sh r retry` instead
#
# The fake reads these variables:
#   FAKE_SLEEP  how long a step runs, in seconds (0): a case about the order of steps sets one
#   FAKE_MEET   steps that must run at the same time ("a/light b/light"): each of them waits, up
#               to 60 s, until the others started. A busy computer can start the second run
#               seconds after the first, after the first's step ended.
#   FAKE_FAIL   the step that fails, printing FAKE_SAY ("a test failed")
#   FAKE_ONCE   set: FAKE_FAIL fails only the first time
#   FAKE_GATE   a file: each step waits until it is there (600 s at most). Only the test opens it,
#               never the clock, so a case that waits for something while it is shut never races it
#   FAKE_GATED  with FAKE_GATE: only these steps wait ("h/heavy")
#   FAKE_JOB    set: each step writes the job of ap-check it runs under to $T/<part>-<step>.job,
#               and its own process to $T/<part>-<step>.self
T=$(mktemp -d)
trap 'wait; rm -rf "$T"' EXIT
R=$T/repo EV=$T/events
mkdir -p "$R"/{a,b,h,m,r}
for d in a b h m r; do echo x >"$R/$d/code"; done
echo x >"$R/shared.txt"
g init -q -b main "$R" && echo ".claude/" >>"$R/.git/info/exclude" && g -C "$R" add -A && g -C "$R" commit -qm test || exit 1
COMMON=$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)
LOCK=$COMMON/ap-check.lock
TEST=$(basename "$0" .sh)

cat >"$T/fake.sh" <<EOF
now() { echo "\${EPOCHREALTIME/[.,]/}"; }
echo "\$1/\$2 start \$(now)" >>"$EV"
if [ -n "\${FAKE_JOB:-}" ]; then # the job of ap-check this step runs under: the process whose parent is the run
  p=\$\$
  while [ "\$p" -gt 1 ]; do
    pp=\$(cat "/proc/\$p/ppid" 2>/dev/null || ps -o ppid= -p "\$p" | tr -d ' ')
    [ -n "\$pp" ] && [ "\$pp" != "\$AP_CHECK_RUN" ] || break
    p=\$pp
  done
  echo "\$p" >"$T/\$1-\$2.job"; echo \$\$ >"$T/\$1-\$2.self"
fi
# The heavy lock is held while a heavy step (or a heavy retry, heavy-retry) runs: nothing else can
# take it then.
if [[ "\$2" == heavy* ]] && mkdir "$LOCK" 2>/dev/null; then echo "\$1/\$2 unlocked 0" >>"$EV"; rmdir "$LOCK"; fi
if [[ " \${FAKE_MEET:-} " == *" \$1/\$2 "* ]]; then
  source "$ROOT/plugins/ap/lib/wait.sh"
  for m in \$FAKE_MEET; do wait_until 60 grep -q "^\$m start" "$EV"; done
fi
if [ -n "\${FAKE_GATE:-}" ] && { [ -z "\${FAKE_GATED:-}" ] || [[ " \$FAKE_GATED " == *" \$1/\$2 "* ]]; }; then source "$ROOT/plugins/ap/lib/wait.sh"; wait_until 600 test -e "\$FAKE_GATE"; fi
# The wait: on Windows a native program, to test that it is stopped with what is under it.
if command -v cygpath >/dev/null; then ping -n "\$((\${FAKE_SLEEP:-0} + 1))" 127.0.0.1 >/dev/null & else sleep "\${FAKE_SLEEP:-0}" & fi
echo \$! >"$T/\$1-\$2.pid"; echo "\${AP_CHECK_RUN:-}" >"$T/\$1-\$2.run"; echo "\${PWD##*/}" >"$T/\$1-\$2.dir"; wait
echo "\$1/\$2 end \$(now)" >>"$EV"
if [ "\${FAKE_FAIL:-}" = "\$1/\$2" ] && { [ -z "\${FAKE_ONCE:-}" ] || mkdir "$T/once" 2>/dev/null; }; then echo "\${FAKE_SAY:-a test failed}"; exit 1; fi
EOF

# config [options]: writes .claude/ap.json with the parts above, and these check_options (JSON
# members, "light_min_mb": 0 when not given: light steps beside heavy ones whatever is free).
config() {
  local f="bash $T/fake.sh"
  write_config "$R" "{
  \"repo\": \"o/n\", \"owner\": \"O\", \"main_branch\": \"main\",
  \"check_options\": { ${1:-\"light_min_mb\": 0} },
  \"check_parts\": [
    { \"name\": \"a\", \"inputs\": [\"a\"], \"light\": \"$f a light\" },
    { \"name\": \"b\", \"inputs\": [\"b\"], \"light\": \"$f b light\" },
    { \"name\": \"h\", \"inputs\": [\"h\", \"shared.txt\"], \"heavy\": \"$f h heavy\" },
    { \"name\": \"m\", \"inputs\": [\"m\"], \"dir\": \"m\", \"light\": \"$f m light\", \"heavy\": \"$f m heavy\", \"light_first\": true },
    { \"name\": \"r\", \"inputs\": [\"r\"], \"light\": \"$f r light\", \"retry\": { \"when\": \"RETRY-ME\", \"run\": \"$f r retry\" } }
  ]
}"
}
config
export AP_CHECK_WATCH_S=1

fails=0
fail() { echo "$TEST: $*"; fails=$((fails + 1)); }
start() { awk -v s="$1" '$1 == s && $2 == "start" {print $3; exit}' "$EV"; }
end() { awk -v s="$1" '$1 == s && $2 == "end" {print $3; exit}' "$EV"; }
ran() { [ -n "$(start "$1")" ] && [ -n "$(end "$1")" ]; }
starts() { grep -c "^$1 start" "$EV"; }
overlap() { ran "$1" && ran "$2" && [ "$(start "$1")" -lt "$(end "$2")" ] && [ "$(start "$2")" -lt "$(end "$1")" ]; }
check() { # name, args: runs ap-check in the test repository in the background
  local name=$1; shift
  (cd "$R" && ap-check "$@" >"$T/$name.out" 2>&1; echo $? >"$T/$name.rc") &
}
rc() { cat "$T/$1.rc"; }
out() { cat "$T/$1.out"; }
begin() { wait; unset FAKE_SLEEP FAKE_MEET FAKE_FAIL FAKE_SAY FAKE_ONCE; : >"$EV"; rm -rf "$T/once" "$T"/*.rc; } # each case sets its own
limited() { if command -v timeout >/dev/null; then timeout "$@"; else "${@:2}"; fi; } # macOS has no timeout
passed_all() { [ $fails = 0 ] && echo "$TEST: every case passed" || exit 1; } # the last line of a test
