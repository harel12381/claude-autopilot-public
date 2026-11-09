# The contract between the plugin's parts

Every skill, brief and script of the `ap` plugin keeps to this file. Change it first, then the parts.

## Folders

```
.claude-plugin/marketplace.json   the marketplace (name: claude-autopilot)
plugins/ap/                       the plugin; ${CLAUDE_PLUGIN_ROOT} is this folder
  .claude-plugin/plugin.json      name: ap
  skills/<name>/SKILL.md          one skill per command: /ap:<name>
  briefs/<name>.md                the briefs a run gives its agents (helper, planner, reviewer, retro), and
                                  the read-only ones of /ap:bug-reports (bug-triage, why-missed)
  agents/reader.md                the plugin's one agent: Read, Grep and Glob only (ap:reader), for the
                                  briefs that read a stranger's text
  bin/ap-*                        the scripts; on the shell's PATH while the plugin is on
  lib/*.sh                        what the scripts share (sourced, never run alone)
  lib/issues.py                   what ap-list and ap-status share about the open issues, and the
                                  run's list itself (run_list: ap-list, /ap:plan and /ap:status's "ready")
  lib/list.py, lib/status.py      the list of ap-list, the report of ap-status (each run through
                                  ap_python of lib/config.sh, after lib/issues.py)
  lib/brief.py                    the brief of one agent of a run, for ap-brief
  lib/background-hook.py          the decision of ap-background-hook
  lib/qa/                         the driver of ap-qa (Python, Playwright): qa.py runs the project's cases
  lib/bug_reports.py              what ap-bug-reports checks and builds: verdicts, issues, why-missed comments
  hooks/hooks.json                the plugin's hooks: ap-background-hook before each Bash command
  docs/                           how issues are written, how a run works; qa.md: the /ap:qa cases'
                                  interface, and qa-example/ (an example case and project.py)
tests/                            the scripts' tests (bash tests/run.sh runs them all); fake-playwright/: a
                                  Playwright with no browser, for qa-test.sh
check.sh                          the repository's own check: every test, shellcheck when it is there
```

## How a skill runs a script

By its `bin/` name, never by a path: `ap-git-sync push`, `ap-run start`. The name is on the PATH
while the plugin is on, the same in every project and after every update, so one permission rule
covers it: `Bash(ap-git-sync:*)`. A script finds its `lib/` with
`$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib`.

A file of the plugin (a brief, a doc) is named in a skill as `${CLAUDE_PLUGIN_ROOT}/briefs/helper.md`:
Claude Code fills in the path inside the skill's text. It is not set in the shell.

## The project's settings: `.claude/ap.json`

Written by `/ap:setup`; read by `ap-config` and by the skills (the manager reads it at the start).

```json
{
  "repo": "owner/name",
  "owner": "Dana",
  "chat_language": "he",
  "main_branch": "main",
  "board": { "owner": "owner", "number": 1 },
  "check": "ap-check",
  "check_parts": [
    { "name": "web", "inputs": ["web", "package-lock.json"], "dir": "web",
      "light": "npm run lint", "heavy": "npm test", "light_first": true, "version": 1,
      "retry": { "when": "ENOSPC", "run": "npm test -- --runInBand", "heavy": true } },
    { "name": "api", "inputs": ["api"], "dir": "api", "light": "go vet ./... && go test ./..." }
  ],
  "check_options": { "light_min_mb": 3000, "step_limit_min": 45 },
  "merge_batch": 3,
  "queue_per_slot": 2,
  "background_wrap": ["npm run", "python"],
  "deploy": "bash scripts/deploy.sh",
  "site": "https://example.org",
  "parts": { "deploy": true, "qa": true, "phone_check": true, "bug_reports": true },
  "qa": { "cases": ".claude/ap/qa", "url": "https://example.org", "langs": ["en", "he"],
          "themes": ["light", "dark"], "browsers": ["chromium", "webkit"], "device": "iPhone 13" },
  "bug_reports": { "trusted": true },
  "hooks": {
    "reports": "bash scripts/reports.sh",
    "notify": "bash scripts/phone-message.sh",
    "cleanup": "bash scripts/cleanup.sh",
    "slot_release": "bash scripts/preview.sh stop",
    "previews_clear": "bash scripts/preview.sh stop-all",
    "check_setup": "npm ci"
  },
  "briefs": {
    "helper": ".claude/ap/helper.md",
    "reviewer": ".claude/ap/reviewer.md",
    "manager": ".claude/ap/manager.md"
  }
}
```

- `repo`, `owner` and `main_branch` must be there, and `check` too for `/ap:run` (and the kind
  skills): a run never merges without a check. Everything else may be missing or `null`: the part
  that needs it is off and says so in one line, never fails half way.
- `owner`: the name the texts use ("Waiting for Dana."). `chat_language`: the language the
  commands talk to the owner in, as a language code (`en`, `he`); issues and code stay in English.
- `check`: the project's self-check, the only gate before a merge. Exit 0 = passed. Either
  `ap-check` (the parts below) or the project's own command.
- `check_parts`: the parts `ap-check` runs, side by side. Each: `name` (letters, digits, `_ . -`),
  `inputs` (files and folders relative to the repository's root: a change in one checks the part
  again), `dir` (where its commands run, default the root), `light` and `heavy` (commands; either
  may be missing, not both), optional `light_first` (true: the light steps first, and a failure
  there skips the heavy ones), `version` (a number; a new one checks the part again), `retry`
  (`when`: a `grep -E` pattern; a step that fails with a log that matches it runs `run` once in
  its place, and that result counts; with `"heavy": true` that command runs under the heavy
  lock). `ap-check` reads them from the checked tree's own
  `.claude/ap.json` (a branch is checked with the parts it has), or the main checkout's when the
  tree has none.
- `check_options`: `light_min_mb` (3000: with less memory free, a run takes the heavy lock for all
  its steps) and `step_limit_min` (45: a step that runs longer is stopped and fails; 0: no limit).
- `merge_batch` (a parallel run only; missing: 1): 1, each approved pull request is merged in its
  helper's merge turn, one at a time, with the check again after the latest main is merged in.
  N above 1: up to N approved pull requests whose `ap-check-branch` passed are merged together on
  the latest main by `ap-batch check`, checked once, and merged into main by `ap-batch merge`; when
  the batch's check fails, the first one that breaks it is found by halves and goes back to its
  helper; one that conflicts goes back to its helper's merge turn.
- `queue_per_slot` (a parallel run only; missing: 1, no queue): how many issues one slot may have open at
  a time, each with its own fresh helper, on its own branch in its own worktree of the slot
  (`ap-<s>`, then `ap-<s>b`, `ap-<s>c`). The manager starts the next one when a helper of the slot
  reports that it waits; it comes only from another `area:*` than the slot's open issues, with
  `files` lines that do not overlap. A fix to an open issue goes to its own helper, first.
  `/ap:setup` writes both, with the numbers `ap-check --suggest` gives (2 for the queue unless the
  disk or memory is short); a missing key keeps the run as it was without them.
- `background_wrap`: the commands (their first words) that a background Bash command may start only
  through `ap-background`; `ap-background-hook` refuses the others. Missing: its own list (dev
  servers, `python`, `node`, `go run`, `flutter run`, ...); `[]`: the hook refuses nothing.
- `deploy`: runs the project's deploy; `ap-deploy` runs the check before it, so it need not check.
  It must deploy HEAD of the main checkout, the commit that was checked (`ap-deploy` sets it in
  `$AP_DEPLOY_COMMIT`), never a newer `origin/<main_branch>` that it fetches itself.
  `site`: what the closing comments name.
- `board`: a GitHub project board every new issue is added to (`gh project item-add`).
  `board.owner` is a GitHub account (usually the part of `repo` before `/`), not the `owner` name.
  `gh project` needs the `project` scope (`gh auth refresh -s project`). A board command that
  fails in a run is one line on the run issue, never a stop.
- `hooks.notify`: sends one message to the owner's phone. Called as
  `<cmd> --title <title> [--high] [--url <url>]`, with the text on stdin. Missing: `ap-notify` only
  prints the message.
- `hooks.cleanup`: stops leftover test runs and deletes their temp files. Called with
  `[--older-than <minutes>] [--min-free-gb <n>]`. Exit 3 = the disk is low. A line it prints that
  starts with `can free:` names space only the owner can give back (a step that needs an admin
  shell, or a tool to stop first): `can free: about 8 GB: compact Docker's disk file (Docker
  stopped, an admin shell)`. Missing: nothing to do.
- `hooks.check_setup`: what a fresh checkout needs before `check` can run (install packages).
  `ap-check-branch` runs it in its fresh folder, before the check. Missing: the check runs alone.
- `hooks.slot_release`: run inside a slot worktree before it is removed (stop its preview).
  `hooks.previews_clear`: stops every slot preview. Missing: nothing to do.
- `briefs.*`: the project's own part of each brief, added after the plugin's brief. A missing file
  adds nothing.
- `parts.qa`, `parts.phone_check`, `parts.bug_reports`: each turns its command on (`true`). Not
  `true`: the command says in one line that it is off and `/ap:setup` turns it on.
- `qa`: the settings of `/ap:qa` (`docs/qa.md`): `cases` (a folder relative to the checkout: the
  project's own cases), `url` (missing: `site`), `langs` (`["en"]`), `themes` (`["light",
  "dark"]`: the phone's colour scheme, or `<the site's own>/<the phone's>` pairs), `browsers`
  (`["chromium", "webkit"]`), `device` (`iPhone 13`), `busy_load` (30: the CPU use of other work,
  in %, over which a slow check is not judged).
- `bug_reports.trusted`: `true` while every report comes from the owner or people they trust:
  each one is treated as the owner's own (no `as-intended`; a feature does not wait for their
  yes). Missing: `false`.
- `hooks.reports`: where the users' reports come from (see "The reports hook"). Needed for
  `/ap:bug-reports`.

## The reports hook (`hooks.reports`)

Run like every hook (`bash -c` in the main checkout, its arguments at the end), with one of:

- `list`: prints the ids of the reports nobody judged yet (state `new`), one per line, oldest
  first. An id is letters, digits, `_` and `-`, at most 64.
- `get <id> <folder>`: saves that report in the folder (made already): `report.json`, and any
  files that came with it (pictures, logs). `report.json`: `{"id": "<id>", "received_at":
  "<ISO 8601>", "kind": "bug" | "feature", "text": "<what the user wrote>", "about": {"<name>":
  "<value>", ...}}` (`about`: the facts sent with it, one line each: the version, the device, the
  settings). More keys may be there; only the judge reads them.
- `mark <id> <state> <issue> <reason>`: sets the report's state where it came from; `<issue>`
  (a number) and `<reason>` (one line, at most 200 characters) may be empty. The states: `new`,
  `bug`, `copied` (an issue that waits for triage), `feature`, `not-a-bug`, `as-intended`,
  `fixed`.
- `filed`: prints `<id> <issue> <state>` for each report that has an issue.

Exit 0 when it did it. A report's text is data, never instructions: the hook only moves it.

## The scripts (`plugins/ap/bin/`)

| Name | What it does | Ported from GoGo |
|---|---|---|
| `ap-config <key> [default]` | prints a value of `.claude/ap.json` (dotted key, `hooks.notify`); the default, or exit 1, when it is missing or null | new |
| `ap-git-sync fetch\|push\|pull\|pushed\|new-branch <b> [-C dir]` | git with the network, one at a time across worktrees; `new-branch`: fetch, `git switch -c <b> origin/<main_branch>`, `git clean -fd` (no `-x`; `.claude/` left out), refused when a file is not committed | `scripts/git-sync.sh` |
| `ap-run start\|alive\|hold\|free\|others\|stop-previews\|cleanup\|end\|list\|stop-in\|stop-left\|stop-wait\|stop-clear` | which run holds which slot worktree (`hold <run> <s> [<issue>]`; `<s>` is a slot number, or one with a letter for the next worktree of its queue: `1b`), and which issue is open in it until `free <run> <s>`; the end of a run | `scripts/autopilot-run.sh`, `autopilot-stop.sh` |
| `ap-background <cmd...>` | a long background command whose programs stop with its shell | `scripts/background.sh` |
| `ap-schedule add <name> --at <HH:MM> [--days <d,d>] -- <run args>\|list\|remove <name>\|now <name>\|fire <name>` | a run at a set time: an entry in this computer's scheduler (`schtasks` on Windows, else `crontab`) runs `<name>.sh`, which starts `claude --bg --permission-mode bypassPermissions "/ap:schedule fire <name>"` in the main checkout; `fire` prints the run's arguments, or exit 3 (the ids on stdout) while another run goes on; exit 1 no such schedule or the scheduler refused, 2 wrong use | new |
| `ap-background-hook` | the PreToolUse hook of `hooks/hooks.json`: reads the hook's JSON on stdin; in a project with `.claude/ap.json`, exit 2 (refused, the words say to add `ap-background`) for a Bash command with `run_in_background` that starts a command of `background_wrap` without it; else exit 0, also when no Python runs or the input cannot be read | new |
| `ap-notify [--high] [--hold <m>] <title> <text> [<url>]` | a message to the owner's phone through `hooks.notify`, with the hold | `scripts/notify.sh` |
| `ap-check [parts...] [--force] [--list] [--stats [since]] [--suggest]` | the steps of `check_parts`, side by side, each part skipped when its inputs passed before; exit 0 every part passed, 1 one failed, 2 it could not run. `--stats`: the log's summary, with the time the batches and the queues saved; `--suggest`: the `merge_batch` and `queue_per_slot` that `/ap:setup` suggests (`lib/suggest.sh`) | `scripts/check.sh`, `lib/check-parts.sh`, `lib/check-log.sh` |
| `ap-deploy` | in the main checkout, on `main_branch`, clean and equal to `origin/<main_branch>` (after `ap-git-sync fetch`): `ap-check` (or `check` when there are no `check_parts`), then `deploy` with `AP_DEPLOY_COMMIT` (it refuses when origin moved during the check), holding the deploy lock while `deploy` runs; exit 0 deployed or no `deploy`, 2 could not run, 3 refused, 4 fetch failed, 5 check failed, 6 deploy failed | `scripts/deploy.sh` |
| `ap-list [--json [--parallel <N>] [--stop-after <N>] [--stop-in <X>]] [--label <l>[,<l>...]]... [--not <l>]... [--leave-out <l>]... [--run <id>] [<N>...]` | only reads: the run's list of issues, in the order the run takes them: first the issues a stop left in the middle (`status:in-progress`, last comment starts with `**Stopped in the middle.**`) while no other run goes on, then the approved look-back issues (`[retro]` in the title, a comment that starts with `**Decided**`: a kind or `--label` does not leave them out, a `--not` can), then `P0` to `P3`; an issue with an open pull request or a branch on origin named for it is left out (`left out: #N (open PR #M)`, `(branch <name>)`), unless named or stopped in the middle; every `--label` is needed (`a,b`: either one), `--not` leaves out, every `P0` is kept; with numbers, only those, in that order; a group of small issues (up to 3 `size:S` of one `area:*`, next to each other) marked `(one helper with #N)`; then `left out: #N (why)` lines and the label limit; with `--json`, the plan instead (`/ap:plan`): `order`, `helpers`, `rounds` (which helpers could run at the same time with `--parallel`), `stop_after`, `stop_in`, `left_out` (every issue left out, with why), `label_limit`; exit 0 a list, 2 it could not run | new |
| `ap-status [--json] [--since <date>] [--label <l>[,<l>...]]... [--not <l>]... [--max <n>]` | only reads: the runs that go on (their stop, slots, run issue), each slot worktree's branch and work not committed, the open pull requests, the open issues in groups (waiting for the owner, a phone check, in progress, blocked, ready in the run's order with the label limit of `ap-list`, inbox), and what was opened and solved since the run started (not the run issues); one `gh` call per kind of list, all at once; exit 0 a report, 2 it could not run | new |
| `ap-qa [--url <u>] [--browsers <b,b>] [--langs <l,l>] [--themes <t,t>] [--only <case,case>] [--device <d>] [--out <dir>] [--deploy-wait <min>] [--busy-load <%>]` | the `/ap:qa` sweep: the project's cases (`qa.cases`, `docs/qa.md`) on its site with Playwright at phone size, per browser, language and theme; a browser that cannot start is a failed `launch` row and the rest goes on; waits while `ap-deploy` holds the deploy lock, and a check that failed beside a deploy, or a slow one on a busy computer, is not judged (`TOLD`); the pictures and `index.html` in `--out`; exit 0 passed, 1 a check failed, 2 could not run, 3 off | `.claude/commands/qa.md`, `scripts/qa/` (the driver; the cases stay the project's) |
| `ap-bug-reports pending\|file <id>\|sync\|why-pending\|found <N>\|why <N>\|mark <id> <state> [#<N>] [<reason>]\|get <id>\|folder` | the users' reports through `hooks.reports`: saves the new ones (and the open issues' titles), files a judged one from its `verdict.md` (an issue, a comment on a duplicate, or only a state), posts the why-missed answer, follows closed issues back to the reports; exit 0 done, 1 a step failed or an answer was refused, 2 wrong use, 3 off | `scripts/bug-reports.sh`, `scripts/bug_report_issue.py` |
| `ap-batch check <run> <branch>...\|merge <run>` | merges in batches (`merge_batch`): `check` reads the commits of `origin/<main_branch>` and each `origin/<branch>` once, merges those commits in the worktree `check-batch-<run>`, runs `hooks.check_setup` and `check` once, and when it fails, finds by halves the first branch that breaks it (a check that could not run, 90 or 91, or 2 of `ap-check`, is no break: no halves); one line per branch (`passed`, `conflict`, `breaks`, `later`, `missing`); exit 0 passed, 1 one breaks it, 3 nothing to check, 4 main fails the check, 2 wrong use, 90 it could not run, 91 `hooks.check_setup` failed. `merge` fetches, merges nothing when main is no longer the commit checked, else squash-merges the passed ones in order (`--match-head-commit` of the commit merged into the batch), then checks that main has the checked tree; exit 0 all merged, 1 nothing merged, 3 something merged but main is not the checked tree (check main at once), 4 main moved since the check, 90 no batch that passed or its first fetch failed (nothing merged, the batch kept) | new |
| `ap-check-branch <branch>` | `hooks.check_setup`, then `check` (both from the branch's own `.claude/ap.json`, else main's), on `origin/<branch>` in a fresh worktree that it removes after; the check's exit code, or its own, out of the checks' range: 90 it could not run (no `check`, no `origin/<branch>`, no worktree, a left folder still in use), 91 `hooks.check_setup` failed | new |
| `ap-brief helper\|planner\|reviewer\|retro --run <R> [--n "<N>..."] [--pr <P>] [--slot <s>] [--worktree ap-<s>b] [--date <d>] [--scratchpad <dir>] [--note <t>]` | the brief of one agent of a run: the plugin's brief, the project's `briefs.<name>`, every fill-in word filled; writes `<common .git>/ap-autopilot/briefs/<name>-<run>-<issue or pr>.md` and prints its path; a word it cannot fill is an error, and nothing is written; exit 0 written, 2 an error | new |

Files they keep: in the repository's common `.git` folder, under `ap-autopilot/` (runs, slots,
the issue open in each slot worktree, stops, the batch that passed: `batch-<run>`), `ap-git.lock`, `ap-notify.*`, and `ap-check`'s: `ap-check-cache/` (one empty file per
part that passed, named `<part>-<hash>`), `ap-check.lock` (the heavy steps), `ap-check-<part>.lock`,
`ap-check-log.tsv` (one line per part of every run; its fields: `lib/check-log.sh`),
`ap-deploy.lock` (held by `ap-deploy` while the deploy command runs; `ap-qa` waits for it) and
`ap-deploy-times` (one line `<start> <end>` per deploy), and
`ap-schedule/` (`<name>.conf`, `<name>.sh`, `<name>.log`: this computer's schedules). `ap-bug-reports` keeps the reports in `<main checkout>/.ap-reports/` (one folder per report,
`issue-<N>/` per filed bug, `open-issues.txt`), which must be in `.gitignore`: it can hold a
user's data. Slot worktrees: `<main checkout>/.claude/worktrees/ap-<s>` (and `ap-<s>b`, `ap-<s>c` of a queue);
the check's worktrees: `<main checkout>/.claude/worktrees/check-<branch>` (a `/` becomes `-`), and
`check-batch-<run>` of `ap-batch`.
`ap-check-branch` removes a left one before it starts, and `ap-run end` removes them when no other
run goes on.

More of how they behave:
- They need bash 5 or newer (on macOS: `brew install bash`), git 2.31 or newer, and Python 3
  (`python3` or `python`) to read `.claude/ap.json`; they say so clearly when one is missing.
- `ap-config` exits 2 (not 1) when `.claude/ap.json` is not valid JSON, no Python runs, or this is
  not a git checkout, also when a default is given: a broken file never looks like a missing setting.
- A hook is run with `bash -c` in the main checkout (`slot_release`: in the slot worktree), with
  its arguments added at the end of the command.
- `ap-git-sync push` never pushes `main_branch`, `main` or `master`, and refuses when
  `.claude/ap.json` cannot be read.

## The skills (`plugins/ap/skills/`)

| Skill | Today in GoGo |
|---|---|
| `run` | `.claude/commands/autopilot.md` |
| `bugs`, `features`, `tests`, `chores` | `ap-bugs.md`, ... |
| `stop`, `stopnow`, `stop-in`, `stop-after` | `stop.md`, ... |
| `waiting`, `waiting-all` | `waiting.md`, `waiting-all.md` |
| `inbox` | `inbox.md` (with `docs/inbox.md`) |
| `report` | `report.md` |
| `setup` | new |
| `status` | new (it only reads; its `allowed-tools`: only `ap-status`, `ap-config` and Read) |
| `plan` | new (it only reads, like `status`: only `ap-list`, `ap-config` and Read; it shows `ap-list --json`, the plan of the list step 2 of `run` takes) |
| `schedule` | new (its scheduled session does the run, so its `allowed-tools` has every tool of `run`, and `ap-schedule`) |

| `qa` | `qa.md` (the driver is `ap-qa`; the project keeps its own cases) |
| `phone-check` | `phone-check.md` |
| `bug-reports` | `bug-reports.md`, with the agents `bug-triage.md` and `why-missed.md` (now briefs, given to `ap:reader`) |

## The labels

The skills and briefs use these labels; `/ap:setup` makes the ones that are missing:
`type:bug`, `type:feature`, `type:test`, `type:chore`, `type:decision`; `P0`, `P1`, `P2`, `P3`;
`size:S`, `size:M`, `size:L`; `area:tooling` (other `area:*` labels are the project's own);
`status:in-progress`, `status:waiting-for-owner`, `status:needs-decision`, `status:blocked`,
`status:later`, `status:phone-check`, `status:triage`; `tracking`, `inbox`, `parallel-safe`,
`user-report`, `not-a-bug`, `as-intended`. The owner's name is only in texts
("Waiting for Dana."), never in a label. Their colours and descriptions: the table in "The labels"
of `skills/setup/SKILL.md` (`tests/skills-test.sh` checks that it has the same names as this list).

## The briefs (`plugins/ap/briefs/`)

The manager runs `ap-brief <name>` (`plugins/ap/bin/ap-brief`, `lib/brief.py`): it reads
`briefs/<name>.md`, adds the file `briefs.<name>` names (when it is there), fills in these words,
writes the brief to `<common .git>/ap-autopilot/briefs/`, and prints its path. A word it cannot fill
is an error. The manager gives a `general-purpose` agent only that path to read. The words:
`<REPO>`, `<OWNER>`, `<MAIN>`, `<CHECK>` (from `ap.json`), `<DOCS>` and `<PLUGIN>` (full paths of
the plugin's `docs/` and root), `<CHECKOUT>` (the full path of the main checkout), `<SCRATCHPAD>`
(the manager's scratchpad folder, `--scratchpad`; else `<common .git>/ap-autopilot/tmp`), `<BOARD>`,
`<CLEANUP>` (`hooks.cleanup`, or "skip"), `<PROJECT_BRIEFS>`, `<RUN>`, `<N>`, `<LIST>`, `<PR>`,
`<DATE>` (`--date`, else today).

- Issue and pull request numbers: `<N>` is the agent's issue numbers without `#`, for commands
  only (a group: `81 84 90`); the briefs run one command per issue. `<LIST>` is the same numbers
  with `#`, for texts (`#81 #84 #90`; in the planner brief, the run's whole list). `<RUN>` and
  `<PR>` are numbers without `#`: the texts write `#<RUN>`, `#<PR>`.
- `<BOARD>` stands alone on one line of each brief. With a board, it is the `gh project item-add`
  step; with none, `ap-brief` drops that whole line.
- `<PR>` is filled in only in the reviewer brief; elsewhere the helper fills in its own pull
  request.

`/ap:bug-reports` gives `briefs/bug-triage.md` and `briefs/why-missed.md` to the plugin's
`reader` agent (`subagent_type: ap:reader`: Read, Grep and Glob only), never to an agent that can
do more. They have no fill-in words: the message gives the report or issue and its files.

Helper results: `merged`, `needs-owner`, `needs #M`, `blocked`, `nothing-to-do`, `failed`, `stopped`,
`ready #<PR>`. The manager's messages to a helper: `MERGE TURN`, `REVIEW CHANGES`, `NO MERGE`,
`BATCH MERGED #<PR>`, `STOP`, `STOPNOW`. A helper's brief ends with `Your slot is <s>.` in a
parallel run, and `Your worktree is ap-<s>b.` (or `ap-<s>c`) for a helper of a slot's queue.

`ap-run cleanup <run> [--older-than <m>] [--min-free-gb <n>]` passes both options to
`hooks.cleanup` (it adds `--older-than 90` itself only while another run goes on and none was
given): the manager of a parallel run gives `--older-than 90`.
