# The run's list of issues, for ap-list; lib/issues.py comes before this file. It reads the facts
# on stdin (parts "@@ issues", "@@ stopped", "@@ lookback", "@@ prs", "@@ branches", "@@ others",
# see bin/ap-list) and prints the list of run_list (lib/issues.py): one line per issue in the
# order the run takes them (a group of small issues says which issues go with it), then a "left
# out:" line for each issue it leaves out that the owner would miss, then the label limit. With --json, the plan of the run instead (for /ap:plan): the same
# issues with their helpers, which could run at the same time, what starts before a stop, and
# every issue left out with why. Exit codes as config.sh's reader: 10 a list, 12 an error (said
# on stdout).
#
#   python -I -c "<issues.py><this file>" [--label L]... [--not L]... [--leave-out L]... [--json]
#     [--parallel N] [--stop-after N] [--stop-in X] [N...]

VALUE_FLAGS = ("--label", "--not", "--leave-out", "--parallel", "--stop-after", "--stop-in")
GROUP_MAX = 3


def label_with(names, prefix):
    return next((x for x in names if x.startswith(prefix)), None)


def plan_item(issue, mark):
    names = labels(issue)
    item = {"number": issue["number"], "title": issue.get("title", ""), "priority": priority(issue),
            "size": label_with(names, "size:"), "area": label_with(names, "area:"),
            "parallel_safe": "parallel-safe" in names, "mark": mark}
    return {k: v for k, v in item.items() if v not in (None, "", False)}


def small_groups(items):
    """The helpers of the list, in its order: issues next to each other with the same area:*
    label and size:S go to one helper, at most GROUP_MAX of them."""
    helpers = []
    for item in items:
        last = helpers[-1] if helpers else None
        small = item.get("size") == "size:S" and item.get("area")
        if small and last and len(last) < GROUP_MAX and all(
                i.get("size") == "size:S" and i.get("area") == item["area"] for i in last):
            last.append(item)
        else:
            helpers.append([item])
    return helpers


def is_p0(helper):
    return any(i.get("priority") == "P0" for i in helper)


def may_run_beside(helper, running):
    """Section 4b of skills/run/SKILL.md: a helper with no area:* label, or with a P0, runs
    alone; two helpers of the same area run together only when all their issues are
    parallel-safe."""
    if not running:
        return True
    area = helper[0].get("area")
    if not area or is_p0(helper):
        return False
    for other in running:
        if not other[0].get("area") or is_p0(other):
            return False
        if other[0]["area"] == area and not all(i.get("parallel_safe") for i in helper + other):
            return False
    return True


def rounds_of(helpers, slots):
    """Which helpers could run at the same time with `slots` helpers, if they end in the order
    they start: each round fills the free slots with the first helpers in the list's order that
    may run beside the others."""
    left, rounds = list(helpers), []
    while left:
        running = []
        for helper in list(left):
            if len(running) < slots and may_run_beside(helper, running):
                running.append(helper)
                left.remove(helper)
        rounds.append(running)
    return rounds


def numbers_of(helpers):
    return [[i["number"] for i in h] for h in helpers]


def plan(taken, left, quiet, limit, opts):
    """The plan of the run: its list, its helpers, the rounds (with --parallel above 1), what
    starts before --stop-after, what may start in the second half of --stop-in, and every issue
    left out with why."""
    items = [plan_item(issue, mark) for issue, mark in taken]
    helpers = small_groups(items)
    slots = opts.get("--parallel") or 1
    rounds = rounds_of(helpers, slots) if slots > 1 else [[h] for h in helpers]
    out = {"order": items, "helpers": numbers_of(helpers), "parallel": slots,
           "rounds": [numbers_of(r) for r in rounds] if slots > 1 else None,
           "stop_after": None, "stop_in": None, "label_limit": limit_text(limit) or None,
           "left_out": [{"number": n, "title": i.get("title") if i else None,
                         "priority": priority(i) if i else None, "why": why}
                        for n, i, why in left + sorted(quiet, key=lambda q: order(q[1]))]}
    if opts.get("--stop-after") is not None:
        # An issue of a group counts one, and a group never gets more issues than are left.
        n_left, start = opts["--stop-after"], []
        for helper in (h for r in rounds for h in r):
            if n_left <= 0:
                break
            start.append([i["number"] for i in helper[:n_left]])
            n_left -= len(start[-1])
        started = {n for h in start for n in h}
        out["stop_after"] = {"n": opts["--stop-after"], "start": start,
                             "not_started": [i["number"] for i in items if i["number"] not in started]}
    if opts.get("--stop-in") is not None:
        # In the second half of the time, only size:S issues start.
        out["stop_in"] = {"minutes": opts["--stop-in"],
                          "after_half": [i["number"] for i in items if i.get("size") == "size:S"]}
    return out


def line(issue, mark=""):
    names = labels(issue)
    words = ["#%d" % issue["number"]]
    if priority(issue):
        words.append(priority(issue))
    words.append(issue.get("title", ""))
    words += [x for x in names if x.startswith("area:") or x.startswith("size:")]
    if mark:
        words.append("(%s)" % mark)
    return " ".join(words)


def text(taken, left, limit):
    """The list as the run reads it: a group of small issues says which issues go with it."""
    helpers = numbers_of(small_groups([plan_item(issue, mark) for issue, mark in taken]))
    helper_of = {n: h for h in helpers for n in h}
    out = []
    for issue, mark in taken:
        others = [n for n in helper_of[issue["number"]] if n != issue["number"]]
        group = "one helper with " + " ".join("#%d" % n for n in others) if others else ""
        out.append(line(issue, ", ".join(x for x in (mark, group) if x)))
    out = (out or ["no issue to take"]) + ["left out: #%d (%s)" % (n, why) for n, _, why in left]
    if limit_text(limit):
        out.append("label limit: " + limit_text(limit))
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    limit = label_limit(args)
    leave_out = tuple(v for f, v in zip(args, args[1:]) if f == "--leave-out")
    opts = {f: int(v) for f, v in zip(args, args[1:]) if f in ("--parallel", "--stop-after", "--stop-in")}
    numbers, skip = [], False
    for a in args:
        if skip:
            skip = False
        elif a in VALUE_FLAGS:
            skip = True
        elif a != "--json":
            numbers.append(int(a))
    taken, left, quiet = run_list(read_facts(), limit, leave_out, numbers)
    if "--json" in args:
        result = json.dumps(plan(taken, left, quiet, limit, opts), ensure_ascii=False, indent=1)
    else:
        result = text(taken, left, limit)
    sys.stdout.buffer.write((result + "\n").encode("utf-8"))
    sys.exit(10)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    sys.stdout.write("ap-list: could not build the list: %r" % e)
    sys.exit(12)
