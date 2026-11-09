# Autopilot and waiting: the two modes of work

Read this when the owner runs `/ap:run` or `/ap:waiting`, or says they are going away and want
the work to go on. The procedures themselves are the plugin's skills (`skills/<name>/SKILL.md`).

The owner's time and the agents' time are different things. Most issues need none of the
owner's. A few need one line from them, or five minutes in one of their accounts, and until then
they block others. The commands keep those apart:

| Command | When | What happens |
|---|---|---|
| `/ap:run` | The owner is away or busy | The session is a manager. A planner agent first cleans up the run's issues (missing type and size labels, duplicates, big issues, "When is it done"). Then one fresh helper agent per issue, from the branch to the merged pull request, and a fresh reviewer agent that checks each pull request before its merge. Whatever needs the owner gets `status:waiting-for-owner` and the run moves on. At the end a retro agent looks back at the run and writes proposals for the owner. The owner's phone gets a message when they are needed and when the run ends (when the project set `hooks.notify`). |
| `/ap:bugs`, `/ap:features`, `/ap:tests`, `/ap:chores` | The owner is away, and wants one kind of work | `/ap:run` that takes only the issues with that label: `type:bug`, `type:feature`, `type:test`, `type:chore`. The same as `/ap:run bugs` (and `features`, `tests`, `chores`). Other arguments work too: `/ap:bugs X2`, and a label limit with `only` and `not` (`/ap:bugs only area:app not size:L`). Every `P0` and every approved look-back issue still comes. |
| `/ap:stopnow`, `/ap:stop`, `/ap:stop-in <X>`, `/ap:stop-after <N>` | During a run, in its chat | End the run: at once, when each helper has finished its issue, at once after X minutes, or after the running issues and N more. The same as the plain words `STOPNOW`, `STOP`, `STOP IN <X>`, `STOP AFTER <N>`. The rules: "Stopping a run" in `skills/run/SKILL.md`. |
| `/ap:schedule` | The owner wants a run at a set time (every night) | This computer's scheduler starts a background session at that time, and it does `/ap:run` with the set arguments. It never starts beside another run: it writes that on the other run's issue and sends a phone message instead. The owner's part (the computer on, bypass permissions accepted once): `README.md`, "A run on a schedule". |
| `/ap:waiting` | The owner has time | Everything that waits for them, one issue at a time, short questions. The answers go on the issues, and the work they set free becomes ready for `/ap:run`. |
| `/ap:waiting-all` | The owner has time for more | Like `/ap:waiting`, plus the issues they skipped there before (`status:later`). |
| `/ap:inbox` | Any time | A raw note in, or the notes turned into real issues (`inbox.md`). |
| `/ap:plan` | Before a run | What `/ap:run` would take with the same arguments: the issues in its order, the groups, what could run at the same time, what starts before a stop, and what it leaves out and why. It only reads. `/ap:run` builds its list with the same script (`ap-list`; `/ap:plan` asks it for `--json`), so it takes the same list. |
| `/ap:status` | Any time, in a run's chat too | One short report: the run, what each helper does now, the open pull requests, the open issues by what they wait for (the owner's first), and what was opened and solved since the run started. It only reads: no comment, no label. |
| `/ap:report` | The owner found a bug | The bug as an issue, then the change to the project's checks that catches its kind next time. |
| `/ap:phone-check` | The owner has their phone and some time | The fixes only a real phone can show (`status:phone-check`), one at a time, step by step; the result goes on each issue. |
| `/ap:qa` | After a deploy, or before a merge that changes screens | The project's own cases on its site at phone size, in Chromium and WebKit, in each language and theme; failures go on their issues; the pictures are judged by eye. A run does it after a deploy, when at most one helper runs. |
| `/ap:bug-reports` | Users sent reports (bugs, feature requests) | Each new report judged by a read-only agent, the real ones filed as issues, and why the checks missed each bug. A run does it before its planner. |

The loop: `/ap:run` until only waiting issues are left, `/ap:waiting` when the owner is back,
`/ap:run` again.

## What the project gives

The plugin is the same in every project. What is only one project's lives in the project:

- **`.claude/ap.json`** (written by `/ap:setup`): the repository, the owner's name and chat
  language, the main branch, the board, the check (`ap-check` with the project's parts in
  `check_parts`, or the project's own command), and the optional parts: the deploy command and
  site, the cleanup, the phone message, the previews, and the parts `qa` (with its cases folder),
  `phone_check` and `bug_reports` (with the reports hook). A part that is not set is off;
  the run says so in one line on the run issue and goes on.
- **`.claude/ap/helper.md`, `reviewer.md`, `manager.md`** (named in `briefs.*`): the project's own
  rules for each agent, added after the plugin's brief. This is the place for how to build and
  look at the app, the design rules, which ports and servers a helper uses, steps after a deploy,
  and anything else that only this project has. They add rules; they never make a check weaker.
- **The project's `CLAUDE.md`**: every agent follows it in full.

## Before an away run (the owner)

- **Start the session in a mode that does not stop for prompts.** A helper that waits for
  "allow this command?" stops the whole run, and nobody is there to answer. The helpers, the
  planner, the reviewer and the retro agent are `general-purpose` agents: the `allowed-tools`
  line of a skill reaches only the manager, never them, and they need git, gh, Edit, Write,
  Monitor and more. So an away run needs one of these:
  - the session in auto mode, or in bypass permissions (`claude --permission-mode
    bypassPermissions` in a terminal);
  - or the full allow list that `/ap:setup` prints (git, gh, the `ap-*` scripts, the project's
    check, deploy and hooks, Read, Edit, Write, Glob, Grep, Monitor, Agent, SendMessage,
    TaskStop) in the project's `.claude/settings.json`.
- **A board needs the `project` scope.** When `.claude/ap.json` has a `board`, `gh project` needs
  it: `gh auth refresh -s project`. Without it, each board step fails; the run writes one line on
  its issue and goes on.
- **Leave the computer on.** The run lives in that session. A scheduled run (`/ap:schedule`) starts
  its own session in bypass permissions, so that mode must have been accepted once.
- **Messages on the phone:** the run sends them with `ap-notify`, through the command in
  `hooks.notify`. Without one, the message is only printed.
- **After `STOP`, start the next run when the old one says "The run is over. A new run can start
  now."** Its end (the last deploy, the look back) can take a while, and a new run started
  meanwhile gets its own run issue.
- **Only one run at a time**, and no other session on the same issues. Nothing stops two sessions
  from taking one issue. For more speed, run one manager with `X<N>` (below), not two runs.

## Parallel runs: `/ap:run X2`, `/ap:run X3`

`X<N>` lets the manager run up to N helpers at the same time, each on its own issue. Without it,
the run is one helper at a time. The procedure is section 4b of `skills/run/SKILL.md`. What keeps
the helpers out of each other's way:

| Shared thing | The rule |
|---|---|
| The checkout and the branch | One worktree per slot, `.claude/worktrees/ap-<slot>`, kept for the whole run. Each helper works there on its own new branch from the main branch: it checks that the helper before it left everything committed and pushed, then `ap-git-sync new-branch <branch>`: a fetch, `git switch -c <branch> origin/<main>` and `git clean -fd` (no `-x`, so the ignored build caches stay), in one command that refuses a tree with work not committed. The main checkout is the manager's, always on the main branch. At the end of the run the manager removes the worktrees its run holds, after the test runs that may hold their files are stopped; the branches stay. Two runs can use the same slot worktrees (a run that went on after a `STOP`, while the old manager session stayed open), so each run writes down which slots it holds (`ap-run hold`): the end of one run leaves another run's worktrees, previews and young test runs alone. |
| The `.git` folder (fetch and push) | Every worktree shares one `.git` folder, so the remote refs too. Two `git fetch` at once fail ("incorrect old value provided": git checks each ref still has the value it read, and the other fetch changed it). So helpers and the manager fetch, pull and push only with `ap-git-sync`: one at a time, with a lock in the shared folder. Its `push` sends the branch to `origin/<branch>` and fails unless GitHub has it; the merge is `gh pr merge --match-head-commit "$(git rev-parse HEAD)"`, so GitHub never merges an older commit. A push in the background, or piped into `tail`, can fail unseen: so a push always runs in the foreground, alone. |
| The same files | The manager starts two issues together only when their `area:*` labels differ, or both have `parallel-safe`, or the planner's `files` lines for the two share no folder or file (and neither is `?`). No `area:*` label: alone. A `P0` first. |
| The scripts and rules every helper uses | One `area:tooling` issue at a time may run beside other helpers, only if it harms nothing else. It keeps every script it changes working for helpers that still use the old copy. It never stops, restarts or changes other helpers' servers, containers, checks or worktrees. A PR that changes the check, the cleanup or the run's rules says under "For the manager" what the manager must do after the merge. |
| The main branch | Merges one at a time: the helper reports `ready #<PR>`, the manager gives one helper at a time the merge turn. In its turn it merges the latest main branch in, solves conflicts, runs the check again, then merges. With `merge_batch` above 1, the manager merges a few approved pull requests together instead (`ap-batch`, below). |
| A helper's waits | With `queue_per_slot` above 1, when a helper reports that it waits for a check, a review or its merge turn, the manager starts a fresh helper on a second issue in a second worktree of the slot (`ap-<s>b`), on its own branch, with its own brief. Each helper holds one issue, so its context does not fill with two. Only from another `area:*`, with `files` lines that do not overlap; a fix to the first goes to its own helper, which is still there, first. Each worktree is held and removed by `ap-run`, like `ap-<s>`, and the disk check before a new worktree counts it. |
| Memory, CPU and the check | `ap-check` lets only one run of heavy steps go at a time across worktrees (a lock in the shared `.git` folder), runs light steps beside them only when enough memory is free, and one run of each part at a time. A part whose inputs passed before, in any worktree, is skipped. A helper's check then waits for another's; the manager writes long waits on the run issue. |
| Other ports, containers | A helper's own servers use the usual port + 100 times its slot number (10 more in `ap-<s>b`, 20 in `ap-<s>c`); its containers end in `-ap<slot>` (`-ap<s>b` in `ap-<s>b`), unless the project's part says otherwise. |
| Temporary files | The session's scratchpad folder is shared by every helper: each one writes in its own `ap<slot>-<issue>/` folder in it, so one helper's `pr.md` never overwrites another's. |
| Disk | Each slot worktree has its own build caches. The manager starts a helper with a new worktree only with 11 GB free, and any helper only with 5 GB free (`ap-run cleanup ... --min-free-gb`, through the project's cleanup). |
| The server | Only the manager deploys, every 5 merges and at the end. |

## Why it is built this way

- **A fresh helper per issue.** A helper starts with an empty context. The manager keeps one line
  per issue, so one session lasts a whole day of work.
- **One issue at a time, unless `X<N>`.** Two helpers in one checkout conflict on the branch; a
  parallel run gives each one its own worktree, and the rules above.
- **Helpers hand their resources on.** The slot worktree, its build caches and its preview stay
  for the next helper of that slot, so a helper does not start cold.
- **A fresh reviewer checks every pull request before its merge.** The helper runs `/code-review`
  and `/simplify` on its own diff, with its branch and its worktree as the target. Both start
  sub-agents that only read; a helper may start no other agents. But an author misses its own
  mistakes, and it already "knows" what the code was meant to do. So when a helper reports
  `ready #<PR>`, the manager starts a reviewer agent that did not see the work. It reads the
  issue, the PR, the diff and the project's rules, and checks three things: the PR does all the
  issue asks; the project's rules; bugs and missing cases. It writes its result as a PR comment in
  simple English (`approve`, or `changes` with a numbered list) and never changes code. On
  `changes` the same helper fixes them and reports `ready` again, and the same reviewer looks
  again. A fix is new code: the helper runs `/code-review` on its fix commits before it reports
  `ready` again, and each new flag, branch, loop or wait gets a test. After 2 rounds of fixes that
  still do not pass, the PR stays open and the issue gets `status:waiting-for-owner`; a third
  round comes only when every point left is a new bug of the last fix (the reviewer says so). One
  reviewer at a time.
- **The manager runs the check on every approved branch.** The helper says its check passed, and
  the project may have no CI, so the manager makes sure: `ap-check-branch` runs the check in a
  fresh worktree of its own, and only a branch whose check passes gets its merge turn. A failing
  check goes back to the helper, like a review change, unless main fails the same way in a fresh
  folder: then the project's setup is the cause (`hooks.check_setup`), and the owner is told.
- **A planner cleans the list up before the first helper.** Two issues can ask for the same
  thing; a `size:L` issue is too big for one helper; an issue with no "When is it done" leaves its
  helper guessing. The manager cannot see any of this from titles. So at the start of every run it
  starts one planner agent that reads the bodies once and: closes the newer of two duplicates
  (what it added goes on the older one); splits a big issue into the parts its own text names
  (the big one becomes `tracking`); writes a missing "When is it done" from the issue's own words,
  or asks the owner when the goal itself is unclear; and writes `Needs #M first.` where one issue
  builds on another. It changes only issues of the run's list, leaves alone every issue that waits
  on the owner or that a helper or a pull request is on, and never makes a product choice. A
  planner that fails costs nothing: the run goes on with the list as it was.
- **The helper decides whether it can do the issue alone**, not the manager. The manager would
  have to read every issue body to know, and its context is the thing to protect.
- **Helpers push after every commit.** A usage limit can cut a run off in the middle of an issue.
  With the branch on `origin`, a fresh helper goes on from it. The push is `ap-git-sync push`, in
  the foreground: a push that fails stops the helper, instead of hiding in a background log.
- **Helpers wait with `Monitor`, never by ending their message.** The end of a helper's message
  is its report. A helper that ends its message to wait for a background check gives the manager
  half a report, and must be sent back.
- **`status:in-progress` marks an issue a helper took.** The list leaves such issues out. An
  issue stopped by `STOP` or `STOPNOW` (its last comment starts with **Stopped in the middle.**)
  goes first in the next run's list, by itself, once no other run goes on: nobody has to remember
  it. One that is still marked for another reason (a run that was cut off with no comment) is
  picked up by name: `/ap:run <N>`.
- **The look-back issues the owner decided go first too**, whatever the run's kind: they change
  the run itself, and a run of one kind would never take them.
- **The list is built in one place**, `ap-list`, with the label limit (`only`, `not`, a kind). The
  `ready` list of `/ap:status` is built from the same code, so it shows what the next run takes.
- **Every run has its own `[autopilot]` issue** with the `tracking` label: one comment per
  finished issue, written when it happens, and a closing comment with the summary. That is what
  the owner reads when they are back; the chat may be gone.
- **Helpers design on their own, and never wait for approval.** They follow the project's design
  rules, check the result themselves, and write each choice on the issue under "Decisions (the
  agent chose, <owner> can change them)".
- **The manager deploys every 5 merged issues and at the end of the run**, not each helper: a
  deploy after every issue costs time. Only when the project set a `deploy` command. It deploys
  with `ap-deploy`: from the main checkout, on the main branch, clean and equal to origin, it runs
  the check, then the `deploy` command only when the check passed.
- **Small issues of one area go to one helper:** up to 3 issues in a row in the list, with the
  same `area:*` label and `size:S`. One branch, one PR, a closing comment for each issue.
- **A helper never releases, spends money or changes a console.** Releases and version tags
  happen only when the owner asks; a server changes only through the project's deploy.
- **A helper ends with nothing of its own still running.** A helper whose background command was
  still open can wake up again and report twice. The manager stops a helper that is still listed
  as running after its report. On Windows, stopping a background task ends only its shell, and the
  programs under it keep running, so long background commands run through `ap-background`, which
  stops the whole tree when its shell is gone. The plugin's hook (`ap-background-hook`) refuses a
  long background command without it (`background_wrap` in `.claude/ap.json`), so nobody has to
  remember.
- **Helpers clean up before they report.** A test run that is killed can leave large temp folders
  and running processes. The project's cleanup (`hooks.cleanup`) removes them; the manager runs it
  through `ap-run cleanup`, with `--older-than 90` while helpers run, so it never stops a young
  test run of another helper.
- **Merges in batches** (`merge_batch`). The check at each merge turn, after the latest main is
  merged in, seldom fails, and it is a whole check each time. So up to `merge_batch` approved pull
  requests (each with its own passing check) are merged together on the latest main in a folder
  of their own, checked once, and merged into main, each still by itself with `--squash
  --match-head-commit`, so each closes its issue. `ap-batch merge` then makes sure main has the
  tree that was checked. When the batch's check fails, `ap-batch` checks the first half, and so
  on, until it has the first pull request with which it fails: that one goes back to its helper
  like a review change, the ones before it are merged, the ones after it wait for the next batch.
  The manager writes no code, so a pull request that does not merge cleanly leaves the batch and
  goes back to its helper's merge turn. `/ap:setup` suggests 1 when the checks before a merge
  fail often (1 in 10 or more: each failure costs the checks of its halves), else 3.
- **A queue per slot** (`queue_per_slot`). About half of a helper's time on an issue goes to
  waiting: the review, the check on its branch, the merge turn. With a queue, the manager starts a
  fresh helper on the slot's next issue then, in a second worktree of the slot. The first helper
  keeps only its own issue and does its fixes as soon as they are asked for; no helper holds two
  issues, so no context fills with both. The next issue comes only from another `area:*` than the
  slot's open ones, so a fix to one never breaks the other. `/ap:setup` suggests the number from the computer's free
  memory and disk, the size of a built worktree, and the check's time.
- **The check's log says what each saved.** `ap-check` writes the kind of every check (a batch, a
  half of one) and, in a slot worktree, how many issues the slot's other worktrees had open. The
  run's closing comment gives `ap-check --stats`'s "Time saved" lines: the batches saved the
  merge-turn checks they replaced, less their own checks; the queues saved at least the time of
  the checks that ran while their slot had another issue open. A slot often idle while its
  helper waits means raise `queue_per_slot`; fixes that come back late, or the disk check that
  stops helpers, mean lower it.
- **"Is the main branch green?" is the project's check on it.** The check is the only gate before
  a merge.
- **Four kinds of stop.** Each one either stops at once (the helper commits and pushes what it
  has and writes on its issue where it got) or lets each helper finish its issue. `STOP` waits
  however long that takes; `STOP IN` is the command for a time limit. The manager is woken only by
  events, so for `STOP IN` a background `ap-run stop-wait` ends at that time and wakes it. Helpers
  run in the background so the manager gets the message at once. Outside a run, the commands only
  say that no run is going on. A stopped issue keeps `status:in-progress`; `/ap:run <N>` goes on
  with it.
- **Three failed helpers in a row stop the run.** By then the cause is shared, and each further
  helper costs a full issue's budget to find the same thing.

## What an agent can do alone

Not alone, so `status:waiting-for-owner`:

- Anything that would cost money or bring a usage limit, when the project's rules forbid it.
- A product choice that cannot be undone cheaply (a name, a price), or anything the issue lists
  as the owner's under *Still to decide*.
- Anything in the owner's accounts or with outside parties: cloud consoles, app stores,
  payments, keys.
- A release (a version, a tag, a merge into another branch than the main branch).

Alone, and written on the issue under "Decisions (the agent chose, <owner> can change them)": a
technical or design choice that can be changed later without touching saved data.

Blocked, not waiting (`status:blocked`): needs another issue first, an outside party that the
owner already asked, or a date or an event outside the repository (a weekly job, a failure that
must come back). Its comment starts with **Blocked until**: the date or the event, and what closes
the issue then. The run's list leaves it out, so no helper is started for it again and again. `/ap:waiting` lists these in one line and asks nothing about them.

## Labels the run uses

`type:bug`, `type:feature`, `type:test`, `type:chore`, `type:decision`; `P0` to `P3`; `size:S`,
`size:M`, `size:L`; `area:*` (the project's own, and `area:tooling`); `status:in-progress`,
`status:waiting-for-owner`, `status:needs-decision`, `status:blocked`, `status:later`;
`tracking`, `inbox`, `parallel-safe`. `/ap:setup` makes the ones that are missing.
