# shellcheck shell=bash
# The first thing every ap-* script loads: it stops at once, with a clear word, in a bash older
# than 5 (the scripts use EPOCHSECONDS, BASHPID and ${x,,}). macOS ships bash 3.2:
# `brew install bash` puts a newer one first on PATH.
if [ "${BASH_VERSINFO[0]:-0}" -lt 5 ]; then
  echo "ap: these scripts need bash 5 or newer, and this is bash $BASH_VERSION (on macOS: brew install bash)" >&2
  exit 2
fi
