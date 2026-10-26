#!/usr/bin/env bash
# The root of the project a hook acts on — sourced by `init.sh`, `entry-protocol.sh`,
# `session-close.sh`, `require-playbook.sh` and `suggest-playbook.sh`, which read the
# config, the state and the playbooks from it and run git there, and by
# `inject-shell-write-rules.sh`, which snapshots the tree there.
#
# `project_root` sets `PROJECT_ROOT`. Claude Code runs a hook from the session's
# current directory and sets `CLAUDE_PROJECT_DIR` to the directory it was started in
# (measured on 2.1.296):
#
#   - after a `cd src` in Bash, the hook's directory is `src`, the project dir is
#     unchanged;
#   - in a sub-agent with `isolation: worktree`, and after `EnterWorktree`, the hook's
#     directory is the worktree while the project dir still names the main checkout.
#
# So the root is the project dir, unless the hook runs inside a linked worktree of the
# project's own repository below it (same git common dir) whose toplevel holds
# `harness.config.yml`: then that worktree, also after a `cd` inside it. Nothing else
# below the project dir counts, so a nested `harness.config.yml` (a package, a fixture,
# a submodule or a nested repository) is never taken for the root. With
# `CLAUDE_PROJECT_DIR` unset (an older Claude Code, a hook run by hand), the root is the
# hook's directory, as before.

# `git rev-parse` from <dir>, discovering the repository from it: an inherited
# `GIT_DIR`, `GIT_WORK_TREE` or `GIT_COMMON_DIR` would name another one.
_project_root_git() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
    cd "$1" 2>/dev/null && git rev-parse --path-format=absolute "${@:2}" 2>/dev/null
  )
}

project_root() {
  local project="${CLAUDE_PROJECT_DIR:-}" physical_project here toplevel common project_common below
  PROJECT_ROOT="$(pwd)"
  [ -n "$project" ] && [ -d "$project" ] || return 0
  PROJECT_ROOT="$project"
  physical_project="$(cd "$project" 2>/dev/null && pwd -P)"
  [ -n "$physical_project" ] || return 0
  here="$(_project_root_git . --show-toplevel --git-common-dir)" || return 0
  toplevel="${here%%$'\n'*}"
  common="${here#*$'\n'}"
  # git prints the toplevel physically (`/tmp` → `/private/tmp`); the part below the
  # project dir is appended to the project dir as Claude Code spelled it, the spelling
  # the paths in the payload use.
  case "$toplevel" in
    "$physical_project"/?*) ;;
    *) return 0 ;;
  esac
  # Only a linked worktree of the project's own repository: a submodule or a nested
  # repository has a common dir of its own.
  project_common="$(_project_root_git "$project" --git-common-dir)" || return 0
  [ "$(cd "$common" 2>/dev/null && pwd -P)" = "$(cd "$project_common" 2>/dev/null && pwd -P)" ] || return 0
  below="${toplevel#"$physical_project"}"
  if [ -e "$toplevel/harness.config.yml" ] || [ -L "$toplevel/harness.config.yml" ]; then
    PROJECT_ROOT="$project$below"
  fi
}
