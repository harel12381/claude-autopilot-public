#!/usr/bin/env bash
# Tests ap-status in a throwaway repository, with a fake `gh` (first on PATH) that answers each
# list from a file of the test and writes down how it was called:
#   - the groups of the open issues and their order: waiting for the owner first (the skipped ones,
#     status:later, last), a phone check only when an issue has that label, in progress (with the
#     slot or the pull request), blocked (with why), ready in the run's order (P0 to P3, then no
#     priority; the lower number first), with a label limit (as ap-list: every --label, a,b for
#     either one, --not; every P0, and the approved look-back issues first), and inbox;
#     a long group shows --max lines and how many more;
#   - opened and solved since the run started, each solved issue with its pull request; duplicates
#     and "not planned" are not solved, nor a run's own issue (tracking);
#   - a run with a stop-in time and a slot worktree (and the next one of its queue, ap-1b): the
#     minutes left, what the run issue says (the stop, the counts, the next deploy), the slot's
#     branch, issue, pull request and the work not committed there;
#   - no run at all, and a project with none of the optional settings: no run part, "since" is
#     24 hours ago, no run issue list, and no phone group;
#   - one gh call per kind of list; a list that fails is named, and the rest still shows;
#   - it changes nothing: the checkouts and the runs' files are as before;
#   - plain text without --json; no .claude/ap.json repo: exit 2.
#
#   bash tests/status-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "status-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b main "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
echo ".claude/" >>"$M/.git/info/exclude"
write_config "$M" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main" }'

# The fake gh: the answer of each list is the file the list's flags point to.
mkdir "$T/bin" "$T/gh"
cat >"$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/gh-calls"
case "\$*" in
  *"--label status:blocked"*) f=blocked ;;
  *"[retro] in:title"*) f=lookback ;;
  *"[autopilot] in:title"*) f=run_issues ;;
  *"created:>="*) f=opened ;;
  *"closed:>="*) f=closed ;;
  "pr list"*"--state merged"*) f=merged ;;
  "pr list"*) f=prs ;;
  "issue list"*) f=issues ;;
  *) echo "fake gh: no answer for \$*" >&2; exit 1 ;;
esac
[ "\${FAKE_GH_FAIL:-}" != "\$f" ] || { echo "HTTP 502: bad gateway" >&2; exit 1; }
cat "$T/gh/\$f.json" 2>/dev/null || echo '[]'
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

issue() { # number, title, labels...: one open issue as gh prints it
  local n=$1 t=$2 l
  shift 2
  l=$(printf '{"name":"%s"},' "$@")
  printf '{"number":%s,"title":"%s","labels":[%s]}' "$n" "$t" "${l%,}"
}
issues() { # the issues (one per argument) as the list of open issues
  local IFS=,
  echo "[$*]" >"$T/gh/issues.json"
}
BASE=(
  "$(issue 1 'Ready two' P2 type:bug area:a)"
  "$(issue 2 'Ready zero' P0 type:chore)"
  "$(issue 3 'Ask' P1 status:waiting-for-owner)"
  "$(issue 4 'Ask later' P0 status:waiting-for-owner status:later)"
  "$(issue 8 'Pick one' P3 status:needs-decision)"
  "$(issue 9 'Blocked one' P1 status:blocked)"
  "$(issue 10 '[inbox] a note' inbox)"
  "$(issue 11 'Skipped' P2 status:later)"
  "$(issue 12 'Working' P1 status:in-progress)"
  "$(issue 13 'No priority')"
  "$(issue 14 'Ready one' P1 type:bug)"
  "$(issue 15 '[autopilot] Run of today' tracking)"
  "$(issue 17 'Has a PR' P3)"
)
issues "${BASE[@]}"
cat >"$T/gh/blocked.json" <<'EOF'
[{"number":9,"body":"Do the thing.","comments":[{"body":"**Blocked:** needs #3 first."}]}]
EOF
cat >"$T/gh/prs.json" <<'EOF'
[{"number":30,"title":"Working","headRefName":"fix/12-working","isDraft":false,"reviewDecision":"","mergeable":"MERGEABLE"},
 {"number":31,"title":"Has a PR","headRefName":"feat/17-has-a-pr","isDraft":true,"reviewDecision":"","mergeable":"UNKNOWN"}]
EOF
cat >"$T/gh/opened.json" <<'EOF'
[{"number":24},{"number":23}]
EOF
cat >"$T/gh/closed.json" <<'EOF'
[{"number":20,"title":"Solved by branch","labels":[],"stateReason":"COMPLETED","closedByPullRequestsReferences":[]},
 {"number":21,"title":"A copy","labels":[],"stateReason":"DUPLICATE","closedByPullRequestsReferences":[]},
 {"number":22,"title":"Not wanted","labels":[],"stateReason":"NOT_PLANNED","closedByPullRequestsReferences":[]},
 {"number":23,"title":"Solved by reference","labels":[],"stateReason":"COMPLETED","closedByPullRequestsReferences":[{"number":41}]},
 {"number":25,"title":"Old duplicate","labels":[{"name":"duplicate"}],"stateReason":"COMPLETED","closedByPullRequestsReferences":[]},
 {"number":26,"title":"[autopilot] Run of 2026-11-01","labels":[{"name":"tracking"}],"stateReason":"COMPLETED","closedByPullRequestsReferences":[]}]
EOF
cat >"$T/gh/merged.json" <<'EOF'
[{"number":40,"headRefName":"fix/20-solved","body":"Closes #20"}]
EOF

status() { # name, args...: ap-status in the main checkout; $T/<name>.out, $T/<name>.rc
  local name=$1
  shift
  : >"$T/gh-calls"
  (cd "$M" && ap-status "$@" >"$T/$name.out" 2>"$T/$name.err"; echo $? >"$T/$name.rc")
}
q() { # name, Python expression on the report r: prints its value as JSON
  local p
  for p in python3 python; do
    if "$p" -I -c 'import json, sys; r = json.load(sys.stdin); print(json.dumps(eval(sys.argv[1])))' "$2" \
      <"$T/$1.out" 2>"$T/q.err"; then return; fi
  done
  echo "q failed: $2: $(cat "$T/q.err")"
}
is() { # name, expression, the value it must have (JSON)
  local got
  got=$(q "$1" "$2")
  [ "$got" = "$3" ] || fail "$1: $2 is $got, not $3"
}
numbers() { echo "[i['number'] for i in r['groups']['$1']['items']]"; }
snapshot() { # what must not change: the checkouts and the runs' files (read without the index
  # lock, which would rewrite the index)
  { g -C "$M" --no-optional-locks status --porcelain; g -C "$M" worktree list --porcelain
    ls -lA "$M/.git/ap-autopilot" 2>/dev/null; cat "$M/.git/ap-autopilot"/* 2>/dev/null
    g -C "$M" stash list; } >"$T/$1.snap"
}

# No run at all, and none of the optional settings.
snapshot before
status none --json
[ "$(cat "$T/none.rc")" = 0 ] || fail "no run: exit $(cat "$T/none.rc"): $(cat "$T/none.err")"
is none "r['runs']" "[]"
is none "r['chat_language']" '"en"'
is none "$(numbers owner)" "[3, 8, 4]"
is none "r['groups']['owner']['items'][2].get('later')" "true"
is none "'phone' in r['groups']" "false"
is none "$(numbers in_progress)" "[12, 17]"
is none "r['groups']['in_progress']['items'][0].get('pr')" "30"
is none "$(numbers blocked)" "[9]"
is none "r['groups']['blocked']['items'][0].get('why')" '"Blocked: needs #3 first"'
is none "$(numbers ready)" "[2, 14, 1, 13]"
is none "[i['priority'] for i in r['groups']['ready']['items']]" '["P0", "P1", "P2", null]'
is none "$(numbers inbox)" "[10]"
is none "r['later']" "1"
is none "r['since']['opened']" "[23, 24]"
is none "[(i['number'], i['pr']) for i in r['since']['solved']]" "[[20, 40], [23, 41]]"
is none "r['since']['duplicates']" "[21, 25]"
is none "r['since']['not_planned']" "[22]"
is none "[p['number'] for p in r['pull_requests']]" "[30, 31]"
is none "r['errors']" "[]"
since=$(q none "r['since']['from']" | tr -d '"')
want=$(printf '%(%Y-%m-%dT%H)T' $((EPOCHSECONDS - 86400)))
[[ $since == "$want"* ]] || fail "no run: since $since, not 24 hours ago ($want...)"
grep -q "autopilot" "$T/gh-calls" && fail "no run: it listed the run issues"
[ "$(wc -l <"$T/gh-calls")" = 7 ] || fail "no run: not one gh call per list: $(cat "$T/gh-calls")"
sort "$T/gh-calls" | uniq -d | grep . && fail "no run: the same gh call twice"

# A branch on origin named for an issue: the run leaves it out, so it is in progress, not ready.
g -C "$M" update-ref refs/remotes/origin/fix/13-no-priority HEAD
status branch --json
is branch "$(numbers ready)" "[2, 14, 1]"
is branch "[(i['number'], i.get('branch')) for i in r['groups']['in_progress']['items']]" '[[12, "fix/12-working"], [17, "feat/17-has-a-pr"], [13, "fix/13-no-priority"]]'
g -C "$M" update-ref -d refs/remotes/origin/fix/13-no-priority

# The label limit, the cut, and the phone check group.
issues "${BASE[@]}" "$(issue 16 'Look on the phone' P2 status:phone-check)"
status limit --json --label type:bug --max 2
is limit "$(numbers ready)" "[2, 14]"
is limit "r['groups']['ready']['total']" "3"
is limit "r['groups']['ready']['more']" "1"
is limit "$(numbers phone)" "[16]"
is limit "r['label_limit']" '"type:bug"'
# More than one label, either of two, not one; an approved look-back issue first, whatever the
# kind; one that is not decided yet is an issue like the others.
issues "${BASE[@]}" "$(issue 18 'Map bug' P1 type:bug area:b)" "$(issue 19 'Big' P3 type:bug area:a size:L)" \
  "$(issue 26 '[retro] Lessons' P2 type:chore area:tooling)" "$(issue 27 '[retro] Not yet' P2 type:chore area:tooling)"
echo '[{"number":26,"comments":[{"body":"**Decided** (Dana)\n1. yes"}]},{"number":27,"comments":[]}]' \
  >"$T/gh/lookback.json"
status kinds --json --label type:bug --label area:a,area:b --not size:L
is kinds "$(numbers ready)" "[26, 2, 18, 1]"
is kinds "r['groups']['ready']['items'][0].get('lookback')" "true"
is kinds "r['label_limit']" '"type:bug, area:a or area:b, not size:L"'
status nolimit --json --max 20
is nolimit "$(numbers ready)" "[26, 2, 14, 18, 1, 27, 19, 13]"
status nottooling --json --max 20 --not area:tooling
is nottooling "$(numbers ready)" "[2, 14, 18, 1, 19, 13]"
rm "$T/gh/lookback.json"
issues "${BASE[@]}"

# A run with a stop-in time, and a helper in slot 1 with work not committed.
run=$(cd "$M" && ap-run start) || fail "ap-run start failed"
(cd "$M" && ap-run stop-in "$run" 90 >/dev/null && ap-run hold "$run" 1 >/dev/null) || fail "ap-run stop-in or hold failed"
g -C "$M" worktree add -q "$M/.claude/worktrees/ap-1" -b fix/12-working || exit 1
echo work >"$M/.claude/worktrees/ap-1/new-file"
# Slot 2's worktree lost its git folder: its facts are unknown, and the report still comes.
(cd "$M" && ap-run hold "$run" 2 >/dev/null) || fail "ap-run hold 2 failed"
g -C "$M" worktree add -q "$M/.claude/worktrees/ap-2" -b fix/13-gone || exit 1
rm -rf "$M/.git/worktrees/ap-2"
# Slot 1's queue holds its next worktree, not made yet.
(cd "$M" && ap-run hold "$run" 1b 14 >/dev/null) || fail "ap-run hold 1b failed"
cat >"$T/gh/run_issues.json" <<EOF
[{"number":15,"title":"[autopilot] Run of today","url":"https://x/15",
  "body":"Started by Dana with the arguments: X2 bugs\nRun id: $run",
  "comments":[{"body":"#5 merged in #20: a fix"},{"body":"Deployed #5: ok."},{"body":"#6 merged in #21"},
   {"body":"#7 waiting for Dana: which colour?"},{"body":"#8 failed: tests"},
   {"body":"**Stop:** STOP IN 90, from 10:00"},{"body":"#9 merged in #22: more"}]}]
EOF
snapshot before
status run --json
[ "$(cat "$T/run.rc")" = 0 ] || fail "a run: exit $(cat "$T/run.rc"): $(cat "$T/run.err")"
is run "[x['id'] for x in r['runs']]" "[\"$run\"]"
is run "r['runs'][0]['issue']['number']" "15"
is run "r['runs'][0]['arguments']" '"Started by Dana with the arguments: X2 bugs"'
is run "r['runs'][0]['stop']['kind']" '"stop-in"'
is run "r['runs'][0]['stop']['written']" '"STOP IN 90, from 10:00"'
is run "r['runs'][0]['stop']['of']" "90"
is run "r['runs'][0]['stop']['minutes_left'] in (89, 90)" "true"
is run "r['runs'][0]['counts']" '{"merged": [5, 6, 9], "failed": [8], "waiting": [7]}'
is run "r['runs'][0]['next_deploy_after']" "null"
is run "r['runs'][0]['last_comment']" '"#9 merged in #22: more"'
is run "[(s['slot'], s['branch'], s['issue'], s['pr'], s['uncommitted']) for s in r['runs'][0]['slots']]" \
  '[["1", "fix/12-working", 12, 30, 1], ["1b", null, null, null, 0], ["2", null, null, null, null]]'
is run "r['groups']['in_progress']['items'][0].get('place')" '"slot 1"'
started=$(head -1 "$M/.git/ap-autopilot/run-$run")
is run "r['since']['from'].startswith('${started/ /T}')" "true"
grep -qF -- "created:>=${started/ /T}" "$T/gh-calls" || fail "a run: opened is not since the run started: $(cat "$T/gh-calls")"
[ "$(wc -l <"$T/gh-calls")" = 8 ] || fail "a run: not one gh call per list: $(cat "$T/gh-calls")"
snapshot after
cmp -s "$T/before.snap" "$T/after.snap" || fail "ap-status changed something: $(diff "$T/before.snap" "$T/after.snap")"

# With a deploy set: the next deploy after the merges since the last one.
write_config "$M" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main", "chat_language": "he", "deploy": "true" }'
status deploy --json
is deploy "r['runs'][0]['next_deploy_after']" "3"
is deploy "r['chat_language']" '"he"'

# Plain text, and a list that fails: with no pull requests known, #17 is ready.
FAKE_GH_FAIL=prs status text
[ "$(cat "$T/text.rc")" = 0 ] || fail "text: exit $(cat "$T/text.rc"): $(cat "$T/text.err")"
for words in "Run $run" "Stop: STOP IN 90, from 10:00, " "Merged 3, failed 1, waiting 1; next deploy after 3 more merges" \
  "Slot 1: fix/12-working, #12 Working" "Slot 1b: no worktree" "1 uncommitted" "Waiting for Dana (3):" "  #4 Ask later P0 (later)" \
  "Ready for the next run (5):" "Could not read: prs: HTTP 502: bad gateway"; do
  grep -qF -- "$words" "$T/text.out" || fail "text: no '$words' in: $(cat "$T/text.out")"
done
grep -q "^Open pull requests" "$T/text.out" && fail "text: pull requests shown from a list that failed"
grep -qx "  #13 No priority" "$T/text.out" || fail "text: an issue with no priority is not '#13 No priority': $(cat "$T/text.out")"
grep -qF "work not committed: unknown" "$T/text.out" || fail "text: slot 2's unknown work is not said"

# The list of open issues fails: the groups are unknown, not empty.
FAKE_GH_FAIL=issues status noissues --json
is noissues "r['groups']" "null"
FAKE_GH_FAIL=issues status noissues-text
grep -qx "Open issues: unknown (their list could not be read)" "$T/noissues-text.out" ||
  fail "no issue list: $(cat "$T/noissues-text.out")"
grep -q "(0)" "$T/noissues-text.out" && fail "no issue list: a group shows (0)"

# The end of the run: no run part any more.
(cd "$M" && ap-run end "$run" >/dev/null 2>&1)
status ended
grep -qx "No run goes on." "$T/ended.out" || fail "after the end: $(cat "$T/ended.out")"

# No settings: exit 2, and it says what to run.
rm "$M/.claude/ap.json"
status nosetup
[ "$(cat "$T/nosetup.rc")" = 2 ] && grep -q "/ap:setup" "$T/nosetup.err" ||
  fail "no settings: exit $(cat "$T/nosetup.rc"): $(cat "$T/nosetup.err")"

[ "$FAILED" = 0 ] && echo "ap-status: ok"
exit "$FAILED"
