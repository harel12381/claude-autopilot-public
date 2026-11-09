# shellcheck shell=bash
# Stopping a process with everything it started, on Windows too, and telling whether a process
# still runs (pid_runs). Loaded with `source` by the ap-* scripts and lib/dirlock.sh; it only
# defines functions and the PowerShell texts below.
#
# On Windows, Git Bash's `kill` ends a Git Bash process, not the native programs under it (a
# compiler, a test runner, a Python server): they keep running, with their memory and their
# ports. So stop_tree stops each native program with `taskkill /T`, which takes its own children
# too.

# The build and test tools (program names, without .exe) that may be stopped when they still run
# in a folder that is removed (stop_folder_users). Any other program there is only named: it may
# be an editor. Add to the list here, or for one project with AP_PROC_TOOLS (names with spaces
# between them).
PROC_TOOLS="dart dartvm dartaotruntime flutter_tester cargo rustc go node npm npx deno bun
  python python3 pytest dotnet msbuild ${AP_PROC_TOOLS:-}"

pid_runs() { # pid: true while the process runs. A process that ended but was not yet reaped (a
  # zombie: its parent has not read its exit code) is still there for `kill -0`, and does not run.
  # Its state letter is Z: in /proc/<pid>/stat after the name in brackets on Linux, in ps on macOS.
  # Git Bash shows Z for a moment while a process starts another program, and leaves no orphan
  # unreaped: `kill -0` alone there.
  local s
  kill -0 "$1" 2>/dev/null || return 1
  if [ -r /proc/self/winpid ]; then return 0
  elif [ -r /proc/self/stat ]; then
    read -r s 2>/dev/null <"/proc/$1/stat" || [ -n "${s:-}" ] || return 1
    s=${s##*) }
  else
    s=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
    s=${s//[[:space:]]/}
  fi
  [ "${s:0:1}" != Z ]
}

tree_under() { # pid, skip: "pid winpid" for it and every process under it, but skip and its own.
  # winpid is 0 for a Git Bash process.
  local rows
  # Git Bash is told by this shell's own process, not by pid's, which may be gone already (its
  # ps has no -o).
  if [ -r /proc/self/winpid ]; then # Git Bash: ps -l prints PID PPID PGID WINPID ... COMMAND
    rows=$(ps -l | awk 'NR > 1 { if ($1 !~ /^[0-9]+$/) { $1 = ""; $0 = $0 }
      print $1, $2, ($0 ~ / \/usr\//) ? 0 : $4 }')
  else
    rows=$(ps -eo pid=,ppid= | awk '{print $1, $2, 0}')
  fi
  awk -v root="$1" -v skip="$2" '{ kids[$2] = kids[$2] " " $1; win[$1] = $3 }
    END { todo[n = 1] = root
      for (i = 1; i <= n; i++) { p = todo[i]; if (p == skip) continue; print p, win[p]
        k = split(kids[p], a, " "); for (j = 1; j <= k; j++) todo[++n] = a[j] } }' <<<"$rows"
}

stop_tree() { # pid: stops it and every process under it, but the process that calls this
  local pid win me=$BASHPID # here: inside <( ) it would be that subshell's id
  # A native Windows program with its own children: taskkill /T. The Git Bash processes by their
  # own ids: their Windows parents are fork stubs, not the bash above.
  while read -r pid win; do
    [ "${win:-0}" = 0 ] || taskkill //F //T //PID "$win" >/dev/null 2>&1
    kill -9 "$pid" 2>/dev/null
  done < <(tree_under "$1" "$me")
}

# The start of every PowerShell script that looks at the Windows processes and stops some of them:
#   - $all: every process by its id. A list that cannot be read, or that lacks this PowerShell
#     itself (so it is no full process list), ends the script with an error: an empty list would
#     make every process look gone;
#   - $self: this PowerShell and the processes it runs under, which Each-Oldest always skips;
#   - Top p name: p followed up through its parents while their program name matches name. A
#     parent that started after its child is another process with a reused id: not followed;
#   - Each-Oldest procs do: runs do on each process that still runs and is not in $self, the
#     oldest first, so that one stopped with its tree takes the younger ones in it along, and
#     those are then skipped;
#   - Stop-Tree p: stops p with every process under it.
# An error ends the script, so a rule that cannot be built never stops processes by a wrong one;
# only inside Each-Oldest it does not, so that one process that cannot be stopped does not keep
# the others running.
# shellcheck disable=SC2016 # PowerShell's $ in single quotes
PROC_TABLE_PS='
$ErrorActionPreference = "Stop"
$all = @{}
Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine, ExecutablePath, CreationDate |
  ForEach-Object { $all[[int]$_.ProcessId] = $_ }
if (-not $all[$PID]) { throw "the process list lacks this PowerShell" }
$self = @{}
for ($p = $all[$PID]; $p -and -not $self[[int]$p.ProcessId]; $p = $all[[int]$p.ParentProcessId]) { $self[[int]$p.ProcessId] = 1 }
function Top($p, $name) {
  while ($true) {
    $up = $all[[int]$p.ParentProcessId]
    if ($up -and -not $self[[int]$up.ProcessId] -and $up.CreationDate -le $p.CreationDate -and
        $up.Name -match $name) { $p = $up } else { return $p }
  }
}
function Each-Oldest($procs, [scriptblock]$do) {
  $ErrorActionPreference = "Continue"
  foreach ($p in @($procs | Where-Object { $_ -and -not $self[[int]$_.ProcessId] } | Sort-Object ProcessId -Unique | Sort-Object CreationDate)) {
    if (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue) { & $do $p }
  }
}
function Stop-Tree($p) { cmd /c "taskkill /PID $($p.ProcessId) /T /F >nul 2>&1" }
'
proc_ps() { # script: runs PROC_TABLE_PS and then script in PowerShell, and prints its output
  # without \r. At most 60 s: WMI can be slow when memory is short. Its exit code: PowerShell's,
  # also in a shell without pipefail.
  local out rc=0
  out=$(timeout 60 powershell.exe -NoProfile -NonInteractive -Command "$PROC_TABLE_PS$1") || rc=$?
  [ -z "$out" ] || printf '%s\n' "${out//$'\r'/}"
  return $rc
}

# The processes that may hold files in a folder, so it can be deleted: Windows does not delete a
# file in use. Windows does not say who holds a file without extra tools, so these are the
# processes whose command line or program names the folder, each followed up through the build
# and test tools it runs under (a test driver runs in the folder, and only its test programs name
# it). A build or test tool (PROC_TOOLS) or a program in the folder is stopped with its tree; any
# other (an editor, a shell) is only named. One line each, the oldest first: "stopped <pid>
# <name>" or "left <pid> <name>". Never the PowerShell that looks, or the processes it runs
# under. Elsewhere nothing: a file in use can be deleted there.
# shellcheck disable=SC2016 # PowerShell's $ in single quotes
FOLDER_USERS_PS='
if (-not ($env:FU_W -and $env:FU_M -and $env:FU_U -and $env:FU_TOOLS)) { throw "no folder" } # it would match every process
$forms = @($env:FU_W, $env:FU_M, $env:FU_U) | ForEach-Object { [regex]::Escape($_) }
$in = "(?im)(" + ($forms -join "|") + ")([\\/`"'"'"' ]|$)" # the folder itself, not ap-1 in ap-10
$tool = "(?i)^(" + $env:FU_TOOLS + ")[.]exe$"
$found = @{}
foreach ($p in @($all.Values)) {
  if ($self[[int]$p.ProcessId] -or "$($p.CommandLine)`n$($p.ExecutablePath)" -notmatch $in) { continue }
  $p = Top $p $tool
  $found[[int]$p.ProcessId] = $p
}
Each-Oldest $found.Values {
  param($p)
  if ($p.Name -match $tool -or "$($p.ExecutablePath)" -match $in) {
    Stop-Tree $p
    "stopped {0} {1}" -f $p.ProcessId, $p.Name
  } else { "left {0} {1}" -f $p.ProcessId, $p.Name }
}'
proc_tools_regex() { # PROC_TOOLS as one regex: "dart|cargo|..." (a dot in a name is a dot)
  local n out=
  for n in $PROC_TOOLS; do out+="${out:+|}${n//./[.]}"; done
  printf '%s\n' "$out"
}
stop_folder_users() { # folder: see above
  command -v powershell.exe >/dev/null && command -v cygpath >/dev/null || return 0
  FU_W=$(cygpath -w "$1") FU_M=$(cygpath -m "$1") FU_U=$(cygpath -u "$1") FU_TOOLS=$(proc_tools_regex) \
    proc_ps "$FOLDER_USERS_PS" || true
}

wait_shell_gone() { # shell, main, seconds: returns 0 once shell is gone while main still runs,
  # 1 once main ended. Looks every few seconds rather than one long sleep, whose output would keep
  # main's output open.
  while pid_runs "$1"; do
    pid_runs "$2" || return 1
    sleep "$3" </dev/null >/dev/null 2>&1
  done
  pid_runs "$2" # it may have ended meanwhile
}
