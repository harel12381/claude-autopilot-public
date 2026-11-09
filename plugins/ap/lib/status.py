# The report of ap-status, built from the facts the script gathered; lib/issues.py comes before
# this file. It reads them on stdin, in parts that each start with a line "@@ <name>" (see
# bin/ap-status), and writes the report as JSON (--json) or as plain text. Its exit code is 10 (a
# report), 12 (an error, said on stdout), as config.sh's reader: ap_python tells them from a
# Python that does not run.
#
#   python -I -c "<issues.py><this file>" [--json] [--max N] [--label L]... [--not L]... < facts
import time

# The labels of the issues that wait for the owner, and for the owner's phone. These, and the
# other labels a run leaves out (step 2 of skills/run/SKILL.md), keep an issue out of "ready".
OWNER = ("status:waiting-for-owner", "status:needs-decision", "type:decision")
PHONE = "status:phone-check"
DEPLOY_EVERY = 5


def rows(facts, name):
    """A part of tab-separated lines, as lists of fields."""
    return [line.split("\t") for line in one(facts, name).splitlines() if line.strip()]


def line_of(issue, **more):
    item = {"number": issue["number"], "title": issue["title"], "priority": priority(issue)}
    item.update({k: v for k, v in more.items() if v not in (None, "", False)})
    return item


def count(text):
    """A count the script gathered; None when it could not be read (`?`)."""
    return int(text) if (text or "0").isdigit() else None


def local_epoch(text):
    """A local time as `date '+%F %T'` writes it, in seconds since 1970; None when it is not one."""
    try:
        return int(time.mktime(time.strptime(text.strip(), "%Y-%m-%d %H:%M:%S")))
    except ValueError:
        return None


def why_blocked(issue):
    """A few words on what a blocked issue waits for: the last line of its comments (or else its
    body) that says so."""
    texts = [c.get("body") or "" for c in issue.get("comments") or []][::-1]
    texts.append(issue.get("body") or "")
    for text in texts:
        for line in text.splitlines()[::-1]:
            if re.search(r"block|waits? for|needs #\d+", line, re.I):
                words = re.sub(r"[*_`>#]+(?!\d)", "", line).strip(" -:.")
                return words[:80] + ("..." if len(words) > 80 else "")
    return None


def run_issue_facts(issue, deploys):
    """What the comments of a run issue say: the counts, the stop, the next deploy."""
    comments = [c.get("body") or "" for c in issue.get("comments") or []]
    found = {"merged": set(), "failed": set(), "waiting": set()}
    merged_since_deploy, stop, args = set(), None, None
    for body in comments:
        if re.match(r"\s*Deployed\b", body):
            merged_since_deploy = set()
        for kind, pattern in (("merged", r"#(\d+) merged\b"), ("failed", r"#(\d+) failed\b"),
                              ("waiting", r"#(\d+) waiting for\b")):
            for n in re.findall(pattern, body):
                found[kind].add(int(n))
                if kind == "merged":
                    merged_since_deploy.add(int(n))
        m = re.search(r"\*\*Stop:\*\*\s*([^\n]+)", body)
        if m:
            stop = m.group(1).strip()
    for line in (issue.get("body") or "").splitlines():
        if re.search(r"argument", line, re.I):
            args = re.sub(r"[*_]+", "", line).strip(" -")[:120]
            break
    last = comments[-1].strip().splitlines()[0][:200] if comments and comments[-1].strip() else None
    counts = {k: sorted(v) for k, v in found.items()}
    next_deploy = None
    if deploys:
        next_deploy = DEPLOY_EVERY - len(merged_since_deploy) % DEPLOY_EVERY
    return counts, stop, args, last, next_deploy


def build(facts, max_items, limit):
    config = json_part(facts, "config", {})
    now = int(one(facts, "now", "0").strip() or 0)
    issues = json_part(facts, "issues", [])
    prs = json_part(facts, "prs", [])
    blocked_why = {i["number"]: why_blocked(i) for i in json_part(facts, "blocked", [])}
    titles = {i["number"]: i["title"] for i in issues}
    pr_of_branch = {p["headRefName"]: p for p in prs}
    pr_of_issue = {}
    for p in prs:
        n = branch_issue(p["headRefName"])
        if n is not None:
            pr_of_issue.setdefault(n, p)

    parts_cfg = config.get("parts") or {}
    deploys = bool(config.get("deploy")) and parts_cfg.get("deploy", True) is not False

    # Where each issue is worked on now: a slot worktree, or the main checkout's branch.
    places = {}
    slots = []
    for s, holder, mtime, there, branch, dirty in rows(facts, "slot"):
        n = branch_issue(branch)
        pr = pr_of_branch.get(branch)
        slot = {"slot": s, "run": holder, "worktree": there == "1", "branch": branch or None,
                "uncommitted": count(dirty), "minutes": max(0, (now - int(mtime)) // 60),
                "issue": n, "title": titles.get(n), "pr": pr["number"] if pr else None}
        slots.append(slot)
        if n is not None:
            places[n] = "slot %s" % s
    main = rows(facts, "main")
    main_branch, main_dirty = (main[0] + ["", "0"])[:2] if main else ("", "0")
    main_place = None
    if main_branch and main_branch != config.get("main_branch"):
        n = branch_issue(main_branch)
        pr = pr_of_branch.get(main_branch)
        main_place = {"branch": main_branch, "uncommitted": count(main_dirty), "issue": n,
                      "title": titles.get(n), "pr": pr["number"] if pr else None}
        if n is not None:
            places.setdefault(n, "main checkout")

    # The runs, each with its run issue (the open "[autopilot]" issue whose body names its id).
    run_issues = json_part(facts, "run_issues", [])
    runs, stale = [], []
    for rid, started, mtime, going, left in rows(facts, "run"):
        if going != "1":
            stale.append(rid)
            continue
        start = local_epoch(started)
        run = {"id": rid, "started": started, "minutes": (now - start) // 60 if start else None,
               "last_seen_minutes": max(0, (now - int(mtime)) // 60),
               "slots": [s for s in slots if s["run"] == rid], "stop": None}
        if left != "none":
            run["stop"] = {"kind": "stop-in"}
            if left == "up":
                run["stop"]["up"] = True
            else:
                m = re.match(r"(\d+) of (\d+)", left)
                if m:
                    run["stop"].update(minutes_left=int(m.group(1)), of=int(m.group(2)))
        runs.append(run)
    for run in runs:
        issue = next((i for i in run_issues if run["id"] in (i.get("body") or "")), None)
        if issue is None and len(runs) == 1 and len(run_issues) == 1:
            issue = run_issues[0]  # one run and one run issue that does not name it: its own
        if issue is None:
            run["issue"] = None
            continue
        counts, stop, args, last, next_deploy = run_issue_facts(issue, deploys)
        run.update(issue={"number": issue["number"], "title": issue["title"], "url": issue.get("url")},
                   arguments=args, counts=counts, next_deploy_after=next_deploy, last_comment=last)
        if stop:
            run["stop"] = dict(run["stop"] or {}, written=stop)
            if "kind" not in run["stop"]:
                run["stop"]["kind"] = re.split(r",| from ", stop)[0].strip()
    if len(runs) == 1 and main_place and not runs[0]["slots"]:
        runs[0]["main_checkout"] = main_place

    # The open issues, in groups: each issue in the first group it fits. "ready" is the run's own
    # list (run_list), without the stopped issues (they are in progress).
    taken, _, _ = run_list(facts, limit, (), [])
    ready = {issue["number"]: mark for issue, mark in taken}
    branch_of = {}
    for line in one(facts, "branches").splitlines():
        branch_of.setdefault(branch_issue(line.strip()), line.strip())
    groups = {k: [] for k in ("owner", "phone", "in_progress", "blocked", "ready", "inbox")}
    later = 0
    for issue in sorted(issues, key=order):
        names = labels(issue)
        n = issue["number"]
        pr = pr_of_issue.get(n)
        if n in ready:
            continue
        if "tracking" in names:
            continue
        if any(x in names for x in OWNER):
            groups["owner"].append(line_of(issue, later="status:later" in names))
        elif PHONE in names:
            groups["phone"].append(line_of(issue))
        elif "status:in-progress" in names or pr or n in branch_of:
            groups["in_progress"].append(line_of(
                issue, place=places.get(n), branch=pr["headRefName"] if pr else branch_of.get(n),
                pr=pr["number"] if pr else None))
        elif "status:blocked" in names:
            groups["blocked"].append(line_of(issue, why=blocked_why.get(n)))
        elif "inbox" in names:
            groups["inbox"].append(line_of(issue))
        elif "status:later" in names:
            later += 1
    groups["ready"] = [line_of(issue, lookback=mark == "approved look back") for issue, mark in taken]
    groups["owner"].sort(key=lambda i: bool(i.get("later")))
    if not groups["phone"] and not parts_cfg.get("phone_check"):
        del groups["phone"]
    cut = {k: {"total": len(v), "items": v[:max_items], "more": max(0, len(v) - max_items)}
           for k, v in groups.items()}
    if "issues" not in facts:  # the list of open issues could not be read: no group is known
        cut, later = None, None

    # Since the run started (or the time asked for): issues opened, solved, closed as duplicates.
    merged = json_part(facts, "merged", [])
    def solved_pr(issue):
        refs = issue.get("closedByPullRequestsReferences") or []
        if refs:
            return refs[0].get("number")
        n = issue["number"]
        for p in merged:
            if branch_issue(p.get("headRefName")) == n or re.search(
                    r"(close[sd]?|fix(e[sd])?|resolve[sd]?|refs)\s+#%d\b" % n, p.get("body") or "", re.I):
                return p["number"]
        return None
    solved, duplicates, not_planned = [], [], []
    for issue in sorted(json_part(facts, "closed", []), key=lambda i: i["number"]):
        reason = (issue.get("stateReason") or "").upper()
        if "tracking" in labels(issue):
            continue  # a run's own issue is no work solved
        if reason == "DUPLICATE" or "duplicate" in labels(issue):
            duplicates.append(issue["number"])
        elif reason == "NOT_PLANNED":
            not_planned.append(issue["number"])
        else:
            solved.append({"number": issue["number"], "title": issue["title"], "pr": solved_pr(issue)})
    opened = sorted(i["number"] for i in json_part(facts, "opened", []))

    return {
        "repo": config.get("repo"), "owner": config.get("owner"),
        "chat_language": config.get("chat_language") or "en",
        "main_branch": config.get("main_branch"),
        "runs": runs, "stale_runs": stale, "label_limit": limit_text(limit) or None,
        "pull_requests": [{"number": p["number"], "title": p["title"], "branch": p["headRefName"],
                           "draft": bool(p.get("isDraft")), "review": p.get("reviewDecision") or None,
                           "mergeable": p.get("mergeable") or None, "issue": branch_issue(p["headRefName"])}
                          for p in sorted(prs, key=lambda p: p["number"])],
        "groups": cut, "later": later,
        "since": {"from": one(facts, "since").strip(), "opened": opened, "solved": solved,
                  "duplicates": duplicates, "not_planned": not_planned},
        "errors": [e.strip() for e in facts.get("error", []) if e.strip()],
    }


GROUP_NAMES = {"owner": "Waiting for {owner}", "phone": "Waiting for a phone check",
               "in_progress": "In progress", "blocked": "Blocked",
               "ready": "Ready for the next run", "inbox": "Inbox"}


def issue_text(i):
    extra = [i[k] if k != "pr" else "PR #%s" % i[k] for k in ("place", "branch", "pr", "why") if i.get(k)]
    if i.get("later"):
        extra.append("later")
    if i.get("lookback"):
        extra.append("approved look back")
    return "  #%d %s%s%s" % (i["number"], i["title"], " " + i["priority"] if i["priority"] else "",
                            " (%s)" % ", ".join(str(e) for e in extra) if extra else "")


def uncommitted(n):
    """The words for the work not committed in a worktree."""
    if n is None:
        return ", work not committed: unknown"
    return ", %d uncommitted" % n if n else ", all committed"


def text(report):
    out = []
    for run in report["runs"]:
        head = "Run %s, started %s" % (run["id"], run["started"])
        if run["minutes"] is not None:
            head += " (%d min ago)" % run["minutes"]
        if run.get("issue"):
            head += ", run issue #%d" % run["issue"]["number"]
        out.append(head)
        if run.get("arguments"):
            out.append("  " + run["arguments"])
        stop = run.get("stop")
        if stop:
            words = "  Stop: " + (stop.get("written") or stop["kind"])
            if stop.get("up"):
                words += ", time is up"
            elif "minutes_left" in stop:
                words += ", %d of %d min left" % (stop["minutes_left"], stop["of"])
            out.append(words)
        if run.get("counts"):
            c = run["counts"]
            words = "  Merged %d, failed %d, waiting %d" % (len(c["merged"]), len(c["failed"]), len(c["waiting"]))
            if run.get("next_deploy_after"):
                words += "; next deploy after %d more merges" % run["next_deploy_after"]
            out.append(words)
        for s in run["slots"]:
            if not s["worktree"]:
                out.append("  Slot %s: no worktree" % s["slot"])
                continue
            words = "  Slot %s: %s" % (s["slot"], s["branch"] or "no branch")
            if s["issue"]:
                words += ", #%d %s" % (s["issue"], s["title"] or "")
            if s["pr"]:
                words += ", PR #%d" % s["pr"]
            words += ", %d min" % s["minutes"]
            words += uncommitted(s["uncommitted"])
            out.append(words)
        m = run.get("main_checkout")
        if m:
            out.append("  Main checkout: %s%s%s" % (m["branch"], ", PR #%d" % m["pr"] if m["pr"] else "",
                                                    uncommitted(m["uncommitted"])))
        if run.get("last_comment"):
            out.append("  Last: " + run["last_comment"])
    if not report["runs"]:
        out.append("No run goes on.")
    if report["stale_runs"]:
        out.append("Not seen for 12 hours: " + ", ".join(report["stale_runs"]))
    if report["pull_requests"]:
        out.append("Open pull requests:")
        for p in report["pull_requests"]:
            state = ["draft"] if p["draft"] else []
            state += [x.lower().replace("_", " ") for x in (p["review"], p["mergeable"]) if x]
            out.append("  #%d %s (%s%s)" % (p["number"], p["title"], p["branch"],
                                           ", " + ", ".join(state) if state else ""))
    if report["groups"] is None:
        out.append("Open issues: unknown (their list could not be read)")
    for key, group in (report["groups"] or {}).items():
        name = GROUP_NAMES[key].format(owner=report["owner"] or "the owner")
        out.append("%s (%d)%s" % (name, group["total"], ":" if group["total"] else ""))
        out.extend(issue_text(i) for i in group["items"])
        if group["more"]:
            out.append("  and %d more" % group["more"])
    if report["later"]:
        out.append("Later: %d" % report["later"])
    s = report["since"]
    out.append("Since %s: opened %d%s, solved %d%s" % (
        s["from"], len(s["opened"]), " (%s)" % " ".join("#%d" % n for n in s["opened"]) if s["opened"] else "",
        len(s["solved"]), " (%s)" % ", ".join("#%d%s" % (i["number"], " in PR #%d" % i["pr"] if i["pr"] else "")
                                             for i in s["solved"]) if s["solved"] else ""))
    if s["duplicates"]:
        out.append("Closed as duplicates: " + " ".join("#%d" % n for n in s["duplicates"]))
    for e in report["errors"]:
        out.append("Could not read: " + e)
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    as_json = "--json" in args
    max_items = int(args[args.index("--max") + 1]) if "--max" in args else 5
    report = build(read_facts(), max_items, label_limit(args))
    result = json.dumps(report, ensure_ascii=False, indent=1) if as_json else text(report)
    sys.stdout.buffer.write((result + "\n").encode("utf-8"))
    sys.exit(10)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    sys.stdout.write("ap-status: could not build the report: %r" % e)
    sys.exit(12)
