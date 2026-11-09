---
name: waiting-all
description: Like /ap:waiting, but also the issues the owner skipped before (status:later)
allowed-tools: Bash(gh:*), Bash(git:*), Bash(ap-config:*), Read, Grep, Glob, Edit, Write, AskUserQuestion
---

# /ap:waiting-all

Arguments: `$ARGUMENTS`

Read `${CLAUDE_PLUGIN_ROOT}/skills/waiting/SKILL.md` and follow it in the **`all`** mode: every
issue with `status:waiting-for-owner`, including the ones the owner skipped before
(`status:later`), which come last. An answer removes `status:later` too; another "skip" leaves it
on.
