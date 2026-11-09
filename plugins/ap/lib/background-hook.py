# The decision of bin/ap-background-hook: whether a Bash command that an agent starts in the
# background must start with ap-background. It reads the hook's JSON on stdin (tool_name,
# tool_input.command, tool_input.run_in_background, cwd). Its exit code is 10 (let it run) or 12
# (refuse it: the words why are on stdout).
#
#   python -I -c "<this file>" < hook-input.json
#
# It refuses only a background command of a project that has .claude/ap.json, when one of the
# simple commands in it starts with a command of the list: `background_wrap` in .claude/ap.json,
# or DEFAULT_WRAP when it is not set ([] turns the hook off). A command that starts with
# ap-background, or a line it cannot read, runs.
import json
import os
import re
import shlex
import sys

DEFAULT_WRAP = ["python", "python3", "py", "node", "npm run", "npm start", "npx", "yarn", "pnpm",
                "go run", "cargo run", "dotnet run", "flutter run", "flutter build", "java",
                "docker compose up"]
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
PREFIXES = {"exec", "nohup", "time", "command", "env", "then", "do", "else", "!", "{"}


def project_config(cwd):
    """The .claude/ap.json of the project that holds cwd (a worktree too), or None."""
    path = os.path.abspath(cwd or ".")
    while True:
        f = os.path.join(path, ".claude", "ap.json")
        if os.path.isfile(f):
            with open(f, encoding="utf-8") as fh:
                return json.load(fh)
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent


def name(word):
    """A command word as the list names it: no folder, no .exe."""
    word = word.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return word[:-4] if word.endswith(".exe") else word


def without_heredocs(command):
    """The command without the bodies of its heredocs (`<<EOF` ... `EOF`): their lines are text
    for a command, not commands."""
    out, ends = [], []
    for line in command.split("\n"):
        if ends:
            if line.strip() == ends[0]:
                ends.pop(0)
            continue
        out.append(line)
        ends = [m.group(2) for m in HEREDOC.finditer(line)]
    return "\n".join(out)


def simple_commands(command):
    """The words of each simple command in the line, without leading VAR=value and prefixes."""
    lexer = shlex.shlex(without_heredocs(command).replace("\n", " ; "), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = "#"
    out, words = [], []
    for token in list(lexer) + [";"]:
        if set(token) <= set("&|;()"):
            if words:
                out.append(words)
            words = []
        elif not words and (ASSIGNMENT.match(token) or token in PREFIXES):
            continue
        else:
            words.append(token)
    return out


def needs_wrap(command, wrap):
    """The item of the list that a simple command of the line starts with, or None. What
    ap-background runs is its arguments, not a simple command of its own."""
    items = [item.lower().split() for item in wrap if isinstance(item, str) and item.strip()]
    for words in simple_commands(command):
        if name(words[0]) == "ap-background":
            continue
        start = [name(words[0])] + [w.lower() for w in words[1:]]
        for item in items:
            if start[:len(item)] == item:
                return " ".join(item)
    return None


def main():
    data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace") or "{}")
    tool = data.get("tool_input") or {}
    if data.get("tool_name") != "Bash" or tool.get("run_in_background") is not True:
        sys.exit(10)
    config = project_config(data.get("cwd"))
    if config is None:
        sys.exit(10)
    wrap = config.get("background_wrap")
    if not isinstance(wrap, list):
        wrap = DEFAULT_WRAP
    command = tool.get("command") or ""
    found = needs_wrap(command, wrap)
    if found is None:
        sys.exit(10)
    sys.stdout.write(
        "This background command starts `%s` without ap-background. Start it as "
        "`%s`: then stopping the task also stops every program it started "
        "(on Windows they keep running otherwise). The list of commands that need it: "
        "`background_wrap` in .claude/ap.json." % (found, wrapped(command.strip())))
    sys.exit(12)


def wrapped(command):
    """The command with ap-background in front: a compound command (several commands, a
    heredoc) runs whole in `bash -c`, so ap-background watches all of it."""
    if len(simple_commands(command)) == 1 and without_heredocs(command) == command:
        return "ap-background " + command
    return "ap-background bash -c " + shlex.quote(command)


try:
    main()
except SystemExit:
    raise
except BaseException:
    sys.exit(10)  # a line or a file it cannot read: the command runs
