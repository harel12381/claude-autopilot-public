# shellcheck shell=bash
# The log of ap-check: one line per part of every run, passed or not, in the repository's common
# .git folder (ap-check-log.tsv), so every worktree writes to the same file. Loaded with `source`
# by ap-check, which writes it; `ap-check --stats` prints its summary. A run stopped before its
# end (its shell gone, Ctrl-C) adds no line.
#
# A line has these fields, split by tabs (new fields only ever go at the end):
#   1  time     when the run ended, local time with its offset (2026-11-01T10:20:30+0200)
#   2  part     the part's name
#   3  result   passed; failed; skipped (passed before, or in another run while this one waited);
#               hung (a step ran past its time limit and was stopped)
#   4  took     seconds its steps ran
#   5  waited   seconds it waited for other runs' locks
#   6  again    retry (its retry command ran in place of a step that failed), or -
#   7  kind     merge (HEAD merges the main branch into a branch: the check at a merge turn); main
#               (HEAD is a commit of the main branch: a deploy, or the main checkout); branch
#               (anything else: a helper's own check); fresh (the manager's check of a branch in a
#               folder of its own, ap-check-branch); batch (the check of a batch of pull
#               requests, ap-batch); bisect (a check ap-batch runs to find which pull request of a
#               batch breaks it). AP_CHECK_KIND sets fresh, batch or bisect; the others are found.
#   8  branch   the branch, or - (a detached HEAD)
#   9  commit   HEAD, its first 10 characters
#   10 dirty    1 when the tree checked has changes that are not committed, else 0
#   11 worktree the checkout's folder name
#   12 run      this run's id: the lines of one run share it
#   13 run_s    seconds the whole run took, from its start to its end
#   14 flags    force when given, or -
#   15 batch    batch and bisect: how many pull requests the checked tree merges (AP_CHECK_BATCH);
#               else -
#   16 others   in a slot worktree (ap-<s>, or ap-<s>b of its queue): how many issues were open in
#               the slot's other worktrees (the issue-<s> files of ap-run); else -. A check with
#               others above 0 ran while its slot had another issue open.
# Lines written before fields 15 and 16 have 14 fields: they read as -.

CHECK_LOG=ap-check-log.tsv # in the common .git folder

check_log_line() { # fields 1 to 16: one line of the log
  local IFS=$'\t'
  echo "$*"
}

check_log_run() { # tree checked, force (0|1), main branch: sets CHECK_LOG_RUN (fields 7 to 12),
  # CHECK_LOG_FLAGS (14) and CHECK_LOG_MORE (15 and 16)
  local commit tree branch dirty=0 kind batch=-
  { read -r commit; read -r tree; read -r branch; } < <(git rev-parse HEAD 'HEAD^{tree}' --abbrev-ref HEAD 2>/dev/null)
  [ "${branch:-HEAD}" != HEAD ] || branch=-
  [ "$1" = "${tree:-}" ] || dirty=1
  case ${AP_CHECK_KIND:-} in
    fresh) kind=fresh ;;
    batch | bisect) kind=$AP_CHECK_KIND
      [[ ${AP_CHECK_BATCH:-} =~ ^[0-9]+$ ]] && batch=$AP_CHECK_BATCH ;;
    *) kind=$(check_log_kind "$branch" "$3") ;;
  esac
  CHECK_LOG_RUN=("$kind" "$branch" "${commit:0:10}" $dirty "${ROOT##*/}" "$EPOCHSECONDS-$$")
  CHECK_LOG_FLAGS=-
  [ "$2" = 0 ] || CHECK_LOG_FLAGS=force
  CHECK_LOG_MORE=("$batch" "$(check_log_others)")
}

check_log_others() { # field 16: the issues open in the other worktrees of this slot, or -
  local me=${ROOT##*/} f n=0
  [[ $me =~ ^ap-([0-9]+)[b-z]?$ ]] || { echo -; return; }
  for f in "$COMMON/ap-autopilot/issue-${BASH_REMATCH[1]}" "$COMMON/ap-autopilot/issue-${BASH_REMATCH[1]}"[b-z]; do
    [ -f "$f" ] && [ "ap-${f##*/issue-}" != "$me" ] && n=$((n + 1))
  done
  echo $n
}

check_log_kind() { # branch, main branch: merge, main or branch (field 7)
  local c base
  if [ "$1" = "$2" ] || [ "$1" = - ]; then c=HEAD
  elif git rev-parse -q --verify 'HEAD^2' >/dev/null; then c='HEAD^2'
  else echo branch; return
  fi
  # The local main branch may be ahead of the last fetch, or behind it.
  for base in "origin/$2" "$2"; do
    if git merge-base --is-ancestor "$c" "$base" 2>/dev/null; then
      [ "$c" = HEAD ] && echo main || echo merge
      return
    fi
  done
  echo branch
}

check_log_times() { # a part's .secs file ("took|waited <seconds>" lines): sets CHECK_LOG_TOOK and CHECK_LOG_WAITED
  local what s
  CHECK_LOG_TOOK=0 CHECK_LOG_WAITED=0
  [ -f "$1" ] || return 0
  while read -r what s; do
    case $what in
      took) CHECK_LOG_TOOK=$((CHECK_LOG_TOOK + s)) ;;
      waited) CHECK_LOG_WAITED=$((CHECK_LOG_WAITED + s)) ;;
    esac
  done <"$1"
}

check_log_runs() { # [since]: one line per whole run of the log (the parts that ran in it, not
  # the skipped ones), split by tabs: kind, run_s, passed (1 when every part that ran passed),
  # batch, others. A line with fewer than 14 fields is a broken one (two runs that wrote at the
  # same moment): left out.
  local log; log=$(git rev-parse --path-format=absolute --git-common-dir)/$CHECK_LOG || return 2
  [ -s "$log" ] || return 0
  awk -F'\t' -v since="${1:-}" '
    NF < 14 || $1 "" < since "" || $3 == "skipped" { next }
    {
      r = $12; if (!(r in kind)) order[++n] = r
      kind[r] = $7; secs[r] = $13; batch[r] = $15 == "" ? "-" : $15; others[r] = $16 == "" ? "-" : $16
      if ($3 != "passed") bad[r] = 1
    }
    END { for (i = 1; i <= n; i++) { r = order[i]; printf "%s\t%s\t%d\t%s\t%s\n", kind[r], secs[r], !(r in bad), batch[r], others[r] } }' "$log"
}

check_log_stats() { # [since: a date or time, as in field 1]: the summary of the log, per part and
  # kind, and the time that merges in batches and the queues saved
  local log; log=$(git rev-parse --path-format=absolute --git-common-dir)/$CHECK_LOG || return 2
  [[ ${1:-2000-01-01} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || { echo "ap-check --stats: since a date like 2026-11-01, not $1" >&2; return 2; }
  [ -s "$log" ] || { echo "No checks in the log yet ($log)."; return 0; }
  awk -F'\t' -v since="${1:-}" '
    NF < 14 || $1 "" < since "" { next }
    {
      k = $2 "\t" $7; keys[k] = 1
      if ($3 == "skipped") { skip[k]++; next }
      runs[k]++; took[k] += $4; waited[k] += $5
      if ($3 == "failed") fail[k]++
      else if ($3 == "hung") hung[k]++
      if ($6 != "-") again[k]++
    }
    END {
      printf "%-12s %-8s %5s %7s %5s %6s %8s %6s %7s\n", "part", "kind", "runs", "failed", "hung", "again", "skipped", "avg s", "wait s"
      sort = "sort"
      for (k in keys) {
        split(k, pk, "\t")
        printf "%-12s %-8s %5d %7d %5d %6d %8d %6d %7d\n", pk[1], pk[2], runs[k], fail[k], hung[k], again[k], skip[k],
          runs[k] ? took[k] / runs[k] : 0, runs[k] ? waited[k] / runs[k] : 0 | sort
      }
      close(sort)
    }' "$log"
  echo
  # The whole runs since the date, then the merge-turn checks of the whole log: what one merge
  # cost, to compare a batch with when no merge-turn check ran since the date.
  { check_log_runs "${1:-}"; echo "@@ all"; check_log_runs | awk -F'\t' '$1 == "merge"'; } | awk -F'\t' '
    $0 == "@@ all" { all = 1; next }
    all { am++; as += $2; next }
    { kr[$1]++; ks[$1] += $2; if (!$3) kb[$1]++ }
    $1 == "batch" { batches++; prs += $4; bs += $2; bchecks++ }
    $1 == "bisect" { bisects++; bs += $2; bchecks++ }
    $5 ~ /^[0-9]+$/ && $5 > 0 { queued++; qs += $2 }
    END {
      printf "%-8s %5s %10s %6s\n", "kind", "runs", "not passed", "avg s"
      split("branch fresh merge main batch bisect", kinds, " ")
      for (i = 1; i <= 6; i++) if ((k = kinds[i]) in kr) printf "%-8s %5d %10d %6d\n", k, kr[k], kb[k], ks[k] / kr[k]
      print ""
      print "Time saved:"
      if (!batches) print "  merges in batches: none"
      else {
        if (kr["merge"]) { m = ks["merge"] / kr["merge"]; from = "since then" }
        else if (am) { m = as / am; from = "in the whole log" }
        line = sprintf("  merges in batches: %d pull requests in %d batches, %d checks (%d to find which one broke a batch), %d s", prs, batches, bchecks, bisects, bs)
        if (m) printf "%s; a merge-turn check for each (%d s on average, %s) takes %d s: saved about %d min\n", line, m, from, prs * m, (prs * m - bs) / 60
        else printf "%s; no merge-turn check in the log to compare with\n", line
      }
      if (!queued) print "  the queues: no check ran while its slot had another issue open"
      else printf "  the queues: %d checks (%d s) ran while their slot had another issue open: saved at least %d min\n", queued, qs, qs / 60
    }'
  echo
  echo "failed: the code or a setup step; hung: a step ran past its time limit; again: its retry ran;"
  echo "runs of a whole ap-check count only the parts that ran; not passed: one of its parts did not pass."
}
