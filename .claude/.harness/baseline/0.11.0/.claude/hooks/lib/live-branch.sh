#!/usr/bin/env bash
# The branch a session is working on, read off live git state — sourced by
# `session-close.sh` (task id of the auto-close record + `session_closed`) and
# `init.sh` (the parked-branch nudge). The TS twin is `readLiveBranch`
# (`src/status/live-branch.ts`, `lemony status`); `live-branch.spec.ts` runs
# both against the same real repositories.
#
# `live_branch <repo-root>` prints the branch name (no `refs/heads/`), or
# nothing when there is none — never a guess:
#
#   1. HEAD's full ref with `refs/heads/` stripped. Not `--short`: the short
#      form lengthens to `heads/<name>` when a tag shares the branch's name.
#   2. When HEAD is detached, git's own record of a rebase in progress —
#      `rebase-merge/head-name` (merge backend, `rebase -i`) or
#      `rebase-apply/head-name` (apply backend) under the git dir. A conflicted
#      or stopped rebase detaches HEAD for its whole duration, and that is
#      exactly when a session is likely to pause. `--absolute-git-dir` resolves
#      inside a linked worktree. `git am` writes no `head-name`, and a rebase
#      of an already-detached HEAD records `detached HEAD` — both stay empty,
#      as does a plain `git checkout --detach` and anything outside a repo.

live_branch() {
  local root="$1" branch git_dir head_name
  branch="$(git -C "$root" symbolic-ref --quiet HEAD 2>/dev/null | sed -n 's#^refs/heads/##p')"
  if [ -z "$branch" ]; then
    git_dir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)"
    if [ -n "$git_dir" ]; then
      for head_name in "$git_dir/rebase-merge/head-name" "$git_dir/rebase-apply/head-name"; do
        if [ -f "$head_name" ]; then
          branch="$(sed -n 's#^refs/heads/##p' "$head_name" 2>/dev/null)"
          break
        fi
      done
    fi
  fi
  printf '%s' "$branch"
}
