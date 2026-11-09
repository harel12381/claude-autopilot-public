#!/usr/bin/env bash
# Tests the plan of a run, `ap-list --json` (what /ap:plan shows), and the groups in ap-list's
# lines (what /ap:run reads), in a throwaway repository with a fake `gh` (first on PATH):
#   - the same order as the list, and every issue left out with why: waits for the owner, a
#     phone check, blocked, in progress, inbox, later, a label of --leave-out, the label limit; a
#     tracking issue is not named;
#   - the helpers: up to 3 size:S issues next to each other with the same area:* label;
#   - --parallel: a P0 or an issue with no area:* label runs alone, one area at a time unless
#     parallel-safe;
#   - --stop-after (a group never gets more issues than are left) and --stop-in (size:S after half);
#   - named issues: their order, one in progress or waiting is taken with its mark, a closed one
#     is left out;
#   - the lines say the group; a bad number: exit 2; it only reads (every gh call is a list).
#
#   bash tests/plan-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "plan-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b main "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
echo ".claude/" >>"$M/.git/info/exclude"
write_config "$M" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main" }'

mkdir "$T/bin"
cat >"$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/gh-calls"
case "\$*" in
  *"--label status:in-progress"*|*"[retro] in:title"*) echo '[]' ;;
  "issue list"*) cat "$T/issues.json" ;;
  "pr list"*) echo '[]' ;;
  *) echo "fake gh: no answer for \$*" >&2; exit 1 ;;
esac
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
  issue 1 'A' P1 type:bug area:x size:S; echo ","
  issue 2 'B' P1 type:bug area:x size:S; echo ","
  issue 3 'C' P1 type:bug area:x size:S; echo ","
  issue 4 'D' P1 type:bug area:x size:S; echo ","
  issue 5 'Main is red' P0 type:chore; echo ","
  issue 6 'F' P2 type:feature area:y size:M; echo ","
  issue 7 'G' P2 type:bug area:y size:M parallel-safe; echo ","
  issue 8 'H' P2 type:bug area:y size:S parallel-safe; echo ","
  issue 9 'Ask' P1 status:waiting-for-owner; echo ","
  issue 10 'Block' P2 status:blocked; echo ","
  issue 11 '[inbox] a note' inbox; echo ","
  issue 12 'Later' P3 status:later; echo ","
  issue 13 'Working' P2 area:z status:in-progress; echo ","
  issue 14 '[autopilot] Run' tracking; echo ","
  issue 15 'Phone' P1 status:phone-check; echo ","
  issue 16 'Held' P3 area:z hold; echo ","
  issue 17 'No priority' area:z size:S
  echo "]"
} >"$T/issues.json"

plan() { # name, args...: ap-list in the main checkout; $T/<name>.out, $T/<name>.rc
  local name=$1
  shift
  : >"$T/gh-calls"
  (cd "$M" && ap-list "$@" >"$T/$name.out" 2>"$T/$name.err"; echo $? >"$T/$name.rc")
}
q() { # name, Python expression on the plan p: prints its value as JSON
  local py
  for py in python3 python; do
    if "$py" -I -c 'import json, sys; p = json.load(sys.stdin); print(json.dumps(eval(sys.argv[1])))' "$2" \
      <"$T/$1.out" 2>"$T/q.err"; then return; fi
  done
  echo "q failed: $2: $(cat "$T/q.err")"
}
is() { # name, expression, the value it must have (JSON)
  local got
  got=$(q "$1" "$2")
  [ "$got" = "$3" ] || fail "$1: $2 is $got, not $3"
}
ORDER="[i['number'] for i in p['order']]"
WHY="[(i['number'], i['why']) for i in p['left_out']]"

plan all --json --leave-out hold
[ "$(cat "$T/all.rc")" = 0 ] || fail "all: exit $(cat "$T/all.rc"): $(cat "$T/all.err")"
is all "$ORDER" "[5, 1, 2, 3, 4, 6, 7, 8, 17]"
is all "$WHY" '[[9, "waits for the owner"], [15, "waits for a phone check"], [10, "blocked"], [13, "in progress"], [12, "later"], [16, "has hold"], [11, "an inbox note"]]'
is all "p['helpers']" "[[5], [1, 2, 3], [4], [6], [7], [8], [17]]"
is all "p['rounds']" "null"
is all "[(i.get('size'), i.get('area')) for i in p['order'][:2]]" '[[null, null], ["size:S", "area:x"]]'
if grep -vE '^(issue|pr) list ' "$T/gh-calls" | grep -q .; then fail "it ran a gh call that is no list: $(cat "$T/gh-calls")"; fi

plan parallel --json --leave-out hold --parallel 2
is parallel "p['rounds']" "[[[5]], [[1, 2, 3], [6]], [[4], [7]], [[8], [17]]]"
# Two parallel-safe issues of one area run together.
plan safe --json --leave-out hold --parallel 3 --label type:bug
is safe "$ORDER" "[5, 1, 2, 3, 4, 7, 8]"
is safe "$WHY[:3]" '[[9, "waits for the owner"], [15, "waits for a phone check"], [6, "not in the label limit"]]'
is safe "p['rounds']" "[[[5]], [[1, 2, 3], [7], [8]], [[4]]]"
is safe "p['label_limit']" '"type:bug"'

plan stops --json --leave-out hold --stop-after 3 --stop-in 60
is stops "p['stop_after']" '{"n": 3, "start": [[5], [1, 2]], "not_started": [3, 4, 6, 7, 8, 17]}'
is stops "p['stop_in']" '{"minutes": 60, "after_half": [1, 2, 3, 4, 8, 17]}'

plan named --json 13 '#9' 99 4
is named "$ORDER" "[13, 9, 4]"
is named "[i.get('mark') for i in p['order']]" '["in progress", "waits for the owner", null]'
is named "$WHY" '[[99, "not open"]]'

# The lines /ap:run reads say which issues one helper does together.
plan text --leave-out hold
[ "$(cat "$T/text.rc")" = 0 ] || fail "text: exit $(cat "$T/text.rc"): $(cat "$T/text.err")"
for want in "#5 P0 Main is red" "#1 P1 A area:x size:S (one helper with #2 #3)" \
  "#3 P1 C area:x size:S (one helper with #1 #2)" "#4 P1 D area:x size:S" "#17 No priority area:z size:S"; do
  grep -qxF -- "$want" "$T/text.out" || fail "text: no line '$want' in: $(cat "$T/text.out")"
done

plan bad --json --parallel two
[ "$(cat "$T/bad.rc")" = 2 ] && grep -q "usage" "$T/bad.err" ||
  fail "a bad number: exit $(cat "$T/bad.rc"): $(cat "$T/bad.err")"

[ "$FAILED" = 0 ] && echo "ap-list --json: ok"
exit "$FAILED"
