---
name: stopnow
description: Use during an /ap:run run - stop every helper at once and end the run (the same as typing STOPNOW)
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-git-sync:*), Bash(ap-run:*), Bash(ap-list:*), Bash(ap-brief:*), Bash(ap-notify:*), Bash(ap-config:*), Bash(ap-check-branch:*), Bash(ap-check:*), Bash(ap-batch:*), Bash(ap-deploy:*), Bash(ap-background:*), Bash(ap-qa:*), Bash(ap-bug-reports:*), Read, Write, Agent, SendMessage, TaskStop
---

# /ap:stopnow

The owner sent `STOPNOW` to the `/ap:run` run. The plain words `STOPNOW` do the same.

- **This session is the manager of an `/ap:run` run that has not ended:** do what the part
  "Stopping a run" of `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md` says for `STOPNOW`. Read it
  there; the rule lives only in that file.
- **Otherwise** (no `/ap:run` run in this session, or it has ended): answer in one line, in the
  `chat_language` of `.claude/ap.json`, that no autopilot run is going on in this session, and
  do nothing else.
