#!/usr/bin/env bash
# Checks the skills that only point to a part of another skill, so each rule lives in one place:
#   - every stop skill (stop, stopnow, stop-in, stop-after) and every kind skill (bugs, features,
#     tests, chores) names a file and a part of it (`the part "<heading>" of `<file>``), and the
#     file has a heading that is that part;
#   - they all run the run's steps, so their `allowed-tools` line is the same as `run`'s;
#   - every script an `allowed-tools` line names (`Bash(ap-<name>:*)`) is in bin/;
#   - status and plan only read: their `allowed-tools` runs ap-status (plan: ap-list) and has no
#     tool that writes, starts an agent, or runs gh, git, ap-run or ap-schedule itself;
#   - the run's list lives in one place: run's step 2 and plan both build it with ap-list;
#   - schedule (its scheduled session does the run) allows every tool of run, and ap-schedule;
#   - the command table of README.md lists every skill folder (`/ap:<name>`);
#   - every `<WORD>` of a brief is named in CONTRACT.md (brief-test checks that ap-brief fills
#     each in), `<BOARD>` stands alone on its line (ap-brief drops the line when there is no board), and
#     no brief writes `#<LIST>` (its value has the `#` already);
#   - the labels table of setup has the same names as the label list of CONTRACT.md;
#   - qa, phone-check and bug-reports each check their part in .claude/ap.json and say when it is
#     off; the run does the QA sweep only with at most one helper running, and the reports before
#     its planner; bug-reports starts its judges side by side, at most 5, only as the read-only
#     ap:reader agent, whose tools are Read, Grep and Glob and nothing more;
#   - the .claude/ap.json examples of CONTRACT.md and setup have the same top-level keys, and run's
#     settings table names merge_batch and queue_per_slot;
#   - every `ap-run <command>` and `ap-batch <command>` that run and the briefs name is a command
#     of that script (its usage line);
#   - each helper holds one issue: no brief, run or CONTRACT.md tells a helper to take a second
#     issue (`QUEUE #`, `GO ON with`, `Your queue:`, `working #`), and run gives a queued issue
#     to a fresh helper.
#
#   bash tests/skills-test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLUGIN=$ROOT/plugins/ap
SKILLS=$PLUGIN/skills
FAILED=0
fail() { echo "skills-test: $*" >&2; FAILED=1; }
tools() { grep -m1 '^allowed-tools:' "$1"; }

run_tools=$(tools "$SKILLS/run/SKILL.md") || { echo "skills-test: run has no allowed-tools line" >&2; exit 1; }

for s in stop stopnow stop-in stop-after bugs features tests chores; do
  f=$SKILLS/$s/SKILL.md
  [ -f "$f" ] || { fail "no skill $s ($f)"; continue; }
  # Each pointer: the part "<heading>" of `<file>`, maybe over two lines.
  pointers=$(tr -s '\n ' '  ' <"$f" | grep -oE 'the part "[^"]+" of `[^`]+`' || true)
  [ -n "$pointers" ] || fail "$s points to no part of another file"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    part=$(sed -E 's/the part "([^"]+)".*/\1/' <<<"$p")
    file=$(sed -E 's/.*`([^`]+)`/\1/' <<<"$p")
    file=${file//'${CLAUDE_PLUGIN_ROOT}'/$PLUGIN}
    [ -f "$file" ] || { fail "$s points to $file, which is not there"; continue; }
    # A heading that is the part, or starts with it and a space.
    awk -v p="$part" 'sub(/^#+ /, "") && ($0 == p || index($0, p " ") == 1) { f = 1 } END { exit !f }' "$file" ||
      fail "$s points to the part \"$part\" of $file, which has no such heading"
  done <<<"$pointers"
  [ "$(tools "$f")" = "$run_tools" ] || fail "$s does not allow the same tools as run"
done

for f in "$SKILLS"/*/SKILL.md; do
  for script in $(tools "$f" | grep -oE 'Bash\(ap-[a-z-]+' | cut -c6-); do
    [ -x "$PLUGIN/bin/$script" ] || fail "$(basename "$(dirname "$f")") allows $script, which is not in bin/"
  done
done

for s in status:ap-status plan:ap-list; do
  read_tools=$(tools "$SKILLS/${s%%:*}/SKILL.md") || { fail "${s%%:*} has no allowed-tools line"; continue; }
  [[ $read_tools == *"Bash(${s#*:}:*)"* ]] || fail "${s%%:*} does not allow ${s#*:}"
  for t in Write Edit NotebookEdit Agent SendMessage TaskStop 'Bash(ap-notify' 'Bash(ap-git-sync' 'Bash(ap-deploy' \
    'Bash(ap-run' 'Bash(ap-schedule' 'Bash(gh:' 'Bash(git:'; do
    [[ $read_tools != *"$t"* ]] || fail "${s%%:*} only reads, but allows $t"
  done
done

# The run's list is built in one place: run's step 2 and plan both take it from ap-list.
sed -n '/^## 2. The list/,/^## /p' "$SKILLS/run/SKILL.md" | grep -q '^ap-list ' ||
  fail "run's step 2 does not build the list with ap-list"
grep -q '^ap-list --json' "$SKILLS/plan/SKILL.md" || fail "plan does not build the list with ap-list --json"

# The scheduled session runs the run's steps: schedule allows every tool of run, and ap-schedule.
schedule_tools=$(tools "$SKILLS/schedule/SKILL.md") || fail "schedule has no allowed-tools line"
for t in $(sed 's/^allowed-tools: //' <<<"$run_tools" | tr -d ','); do
  [[ " ${schedule_tools//,/} " == *" $t "* ]] || fail "schedule runs the run, but does not allow $t"
done
[[ $schedule_tools == *"Bash(ap-schedule:*)"* ]] || fail "schedule does not allow ap-schedule"

# README's command table: the rows that start with | and name a command.
table=$(grep -E '^\| `/ap:' "$ROOT/README.md" || true)
for d in "$SKILLS"/*/; do
  s=$(basename "$d")
  grep -qE "\`/ap:$s( [^\`]*)?\`" <<<"$table" || fail "README's command table does not list /ap:$s"
done

# The briefs' fill-in words.
contract_briefs=$(sed -n '/^## The briefs/,/^## /p' "$ROOT/CONTRACT.md")
for b in "$PLUGIN"/briefs/*.md; do
  name=$(basename "$b")
  # Two letters or more: one-letter words (<M>) are the agent's own, not the manager's.
  for w in $(grep -oE '<[A-Z][A-Z_]+>' "$b" | sort -u); do
    grep -qF -- "\`$w\`" <<<"$contract_briefs" || fail "$name uses $w, which CONTRACT.md does not name"
  done
  if grep -n '<BOARD>' "$b" | grep -vqE '^[0-9]+:<BOARD>$'; then
    fail "$name has <BOARD> inside a line; it must stand alone on its own line"
  fi
  grep -q '#<LIST>' "$b" && fail "$name writes #<LIST>; <LIST> has its # already"
done

# The settings: the top-level keys of the .claude/ap.json examples in CONTRACT.md and in setup.
example_keys() { # file, heading: the top-level keys of the first ```json block after the heading
  sed -n "/^## $2/,\$p" "$1" | sed -n '/^```json/,/^```$/p' | sed '1d;/^```$/,$d' |
    python -c 'import json, sys; print("\n".join(sorted(json.load(sys.stdin))))' 2>&1 ||
    echo "no JSON example after '$2' in $1"
}
contract_keys=$(example_keys "$ROOT/CONTRACT.md" "The project's settings")
setup_keys=$(example_keys "$SKILLS/setup/SKILL.md" "The project's settings")
[ "$contract_keys" = "$setup_keys" ] ||
  fail "the keys of the ap.json examples in CONTRACT.md and setup differ: $(diff <(echo "$contract_keys") <(echo "$setup_keys") | grep -E '^[<>]' | tr '\n' ' ')"
for k in merge_batch queue_per_slot; do
  sed -n '/^## 0\./,/^## /p' "$SKILLS/run/SKILL.md" | grep -q "^| \`$k\` |" || fail "run's settings table does not name $k"
done

# Every command of ap-run and ap-batch that run and the briefs name is one the script has (its
# usage line).
for script in ap-run ap-batch; do
  usage=$(cd "$ROOT" && bash "$PLUGIN/bin/$script" 2>&1 >/dev/null </dev/null | tr -d '\n' || true)
  for c in $(cat "$SKILLS/run/SKILL.md" "$PLUGIN"/briefs/*.md | grep -oE "\`$script [a-z-]+" | cut -d' ' -f2 | sort -u); do
    [[ $usage =~ (^|[ |])$c( |$) ]] || fail "run or a brief names \`$script $c\`, which is not a command of $script ($usage)"
  done
done

# Each helper holds one issue: a queued issue goes to a fresh helper, never to one that has an
# issue already.
for f in "$PLUGIN"/briefs/*.md "$SKILLS/run/SKILL.md" "$ROOT/CONTRACT.md"; do
  second=$(grep -nE 'QUEUE #|GO ON with|Your queue:|working #' "$f" | head -1)
  [ -z "$second" ] || fail "$(basename "$f") tells a helper to take a second issue: $second"
done
sed -n '/^\*\*A queue per slot\*\*/,/^\*\*Before each new helper/p' "$SKILLS/run/SKILL.md" | tr -s '\n ' '  ' |
  grep -q 'always goes to a fresh helper' || fail "run's \"A queue per slot\" does not give a queued issue to a fresh helper"

# The labels: CONTRACT.md's list (up to "The owner's name") and setup's table.
contract_labels=$(sed -n '/^## The labels/,/^## /p' "$ROOT/CONTRACT.md" | tr '\n' ' ' |
  sed -E "s/The owner's name.*//" | grep -oE '`[^`]+`' | tr -d '`' | grep -v '[*/]' | sort)
setup_labels=$(sed -n '/^## 4. The labels/,/^## /p' "$SKILLS/setup/SKILL.md" |
  grep -E '^\| `' | cut -d'|' -f2 | tr -d '` ' | sort)
[ -n "$contract_labels" ] || fail "CONTRACT.md lists no labels"
[ "$contract_labels" = "$setup_labels" ] ||
  fail "setup's labels table and CONTRACT.md's label list differ: $(diff <(echo "$contract_labels") <(echo "$setup_labels") | grep -E '^[<>]' | tr '\n' ' ')"

# The parts that are off until setup turns them on.
for s in qa:parts.qa phone-check:parts.phone_check bug-reports:parts.bug_reports; do
  f=$SKILLS/${s%%:*}/SKILL.md
  [ -f "$f" ] || { fail "no skill ${s%%:*}"; continue; }
  text=$(tr -s '
 ' '  ' <"$f")
  [[ $text == *"\`${s#*:}\`"* && $text == *"is off in this project"* ]] || fail "${s%%:*} does not say when ${s#*:} is off"
done
run_text=$(tr -s '
 ' '  ' <"$SKILLS/run/SKILL.md")
[[ $run_text == *"QA after a deploy"*"only when at most one helper runs"* ]] || fail "run does not keep the QA sweep to at most one helper"
[[ $run_text == *"skills/bug-reports/SKILL.md"* ]] || fail "run does not do the users' reports"
reports=$(tr -s '
 ' '  ' <"$SKILLS/bug-reports/SKILL.md")
[[ $reports == *"at most 5 at a time"* ]] || fail "bug-reports does not start its judges side by side, at most 5"
grep -q 'subagent_type: ap:reader' "$SKILLS/bug-reports/SKILL.md" || fail "bug-reports does not start the ap:reader agent"
grep -q 'general-purpose' "$SKILLS/bug-reports/SKILL.md" && fail "bug-reports names a general-purpose agent"
[ "$(grep -m1 '^tools:' "$PLUGIN/agents/reader.md")" = "tools: Read, Grep, Glob" ] || fail "the reader agent may do more than read"

[ "$FAILED" = 0 ] && echo "skills: ok"
exit "$FAILED"
