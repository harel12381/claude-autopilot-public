---
name: stop-in
description: Use during an /ap:run run - stop the run at once when X minutes have passed (the same as typing STOP IN <X>)
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-git-sync:*), Bash(ap-run:*), Bash(ap-list:*), Bash(ap-brief:*), Bash(ap-notify:*), Bash(ap-config:*), Bash(ap-check-branch:*), Bash(ap-check:*), Bash(ap-batch:*), Bash(ap-deploy:*), Bash(ap-background:*), Bash(ap-qa:*), Bash(ap-bug-reports:*), Read, Write, Agent, SendMessage, TaskStop
---

# /ap:stop-in

Arguments: `$ARGUMENTS`

The owner wants the `/ap:run` run to stop in `$ARGUMENTS` minutes (`<X>`). The plain words `STOP IN <X>` do the same.

- **This session is the manager of an `/ap:run` run that has not ended:** do what the part
  "Stopping a run" of `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md` says for `STOP IN <X>`. Read it
  there; the rule lives only in that file.
- **No number in the arguments:** ask the owner for it in one line, in the `chat_language` of
  `.claude/ap.json`.
- **Otherwise** (no `/ap:run` run in this session, or it has ended): answer in one line, in the
  `chat_language` of `.claude/ap.json`, that no autopilot run is going on in this session, and
  do nothing else.
