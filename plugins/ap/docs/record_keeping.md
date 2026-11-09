# The chat is not the record

Read this when you are unsure whether something from the session must go into an issue, or where.

## Why

The owner does not always read the chat. They close sessions, the context is compacted, and the
next agent starts cold. Anything that exists **only** in a chat reply is lost. The GitHub issues
of the project (`repo` in `.claude/ap.json`) are the one place the owner, and the next agent, will
look. So: **if it still matters after this session ends, it is written on an issue before the
session can end.**

Test for every reply you are about to send: *"If the owner closes this session right now and only
reads GitHub, do they lose anything?"* If yes, write it to an issue first, then send the reply.

## What must be recorded

| What happened in the chat | Where it goes |
|---|---|
| The owner made a decision or answered a question | Comment on the issue it belongs to: the question, the answer, the date. Update the issue body's *Decided* part. Close the `type:decision` issue if it is settled. |
| You recommend something and it needs the owner (a choice, an account step, a key) | The issue, with `status:waiting-for-owner` and a comment that starts with **Waiting for <owner>.** Asking only in the chat is not enough. |
| You asked the owner a question and they did not answer | Same as the row above. An unanswered chat question is a lost question. |
| You found a root cause, explained how something works, or ruled a theory out | Comment on the issue: what you checked, what you found, what it means, with the evidence (file:line, log line, command). A dead end is worth recording too. |
| Something went wrong on the way: a check failed, a script or a git command failed, a tool did something odd | A small one: the cause and the fix in the pull request text. A bigger one: a **new `type:bug` issue**, at once. Never only a retry. |
| You noticed a bug, a risk, missing tests, or other work that is out of scope | A **new issue** (with the project's issue forms, when it has them). |
| You did something outside the code: on a server, in a cloud console, an account setting | Comment on the issue: what, where, when, how to undo it. If there is no issue, open one and close it with that comment. |
| A plan was agreed for work with more than a few steps | On the issue before you start: the steps and what "done" means. |
| Work stopped part way | Comment: what is done, what is left, what you tried and why it failed, the next step. |
| You changed your mind about something you said earlier | Correct it on the issue too. |

**A write that fails is seen.** A command that writes to GitHub, git or a server (`gh issue comment`, `create`, `edit`,
`close`, `gh pr comment`, `gh project item-add`, a commit, a push) is joined to the next step with
`&&`, never `;`, and its output is never sent to `/dev/null` or cut with `tail`, `head` or `-q`
without `set -o pipefail`. A write that fails must stop where you see it: GitHub can answer an
error once (HTTP 499, 502), and a lost comment is lost work. When it failed, write it
again.

**Search before you open a new issue:** `gh issue list --state all --search "<2-3 key words>"`.
When an open issue already has it, add what you found there as a comment instead. A closed one
that has it: name it in the new issue.

Not recorded: the step-by-step of routine work, tool output, and anything the commit and the code
already say clearly.

## When

**At the moment it happens, not at the end of the session.** A session can be closed at any
second. Write the issue comment first, then send the chat reply.

## Every task has an issue

- If the owner asks for something about the project and there is no issue for it, open one
  **before** starting (a small, reversible action: do not ask). Small tweaks of one area can share
  one issue.
- One conversation that touches several topics records each on its own issue.
- Questions with no code change still get recorded when the answer took real investigation or
  will be needed again.
- A task that is not about the project (general research, a setup on the computer) needs no
  issue, unless the project's `CLAUDE.md` says otherwise.

## The chat reply

End any reply that recorded something with one line that says where it went:
`Recorded: #12 (decision), #15 (new bug), #7 (waiting for <owner>).`

## What is not a substitute

- Agent memory is private to agents. Anything in it that the owner would want to know also goes
  on an issue.
- A commit message is read by agents and `git log`, not by the owner.

Every issue comment follows `issue_writing.md` (simple English).
