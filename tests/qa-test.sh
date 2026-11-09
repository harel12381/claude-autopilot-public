#!/usr/bin/env bash
# Tests ap-qa and its driver (lib/qa/) with a fake Playwright (tests/fake-playwright, first on
# PYTHONPATH: no browser runs), in a throwaway repository whose cases are the plugin's example
# (docs/qa-example) and a few of the test's own:
#   - parts.qa not true: one line, exit 3; no Python with Playwright: the install line, exit 2;
#     no cases folder, a case with no run(), no site: exit 2;
#   - a browser that cannot start (Windows blocked WebKit) is a failed `launch` row and the sweep
#     goes on with the next browser; the contact sheet and the summary are written;
#   - every language and theme: a LOOK case runs with each theme, another only with the first;
#     the browser's locale (project.py's LOCALES) and colour scheme; pictures in the out folder;
#   - a console error fails the case's console row, named by its step;
#   - a case stopped by a time-out: failed on a quiet computer, not judged on a busy one;
#   - a deploy: a check that failed beside one is not judged; a deploy lock that stays held stops
#     the sweep (exit 2); a lock whose ap-deploy is gone is removed first;
#   - the driver's rules alone: Windows' block in its words and its exit codes, a row's mark.
#
#   bash tests/qa-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "qa-test: $*" >&2; FAILED=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
export PYTHONPATH
PYTHONPATH=$(native "$ROOT/tests/fake-playwright")
export FAKE_PW_LOG=$T/pw.log

R=$T/repo
g init -q -b main "$R" && g -C "$R" commit -q --allow-empty -m init || exit 1
COMMON=$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)
mkdir -p "$R/.claude/qa"
cp "$ROOT/plugins/ap/docs/qa-example/"*.py "$R/.claude/qa/"
cat >"$R/.claude/qa/fails.py" <<'EOF'
def run(case):
    case.open('/')
    case.check('always', False, 'it fails')
EOF
cat >"$R/.claude/qa/broken.py" <<'EOF'
def run(case):
    case.step('broken page')
    case.open('/broken')
EOF
cat >"$R/.claude/qa/stops.py" <<'EOF'
from playwright.sync_api import TimeoutError

def run(case):
    case.step('waiting')
    raise TimeoutError('Timeout 30000ms exceeded.')
EOF
QA='"qa": { "cases": ".claude/qa", "langs": ["en", "he"], "themes": ["light", "dark"] }'
config() { write_config "$R" "{ \"repo\": \"o/n\", \"owner\": \"O\", \"main_branch\": \"main\", $1 }"; }
config "\"site\": \"http://site.test\", \"parts\": { \"qa\": true }, $QA"

qa() { # name, args...: runs ap-qa in the repository; $T/<name>.out, its exit code in $T/<name>.rc
  local n=$1
  shift
  (cd "$R" && ap-qa --out "$T/out-$n" "$@" >"$T/$n.out" 2>&1; echo $? >"$T/$n.rc")
}
rc() { cat "$T/$1.rc"; }
out() { tail -5 "$T/$1.out"; }
row() { # name, mark, case, check: the run printed that row
  grep -qE "^$2 +$3 +$4( |\$)" "$T/$1.out" || fail "$1: no row '$2 $3 $4': $(cat "$T/$1.out")"
}
no_row() { # name, case, check
  grep -qE "^[A-Za-z]+ +$2 +$3( |\$)" "$T/$1.out" && fail "$1: a row it should not have: $2 $3"
  return 0
}

# Off, and what it needs.
config "\"site\": \"http://site.test\", \"parts\": { \"qa\": false }, $QA"
qa off
[ "$(rc off)" = 3 ] && [ "$(wc -l <"$T/off.out")" = 1 ] && grep -q "off in this project" "$T/off.out" ||
  fail "parts.qa false: exit $(rc off), not 3 with one line: $(out off)"
config "\"site\": \"http://site.test\", \"parts\": { \"qa\": true }, $QA"
mkdir -p "$T/nopy"
printf '#!/usr/bin/env bash\nexit 1\n' >"$T/nopy/nopython" && chmod +x "$T/nopy/nopython"
PATH="$T/nopy:$PATH" AP_QA_PYTHON=nopython qa nopw
[ "$(rc nopw)" = 2 ] && grep -q "pip install playwright" "$T/nopw.out" || fail "no Playwright: exit $(rc nopw): $(out nopw)"
config "\"parts\": { \"qa\": true }, $QA"
qa nosite
[ "$(rc nosite)" = 2 ] && grep -q "no site to check" "$T/nosite.out" || fail "no site: exit $(rc nosite): $(out nosite)"
config "\"site\": \"http://site.test\", \"parts\": { \"qa\": true }, $QA"
qa nofolder --cases nothing-here
[ "$(rc nofolder)" = 2 ] && grep -q "no cases folder" "$T/nofolder.out" || fail "no cases folder: exit $(rc nofolder): $(out nofolder)"
echo "x = 1" >"$R/.claude/qa/norun.py"
qa norun
[ "$(rc norun)" = 2 ] && grep -q "norun.py has no run(case)" "$T/norun.out" || fail "a case with no run(): exit $(rc norun): $(out norun)"
rm "$R/.claude/qa/norun.py"

# The sweep: WebKit blocked, Chromium with every language and theme.
FAKE_PW_BLOCK=webkit qa sweep --browsers webkit,chromium --only home,fails,broken --busy-load 1000
[ "$(rc sweep)" = 1 ] || fail "a sweep with failed checks: exit $(rc sweep), not 1: $(out sweep)"
row sweep FAIL webkit launch
grep -q "Windows blocked WebKit (Smart App Control" "$T/sweep.out" || fail "the launch row does not say Windows blocked WebKit"
for l in en he; do
  for th in light dark; do
    row sweep ok "chromium-$l-$th" home.title
    row sweep ok "chromium-$l-$th" home.width
    row sweep ok "chromium-$l-$th" home.screen
    [ -f "$T/out-sweep/chromium-$l-$th-home-screen.png" ] || fail "no picture chromium-$l-$th-home-screen.png"
  done
  row sweep FAIL "chromium-$l-light" fails.always
  no_row sweep "chromium-$l-dark" fails.always
  row sweep FAIL "chromium-$l-light" broken.console
  grep -q "\[broken page\] Uncaught Error: broken page" "$T/sweep.out" || fail "the console error does not name its step"
done
grep -q "goto http://site.test/ he-IL dark" "$T/pw.log" || fail "the page was not opened in Hebrew (he-IL) and dark: $(head -3 "$T/pw.log")"
grep -q "launch chromium" "$T/pw.log" || fail "Chromium did not start after WebKit was blocked"
[ -f "$T/out-sweep/index.html" ] && grep -q "chromium-he-dark" "$T/out-sweep/index.html" || fail "no contact sheet"
grep -qE "^[0-9]+ checks, 5 failed, 0 not judged, .* Pictures: .*index.html" "$T/sweep.out" || fail "the summary: $(out sweep)"

# A case stopped by a time-out: failed when the computer is quiet, not judged when it is busy.
qa quiet --browsers chromium --langs en --only stops --busy-load 1000
[ "$(rc quiet)" = 1 ] && row quiet FAIL chromium-en-light stops.run || fail "a time-out on a quiet computer did not fail: $(out quiet)"
grep -q "stopped in waiting: TimeoutError" "$T/quiet.out" || fail "the stop does not name its step: $(out quiet)"
[ -f "$T/out-quiet/chromium-en-light-stops-failed.png" ] || fail "no picture of the stopped case"
if python -c 'import psutil' 2>/dev/null || python3 -c 'import psutil' 2>/dev/null; then
  qa busy --browsers chromium --langs en --only stops --busy-load -1
  [ "$(rc busy)" = 0 ] && row busy TOLD chromium-en-light stops.run && grep -q "computer busy, not judged" "$T/busy.out" &&
    grep -q "^Not judged: chromium-en-light stops.run" "$T/busy.out" ||
    fail "a time-out on a busy computer was judged: exit $(rc busy): $(out busy)"
else
  echo "qa-test: psutil is missing: the busy computer case is skipped"
fi

# A deploy beside a case: its failed check is not judged.
echo "$((EPOCHSECONDS - 10)) $((EPOCHSECONDS + 600))" >"$COMMON/ap-deploy-times"
qa deployed --browsers chromium --langs en --themes light --only fails
[ "$(rc deployed)" = 0 ] && row deployed TOLD chromium-en-light fails.always && grep -q "the site was deploying, not judged" "$T/deployed.out" ||
  fail "a failure beside a deploy was judged: exit $(rc deployed): $(out deployed)"
rm "$COMMON/ap-deploy-times"
# A deploy lock that stays held stops the sweep; one whose ap-deploy is gone is removed.
mkdir "$COMMON/ap-deploy.lock" && echo "$$ deploy of abc (since 10:00:00)" >"$COMMON/ap-deploy.lock/owner"
qa held --browsers chromium --langs en --themes light --only home --deploy-wait 0.01
[ "$(rc held)" = 2 ] && grep -q "Waiting for the deploy to end: deploy of abc" "$T/held.out" && grep -q "still held" "$T/held.out" ||
  fail "a held deploy lock did not stop the sweep: exit $(rc held): $(out held)"
echo "999999 deploy of def (since 10:00:00)" >"$COMMON/ap-deploy.lock/owner"
pid_runs 999999 && fail "process 999999 runs here: the case of a lock left by a gone deploy cannot be told"
qa left --browsers chromium --langs en --themes light --only home
[ "$(rc left)" = 0 ] && grep -q "removed the deploy lock" "$T/left.out" && [ ! -d "$COMMON/ap-deploy.lock" ] ||
  fail "a deploy lock whose ap-deploy is gone was not removed: exit $(rc left): $(out left)"

# The driver's rules alone.
PY=$(command -v python3 || command -v python)
"$PY" - "$(native "$ROOT/plugins/ap/lib/qa")" <<'EOF' || fail "the driver's rules"
import sys
sys.path.insert(0, sys.argv[1])
from browsers import blocked, cannot_start
from result import mark
from deploy import Deploys
bad = []
def check(what, ok):
    if not ok:
        bad.append(what)
check('the exit code in decimal', blocked('exitCode=3236495362'))
check('the exit code as a signed number', blocked('exit code -1058471934'))
check('the exit code in hex', blocked('exit 0xc0e90002'))
check("Windows' words", blocked('An Application Control policy has blocked this file'))
check('another exit code', not blocked('exitCode=32364953620'))
check('a browser not installed', cannot_start('chromium', Exception("Executable doesn't exist")).startswith('Chromium could not start'))
check('marks', (mark(True, 'x'), mark(False, 'x'), mark(True, 'y; not judged')) == ('ok  ', 'FAIL', 'TOLD'))
d = Deploys(None)
check('no deploys known', not d.held() and not d.ran_between(0, 10 ** 10))
if bad:
    print('qa-test: wrong: ' + '; '.join(bad), file=sys.stderr)
    sys.exit(1)
EOF

[ "$FAILED" = 0 ] && echo "qa-test: every case passed"
exit "$FAILED"
