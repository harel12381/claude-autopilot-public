---
name: features
description: Away mode for new features only - /ap:run with only the type:feature issues
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-git-sync:*), Bash(ap-run:*), Bash(ap-list:*), Bash(ap-brief:*), Bash(ap-notify:*), Bash(ap-config:*), Bash(ap-check-branch:*), Bash(ap-check:*), Bash(ap-batch:*), Bash(ap-deploy:*), Bash(ap-background:*), Bash(ap-qa:*), Bash(ap-bug-reports:*), Read, Write, Agent, SendMessage, TaskStop
---

# /ap:features

Arguments: `$ARGUMENTS`

Do all of `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`, as its manager, with the arguments
`features $ARGUMENTS` (only the `type:feature` issues: the part "Which mode am I in?" of
`${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`). Every other argument works as in `/ap:run`:
`/ap:features X3` (or `x3`) runs up to 3 helpers at once, and `/ap:features only area:app not size:L`
takes only the ones that also have `area:app` and not `size:L`.
