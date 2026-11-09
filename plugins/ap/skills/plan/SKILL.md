---
name: plan
description: What a run would take - the issues /ap:run would work on with the same arguments, in its order, its groups, what it leaves out and why; it only reads and starts nothing
allowed-tools: Bash(ap-list:*), Bash(ap-config:*), Read
---

# /ap:plan

Arguments: `$ARGUMENTS`

The owner wants to see what a run would do before it starts: which issues, in which order, and
which ones it leaves out. **This command only reads: no helper, no run issue, no comment, no
label, no file changes.** To change the plan, the owner changes the issues (or the arguments) and
runs `/ap:plan` again; then `/ap:run` with the same arguments takes the same list.

## 1. The arguments

The same as `/ap:run` (the part "Which mode am I in?" of `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`).
Turn them into the options of `ap-list`, the one place the run's list is built (`/ap:run` reads
its lines, `/ap:plan` its plan with `--json`):

| Arguments | Option |
|---|---|
| issue numbers (`47 58`) | `47 58` |
| a kind (`bugs`, `features`, `tests`, `chores`) | `--label type:bug` (`type:feature`, `type:test`, `type:chore`) |
| a label limit (`only <label>`, `not <label>`) | as step 2 of `run` gives it: `--label <l>` (`<a>,<b>`: either one), `--not <l>` |
| `X<N>` (or `x<N>`) | `--parallel <N>` |
| `stop-after <N>` (`STOP AFTER <N>`) | `--stop-after <N>` |
| `stop-in <X>` (`STOP IN <X>`) | `--stop-in <X>` |

When `briefs.manager` in `.claude/ap.json` names a file that is there, read it: each label it
says a run leaves out goes in its own `--leave-out <label>`. Other words that limit the run
(`only size:S`): the run follows them, the plan cannot; say so in one line.

## 2. The list

```bash
ap-list --json <the options>
```

Exit 2: it says why (`/ap:setup` must run first, or gh could not list the issues); say that in
one line and stop.

## 3. The answer

In the owner's `chat_language` (`ap-config chat_language en`; GitHub's titles stay as they are).
Short lines, nothing the owner does not need now. The parts, in this order; skip an empty one:

1. **The order** (`order`): one line each, `<k>. #<number> <title> <priority> <size>`. A
   group of small issues (a list in `helpers` with more than one number) is one helper: say
   so on its first line. An issue with a `mark` (stopped in the middle, an approved look back, a
   named issue that is in progress or waits): add the mark.
2. **At the same time** (`rounds`, only with `X<N>`): one line per round, the helpers that
   could run together. Say that this is a guess: the real order follows which helper ends first.
3. **The stop:** `stop_after` (the issues that start before the stop, and the ones that do
   not), and `stop_in` (in the second half of the time, only these `size:S` issues start).
4. **Left out** (`left_out`): one line each, the issue and its `why` (waits for the owner, a
   phone check, blocked, in progress, an inbox note, later, not in the label limit, not open,
   stopped in the middle while another run goes on). Then the label limit (`label_limit`).

End with one line: before the first helper, the run's planner may still close duplicates and
split big issues, and leaves out an issue whose branch or pull request is already open; then
`/ap:run <the same arguments>` starts the run. Nothing else: no question,
no "Recorded:" line (nothing was written).
