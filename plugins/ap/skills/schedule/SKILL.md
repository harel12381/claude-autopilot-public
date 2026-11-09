---
name: schedule
description: A run that starts by itself at a set time on this computer (for example every night at 2:00 with X2 stop-in 300) - set one up, list them, remove one, try one; the scheduled session starts the run
allowed-tools: Bash(ap-schedule:*), Bash(gh:*), Bash(git:*), Bash(ap-git-sync:*), Bash(ap-run:*), Bash(ap-list:*), Bash(ap-brief:*), Bash(ap-notify:*), Bash(ap-config:*), Bash(ap-check-branch:*), Bash(ap-check:*), Bash(ap-batch:*), Bash(ap-deploy:*), Bash(ap-background:*), Bash(ap-qa:*), Bash(ap-bug-reports:*), Read, Write, Agent, SendMessage, TaskStop
---

# /ap:schedule

Arguments: `$ARGUMENTS`

A scheduled run is `/ap:run` with set arguments, started at a set time by this computer's own
scheduler (Task Scheduler on Windows, cron on macOS and Linux). At that time the scheduler starts
a background Claude Code session in the main checkout (`claude --bg --permission-mode
bypassPermissions`), and that session runs `/ap:schedule fire <name>`. It costs nothing more than
the runs themselves: no service, no account. It works only while the computer is on, awake and
logged in, as for any away run.

`ap-schedule` does the work (how: the top of `ap-schedule`). Talk to the owner in their
`chat_language` (`ap-config chat_language en`).

## Which one?

| Arguments | What to do |
|---|---|
| empty, or `list` | **List** |
| `remove <name>` | **Remove** |
| `now <name>` | **Try it** |
| `fire <name>` | **The scheduled session** |
| a time, then run arguments (`every night at 2:00 X2 stop-in 300`) | **Set one up** |

## List

`ap-schedule list`: one line per schedule (its name, when, the run's arguments, whether the
scheduler still has its entry, its last start). Say it in short lines. An entry that is
`missing` was removed in the scheduler itself: `/ap:schedule <when> <arguments>` sets it again.

## Set one up

1. **When.** Turn the owner's words into a time `HH:MM` (24 hours, the computer's own time) and,
   when they name days, `--days` (`mon,tue,wed,thu,fri,sat,sun`; "weekdays" is
   `mon,tue,wed,thu,fri`; "every night" or "every day" is no `--days`). Words you cannot turn
   into these: ask once.
2. **The run's arguments**: the rest, as `/ap:run` takes them ("Which mode am I in?" in
   `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`). A run that should end before the owner is back
   needs a stop (`stop-in <minutes>`): when none is given, suggest one in a line.
3. **The name**: the owner's (`name nightly`), or a short one from the time (`nightly`,
   `weekdays-0200`): small letters, digits and `-`. The same name again replaces that schedule.
4. `ap-schedule add <name> --at <HH:MM> [--days <days>] -- <run arguments>`.
   Exit 1: it says why (no `claude` on the PATH, the scheduler refused); say that and stop.
5. Show the plan of such a run now, so the owner sees what it would take today:
   do `/ap:plan <run arguments>` (`${CLAUDE_PLUGIN_ROOT}/skills/plan/SKILL.md`), short.
6. **Tell the owner what only they can do**, in a few lines:
   - Leave the computer on and logged in at that time. On Windows, to wake it from sleep: Task
     Scheduler, the task `ap-<folder>-<hash>-<name>` (the name `add` printed), Properties,
     Conditions, "Wake the computer to run this task". A Windows task starts only on AC power
     and stops on battery unless that is turned off: `add` turns it off; when it says it could
     not, untick "Start the task only if the computer is on AC power" on the same tab. On a Mac,
     cron needs the computer awake (`pmset` can wake it).
   - The session runs in bypass permissions mode, as an away run must. Claude Code asks once
     before it allows that mode: run `claude --permission-mode bypassPermissions` in a terminal
     in this folder one time and accept, or the scheduled session waits for an answer.
   - Try it now: `/ap:schedule now <name>` starts it at once, as the scheduler would.

## Remove

`ap-schedule remove <name>`. Exit 1: no such schedule, or the scheduler did not remove the entry
(say its words).

## Try it

`ap-schedule now <name>` starts the session at once. Say that `claude agents` lists it and
`claude attach <id>` opens it; its first words are in the log the script names.

## The scheduled session

This session was started by the scheduler, and nobody watches it. Never ask the owner anything
here.

```bash
ap-schedule fire <name>
```

- **Exit 0:** it started the run: its first line is `run <id>`, its second the run's arguments.
  Do all of `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`, as its manager, with those arguments and
  that run id: never run `ap-run start` again (the check for another run and the start were one
  step, so two scheduled sessions never start two runs). In the run issue's body, say it was
  started by the schedule `<name>`. The run ends as every run does: the closing comment and the message to the
  owner's phone.
- **Exit 3: another run goes on** (its ids on stdout). Start nothing. Find its run issue
  (`gh issue list --state open --label tracking --search "[autopilot] in:title" --json number,url,body`,
  the one whose body names the id) and write one comment there: `The scheduled run <name> did not
  start at <time>: this run still goes on.` Then
  `ap-notify "<repo name>: scheduled run did not start" "<name>: another run goes on." <its url>`.
  End there.
- **Exit 1 or 2:** `ap-notify --high "<repo name>: scheduled run did not start" "<name>: <its words>"`,
  and end there.
