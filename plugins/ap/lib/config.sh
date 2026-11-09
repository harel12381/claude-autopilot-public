# shellcheck shell=bash
# The project's settings: .claude/ap.json in the main checkout, the folder of the repository's
# common .git (every worktree reads the same file). What checks a tree (the check, its parts and
# its setup) reads the tree's own file instead, so a branch is checked with the settings it has.
# Loaded with `source`; it only defines functions. Their exit codes: 0 a value, 1 not set
# (missing or null), 2 an error, said on stderr.

ap_main() { # prints the main checkout of the current folder's repository
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    echo "ap: $PWD is not inside a git repository" >&2
    return 2
  }
  dirname "$common"
}

# The reader. The file comes on stdin (so a native Windows Python needs no Git Bash path), the
# key and the file's name (for the error) as arguments. The value goes out as UTF-8 with a plain
# newline; a value that is no string goes out as JSON. Its own exit codes (10 a value, 11 not set,
# 12 an error, said on stdout) tell its answer from a Python that does not run: on Windows,
# python3 can be a stub that only offers to install Python, with words on stderr, which are
# dropped. -I keeps the folder's own files out of its imports.
AP_CONFIG_PY='
import sys
try:
    import json
    key, name = sys.argv[1], sys.argv[2]
    try:
        value = json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))
    except ValueError as e:
        sys.stdout.write("ap-config: %s is not valid JSON: %s" % (name, e))
        sys.exit(12)
    for part in key.split("."):
        if not isinstance(value, dict) or part not in value:
            sys.exit(11)
        value = value[part]
    if value is None:
        sys.exit(11)
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    sys.stdout.buffer.write((text + "\n").encode("utf-8"))
    sys.exit(10)
except SystemExit:
    raise
except BaseException as e:
    sys.stdout.write("ap-config: %s" % e)
    sys.exit(12)
'

ap_python() { # code, file, args...: runs the code in Python with the file on stdin and the args;
  # prints what it wrote. 0 a value (its exit 10), 1 not set (11), 2 an error (12, its words go to
  # stderr) or no Python runs. The codes of AP_CONFIG_PY below; any other code is a Python that
  # does not run, and the next one is tried.
  local code=$1 file=$2 p out rc
  shift 2
  for p in python3 python; do
    command -v "$p" >/dev/null 2>&1 || continue
    rc=0
    out=$("$p" -I -c "$code" "$@" <"$file" 2>/dev/null) || rc=$?
    case $rc in
      10) printf '%s\n' "$out"; return 0 ;;
      11) return 1 ;;
      12) printf '%s\n' "$out" >&2; return 2 ;;
    esac
  done
  echo "ap: reading .claude/ap.json needs Python 3 (python3 or python), and neither runs here" >&2
  return 2
}

ap_read() { # file, key: prints the value; 0 a value, 1 not set, 2 an error
  ap_python "$AP_CONFIG_PY" "$1" "$2" "$1"
}

ap_config_file() { # [folder]: prints the settings file: the folder's own .claude/ap.json when it
  # has one, else (or with no folder) the main checkout's
  local main
  if [ -n "${1:-}" ] && [ -f "$1/.claude/ap.json" ]; then
    echo "$1/.claude/ap.json"
    return
  fi
  main=$(ap_main) || return 2
  echo "$main/.claude/ap.json"
}

ap_config() { # key [default]: prints the value; when it is not set, the default (exit 0), or exit 1
  ap_config_at "" "$@"
}

ap_config_at() { # folder, key [default]: as ap_config, from the folder's settings file (ap_config_file)
  local file rc=0
  file=$(ap_config_file "$1") || return 2
  shift
  if [ -f "$file" ]; then
    ap_read "$file" "$1" || rc=$?
    [ $rc = 1 ] || return $rc
  fi
  [ $# -ge 2 ] || return 1
  printf '%s\n' "$2"
}
