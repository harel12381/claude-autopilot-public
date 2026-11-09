---
name: waiting
description: The owner has time - go through everything that waits for them, one issue at a time, and write their answers on the issues
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-config:*), Read, Grep, Glob, Edit, Write, AskUserQuestion
---

# /ap:waiting

Arguments: `$ARGUMENTS`

The owner is at the computer and has time for the things only they can do: answer a question,
pick between choices, look at a design, do a step in one of their accounts. Your job is to make
that time count. They answer; you do all the writing. Background:
`${CLAUDE_PLUGIN_ROOT}/docs/autopilot.md`.

**First, the project's settings:** read `.claude/ap.json`. Use `repo`, `owner` (the name in
**Waiting for <owner>.**), `chat_language` (talk to the owner in it; everything written on GitHub
is simple English, `${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md`) and `board` (missing: no board
step). No `.claude/ap.json`: say in one line that `/ap:setup` must run first, and stop.

## Which mode am I in?

- **Empty** -> everything with `status:waiting-for-owner`, except the issues the owner skipped
  before (`status:later`).
- **`all`** (`/ap:waiting all`, or `/ap:waiting-all`) -> everything with
  `status:waiting-for-owner`, the skipped issues too. Show the skipped ones last, marked
  "skipped".
- **Issue numbers** (`/ap:waiting 37 54`) -> only those, skipped or not.

## 1. The overview

```bash
gh issue list --state open --limit 200 --label "status:waiting-for-owner" --json number,title,labels --jq '
  map(.p = (([.labels[].name] | map(select(test("^P[0-3]$"))) | first) // "P9")
      | .later = ([.labels[].name] | any(. == "status:later")))
  | sort_by(.later, .p, .number) | .[] | "#\(.number) \(.p) \(if .later then "later " else "" end)\(.title)"'
gh issue list --state all --search "[autopilot] in:title" --limit 1 --json number,title,state
gh issue list --state open --label "status:blocked" --limit 50 --json number,title
gh issue list --state open --label inbox --json number --jq length
```

Without `all`, drop the lines marked `later`. Read each waiting issue (`gh issue view <N>`, then
`gh issue view <N> --comments`: that one prints only the comments), mainly its last
**Waiting for <owner>.** comment. Then show the owner one short list, and nothing else yet:

- One line per issue: the number, what it is about in a few words, and its kind:
  **answer** (a question they can answer in one line) or **do** (a step in an account, a console
  or on a device, which takes minutes).
- The order: first the issue that the most other issues wait for, then `P0` to `P3`. Say what an
  answer sets free: "#37, the API access: #41 and #59 wait for it".
- If the list is empty, say so and stop after the lines below.

Under the list, at most four lines, with no question in them:

- The last autopilot run: its issue number, and how many issues it merged.
- Blocked issues, grouped by what they wait for ("API access: #23, #25, #31"). An issue whose
  **Blocked until** date has passed: remove its `status:blocked` and say so in that line ("#54:
  its date passed, ready for `/ap:run`").
- The inbox, when it has notes: "3 notes in the inbox: `/ap:inbox`".
- Without `all`, the skipped issues, when there are any: "2 skipped before: `/ap:waiting-all`".

Then start with the first issue. Do not ask where to start: the owner can say a number at any
time.

## 2. One issue at a time

**Show it short.** Two or three lines of background, in simple words. The owner has not read the
issue today, and will not read a wall of text. Then the questions.

**An "answer" issue**

- Closed choices go through AskUserQuestion: your suggestion first, marked "(Recommended)", and
  one line under each choice on what it means. Up to four questions of one issue in one call.
- An open question (a name, a text) is asked in the chat, with your suggestion.
- A design to approve: show it (the mockup or the screenshot on the issue) before you ask.
- Product choices are the owner's. Give a suggestion, never the answer.

**A "do" issue**

- Walk the owner through it, one step at a time: the page to open, what to click, what to type.
  Wait for them after each step that they do.
- Say what you need back: an id, a file. **A secret never goes into the chat or an issue**: tell
  them the key name and where it goes (the project's `.env` or its secret store), and check that
  the key name is there (never print its value).
- When their part is done, do the part that follows right away only if it takes a minute (a file
  in place, a check command). Real work becomes ready for `/ap:run`, see step 3.

**The owner can always say** "skip", "later" or "I do not know". Then `status:waiting-for-owner`
stays. If they gave half an answer, write that half on the issue.

**"skip" or "later"** also adds `status:later`, and a one-line comment: "Skipped in /ap:waiting
on <date>." The next `/ap:waiting` leaves the issue out, so that what they put off does not come
back every time; `/ap:waiting-all` still shows it. "I do not know" adds nothing: the issue may
need a better question, so say on the issue what was missing.

## 3. Write it down at once

After each issue, before the next one (`${CLAUDE_PLUGIN_ROOT}/docs/record_keeping.md`). The owner
may close the session at any second.

1. A comment on the issue: the question, the owner's answer (their own words when short,
   translated to simple English when they wrote in another language), the date. Simple English.
   On a `[retro]` look-back issue, the comment starts with `**Decided** (<owner>, /ap:waiting,
   <date>)`, then one numbered line per proposal: its few words and **yes** or **no**. It ends
   with: "Ready for an agent: make each "yes" change exactly as its proposal says. A "no" is not
   done." The next run takes it first, whatever its kind (`ap-list` looks for that first word).
2. The body: move the answered lines from *Still to decide* to *Decided*.
3. The labels: remove `status:waiting-for-owner`, `status:needs-decision` and `status:later` when
   nothing is left to ask.
4. A `type:decision` issue that is settled gets a closing comment and is closed.
5. **Make the next work ready for an agent.** An answer usually sets work free:
   - An issue that waited only for this: remove its `status:blocked`, and add a comment with the
     answer, so that the agent who takes it does not have to look for it.
   - No issue for the work yet: open one, with the answer under *Decided*, labelled in full, and
     put it on the board (`gh project item-add <board.number> --owner <board.owner> --url <url>`,
     only when there is a board).
   - Something done in an account or a console: what, where, how to undo it, on the issue.

Do not build anything here. The owner's time is for the answers; the building is for `/ap:run`.

## 4. When you are done

**The report**, short, in the `chat_language`:

- Answered: one line per issue, with the answer in a few words.
- Still waiting: the issues the owner skipped (these now have `status:later`).
- Ready for an agent now: the issues that the answers set free. If there are any, the last line
  says that `/ap:run` will take them.
- `Recorded: #37 (decision), #41 (unblocked), #63 (new issue).`
