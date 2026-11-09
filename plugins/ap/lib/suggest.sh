# shellcheck shell=bash
# This computer's free memory and disk, and what `ap-check --suggest` (for /ap:setup) suggests
# for merge_batch and queue_per_slot, from them and the check log. Loaded with `source` by
# ap-check (after lib/check-log.sh); it only defines functions.

free_mb() { # free memory in MB; 0 when it cannot be read
  if [ -r /proc/meminfo ]; then # Linux, and Git Bash on Windows
    awk '/^MemAvailable:/ {a = $2} /^MemFree:/ {f = $2} END {print int((a ? a : f) / 1024)}' /proc/meminfo 2>/dev/null || echo 0
  elif command -v vm_stat >/dev/null; then # macOS: free, inactive and speculative pages
    vm_stat 2>/dev/null | awk '/page size of/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) ps = $i}
      /^Pages (free|inactive|speculative):/ {n += $NF + 0} END {print int(n * ps / 1048576)}' || echo 0
  else
    echo 0
  fi
}

free_disk_mb() { # folder: the free space of its disk in MB; 0 when it cannot be read
  df -Pk "$1" 2>/dev/null | awk 'NR == 2 {print int($4 / 1024); found = 1} END {if (!found) print 0}'
}

tree_mb() { # folder: the size of what is in it in MB, its .git and .claude left out (a slot
  # worktree has neither: its git folder is the main checkout's, and its own .claude holds no build)
  local f files=()
  for f in "$1"/* "$1"/.[!.]*; do
    [ -e "$f" ] || continue
    case ${f##*/} in .git | .claude) continue ;; esac
    files+=("$f")
  done
  [ ${#files[@]} -gt 0 ] || { echo 0; return; }
  du -sk "${files[@]}" 2>/dev/null | awk '{s += $1} END {print int(s / 1024)}'
}

suggest_merge_batch() { # checks before a merge, how many did not pass: 1 when they fail often (1
  # in 10 or more): each failure in a batch costs checks of its halves; else 3
  if [ "$1" -gt 0 ] && [ $(($2 * 10)) -ge "$1" ]; then echo 1; else echo 3; fi
}

# The disk a queue needs: up to 3 slots (X3), each with one worktree per open issue, and the space
# a run keeps free: 5 GB, and 11 GB before it makes a new worktree.
suggest_queue() { # free memory MB, free disk MB, one built worktree MB, a helper's check s,
  # light_min_mb: 1 when the disk or the memory is short, 3 when both are plenty and the check is
  # long (10 minutes or more), else 2
  local mem=$1 disk=$2 wt=$3 secs=$4 light=$5
  if [ "$mem" -lt $((2 * light)) ] || [ "$disk" -lt $((5 * 1024 + 3 * 2 * wt)) ]; then echo 1
  elif [ "$mem" -ge $((4 * light)) ] && [ "$disk" -ge $((11 * 1024 + 3 * 3 * wt)) ] && [ "$secs" -ge 600 ]; then echo 3
  else echo 2
  fi
}

check_suggest() { # main checkout, light_min_mb: the facts, then `merge_batch: <n>` and
  # `queue_per_slot: <n>`, each with why
  local main=$1 light=$2 runs bad checks secs mem disk wt where=the\ main\ checkout q m f
  read -r runs bad checks secs < <(check_log_runs | awk -F'\t' '
    $1 == "merge" || $1 == "batch" { r++; if (!$3) b++ }
    $1 == "branch" { c++; s += $2 }
    END { printf "%d %d %d %d\n", r, b, c, c ? s / c : 0 }')
  m=$(suggest_merge_batch "$runs" "$bad")
  echo "checks before a merge in the log (merge turns and batches): $runs, not passed: $bad"
  if [ "$m" = 1 ]; then echo "merge_batch: 1 (they fail often: one merge at a time, each checked)"
  else echo "merge_batch: 3 (they seldom fail: 3 approved pull requests merged together, checked once)"
  fi
  for f in "$main"/.claude/worktrees/ap-*; do
    [ -d "$f" ] && { where=${f##*/}; break; }
  done
  if [ "$where" = "the main checkout" ]; then wt=$(tree_mb "$main"); else wt=$(tree_mb "$f"); fi
  mem=$(free_mb) disk=$(free_disk_mb "$main")
  if [ "$checks" = 0 ]; then checks="none in the log yet"; else checks="$secs s on average ($checks runs)"; fi
  echo "free memory: $mem MB; free disk: $disk MB; one built worktree: $wt MB ($where);" \
    "a helper's own check: $checks"
  q=$(suggest_queue "$mem" "$disk" "$wt" "$secs" "$light")
  case $q in
    1) echo "queue_per_slot: 1 (the disk or the memory is short for a second worktree in each slot)" ;;
    3) echo "queue_per_slot: 3 (memory and disk are plenty, and the check is long)" ;;
    *) echo "queue_per_slot: 2 (a second issue in each slot while the first one waits)" ;;
  esac
}
