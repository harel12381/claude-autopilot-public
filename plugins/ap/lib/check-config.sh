# shellcheck shell=bash
# The parts of ap-check: `check_parts` and `check_options` of .claude/ap.json. Loaded with
# `source` after config.sh; it defines functions and the reader below.
#
# check_config_load <file> fills, for each part (in the order of the file):
#   PART_NAMES          the names
#   PART_DIR[name]      the folder its steps run in, relative to the repository's root ("." for it)
#   PART_LIGHT[name]    its light command, empty when it has none
#   PART_HEAVY[name]    its heavy command, empty when it has none
#   PART_FIRST[name]    1 when its light steps come first (light_first), else 0
#   PART_VERSION[name]  its version, as text
#   PART_WHEN[name]     the retry pattern, empty when it has no retry
#   PART_RETRY[name]    the retry command
#   PART_RHEAVY[name]   1 when the retry runs under the heavy lock (retry.heavy), else 0
#   PART_INPUTS[name]   its inputs, one per line
# and LIGHT_MIN_MB, STEP_LIMIT_S (check_options; the limit in seconds, 0 for none).
# Exit codes: 0 read, 1 no check_parts, 2 an error (said on stderr).

# The reader: the file on stdin, its name as the argument. Each value goes out followed by the
# separator \x1f (no value may hold one): the two options, then ten values for each part. The
# exit codes are those of AP_CONFIG_PY (config.sh). A wrong value is named with its part.
CHECK_CONFIG_PY='
import sys
try:
    import json, math, re
    name = sys.argv[1]
    def bad(text):
        sys.stdout.write("ap-check: %s: %s" % (name, text))
        sys.exit(12)
    try:
        conf = json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))
    except ValueError as e:
        bad("not valid JSON: %s" % e)
    if not isinstance(conf, dict) or conf.get("check_parts") is None:
        sys.exit(11)
    parts = conf["check_parts"]
    if not isinstance(parts, list) or not parts:
        bad("check_parts must be a list of parts")
    opts = conf.get("check_options") or {}
    if not isinstance(opts, dict):
        bad("check_options must be an object")
    extra = sorted(set(opts) - {"light_min_mb", "step_limit_min"})
    if extra:
        bad("check_options: unknown keys %s" % ", ".join(extra))
    def number(key, default):
        v = opts.get(key, default)
        if v is None:
            v = default
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0 or math.isinf(v) or v != v:
            bad("check_options.%s must be a number, 0 or more" % key)
        return v
    out = [str(int(number("light_min_mb", 3000))), str(int(round(number("step_limit_min", 45) * 60)))]
    def text(v):
        if "\x1f" in v or "\x00" in v:
            bad("a value with a control character: %r" % v)
        return v
    seen = set()
    for i, p in enumerate(parts):
        if not isinstance(p, dict):
            bad("check_parts[%d] must be an object" % i)
        n = p.get("name")
        if not isinstance(n, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", n) or n.startswith("-"):
            bad("check_parts[%d]: a name of letters, digits, _ . - (got %r)" % (i, n))
        if n in seen:
            bad("two parts are named %s" % n)
        seen.add(n)
        known = {"name", "inputs", "dir", "light", "heavy", "light_first", "version", "retry"}
        extra = sorted(set(p) - known)
        if extra:
            bad("part %s: unknown keys %s" % (n, ", ".join(extra)))
        ins = p.get("inputs")
        if not isinstance(ins, list) or not ins or not all(isinstance(x, str) and x.strip() for x in ins):
            bad("part %s: inputs must be a list of paths" % n)
        clean = []
        for x in ins:
            x = x.strip().replace("\\", "/").strip("/") or "."
            if "\n" in x or x.startswith("../") or x == ".." or re.match(r"^[A-Za-z]:", x):
                bad("part %s: an input must be a path inside the repository: %r" % (n, x))
            clean.append(x)
        d = p.get("dir") or "."
        if not isinstance(d, str):
            bad("part %s: dir must be a path" % n)
        cmds = []
        for k in ("light", "heavy"):
            c = p.get(k)
            if c is not None and not isinstance(c, str):
                bad("part %s: %s must be a command" % (n, k))
            cmds.append(text(c if c and c.strip() else ""))
        if not cmds[0] and not cmds[1]:
            bad("part %s: it needs a light or a heavy command" % n)
        first = p.get("light_first", False)
        if not isinstance(first, bool):
            bad("part %s: light_first must be true or false" % n)
        v = p.get("version", 1)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            bad("part %s: version must be a number" % n)
        r = p.get("retry")
        when = run = ""
        rheavy = False
        if r is not None:
            if not isinstance(r, dict) or not isinstance(r.get("when"), str) or not isinstance(r.get("run"), str) \
                    or not r["when"] or not r["run"].strip():
                bad("part %s: retry must be { \"when\": \"<pattern>\", \"run\": \"<command>\" }" % n)
            extra = sorted(set(r) - {"when", "run", "heavy"})
            if extra:
                bad("part %s: retry: unknown keys %s" % (n, ", ".join(extra)))
            rheavy = r.get("heavy", False)
            if not isinstance(rheavy, bool):
                bad("part %s: retry.heavy must be true or false" % n)
            when, run = r["when"], r["run"]
        out += [n, text(d), cmds[0], cmds[1], "1" if first else "0", str(v), text(when), text(run),
                "1" if rheavy else "0", text("\n".join(clean))]
    sys.stdout.buffer.write("".join(x + "\x1f" for x in out).encode("utf-8"))
    sys.exit(10)
except SystemExit:
    raise
except BaseException as e:
    sys.stdout.write("ap-check: %s" % e)
    sys.exit(12)
'

check_config_file() { # prints the settings file the parts come from: the checked tree's (ap_config_file)
  local root
  root=$(git rev-parse --show-toplevel) || return 2
  ap_config_file "$root"
}

check_config_load() { # file: see above
  local out rc=0 v i n
  [ -f "$1" ] || return 1
  out=$(ap_python "$CHECK_CONFIG_PY" "$1" "$1") || rc=$?
  [ $rc = 0 ] || return $rc
  IFS=$'\x1f' read -r -d '' -a v <<<"$out" || true
  LIGHT_MIN_MB=${v[0]} STEP_LIMIT_S=${v[1]}
  PART_NAMES=()
  declare -gA PART_DIR=() PART_LIGHT=() PART_HEAVY=() PART_FIRST=() PART_VERSION=() PART_WHEN=() PART_RETRY=() \
    PART_RHEAVY=() PART_INPUTS=()
  for ((i = 2; i + 9 < ${#v[@]}; i += 10)); do
    n=${v[i]}
    PART_NAMES+=("$n")
    PART_DIR[$n]=${v[i + 1]} PART_LIGHT[$n]=${v[i + 2]} PART_HEAVY[$n]=${v[i + 3]} PART_FIRST[$n]=${v[i + 4]}
    PART_VERSION[$n]=${v[i + 5]} PART_WHEN[$n]=${v[i + 6]} PART_RETRY[$n]=${v[i + 7]} PART_RHEAVY[$n]=${v[i + 8]}
    PART_INPUTS[$n]=${v[i + 9]}
  done
}
