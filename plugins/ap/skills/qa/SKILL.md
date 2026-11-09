---
name: qa
description: QA sweep - drive the project's site at phone size in Chromium and WebKit, in each language and theme, with the project's own cases, and judge every screen (/ap:qa)
allowed-tools: Bash(ap-qa:*), Bash(ap-background:*), Bash(ap-config:*), Bash(gh:*), Bash(git:*), Read, Grep, Glob, Edit, Write, Monitor
---

# /ap:qa

Arguments: `$ARGUMENTS` (optional): passed to `ap-qa` as they are, for example
`--url http://127.0.0.1:5190` or `--browsers chromium --langs he --only home`.

`ap-qa` runs the project's own cases (the folder `qa.cases` in `.claude/ap.json`) on its site with
Playwright at phone size, in Chromium and WebKit (Safari's engine), in each of the project's
languages and themes. Each case checks by itself what a still picture can't show, and saves
pictures of its screens for you to judge. The driver, the cases' interface and the settings:
`${CLAUDE_PLUGIN_ROOT}/docs/qa.md`.

**First, the project's settings:** read `.claude/ap.json`. No file: say in one line that
`/ap:setup` must run first, and stop. `parts.qa` is not `true`: say in one line that `/ap:qa` is
off in this project and `/ap:setup` turns it on, and stop. Use `owner`, `chat_language` (talk to
the owner in it; GitHub texts are simple English, `${CLAUDE_PLUGIN_ROOT}/docs/issue_writing.md`)
and `board`.

## 1. Run it

```bash
ap-background ap-qa $ARGUMENTS
```

In the background (`run_in_background: true`, `timeout: 7200000`): it takes minutes. Wait for it
with its notice or `Monitor`; never pipe it into `tail` without `set -o pipefail`, so its exit
code reaches you. Keep only its last lines and the failed rows (`FAIL ...`).

- The live site (after a deploy): no `--url` (it checks `qa.url`, or `site`). It waits by itself
  while a deploy runs, and does not judge a check that failed beside one.
- A build of this checkout: start the project's own preview (its `CLAUDE.md` or
  `.claude/ap/helper.md` says how), then `--url <its address>`.
- One change to one screen: narrow it, `--only <case> --langs <one>`.

Its exit code: 0 every check passed; 1 a check failed; 2 it could not run (its words say why: no
Playwright on this computer, then say the install line it printed to the owner; no cases; a
deploy that did not end); 3 off.

## 2. Judge the pictures

Open `<out>/index.html` (its last line says where) and read each picture against the project's
screen checklist (the doc its `CLAUDE.md` names for it; none: alignment, nothing covered or cut,
every text and button there, the theme right, and it makes sense). Compare one language with the
other, light with dark, Chromium with WebKit.

## 3. Record what it found

- A failed check or a bad picture is a bug: look for its issue first
  (`gh issue list --state all --search "<words>"`). There is one: comment on it with the check,
  the case (browser, language, theme) and the numbers. None: open one as `/ap:report` does
  (`${CLAUDE_PLUGIN_ROOT}/skills/report/SKILL.md`, Part 1).
- A failure that comes from a case itself (a wrong limit, a button it could not find) is a bug in
  the sweep, never ignored. In a run, or in the main checkout, never edit the cases there (a dirty
  main checkout makes `ap-deploy` and `ap-git-sync new-branch` refuse): open a `type:bug` issue for
  the case instead, and a helper fixes it on a branch. Fix it in place only on the owner's own
  branch, outside a run.
- `launch` (a browser did not start): say it in the reply. "Windows blocked WebKit": its cases did
  not run; they need another computer, or the browser allowed in Windows Security.
- **Not judged is not a pass.** Every check listed under `Not judged:` (orange in `index.html`)
  passed only because it could not be judged: a busy computer, or a deploy beside it. Name each
  one in the reply as not checked. A check of time or frames that failed on a busy computer: run
  that case again alone on a quiet computer (`--browsers <b> --langs <l> --themes <t> --only
  <case>`) before any issue. No quiet computer now: name it as not judged, never as a new issue.
- **In a run** (the manager runs it after a deploy): only when at most one helper runs; see
  "QA after a deploy" in section 4 of `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`. Each failure
  goes on its issue as above, and one line on the run issue: `QA after the deploy of <commit>: <n>
  checks, <f> failed, <t> not judged: <issues>`.

Reply in the `chat_language`: what passed, what failed, what was not judged, and where each one is
recorded. End with `Recorded: #<N> (<what>)`, or "nothing to record".
