# What ap-list and ap-status share about the open issues: how the facts are read, the labels a
# run leaves out, the label limit, which issues a stop left in the middle and which look-back
# issues the owner approved, and the run's list itself (run_list). Only functions and names: the
# script's own file is added after this one (`python -I -c "<this file><its file>"`).
import json
import re
import sys

# The labels that keep an issue out of the run's list (step 2 of skills/run/SKILL.md).
LEAVE_OUT = ("status:waiting-for-owner", "status:needs-decision", "status:blocked", "status:later",
             "status:in-progress", "status:phone-check", "type:decision", "tracking", "inbox")
STOPPED = "**Stopped in the middle.**"
DECIDED = "**Decided**"


def parts(text):
    """The facts: {name: [the text of each part with that name]}. A part starts with "@@ <name>"."""
    out, name, lines = {}, None, []
    for line in text.splitlines():
        if line.startswith("@@ "):
            if name is not None:
                out.setdefault(name, []).append("\n".join(lines))
            name, lines = line[3:].strip(), []
        else:
            lines.append(line)
    if name is not None:
        out.setdefault(name, []).append("\n".join(lines))
    return out


def read_facts():
    return parts(sys.stdin.buffer.read().decode("utf-8", "replace"))


def one(facts, name, default=""):
    return facts.get(name, [default])[0]


def json_part(facts, name, default):
    text = one(facts, name).strip()
    return json.loads(text) if text else default


def labels(issue):
    return [lab["name"] for lab in issue.get("labels") or []]


def priority(issue):
    for name in labels(issue):
        if re.fullmatch(r"P[0-3]", name):
            return name
    return None


def order(issue):
    return (priority(issue) or "P9", issue["number"])


def label_limit(args):
    """The label limit from the arguments: every `--label a,b` is needed (either of its labels),
    and no `--not c` may be there. {"all": [["a", "b"]], "not": ["c"]}."""
    limit = {"all": [], "not": []}
    for flag, value in zip(args, args[1:]):
        if flag == "--label":
            limit["all"].append([x.strip() for x in value.split(",") if x.strip()])
        elif flag == "--not":
            limit["not"].append(value.strip())
    return limit


def limit_text(limit):
    """The limit in a few words ("type:bug, area:app or area:map, not size:L"), or "" for none."""
    words = [" or ".join(group) for group in limit["all"]]
    words += ["not " + name for name in limit["not"]]
    return ", ".join(words)


def keeps(issue, limit):
    """The label limit keeps the issue: every P0 is kept, whatever its labels."""
    names = labels(issue)
    if priority(issue) == "P0":
        return True
    if any(not any(x in names for x in group) for group in limit["all"]):
        return False
    return not any(x in names for x in limit["not"])


def bodies(issue):
    return [(c.get("body") or "").strip() for c in issue.get("comments") or []]


def stopped_numbers(in_progress):
    """The issues a stop left in the middle: their last comment starts with **Stopped in the middle.**"""
    return {i["number"] for i in in_progress if (bodies(i) or [""])[-1].startswith(STOPPED)}


def approved_lookbacks(lookbacks):
    """The look-back issues the owner said yes or no to: a comment starts with **Decided**."""
    return {i["number"] for i in lookbacks if any(b.startswith(DECIDED) for b in bodies(i))}


def is_lookback(issue, approved):
    return issue["number"] in approved and issue.get("title", "").startswith("[retro]")


def lookback_keeps(issue, limit):
    """An approved look-back issue changes the run itself: a kind or --label limit never leaves it
    out, only a --not that names one of its labels."""
    return not any(x in labels(issue) for x in limit["not"])


BRANCH_ISSUE = re.compile(r"^[^/]+/(\d+)-")
# Why a label of LEAVE_OUT keeps an issue out, in the plan's words; a tracking issue is not named.
HOLD_WHY = {"status:waiting-for-owner": "waits for the owner", "status:needs-decision": "waits for the owner",
            "type:decision": "waits for the owner", "status:phone-check": "waits for a phone check",
            "status:blocked": "blocked", "status:in-progress": "in progress", "status:later": "later",
            "inbox": "an inbox note", "tracking": None}


def branch_issue(branch):
    """The issue a branch is named for (`fix/47-slug`: 47), or None."""
    m = BRANCH_ISSUE.match(branch or "")
    return int(m.group(1)) if m else None


def hold_why(names, leave_out):
    """Why a label keeps the issue out ("" for a tracking issue), or None when none does."""
    for x in names:
        if x in LEAVE_OUT + leave_out:
            return HOLD_WHY.get(x, "has " + x) or ""
    return None


def taken_elsewhere(facts):
    """{issue: why}: the issues another session may be on, an open pull request ("open PR #M") or
    a branch on origin ("branch <name>") named for them."""
    out = {}
    for line in one(facts, "branches").splitlines():
        n = branch_issue(line.strip())
        if n is not None:
            out.setdefault(n, "branch " + line.strip())
    for p in json_part(facts, "prs", []):
        n = branch_issue(p.get("headRefName"))
        if n is not None:
            out[n] = "open PR #%d" % p["number"]
    return out


def run_list(facts, limit, leave_out, numbers):
    """The run's list, in the one place it is built (ap-list prints it, /ap:plan and /ap:status
    show it). (taken, left, quiet): the issues the run takes in order, each with its mark; the
    ones left out that the list says, as (number, issue or None, why); and the ones a label or the
    label limit leaves out, which only the plan names, as (number, issue, why)."""
    issues = {i["number"]: i for i in json_part(facts, "issues", [])}
    stopped = stopped_numbers(json_part(facts, "stopped", []))
    approved = approved_lookbacks(json_part(facts, "lookback", []))
    elsewhere = taken_elsewhere(facts)
    others = " ".join(one(facts, "others").split())
    taken, left, quiet = [], [], []

    if numbers:  # only those, in that order: a named issue is taken even when it is in progress
        for n in numbers:
            issue = issues.get(n)
            if issue is None:
                left.append((n, None, "not open"))
            elif not keeps(issue, limit):
                left.append((n, issue, "not in the label limit"))
            else:
                taken.append((issue, hold_why(labels(issue), leave_out) or ""))
        return taken, left, quiet

    first, lookback, rest = [], [], []
    for issue in sorted(issues.values(), key=order):
        n, names = issue["number"], labels(issue)
        why = hold_why(names, leave_out)
        if n in stopped:
            holds = [x for x in names if x in LEAVE_OUT + leave_out and x != "status:in-progress"]
            if holds:
                if hold_why(holds, leave_out):
                    quiet.append((n, issue, hold_why(holds, leave_out)))
            elif others:
                left.append((n, issue, "stopped in the middle, but another run goes on: %s" % others))
            elif not keeps(issue, limit):
                left.append((n, issue, "stopped in the middle, not in the label limit"))
            else:
                first.append((issue, "stopped in the middle"))
        elif why is not None:
            if why:
                quiet.append((n, issue, why))
        elif is_lookback(issue, approved) and not lookback_keeps(issue, limit):
            quiet.append((n, issue, "not in the label limit"))
        elif not is_lookback(issue, approved) and not keeps(issue, limit):
            quiet.append((n, issue, "not in the label limit"))
        elif n in elsewhere:
            left.append((n, issue, elsewhere[n]))
        elif is_lookback(issue, approved):
            lookback.append((issue, "approved look back"))
        else:
            rest.append((issue, ""))
    return first + lookback + rest, left, quiet
