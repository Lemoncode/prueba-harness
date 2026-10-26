#!/usr/bin/env bash
# Lemony — Claude Code SessionEnd hook + `/pause` adaptor.
#
# Fires:
#   • automatically on SessionEnd (no `--manual`) → auto-close path: writes a
#     skeleton `sessions/<user>/<ts>-auto.md`.
#   • from `/pause` with `--manual` → Claude has already written
#     `sessions/<user>/<ts>-<topic>.md`; the hook only emits + updates pointers.
#
# Both paths emit a `session_closed` event and print `git status --porcelain`
# without auto-committing (the user decides what to commit).

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

MANUAL=0
for arg in "$@"; do
  case "$arg" in
    --manual) MANUAL=1 ;;
  esac
done

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
INPUT=""
if [ "$MANUAL" -eq 0 ]; then
  # Claude Code pipes a JSON payload on SessionEnd. The hook reads stdin once;
  # if no payload was sent (manual invocation, missing pipe) we proceed with
  # `reason=other`.
  if [ -t 0 ]; then
    INPUT=""
  else
    INPUT="$(cat || true)"
  fi
fi

# ── Resolve the user (filename + envelope `user` derive from git config) ───
EMAIL="$(git config user.email 2>/dev/null || true)"
if [ -z "$EMAIL" ]; then
  # Self-identify so a maintainer reading the log can locate the source
  # without a grep — same treatment as the enforcement hooks.
  echo "session-close (${BASH_SOURCE[0]}): git config user.email is empty — skipping (init.sh would have blocked the session, so this is a defensive guard)." >&2
  exit 0
fi
# `%%@*` strips from the FIRST `@` (parity with status.ts's `email.split('@')[0]`),
# not `%@*` which strips from the last — they diverge only on a malformed multi-`@`
# address, but the pointer filename must match what status.ts reads back.
USER_SLUG="${EMAIL%%@*}"
# The slug becomes a filename — bail on anything path-significant so a crafted
# user.email (`../../x@y`) can't make CURRENT_PATH escape `.claude/state/`.
# Mirrors the readPointer guard in status.ts; fail-open like the empty-email case.
case "$USER_SLUG" in
  '' | */* | *'\'* | *..*)
    echo "session-close (${BASH_SOURCE[0]}): git config user.email derives a path-unsafe slug — skipping." >&2
    exit 0
    ;;
esac

# ── Timestamps ─────────────────────────────────────────────────────────────
NOW_EPOCH="$(date -u +%s)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── Read current-<user>.md frontmatter ─────────────────────────────────────
# An awk scrape of the leading frontmatter block — works for the shallow
# scalars the harness writes, fails gracefully on anything richer. yq was
# removed harness-wide: jq is the sole hard dependency; awk/grep/git
# (preinstalled) cover the rest.
CURRENT_PATH="$REPO_ROOT/.claude/state/current-$USER_SLUG.md"
SESSION_START_TS=""
read_frontmatter_field() {
  local field="$1"
  awk -v field="$field" '
    /^---/ { block++; next }
    block == 1 {
      n = index($0, ":")
      if (n > 0) {
        key = substr($0, 1, n - 1)
        sub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == field) {
          value = substr($0, n + 1)
          sub(/^[[:space:]]+|[[:space:]]+$/, "", value)
          gsub(/"/, "", value)
          print value
          exit
        }
      }
    }
  ' "$CURRENT_PATH" 2>/dev/null
}
if [ -f "$CURRENT_PATH" ]; then
  SESSION_START_TS="$(read_frontmatter_field session_start_ts)"
fi

# ── Derive the task context from the live branch ───────────────────────────
# The pointer never carried a real `active_task` / `branch` — nothing in the
# contract wrote them after init, so every auto-close record copied `null` /
# the init-day branch. The branch is the source of truth: the Orchestrator
# works every task on `harness/<id>-<slug>` and closes it out on
# `harness/closeout-<id>`, so the branch names the task. `live_branch` reads
# HEAD, or the rebasing branch while a rebase has HEAD detached; empty
# (→ `(unknown)`, no task) on any other detached HEAD or outside a repo —
# never a stale guess.
TASK_BRANCH="$(live_branch "$REPO_ROOT")"
if [ "$LIVE_BRANCH_LIB" -eq 0 ]; then
  echo "session-close: .claude/hooks/lib/live-branch.sh is missing or unreadable — the task branch was read from HEAD only (a rebase in progress reads as no branch). Run \`lemony repair\` to restore it." >&2
fi
ACTIVE_TASK="$(printf '%s' "$TASK_BRANCH" | sed -n -e 's#^harness/\([0-9][0-9]*\)-..*$#\1#p' -e 's#^harness/closeout-\([0-9][0-9]*\)$#\1#p')"

# Fallback: a session with no recorded start defaults to "started now" so the
# math is well-defined; duration becomes 0 hours, which the schema accepts.
if [ -z "$SESSION_START_TS" ]; then
  SESSION_START_TS="$NOW_ISO"
fi

# Convert SESSION_START_TS to epoch (portable between GNU and BSD date).
iso_to_epoch() {
  local ts="$1"
  # Strip fractional seconds and the trailing Z for BSD `date -j -f`.
  local clean="${ts%%.*}"
  clean="${clean%Z}"
  if date -u -d "@0" +%s >/dev/null 2>&1; then
    date -u -d "$ts" +%s
  else
    date -juf "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null
  fi
}
START_EPOCH="$(iso_to_epoch "$SESSION_START_TS")"
if [ -z "${START_EPOCH:-}" ]; then
  START_EPOCH="$NOW_EPOCH"
fi
DURATION_H="$(awk -v start="$START_EPOCH" -v now="$NOW_EPOCH" 'BEGIN { printf "%.4f", (now - start) / 3600.0 }')"
# Floor at zero — a clock skew between session_start_ts and now must not yield
# a negative duration that fails Zod validation.
if awk -v d="$DURATION_H" 'BEGIN { exit !(d < 0) }'; then
  DURATION_H="0.0000"
fi

# ── Resolve reason + auto_close flag ───────────────────────────────────────
if [ "$MANUAL" -eq 1 ]; then
  REASON="manual"
  AUTO_CLOSE="false"
else
  REASON="$(printf '%s' "$INPUT" \
    | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/')"
  REASON="${REASON:-other}"
  AUTO_CLOSE="true"
fi

# ── Emit the event via the CLI (Zod-validates the line) ────────────────────
EMIT_ARGS=(
  emit session_closed
  --session-start-ts="$SESSION_START_TS"
  --session-active-h="$DURATION_H"
  --reason="$REASON"
  --auto-close="$AUTO_CLOSE"
)
# Only a task branch yields an id; a session closed on `main` (or detached)
# emits the envelope without `task_id`, as the schema allows.
if [ -n "$ACTIVE_TASK" ]; then
  EMIT_ARGS+=(--task-id="$ACTIVE_TASK")
fi
# Resolve the CLI via the launcher (local devDependency → global → fail-fast)
# rather than a bare `command -v` on PATH, which an npx install or an fnm Node
# switch leaves empty. Fail open — a missing launcher or a failed emit warns and
# continues; the session must never be blocked by telemetry.
LF_CLI="$REPO_ROOT/.claude/hooks/lib/lemony.sh"
if [ -x "$LF_CLI" ]; then
  "$LF_CLI" "${EMIT_ARGS[@]}" || \
    echo "session-close: \`lemony emit\` failed (continuing — see previous error)." >&2
else
  echo "session-close: CLI launcher missing ($LF_CLI) — skipping event emit. Re-run \`lemony install\`." >&2
fi

# ── Fire-and-forget telemetry send ─────────────────────────────────────────
# Flush the unsent tail of events.jsonl to the ingest Worker. Detached in a
# subshell (`( … & )`) so SessionEnd never waits on the network; `nohup` lets it
# outlive a SIGHUP if the session tears down its process group before the send
# completes. The CLI has its own hard per-request timeout and never throws —
# output is discarded and a failure leaves the cursor untouched, so the next run
# (or init.sh catch-up) retries the same bytes. No-op when no endpoint is
# configured. Telemetry must never block or break session exit.
if [ -x "$LF_CLI" ]; then
  ( nohup "$LF_CLI" telemetry send >/dev/null 2>&1 & )
fi

# ── Auto-close path: write the session skeleton ───────────────────────────
if [ "$MANUAL" -eq 0 ]; then
  SESSIONS_DIR="$REPO_ROOT/.claude/state/sessions/$USER_SLUG"
  mkdir -p "$SESSIONS_DIR"
  SESSION_FILE="$SESSIONS_DIR/$NOW_ISO-auto.md"
  cat > "$SESSION_FILE" <<EOF
---
session_start_ts: $SESSION_START_TS
session_close_ts: $NOW_ISO
session_active_h: $DURATION_H
active_task: ${ACTIVE_TASK:-null}
branch: ${TASK_BRANCH:-(unknown)}
reason: $REASON
auto_close: true
---

# Session — auto-close ($NOW_ISO)

_Closed by Claude Code's SessionEnd event with no narrative model run._
_If you want a written resume, use \`/pause\` before exiting next time._
EOF
fi

# ── Update current-<user>.md frontmatter pointers ──────────────────────────
# Blank session_start_ts (the next SessionStart re-stamps it) and record the
# close ts. awk in-place rewrite of the frontmatter scalars — mirrors the read
# fallback above and the session_start_ts rewrite in init.sh (no yq).
if [ -f "$CURRENT_PATH" ]; then
  # Rewrite each scalar if present; if a legacy/hand-edited pointer lacks the
  # line, append it just before the closing `---` (parity with the `yq -i` set
  # this replaced — `block == 2` is the frontmatter's closing fence).
  # Write through a mktemp file, not a predictable `$CURRENT_PATH.tmp`: the
  # latter is a known path an attacker could pre-plant as a symlink for the
  # redirect to follow. `mktemp` refuses to reuse an existing path, and `mv`
  # over CURRENT_PATH itself safely replaces a symlink with a regular file.
  if tmp="$(mktemp "$REPO_ROOT/.claude/state/.ptr.XXXXXX")"; then
    awk -v ts="$NOW_ISO" '
      /^---/ {
        block++
        if (block == 2) {
          if (!seen_start) print "session_start_ts: \"\""
          if (!seen_close) print "last_close_ts: " ts
        }
        print
        next
      }
      block == 1 && /^session_start_ts:/ { print "session_start_ts: \"\""; seen_start = 1; next }
      block == 1 && /^last_close_ts:/ { print "last_close_ts: " ts; seen_close = 1; next }
      { print }
    ' "$CURRENT_PATH" > "$tmp" && mv "$tmp" "$CURRENT_PATH" || rm -f "$tmp"
  fi
fi

# ── Print git status without committing ────────────────────────────────────
echo "git status --porcelain ($NOW_ISO):"
git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true

exit 0
