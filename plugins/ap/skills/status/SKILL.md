---
name: status
description: What goes on now - the run and its helpers, the open pull requests, and the open issues by what they wait for, in one short report; it only reads
allowed-tools: Bash(ap-status:*), Bash(ap-config:*), Read
---

# /ap:status

Arguments: `$ARGUMENTS`

The owner wants to see, in one place, what goes on: the run (if one goes on), what each helper
does now, and which open issues wait for whom. Print one short report. **This command only
reads: no comment, no label, no message, no file changes.** It does not stop or start anything,
and in a run's chat it does not change what the manager does next.

## 1. The facts

```bash
ap-status --json
```

It prints one JSON report (how it is built: the top of `ap-status`). Exit 2: it says why
(mostly: `/ap:setup` must run first); say that in one line and stop.

Arguments: a number (`/ap:status 10`) is `--max 10`, the lines each group shows (default 5).
`since <date>` is `--since <date>`.

**In the manager's chat of a run that goes on** (this session runs `/ap:run`, or one of the kind
skills, and has not reached its end), also pass the run's label limit when it has one
(the same `--label` and `--not` arguments you gave `ap-list`: `--label type:bug --not size:L`),
and add what only you know, from your own memory of the run (do not ask
the helpers, do not read their output):
- each helper that runs: its slot, its issue, what it does now (working, waiting for its review,
  in review, waiting for its merge turn, merging), and since when;
- for `STOP AFTER <N>`, how many of the N are left to start;
- the last lines you wrote on the run issue.

Your memory wins over the report where they differ (a helper that already reported); the report
wins for the files (a branch, work not committed). Outside a run's chat, the report is all.

## 2. The report

In the owner's `chat_language` (the report's `chat_language`; GitHub's titles stay as they are).
Short lines, no tables wider than a phone, nothing the owner does not need now. The parts, in
this order; skip an empty one:

1. **Needs you:** the group `owner` (waits for the owner: `status:waiting-for-owner`,
   `status:needs-decision`, `type:decision`; the ones marked `later` are the ones skipped before)
   and, when the report has it, `phone` (waits for a phone check). End with one line: "`/ap:waiting`
   goes through them".
2. **The run** (each run in `runs`): its run issue, when it started and how long ago, its
   arguments, its stop (the kind; `stop-in`: the minutes left; `STOP AFTER`: how many are left,
   from your memory), merged / failed / waiting so far, and the next deploy (`next_deploy_after`:
   after that many more merges; `null`: no deploys). Then one line per helper: the slot, the
   issue (number and title), what it does now, how many minutes, its pull request, and "work not
   committed" when `uncommitted` is more than 0. No run: one line, "No run goes on." A run in
   `stale_runs` (not seen for 12 hours: its session was closed): one line that names it.
3. **Open pull requests:** one line each: number, title, and its state (draft, the review,
   whether it can merge).
4. **The open issues**, in this order: `in_progress` (with its slot or branch and pull request),
   `blocked` (with `why`, when the report has it), `ready` (the order the next run takes them; the
`lookback` ones are approved look-back issues; the issues a stop left in the middle are under
`in_progress`, and the next run takes them before these, once no other run goes on),
   `inbox` (with "`/ap:inbox` sorts them" when there are any). `later` is one number.
5. **Since** `since.from` (the run's start, or the last 24 hours): the issues opened (count and
   numbers), the issues solved (count, and each number with its pull request), and the ones
   closed as duplicates in one line.
6. Anything in `errors`: one line, "Could not read: ...".

**Each issue line:** `#<number> <title> <priority>` (no priority: leave it out). A group that has
`more` above 0 ends with "and <more> more". Never list more than the report gives.

Keep the whole report on one screen where you can. End with nothing else: no advice, no
question, no "Recorded:" line (nothing was written).
