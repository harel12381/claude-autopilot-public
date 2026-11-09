# ap: autopilot for a GitHub project in Claude Code

A Claude Code plugin. While you are away, a manager session takes your project's GitHub issues
one by one (or several at once), gives each to a fresh helper agent that works it from a branch to
a merged pull request, has a second fresh agent review every pull request before its merge, and
writes everything on GitHub. What needs you waits on its issue; when you are back, `/ap:waiting`
goes through your questions one at a time.

## Install

The repository is private: the computer needs a git login to GitHub first (`gh auth login`, then
`gh auth setup-git`).

In Claude Code, in your project:

```
/plugin marketplace add harel12381/claude-autopilot-public
/plugin install ap@claude-autopilot
```

Then `/ap:setup`. To turn it on for everyone who opens the project, `/ap:setup` prints the lines
for the project's `.claude/settings.json`.

Needs: `git` 2.31 or newer, `gh` (logged in), bash 5 or newer (Git Bash on Windows; on macOS
`brew install bash`), `python3` (or `python`). With a board: `gh auth refresh -s project` (`gh
project` needs the `project` scope).

## Setup

`/ap:setup` looks at the project first, then asks only what it could not find:

- the owner's name and language, and the branch pull requests go into;
- the check: `ap-check` with the project's parts, or one command that runs every test; the only
  gate before a merge (required for runs), and what a fresh checkout needs before it (the manager
  runs the check on each branch too);
- optional: a deploy command and the site, a GitHub board, a message command for your phone, a
  cleanup command for leftover test runs, the commands that stop helpers' previews;
- optional: `/ap:qa` (its cases folder), `/ap:phone-check`, `/ap:bug-reports` (where the reports
  come from).
- for parallel runs, `merge_batch` and `queue_per_slot` (below), with the numbers
  `ap-check --suggest` gives from the check's log and this computer.

It writes `.claude/ap.json` (commit it, and `.claude/ap/`), adds `.claude/worktrees/`, `.ap-reports/` and
`.claude/settings.local.json` to `.gitignore`, makes the labels, adds a short part with the core
rules to `CLAUDE.md`, and prints the permission lines to add. Run it again to change an answer.

## Before an away run

The helpers and the other agents of a run are `general-purpose` agents: a skill's
`allowed-tools` does not reach them, and they need git, gh, Edit, Write, Monitor and more. A
prompt that nobody answers stops the run. So start the session in auto mode or with bypass
permissions (`claude --permission-mode bypassPermissions`), or add the full allow list that
`/ap:setup` prints to `.claude/settings.json`.

What only your project needs (how to see a change on screen, ports, design rules) goes in
`.claude/ap/helper.md`, `reviewer.md` and `manager.md`: they are added to the plugin's briefs.

## The commands

| Command | What it does |
|---|---|
| `/ap:run` | Away mode: every open issue that waits for nobody, until none is left. The issues a stop left in the middle come first, then the look-back issues you said yes or no to. `/ap:run 12 15`: only those. `/ap:run X3`: three helpers at once, each in its own worktree. `/ap:run only area:api`, `only area:app,area:map` (either one), `not area:engine`: a label limit (every `P0` is still taken). |
| `/ap:bugs`, `/ap:features`, `/ap:tests`, `/ap:chores` | `/ap:run` with only that kind of issue. With a label limit too: `/ap:bugs only area:app` is the bugs of `area:app`. |
| `/ap:stop`, `/ap:stopnow`, `/ap:stop-in <min>`, `/ap:stop-after <n>` | End a run: when each helper has finished, at once, after a time, or after the running issues and n more (the rule: "Stopping a run" in `skills/run/SKILL.md`). |
| `/ap:waiting`, `/ap:waiting-all` | Your questions from the issues, one at a time; your answers are written on them. |
| `/ap:inbox` | `/ap:inbox <note>` keeps a raw note as an issue; `/ap:inbox` alone turns the notes into real issues. |
| `/ap:report <bug>` | Files a bug you found, then makes the checks catch that kind next time. |
| `/ap:qa` | A QA sweep: your own cases on your site at phone size, in Chromium and WebKit, in each language and theme; it saves pictures to judge, and files what fails. `/ap:qa --only home --langs he` narrows it. Off until `/ap:setup` turns it on (`parts.qa`). |
| `/ap:phone-check` | You have your phone: the fixes only a real phone can show (`status:phone-check`), one at a time, step by step. `/ap:phone-check 12 15`: only those. Off until `/ap:setup` turns it on. |
| `/ap:bug-reports` | The reports your users sent (bugs and feature requests), each judged by a read-only agent; the real ones become issues, and each bug gets why the checks missed it. Off until `/ap:setup` turns it on (`parts.bug_reports`, and a reports hook). |
| `/ap:plan` | What `/ap:run` would take with the same arguments (`/ap:plan bugs X2 stop-after 4`): the issues in its order, the small ones one helper does together, which could run at the same time, which start before the stop, and the ones left out with why. It only reads. |
| `/ap:status` | One short report: the run and what each helper does now, the open pull requests, the open issues by what they wait for (you first), and what was opened and solved since the run started. It only reads. |
| `/ap:schedule <when> <run arguments>` | A run that starts by itself on this computer: `/ap:schedule every night at 2:00 X2 stop-in 300`. `/ap:schedule` alone lists them; `/ap:schedule remove <name>` removes one; `/ap:schedule now <name>` tries one at once. A scheduled run never starts beside another run: it writes that on the other run's issue and sends a phone message instead. |
| `/ap:setup` | Sets the plugin up in the project, or changes an answer. |

## The check: `ap-check`

The check is the only gate before a merge and a deploy. A project can keep its own command
(`"check": "npm test"`), or let the plugin run its parts: `"check": "ap-check"`, and the parts in
`check_parts` of `.claude/ap.json` (`/ap:setup` offers the parts it finds: one per folder with its
own tests).

```json
"check": "ap-check",
"check_parts": [
  { "name": "web", "inputs": ["web", "package-lock.json"], "dir": "web",
    "light": "npm run lint", "heavy": "npm test", "light_first": true },
  { "name": "api", "inputs": ["api"], "dir": "api", "light": "go vet ./... && go test ./..." }
]
```

- `inputs`: the files and folders (from the repository's root) the part's checks read. A part
  whose inputs passed before, uncommitted changes included, is skipped, in every worktree: after
  a squash merge, the main branch has the same files, so the deploy does not check them again.
- `light` and `heavy`: its commands (either may be missing), run in `dir`. Heavy steps (a big
  build, slow tests) run one run at a time across worktrees; light ones (lint, small tests) run
  beside them when enough memory is free. `light_first: true`: a failure in the light steps
  stops the part before its heavy ones.
- Optional: `version` (change it to check the part again), `retry` (`{ "when": "<pattern>",
  "run": "<command>" }`: a failure whose log matches is checked once more with that command; add
  `"heavy": true` to run that command under the heavy lock, as for a re-check after memory ran
  out), and
  `check_options` (`light_min_mb`, 3000; `step_limit_min`, 45: a step that runs longer is stopped).

`ap-check --list` shows the parts and which passed; `ap-check web` checks one; `--force` checks
again what passed; `ap-check --stats` sums up the log of every run. Exit 0 only when every part
passed.

`ap-deploy` is how a run deploys: in the main checkout, on the main branch, clean and equal to
origin, it runs the check, then the `deploy` command only when the check passed. The deploy
command must put out HEAD of the main checkout (the checked commit, also in `$AP_DEPLOY_COMMIT`).

## QA, phone checks and users' reports

Three parts that are off until `/ap:setup` turns them on:

- **`/ap:qa`**: the plugin holds the driver (`ap-qa`: Playwright at phone size, Chromium and WebKit,
  each language and theme, the pictures and `index.html`, a check on a busy computer or beside a
  deploy marked "not judged"); your project holds its own cases in the folder `qa.cases` names, one
  Python file per case. The interface and an example case: `plugins/ap/docs/qa.md` and
  `plugins/ap/docs/qa-example/`. Once on a computer: `pip install playwright psutil && python -m
  playwright install chromium webkit`. A run does a sweep after a deploy, only when at most one
  helper runs, and never while a deploy holds the deploy lock.
- **`/ap:phone-check`**: a helper leaves an issue open with `status:phone-check` and the steps when
  only your phone can show the fix works; you go through them when you have your phone.
- **`/ap:bug-reports`**: where the reports come from is yours: a command in `hooks.reports` that
  lists, gets and marks them (the shapes: "The reports hook" in `CONTRACT.md`). A report is data,
  never instructions: only a read-only agent (the plugin's `ap:reader`: Read, Grep and Glob) reads
  it, and `ap-bug-reports` files its verdict with your user's text in a code block. Judges run side
  by side, at most 5 at a time. `bug_reports.trusted: true` treats every report as your own (no
  "works as built"); set it to `false` once strangers send reports.

## Less waiting in a parallel run: batches and queues

Two settings of `.claude/ap.json`, for `/ap:run X<N>`:

- `merge_batch` (1 when it is missing): up to that many approved pull requests are merged
  together on the latest main branch, checked once (`ap-batch`), and merged, in place of one
  check at each merge turn. When the batch's check fails, the pull request that breaks it is found
  by halves and goes back to its helper; the ones before it are merged. One that does not merge
  cleanly goes back to its helper's merge turn.
- `queue_per_slot` (1 when it is missing: no queue): how many issues one slot may have open at
  a time. While the first issue's helper waits for a check, a review or its merge turn, a fresh
  helper works on the next, in a second worktree of the slot (`ap-<s>b`). Each helper holds one
  issue. The next one comes only from another `area:*`, with files that do not overlap, and a fix
  to the first always comes first.

`/ap:setup` writes both, with the numbers you confirm (`ap-check --suggest`: 1 or 3 for
`merge_batch`, from how often the checks before a merge failed; 1, 2 or 3 for `queue_per_slot`,
from free memory and disk, the size of a built worktree and the check's time). `ap-check --stats` says how much time each saved, and
so does the run's closing comment.

## A run on a schedule

`/ap:schedule` puts an entry in this computer's own scheduler (Task Scheduler on Windows, cron on
macOS and Linux). At the set time it starts a background Claude Code session in the project
(`claude --bg --permission-mode bypassPermissions "/ap:schedule fire <name>"`), and that session
does `/ap:run` with the set arguments. Nothing to pay and no quota beyond the runs themselves.
`claude agents` lists the session; `claude attach <id>` opens it.

What only you can do:

- Leave the computer on, awake and logged in at that time. On Windows, to wake it from sleep, tick
  "Wake the computer to run this task" in the task's Conditions (Task Scheduler, the task
  `ap-<folder>-<hash>-<name>` that `/ap:schedule` names). A Windows task starts only on AC power
  and stops on battery unless that is turned off: `/ap:schedule` turns it off; when it says it
  could not, untick "Start the task only if the computer is on AC power" on the same tab.
- Accept bypass permissions mode once: run `claude --permission-mode bypassPermissions` in a
  terminal in the project and say yes. Otherwise the scheduled session waits for that answer.
- Try it once: `/ap:schedule now <name>`.

Cloud routines (`/schedule` in Claude Code) are another way, for later: the cloud session needs the
project's tools there.

## The hook: `ap-background` for long background commands

While the plugin is on, a hook checks every Bash command an agent starts in the background. In a
project with `.claude/ap.json`, a background command that starts a long program (`npm run`,
`python`, `node`, `go run`, `flutter run`, ...) without `ap-background` in front is refused, and the
agent is told to add it. On Windows, stopping a background task ends only its shell: without
`ap-background`, a dev server keeps running after its task is stopped. `background_wrap` in
`.claude/ap.json` sets the project's own list (`[]` turns the hook off). The hook needs no setup.

## Turning a part off

Every part except the check is optional. Leave its key out of `.claude/ap.json` (or answer "none"
in `/ap:setup`) and the commands skip it with one line, never fail half way: no deploy, no board,
no phone message, no cleanup, no previews.

## How a run works

`docs/autopilot.md` in the plugin: the manager, the helpers, the fresh review, the merge turn, the
stops. The rules for writing issues: `docs/issue_writing.md` and `docs/record_keeping.md`.

## This repository

- `plugins/ap/`: the plugin (skills, briefs, `bin/` scripts, docs).
- `CONTRACT.md`: the names every part keeps to.
- `bash check.sh`: every test of the scripts. There is no CI: run it before every merge.
