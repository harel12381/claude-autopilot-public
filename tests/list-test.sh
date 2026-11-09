#!/usr/bin/env bash
# Tests ap-list, the run's list of issues, with a fake `gh` (first on PATH) that answers each list
# from a file of the test:
#   - the order: the issues a stop left in the middle first, then the approved look-back issues,
#     then P0 to P3 (the lower number first); the labels a run leaves out stay out, and so do the
#     ones given with --leave-out;
#   - a stopped issue is one with status:in-progress whose last comment starts with
#     **Stopped in the middle.**; while another run goes on it is left out, and says why;
#   - an approved look-back issue is a [retro] issue with a **Decided** comment: it passes a kind
#     or --label limit, and a --not limit can still leave it out;
#   - the label limit: --label <l> (every --label is needed), --label <a>,<b> (either one),
#     --not <l>, alone and together; every P0 is kept, whatever its labels;
#   - issue numbers: only those, in that order, with the same limit; a closed one is said;
#   - an issue with an open pull request or a branch on origin named for it is left out and
#     said (`open PR #M`, `branch <name>`), unless it is named or was stopped in the middle;
#   - a list that gh cannot give: exit 2, with gh's words.
#
#   bash tests/list-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "list-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b main "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
echo ".claude/" >>"$M/.git/info/exclude"
write_config "$M" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main" }'

mkdir "$T/bin" "$T/gh"
cat >"$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/gh-calls"
case "\$*" in
  *"--label status:in-progress"*) f=stopped ;;
  *"[retro] in:title"*) f=lookback ;;
  "pr list"*) f=prs ;;
  "issue list"*) f=issues ;;
  *) echo "fake gh: no answer for \$*" >&2; exit 1 ;;
esac
[ "\${FAKE_GH_FAIL:-}" != "\$f" ] || { echo "HTTP 502: bad gateway" >&2; exit 1; }
cat "$T/gh/\$f.json" 2>/dev/null || echo '[]'
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

issue() { # number, title, labels...
  local n=$1 t=$2 l
  shift 2
  l=$(printf '{"name":"%s"},' "$@")
  printf '{"number":%s,"title":"%s","labels":[%s]}' "$n" "$t" "${l%,}"
}
{
  echo "["
  issue 1 'App bug' P2 type:bug area:app; echo ","
  issue 2 'Main is red' P0 type:chore area:engine; echo ","
  issue 3 'Ask' P1 type:bug status:waiting-for-owner; echo ","
  issue 5 'Map bug' P1 type:bug area:map; echo ","
  issue 6 'Big app bug' P3 type:bug area:app size:L; echo ","
  issue 7 'Engine bug' P2 type:bug area:engine; echo ","
  issue 8 'App feature' P1 type:feature area:app; echo ","
  issue 9 'Blocked' P1 type:bug status:blocked; echo ","
  issue 10 '[inbox] a note' inbox; echo ","
  issue 12 'Stopped bug' P2 type:bug area:app status:in-progress; echo ","
  issue 13 'Stopped chore' P3 type:chore status:in-progress; echo ","
  issue 15 '[autopilot] Run of today' tracking; echo ","
  issue 18 'Working' P1 type:bug status:in-progress; echo ","
  issue 20 '[retro] Lessons from the run of one day' P2 type:chore area:tooling; echo ","
  issue 21 '[retro] Lessons waiting' P2 type:chore area:tooling status:waiting-for-owner; echo ","
  issue 22 '[retro] Lessons not decided' P2 type:chore area:tooling
  echo "]"
} >"$T/gh/issues.json"
cat >"$T/gh/stopped.json" <<'EOF'
[{"number":12,"comments":[{"body":"Took it."},{"body":"**Stopped in the middle.** The branch has the fix."}]},
 {"number":13,"comments":[{"body":"\n**Stopped in the middle.** Half done."}]},
 {"number":18,"comments":[{"body":"**Stopped in the middle.** Once."},{"body":"Went on with it."}]}]
EOF
cat >"$T/gh/lookback.json" <<'EOF'
[{"number":20,"comments":[{"body":"**Decided** (Dana, 2026-11-01)\n1. yes"},{"body":"Point 1 is half done."}]},
 {"number":21,"comments":[{"body":"**Decided** (Dana)\n1. no"}]},
 {"number":22,"comments":[{"body":"A note, nothing decided."}]}]
EOF

list() { # name, args...: ap-list in the main checkout; $T/<name>.out, .err, .rc, and the numbers
  local name=$1
  shift
  : >"$T/gh-calls"
  (cd "$M" && ap-list "$@" >"$T/$name.out" 2>"$T/$name.err"; echo $? >"$T/$name.rc")
  grep -oE '^#[0-9]+' "$T/$name.out" | tr -d '#' | paste -sd' ' - >"$T/$name.nums"
}
takes() { # name, args..., then "--", then the numbers it must list, in order
  local name=$1 args=() want
  shift
  while [ "$1" != -- ]; do args+=("$1"); shift; done
  shift
  want="$*"
  list "$name" "${args[@]}"
  [ "$(cat "$T/$name.rc")" = 0 ] || fail "$name: exit $(cat "$T/$name.rc"): $(cat "$T/$name.err")"
  [ "$(cat "$T/$name.nums")" = "$want" ] || fail "$name: takes '$(cat "$T/$name.nums")', not '$want': $(cat "$T/$name.out")"
}
says() { grep -qF -- "$2" "$T/$1.out" || fail "$1: no '$2' in: $(cat "$T/$1.out")"; }

# No limit: stopped (P2, P3), the look back, then the rest by priority and number.
takes all -- 12 13 20 2 5 8 1 7 22 6
says all "#12 P2 Stopped bug area:app (stopped in the middle)"
says all "#20 P2 [retro] Lessons from the run of one day area:tooling (approved look back)"
says all "#6 P3 Big app bug area:app size:L"
[ "$(wc -l <"$T/gh-calls")" = 4 ] || fail "all: not one gh call per list: $(cat "$T/gh-calls")"
grep -q -- "--repo o/n" "$T/gh-calls" || fail "all: gh is not asked about the repo of ap.json: $(cat "$T/gh-calls")"
takes leave --leave-out area:map -- 12 13 20 2 8 1 7 22 6

# A kind: the look back still comes, a stopped issue of another kind is left out and said.
takes bugs --label type:bug -- 12 20 2 5 1 7 6
says bugs "left out: #13"
says bugs "label limit: type:bug"
# Two labels, both needed; either of two; not one; and all together.
takes bugs-app --label type:bug --label area:app -- 12 20 2 1 6
takes app-or-map --label area:app,area:map -- 12 20 2 5 8 1 6
says app-or-map "label limit: area:app or area:map"
takes not-engine --not area:engine -- 12 13 20 2 5 8 1 22 6
takes not-tooling --not area:tooling -- 12 13 2 5 8 1 7 6
takes together --label type:bug --label area:app,area:map --not size:L -- 12 20 2 5 1
says together "label limit: type:bug, area:app or area:map, not size:L"

# Another run goes on: the stopped issues are left out, and the list says why.
run=$(cd "$M" && ap-run start) || fail "ap-run start failed"
takes other -- 20 2 5 8 1 7 22 6
says other "left out: #12 (stopped in the middle, but another run goes on: $run)"
takes mine --run "$run" -- 12 13 20 2 5 8 1 7 22 6
(cd "$M" && ap-run end "$run" >/dev/null 2>&1)

# Issue numbers: only those, in that order, with the limit (a P0 is kept); a closed one is said.
takes named --label type:bug 7 8 99 2 -- 7 2
says named "left out: #8 (not in the label limit)"
says named "left out: #99 (not open)"

# Another session may be on an issue: an open pull request or a branch on origin names it.
cat >"$T/gh/prs.json" <<'EOF'
[{"number":40,"headRefName":"fix/7-engine-bug"},{"number":41,"headRefName":"fix/12-stopped-bug"}]
EOF
g -C "$M" update-ref refs/remotes/origin/feat/1-app-bug HEAD
takes busy -- 12 13 20 2 5 8 22 6
says busy "left out: #7 (open PR #40)"
says busy "left out: #1 (branch feat/1-app-bug)"
takes busy-named 1 7 -- 1 7
g -C "$M" update-ref -d refs/remotes/origin/feat/1-app-bug
rm "$T/gh/prs.json"

# Wrong arguments, and a list gh cannot give.
list empty --label ""
[ "$(cat "$T/empty.rc")" = 2 ] || fail "an empty --label: exit $(cat "$T/empty.rc")"
list word nothing
[ "$(cat "$T/word.rc")" = 2 ] || fail "a word that is no issue number: exit $(cat "$T/word.rc")"
FAKE_GH_FAIL=lookback list nogh
[ "$(cat "$T/nogh.rc")" = 2 ] && grep -q "HTTP 502" "$T/nogh.err" ||
  fail "gh failed: exit $(cat "$T/nogh.rc"): $(cat "$T/nogh.err")"

[ "$FAILED" = 0 ] && echo "ap-list: ok"
exit "$FAILED"
