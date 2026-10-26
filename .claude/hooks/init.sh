#!/usr/bin/env bash
# Lemony — Claude Code SessionStart hook.
#
# Read-only orient run on every session entry filtered by source: orient on
# {startup, resume, clear}; on {compact}, print only the ground-truth block
# (task state per disk and git — see "Compact" below) and exit 0.
#
# Orient reports four blocking checks and six warnings (stdout — folded into
# session context), plus a doctor check for bash version. When a blocking check
# fails, stdout is the hook's JSON reply instead (exit 0): `additionalContext`
# for the model, `systemMessage` for the human — see "Output" below. The hook
# always exits 0. The compact block goes to stdout too.
# Target: <1s p99.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/live-branch.sh
if [ -f "$SCRIPT_DIR/lib/live-branch.sh" ] && [ -r "$SCRIPT_DIR/lib/live-branch.sh" ]; then
  source "$SCRIPT_DIR/lib/live-branch.sh"
  LIVE_BRANCH_LIB=1
else
  # A hand-copied or partial install without the helper (`lemony install`
  # copies all of lib/): read HEAD's branch only — a rebase in progress reads
  # as no branch — and say so once instead of failing on every call.
  live_branch() {
    git -C "$1" symbolic-ref --quiet HEAD 2>/dev/null | sed -n 's#^refs/heads/##p'
  }
  LIVE_BRANCH_LIB=0
fi

# A json_string inherited from the environment (an exported function) is not ours.
unset -f json_string 2>/dev/null
# shellcheck source=lib/json-string.sh
if [ -f "$SCRIPT_DIR/lib/json-string.sh" ] && [ -r "$SCRIPT_DIR/lib/json-string.sh" ]; then
  source "$SCRIPT_DIR/lib/json-string.sh"
fi
# Only a helper that defines the encoder counts: a truncated copy does not.
if command -v json_string >/dev/null 2>&1; then
  JSON_STRING_LIB=1
else
  JSON_STRING_LIB=0
fi

# ── Compact: ground truth from disk ────────────────────────────────────────
# A compaction replaces the conversation with a generated summary, and a summary
# can confabulate state — "the checkpoint was approved" when it was not would
# skip a human gate. So the `compact` trigger prints what disk and git say, in
# the turn right after the summary, instead of asking the agent to re-read:
# a printed contradiction is visible, an instruction to check can be skipped.
# Nothing else runs on compact — no orient checks, and no `session_start_ts`
# refresh (a compaction does not start a session). Fail-open: a read that fails
# is reported as such, and the hook always exits 0.
#
# The task comes from the live branch (`harness/<id>-<slug>`, or
# `harness/closeout-<id>`) — the same derivation as `session-close.sh`. Its
# `progress.md` is prose an agent writes, so only the lines the contract fixes
# are read: the first `Mode:` and `Auto-commit:` lines, a line that is exactly
# `awaiting design definition`, the last line naming a full-pass ledger retry,
# and the last top-level bullet under a heading naming a step log (a step's
# transient sub-state is that line's tail). Status and next action stay in the
# file, which the block points at.
#
# Three more human gates are read from what the contract fixes elsewhere:
# - spec approval: `Mode:` is written at approval, so on a task branch a
#   `spec/` with no `Mode:` line means the approval is not recorded;
# - discovery mediation: the last `D<nnn>` section of `discoveries.md` is open
#   while no line in it starts with the `Resolution` label (agents write it as
#   `### Resolution`, `- **Resolution** —`, `**Resolution — D002**` — and a
#   mid-text mention, `Plan says: D016 Resolution: …`, is not one). Only the last
#   entry: one pause raising two entries records one Resolution under the later;
#   a file with conflict markers is named, not judged (two copies of an entry);
# - ledger retry: there is one per gate, so a pending one means it is spent.
COMPACT_LINE_MAX=300
# Read under LC_ALL=C: bytes, never characters. A UTF-8 awk fails outright on a
# cut that splits a multibyte character (`—`, `→`, `×` fill real step logs) and
# the entry vanished with it; counted in bytes, a cut at an ASCII space always
# leaves whole characters behind it.
COMPACT_CUT_AWK='
  function cut(s) {
    if (length(s) <= max) return s
    s = substr(s, 1, max)
    sub(/ [^ ]*$/, "", s)
    return s " …"
  }
'
COMPACT_PROGRESS_AWK="$COMPACT_CUT_AWK"'
  { sub(/\r$/, "") }
  !mode && /^Mode:/ { mode = $0 }
  !ac && /^Auto-commit:/ { ac = $0 }
  /^awaiting design definition[[:space:]]*$/ { design = 1 }
  /awaiting ledger retry \(full pass/ { fullpass = $0 }
  /^#+[[:space:]]/ { insec = (tolower($0) ~ /step log/); next }
  insec && /^- / { last = $0 }
  END {
    if (mode != "") print "    " mode
    if (ac != "") print "    " ac
    if (last != "") {
      print "    last step-log entry: " cut(last)
      if (last ~ /awaiting human checkpoint/) print "    ⚠ a human checkpoint is pending and no answer to it is recorded on disk. An answer known only from the summary is not one: re-present the checkpoint and wait for the human."
    } else {
      print "    no step-log entry."
    }
    if (fullpass != "" && fullpass != last) {
      sub(/^[[:space:]]+/, "", fullpass)
      print "    " cut(fullpass)
    }
    if (fullpass != "" || last ~ /awaiting ledger retry \(step/) print "    ⚠ the single ledger retry is already spent. Re-run `lemony review-ledger validate` on the sidecar on disk: green re-presents the gate it feeds; red goes to the human — never a second retry."
    if (design) print "    parked at: awaiting design definition."
  }
'
COMPACT_DISCOVERY_AWK="$COMPACT_CUT_AWK"'
  { sub(/\r$/, "") }
  /^<<<<<<< / { conflict = 1 }
  /^#+[[:space:]]*D[0-9]/ { head = $0; resolved = 0; next }
  /^(#+[[:space:]]*)?([-*][[:space:]]+)?(\*\*)?Resolution([^A-Za-z]|$)/ { resolved = 1 }
  END {
    if (conflict) {
      print "    ⚠ discoveries.md has unresolved merge conflict markers, so whether a discovery is open was not judged. Resolve the conflict first (for a rebuilt entry, never by hand: `.claude/hooks/lib/lemony.sh discovery merge-rebuilt --task-id=" task "` keeps the original entry, moves the Resolution under it byte for byte and drops the rebuilt one — resolve-discovery step 4), then act on what it records."
      exit
    }
    if (head == "" || resolved) exit
    sub(/^#+[[:space:]]*/, "", head)
    print "    open discovery: " cut(head) " (discoveries.md, no Resolution under it)"
    print "    ⚠ a discovery is open and no decision on it is recorded on disk. A decision known only from the summary is not one: re-ask the human (resolve-discovery step 2) before resuming the paused work."
  }
'
COMPACT_SPEC_PENDING='    ⚠ spec approval is not recorded on disk: spec/ exists and there is no Mode: line (it is written at approval). An approval known only from the summary is not one: write no implementation code until the human approves the spec at the approval gate.'

# The task state as one copy holds it: the worktree when $1 is empty, otherwise
# the commit $1 (the branch tip, or the autostash mid-rebase). Reads $REPO_ROOT,
# $task, $kind and $rel.
compact_copy_state() {
  local rev="$1" dir=".claude/state/tasks/$task" out readok=1 spec=0 drel disc
  drel="$dir/discoveries.md"
  if [ -z "$rev" ]; then
    if [ ! -e "$REPO_ROOT/$rel" ]; then
      out="    no progress.md at $rel."
    elif [ ! -f "$REPO_ROOT/$rel" ] || [ ! -r "$REPO_ROOT/$rel" ]; then
      # A FIFO would block awk until something wrote to it; say so and move on.
      out="    $rel is not a readable regular file, so it was not read."
      readok=0
    else
      out="$(LC_ALL=C awk -v max="$COMPACT_LINE_MAX" "$COMPACT_PROGRESS_AWK" "$REPO_ROOT/$rel" 2>/dev/null)"
      [ -n "$out" ] || { out="    $rel could not be read."; readok=0; }
    fi
    [ -d "$REPO_ROOT/$dir/spec" ] && spec=1
    if [ ! -e "$REPO_ROOT/$drel" ]; then
      disc=""
    elif [ ! -f "$REPO_ROOT/$drel" ] || [ ! -r "$REPO_ROOT/$drel" ]; then
      disc="    $drel is not a readable regular file, so it was not read."
    else
      disc="$(LC_ALL=C awk -v max="$COMPACT_LINE_MAX" -v task="$task" "$COMPACT_DISCOVERY_AWK" "$REPO_ROOT/$drel" 2>/dev/null)"
    fi
  else
    if out="$(git -C "$REPO_ROOT" show "$rev:$rel" 2>/dev/null)"; then
      out="$(printf '%s\n' "$out" | LC_ALL=C awk -v max="$COMPACT_LINE_MAX" "$COMPACT_PROGRESS_AWK" 2>/dev/null)"
      [ -n "$out" ] || { out="    $rel could not be read."; readok=0; }
    else
      out="    no progress.md at $rel."
    fi
    git -C "$REPO_ROOT" cat-file -e "$rev:$dir/spec" 2>/dev/null && spec=1
    disc="$(git -C "$REPO_ROOT" show "$rev:$drel" 2>/dev/null | LC_ALL=C awk -v max="$COMPACT_LINE_MAX" -v task="$task" "$COMPACT_DISCOVERY_AWK" 2>/dev/null)"
  fi
  printf '%s\n' "$out"
  # A closeout branch archives spec/ and drops progress.md, so the rule is for
  # task branches only; an unread progress.md proves nothing either way.
  if [ "$kind" = "task" ] && [ "$spec" -eq 1 ] && [ "$readok" -eq 1 ] \
    && ! printf '%s\n' "$out" | grep -q '^    Mode:'; then
    printf '%s\n' "$COMPACT_SPEC_PENDING"
  fi
  [ -z "$disc" ] || printf '%s\n' "$disc"
}

compact_ground_truth() {
  local branch head status dirty="" task="" kind="" rebasing=0 rel wt tip
  local stash="" stash_file stash_seen="" oid="" dir
  branch="$(live_branch "$REPO_ROOT")"
  head="$(git -C "$REPO_ROOT" log -1 --format='%h %s' 2>/dev/null)"
  # Counted from porcelain v1's XY columns: X is the index, Y the worktree; an
  # unmerged path (both columns from DD AU UD UA DU AA UU) is its own count, not a
  # staged-and-modified file. A failed status reads as unreadable, never as a
  # clean "0 staged". `--no-optional-locks`: a read must not take the index lock
  # from the agent.
  if status="$(git -C "$REPO_ROOT" --no-optional-locks status --porcelain=v1 2>/dev/null)"; then
    dirty="$(printf '%s\n' "$status" | awk '
      /^\?\?/ { untracked++; next }
      /^(DD|AU|UD|UA|DU|AA|UU)[[:space:]]/ { conflicted++; next }
      /^..[[:space:]]/ { if (substr($0, 1, 1) != " ") staged++; if (substr($0, 2, 1) != " ") unstaged++ }
      END {
        printf "%d staged, %d unstaged, %d untracked", staged, unstaged, untracked
        if (conflicted) printf ", %d conflicted (unresolved)", conflicted
      }
    ')"
  fi
  task="$(printf '%s' "$branch" | sed -n -e 's#^harness/\([0-9][0-9]*\)-..*$#\1#p')"
  if [ -n "$task" ]; then
    kind="task"
  else
    task="$(printf '%s' "$branch" | sed -n -e 's#^harness/closeout-\([0-9][0-9]*\)$#\1#p')"
    [ -n "$task" ] && kind="closeout"
  fi

  echo "Lemony — context was compacted. Ground truth read from disk just now; where the summary above disagrees, this wins:"
  if [ -z "$branch" ]; then
    echo "  branch: none (detached HEAD, or not a git repository)"
  elif git -C "$REPO_ROOT" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    echo "  branch: $branch"
  else
    rebasing=1
    echo "  branch: $branch (rebase in progress — HEAD is detached)"
  fi
  if [ "$LIVE_BRANCH_LIB" -eq 0 ]; then
    echo "  (.claude/hooks/lib/live-branch.sh is missing or unreadable, so the branch was read from HEAD only; run \`lemony repair\`.)"
  fi
  echo "  HEAD: ${head:-unreadable (no commit yet, or not a git repository)}"
  echo "  worktree: ${dirty:-unreadable}"

  if [ -z "$kind" ]; then
    echo "  task: none — not a task branch, so no task state was read."
    echo "(Hook: ${BASH_SOURCE[0]})"
    return 0
  fi
  dir=".claude/state/tasks/$task"
  rel="$dir/progress.md"
  if [ "$kind" = "closeout" ]; then
    echo "  task: closeout of #$task ($rel)"
  else
    echo "  task: #$task ($rel)"
  fi
  wt="$(compact_copy_state "")"
  if [ "$rebasing" -eq 0 ]; then
    printf '%s\n' "$wt"
    echo "  Status and next action are prose: read $rel before acting, and re-derive anything else from git and the files."
    echo "(Hook: ${BASH_SOURCE[0]})"
    return 0
  fi
  # Mid-rebase the worktree holds the commit being replayed: older than the branch
  # tip, or newer when work was committed at an `edit`/`break` stop. Which one is
  # live cannot be told from here, so both are read and, when they differ, shown
  # apart — a warning in either copy is kept. With `rebase.autoStash`, uncommitted
  # changes sit in a stash commit until the rebase ends — in neither copy — so that
  # commit is read as a third one.
  if ! git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
    tip="    refs/heads/$branch is gone, so the branch tip was not read."
  else
    tip="$(compact_copy_state "refs/heads/$branch")"
  fi
  for stash_file in rebase-merge/autostash rebase-apply/autostash; do
    stash_file="$(git -C "$REPO_ROOT" rev-parse --git-path "$stash_file" 2>/dev/null)"
    case "$stash_file" in /*) ;; ?*) stash_file="$REPO_ROOT/$stash_file" ;; esac
    [ -n "$stash_file" ] && { [ -e "$stash_file" ] || [ -L "$stash_file" ]; } || continue
    stash_seen="$stash_file"
    oid=""
    # `read` fails on a last line with no newline, though it fills `oid`.
    if [ -f "$stash_file" ] && [ -r "$stash_file" ] \
      && { read -r oid <"$stash_file" || [ -n "$oid" ]; } \
      && oid="$(git -C "$REPO_ROOT" rev-parse --verify --quiet --short "$oid^{commit}" 2>/dev/null)"; then
      break
    fi
    oid=""
  done
  if [ -n "$oid" ]; then
    stash="$(compact_copy_state "$oid")"
    if [ "$tip" = "$wt" ] && [ "$stash" = "$wt" ]; then
      echo "    mid-rebase: the tip of $branch, the worktree and the autostash agree."
      printf '%s\n' "$wt"
    else
      echo "    mid-rebase: the tip of $branch, the worktree and the autostash differ — all shown; work out which is live before acting."
      echo "    at the tip of $branch:"
      printf '%s\n' "$tip" | sed 's/^/  /'
      echo "    in the worktree:"
      printf '%s\n' "$wt" | sed 's/^/  /'
      echo "    in the autostash ($oid — uncommitted changes git set aside for the rebase):"
      printf '%s\n' "$stash" | sed 's/^/  /'
    fi
    echo "  Status and next action are prose: read all three copies of $dir/ — at the tip (\`git show refs/heads/$branch:$dir/<file>\`), in the worktree, and in the autostash (\`git show $oid:$dir/<file>\`) — before acting, and re-derive anything else from git and the files."
    echo "(Hook: ${BASH_SOURCE[0]})"
    return 0
  fi
  if [ "$tip" = "$wt" ]; then
    echo "    mid-rebase: the tip of $branch and the worktree agree."
    printf '%s\n' "$wt"
  else
    echo "    mid-rebase: the tip of $branch and the worktree differ — both shown; work out which is live before acting."
    echo "    at the tip of $branch:"
    printf '%s\n' "$tip" | sed 's/^/  /'
    echo "    in the worktree:"
    printf '%s\n' "$wt" | sed 's/^/  /'
  fi
  if [ -n "$stash_seen" ]; then
    echo "    an autostash exists ($stash_seen) but could not be read as a commit, so the uncommitted changes git set aside for the rebase were not checked: inspect them before acting."
  fi
  echo "  Status and next action are prose: read both copies of $dir/ — at the tip (\`git show refs/heads/$branch:$dir/<file>\`) and in the worktree — before acting, and re-derive anything else from git and the files."
  echo "(Hook: ${BASH_SOURCE[0]})"
}

# Read stdin only when Claude Code is piping a payload; if a developer runs
# this hook interactively (no pipe), default to an empty payload so the script
# doesn't hang on `cat` waiting for input.
if [ -t 0 ]; then
  INPUT=""
else
  INPUT="$(cat)"
fi

# Extract `source` field from the JSON Claude Code pipes in. Bash-only
# (no jq dep) — minimal stdin parse keeps the hook startup cheap.
SOURCE="$(printf '%s' "$INPUT" \
  | grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed 's/.*"\([^"]*\)"$/\1/')"
# The project root, not the session's current directory, which a `cd` moves.
PROJECT_ROOT="$(pwd)"
# shellcheck source=lib/project-root.sh
if [ -f "$SCRIPT_DIR/lib/project-root.sh" ] && [ -r "$SCRIPT_DIR/lib/project-root.sh" ]; then
  source "$SCRIPT_DIR/lib/project-root.sh"
  project_root
fi
REPO_ROOT="$PROJECT_ROOT"
# git and the CLI below run from it too.
cd "$REPO_ROOT" 2>/dev/null || true
if [ "$SOURCE" = "compact" ]; then
  compact_ground_truth
  exit 0
fi

CONFIG="$REPO_ROOT/harness.config.yml"

ERRORS=()
WARNINGS=()
if [ "$LIVE_BRANCH_LIB" -eq 0 ]; then
  WARNINGS+=(".claude/hooks/lib/live-branch.sh is missing or unreadable — the task branch is read from HEAD only, so a rebase in progress reads as no branch. Run \`lemony repair\` to restore it.")
fi
if [ "$JSON_STRING_LIB" -eq 0 ]; then
  WARNINGS+=(".claude/hooks/lib/json-string.sh is missing or unreadable — a blocking issue reaches the model as plain text and is not shown to you. Run \`lemony repair\` to restore it.")
fi

# ── Block 1 ─ harness.config.yml present and parseable ─────────────────────
# Pure-bash validation (no yq): presence of the four keys the harness
# needs to operate, checked top-level plus block-scoped under `task_storage`
# in one awk pass, then extraction of the two values the orient output uses.
# Deep schema validation (formats, enums, did-you-mean typos) lives in
# `lemony doctor`; init.sh stays fail-closed yet node-free, so the boot
# path never depends on the CLI being installed. `jq` is the sole hard dep;
# awk/grep/git (preinstalled) cover the rest.
CONFIG_VERSION=""
CONFIG_REPO=""
# An install's baseline: a version directory (not a dot entry, not a link) under
# `.claude/.harness/baseline/` — the CLI's `hasInstallBaseline`. The `baseline/` entry
# alone is no trace: an ignored file in it keeps it on a branch from before the install.
has_install_baseline() {
  local base="$REPO_ROOT/.claude/.harness/baseline" dir
  # One it may not list is there all the same: "run install" would clobber edits.
  if [ -d "$base" ] && { [ ! -r "$base" ] || [ ! -x "$base" ]; }; then
    return 0
  fi
  for dir in "$base"/*/; do
    [ -d "$dir" ] && [ ! -L "${dir%/}" ] && return 0
  done
  return 1
}
if [ -L "$CONFIG" ] && [ ! -e "$CONFIG" ]; then
  # `-e` follows the link, so a dead one (or a loop, or one behind a directory it
  # may not search) read as "not found" — and `lemony install` refuses to write
  # through a symlink, so "run install" went in a circle. On an installed repo,
  # install after removing it re-scaffolds over the user's edits: restore first.
  ERRORS+=("harness.config.yml at $REPO_ROOT is a symlink that does not resolve (its target is missing or cannot be reached, or it loops). Repoint it at the config file, or replace it with a copy of the config (from git history or a backup); remove it and run \`lemony install\` only in a repo that was never installed.")
elif [ ! -e "$CONFIG" ] && has_install_baseline; then
  # No config next to an install's baseline: removed from an installed repo, or an
  # install that did not finish (it writes the config last). "Run install" is wrong
  # for the first — with no TTY it keeps the vendor copy of every edited file.
  ERRORS+=("harness.config.yml not found at $REPO_ROOT, but .claude/.harness/baseline exists: the harness was installed here, or an install did not finish. If a \`lemony install\` did not finish here, re-run it; otherwise restore harness.config.yml from git history or a backup (\`lemony install\` would, with no TTY, replace the files you edited with the vendor copy).")
elif [ ! -e "$CONFIG" ]; then
  ERRORS+=("harness.config.yml not found at $REPO_ROOT. Run \`lemony install\`.")
elif [ ! -f "$CONFIG" ]; then
  # There, but not a file awk can read: a directory, or a FIFO it would block on
  # until something wrote to it. `-e`/`-f` follow a symlink, so a link to one of
  # these lands here.
  ERRORS+=("harness.config.yml at $REPO_ROOT is not a regular file (a directory, a FIFO, a socket or a device), so it was not read. Replace it with the config file.")
elif [ ! -r "$CONFIG" ]; then
  # A file awk cannot open failed the key check below, so the boot blamed missing keys
  # under a raw awk error.
  ERRORS+=("harness.config.yml at $REPO_ROOT cannot be read (check its permissions), so it was not read.")
elif ! awk '
    { sub(/\r$/, "") }
    /^[^[:space:]#]/ {
      in_ts = ($1 == "task_storage:") ? 1 : 0
      if ($1 == "vendor_version:") have_vv = 1
      else if ($1 == "target:") have_tg = 1
      else if ($1 == "task_storage:") have_ts = 1
    }
    in_ts && /^[[:space:]]+type:/ { have_tt = 1 }
    in_ts && /^[[:space:]]+repo:/ { have_tr = 1 }
    END {
      exit !(have_vv && have_tg && have_ts && have_tt && have_tr)
    }
  ' "$CONFIG"; then
  ERRORS+=("harness.config.yml is missing required keys (vendor_version, target, task_storage.type, task_storage.repo).")
else
  CONFIG_VERSION="$(awk '{ sub(/\r$/, "") } /^vendor_version:/ { sub(/^vendor_version:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }' "$CONFIG")"
  CONFIG_REPO="$(awk '
    { sub(/\r$/, "") }
    /^[^[:space:]#]/ { in_ts = ($1 == "task_storage:") ? 1 : 0 }
    in_ts && /^[[:space:]]*repo:/ { sub(/^[[:space:]]*repo:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
  ' "$CONFIG")"
fi

# ── Block 2 ─ state corruption (critical dirs missing) ─────────────────────
for dir in .claude/state .claude/skills .claude/agents; do
  if [ ! -d "$REPO_ROOT/$dir" ]; then
    ERRORS+=("Harness directory missing: $dir (state corruption — re-run \`lemony install\`).")
  fi
done

# ── Block 3 ─ git config user.email present ────────────────────────────────
GIT_USER_EMAIL="$(git config user.email 2>/dev/null || true)"
if [ -z "$GIT_USER_EMAIL" ]; then
  ERRORS+=("git config user.email is empty. Run: git config --global user.email 'you@example.com'.")
fi

# ── Block 4 ─ gh CLI installed and authenticated ───────────────────────────
# Uses `gh auth token` (local-only) instead of `gh auth status` (HTTPS round
# trip) to keep the orient inside the <1s p99 budget.
if ! command -v gh >/dev/null 2>&1; then
  ERRORS+=("\`gh\` CLI not found in PATH. Install: https://cli.github.com")
elif ! gh auth token >/dev/null 2>&1; then
  ERRORS+=("\`gh auth token\` returned no token. Run \`gh auth login\`.")
fi

# ── Warning 1 ─ vendor version drift (config vs installed CLI) ─────────────
# Resolve the CLI for the version read: the project-local devDependency bin first
# (it survives an fnm Node switch), then a global install. No npx fallback —
# the orient hook stays inside its <1s p99 budget, so a non-resolvable CLI just
# skips the drift check rather than paying a network round trip every session.
LF_BIN=""
if [ -x "$REPO_ROOT/node_modules/.bin/lemony" ]; then
  LF_BIN="$REPO_ROOT/node_modules/.bin/lemony"
elif command -v lemony >/dev/null 2>&1; then
  LF_BIN="lemony"
fi
if [ -n "$CONFIG_VERSION" ] && [ -n "$LF_BIN" ]; then
  INSTALLED_VERSION="$("$LF_BIN" --version 2>/dev/null | head -1)"
  if [ -n "$INSTALLED_VERSION" ] && [ "$CONFIG_VERSION" != "$INSTALLED_VERSION" ]; then
    # Direction-neutral by design: the hook stays offline + node-free, so it
    # can't order the two versions reliably (no portable semver compare in bash —
    # BSD `sort` lacks `-V`). It flags the drift with a remedy safe in BOTH
    # directions; `lemony doctor` resolves the precise direction (it has a
    # real comparator) and the exact remediation.
    WARNINGS+=("vendor version drift: harness.config.yml pins $CONFIG_VERSION, installed CLI is $INSTALLED_VERSION. If your CLI is newer, run \`lemony update\`; if it is older, upgrade your CLI (\`npm install\`) and do NOT run \`update\` (it would downgrade the repo). \`lemony doctor\` tells you which.")
  fi
elif [ -n "$CONFIG_VERSION" ]; then
  # The repo pins a version but no CLI resolves (a teammate never ran
  # `npm install`, no global). This used to be a silent skip — so a stale CLI could
  # drift with no signal at all. Emit a visible line instead, so the check's absence
  # isn't mistaken for "no drift". Still offline: no registry lookup, just a
  # heads-up to install the project-local CLI.
  WARNINGS+=("could not verify CLI version: harness.config.yml pins $CONFIG_VERSION but no \`lemony\` CLI resolved. Run \`npm install\` to get the project-local one (then re-check with \`lemony doctor\`). Version-drift check skipped.")
fi

# ── Warning 2 ─ peer hook missing or non-executable ────────────────────────
PEER_HOOK="$REPO_ROOT/.claude/hooks/session-close.sh"
if [ ! -x "$PEER_HOOK" ]; then
  WARNINGS+=("$PEER_HOOK is missing or not executable — \`/pause\` and SessionEnd telemetry will fail. Run \`lemony repair\` (it restores the file and its exec bit).")
fi

# ── Warning 3 ─ default branch behind origin (no fetch — uses existing refs) ─
# Scoped to a session sitting ON the default branch: "pull before starting" is
# advice for main, and a task branch is behind origin/main by construction.
# The nudge used to fire branch-agnostic: mid-task under auto-commit OFF
# the worktree is dirty by design with the staged index as the save-point
# ladder, and following `git pull --rebase` with `rebase.autostash` set flattens
# that index — the documented rollback then reverts to the last commit and the
# group's whole uncommitted work is gone. So on any other branch: silence.
# Silence too while a rebase has HEAD detached, even a rebase of the default
# branch: the count would be taken from the half-replayed HEAD, and the advice
# cannot be followed mid-rebase — hence the attached-HEAD check.
# `live_branch` (same read as `session-close.sh` / `status`): the full ref
# with `refs/heads/` stripped — `--short` lengthens to `heads/<name>` when a
# tag shares the branch's name, failing the `harness/*` test below — or, while
# a rebase has HEAD detached, the branch being rebased (a rebase of a task
# branch is not a parked task).
CURRENT_BRANCH="$(live_branch "$REPO_ROOT")"
DEFAULT_BRANCH="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
if [ -n "$DEFAULT_BRANCH" ] && [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ] \
  && git symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  BEHIND="$(git rev-list --count "HEAD..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)"
  if [ "${BEHIND:-0}" -gt 0 ]; then
    WARNINGS+=("local branch is $BEHIND commit(s) behind origin/$DEFAULT_BRANCH. Consider \`git pull --rebase\` before starting.")
  fi
fi

# ── Warning 4 ─ residual harness branches (parked tasks) ───────────────────
STALE_BRANCHES="$(git for-each-ref --format='%(refname:short)' refs/heads/harness/ 2>/dev/null | wc -l | tr -d ' ')"
if [ "${STALE_BRANCHES:-0}" -gt 0 ]; then
  case "$CURRENT_BRANCH" in
    harness/*) : ;;
    *) WARNINGS+=("$STALE_BRANCHES parked harness branch(es) present. Resume with \`continue <id>\` or close them with task-closeout.") ;;
  esac
fi

# ── Warning 5 ─ the entry protocol still in a rules file ───────────────────
# An earlier install put the protocol at .claude/rules/; `update` keeps an
# edited copy there as the client's. Claude Code loads rules files into the
# main session and every sub-agent, so while it stays the protocol rides
# twice in the main session and again in each sub-agent.
# The path is built from two parts so that `update` does not read this hook as
# a file that still names the rules file it prunes.
RULES_DIR=".claude/rules"
RULES_PROTOCOL="$RULES_DIR/lemony-entry-protocol.md"
if [ -e "$REPO_ROOT/$RULES_PROTOCOL" ]; then
  WARNINGS+=("$RULES_PROTOCOL is still here: Claude Code loads it into this session and every sub-agent, on top of .claude/agents/entry-protocol.md. Carry the edits you made to it over to .claude/agents/entry-protocol.md, then delete it.")
fi

# ── Warning 6 ─ playbooks still enforced (0.11 transition) ────────────────
# `lemony update` never touches client content and never runs a model, so the
# migration is offered here, in every session while the project's playbook
# directory (`paths.playbooks`, resolved by the old hooks' own helper) holds a
# playbook. Its README.md is the vendor's format document, not a playbook. An
# import leaves its sources in place, so a playbook here may be imported already:
# the hook cannot tell, and the warning offers both ways out. A missing or broken
# helper falls back to the default directory.
PLAYBOOKS_LOCAL_DIR="$REPO_ROOT/docs/playbooks"
# A function inherited from the environment (an exported one) is not ours.
unset -f _resolve_playbook_dirs 2>/dev/null
# shellcheck source=lib/playbook-scan.sh
if [ -f "$SCRIPT_DIR/lib/playbook-scan.sh" ] && [ -r "$SCRIPT_DIR/lib/playbook-scan.sh" ]; then
  source "$SCRIPT_DIR/lib/playbook-scan.sh"
fi
if command -v _resolve_playbook_dirs >/dev/null 2>&1; then
  _resolve_playbook_dirs "$REPO_ROOT" "${HOME:-}"
fi
PLAYBOOK_COUNT=0
for f in "$PLAYBOOKS_LOCAL_DIR"/*.md; do
  [ -f "$f" ] || continue
  [ "${f##*/}" = "README.md" ] && continue
  PLAYBOOK_COUNT=$((PLAYBOOK_COUNT + 1))
done
if [ "$PLAYBOOK_COUNT" -gt 0 ]; then
  PLAYBOOKS_REL="${PLAYBOOKS_LOCAL_DIR#"$REPO_ROOT"/}"
  # `pb/` in the config reads as `pb`, not `pb//`.
  while [ "${#PLAYBOOKS_REL}" -gt 1 ] && [ "${PLAYBOOKS_REL%/}" != "$PLAYBOOKS_REL" ]; do
    PLAYBOOKS_REL="${PLAYBOOKS_REL%/}"
  done
  WARNINGS+=("$PLAYBOOKS_REL/ still holds $PLAYBOOK_COUNT playbook(s), which the old hooks enforce until 0.12.0 removes those hooks. Offer the human \`/import $PLAYBOOKS_REL/\` for the ones not imported yet (it turns them into Claude Code rules, client skills and reference docs, and writes nothing until they approve its plan), or deleting the ones an import already covers.")
fi

# ── Doctor (informational; never blocking) ─────────────────────────────────
BASH_MAJOR="${BASH_VERSION%%.*}"
if [ "${BASH_MAJOR:-0}" -lt 4 ]; then
  # The shipped hooks (lifecycle + enforcement) are explicitly bash
  # 3.2 compatible. The warning is forward-looking: a future hook MAY require
  # bash 4 features (`shopt -s globstar`, associative arrays). On stock macOS
  # `/bin/bash` is 3.2 and current hooks run cleanly there.
  WARNINGS+=("bash $BASH_VERSION detected; current hooks run on 3.2 but future ones may want 4+. \`brew install bash\` to be future-proof.")
fi

# ── Lazy-init current-<user>.md (per-dev pointer, gitignored) ──────────────
# If the blocks didn't fire and we know the user, ensure the per-dev pointer
# file exists with a fresh `session_start_ts` so `session-close.sh` can compute
# `session_active_h` accurately. The refresh is a pure-awk in-place rewrite of
# the frontmatter scalar (no yq).
if [ "${#ERRORS[@]}" -eq 0 ] && [ -n "$GIT_USER_EMAIL" ]; then
  NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # `%%@*` strips from the FIRST `@` (parity with status.ts's `email.split('@')[0]`),
  # not `%@*` which strips from the last — they diverge only on a malformed multi-`@`
  # address, but the pointer filename must match what status.ts reads back.
  USER_SLUG="${GIT_USER_EMAIL%%@*}"
  # The slug becomes a filename — drop anything path-significant so a crafted
  # user.email (`../../x@y`) can't make CURRENT_PATH escape `.claude/state/`.
  # Mirrors the readPointer guard in status.ts; skips the write (status returns
  # empty), since the boot can otherwise proceed.
  case "$USER_SLUG" in
    '' | */* | *'\'* | *..*) USER_SLUG="" ;;
  esac
  CURRENT_PATH="$REPO_ROOT/.claude/state/current-$USER_SLUG.md"
  if [ -z "$USER_SLUG" ]; then
    : # path-unsafe slug — pointer write skipped above
  elif [ -L "$REPO_ROOT/.claude" ] || [ -L "$REPO_ROOT/.claude/state" ]; then
    # A linked directory takes the pointer, and every refresh after it, out of the
    # repo — the same write-through the dangling-link branch below refuses.
    WARNINGS+=(".claude or .claude/state is a symlink, so the session start was not recorded (the pointer would be written wherever it points). Replace it with a directory.")
  elif [ -e "$CURRENT_PATH" ] && [ ! -f "$CURRENT_PATH" ]; then
    # There, but not a file: writing to a FIFO blocks until something reads it, and
    # awk reading one blocks until something writes. The pointer is not critical, so
    # the boot goes on without it — a warning, not a blocking error.
    WARNINGS+=(".claude/state/current-$USER_SLUG.md is not a regular file (a directory, a FIFO, a socket or a device), so the session start was not recorded. Remove it; the next session recreates it.")
  elif [ -L "$CURRENT_PATH" ] && [ ! -e "$CURRENT_PATH" ]; then
    # A symlink whose target is gone: `-e`/`-f` follow it and see nothing, and the
    # `cat >` below would create the target wherever the link points.
    WARNINGS+=(".claude/state/current-$USER_SLUG.md is a symlink whose target is missing, so the session start was not recorded (writing through it would create the file it points at). Remove it; the next session recreates it.")
  elif [ ! -f "$CURRENT_PATH" ]; then
    mkdir -p "$REPO_ROOT/.claude/state"
    cat > "$CURRENT_PATH" <<EOF
---
session_start_ts: $NOW_ISO
last_close_ts: ""
---

# Current session — $GIT_USER_EMAIL

Per-dev pointer (gitignored). The lifecycle hooks read \`session_start_ts\`
to compute \`session_active_h\` and reset it on each SessionStart that orients.
The active task and its branch are not recorded here — \`session-close.sh\`
derives them from the live branch (\`harness/<id>-<slug>\` or
\`harness/closeout-<id>\`, the rebasing branch mid-rebase) at close time — and
the narrative resume lives under \`sessions/<user>/\` (written by \`/pause\`).
EOF
  else
    # Refresh session_start_ts on every orient so close-time math is accurate.
    # awk in-place rewrite of the frontmatter scalar — without this,
    # `session_start_ts` would stay frozen at the first orient and
    # `session_active_h` would be cumulative across every clear/resume.
    # The same pass drops the dead `active_task` / `branch` scalars a pointer
    # created by an earlier version still carries — nothing ever updated them,
    # so they lie (`null` / the init-day branch); the live branch is the source.
    # Its "Resume hint" section goes too, but ONLY while it is still exactly
    # the untouched placeholder — the heading, blank lines, the one placeholder
    # line, and nothing else up to the next heading or EOF (its "Updated by
    # `/pause`" promise was never kept). Anything a person wrote there — the
    # placeholder replaced, a paragraph added below it, even a `---` rule —
    # makes the section theirs and it stays, heading included; so does a
    # section stripped to its bare heading. Decided by a read-only pre-pass so
    # the rewrite below never looks ahead; `[[:space:]]*$` tolerates CRLF.
    PRUNE_HINT="$(awk '
      inhint && /^---/ { other = 1; next }
      /^---/ { block++; next }
      block < 2 { next }
      /^## Resume hint[[:space:]]*$/ { inhint = 1; seen = 1; next }
      inhint && /^## / { inhint = 0 }
      !inhint { next }
      /^[[:space:]]*$/ { next }
      /Updated by `\/pause`/ { placeholder++; next }
      { other = 1 }
      END { print (seen && placeholder == 1 && !other) ? 1 : 0 }
    ' "$CURRENT_PATH" 2>/dev/null)"
    [ "$PRUNE_HINT" = "1" ] || PRUNE_HINT=0
    # Write through a mktemp file, not a predictable `$CURRENT_PATH.tmp`: the
    # latter is a known path an attacker could pre-plant as a symlink for the
    # redirect to follow. `mktemp` refuses to reuse an existing path, and `mv`
    # over CURRENT_PATH itself safely replaces a symlink with a regular file.
    if tmp="$(mktemp "$REPO_ROOT/.claude/state/.ptr.XXXXXX")"; then
      awk -v ts="$NOW_ISO" -v prune="$PRUNE_HINT" '
        /^---/ {
          block++
          if (block == 2 && !seen) print "session_start_ts: " ts
          print
          next
        }
        block == 1 && /^session_start_ts:/ { print "session_start_ts: " ts; seen = 1; next }
        block == 1 && /^(active_task|branch):/ { next }
        prune && block >= 2 && /^## Resume hint[[:space:]]*$/ { inhint = 1; next }
        inhint && /^## / { inhint = 0 }
        inhint { next }
        { print }
      ' "$CURRENT_PATH" > "$tmp" && mv "$tmp" "$CURRENT_PATH" || rm -f "$tmp"
    fi
  fi
fi

# ── Telemetry opt-out disclosure ───────────────────────────────────────────
# Anonymous telemetry is on by default, so the first session — and any session
# after the effective consent changes — must surface the opt-out. The sentinel +
# fingerprint logic lives in TS (one resolver, no bash duplication of the env ›
# local › config precedence + .strict() fail-safe); init.sh just shells
# out when a CLI resolves ($LF_BIN from the version-drift check) and skips
# otherwise. A CLI-less teammate is not left uninformed: `install` already showed
# the notice once. Healthy-path only, and never fails the boot — the command
# self-suppresses when telemetry is OFF and `|| true` swallows any non-zero.
if [ "${#ERRORS[@]}" -eq 0 ] && [ -n "$LF_BIN" ]; then
  "$LF_BIN" telemetry notice 2>/dev/null || true
fi

# ── Telemetry catch-up send ────────────────────────────────────────────────
# SessionEnd's send is the timely path; this is the safety net for a
# session that closed uncleanly (crash / SIGKILL / no SessionEnd fired) and so
# never shipped its tail. Flush the unsent tail of events.jsonl now, on entry.
# Detached in a subshell (`( … & )`) with output redirected so SessionStart never
# waits on the network; `nohup` lets it outlive a SIGHUP if the orient's process
# group tears down before the send completes — same fire-and-forget shape as
# session-close.sh (the CLI carries its own hard per-request timeout, D4, and
# never throws). The byte-offset cursor dedups: a clean prior close already
# advanced it, so this finds nothing to send. A failure (offline) leaves the
# cursor untouched and the next hook retries the same bytes — the offline
# invariant. No-op when no endpoint is configured. Runs AFTER the disclosure so a
# first-ever session surfaces the opt-out first (there is no backlog on a first
# session anyway, and the engine re-checks consent before any byte leaves the box).
if [ "${#ERRORS[@]}" -eq 0 ] && [ -n "$LF_BIN" ]; then
  ( nohup "$LF_BIN" telemetry send >/dev/null 2>&1 & )
fi

# ── Output ─────────────────────────────────────────────────────────────────
orient_warnings() {
  echo "Lemony — orient ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  if [ -n "$CONFIG_REPO" ]; then
    echo "  project: $CONFIG_REPO  user: ${GIT_USER_EMAIL:-(unset)}"
  fi
  for w in "${WARNINGS[@]}"; do
    echo "  ⚠ $w"
  done
}

blocking_issues() {
  echo "Lemony — blocking issues:"
  for e in "${ERRORS[@]}"; do
    echo "  ✖ $e"
  done
  # Self-identify so a maintainer reading the log can locate the source
  # without a grep — same treatment as the enforcement hooks' block messages.
  echo "(Hook: ${BASH_SOURCE[0]})"
}

if [ "${#ERRORS[@]}" -gt 0 ]; then
  # Claude Code keeps a SessionStart hook's exit-2 stderr out of the model's
  # context (shown to the human only — measured on Claude Code 2.1.290), so
  # blocking issues go out as the hook's JSON reply, exit 0: `additionalContext`
  # reaches the model, `systemMessage` the human. The warnings ride in the same
  # reply — Claude Code parses stdout as JSON only when it is nothing else.
  BLOCK="$(blocking_issues)"
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    CONTEXT="$(orient_warnings)
$BLOCK"
  else
    CONTEXT="$BLOCK"
  fi
  if [ "$JSON_STRING_LIB" -eq 0 ]; then
    # No encoder: plain stdout still reaches the model as context, the human
    # gets nothing — the warning above names the missing helper.
    printf '%s\n' "$CONTEXT"
    exit 0
  fi
  printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "$BLOCK" | json_string)" \
    "$(printf '%s' "$CONTEXT" | json_string)"
  exit 0
fi

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  orient_warnings
fi

exit 0
