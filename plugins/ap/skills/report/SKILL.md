---
name: report
description: Report a bug the owner found - file it as an issue (or update its issue), then change the project's checks so they catch its kind next time
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-git-sync:*), Bash(ap-config:*), Bash(ap-check:*), Read, Grep, Glob, Edit, Write
---

# /ap:report

Arguments: `$ARGUMENTS` (the owner's words about the bug; screenshots may be attached in the
chat).

Two parts, always in this order: **first the issue, then the method.** The issue is the record
(`${CLAUDE_PLUGIN_ROOT}/docs/record_keeping.md`); never start on the method or a fix before it
exists.

**First, the project's settings:** read `.claude/ap.json`. Use `repo`, `owner`, `chat_language`
(talk to the owner in it), `main_branch`, `check` and `board` (missing: no board step). No
`.claude/ap.json`: say in one line that `/ap:setup` must run first, and stop.

If the arguments are empty, ask the owner what they saw, in one line, and stop.

## Part 1: the issue

### 1. Understand it

- Read `${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md` before you write. Read the code only as much
  as you need to name the screen, the command or the files.
- Look at each screenshot closely: the screen, the theme, the language, the time, what is wrong.
  Write what it shows in words on the issue (`gh` does not upload screenshots).
- Several bugs in one report: one issue per bug, handled one by one.

### 2. A duplicate?

```bash
gh issue list --state all --search "<2-3 keywords>" --json number,title,state --limit 20
```

| Found | Do |
|---|---|
| An open issue for the same bug | Comment on it with the owner's new words and what the screenshots show. Keep its number. |
| A closed issue for the same bug | It came back. Reopen it (`gh issue reopen <N>`), comment "Came back on <date>:" and the details. A bug that comes back is a failed check: say so in part 2. |
| Nothing | Open a new one (step 3). |

### 3. A new issue

Title `[bug] <short, plain>`. Body in simple English, with the bug headings: What happens · What
should happen instead · Steps to reproduce · The cause (write "Not known yet" if so). Put the
owner's own words at the end under **<owner>'s words** (verbatim, any language).

```bash
gh issue create --title "[bug] ..." --label "type:bug,P2,area:<area>" --body-file <file>
gh project item-add <board.number> --owner <board.owner> --url <issue url>   # only with a board
```

Labels: `type:bug`, one priority (P0 broken for everyone, P1 a main flow, P2 most bugs, P3
small), one `area:*` when the project uses them, and `parallel-safe` when the fix is small and
safe to run beside other work.

Tell the owner in one line: the number, the title, new or updated.

## Part 2: why we missed it, and the fix to the method

Read the project's bug-finding method first, when it has one: the doc its `CLAUDE.md` names for
it (a list of bug kinds, a screen checklist, a list of what only a real device can show). Then:

1. **The kind:** which kind of bug in that method is this? None fits, or the project has no such
   list: it is a new kind.
2. **Why it got past:** pick one, with the reason in one or two sentences:
   - no check for this kind;
   - the check exists but did not run on the change (which PR, why not);
   - the check ran but was not strict enough (what it did not look at);
   - only a real device can show it (then: did the PR ask for a check on one?).
3. **The change to the method,** so this bug and its cousins are caught next time. The smallest
   thing that would have caught it:
   - a line in the project's checklist;
   - a new kind in its list of bug kinds;
   - a test that fails on today's code (a unit, a widget, an end-to-end test);
   - a step in a sweep the project runs.
4. **Write it on the issue** as a comment that starts with **Why our checks missed it.** (the
   kind, the reason, the change). Put the change a fix must make under "For the fix".
5. **Make the change:**
   - A docs change (a checklist line, a new kind): do it now. Branch `docs/<N>-catch-<slug>`
     from `origin/<main_branch>` (`ap-git-sync fetch` first), in your own worktree if other
     sessions use the main checkout. Then run the project's check (`check`), push with
     `ap-git-sync push`, open the pull request into `<main_branch>`, and merge it
     (`gh pr merge <PR> --squash --match-head-commit "$(git rev-parse HEAD)"`) only after the
     check passed. The project's own merge rules (its `CLAUDE.md`) hold too.
   - A test or a sweep step: add it to the bug issue under **When is it done**: "A test that
     fails on the old code: <which>". Whoever fixes the bug writes it first, sees it fail, then
     fixes. When the check is bigger than this one bug, open its own issue and link both.
6. **Same kind elsewhere:** name the mistake in one sentence and look for it in the other
   screens, commands and flows. Each new find is its own issue (or a comment on this one if it is
   the same fix).

## When you are done

Reply in the `chat_language`, short: the issue (new, updated or reopened), the kind, why it got
past, and what changed in the method. End with `Recorded: #<N> (bug)` plus any other issue you
opened.

Do not fix the bug itself unless the owner asks. The next `/ap:run` takes it.
