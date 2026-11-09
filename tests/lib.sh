# shellcheck shell=bash
# What every test shares. Loaded with `source` by the test files.
#   - BIN: the plugin's bin/ folder, put first on PATH, so the tests run the scripts by their names
#     as the skills do (this also checks that each script finds its lib/ from its real path);
#   - wait_until (lib/wait.sh) and pid_runs (lib/proc-tree.sh);
#   - backdate <file> <minutes>: sets the file's time that many minutes back, with GNU or BSD tools;
#   - g: git with a user and plain line endings, for the throwaway repositories.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$ROOT/plugins/ap/bin
export PATH="$BIN:$PATH"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
# shellcheck source=plugins/ap/lib/wait.sh
source "$ROOT/plugins/ap/lib/wait.sh"
# shellcheck source=plugins/ap/lib/proc-tree.sh
source "$ROOT/plugins/ap/lib/proc-tree.sh"

backdate() { # file, minutes ago
  local t=$((EPOCHSECONDS - $2 * 60))
  touch -d "@$t" "$1" 2>/dev/null || touch -t "$(date -r "$t" +%Y%m%d%H%M.%S)" "$1"
}

g() { git -c user.name=t -c user.email=t@t -c core.autocrlf=false -c advice.detachedHead=false "$@"; }

# write_config <main checkout> <json>: the project's .claude/ap.json
write_config() {
  mkdir -p "$1/.claude"
  printf '%s\n' "$2" >"$1/.claude/ap.json"
}
