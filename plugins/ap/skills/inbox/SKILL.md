---
name: inbox
description: Capture a raw note as an inbox issue (/ap:inbox <note>), or triage the inbox - turn the owner's raw notes into real issues (/ap:inbox, /ap:inbox <numbers>)
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-config:*), Read, Grep, Glob, Edit, Write
---

# /ap:inbox

Arguments: `$ARGUMENTS`

The rules behind it: `${CLAUDE_PLUGIN_ROOT}/docs/inbox.md`.

**First, the project's settings:** read `.claude/ap.json`. Use `repo`, `owner`, `chat_language`
(talk to the owner in it) and `board` (missing: no board step). No `.claude/ap.json`: say in one
line that `/ap:setup` must run first, and stop.

## Which mode am I in?

- **Empty** -> triage every open issue labelled `inbox`.
- **One or more issue numbers** (`/ap:inbox 61 64`) -> triage only those.
- **Anything else** (`/ap:inbox a button to share a stop`) -> capture mode: open a new inbox issue
  with that text as the body, then stop. Do not triage in capture mode.

## Capture mode

```bash
gh issue create --label inbox --title "[inbox] <first few words, kept as the owner wrote them>" --body "<the text, verbatim>"
```

Keep the owner's words exactly, in whatever language they used. Do not improve, translate or
expand the note. Reply with one line: the number and the URL. Then go back to whatever we were
doing.

## Triage mode

```bash
gh issue list --state open --label inbox --json number,title,body,createdAt
```

If the list is empty, say the inbox is empty and stop.

Take one note at a time, oldest first. For each one:

### 1. Understand it before you write anything

The note is a hint, not a specification. Work out what it really is:

- Read the code and the relevant docs as needed (grep them, never read them whole).
  Read `${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md` before you write the issue.
- Search the tracker for an issue that already covers it:
  `gh issue list --state all --search "<keywords>"`.
- Check whether it already shipped: `git log --oneline --grep "<keyword>"`.

Then decide which of these it is:

| It is... | Do this |
|---|---|
| Real, new work | Rewrite it in place (step 2). |
| A new feature idea | Rewrite it in place as `[feat]`. |
| Already covered by issue #N | Ask the owner first. If they agree: comment "Same as #N.", then `gh issue close <n> --duplicate-of N`. |
| Already done | Say which commit or release did it, comment that on the issue, close it. |
| Several things in one note | Rewrite the issue for the main one, open a new issue per extra thing, link them all. |
| Too vague to act on | Do **not** guess. Ask the owner right now, in this session. They ran this command, so they are here. |

### 2. Rewrite it in place, keeping the number

**Never close an inbox issue and open a replacement.** The number is the link the owner already
has. Edit the same issue:

- **Title**: the right prefix (`[bug]`, `[feat]`, `[task]`, `[decision]`), then a short, plain
  title. Drop the `[inbox]` prefix.
- **Body**: rewritten in **simple English**, with the headings in
  `${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md` for that kind of issue. The original wording in
  another language or in shorthand does not survive.
- When the project has issue forms (`.github/ISSUE_TEMPLATE/`), fill the body the way the
  matching form would have. The note usually lacks the "why" and the "when is it done". Work
  them out or ask.

```bash
gh issue edit <N> --title "<new title>" --body-file <file>
```

### 3. Label it properly

Every triaged issue ends up with, at least:

- exactly one `type:*`
- exactly one priority (`P0`..`P3`)
- one `area:*`, when the project uses area labels (`gh label list`)
- `size:*` if it is a task
- any other label the project's `CLAUDE.md` asks for
- `status:needs-decision` **only** if a question is still open after you asked the owner,
  together with `status:waiting-for-owner` and a **Waiting for <owner>.** comment with the
  question
- `parallel-safe` if it is small and safe to run beside other work

And always remove the marker, which is what "triaged" means here:

```bash
gh issue edit <N> --add-label "type:bug,P2,area:api" --remove-label inbox
```

### 4. Put it on the board

Only when `.claude/ap.json` has a `board`. A board with no auto-add rule has a new issue only if
someone put it there:

```bash
gh project item-add <board.number> --owner <board.owner> --url https://github.com/<repo>/issues/<N>
```

Adding an item that is already there is harmless.

## When you are done

Report, in the `chat_language`, one line per note: `#61 -> [feat] Share a stop (type:feature,
P3, area:app)`. List apart anything you closed as a duplicate or already done, and anything still
waiting on an answer from the owner.

Never drop a note silently. Every inbox issue leaves triage either rewritten and relabelled, or
closed with a reason written on it.
