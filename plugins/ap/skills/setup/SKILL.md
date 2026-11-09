---
name: setup
description: Set up the ap plugin in this project, or change an answer - writes .claude/ap.json, makes the labels, adds the commands to CLAUDE.md, and prints the permission lines to add (/ap:setup)
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-config:*), Bash(ap-check:*), Bash(ap-schedule:*), Bash(ap-qa:*), Read, Glob, Grep, Edit, Write
---

# /ap:setup

Arguments: `$ARGUMENTS`

You set up the `ap` plugin in the project of the current folder, so its commands work here. The
settings file: the part "The project's settings" at the end. Run again any time to change an
answer: a value that is there is kept unless the owner changes it.

Talk to the owner in their language (ask once if it is not clear). Everything written to GitHub
and to files is simple English.

## 1. Look before asking

Find what the project already says, so you ask as little as you can:

- `git remote get-url origin` -> `repo` (`owner/name`). Not a GitHub repository: say that the
  plugin needs one, and stop.
- `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, and whether a `develop`
  branch is there -> `main_branch` (the branch pull requests go into).
- `gh project list --owner <repo owner> --format json` -> the boards, for `board`. `<repo owner>`
  is the GitHub account of `repo`, the part before `/` (never the `owner` name, which is a
  person's name). `gh project` needs the `project` scope: when it says the token lacks it, tell
  the owner to run `gh auth refresh -s project`, and ask about the board again after that (or
  none).
- `.claude/ap.json`: the answers of an earlier setup.
- `CLAUDE.md`, `README.md`, `package.json`, `Makefile`, `scripts/`, `.github/workflows/`: the
  project's check (tests, lint, build) and deploy commands, and the owner's name and language.
- The parts for `ap-check`: one part per folder that has its own tests and its own way to run
  them (a `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `pubspec.yaml`, a `tests/`
  folder with a runner). For each: its folder, the files outside it that its tests read (shared
  config, scripts its tests run), and its commands, from its CI job or its README. A project with
  one such folder (or none) has one part, at the root.

## 2. Ask

One short question at a time, with your suggestion from step 1 as the first answer. Closed
choices through AskUserQuestion. Only ask what step 1 could not settle.

Answers given in the arguments are taken as they are and not asked again: the key names of
`.claude/ap.json` with their values (`/ap:setup check="bash check.sh" deploy=none owner=Dana`).
`none` turns that part off.

1. The owner's name (texts say "Waiting for <owner>.") and the language to talk to them in, as a
   language code (`en`, `he`).
2. The branch pull requests go into.
3. The check: it runs every test and check of the project, exit 0 when all pass. It is the only
   gate before a merge, so it must be there: without it `/ap:run` does not start. Offer
   `ap-check` with the parts step 1 found first: show each part (its name, inputs, dir, and its
   `light` and `heavy` commands) and ask the owner to say yes, or to change one. A command goes
   in `light` when it is quick and needs little memory (lint, format, type checks, small tests),
   in `heavy` when it builds much or takes much memory (a big build, the slow tests); a part
   whose light steps should stop it before its heavy ones gets `light_first: true`. With
   `ap-check`, `check` is `"ap-check"` and the parts go in `check_parts` (the part "The project's
   settings" at the end). Or the project's own command, when it has one that it wants to keep:
   then `check` is that command and there are no `check_parts`.
   Then what a fresh checkout needs before the check can run (install the packages, fetch the
   tools: `npm ci`, `flutter pub get`), or none. The manager runs the check on each branch in a
   fresh folder (`ap-check-branch`), so this goes in `hooks.check_setup`, and one line in
   `.claude/ap/manager.md` says what it is for (step 5).
4. Deploy: a command that puts the main branch live (or none), and the site's address. A run
   deploys through `ap-deploy`, which runs the check first, so the deploy command need not check.
   It must deploy HEAD of the main checkout, the commit that was checked (also in
   `$AP_DEPLOY_COMMIT`), never fetch a newer one itself.
5. A GitHub board to add every new issue to (or none). `board.owner` is the GitHub account that
   holds the board (the part of `repo` before `/`, unless the board is elsewhere).
6. A message to the owner's phone when a run needs them or ends: a command that takes
   `--title <t> [--high] [--url <u>]` and the text on stdin (or none: the run prints it instead).
7. A cleanup command for leftover test runs and their temp files, `--older-than <m>` and
   `--min-free-gb <n>`, exit 3 when the disk is low (or none). It may print `can free: <how much>:
   <what to do>` for space only the owner can give back; a run then asks them at its start.
8. Previews the helpers start in their worktrees: the command that stops one in a worktree
   (`hooks.slot_release`) and the one that stops them all (`hooks.previews_clear`), or none.
9. `/ap:qa`, a sweep of the site at phone size with the project's own cases (yes for a site or a
   web app, else none): `parts.qa`, and the `qa` settings (`${CLAUDE_PLUGIN_ROOT}/docs/qa.md`): the
   cases folder (suggest `.claude/ap/qa`), the site to check (missing: `site`), the languages and
   the themes (`light,dark`; pairs `<the site's own>/<the phone's>` when the site has a theme of
   its own). When the folder is new, copy `${CLAUDE_PLUGIN_ROOT}/docs/qa-example/` into it (its
   `home.py` and `project.py`), and say the owner changes them to the project's screens. Say the
   one-time install: `pip install playwright psutil && python -m playwright install chromium
   webkit`. With Playwright there, `ap-qa --browsers chromium --only home` tries it once.
10. `/ap:phone-check` (yes when some fixes can only be seen on the owner's own phone: sound,
   location, a phone's browser, an app from the Home Screen; else none): `parts.phone_check`.
11. `/ap:bug-reports`, when users send reports (bugs or feature requests) from the product, or
   none: `parts.bug_reports`, and `hooks.reports`, a command of the project that lists, gets and
   marks them in the shape of "The reports hook" in `CONTRACT.md` of the plugin (`list`, `get <id>
   <folder>`, `mark <id> <state> <issue> <reason>`, `filed`). The project has none yet: say what it
   must do, and leave the part off until it is there. Then `bug_reports.trusted`: does every
   report come from the owner or people they trust? Yes: each report is treated as the owner's
   own (nothing is left out as "works as built"); set it back to no when strangers send reports.
12. Less waiting in a parallel run: `merge_batch` and `queue_per_slot`. Run `ap-check --suggest`
    (it only reads): it prints the facts (the checks before a merge in the check's log and how many
    did not pass; free memory, free disk, the size of one built worktree, how long a helper's check
    takes) and a line for each, `merge_batch: <n> (why)` and `queue_per_slot: <n> (why)`. Show the
    owner both numbers with their why, ask them to confirm or change each, and write both in
    `.claude/ap.json` (a missing key is 1 for both: the run as it was without them):
    - `merge_batch`: how many approved pull requests are merged together and checked once (1: one
      at a time, each in its helper's merge turn). It suggests 1 when the checks before a merge
      fail often (1 in 10 or more), else 3.
    - `queue_per_slot`: how many issues one slot may have open at a time, each with its own
      helper in its own worktree, so a fresh helper works on the next while the first waits for a
      check or a review. It
      suggests 1 when the disk or memory is short, 3 when both are plenty and the check is long,
      else 2.
    Say how to tell later whether to change them: `ap-check --stats` after a run or two. A slot
    often idle while its helper waits: raise `queue_per_slot`; fixes that come back late, or the
    disk check that stops helpers: lower it. Batches that often fail: lower `merge_batch`.
    With a project check that is not `ap-check`, there is no log: the suggestions read only the
    computer.
13. A run on a schedule (for example every night at 2:00, with `X2 stop-in 300`), or none. It is
   not in `.claude/ap.json`: it is this computer's. With a yes, after step 12, do what
   `/ap:schedule <when> <run arguments>` does (`${CLAUDE_PLUGIN_ROOT}/skills/schedule/SKILL.md`).

## 3. Write `.claude/ap.json`

Only the keys that have a value (a missing key is a part that is off): a part that is off is left
out, never written as `false` (`parts` only names the parts that are on, or is left out). Show it
to the owner before you write it.

`.claude/ap.json` and the folder `.claude/ap/` (step 5) are meant to be committed: everyone who
works on the project, and every helper in its worktree, reads the same settings. Say so to the
owner.

## 3b. `.gitignore`

A run makes files under `.claude/` that must never be committed: the helpers' worktrees and the
local settings. Add each of these lines to the project's `.gitignore` when it is not there yet
(make the file when there is none), and say which you added:

```
.claude/worktrees/
.claude/settings.local.json
.ap-reports/
```

(`.ap-reports/` holds the users' reports of `/ap:bug-reports`, which can hold their data.)

Never add `.claude/` as a whole: `.claude/ap.json` and `.claude/ap/` must stay in git.

When `git add` warns about line endings on every file (`LF will be replaced by CRLF`, on
Windows) and the project has no `.gitattributes`, offer one with the line `* text=auto eol=lf`.
Add it only when the owner says yes.

## 4. The labels

Make the labels the commands use that the repository does not have yet: `gh label list` first,
then for each missing one, `gh label create "<name>" --color <colour> --description "<description>"`,
with the values of this table. Never delete or rename a label that is there, and never change its
colour or description. Say which ones you made.

| Name | Colour | Description |
|---|---|---|
| `type:bug` | `d73a4a` | Something is broken |
| `type:feature` | `a2eeef` | Something new |
| `type:test` | `0e8a16` | Tests only |
| `type:chore` | `cfd3d7` | Cleanup, tooling, docs |
| `type:decision` | `d4c5f9` | A choice the owner makes |
| `P0` | `b60205` | Do first: main is red or a deploy failed |
| `P1` | `d93f0b` | High priority |
| `P2` | `fbca04` | Normal priority |
| `P3` | `c2e0c6` | Low priority |
| `size:S` | `c5def5` | A small change in a few files |
| `size:M` | `7aa6dc` | One part of the product |
| `size:L` | `1d76db` | Several parts; the planner may split it |
| `area:tooling` | `5319e7` | Scripts, checks and the run's rules |
| `status:in-progress` | `0052cc` | An agent works on it now |
| `status:waiting-for-owner` | `e99695` | Waits for the owner's answer |
| `status:needs-decision` | `f9d0c4` | Needs a decision before work starts |
| `status:blocked` | `000000` | Cannot go on until something outside changes |
| `status:later` | `ededed` | The owner put it off |
| `tracking` | `006b75` | Holds a list of other issues |
| `inbox` | `fef2c0` | A raw note, not sorted yet |
| `parallel-safe` | `bfdadc` | Can run beside an issue of the same area |
| `status:phone-check` | `c2e0c6` | Merged; only the owner's real phone can check it |
| `status:triage` | `fbca04` | From a user's report: look again before the work |
| `user-report` | `bfd4f2` | Came from a user's report |
| `not-a-bug` | `ffffff` | Closed: not a bug |
| `as-intended` | `ffffff` | Closed: it works as it was made to |

## 5. The project's own parts of the briefs

The helpers, the reviewer and the manager get the plugin's briefs. What only this project needs
(how to see a change on screen, ports, the build, the design rules) goes in
`.claude/ap/helper.md`, `.claude/ap/reviewer.md`, `.claude/ap/manager.md`. When none is there,
write a short `helper.md` from what step 1 found (how to build and test one part, where things
live), and add `briefs` to `ap.json`. With a `hooks.check_setup`, add to `manager.md` (make it
when it is not there): `A fresh checkout needs <the setup command> before the check;
ap-check-branch runs it (hooks.check_setup).` Never more than the project says: leave out what you are not
sure of. When these files are there already (a second setup), read each against the new answers:
a line that names the old check, branch or parts is changed to the new one.

## 6. CLAUDE.md

Add a short part (or update it when it is there), between the lines `<!-- ap:start -->` and
`<!-- ap:end -->`. Every agent reads `CLAUDE.md`, but not the plugin's docs, so the part carries
the core rules themselves, short, with the owner's name filled in:

- Every task, decision, finding and question goes on a GitHub issue first, then in the chat. The
  chat is not the record: the owner may read only GitHub.
- A question for the owner: the label `status:waiting-for-owner`, and a comment that starts with
  **Waiting for <owner>.**
- Every issue, title, comment and pull request text is in simple English: short sentences, common
  words, bullets.
- When the owner writes "inbox: X", run `/ap:inbox X` (it keeps the note as an issue, word for
  word), then go back to the task.

Then the commands and what each is for:

- `/ap:run` (away mode: helpers take the open issues to merged pull requests), `/ap:bugs`,
  `/ap:features`, `/ap:tests`, `/ap:chores` (one kind only), `X<N>` for N at once.
- `/ap:stop`, `/ap:stopnow`, `/ap:stop-in <minutes>`, `/ap:stop-after <n>`.
- `/ap:waiting`, `/ap:waiting-all` (the owner's questions, one at a time), `/ap:inbox`, `/ap:report`.
- `/ap:status` (what goes on now), `/ap:plan` (what a run would take, and how many at once),
  `/ap:schedule` (a run at a set time).
- The parts that are on: `/ap:qa` (a sweep of the site at phone size), `/ap:phone-check` (the
  fixes only the owner's phone can show), `/ap:bug-reports` (the users' reports, judged and filed).
- The rules for issues: `docs/issue_writing.md` and `docs/record_keeping.md` of the ap plugin.
  Name them that way, never by the install path (it changes with each update).

No CLAUDE.md: make one with only this part.

## 7. Permissions

An away run must never stop for "allow this command?": nobody is there to answer, and the run
waits for hours. A skill's `allowed-tools` reaches only the manager. The helpers, the planner, the
reviewer and the retro agent are `general-purpose` agents: they get no skill's rules, and they
need git, gh, Edit, Write, Monitor and more. So tell the owner plainly that an away run needs one
of these:

- the session in a mode that does not stop for prompts: auto mode, or bypass permissions
  (`claude --permission-mode bypassPermissions` in a terminal); or
- the full allow list below in the project's `.claude/settings.json`.

A plugin cannot add permission rules, so print the full list for the owner to add under
`permissions.allow`, and say why each part is needed. Never change a settings file yourself.

```json
"permissions": {
  "allow": [
    "Bash(git:*)", "Bash(gh:*)",
    "Bash(ap-config:*)", "Bash(ap-git-sync:*)", "Bash(ap-run:*)", "Bash(ap-notify:*)", "Bash(ap-background:*)",
    "Bash(ap-check-branch:*)", "Bash(ap-check:*)", "Bash(ap-batch:*)", "Bash(ap-deploy:*)", "Bash(ap-status:*)", "Bash(ap-list:*)", "Bash(ap-brief:*)", "Bash(ap-schedule:*)",
    "Bash(ap-qa:*)", "Bash(ap-bug-reports:*)",
    "Bash(<check>:*)", "Bash(<deploy>:*)", "Bash(<each hook>:*)",
    "Read", "Edit", "Write", "Glob", "Grep",
    "Monitor", "Agent", "SendMessage", "TaskStop"
  ]
}
```

- `git`, `gh`: branches, commits, issues, pull requests, merges.
- The `ap-*` scripts: the run, git with the network, the phone message, background commands,
  `ap-check-branch` (the manager runs the check too, on every branch before its merge, in a fresh
  folder), `ap-check` (the check, when `check` is `ap-check`), `ap-batch` (merges in batches,
  `merge_batch`) and `ap-deploy` (the deploy: the check, then `deploy`), `ap-status`
  (`/ap:status`), `ap-list` (the run's list, and `/ap:plan`), `ap-brief` (each agent's brief), `ap-schedule` (`/ap:schedule`: a run
  at a set time), `ap-qa` (`/ap:qa`, and a run after a deploy), `ap-bug-reports`
  (`/ap:bug-reports`, and a run before its planner). Leave out the ones of a part that is off.
- The project's own commands from `ap.json`, one line each, with the real command filled in:
  `check` when it is the project's own (the helpers run it, and the manager on main), the
  `light` and `heavy` commands of `check_parts` (ap-check runs them; a helper may run one alone),
  `deploy`, and each hook (for example `Bash(bash scripts/check.sh:*)`). Leave out a part that is
  off.
- `Read`, `Edit`, `Write`, `Glob`, `Grep`: the helpers change the code.
- `Monitor`: a helper waits for its background check with it.
- `Agent`, `SendMessage`, `TaskStop`: the manager starts, talks to and stops the agents.

The project's own build and test tools (`npm`, `cargo`, ...) that helpers run outside the check
need their lines too; name the ones step 1 found.

And the lines that turn the plugin on for everyone who opens the project (they go in the same file;
the owner adds them):

```json
"extraKnownMarketplaces": {
  "claude-autopilot": { "source": { "source": "github", "repo": "harel12381/claude-autopilot-public" } }
},
"enabledPlugins": { "ap@claude-autopilot": true }
```

## 8. The end

One short summary in the owner's language: what was found, what was written, the labels made,
what each part does now (on, or off and how to turn it on), and the lines left for the owner to add.
Say again that an away run needs auto mode, bypass permissions, or the full allow list (step 7).
Then: "Try it: open an issue, then `/ap:run <number>`."

## The project's settings

`.claude/ap.json`:

```json
{
  "repo": "owner/name",
  "owner": "Dana",
  "chat_language": "en",
  "main_branch": "main",
  "board": { "owner": "owner", "number": 1 },
  "check": "ap-check",
  "check_parts": [
    { "name": "web", "inputs": ["web", "package-lock.json"], "dir": "web",
      "light": "npm run lint", "heavy": "npm test", "light_first": true },
    { "name": "api", "inputs": ["api"], "dir": "api", "light": "go vet ./... && go test ./..." }
  ],
  "check_options": { "light_min_mb": 3000, "step_limit_min": 45 },
  "merge_batch": 3,
  "queue_per_slot": 2,
  "background_wrap": ["npm run", "python"],
  "deploy": "npm run deploy",
  "site": "https://example.org",
  "parts": { "deploy": true, "qa": true, "phone_check": true, "bug_reports": true },
  "qa": { "cases": ".claude/ap/qa", "langs": ["en", "he"], "themes": ["light", "dark"] },
  "bug_reports": { "trusted": true },
  "hooks": { "notify": "...", "cleanup": "...", "slot_release": "...", "previews_clear": "...", "check_setup": "npm ci",
             "reports": "bash scripts/reports.sh" },
  "briefs": { "helper": ".claude/ap/helper.md", "reviewer": ".claude/ap/reviewer.md", "manager": ".claude/ap/manager.md" }
}
```

`repo`, `owner`, `main_branch` and `check` must be there for `/ap:run`. `parts.qa`,
`parts.phone_check` and `parts.bug_reports` turn on `/ap:qa` (with `qa.cases`), `/ap:phone-check`
and `/ap:bug-reports` (with `hooks.reports`); `bug_reports.trusted` is `true` while every report is
the owner's own. `chat_language` is a
language code (`en`, `he`). Everything else may be missing: that part is off.

`check_parts` (for `check: "ap-check"`): each part has a `name` (letters, digits, `_ . -`),
`inputs` (the files and folders, from the repository's root, whose change checks the part again;
a part for the whole project, at the root, takes `["."]`: a list of its files would miss a file
added later),
`dir` (where its commands run; default the root), and a `light` and a `heavy` command (either may
be missing). Optional: `light_first`, `version` (a number: change it to check the part again),
`retry` (`{ "when": "<a grep -E pattern on its log>", "run": "<a command>" }`: a failure that is
not the code's, checked another way; `"heavy": true` runs that command under the heavy lock). `check_options`: `light_min_mb` (the free memory below which
a run takes the heavy lock for all its steps) and `step_limit_min` (a step that runs longer is
stopped and fails). `ap-check --list` shows the parts.

`merge_batch` and `queue_per_slot` (missing: 1 for both): step 2, question 12. They count only
in a parallel run (`X2` and up). `background_wrap`: the commands a background command may start
only through `ap-background` (missing: the hook's own list; `[]`: none); setup does not ask it.
