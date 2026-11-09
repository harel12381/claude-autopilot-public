#!/usr/bin/env bash
# Tests ap-background-hook, the plugin's PreToolUse hook (hooks/hooks.json), with the JSON
# Claude Code gives a hook on stdin:
#   - a background command that starts a command of the list is refused (exit 2) with the
#     prefix to add, also after `cd x &&`, `VAR=1`, a folder or `.exe`, and on a later line;
#   - it runs (exit 0): with ap-background in front, in the foreground, a command not on the
#     list (`ap-check`, `git`), a list word only inside quotes or as an argument, another tool,
#     a project with no .claude/ap.json, `background_wrap: []`, and an input it cannot read;
#   - the fix it gives: the prefix for one command, `ap-background bash -c '<all of it>'`
#     (quoted for bash) for a compound one;
#   - a heredoc's body is text, not commands, and a command after it still counts;
#   - a foreground command never starts Python;
#   - `background_wrap` in .claude/ap.json replaces the list, also from a worktree folder below;
#   - hooks/hooks.json is valid JSON and runs this script for the Bash tool.
#
#   bash tests/background-hook-test.sh
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "background-hook-test: $*" >&2; FAILED=1; }
P=$T/project
mkdir -p "$P/web" "$T/other"
write_config "$P" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main" }'

json() { # text: as a JSON string (on stdin: Git Bash would turn a /path argument into C:/...)
  local p
  for p in python3 python; do
    printf '%s' "$1" | "$p" -I -c 'import json, sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null && return
  done
}
native() { # folder: as the programs of this computer write it (Claude Code gives a Windows path there)
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
hook() { # cwd, background (true/false), command, [tool]: runs the hook; $T/err has its words
  printf '{"tool_name":"%s","cwd":%s,"tool_input":{"command":%s,"run_in_background":%s}}' \
    "${4:-Bash}" "$(json "$(native "$1")")" "$(json "$3")" "$2" | ap-background-hook 2>"$T/err"
}
refused() { # command, [cwd]
  local rc=0
  hook "${2:-$P}" true "$1" || rc=$?
  [ $rc = 2 ] || { fail "not refused (exit $rc): $1"; return; }
  grep -qF "ap-background" "$T/err" || fail "refused without saying the prefix: $1: $(cat "$T/err")"
}
runs() { # command, [cwd], [background], [tool]
  local rc=0
  hook "${2:-$P}" "${3:-true}" "$1" "${4:-Bash}" || rc=$?
  [ $rc = 0 ] || fail "refused (exit $rc): $1: $(cat "$T/err")"
}

refused "npm run dev"
refused "cd web && npm run dev -- --port 8100"
refused "PORT=8100 python -m http.server"
refused "/usr/bin/python3 server.py"
refused '"C:/Program Files/Python312/python.exe" server.py'
refused "go run ./cmd/api"
refused "flutter run -d web-server"
refused $'cd web\nnpx vite'
refused "ap-background npm run dev && python other.py"

# The fix it gives: the prefix for one command, `bash -c '<all of it>'` for a compound one.
says() { # command, the fix it must give
  hook "$P" true "$1" >/dev/null 2>&1
  grep -qF -- "\`$2\`" "$T/err" || fail "for '$1' it does not say \`$2\`: $(cat "$T/err")"
}
says "npm run dev" "ap-background npm run dev"
says "cd web && npm run dev" "ap-background bash -c 'cd web && npm run dev'"
says "cd web && echo 'hi' && npm start" "ap-background bash -c 'cd web && echo '\"'\"'hi'\"'\"' && npm start'"

# A heredoc's body is text, not commands; a command after it still counts.
runs $'cat > notes.txt <<\'EOF\'\npython server.py\nnpm run dev\nEOF'
runs $'git commit -F - <<-EOF\n\tpython is named here\n\tEOF'
refused $'cat > a.txt <<EOF\nhello\nEOF\nnpm run dev'
says $'cat > a.txt <<EOF\nhello\nEOF\nnpm run dev' $'ap-background bash -c \'cat > a.txt <<EOF\nhello\nEOF\nnpm run dev\''
runs "cat <<< 'python here'"

runs "ap-background npm run dev"
runs "cd web && ap-background flutter run -d web-server"
runs "npm run dev" "$P" false
runs "ap-check"
runs "git log --oneline | head -5"
runs "echo 'python server.py'"
runs "gh issue comment 5 --body \"start python later\""
runs "npm run dev" "$P" true PowerShell
runs "npm run dev" "$T/other"

# The project's own list, read from a folder below the project too (a worktree).
write_config "$P" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main", "background_wrap": ["make serve"] }'
refused "make serve" "$P/web"
runs "npm run dev" "$P/web"
write_config "$P" '{ "repo": "o/n", "owner": "Dana", "main_branch": "main", "background_wrap": [] }'
runs "make serve"

# A foreground command never starts Python (most Bash calls are such).
mkdir "$T/fakepy"
for p in python3 python; do printf '#!/usr/bin/env bash\ntouch "%s/python-ran"\n' "$T" >"$T/fakepy/$p"; done
chmod +x "$T/fakepy/"*
printf '{"tool_name":"Bash","tool_input":{"command":"npm run dev","run_in_background":false}}' |
  PATH="$T/fakepy:$PATH" ap-background-hook || fail "a foreground command: refused"
[ ! -e "$T/python-ran" ] || fail "a foreground command started Python"
printf '{"tool_name":"Bash","tool_input":{"command":"npm run dev","run_in_background": true}}' |
  PATH="$T/fakepy:$PATH" ap-background-hook 2>/dev/null
[ -e "$T/python-ran" ] || fail "a background command did not reach Python"

# An input it cannot read lets the command run.
rc=0; echo 'not json' | ap-background-hook 2>/dev/null || rc=$?
[ $rc = 0 ] || fail "an input it cannot read: exit $rc"
write_config "$P" '{ "repo": '
runs "npm run dev"

# hooks/hooks.json: the Bash tool runs this script.
H=$ROOT/plugins/ap/hooks/hooks.json
for p in python3 python; do
  out=$("$p" -I -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
print(" ".join(x["command"] for e in h if e["matcher"] == "Bash" for x in e["hooks"]))' "$H" 2>&1) && break
done
[[ $out == *'${CLAUDE_PLUGIN_ROOT}/bin/ap-background-hook'* ]] || fail "hooks.json does not run ap-background-hook for Bash: $out"

[ "$FAILED" = 0 ] && echo "ap-background-hook: ok"
exit "$FAILED"
