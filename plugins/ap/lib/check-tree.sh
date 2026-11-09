# shellcheck shell=bash
# The check worktrees of ap-check-branch and ap-batch: <main checkout>/.claude/worktrees/check-*,
# folders of their own, detached at a commit, so the main checkout stays on its branch. Loaded
# with `source` after hooks.sh and proc-tree.sh; it only defines functions. Their lines start with
# the script's name.

check_tree_remove() { # main checkout, folder: removes the check worktree, as a worktree and as a
  # folder; 1 (and a line saying why) when the folder is still there. Before it deletes the folder,
  # it stops the build and test tools that still run in it (stop_folder_users), as `ap-run end`
  # does. Nothing in it fails: it also runs from an EXIT trap.
  local who by me=${0##*/}
  git -C "$1" worktree remove --force "$2" >/dev/null 2>&1 || true
  git -C "$1" worktree prune || true
  [ -e "$2" ] || return 0
  who=$(stop_folder_users "$2")
  if grep -q '^stopped ' <<<"$who"; then
    echo "$me: stopped what still ran in ${2##*/}: $(sed -n 's/^stopped //p' <<<"$who" | paste -sd, -)"
    sleep 2 # Windows lets go of their files a moment later
  fi
  rm -rf "$2" 2>/dev/null || true
  [ -e "$2" ] || return 0
  by=$(sed -n 's/^left //p' <<<"$who" | paste -sd, -)
  echo "$me: could not delete the folder $2: a file in it is still in use${by:+ (by $by)}" >&2
  return 1
}

check_tree_make() { # main checkout, folder, commit: a fresh worktree there, detached at the
  # commit. A folder of that name that is still there (a check that a stop or a closed session
  # cut off) is removed first. 1 (and a line saying why) when it could not.
  local me=${0##*/}
  if [ -e "$2" ]; then
    echo "$me: removing the folder ${2##*/} that an earlier check left"
    check_tree_remove "$1" "$2" || { echo "$me: the check did not run: stop what holds $2, then run it again" >&2; return 1; }
  fi
  git -C "$1" worktree add -q --detach "$2" "$3" || { echo "$me: could not make the worktree $2" >&2; return 1; }
}

check_tree_run() { # folder, setup command (may be empty), check command, what is checked (for
  # its line): hooks.check_setup, then the check, in the folder. The check's exit code; 91 when
  # the setup failed, and then the check did not run (CHECK_TREE_SETUP_FAILED is 1 then, else 0:
  # the check itself may exit 91 too).
  local rc=0
  CHECK_TREE_SETUP_FAILED=0
  if [ -n "$2" ]; then
    hook_run "$2" "$1" || rc=$?
    [ $rc = 0 ] || { echo "${0##*/}: $4: hooks.check_setup failed (exit $rc): the check did not run"; CHECK_TREE_SETUP_FAILED=1; return 91; }
  fi
  hook_run "$3" "$1" || rc=$?
  return $rc
}
