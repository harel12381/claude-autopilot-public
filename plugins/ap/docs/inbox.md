# The inbox

Read this when the owner says "inbox:", runs `/ap:inbox`, or asks you to triage.

Every issue is a small piece of writing. That is right for the tracker and wrong for the moment
an idea arrives. The inbox is the release valve: **capture is free, structure is the agent's
job.**

## Capturing (the owner)

1. **An issue form** "Inbox note", when the project has one: one free-text box, the `inbox`
   label. It works from the GitHub mobile app.
2. **Say it in a session:** "inbox: a button to share a card", or `/ap:inbox <the note>`.

A captured note may be everything a normal issue may not be: one line, no context, shorthand,
**and any language**. This is the one exception to "issues in English", and it lasts only until
triage.

## Capturing (agent)

When the owner says "inbox: X" during a session, open the issue **at once** and go straight back
to the task. Do not triage it, do not ask about it:

```bash
gh issue create --label inbox --title "[inbox] <their first few words>" --body "<their words, verbatim>"
```

Keep their wording and their language exactly. Confirm with one line (number + URL) and move on.

## Triaging (agent, on request only)

Triage runs when the owner asks, or runs `/ap:inbox`. **Never triage unasked.** The full procedure
is the `inbox` skill (`skills/inbox/SKILL.md`). The rules that matter:

- **Understand before writing.** Read the code and the docs; search the tracker for a duplicate;
  check `git log` in case it already shipped. A note is a hint, not a specification.
- **Rewrite in place. Keep the number.** Never close an inbox note and open a replacement.
- **The output is a normal issue:** simple English, the headings from `issue_writing.md`.
- **Label fully:** one `type:*`, one `P0`-`P3`, one `area:*` when the project uses them,
  `size:*` for tasks. Removing `inbox` is what marks it triaged.
- **Do not guess.** If the note is too thin, ask the owner right then.
- **Nothing is dropped.** Every note leaves triage rewritten and relabelled, or closed with the
  reason written on it.
