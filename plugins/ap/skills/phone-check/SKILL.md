---
name: phone-check
description: The owner has their phone - check the fixes that only a real phone can show, one issue at a time, and write the result on each issue (/ap:phone-check)
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-config:*), Read, Grep, Glob, Write, AskUserQuestion
---

# /ap:phone-check

Arguments: `$ARGUMENTS`

The owner has their phone in their hand and some time. Some fixes are merged and live, but only a
real phone shows whether they work: sound, location, the locked screen, the phone's own browsers,
an app opened from the Home Screen, a real trip outside. These issues stay open with the label
`status:phone-check`. Your job is to lead the owner through each check so that it takes minutes,
and to write the result on the issue at once.

**First, the project's settings:** read `.claude/ap.json`. No file: say in one line that
`/ap:setup` must run first, and stop. `parts.phone_check` is not `true`: say in one line that
`/ap:phone-check` is off in this project and `/ap:setup` turns it on, and stop. Use `owner`,
`chat_language` (talk to the owner in it; everything on GitHub is simple English,
`${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md`, `${CLAUDE_PLUGIN_ROOT}/docs/record_keeping.md`)
and `site` (the address the steps open).

## Which mode am I in?

- **Empty** -> every open issue with `status:phone-check`, oldest first.
- **Issue numbers** (`/ap:phone-check 374 409`) -> only those, in that order.

## 1. The overview

```bash
gh issue list --state open --limit 200 --label "status:phone-check" --json number,title \
  --jq 'sort_by(.number) | .[] | "#\(.number) \(.title)"'
```

Read each issue (`gh issue view <N>`, then `gh issue view <N> --comments`), mainly its real-phone
steps. Then show the owner one short list, and nothing else yet: one line per issue, the number
and what to check in a few words. The list is empty: say so, and stop.

Then start with the first issue. Do not ask where to start: the owner can say a number at any
time.

## 2. One issue at a time

**Show it short.** In a few words: what was wrong, what was fixed, what they are going to check.

**Then lead them step by step, one step per message.** Wait for their "done", or for what they
see, before the next step. The steps come from the issue's real-phone steps, and from the project's
own list of what only a real phone shows, when its `CLAUDE.md` names one. Each step says exactly
what to do: which page to open (on `site`), in which browser or from the Home Screen icon, what to
tap, how long to wait, and what they should see.

- What they see is not what they should see: ask one short question to make it clear (when it
  happens, every time or once), then go on.
- A step they cannot do now (they are not where it happens, a needed app is missing): say so, and
  go on with the others.
- At the end, ask: is it fixed? Closed choices go through AskUserQuestion: **fixed**,
  **not fixed**, **skip**.

**They can always say** "skip" or "later". Then the issue stays as it is, for the next
`/ap:phone-check`.

## 3. Write it down at once

After each issue, before the next one: the owner may close the session at any second. Each
comment is written to a file in your scratchpad first (`gh issue comment <N> --body-file <file>`).

- **Fixed:**
  ```bash
  gh issue comment <N> --body-file <file> &&    # "Checked by <owner> on their phone on <date>: <what they saw>."
    gh issue edit <N> --remove-label "status:phone-check" && gh issue close <N>
  ```
- **Not fixed:** a comment: what they did, what they saw, on which phone and system version if
  they said, the date; their own words at the end (in simple English when they wrote in another
  language). Then remove `status:phone-check`, and `status:waiting-for-owner` when nothing is left
  to ask them, so the next `/ap:run` takes the issue again. When the next step needs their
  decision, add `status:waiting-for-owner` with a comment that starts with **Waiting for
  <owner>.** instead.
- **Skip:** nothing changes. A half check is still written as a comment ("Steps 1-2 checked on
  <date>: ..."), so the next check does not start from zero.

Do not fix anything here. The owner's time is for the checks; the fixing is for `/ap:run`.

## 4. When you are done

**The report**, short, in the `chat_language`:

- Fixed and closed: one line per issue.
- Back to the runs: one line per issue, with what they saw in a few words. When there are any, the
  last line says that the next `/ap:run` takes them.
- Skipped: the numbers.
- `Recorded: #374 (closed), #409 (not fixed, back to the runs).`
