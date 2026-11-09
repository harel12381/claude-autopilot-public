# Write issues in simple English

Read this **before you write or edit any issue, issue title, issue comment or pull request text**.

**The owner reads every issue, and English may not be their first language.** Dense English makes
the tracker hard to use for the person who makes the decisions in it. An issue the owner cannot
read is a broken issue. (The owner's name is `owner` in `.claude/ap.json`.)

Applies to: issue titles, bodies, comments, pull request text, and the project's issue forms.
It does **not** apply to code comments, docs or commit messages. The chat with the owner is in
their `chat_language`.

## How to write it

- **One idea per sentence.** Short sentences. Common words.
- **Bullets, not paragraphs.** A paragraph over about four lines is usually a list.
- **Explain the choice, don't compress it.** "Good:" / "Bad:" lists beat a clause packed with
  trade-offs.
- **Say what to do.** "Decide this before we build live updates (#9)", not "gated on the
  realtime milestone".
- **No jargon where a plain word works.** Not *precedence*, *degrade gracefully*, *surface*,
  *spike*, *abstraction*. Write "which one wins", "keeps working with less detail", "screen",
  "try it out first", "one small shared interface".
- **Keep real code names exactly as they are** (`src/router.ts`, `lib/cache.py`, field names). An
  agent needs them to find the thing. Explain each one in plain words the first time it appears
  in that issue: "`jobs/import`, the job that loads the price list every night".
- **English only.** No other language in issues (the `inbox` note is the one exception, until
  triage).

Example of the right level:

> **What we want**
> - A button on a card that shares it.
> - The link opens the app on that card.
>
> **When is it done**
> - The link works in the web app.
> - The button reads right in every language the app has.

## Headings to use

| Kind of issue | Headings |
|---|---|
| Feature | What we want · Why · Decided · Still to decide · How to build it · Saved data |
| Decision | The question · The choices · What I suggest · What is waiting for this · Can we change our mind later? |
| Task / chore | What is already done · What is left · When is it done |
| Bug | What happens · What should happen instead · Steps to reproduce · The cause |

## The closing comment

**Every issue that gets closed gets a closing comment**, and is closed by hand:
`gh issue comment <N> --body-file <file> && gh issue close <N>`. `Closes #N` in a PR closes an
issue only on a merge into the repository's default branch, and the run merges into
`main_branch`, which may be another one. The issue is where decisions are looked up later. Use
these parts (skip the ones that do not apply):

- **Fixed in `<commit or PR>`** (or "Closed without code" and why).
- **The problem:** what was really wrong, found while working on it. For a bug or anything that
  went wrong, this is the root cause: why it happened, and why no check caught it.
- **The same problem in other places:** where you looked, and what you found and fixed there.
  "Looked in X and Y, found nothing" is an answer too.
- **So it does not come back:** the test or check that holds it now.
- **Decision:** anything chosen on the way, and why. Future agents must not undo it by accident.
- **What changed:** in plain words, with the file or function names.
- **Tests:** what checks it now, and what was **not** tested (for example: only in one browser).
- **Left for later:** follow-ups, with their new issue numbers.

## "Waiting for the owner"

When an issue needs the owner, add the label `status:waiting-for-owner` and a comment that starts
with **Waiting for <owner>.** (the owner's name). Then list what they must answer or do:

- Short numbered questions they can answer with "yes", "no" or one line. Say your suggestion.
- Or the exact thing only they can do (a step in an account, a key to put in a secret store),
  and what happens after.
- What an agent will do once they answer.

Agents never start these issues alone. When the owner answers (on the issue or in a chat), write
the answer on the issue and remove the label.
