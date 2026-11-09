#!/usr/bin/env bash
# Tests ap-deploy in a throwaway repository with an origin (tests/check-fake.sh), and a fake
# deploy that writes when it runs:
#   - it refuses (exit 3), with no check and no deploy: in a linked worktree, on another branch,
#     with a change not committed, and when the branch is not origin's (ahead, or behind after
#     the fetch);
#   - it runs ap-check on every part, and the deploy only after the check passed; a check that
#     fails: exit 5, no deploy; a deploy that fails: exit 6;
#   - the deploy gets the checked commit (AP_DEPLOY_COMMIT); when origin moved during the check,
#     it refuses (exit 3) and does not deploy;
#   - without check_parts it runs the `check` command; with neither: exit 2;
#   - no `deploy` set: it says so and exits 0;
#   - the deploy lock (ap-deploy.lock) is held while the deploy runs and gone after it, also when
#     the deploy fails, and each deploy adds its start and end to ap-deploy-times.
#
#   bash tests/deploy-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/check-fake.sh
source "$(dirname "$0")/check-fake.sh"
g clone -q --bare "$R" "$T/origin.git" && g -C "$R" remote add origin "$T/origin.git" && g -C "$R" fetch -q origin || exit 1
cat >"$T/deploy.sh" <<EOF
echo "deploy start \${PWD##*/}" >>"$EV"
echo "\${AP_DEPLOY_COMMIT:-}" >"$T/deploy-commit"
[ -d "$COMMON/ap-deploy.lock" ] && echo held >>"$T/deploy-lock"
exit \$(cat "$T/deploy-rc" 2>/dev/null || echo 0)
EOF
cp "$R/.claude/ap.json" "$T/ap.json"
with() { # extra members of ap.json: the test's parts and these
  write_config "$R" "$(sed "s|\"main_branch\": \"main\",|\"main_branch\": \"main\", $1|" "$T/ap.json")"
}
with "\"deploy\": \"bash $T/deploy.sh\","
deploy() { # name, folder: runs ap-deploy there; $T/<name>.out, $T/<name>.rc
  (cd "${2:-$R}" && ap-deploy >"$T/$1.out" 2>&1; echo $? >"$T/$1.rc")
}
deployed() { grep -q "^deploy start" "$EV"; }
refused() { # name, words: exit 3, the words, no check and no deploy
  [ "$(rc "$1")" = 3 ] && grep -q "$2" "$T/$1.out" || fail "$1: not refused with '$2': exit $(rc "$1"), $(out "$1")"
  [ -s "$EV" ] && fail "$1: a check or the deploy ran after a refusal: $(cat "$EV")"
  return 0
}

# The refusals.
g -C "$R" worktree add -q "$R/.claude/worktrees/w" -b w || exit 1
begin; deploy wt "$R/.claude/worktrees/w"; refused wt "not the main checkout"
begin; g -C "$R" switch -q -c w2; deploy branch; refused branch "not on main"
g -C "$R" switch -q main
begin; echo y >"$R/a/code"; deploy dirty; refused dirty "not committed"
g -C "$R" checkout -q -- a/code
begin; echo new >"$R/a/new"; deploy untracked; refused untracked "not committed"
rm "$R/a/new"
begin; g -C "$R" commit -q --allow-empty -m ahead; deploy ahead; refused ahead "not origin/main"
g -C "$R" reset -q --hard origin/main
g clone -q "$T/origin.git" "$T/other" && g -C "$T/other" commit -q --allow-empty -m pushed && g -C "$T/other" push -q origin HEAD:main || exit 1
begin; deploy behind; refused behind "not origin/main"
g -C "$R" merge -q --ff-only origin/main || exit 1

# The check first, then the deploy.
begin; FAKE_FAIL=a/light deploy failing
[ "$(rc failing)" = 5 ] || fail "a failing check: exit $(rc failing), not 5: $(out failing)"
deployed && fail "it deployed after a failing check"
begin; deploy good
[ "$(rc good)" = 0 ] || fail "a good deploy: exit $(rc good): $(out good)"
# The parts that passed in the failing run are skipped; a, which failed there, runs.
for p in a b h m r; do grep -q "^$p: passed" "$T/good.out" || fail "the check did not pass $p before the deploy: $(out good)"; done
ran a/light || fail "the check did not run a again: $(cat "$EV")"
deployed || fail "it did not deploy: $(out good)"
[ "$(tail -1 "$EV")" = "deploy start repo" ] || fail "the deploy did not run last, in the main checkout: $(cat "$EV")"
[ "$(cat "$T/deploy-commit")" = "$(g -C "$R" rev-parse HEAD)" ] || fail "the deploy was not given the checked commit: $(cat "$T/deploy-commit")"
begin; echo 7 >"$T/deploy-rc"; deploy deploy-fails; rm "$T/deploy-rc"
[ "$(rc deploy-fails)" = 6 ] || fail "a failing deploy: exit $(rc deploy-fails), not 6: $(out deploy-fails)"
# The deploy lock: held during both deploys, gone after them, and two lines of times.
[ "$(grep -c held "$T/deploy-lock" 2>/dev/null)" = 2 ] || fail "the deploy lock was not held during each deploy"
[ -d "$COMMON/ap-deploy.lock" ] && fail "the deploy lock is still there after the deploys"
grep -cE '^[0-9]+ [0-9]+$' "$COMMON/ap-deploy-times" | grep -qx 2 || fail "ap-deploy-times has not one line per deploy: $(cat "$COMMON/ap-deploy-times" 2>&1)"

# Without check_parts: the check command; with neither: exit 2.
base='"repo": "o/n", "owner": "O", "main_branch": "main"'
write_config "$R" "{ $base, \"check\": \"echo check >>$EV\", \"deploy\": \"bash $T/deploy.sh\" }"
begin; deploy cmd
[ "$(rc cmd)" = 0 ] && [ "$(head -1 "$EV")" = check ] && deployed || fail "the check command did not run before the deploy: $(out cmd); $(cat "$EV")"
# origin moves during the check: no deploy.
cat >"$T/push.sh" <<EOF
g() { git -c user.name=t -c user.email=t@t "\$@"; }
g -C "$T/other" commit -q --allow-empty -m "during the check" && g -C "$T/other" push -q origin HEAD:main
EOF
write_config "$R" "{ $base, \"check\": \"bash $T/push.sh\", \"deploy\": \"bash $T/deploy.sh\" }"
begin; deploy moved
[ "$(rc moved)" = 3 ] && grep -q "origin/main moved during the check" "$T/moved.out" && ! deployed ||
  fail "origin moved during the check: exit $(rc moved), $(out moved)"
g -C "$R" merge -q --ff-only origin/main || exit 1
write_config "$R" "{ $base, \"deploy\": \"bash $T/deploy.sh\" }"
begin; deploy none
[ "$(rc none)" = 2 ] && ! deployed || fail "no check at all: exit $(rc none), not 2: $(out none)"

# No deploy set.
cp "$T/ap.json" "$R/.claude/ap.json"
begin; deploy nodeploy
[ "$(rc nodeploy)" = 0 ] && grep -q "no deploy" "$T/nodeploy.out" || fail "no deploy set: exit $(rc nodeploy), $(out nodeploy)"

passed_all
