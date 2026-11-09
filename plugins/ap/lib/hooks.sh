# shellcheck shell=bash
# The project's hooks: shell commands in the "hooks" part of .claude/ap.json. Loaded with
# `source`; it only defines functions.

# shellcheck source=plugins/ap/lib/config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

hook_cmd() { # name [folder]: prints hooks.<name>, empty when it is not set; exit 2 when the
  # settings cannot be read (ap_config has said why). With a folder, from its settings (ap_config_at).
  ap_config_at "${2:-}" "hooks.$1" ""
}

hook_run() { # command, folder, args...: runs the command in bash in that folder, with the args
  # added at its end; its exit code. Its input is this script's.
  local cmd=$1 dir=$2
  shift 2
  (cd "$dir" && bash -c "$cmd"' "$@"' ap-hook "$@")
}
