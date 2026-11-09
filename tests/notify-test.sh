#!/usr/bin/env bash
# Tests ap-notify with a fake hooks.notify (set in a temporary .claude/ap.json) that writes down
# its arguments, one per line, then the text it got on its input:
#   - a title, a text and a link with quotes, $, backticks and new lines reach the hook as they
#     are, as --title, --url and the input; --high adds --high, and only then;
#   - --hold: a second message of a title within the time is kept, and goes with the next message
#     that is sent, of any title, once;
#   - a hook that fails: exit 1, and the kept messages stay;
#   - no hook set: the message is printed, it says so, exit 0;
#   - a message with no text is not sent.
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "notify-test: $*" >&2; exit 1; }

M=$T/main
g init -q -b develop "$M" && g -C "$M" commit -q --allow-empty -m init
mkdir "$T/state"
cat >"$T/hook.sh" <<EOF
#!/usr/bin/env bash
[ ! -f "$T/hook-fails" ] || exit 5
{ printf '%s\n' "\$@"; echo ---; cat; } >"$T/got"
EOF
CONFIG="{ \"repo\": \"o/n\", \"owner\": \"O\", \"main_branch\": \"develop\",
  \"hooks\": { \"notify\": \"bash $T/hook.sh\" } }"
write_config "$M" "$CONFIG"

send() { # ap-notify arguments; then $T/got is what the hook got ("" when nothing was sent)
  rm -f "$T/got"
  (cd "$M" && AP_NOTIFY_STATE=$T/state ap-notify "$@" >"$T/out")
  [ -f "$T/got" ] || : >"$T/got"
}
has() { grep -qxF -- "$1" "$T/got" || fail "$2 (the hook got: $(tr '\n' '|' <"$T/got"))"; }

title='Run "ended": $HOME & it'"'"'s done'
send "$title" $'2 merged\n1 waits for the owner: $PATH `x`' 'https://example.org/issues/1?a=1&b=$x'
has "--title" "--title is missing"
has "$title" "the title did not arrive as it is"
has "--url" "the link is missing"
has 'https://example.org/issues/1?a=1&b=$x' "the link did not arrive as it is"
has "2 merged" "the first line of the text is missing"
has '1 waits for the owner: $PATH `x`' "the second line of the text did not arrive as it is"
grep -qxF -- --high "$T/got" && fail "a plain message is sent with --high"
grep -q "^Sent: " "$T/out" || fail "a sent message is not said: $(cat "$T/out")"

send --high "Run stopped" "The disk is low."
has "--high" "--high was not passed to the hook"
grep -qxF -- --url "$T/got" && fail "a message with no link is sent with --url"

# --hold: the second message within the time waits, and goes with the next one that is sent.
send --hold 30 "Owner is needed" "#1: which colour?"
has "#1: which colour?" "the first held-kind message was not sent"
send --hold 30 "Owner is needed" "#2: which name?"
[ -s "$T/got" ] && fail "a second message within 30 minutes was sent at once"
grep -q "^Held" "$T/out" || fail "a held message is not said: $(cat "$T/out")"
backdate "$T/state/ap-notify.sent-Owner_is_needed" 31
send --hold 30 "Owner is needed" "#3: which icon?"
has "#2: which name?" "the held message was lost"
has "#3: which icon?" "the new message was lost"
send --hold 30 "Another title" "#4"
has "#4" "--hold of one title held a message of another title"
# A message held at the end of a run goes with the run's last message, not with the next run.
send --hold 30 "Owner is needed" "#5: which sound?"
[ -s "$T/got" ] && fail "a message within 30 minutes of the last one of its title was sent at once"
# A hook that fails: exit 1, and the held message stays for the next one.
touch "$T/hook-fails"
if (cd "$M" && AP_NOTIFY_STATE=$T/state ap-notify "Run ended" "3 merged." >/dev/null 2>"$T/err"); then
  fail "a hook that failed looked like it sent"
fi
grep -q "hooks.notify failed" "$T/err" || fail "a failed hook is not said: $(cat "$T/err")"
rm "$T/hook-fails"
send "Run ended" "3 merged."
has "3 merged." "the end message was lost"
has "#5: which sound?" "a held message did not go with the next message of another title"
send "Run ended" "Again."
grep -qxF -- "#5: which sound?" "$T/got" && fail "a held message was sent twice"

# No hook: printed, and said, exit 0.
write_config "$M" '{ "repo": "o/n", "owner": "O", "main_branch": "develop" }'
send "Plain" "Only here." || fail "no hook: ap-notify failed"
[ -s "$T/got" ] && fail "no hook set, but the old hook ran"
grep -qxF "Only here." "$T/out" || fail "no hook: the text is not printed: $(cat "$T/out")"
grep -q "No hooks.notify" "$T/out" || fail "no hook: it does not say so: $(cat "$T/out")"

if (cd "$M" && ap-notify "only a title" 2>/dev/null); then fail "a message with no text was sent"; fi
echo "ap-notify: ok"
