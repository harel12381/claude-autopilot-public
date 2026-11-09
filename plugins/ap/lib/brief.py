# The brief of one agent of /ap:run, for ap-brief. It reads .claude/ap.json on stdin, adds the
# project's own part (briefs.<name>) to the plugin's brief, fills in every <WORD> that
# CONTRACT.md names ("The briefs"), and writes the result to the file given. A word it cannot
# fill (a value the command line did not give) is an error: no brief goes out with a word in it
# that the agent would read as text. Exit codes as config.sh's reader: 10 written (the file's path
# on stdout), 12 an error (said on stdout).
#
#   python -I -c "<this file>" <name> <plugin> <checkout> <common> <out> [--n "47 81"] [--run R]
#     [--pr P] [--slot S] [--worktree W] [--date D] [--scratchpad F] [--note T]

import datetime
import json
import os
import posixpath
import re
import sys

NAMES = ("helper", "planner", "reviewer", "retro")
# The words an agent fills in itself, in its own brief: each stays as it is.
OWN = {"helper": {"PR"}, "retro": {"M"}}
FLAGS = ("--n", "--run", "--pr", "--slot", "--worktree", "--date", "--scratchpad", "--note")
PROJECT_LINE = ("**This project's own rules** (they add to the rules above; where they say more, "
                "follow them):")


class Bad(Exception):
    pass


def read(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read()


def parse(argv):
    if len(argv) < 5 or argv[0] not in NAMES:
        raise Bad("usage: ap-brief <%s> [--n \"47 81\"] [--run R] [--pr P] [--slot S] [--worktree W] "
                  "[--date D] [--scratchpad F] [--note T]" % "|".join(NAMES))
    name, plugin, checkout, common, out = argv[:5]
    opts, rest = {}, argv[5:]
    while rest:
        flag = rest.pop(0)
        if flag not in FLAGS or not rest:
            raise Bad("unknown or empty option: %s" % flag)
        opts[flag[2:]] = rest.pop(0)
    numbers = (opts.get("n") or "").replace(",", " ").split()
    if any(not re.fullmatch(r"#?[0-9]+", x) for x in numbers):
        raise Bad("--n takes issue numbers: %s" % opts["n"])
    opts["numbers"] = [x.lstrip("#") for x in numbers]
    for key in ("run", "pr", "slot"):
        if key in opts and not re.fullmatch(r"#?[0-9]+", opts[key]):
            raise Bad("--%s takes a number: %s" % (key, opts[key]))
        if key in opts:
            opts[key] = opts[key].lstrip("#")
    if "worktree" in opts and not re.fullmatch(r"ap-[0-9]+[b-z]", opts["worktree"]):
        raise Bad("--worktree takes a queue worktree's name, such as ap-1b: %s" % opts["worktree"])
    return name, plugin, checkout, common, out, opts


def setting(conf, key):
    value = conf
    for part in key.split("."):
        if not isinstance(value, dict) or value.get(part) is None:
            return None
        value = value[part]
    return value


def project_files(conf, checkout):
    briefs = setting(conf, "briefs") or {}
    if not isinstance(briefs, dict):
        raise Bad(".claude/ap.json: briefs must be an object")
    found = {}
    for key, rel in briefs.items():
        if isinstance(rel, str) and os.path.isfile(os.path.join(checkout, rel)):
            found[key] = rel
    return found


def values(name, conf, plugin, checkout, common, opts, files):
    # The paths go to agents that run them in bash: always with /, also from a Windows Python.
    v = {"DOCS": posixpath.join(plugin, "docs"), "PLUGIN": plugin, "CHECKOUT": checkout,
         "SCRATCHPAD": opts.get("scratchpad") or posixpath.join(common, "ap-autopilot", "tmp"),
         "DATE": opts.get("date") or datetime.date.today().isoformat(),
         "MAIN": setting(conf, "main_branch") or "main",
         "PROJECT_BRIEFS": ", ".join(files.values()) or "none"}
    for word, key in (("REPO", "repo"), ("OWNER", "owner"), ("CHECK", "check")):
        if isinstance(setting(conf, key), str):
            v[word] = setting(conf, key)
    cleanup = setting(conf, "hooks.cleanup")
    if isinstance(cleanup, str) and cleanup.strip():
        older = " --older-than 90" if name == "helper" and "slot" in opts else ""
        v["CLEANUP"] = "`%s%s`" % (cleanup, older)
    else:
        v["CLEANUP"] = "none is set: skip it"
    if "run" in opts:
        v["RUN"] = opts["run"]
    if opts["numbers"]:
        v["N"] = " ".join(opts["numbers"])
        v["LIST"] = " ".join("#" + x for x in opts["numbers"])
    if name == "reviewer" and "pr" in opts:
        v["PR"] = opts["pr"]
    return v


def board_line(conf):
    board = setting(conf, "board")
    if not isinstance(board, dict) or board.get("number") is None or not board.get("owner"):
        return None
    return ("- **The board.** Every issue you open goes on it: `gh project item-add %s --owner %s "
            "--url <issue url>`. When that fails, write the error in one line on the issue and go on."
            % (board["number"], board["owner"]))


def make(name, conf, plugin, checkout, common, opts):
    text = read(os.path.join(plugin, "briefs", name + ".md")).rstrip("\n")
    files = project_files(conf, checkout)
    if name in files:
        text += "\n\n" + PROJECT_LINE + "\n\n" + read(os.path.join(checkout, files[name])).strip("\n")
    board = board_line(conf)
    lines = []
    for line in text.split("\n"):
        if "<BOARD>" in line:
            if board is None:
                continue
            line = line.replace("<BOARD>", board)
        lines.append(line)
    text = "\n".join(lines)
    v = values(name, conf, plugin, checkout, common, opts, files)
    text = re.sub(r"<([A-Z][A-Z_]*)>", lambda m: v.get(m.group(1), m.group(0)), text)
    left = sorted(set(re.findall(r"<([A-Z][A-Z_]*)>", text)) - OWN.get(name, set()))
    if left:
        raise Bad("the %s brief still has %s: give the values (ap-brief --help) or set them in .claude/ap.json"
                  % (name, ", ".join("<%s>" % w for w in left)))
    if name == "helper" and "slot" in opts:
        text += "\n\nYour slot is %s." % opts["slot"]
        if "worktree" in opts:
            text += "\nYour worktree is %s." % opts["worktree"]
    if opts.get("note"):
        text += "\n\n" + opts["note"].strip()
    return text + "\n"


def say(text):
    """Out as UTF-8, as config.sh's reader does: a Windows pipe's code page cannot hold every path."""
    sys.stdout.buffer.write(text.encode("utf-8"))


def main():
    try:
        name, plugin, checkout, common, out, opts = parse(sys.argv[1:])
        try:
            conf = json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))
        except ValueError as e:
            raise Bad(".claude/ap.json is not valid JSON: %s" % e)
        if not isinstance(conf, dict):
            raise Bad(".claude/ap.json must be an object")
        text = make(name, conf, plugin, checkout, common, opts)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        say(out)
        sys.exit(10)
    except Bad as e:
        say("ap-brief: %s" % e)
        sys.exit(12)
    except SystemExit:
        raise
    except BaseException as e:
        say("ap-brief: %s" % e)
        sys.exit(12)


main()
