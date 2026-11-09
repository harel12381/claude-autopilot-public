#!/usr/bin/env bash
# Tests ap-git-sync in a throwaway repository: a bare "origin", a clone, and two worktrees of it
# that share one .git folder, as the parallel helpers of a run do.
#   - two fetches at once in two worktrees both work, in every round (plain `git fetch` clashes
#     with "incorrect old value provided" in many rounds: see the count it prints);
#   - a push while another worktree fetches arrives on origin;
#   - a push on a branch made from origin/develop goes to origin/<branch>, not to develop;
#   - a push that origin refuses fails, loudly, and `pushed` says it did not arrive;
#   - push never sends the main branch of .claude/ap.json, main or master;
#   - a lock left by a killed run is taken over;
#   - pull moves the branch forward (and -C <dir> works in that folder);
#   - when origin cannot be asked, pushed fails and says so, not "the push failed";
#   - new-branch makes the branch from the newest origin/<main>, deletes the files git does not
#     know, keeps the ignored ones and the local .claude/ files, and refuses a tree that is not clean.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'wait; rm -rf "$T"' EXIT
FAILED=0
fail() { echo "git-sync-test: $*" >&2; FAILED=1; }
# With a timeout where the computer has one (macOS has none by default).
limited() { if command -v timeout >/dev/null; then timeout "$@"; else "${@:2}"; fi; }

g init -q --bare "$T/origin.git"
g init -q -b develop "$T/up" && g -C "$T/up" commit -q --allow-empty -m init \
  && g -C "$T/up" remote add origin "$T/origin.git"
# Many branches, as on GitHub: each fetch writes many refs, so two fetches overlap.
advance() { # a new commit on develop and on 20 other branches of origin
  local refs=() i
  for i in $(seq 1 20); do refs+=("HEAD:refs/heads/b$i"); done
  g -C "$T/up" commit -q --allow-empty -m "c$1" || return 1
  g -C "$T/up" push -q -f origin HEAD:refs/heads/develop "${refs[@]}"
}
advance 0
g clone -q "$T/origin.git" "$T/main" 2>/dev/null
write_config "$T/main" '{ "repo": "o/n", "owner": "O", "main_branch": "develop" }'
g -C "$T/main" worktree add -q -b fix/1-a "$T/wt1" origin/develop
g -C "$T/main" worktree add -q -b fix/2-b "$T/wt2" origin/develop
# The helpers' commits: a user for git in the worktrees.
for w in wt1 wt2; do g -C "$T/$w" config user.name t && g -C "$T/$w" config user.email t@t; done

# 1. Two fetches at once.
plain=0 bad=0 ROUNDS=4
for r in $(seq 1 $ROUNDS); do
  advance "p$r"
  (cd "$T/wt1" && git fetch -q origin) 2>/dev/null & a=$!
  (cd "$T/wt2" && git fetch -q origin) 2>/dev/null & b=$!
  wait $a || plain=$((plain + 1)); wait $b || plain=$((plain + 1))
  advance "s$r"
  (cd "$T/wt1" && ap-git-sync fetch -q) >"$T/f1" 2>&1 & a=$!
  (cd "$T/wt2" && ap-git-sync fetch -q) >"$T/f2" 2>&1 & b=$!
  wait $a || { bad=1; cat "$T/f1"; }; wait $b || { bad=1; cat "$T/f2"; }
done
echo "git-sync-test: plain git fetch clashed $plain times in $ROUNDS rounds of two at once"
[ $bad = 0 ] || fail "two fetches at once: one failed"
[ "$(g -C "$T/main" rev-parse origin/develop)" = "$(g -C "$T/up" rev-parse HEAD)" ] \
  || fail "after the fetches, origin/develop is not the newest develop"

# 2. A push while another worktree fetches, on a branch made from origin/develop.
g -C "$T/wt1" commit -q --allow-empty -m mine
advance push
(cd "$T/wt2" && ap-git-sync fetch -q) >"$T/f2" 2>&1 & b=$!
(cd "$T/wt1" && ap-git-sync push) >"$T/p1" 2>&1 || { fail "push while another worktree fetches failed"; cat "$T/p1"; }
wait $b || { fail "fetch while another worktree pushes failed"; cat "$T/f2"; }
[ "$(g -C "$T/origin.git" rev-parse -q --verify refs/heads/fix/1-a)" = "$(g -C "$T/wt1" rev-parse HEAD)" ] \
  || fail "the push did not reach origin/fix/1-a"
[ "$(g -C "$T/origin.git" rev-parse refs/heads/develop)" = "$(g -C "$T/up" rev-parse HEAD)" ] \
  || fail "the push changed develop on origin"
[ "$(g -C "$T/wt1" rev-parse --abbrev-ref '@{upstream}')" = origin/fix/1-a ] \
  || fail "after the push, the branch's upstream is not origin/fix/1-a"
(cd "$T/wt1" && ap-git-sync pushed) >/dev/null 2>&1 || fail "pushed says no after a push that arrived"

# 3. A push that origin refuses.
mkdir -p "$T/origin.git/hooks"
printf '#!/bin/sh\necho refused by the test >&2\nexit 1\n' >"$T/origin.git/hooks/pre-receive"
chmod +x "$T/origin.git/hooks/pre-receive"
g -C "$T/wt1" commit -q --allow-empty -m refused
if (cd "$T/wt1" && ap-git-sync push) >"$T/p1" 2>&1; then fail "a refused push looked like it worked"; fi
grep -q "refused by the test" "$T/p1" || fail "a refused push hid git's words"
if (cd "$T/wt1" && ap-git-sync pushed) >/dev/null 2>&1; then fail "pushed says yes after a refused push"; fi
rm "$T/origin.git/hooks/pre-receive"

# 4. Never the main branch of .claude/ap.json (develop here), main or master; a broken
# .claude/ap.json stops a push.
g -C "$T/main" switch -q develop 2>/dev/null || g -C "$T/main" switch -q -c develop origin/develop
g -C "$T/main" commit -q --allow-empty -m "not for origin"
if (cd "$T/main" && ap-git-sync push) >"$T/p1" 2>&1; then fail "push sent develop, the main branch of ap.json"; fi
grep -q "never push develop" "$T/p1" || fail "a refused push of develop does not say why: $(cat "$T/p1")"
for b in main master; do
  g -C "$T/wt2" switch -q -c "$b"
  if (cd "$T/wt2" && ap-git-sync push) >/dev/null 2>&1; then fail "push sent $b"; fi
  g -C "$T/origin.git" rev-parse -q --verify "refs/heads/$b" >/dev/null && fail "$b reached origin"
  g -C "$T/wt2" switch -q fix/2-b
done
write_config "$T/main" '{ "repo": '
if (cd "$T/wt2" && ap-git-sync push) >"$T/p1" 2>&1; then fail "push went on with a broken .claude/ap.json"; fi
write_config "$T/main" '{ "repo": "o/n", "owner": "O", "main_branch": "develop" }'
(cd "$T/wt2" && ap-git-sync push) >"$T/p1" 2>&1 || fail "push of a topic branch failed: $(cat "$T/p1")"

# 5. A lock left by a killed run.
COMMON=$(g -C "$T/wt1" rev-parse --path-format=absolute --git-common-dir)
mkdir "$COMMON/ap-git.lock" && echo "999999 $T/wt2 (since 00:00:00) fetch" >"$COMMON/ap-git.lock/owner"
(cd "$T/wt1" && limited 30 ap-git-sync fetch -q) >/dev/null 2>&1 || fail "a lock of a killed run was not taken over"
[ ! -d "$COMMON/ap-git.lock" ] || fail "the lock was left behind"

# 6. Pull.
g -C "$T/main" reset -q --hard origin/develop
advance pull
ap-git-sync -C "$T/main" pull >/dev/null 2>&1 || fail "pull (with -C) failed"
[ "$(g -C "$T/main" rev-parse HEAD)" = "$(g -C "$T/up" rev-parse HEAD)" ] || fail "pull did not move develop forward"

# 7. Origin cannot be asked (a network error): pushed fails, and says so, not "the push failed".
mv "$T/origin.git" "$T/gone.git"
if (cd "$T/wt1" && ap-git-sync pushed) >"$T/p1" 2>&1; then fail "pushed says yes when origin cannot be asked"; fi
mv "$T/gone.git" "$T/origin.git"
grep -q "could not ask origin" "$T/p1" || fail "pushed hid that origin could not be asked: $(cat "$T/p1")"

# 8. new-branch: fetch, a new branch from origin/<main>, and git clean -fd without -x. The old
# branch ignores out/, so after the switch out/ is a folder git does not know: it goes. build/ is
# ignored on every branch (the repository's exclude file): it stays, as a build cache does.
advance newbranch
W=$T/wt2
echo "build/" >>"$(g -C "$W" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
g -C "$W" switch -q -c chore/3-old origin/develop
echo "out/" >"$W/.gitignore" && g -C "$W" add .gitignore && g -C "$W" commit -q -m "old branch"
mkdir -p "$W/out" "$W/build" "$W/.claude"
echo o >"$W/out/old" && echo c >"$W/build/cache" && echo m >"$W/.claude/local" && echo s >"$W/stray.txt"
if (cd "$W" && ap-git-sync new-branch fix/4-new) >"$T/n1" 2>&1; then fail "new-branch went on in a tree with a file not committed"; fi
grep -q "not clean" "$T/n1" || fail "a refused new-branch does not say why: $(cat "$T/n1")"
[ "$(g -C "$W" branch --show-current)" = chore/3-old ] || fail "a refused new-branch switched the branch"
[ -f "$W/stray.txt" ] || fail "a refused new-branch deleted a file"
rm "$W/stray.txt"
(cd "$W" && ap-git-sync new-branch fix/4-new) >"$T/n1" 2>&1 || fail "new-branch failed: $(cat "$T/n1")"
[ "$(g -C "$W" branch --show-current)" = fix/4-new ] || fail "new-branch is not on the new branch"
[ "$(g -C "$W" rev-parse HEAD)" = "$(g -C "$T/up" rev-parse HEAD)" ] || fail "new-branch did not start from the newest origin/develop"
[ ! -e "$W/out" ] || fail "new-branch kept a folder git does not know (out/)"
[ -f "$W/build/cache" ] || fail "new-branch deleted an ignored file (a build cache)"
[ -f "$W/.claude/local" ] || fail "new-branch deleted a local .claude/ file"
if (cd "$W" && ap-git-sync new-branch) >/dev/null 2>&1; then fail "new-branch with no branch name passed"; fi
if (cd "$W" && ap-git-sync new-branch fix/4-new) >/dev/null 2>&1; then fail "new-branch made a branch that is already there"; fi

ap-git-sync nothing 2>"$T/p1" && fail "an unknown command passed"
grep -q "usage: ap-git-sync" "$T/p1" || fail "the usage does not name ap-git-sync: $(cat "$T/p1")"

[ $FAILED = 0 ] && echo "ap-git-sync: ok"
exit $FAILED
