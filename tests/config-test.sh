#!/usr/bin/env bash
# Tests ap-config in a throwaway repository with a main checkout and a linked worktree:
#   - a string, a nested value (dotted key), a number, a boolean and an object are printed;
#   - text with quotes, $, spaces and Hebrew comes out as it is, with no \r;
#   - a missing key, a null value and a missing file: the default, or exit 1;
#   - a worktree and a subfolder read the main checkout's file;
#   - a file that is not JSON, or no Python to read it: exit 2 and a clear message, even with a
#     default (a broken file must never look like an empty setting);
#   - no arguments, or outside a git repository: exit 2.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "config-test: $*" >&2; FAILED=1; }
M=$T/main
g init -q -b develop "$M" && g -C "$M" commit -q --allow-empty -m init || exit 1
g -C "$M" worktree add -q "$M/.claude/worktrees/ap-1" -b b1 || exit 1
mkdir -p "$M/sub/deep"

get() { # folder, ap-config arguments: $T/out, $T/err; its exit code
  (cd "$1" && ap-config "${@:2}" >"$T/out" 2>"$T/err")
}
is() { # what ap-config printed must be this (and exit 0)
  local want=$1 rc=$2 what=$3
  [ "$rc" = 0 ] || { fail "$what: exit $rc ($(cat "$T/err"))"; return; }
  [ "$(cat "$T/out")" = "$want" ] || fail "$what: '$(cat "$T/out")', not '$want'"
}

# No file yet.
get "$M" repo; rc=$?; [ $rc = 1 ] || fail "a missing file: exit $rc, not 1"
get "$M" repo fallback; is fallback $? "a missing file with a default"

write_config "$M" '{
  "repo": "o/n",
  "owner": "הראל \"the owner\" $HOME",
  "main_branch": "develop",
  "board": { "owner": "o", "number": 2 },
  "parts": { "deploy": true, "qa": false },
  "site": null,
  "empty": "",
  "hooks": { "notify": "bash scripts/notify send.sh" }
}'
get "$M" repo; is o/n $? "a string"
get "$M" owner; is 'הראל "the owner" $HOME' $? "Hebrew, quotes and \$"
grep -q $'\r' "$T/out" && fail "the value ends in \\r"
get "$M" hooks.notify; is "bash scripts/notify send.sh" $? "a dotted key"
get "$M" board.number; is 2 $? "a number"
get "$M" parts.deploy; is true $? "a boolean"
get "$M" board; is '{"owner": "o", "number": 2}' $? "an object"
get "$M" empty; is "" $? "an empty string"
get "$M" site; rc=$?; [ $rc = 1 ] || fail "a null value: exit $rc, not 1"
get "$M" site dflt; is dflt $? "a null value with a default"
get "$M" hooks.cleanup; rc=$?; [ $rc = 1 ] || fail "a missing key: exit $rc, not 1"
get "$M" hooks.cleanup ""; is "" $? "a missing key with an empty default"
get "$M" repo.x; rc=$?; [ $rc = 1 ] || fail "a key under a string: exit $rc, not 1"
get "$M/.claude/worktrees/ap-1" repo; is o/n $? "from a linked worktree"
get "$M/sub/deep" main_branch; is develop $? "from a subfolder"

# No Python that runs: fakes of python3 and python that fail, first on PATH.
mkdir "$T/nopy"
for p in python3 python; do printf '#!/bin/sh\nexit 127\n' >"$T/nopy/$p" && chmod +x "$T/nopy/$p"; done
(cd "$M" && PATH="$T/nopy:$PATH" ap-config repo dflt >"$T/out" 2>"$T/err"); rc=$?
[ $rc = 2 ] || fail "no Python: exit $rc, not 2 (printed '$(cat "$T/out")')"
grep -qi "python" "$T/err" || fail "no Python is not said: $(cat "$T/err")"

# A broken file.
write_config "$M" '{ "repo": "o/n", '
get "$M" repo dflt; rc=$?
[ $rc = 2 ] || fail "a file that is not JSON: exit $rc, not 2 (printed '$(cat "$T/out")')"
grep -q "ap.json" "$T/err" || fail "a broken file is not named: $(cat "$T/err")"

# A missing file needs no Python.
rm "$M/.claude/ap.json"
(cd "$M" && PATH="$T/nopy:$PATH" ap-config repo dflt >"$T/out" 2>"$T/err"); is dflt $? "no file and no Python"

get "$M"; rc=$?; [ $rc = 2 ] || fail "no arguments: exit $rc, not 2"
grep -q "usage: ap-config" "$T/err" || fail "the usage does not name ap-config: $(cat "$T/err")"
mkdir "$T/plain"
(cd "$T/plain" && GIT_CEILING_DIRECTORIES=$T ap-config repo dflt >"$T/out" 2>"$T/err"); rc=$?
[ $rc = 2 ] || fail "outside a git repository: exit $rc, not 2"

[ $FAILED = 0 ] && echo "ap-config: ok"
exit $FAILED
