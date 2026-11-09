#!/usr/bin/env bash
# Tests ap-batch in a throwaway repository with an origin, a fake check (it fails when the tree
# has a file `fail`, and writes down what it checked) and a fake `gh` (first on PATH) that
# squash-merges a pull request's branch into origin's main branch:
#   - check: the branches are merged on origin/<main> in their order; one that conflicts leaves
#     the batch, one not on origin is named; the check runs once, with AP_CHECK_KIND=batch and the
#     batch's size; the worktree is gone after, and the main checkout is as it was;
#   - a batch that fails: the first branch that breaks it is found by halves (the checks of the
#     halves are AP_CHECK_KIND=bisect), the ones before it passed, the ones after it come later;
#     when the first branch breaks it, main is checked alone, and a red main is exit 4;
#   - a branch with its own .claude/ap.json: the batch runs its check and setup, not main's;
#   - nothing to check (exit 3), a failing hooks.check_setup (exit 91), no such run (exit 90);
#   - a check that could not run (90, 91; 2 when the check is ap-check) is exit 90, with no halves
#     and no branch blamed; a project check's own 2 is a failure;
#   - merge: each pull request of the batch that passed, in order, with --match-head-commit of
#     the commit merged into the batch (one pushed and fetched during the check is refused, and
#     nothing is merged: exit 1); main then has the checked tree; the batch is used once; some
#     merged and then one refused: exit 3 (main is not a checked tree); main moved since the
#     check: nothing merged, exit 4; a failed first fetch: nothing merged, the batch kept, exit
#     90; "Base branch was modified" is tried again.
#
#   bash tests/batch-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "batch-test: $*" >&2; FAILED=1; }
O=$T/origin.git M=$T/main
g init -q --bare -b develop "$O" && g clone -q "$O" "$M" 2>/dev/null || exit 1
echo ".claude/" >>"$M/.git/info/exclude"
echo x >"$M/shared.txt" && g -C "$M" add shared.txt && g -C "$M" commit -qm init && g -C "$M" push -q origin develop || exit 1
branch() { # name, file, text: a branch from develop on origin that writes the text in the file
  g -C "$M" switch -q -c "$1" develop && echo "$3" >"$M/$2" && g -C "$M" add "$2" && g -C "$M" commit -qm "$1" &&
    g -C "$M" push -q origin "$1" && g -C "$M" switch -q develop
}
for b in one two three four five; do branch "$b" "$b.txt" "$b" || exit 1; done
branch edit shared.txt edit && branch clash shared.txt clash && branch bad fail x || exit 1
g -C "$M" fetch -q origin || exit 1

# The fake check. With the file $T/move, it pushes a new commit to the branch named there and
# fetches it into the main checkout while it runs; with $T/cant, it exits with the code there.
cat >"$T/check.sh" <<EOF
echo "check \${AP_CHECK_KIND:-} \${AP_CHECK_BATCH:-} \$(ls *.txt | tr '\n' ' ')" >>"$T/calls"
if [ -f "$T/move" ]; then
  b=\$(cat "$T/move"); rm "$T/move"; C=$T/gh-clone
  git -C "\$C" fetch -q origin && git -C "\$C" checkout -q -B "\$b" "origin/\$b" && echo late >>"\$C/\$b.txt" &&
    git -C "\$C" -c user.name=t -c user.email=t@t commit -qam late && git -C "\$C" push -q origin "\$b" &&
    git -C "$M" fetch -q origin || exit 7
fi
[ ! -f "$T/cant" ] || exit \$(cat "$T/cant")
[ ! -f fail ] || exit 5
EOF
cat >"$T/setup.sh" <<EOF
exit \$(cat "$T/setup-rc" 2>/dev/null || echo 0)
EOF
CONFIG="\"repo\": \"o/n\", \"owner\": \"O\", \"main_branch\": \"develop\", \"check\": \"bash $T/check.sh\""
write_config "$M" "{ $CONFIG, \"hooks\": { \"check_setup\": \"bash $T/setup.sh\" } }"

# The fake gh: the pull requests are the lines "<number> <branch>" of $T/prs.
mkdir "$T/bin" && g clone -q "$O" "$T/gh-clone" 2>/dev/null || exit 1
cat >"$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/gh-calls"
arg() { sed -E "s/.*\$1 ([^ ]+).*/\\1/" <<<"\$*"; }
case "\$1 \$2" in
  "pr list")
    b=\$(arg --head "\$*") n=\$(awk -v b="\$(arg --head "\$*")" '\$2 == b {print \$1}' "$T/prs")
    if [ -n "\$n" ]; then echo "\$n \$(git -C "$O" rev-parse "\$b")"; else echo "null null"; fi ;;
  "pr merge")
    b=\$(awk -v n="\$3" '\$1 == n {print \$2}' "$T/prs")
    if [ -f "$T/flaky" ]; then rm "$T/flaky"; echo "GraphQL: Base branch was modified. Review and try the merge again." >&2; exit 1; fi
    [ "\$(git -C "$O" rev-parse "\$b")" = "\$(arg --match-head-commit "\$*")" ] || { echo "head moved" >&2; exit 1; }
    C=$T/gh-clone
    git -C "\$C" fetch -q origin && git -C "\$C" checkout -q -B develop origin/develop &&
      git -C "\$C" merge -q --squash "origin/\$b" && git -C "\$C" -c user.name=t -c user.email=t@t commit -q -m "squash \$b" &&
      git -C "\$C" push -q origin develop ;;
  *) echo "fake gh: no answer for \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" AP_BATCH_MERGE_WAIT_S=0
n=0; for b in one two three four five edit clash bad; do echo "$((n += 1)) $b" >>"$T/prs"; done

RUN=$(cd "$M" && ap-run start) || exit 1
batch() { : >"$T/calls"; (cd "$M" && ap-batch "$@" >"$T/out" 2>"$T/err"); }
lines() { grep -E '^(passed|breaks|later|conflict|missing) ' "$T/out" | paste -sd, -; }
checks() { paste -sd, - <"$T/calls"; }
record=$M/.git/ap-autopilot/batch-$RUN
unchanged() { # the main checkout stays on develop, clean, and the batch's worktree is gone
  [ "$(git -C "$M" branch --show-current)" = develop ] && [ -z "$(git -C "$M" status --short)" ] ||
    fail "$1: the main checkout changed: $(git -C "$M" status --short)"
  [ ! -e "$M/.claude/worktrees/check-batch-$RUN" ] || fail "$1: the batch's worktree is still there"
  git -C "$M" worktree list | grep -q check-batch && fail "$1: git still lists the batch's worktree"
  return 0
}

# A batch that passes: edit and clash change the same line, so clash leaves the batch.
batch check "$RUN" one edit clash nope two; rc=$?
[ $rc = 0 ] || fail "a batch that passes: exit $rc ($(cat "$T/err"))"
[ "$(lines)" = "conflict clash,missing nope,passed one,passed edit,passed two" ] || fail "a batch that passes: $(cat "$T/out")"
[ "$(checks)" = "check batch 3 one.txt shared.txt two.txt " ] ||
  fail "a batch that passes is not checked once, as a batch of 3: $(checks)"
[ "$(sed -n 3,9p "$record" | cut -d' ' -f1 | paste -sd, -)" = one,edit,two ] || fail "the record of the batch is wrong: $(cat "$record")"
[ "$(sed -n 3p "$record" | cut -d' ' -f2)" = "$(git -C "$M" rev-parse origin/one)" ] || fail "the record does not keep the commit checked"
[ "$(sed -n 1p "$record")" = "base $(git -C "$M" rev-parse origin/develop)" ] || fail "the record does not keep main's commit: $(cat "$record")"
unchanged "a batch that passes"

# Merge it: in order, each with its commit; main is then the tree that was checked.
batch merge "$RUN"; rc=$?
[ $rc = 0 ] || fail "merge: exit $rc ($(cat "$T/err"))"
[ "$(grep '^merged' "$T/out" | paste -sd, -)" = "merged #1 one,merged #6 edit,merged #2 two" ] || fail "merge: $(cat "$T/out")"
grep -q "pr merge 6 --repo o/n --squash --match-head-commit $(git -C "$M" rev-parse origin/edit)" "$T/gh-calls" ||
  fail "merge does not give the commit checked: $(cat "$T/gh-calls")"
grep -q "origin/develop is the tree the batch checked" "$T/out" || fail "merge does not say main is the checked tree: $(cat "$T/out")"
[ ! -e "$record" ] || fail "the batch is kept after its merge"
batch merge "$RUN"; rc=$?
[ $rc = 90 ] || fail "a second merge of the same batch: exit $rc, not 90"
g -C "$M" pull -q --ff-only origin develop || exit 1

# A batch that fails: bad breaks it. Checks: all 5, the first 2 (fails), the first 1 (passes).
batch check "$RUN" three bad four five; rc=$?
[ $rc = 1 ] || fail "a batch that fails: exit $rc ($(cat "$T/err"))"
[ "$(lines)" = "passed three,breaks bad,later four,later five" ] || fail "a batch that fails: $(cat "$T/out")"
[ "$(cut -d' ' -f2,3 "$T/calls" | paste -sd, -)" = "batch 4,bisect 2,bisect 1" ] || fail "the halves are not checked as they should be: $(checks)"
[ "$(sed -n 3,9p "$record" | cut -d' ' -f1 | paste -sd, -)" = three ] || fail "the record of the half that passed is wrong: $(cat "$record")"
unchanged "a batch that fails"
# The first one breaks it: main is checked alone, and passes.
batch check "$RUN" bad four; rc=$?
[ $rc = 1 ] && [ "$(lines)" = "breaks bad,later four" ] || fail "the first one breaks it: exit $rc, $(cat "$T/out")"
[ "$(cut -d' ' -f2,3 "$T/calls" | paste -sd, -)" = "batch 2,bisect 1,- 0" ] || fail "main is not checked alone when the first one breaks it: $(checks)"
[ ! -e "$record" ] || fail "a batch with nothing that passed left a record"

# Nothing to check; a setup that fails; no such run; a wrong use.
batch check "$RUN" nope; rc=$?
[ $rc = 3 ] && [ ! -s "$T/calls" ] || fail "nothing to check: exit $rc, checks: $(checks)"
echo 4 >"$T/setup-rc"; batch check "$RUN" four; rc=$?; rm "$T/setup-rc"
[ $rc = 91 ] && [ ! -s "$T/calls" ] || fail "a setup that fails: exit $rc, checks: $(checks)"
unchanged "a setup that fails"
batch check no-such-run four; rc=$?
[ $rc = 90 ] || fail "no such run: exit $rc, not 90"
batch check "$RUN"; rc=$?
[ $rc = 2 ] || fail "no branch: exit $rc, not 2"
batch frob "$RUN"; rc=$?
[ $rc = 2 ] || fail "an unknown command: exit $rc, not 2"

# A commit pushed and fetched while the check runs is not the one checked: merge refuses it, and
# merges nothing.
echo three >"$T/move"
batch check "$RUN" three four || fail "three four: $(cat "$T/out") $(cat "$T/err")"
[ ! -e "$T/move" ] || fail "the check did not push the late commit"
: >"$T/gh-calls"; batch merge "$RUN"; rc=$?
[ $rc = 1 ] || fail "a commit pushed during the check: exit $rc, not 1 ($(cat "$T/err"))"
grep -q "#3 (three) has a commit the batch did not check" "$T/err" || fail "the late commit is not named: $(cat "$T/err")"
grep -q "pr merge" "$T/gh-calls" && fail "something was merged after a late commit: $(cat "$T/gh-calls")"

# Some merged, then one with a new commit: main is not a tree that was checked: exit 3.
batch check "$RUN" four five || fail "four five: $(cat "$T/out") $(cat "$T/err")"
branch_more() { g -C "$M" switch -q "$1" && echo more >>"$M/$1.txt" && g -C "$M" commit -qam more && g -C "$M" push -q origin "$1" && g -C "$M" switch -q develop; }
branch_more five || exit 1
batch merge "$RUN"; rc=$?
[ $rc = 3 ] || fail "one merged, then a new commit: exit $rc, not 3"
grep -q "merged #4 four" "$T/out" && grep -q "#5 (five) has a commit the batch did not check" "$T/err" &&
  grep -q "1 of 2 merged, but origin/develop is not the tree the batch checked" "$T/err" ||
  fail "one merged, then a new commit: $(cat "$T/out") $(cat "$T/err")"
g -C "$M" pull -q --ff-only origin develop || exit 1

# Main moved by another hand after the check: nothing merged, and the batch is gone (check again).
batch check "$RUN" five || fail "five: $(cat "$T/out") $(cat "$T/err")"
g -C "$T/gh-clone" fetch -q origin && g -C "$T/gh-clone" checkout -q -B develop origin/develop &&
  echo other >"$T/gh-clone/other.txt" && g -C "$T/gh-clone" add other.txt && g -C "$T/gh-clone" commit -qm other &&
  g -C "$T/gh-clone" push -q origin develop || exit 1
: >"$T/gh-calls"; batch merge "$RUN"; rc=$?
[ $rc = 4 ] || fail "main moved since the check: exit $rc, not 4 ($(cat "$T/err"))"
grep -q "pr " "$T/gh-calls" && fail "a pull request was looked at or merged after main moved: $(cat "$T/gh-calls")"
grep -q "moved since the batch was checked" "$T/err" || fail "the move of main is not named: $(cat "$T/err")"
[ ! -e "$record" ] || fail "the batch is kept after main moved"
g -C "$M" pull -q --ff-only origin develop || exit 1

# The first fetch of merge fails (origin cannot be reached): a problem of the run, exit 90; nothing
# merged, and the batch is kept for a second try.
batch check "$RUN" five || fail "five: $(cat "$T/out") $(cat "$T/err")"
mv "$O" "$O.away" && : >"$T/gh-calls"; batch merge "$RUN"; rc=$?; mv "$O.away" "$O"
[ $rc = 90 ] || fail "a failed fetch in merge: exit $rc, not 90 ($(cat "$T/err"))"
grep -q "fetch failed: nothing merged" "$T/err" || fail "a failed fetch is not named: $(cat "$T/err")"
grep -q "pr " "$T/gh-calls" && fail "a pull request was looked at or merged after a failed fetch: $(cat "$T/gh-calls")"
[ -s "$record" ] || fail "a failed fetch dropped the batch"

# GitHub says "Base branch was modified" once: tried again.
touch "$T/flaky"
batch merge "$RUN"; rc=$?
[ $rc = 0 ] && grep -q "merged #5 five" "$T/out" || fail "Base branch was modified was not tried again: exit $rc, $(cat "$T/out") $(cat "$T/err")"
g -C "$M" pull -q --ff-only origin develop || exit 1

# A check that could not run is no break: no halves, no blame, exit 90. With ap-check (a fake one,
# first on PATH), its 2 is the same; a project check's own 2 is a failure.
cant() { # code: a batch of three and four, with a check that exits with it
  echo "$1" >"$T/cant"; batch check "$RUN" three four; rc=$?; rm "$T/cant"
}
for c in 90 91; do
  cant $c
  [ $rc = 90 ] && [ "$(wc -l <"$T/calls")" = 1 ] || fail "a check that could not run ($c): exit $rc, checks: $(checks)"
  grep -q "the check could not run (exit $c)" "$T/out" || fail "a check that could not run ($c) is not named: $(cat "$T/out")"
  grep -qE "^(breaks|passed) " "$T/out" && fail "a check that could not run ($c) blamed or passed a branch: $(cat "$T/out")"
done
cant 2
[ $rc = 4 ] || fail "a project check's own exit 2 is not a failure: exit $rc ($(cat "$T/out"))"
printf '#!/usr/bin/env bash\nbash %s/check.sh\n' "$T" >"$T/bin/ap-check" && chmod +x "$T/bin/ap-check"
write_config "$M" "{ \"repo\": \"o/n\", \"owner\": \"O\", \"main_branch\": \"develop\", \"check\": \"ap-check\" }"
cant 2
[ $rc = 90 ] && [ "$(wc -l <"$T/calls")" = 1 ] || fail "ap-check's 2 is not 'could not run': exit $rc, checks: $(checks)"
rm "$T/bin/ap-check"
write_config "$M" "{ $CONFIG, \"hooks\": { \"check_setup\": \"bash $T/setup.sh\" } }"
unchanged "a check that could not run"

# A branch with its own .claude/ap.json: the batch is checked with its check and setup, not main's.
cat >"$T/own.sh" <<EOF
echo "own \$(basename "\$PWD")" >>"$T/calls"
EOF
C=$T/gh-clone
g -C "$C" fetch -q origin && g -C "$C" checkout -q -B own origin/develop && mkdir -p "$C/.claude" &&
  echo "{ $CONFIG, \"check\": \"bash $T/own.sh\", \"hooks\": { \"check_setup\": \"bash $T/own.sh\" } }" >"$C/.claude/ap.json" &&
  g -C "$C" add .claude/ap.json && g -C "$C" commit -qm own && g -C "$C" push -q origin own &&
  g -C "$C" checkout -q -B develop origin/develop && g -C "$M" fetch -q origin || exit 1
batch check "$RUN" own; rc=$?
[ $rc = 0 ] && [ "$(checks)" = "own check-batch-$RUN,own check-batch-$RUN" ] ||
  fail "a branch with its own settings: exit $rc, checks: $(checks) ($(cat "$T/err"))"
unchanged "a branch with its own settings"

# A red main: every check fails, and no branch is to blame.
echo x >"$T/gh-clone/fail" && g -C "$T/gh-clone" add fail && g -C "$T/gh-clone" commit -qm red && g -C "$T/gh-clone" push -q origin develop || exit 1
g -C "$M" fetch -q origin || exit 1
batch check "$RUN" three; rc=$?
[ $rc = 4 ] || fail "a red main: exit $rc, not 4 ($(cat "$T/out"))"
grep -q "fails the check by itself" "$T/out" || fail "a red main is not named: $(cat "$T/out")"
unchanged "a red main"

[ "$FAILED" = 0 ] && echo "ap-batch: ok"
exit "$FAILED"
