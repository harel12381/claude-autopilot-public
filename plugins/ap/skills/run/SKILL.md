---
name: run
description: Away mode - the owner is away or busy; work through the issues that do not need them, one fresh helper agent per issue, from the branch to the merged pull request
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-git-sync:*), Bash(ap-run:*), Bash(ap-list:*), Bash(ap-brief:*), Bash(ap-notify:*), Bash(ap-config:*), Bash(ap-check-branch:*), Bash(ap-check:*), Bash(ap-batch:*), Bash(ap-deploy:*), Bash(ap-background:*), Bash(ap-qa:*), Bash(ap-bug-reports:*), Read, Write, Agent, SendMessage, TaskStop
---

# /ap:run

Arguments: `$ARGUMENTS`

(The kind skills (`bugs`, `features`, `tests`, `chores`) and the stop skills (`stop`, `stopnow`,
`stop-in`, `stop-after`) copy the `allowed-tools` line above: a change to it goes in all nine.
`tests/skills-test.sh` checks that they agree.)

The owner is away, or busy. You are the **manager** of this run. You pick the next issue, start
one fresh helper agent for it, keep its short report, and start the next. You do not write code,
you do not read code, and you do not do an issue yourself: your context has to last the whole
run. Background and the reasons: `${CLAUDE_PLUGIN_ROOT}/docs/autopilot.md`.

Running this command is the owner's approval to start helper agents, for this run only.

## 0. The project's settings

Read `.claude/ap.json` (the Read tool; `ap-config <key>` prints one value). Keep these for the
whole run:

| Key | Used for |
|---|---|
| `repo`, `owner`, `main_branch` | Must be there. Missing: say in one line that `/ap:setup` must run first, and stop. |
| `chat_language` | A language code (`en`, `he`): the language you talk to the owner in, in this chat (missing: `en`). Everything on GitHub stays simple English. |
| `check` | The project's check, the only gate before a merge: `ap-check` (the parts in `check_parts`) or the project's own command. Missing: say in one line that a run cannot merge without a check, that `/ap:setup` sets it, and stop. |
| `merge_batch` | A parallel run (`X2` and up): how many approved pull requests are merged together and checked once, by `ap-batch` (section 4d). Missing or `1`: one at a time, each in its helper's merge turn. |
| `queue_per_slot` | A parallel run: how many issues one slot may have open at a time, each with its own helper in its own worktree of the slot ("A queue per slot", section 4b). Missing or `1`: no queue. |
| `board` | Every new issue goes on it: `gh project item-add <board.number> --owner <board.owner> --url <url>`. Missing: no board step. A board command that fails (the token lacks the `project` scope, `gh auth refresh -s project`; the board is gone) is one line on the run issue, never a stop. |
| `deploy`, `site`, `parts.deploy` | The deploys (section 4), always through `ap-deploy`, which runs the check first. No `deploy`, or `parts.deploy` is `false`: no deploys. |
| `hooks.cleanup` | Used through `ap-run cleanup` and by the helpers. Missing: no cleanup and no disk check. |
| `hooks.notify` | Used through `ap-notify`. Missing: `ap-notify` only prints the message. |
| `hooks.check_setup` | Used through `ap-check-branch` (section 4c): what a fresh checkout needs before the check. Missing: the check runs alone. |
| `briefs.helper`, `briefs.reviewer`, `briefs.manager` | The project's own part of each brief. |
| `parts.bug_reports`, `parts.qa` | `true`: the users' reports before the planner (section 3a), a QA sweep after a deploy (section 4). |

**The project's part of this command:** when `briefs.manager` names a file that is there, read
it now. It adds this project's steps and rules to the ones below (where it adds a step, it says
after which step). It never makes a check weaker or a rule below looser.

**A command the permission check refuses** (not a failure of the code: "permission denied",
"not allowed"): never try another way around it. Write on the run issue the exact command and the
permission rule that would allow it (`Bash(<command>:*)`), and tell the owner (`ap-notify --hold
30`). A helper reports it as `needs-owner`.

**Writes and waits.** Every command of yours that writes to GitHub, git or a server (a comment,
an issue, a label, the board, a push, a merge) is joined to the next step with `&&`, never `;`,
and its output is kept: never `>/dev/null`, never `| tail` without `set -o pipefail`. A comment
that failed (GitHub can answer HTTP 499 or 502 once) is written again. Every wait loop has a limit
(`timeout <seconds> bash -c 'until ...; do sleep 20; done'`), and a loop that looks for a process
by its command line must not match its own.

In the texts below, "the owner" is the `owner` name, and "main" is the `main_branch`. A part that
is off (no `deploy`, no `board`, no `hooks.notify`, no `hooks.cleanup`) is skipped: write one
line on the run issue the first time (`No deploy set in .claude/ap.json: no deploys this run.`),
never a failure.

## The briefs

Each agent of the run gets one brief and nothing else. Make it with `ap-brief`, never by hand:

```bash
ap-brief helper   --run <RUN> --n "<N>" [--slot <s>] [--worktree ap-<s>b] [--note "<a limit>"]
ap-brief reviewer --run <RUN> --n "<N>" --pr <PR>
ap-brief planner  --run <RUN> --n "<the run's whole list, in its order>"
ap-brief retro    --run <RUN>
```

Add `--date <the day the run started>` after a run that went past midnight, and
`--scratchpad <your scratchpad folder>` when your system prompt names one. It adds the project's
own part (`briefs.<name>` of `.claude/ap.json`) after the plugin's brief, fills in every `<WORD>`
from the settings and these values, and prints the path of the file it wrote. It fails, and
writes nothing, when a word is left that it cannot fill: give the value, or fix the setting. The
words an agent fills in itself (`<PR>` in the helper's brief, `<M>` in the retro's) stay.

Then start the agent with the Agent tool, `subagent_type: general-purpose`, in the background
(`run_in_background: true` where the Agent tool has that field; where it has none, agents always
run in the background), and only this prompt: `Your brief is the file <path>. Read all of it
first, then do what it says.` Never paste the brief itself into the prompt: a helper's brief is
about 20 KB, and your context has to last the whole run.

`--slot` (a helper of a parallel run) adds `Your slot is <s>.`, and `--worktree` (a helper in
another worktree of its slot, "A queue per slot", section 4b) adds `Your worktree is ap-<s>b.`.
Give `--note` only when the owner gave a limit that changes how the issue is done.

## Which mode am I in?

- **Empty** -> every open issue an agent can do alone, until none is left. The issues a stop
  left in the middle come first, by themselves (step 2).
- **Issue numbers** (`/ap:run 47 58`) -> only those, in that order. A named issue is taken even
  when it has `status:in-progress` (this is how a run that was cut off is picked up).
- **A label limit** (step 2): the run takes only some labels. Each of these is one part of it,
  and they go together (every part must hold):
  - **One kind of issue** (`bugs`, `features`, `tests`, `chores`: `/ap:run bugs`, or `/ap:bugs`,
    `/ap:features`, `/ap:tests`, `/ap:chores`) -> `--label type:bug` (`type:feature`,
    `type:test`, `type:chore`).
  - **`only <label>`** (`/ap:run only area:api`) -> `--label area:api`. Two or more labels with
    a comma (`only area:app,area:map`) -> `--label area:app,area:map`: either of them.
  - **`not <label>`** (`/ap:run not area:engine`) -> `--not area:engine`.

  So `/ap:bugs only area:app not size:L` takes the bugs of `area:app` that are not `size:L`:
  `--label type:bug --label area:app --not size:L`.
- **A stop** (`stop-in <X>`, `stop-after <N>`) -> as "Stopping a run" below, from the start.
- **Other words** (`/ap:run only small ones`) -> a limit from the owner on the empty mode. Follow
  it and write it in the run issue. A limit that names labels is a label limit (above).
- Every mode goes with the others: `/ap:bugs X3` (or `x3`) is up to 3 bug helpers at the same
  time, `/ap:features X2 stop-after 4` too, `/ap:run X2 only area:api 47 58` as well.
- **`X<N>`** (`/ap:run X3`, `/ap:run X2 47 58`, any N, `x3` too) -> up to N helpers at the same
  time, each on its own issue, in its own worktree: section 4b. It goes with any of the modes
  above. No `X<N>`, or `X1`: one helper at a time, as below.

## Stopping a run (the owner can send any of these at any time)

Four kinds. The owner sends them as commands, or as the plain words in capitals. Each one ends in
one of two ways:

- **Stop at once:** send every helper that runs `STOPNOW from the owner. Do the STOPNOW steps of
  your brief now.` Start no new helper; stop a reviewer that runs (`TaskStop`), its pull request
  stays open. When a helper reports, write its line on the run issue. When none runs any more:
  step 6.
- **Finish, then stop:** send every helper that runs `STOP from the owner. Finish your issue as
  usual, then report. You get no new issue.` Start no new helper. Reviews, merge turns and step 4
  go on as usual. When the last helper has reported: step 6.

| Command | Plain words | How it ends |
|---|---|---|
| `/ap:stopnow` | `STOPNOW` | At once. |
| `/ap:stop` | `STOP` | Finish, then stop: now. |
| `/ap:stop-in <X>` | `STOP IN <X>` | At once, when X minutes have passed. |
| `/ap:stop-after <N>` | `STOP AFTER <N>` | Finish, then stop: the running issues and N more (the rule below). |

The same words in the arguments of `/ap:run` (`/ap:run stop-in 90`, `/ap:run X2 stop-after 3`)
set the stop from the start. `/ap:run stop after 3` and other words with the same meaning do too.

Start every helper **in the background** (as "The briefs" says), so that you are free and get
the owner's message at once, even while a helper works.

- **Write the stop on the run issue at once**, in one comment: `**Stop:** <the kind>, from <the
  time>`. A session that goes on later reads it there. A newer stop replaces the older one;
  `STOPNOW` always wins. When a stop replaces `STOP IN`: stop its `stop-wait` (`TaskStop`), and
  `ap-run stop-clear <run id>`.
- **`STOP IN <X>`:** `ap-run stop-in <run id> <X>`, then `ap-run stop-wait <run id>` in the
  background (`run_in_background: true`, `timeout: 7200000`). You are told when it ends. It prints
  `up` (stop at once), `again` (it waited its longest, 100 minutes: run it again, the same way) or
  `cancelled` (nothing to do). Before you start each helper, and whenever you are woken:
  `ap-run stop-left <run id>`. It prints `up` (stop at once: the wait may have been lost with a
  session) or `<L> of <X>` minutes left. When L is X/2 or less, start no helper on an issue that
  is `size:M` or `size:L`, or has no `size:*` label: take the next `size:S` issue in the list, or
  none.
- **`STOP AFTER <N>`** (the one rule for it; the other texts point here): the issues that run at
  the time of the stop finish, and N more issues start after the stop (an issue of a group counts
  one, so a group of 3 counts 3). The running ones are not part of the N. Each of the N counts
  once it starts, whatever its end (merged, waiting for the owner, failed); a queued issue starts
  when its helper starts. Once N have started, start no new helper: finish, then stop. Never give a group more issues than are left.
  `STOP AFTER 0` is the same as `STOP`.
- **The helper does not answer** `STOPNOW` within 10 minutes: stop it (`TaskStop`), and do its
  STOPNOW steps yourself, only with `git` and `gh` (you still do not write code): on its branch,
  `git add -A -- . ':!.claude' && git add -u && git commit -m "WIP: stopped by STOPNOW"`, then
  `ap-git-sync push`, a comment on its issue that starts with **Stopped in the middle.** (what
  the branch has, what is left), then `git switch <main>`. The first `git add` leaves out the local files under
  `.claude/` (worktrees, local settings); `git add -u` still takes the changes to files there
  that git already tracks.
- **A parallel run:** every rule above is for every helper that runs. When the run stops at once,
  a helper that waits for its merge turn does the STOPNOW steps, and its pull request stays open.
  With a queue, each helper of a slot does them for its own issue; after `STOP`, no new helper
  starts in a slot. A batch check that runs (section 4d) is stopped like a check on a branch
  (below); its pull requests stay open, and a later run takes them.
- **A check on a branch** (`ap-check-branch`, section 4c, or `ap-batch check`, section 4d) that
  runs when the run stops at once: stop it (`TaskStop`). The worktree
  `.claude/worktrees/check-<branch>` (or `check-batch-<run id>`) it leaves is removed by the next
  check of that name, or by `ap-run end` when no other run goes on.
- An issue stopped in the middle keeps `status:in-progress`, and its last comment starts with
  **Stopped in the middle.** The next run takes it first, by itself (step 2), once no other run
  goes on. `/ap:run <N>` takes it at once. Say this in the closing comment.

## 1. Before the first helper

```bash
git status --short | head -5      # the main checkout must be clean (local .claude/ files aside)
git switch <main> && ap-git-sync pull   # fetch and pull, one worktree at a time
git branch --show-current         # on main
gh pr list --state open --limit 20
ap-run start                      # this run's id: keep it, and write it on the run issue
                                  # (a run that /ap:schedule started has its id already: no start)
ap-run cleanup <run id> --min-free-gb 5   # the project's cleanup; exit 3 = disk low
```

The manager never runs the project's cleanup hook itself: it uses `ap-run cleanup <run id>`.
While another run goes on (a run that went on after a `STOP`), that adds `--older-than 90`, so the
other run's test runs stay. With no `hooks.cleanup`, it does nothing and exits 0.

- **Is the disk low?** The cleanup exits 3 when less than 5 GB stay free (the project's cleanup
  decides how it counts). Do not start a helper: a full disk stops every build and deploy.
- **Space only the owner can give back.** When the cleanup prints a line that starts with
  `can free:` (space a step of the owner's frees, such as a disk file that only shrinks in an
  admin shell), ask now, before the first helper, not when the disk runs out in the middle of the
  run. The owner is in this chat: ask them to do it (the line says what), wait for their answer,
  and run the cleanup again. They are away: write the line on the run issue, send it to the
  owner's phone (`ap-notify --hold 30`), and go on.
- **Exit 3 while no helper runs** (here, and wherever a step below sends you here): first free
  what the run still holds, then check again. Stop the slot previews (parked or not):
  `ap-run stop-previews <run id>` (all of them, or only this run's while another run goes on).
  Run the same cleanup command again. It passes: go on. If it was the `--min-free-gb 11` check
  for a slot with no worktree yet, a slot that already has its worktree needs only
  `--min-free-gb 5`: when that passes, start the helper there. Still exit 3: the disk is low. Do
  not start a helper, and do not deploy. Write it on the run issue (**Waiting for <owner>.** the
  free space, and what takes it, as the cleanup printed it; the merged issues that wait for a
  deploy), and stop the run (step 6, without its last deploy: it still ends with the look back
  and the message to the owner's phone).
- **Another exit that is not 0 or 3:** the cleanup did not run in full. Write its last line on
  the run issue, and run it again before the next helper.

- **Is main green?** Run the project's check (`check` in `.claude/ap.json`) on main.
- **Main is red:** that comes before everything. Open a `type:bug`, `P0` issue with the failing
  part and the end of its log, and make it the first issue of the list. Search first
  (`gh issue list --state open --search "<the failing part>"`): when an open issue already has
  it, add the log there as a comment, give it `P0`, and make that one first.
- **A branch on `origin` or an open pull request already exists** for an issue: another session
  may be on it. `ap-list` (step 2) leaves it out and says so (`left out: #N (open PR #M)`, or
  `(branch <name>)`), unless the owner named it in the arguments, or it is
  `(stopped in the middle)`: its helper goes on from the branch.

## 2. The list

```bash
ap-list --run <run id> [the label limit] [the issue numbers]
```

`ap-list` is the one place the list is built (`/ap:status` shows the same list, with the same
limit). It prints one line per issue, in the order to take them
(`#47 P2 <title> area:app size:S`), then a `left out: #N (why)` line for each stopped or named
issue it leaves out, then the label limit (`ap-list --json` names every issue left out, with why).
It leaves out the issues that wait for the owner, are
blocked, in progress, later, wait for a phone check, `type:decision`, `tracking` and `inbox`. The
project's part may name more labels to leave out: give each with `--leave-out <label>`. Exit 2:
it could not read the issues (its words say why); run it again once, then write its words on the
run issue and stop (step 6).

The order:

1. **The issues a stop left in the middle** (marked `(stopped in the middle)`): `status:in-progress`
   and a last comment that starts with **Stopped in the middle.** Their work is pushed, often
   with a pull request; their helper goes on from it. They come first only while no other run
   goes on (it may be on them): else `ap-list` leaves them out and says so.
2. **The approved look-back issues** (marked `(approved look back)`): a `[retro]` issue with a
   comment that starts with **Decided** (the owner said yes or no to each proposal in
   `/ap:waiting`). They are `area:tooling` issues: one at a time beside other helpers (section
   4b). They change the run itself, so they never wait for a run of their own kind.
3. `P0` to `P3`, and the lower number first inside one priority.
4. An issue that needs another open issue goes after it. The planner (section 3b) or the helper
   tells you (`needs #M`); you do not read issue bodies to find out.

**A label limit** ("Which mode am I in?") is given to `ap-list` as `--label <l>` (every one is
needed; `--label <a>,<b>` means either one) and `--not <l>`. It keeps every `P0` (a red main, a
failed deploy: it comes first, whatever its labels). A kind or `--label` never leaves out an
approved look-back issue; a `--not` that names one of its labels does. It holds for the whole
run: for named issues (`ap-list` says which one it leaves out: write that line on the run issue),
for the bugs the run files, and for the planner's list. Write it in the run issue, as `ap-list`'s
last line says it.

Do not read the bodies. The planner reads them once at the start (section 3b), and each helper
reads its own issue and decides whether an agent can do it.

**Small issues go together.** Issues that are next to each other in the list, have the same
`area:*` label and `size:S`, go to one helper as a group: at most 3 per group. An issue with no
size label is not small. `ap-list` marks them: `(one helper with #N #M)`. The helper does them on
one branch, with one pull request, and that saves the start of a helper, the reading of the code
and the checks for each one. `/ap:plan` shows the same list before a run (`ap-list --json`).

## 3. The run issue

Every run has one issue. It is what the owner reads when they are back.

```bash
gh issue create --label "tracking,type:chore,area:tooling" \
  --title "[autopilot] Run of <YYYY-MM-DD>" --body-file <file>
gh project item-add <board.number> --owner <board.owner> --url <url of the new issue>   # only with a board
```

Body: who started it and with which arguments, the run's id (from `ap-run start`), then the list
from step 2 as it stands, with its `left out` lines. Name the stopped issues it takes first in one
line: `Stopped earlier, taken first: #591, #711.` Simple English
(`${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md`). If an `[autopilot]` issue is still open from a run that was cut off, go on in that one instead of
opening a second, but only when no other run goes on (`ap-run others <run id>` prints nothing). A
run that is still ending after a `STOP` is not cut off: open a new issue,
`[autopilot] Run of <YYYY-MM-DD> (second)`, with a link to the other one.

Then the lines for the parts that are off (section 0), in one comment.

## 3a. New reports from users

Only when `parts.bug_reports` is `true`: do the steps of `${CLAUDE_PLUGIN_ROOT}/skills/bug-reports/SKILL.md`
now, with its rule first (you never read a report: only its read-only judge does), and one line
per report on the run issue. The bugs and features it files are new issues: add them to the list
of step 2 by their priority, within the label limit.

## 3b. The planner, before the first helper

The list is only as good as its issues. Two issues can ask for the same thing and nobody sees
it, a `size:L` issue is too big for one helper, and an issue with no "When is it done" leaves its
helper guessing. So every run, before the first helper (a run that goes on in an open
`[autopilot]` issue too), start **one planner agent** that cleans the list up:

1. Start it with the `planner` brief ("The briefs" above): `ap-brief planner --run <RUN> --n
   "<the issue numbers of the list from step 2, in its order>"`. Wait for
   its report; `STOP` and `STOPNOW` can come meanwhile: then stop it (`TaskStop`) and go to step 6.
   (`STOP IN` and `STOP AFTER` let it finish.)
2. Its report is a few lines: issues it gave a missing `type:*` or `size:*` label, closed as
   duplicates, split, gave a "When is it done", sent to the owner, `needs` lines (every pair,
   also the ones already written on the issues) and `files` lines. Keep only the `needs` lines
   (they set the order, step 2) and the `files` lines (which issues of one area may run together,
   section 4b). Its full summary is a comment on the run issue.
3. Run the list of step 2 again: the closed, split (now `tracking`) and waiting issues are gone,
   and the new parts are in. Put the new list in the run issue's body
   (`gh issue edit <RUN> --body-file <file>`).
   - With issue numbers in the arguments: a named issue the planner closed as a duplicate is
     replaced by the one it points to, and a split one by its parts, in their order.
4. Stop the planner (`TaskStop`) if it is still listed as running after its report.

The planner fails or ends without a report: write it on the run issue in one line and go on with
the list as it is. A failed planner never stops the run.

## 4. One issue at a time

(A parallel run, `X2` and up: section 4b says what changes.)

For each issue, in order:

1. `ap-run alive <run id>` (the run still goes on, so the end of another run leaves its test runs
   alone). Start **one** helper with the `helper` brief ("The briefs" above): `ap-brief helper
   --run <RUN> --n "<its issue, or all the numbers of a group>"`.
2. Wait for its report (you are told when it ends; one of the owner's stops can come meanwhile,
   "Stopping a run"). Do not start a second helper while one runs: they share the main checkout.
   Do not check on it, do not do part of its work.
   - It reports `ready #<PR>` when its pull request waits for the merge: do the review and the
     check (section 4c), then send it `MERGE TURN` (SendMessage), and wait for its last report.
   - **A report with no result word** (`merged`, `needs-owner`, `needs #M`, `blocked`,
     `nothing-to-do`, `failed`, `stopped`, `ready #<PR>`): the helper stopped too early. Send it back at once
     (SendMessage): `Go on: wait for your background command with Monitor, and finish the
     issue.` Write one line on the run issue.
3. Check the report against the tracker, cheaply:
   ```bash
   gh issue view <N> --json state,labels --jq '.state, [.labels[].name]'
   git branch --show-current         # back on main
   ap-run cleanup <run id> --min-free-gb 5   # nothing left to stop or delete
   ```
   - `merged` but the issue is still open (and neither `status:phone-check` nor a label of the
     project's part keeps it open),
     `blocked` but the issue has no `status:blocked`, or the checkout is not back on main: send
     the same helper back to finish (SendMessage), once.
   - Main went red: the next helper fixes main first (a `P0` bug issue), before any other issue.
   - The cleanup stopped or deleted something: the helper left it. Say so in the run issue
     comment. It exits 3: do what step 1 says for "Exit 3 while no helper runs".
4. Write one comment on the run issue: `#47 merged in #62: <one line>`, or
   `#39 waiting for <owner>: <the question in a few words>`, or `#21 failed: <why, one line>`, or
   `#54 blocked until 2026-10-27: <why, one line>`.
   Write it now, not at the end. The session can be closed at any second.
   - A `waiting for <owner>` line (from a helper, the planner's "Sent to <owner>", or a
     `NO MERGE`) also goes to the owner's phone, at most one message every 30 minutes:
     `ap-notify` keeps the others and sends them with the next message, the run's last one too
     (step 6).
     ```bash
     ap-notify --hold 30 "<repo name>: <owner> is needed" "#39: <the question in a few words>" <issue url>
     ```
5. Keep only that line. Drop the rest of the report.
6. If the helper is still listed as running after its report, stop it (`TaskStop` with its id).
   A helper that still runs can wake up again and use budget. Write it in the run issue comment
   when you had to.

**Deploy every 5 merged issues**, not after each one: a deploy takes time, and helpers keep
working meanwhile. Also deploy at the end of the run, whatever ended it. Only when the project
deploys (section 0):

```bash
ap-git-sync pull && ap-deploy   # in the main checkout, on main: the check, then the deploy command
```

When `ap-git-sync pull` fails (its words say why), do not deploy this time: write one line on the
run issue with its last line, and try again at the next deploy point; at the run's end, it goes in
the closing comment.

`ap-deploy` refuses unless the main checkout is on main, with nothing uncommitted, and equal to
`origin/<main>`; then it runs the check (`ap-check` on every part of `check_parts`, quick after
the merges, which passed already; or the `check` command), and the `deploy` command only when the
check passed. Its exit code:
- 0: deployed. Write it on the run issue: `Deployed <the issues>: <its last line>.`
- 3 (refused: the main checkout is not ready, or origin moved during the check): a problem of the
  run, not of the code. Write its last line on the run issue, put the main checkout right
  (`git status`, `ap-git-sync pull`), and run it once more.
- 2 (it could not run), 4 (the fetch failed): write its last line on the run issue; try again at
  the next deploy.
- 5 (the check failed) or 6 (the deploy failed): like a red main. Open a `type:bug`, `P0` issue
  with the end of the output, and the next helper fixes it first.

The project's part may add a step after a deploy.

**QA after a deploy**, only when `parts.qa` is `true`: do the steps of
`${CLAUDE_PLUGIN_ROOT}/skills/qa/SKILL.md` on the live site, in the background (`ap-background
ap-qa`), and only when at most one helper runs (its browsers on a busy computer make checks fail
for nothing); otherwise wait for that moment. After the last deploy of the run, when no helper
runs. `ap-qa` waits by itself while a deploy holds the deploy lock.

**The helper was cut off** (usage limit, a crash, no report): when the session goes on, look at
what it left (`git status`, `gh pr list`, `git log origin/<main>..origin/<branch> --oneline`),
then start a fresh helper for the same issue. The brief already tells it to go on from the
branch.

## 4b. A parallel run (`X<N>`)

Up to N slots work at the same time (with a queue, a slot has a helper in each of its worktrees,
below). They must never get in each other's way, so:

- **Slots.** Number the running helpers 1 to N. A helper keeps its slot until it ends; the next
  helper takes a free one. Give the slot number in the brief. Before you start a helper in a
  slot: `ap-run hold <run id> <slot> <issue>` (a group: its first issue), so the end of another
  run leaves that slot's worktree alone. When an issue of the slot ends (its helper's line for it
  has a result, whatever it is): `ap-run free <run id> <slot>` (with a queue: the worktree's name,
  `1b`). The check's log counts the checks that ran while the same slot had another issue open:
  the time a queue saved. `hold` warns when another run that still goes on held the slot: start
  the helper there only when no helper of that run works in it. It deletes a folder that an end
  of a run left in the slot. It fails ("not taken") while a file there is still in use, or when
  the slot's folder is no worktree and no end left it: start no helper in that slot. Hold it
  again later, or write on the run issue what is in that folder.
- **One git worktree per slot, for the whole run:** `.claude/worktrees/ap-<slot>`, a second
  folder of the same repository. The first helper of a slot makes it; every later helper of that
  slot uses it again, on its own new branch, so the build caches are still warm. A helper leaves
  its worktree clean (everything committed and pushed). The main checkout is yours: it stays on
  main, clean, and you `ap-git-sync pull` there after each merge.

**Which issues may run together.** When a slot is free, take the first issue in the list order
(step 2) that may run beside the ones that run now. You still read only titles and labels:

- Not the same `area:*` label as a running issue, unless both issues have `parallel-safe`. The
  same area means the same files, and so merge conflicts. Two issues of one area may also run
  together when the planner gave both a `files` line, the two lines share no folder or file (and
  none is inside a folder of the other), and neither is `?`. A merge conflict between them then
  is a planner mistake: write it on the run issue.
- An issue with no `area:*` label runs alone: start it only when no helper runs, and start
  nothing beside it.
- One `area:tooling` issue at a time may run beside other helpers, only if it harms nothing else.
  It changes the scripts and rules every helper uses, so its helper:
  - keeps every script it changes working for helpers that still use the old copy;
  - never stops, restarts or changes other helpers' servers, containers, checks or worktrees;
  - when its PR changes the project's check, cleanup or the run's own rules, says in the PR under
    "For the manager" what you must do after the merge. Do it.

  Tell the helper these rules in the message that starts it.
- A `P0` issue (main red, a failed deploy) comes first: start no new helper until it is merged.
  The helpers that run go on working, but get no merge turn until then.
- A helper reported `needs #M`: that issue waits until #M is merged.
- A group of small issues (step 2) is one helper, as before.
- Nothing fits: wait until a helper ends.

**A queue per slot** (`queue_per_slot`, Q; missing or `1`: no queue). A helper waits a lot:
for the review, the check on its branch, its merge turn. So a slot may have up to Q issues open
at a time, each with its own helper, on its own branch in its own worktree of the slot: `ap-<s>`
for the first, `ap-<s>b` for the next (`ap-<s>c` with Q = 3). A queued issue always goes to a
fresh helper with its own brief, never to a helper that has an issue already: each helper holds
one issue, so its context holds only that one.
- **Which issue may queue.** The first issue in the list order that may run beside every issue
  that runs now (the rules above), and also: not the same `area:*` as any issue open in the slot,
  and, when the planner gave both a `files` line, the two share no folder or file. No `area:*`
  label, a group, or a `P0` open: no queued issue.
- **When you start its helper.** When a helper of the slot reports that it waits (`ready #<PR>`,
  or a fix pushed after `REVIEW CHANGES`: it waits for the review, the check on its branch or its
  merge turn) and the slot has fewer than Q issues open. It goes in the first worktree of the slot
  that is free (its issue ended). Before you start it: `ap-run hold <run id> <s>b <issue>` (the
  worktree's name), and the cleanup below, which counts that worktree too. Its brief ends with
  `Your slot is <s>.` and `Your worktree is ap-<s>b.`
- **A fix to the first issue comes first.** The helper that waits is still there: `REVIEW
  CHANGES`, `MERGE TURN`, `BATCH MERGED` and `NO MERGE` go to it, as without a queue. Answer its
  reports before you start a new helper in the slot.
- Write on the run issue, for each queued issue, the line of its start: `#58 queued in ap-1b
  (beside #47)`.

**Before each new helper:** `ap-run cleanup <run id> --older-than 90 --min-free-gb 11` when its
worktree (`ap-<s>`, or `ap-<s>b` of a queue) is not there yet (a new worktree with its build
caches takes space), `--min-free-gb 5` when it is already there. The project's part may set other numbers. Exit 3:
start no new helper now. When none runs: step 1, "Exit 3 while no helper runs". When the cleanup
prints that the disk or memory fell by a few GB since its last run, write that line on the run
issue, and start no new helper until a helper ends.
Never run the cleanup without `--older-than` while a helper runs: it would stop that helper's
test run.

**Merges, one at a time.** A helper whose pull request is ready reports `ready #<PR>` and stops.
Review and check it first (section 4c, one at a time); only an approved pull request whose check
passed joins the queue. With `merge_batch` 2 or more, the queue's pull requests are merged in
batches instead (section 4d); a conflict in a batch, and a `P0`, still take the merge turn below.
When no helper holds the merge turn, no batch is being merged, and no `P0` is open, send the first
one in the queue (SendMessage): `MERGE TURN`. It merges the latest main into its branch, solves
the conflicts, runs the check again, pushes when the merge made a commit, merges, and reports.
Then `ap-git-sync pull` here, and give the turn to the next one. Only one helper merges at a
time, so every branch is checked on top of everything merged before it.

**Long check waits.** The project's check may run its heavy steps one at a time, so a helper's
check can wait for another's. When a helper reports long waits, write them on the run issue.

**Deploy** every 5 merges, as before, at a moment when no helper holds the merge turn and no batch
is merged (section 4d), and only
after `ap-run cleanup <run id> --older-than 90 --min-free-gb 5` passes. Exit 3: wait until a
helper ends; when none runs, step 1, "Exit 3 while no helper runs".

**Checking a report** (step 4.3) in a parallel run:
```bash
gh issue view <N> --json state,labels --jq '.state, [.labels[].name]'
git -C .claude/worktrees/ap-<slot> status --short       # nothing: all committed
ap-git-sync -C .claude/worktrees/ap-<slot> pushed        # and pushed: origin/<branch> is HEAD
```
(`ap-<s>b` for an issue of a queue: the worktree its helper was in.)
Work left in the worktree: send the helper back once to fix it. The worktree stays for the next
helper of that slot.

**A helper that does not answer** `STOPNOW` in 10 minutes: stop it (`TaskStop`), then
`git -C .claude/worktrees/ap-<slot> add -A -- . ':!.claude'`,
`git -C .claude/worktrees/ap-<slot> add -u`, `git -C .claude/worktrees/ap-<slot> commit -m "WIP:
stopped by STOPNOW"`, `ap-git-sync -C .claude/worktrees/ap-<slot> push`, and a comment on its
issue. The worktree stays for the next helper of that slot.

Three helpers in a row that report `failed` (in the order the reports come) stop the run (step 5).

## 4c. A fresh review before every merge

The helper that wrote the code also ran `/code-review` on it, but an author misses its own
mistakes, and it already "knows" what the code was meant to do. So every pull request gets a
second look from a **fresh reviewer agent** that did not see the work, before its merge turn.

1. A helper reports `ready #<PR>`. Start a reviewer with the `reviewer` brief ("The briefs"
   above): `ap-brief reviewer --run <RUN> --n "<the helper's issues>" --pr <PR>`. Only one reviewer runs at a time (the run may be
   short of memory): the others wait in the order their `ready` came.
2. The reviewer ends with one line: `approve` or `changes: <how many points>`. Keep only that
   line. It wrote the full result as a comment on the pull request.
   - `approve`: step 3.
   - `changes` (and `changes: ..., all new from the last fix`): send the helper (SendMessage,
     the same helper, not a new one):
     `REVIEW CHANGES on PR #<PR>. A fresh reviewer asks for changes: read its last comment
     (gh pr view <PR> --comments). Fix each point, or answer on the PR why it is wrong. Run
     /code-review on your fix commits, from the commit the reviewer read to HEAD. Commit, run
     the check, push with ap-git-sync, then report ready #<PR> again. Do not merge.` When it
     reports `ready` again, send the **same** reviewer (SendMessage): `The helper reported ready
     again. This is a later round: check its new commits and its answers on PR #<PR> against your
     points, and anything the fixes broke. Write a new comment, and end with one line as before.`
3. **The check on the branch.** The helper says its check passed; you make sure, in a folder of
   its own, so your checkout stays on main. From the main checkout (keep only its exit code and
   its last lines):
   ```bash
   ap-git-sync fetch
   ap-check-branch <the PR's branch>                 # when the check is quick
   ap-background ap-check-branch <the PR's branch>   # in the background, when it takes long
   ```
   In the background, always through `ap-background`: stopping it then also stops the programs
   the check started. `ap-check-branch` makes the worktree `.claude/worktrees/check-<branch>` at
   `origin/<branch>`, runs `hooks.check_setup` there when it is set, then `check` (both from the
   branch's own `.claude/ap.json`), and removes the worktree, also when the check fails. With
   `ap-check`, a part whose code passed already (in the helper's worktree, most often) is not
   checked again: its line says where and when it passed (`py: passed before (ap-1, ...)`). Its
   exit code is the check's, or one of its own:
   - Exit 0: the pull request joins the merge queue (`MERGE TURN`, section 4 or 4b), or the next
     batch (section 4d).
   - Exit 90 (it could not run: no `origin/<branch>`, no worktree, a left folder still in use) or
     91 (`hooks.check_setup` failed): a problem of the run, not of the branch. Write its last line
     on the run issue, then `ap-git-sync fetch` and run it once more. Never send `REVIEW CHANGES`
     for it. Still 90 or 91: as "main fails the same way" below.
   - Any other code: the check failed. First see whether the fresh folder is the cause. Run it
     once on main too: `ap-check-branch <main>`. Main fails the same way: it is the project's setup,
     not the helper's code. Write one line on the run issue, tell the owner (`ap-notify --hold 30`:
     "the check cannot run in a fresh checkout; `/ap:setup` sets `hooks.check_setup`"), and take the
     helper's own check: the pull request joins the merge queue. Do this test on main once per run,
     and keep its answer. From then on this run uses no batches (section 4d): every pull request
     takes its helper's merge turn. Write that in one line on the run issue.
   - Main passes: the branch is the cause. Send the helper (SendMessage): `REVIEW CHANGES on PR
     #<PR>. The check failed on your branch: <the failing part and its last lines>. Fix it, run
     the check, push with ap-git-sync, then report ready #<PR> again. Do not merge.` This counts
     as a round of fixes. When it reports `ready` again: the same reviewer checks the new commits
     (step 2), then this step again.
4. **After 2 rounds of fixes** that still do not pass (the review still asks for changes, or the
   check still fails): do not merge. One case gets a third round: the reviewer's last line ends
   `all new from the last fix` (the helper fixed every earlier point, and only the last fix's new
   bugs are left). Send `REVIEW CHANGES` once more, as in step 2. After a third round that still
   does not pass, or in every other case: add `status:waiting-for-owner` to the issue, and a comment
   that starts with **Waiting for <owner>.**: which one still fails (the reviewer and the helper
   do not agree on PR #<PR>, with a link to the last review comment; or the check, with its
   failing part), and the question "Merge as it is, or what should change?". Send the helper:
   `NO MERGE: after <2 or 3> rounds, <the review still asks for changes | the check still fails>. Leave
   PR #<PR> open, do the "At the end" steps of your brief, and report needs-owner.`
5. Write the result in the issue's line on the run issue (step 4 of section 4): `#47 merged in
   #62 (review: 1 round)`.
6. Stop the reviewer (`TaskStop`) if it is still listed as running after its last line.

The reviewer never changes code, pushes, merges or deploys, and starts no agents of its own.
A stop at once while a review runs: stop the reviewer (`TaskStop`); the pull request stays open,
as for any helper that stopped ("Stopping a run").

## 4d. Merges in batches (`merge_batch`)

In a parallel run with `merge_batch` B of 2 or more, while the check runs in a fresh checkout
(section 4c, step 3: not "main fails the same way"). Each merge turn runs the check once more,
after the latest main is merged in, and it seldom fails. So up to B approved pull requests, each
with a passing `ap-check-branch` (section 4c), are merged together on the latest main, checked
once, and then merged into main. Their helpers do not run the merge turn's check.

1. **When.** B pull requests wait in the queue; or fewer wait, and no helper works on anything
   that could join soon (every helper waits for you); or the run is ending. Never while a helper
   holds the merge turn, and never while a `P0` is open (a `P0`'s own pull request takes the merge
   turn at once). One batch at a time. Only one pull request waits: no batch; its helper takes
   the merge turn (`MERGE TURN`, section 4b), which does the same with fewer steps.
2. **The check**, from the main checkout, the branches in the order they joined the queue:
   ```bash
   ap-git-sync fetch && ap-background ap-batch check <run id> <branch> <branch> ...
   ```
   In the background, like `ap-check-branch`, and wait for it. It merges each `origin/<branch>`
   on `origin/<main>` in a worktree of its own (`check-batch-<run id>`), runs `hooks.check_setup`
   and the check once, and when that fails, finds by halves the first branch that breaks it. One
   line per branch:
   - `passed <branch>`: checked with the ones before it. Step 3.
   - `conflict <branch>`: it does not merge cleanly. It leaves the batch: send its helper
     `MERGE TURN` as in section 4b (it merges main, solves the conflict, runs the check, merges),
     after this batch is merged.
   - `breaks <branch>`: the check fails with it. Send its helper: `REVIEW CHANGES on PR #<PR>.
     The check of a batch failed once your branch was merged on the latest main: <the failing
     part and its last lines>. Merge the latest main into your branch, fix the cause, run the
     check, push with ap-git-sync, then report ready #<PR> again. Do not merge.` It counts as a
     round of fixes (section 4c, step 4).
   - `later <branch>`, `missing <branch>`: not checked; it stays in the queue for the next batch.

   Its exit code: 0 passed, 1 one breaks it, 3 nothing to check (every branch conflicts), 4 main
   itself fails the check (as a red main: a `P0`; the pull requests wait in the queue), 90 or 91 a
   problem of the run, not of a branch ("the check could not run" is never a break, and it finds
   no halves then): as in section 4c step 3, write it, `ap-git-sync fetch`, and run it once more.
   Still 90 or 91: this run uses no more batches (one line on the run issue), and each of its pull
   requests takes the merge turn, one at a time.
3. **The merge**, when there are `passed` lines (exit 0 or 1):
   ```bash
   ap-batch merge <run id>
   ```
   It first fetches: when main is no longer the commit the batch was checked on, it merges
   nothing. Else it merges each passed pull request in its order (`--squash
   --match-head-commit`, the commit the batch merged), stops at the first one it cannot merge,
   and checks that main has the tree the batch checked. Then `ap-git-sync pull` here, and send
   each merged one's helper (SendMessage): `BATCH MERGED #<PR>. It was merged with a batch: write
   the closing comment, close the issue, and do the "At the end" steps.`
   - Exit 1: nothing was merged (the first one has a new commit since the check, or GitHub
     refused it). That one goes back through section 4c (review and check); the rest go in the
     next batch. Write it on the run issue.
   - Exit 4: main moved since the check: nothing was merged. Check the same batch again (step 2).
   - Exit 90: a problem of the run (its first fetch failed): nothing was merged, and the batch is
     kept. Write its last line on the run issue, and run `ap-batch merge <run id>` once more.
   - Exit 3: something was merged, but main is not a tree that was checked (not all were merged,
     or another hand changed main). Before any other merge, run the project's check on main at
     once (as in step 1, "Is main green?"); red: a `P0`. The ones not merged go back through
     section 4c, or in the next batch. Write it on the run issue.
4. Write one line per merged issue on the run issue, as in section 4: `#47 merged in #62 (batch of
   3)`. A deploy counts each merged pull request.

## 5. When to stop

- The list is empty.
- The owner's limit is reached, or one of the owner's stops says so ("Stopping a run").
- Three helpers in a row report `failed`. Something shared is broken; more helpers will only burn
  the budget. Write what the three have in common on the run issue.
- Main is red and the helper that was sent to fix it failed.
- `ap-run cleanup <run id> --min-free-gb 5` still exits 3 with no helper running and the previews
  stopped (step 1, "Exit 3 while no helper runs").

Never stop to ask the owner something. A question for the owner goes on its issue with
`status:waiting-for-owner`, and the run goes on with the next issue.

## 6. The end of the run

First the last deploy (step 4, when the project deploys), after
`ap-run cleanup <run id> --min-free-gb 5` passes (exit 3: step 1, "Exit 3 while no helper runs").
Then `ap-run end <run id>`. It frees only what this run holds, since another run may work in the
same slot worktrees (a run that went on after a `STOP`). It stops the slot previews, the test runs
(only what is 90 minutes old while another run goes on), and only then removes this run's slot
worktrees (the branches stay), and, when no other run goes on, the check worktrees (`check-*`)
that a stopped `ap-check-branch` left. A removal can fail in two ways, and the script says which:
- "kept the worktree ap-<s>": git refused, so it has work not committed (or it is locked). Write
  it in the closing comment, under "Stopped in the middle".
- "kept the folder ap-<s>": a file is still in use. git has dropped the worktree, and something
  else holds the file (the line names it when it finds one, such as an editor). Write the line on
  the run issue. Never delete the folder by hand: the next `ap-run hold` of that slot deletes it,
  and takes the slot only once it is gone.

The script's last line says whether another run goes on ("other runs: none", or "other runs:
<ids>"). The project's part may say what to stop when none goes on.

Its exit code:
- **0:** all done.
- **3:** the disk is low (the project's cleanup said so). Say it in the closing comment (the free
  space, as the cleanup printed it) and in the message to the owner's phone (`--high`).
- **Any other code that is not 0:** a part of the end did not run in full. Write its lines on the
  run issue, and go on with the look back.

**The look back.** Every run ends with one, so the next run does not lose time on the same
trouble. Start **one retro agent** with the `retro` brief ("The briefs" above): `ap-brief retro
--run <RUN> --date <the day the run started>`. Wait for its last line (`retro #<M>`, or `no lessons`), and
stop it (`TaskStop`) if it is still listed as running after it. It fails or gives no report:
write "Look back: the retro agent failed" in the closing comment, and go on. `STOPNOW` while it
runs: stop it, and write "Look back: stopped by STOPNOW".

Then close the run issue with a closing comment, in simple English, with these parts (skip an
empty one):

- **Merged and deployed:** one line per issue, with its pull request. When the project deploys,
  say that it is live (on `site`, when it is set), or that the last deploy failed, and its issue.
- **Planned:** the planner's changes in one line (duplicates closed, issues split), with a link
  to its summary comment (section 3b).
- **Waiting for <owner>:** one line per issue, with the question (the retro issue goes under
  "Look back"). End with: "Run `/ap:waiting` to go through them."
- **Choices the agents made, that <owner> can change:** from the helpers' reports. Design choices
  (how a screen looks and works) go here too.
- **Stopped in the middle** (`STOP` or `STOPNOW`): the issue, its branch, what is done, what is
  left. "The next run takes them first (or `/ap:run <N>` now)."
- **Failed or left out:** the issue and why.
- **Done outside the repository:** what, where, how to undo it.
- **New issues opened on the way.**
- **Time saved:** when `check` is `ap-check`, the two lines under "Time saved:" of
  `ap-check --stats <the run's start, as YYYY-MM-DDTHH:MM>`: what the batches saved (section 4d)
  and what the queues saved (section 4b), from the check's log.
- **Look back:** the retro issue (and its bug issues), or "No lessons this time".

**The message to the owner's phone, the very last step:** one message with the numbers and the
link to the run issue. `--high` when the run stopped because something broke (the disk is low,
main is red, three helpers failed, the last deploy failed), with the reason in a few words. It
also carries the "is needed" lines that `--hold` kept back, so none waits for the next run.
The retro issue is counted apart: it is a proposal, not a question about the work.
```bash
ap-notify "<repo name>: autopilot run ended" "5 merged, 1 failed, 2 wait for <owner>, 1 retro proposal waits." <run issue url>
ap-notify --high "<repo name>: autopilot run stopped" "The disk is low. 3 merged, 0 failed, 1 waits for <owner>." <run issue url>
```

The reply in the chat is the same list, shorter, in the `chat_language`. It ends with
`Recorded: #<run issue>`, and then, as its very last line (in the `chat_language`): `The run is
over. A new run can start now.` Until that line, the run still ends (its last deploy, its look
back) and holds its slots: a new run started meanwhile opens its own run issue (section 3).
