#!/usr/bin/env bash
# Lemony — Claude Code PreToolUse hook (playbook enforcement).
#
# On every Write/Edit, scan the project's playbooks (local docs/playbooks/ +
# global ~/.claude/playbooks/, local shadowing global) and find those whose
# `applies_to` glob matches the target file path. If any matching playbook was
# NOT loaded in full by the writing agent, block the call (exit 2) with a message
# telling the agent exactly which playbook(s) to read first.
#
# A playbook is loaded when its whole current text came back in a tool result of the
# writing agent's own transcript — a `Read`, or a `cat` however written —
# `subagents/agent-<agent_id>.jsonl` inside a sub-agent, never a sibling's. A partial,
# piped, captured or cut output does not count, nor does a large output Claude Code
# saved to a file and showed as a preview, nor a read sent in the same message as the
# write. The rule lives in lib/tool-loads.sh, shared with the other load hooks.
#
# Fails open (exit 0) when jq is missing, no playbooks exist, the transcript is
# unreadable or could not be scanned, the payload's agent_id is malformed, the
# shared lib is missing, or the tool is not Write/Edit — the hook is an
# enforcement layer, not a gate of last resort. The doctor warnings in init.sh
# cover missing tooling.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/playbook-scan.sh
source "$SCRIPT_DIR/lib/playbook-scan.sh"
# shellcheck source=lib/tool-loads.sh
source "$SCRIPT_DIR/lib/tool-loads.sh" || {
  printf '[require-playbook] lib/tool-loads.sh missing, skipping the check\n' >&2
  exit 0
}

warn() {
  printf '[require-playbook] %s\n' "$*" >&2
}

# Read stdin only when Claude Code is piping a payload; if a developer runs the
# hook interactively (no pipe), default to an empty payload so the script
# doesn't hang on `cat`.
if [ -t 0 ]; then
  PAYLOAD=""
else
  PAYLOAD="$(cat 2>/dev/null || true)"
fi
[ -n "$PAYLOAD" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found, skipping check"
  exit 0
fi

TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty')"
case "$TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

FILEPATH="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty')"
[ -n "$FILEPATH" ] || exit 0

# The project root, not the session's current directory, which a `cd` moves.
PROJECT_ROOT="$(pwd)"
# shellcheck source=lib/project-root.sh
if [ -f "$SCRIPT_DIR/lib/project-root.sh" ] && [ -r "$SCRIPT_DIR/lib/project-root.sh" ]; then
  source "$SCRIPT_DIR/lib/project-root.sh"
  project_root
fi
REPO_ROOT="$PROJECT_ROOT"
HOME_DIR="${HOME:-$REPO_ROOT}"

playbook_scan_for_path "$REPO_ROOT" "$HOME_DIR" "$FILEPATH"
if [ ${#MATCHED_PLAYBOOKS[@]} -eq 0 ]; then
  exit 0
fi

TRANSCRIPT_PATH="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty')"
AGENT_ID="$(printf '%s' "$PAYLOAD" | jq -r '.agent_id // empty')"
TOOL_USE_ID="$(printf '%s' "$PAYLOAD" | jq -r '.tool_use_id // empty')"
tool_loads_own_transcript "$TRANSCRIPT_PATH" "$AGENT_ID" || {
  warn "unexpected agent_id, allowing $FILEPATH"
  exit 0
}

# Fail open if the transcript is not accessible — better to allow than wrongly
# block a legitimate workflow.
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -r "$OWN_TRANSCRIPT" ]; then
  warn "transcript not accessible, allowing $FILEPATH"
  exit 0
fi

tool_loads_scan "$OWN_TRANSCRIPT" "$TOOL_USE_ID" "${MATCHED_PLAYBOOKS[@]}" || {
  warn "could not scan the transcript, allowing $FILEPATH"
  exit 0
}

MISSING=()
for pb in "${MATCHED_PLAYBOOKS[@]}"; do
  loaded=0
  if [ ${#LOADED_TARGETS[@]} -gt 0 ]; then
    for t in "${LOADED_TARGETS[@]}"; do
      [ "$t" = "$pb" ] && loaded=1
    done
  fi
  [ "$loaded" -eq 1 ] || MISSING+=("$pb")
done

if [ ${#MISSING[@]} -eq 0 ]; then
  exit 0
fi

{
  printf 'Before writing %s, you MUST first read the relevant playbook(s):\n\n' "$FILEPATH"
  for pb in "${MISSING[@]}"; do
    printf '  - %s\n' "$pb"
  done
  printf '\nCall the Read tool for each missing playbook:\n\n'
  for pb in "${MISSING[@]}"; do
    printf '  Read(file_path="%s")\n' "$pb"
  done
  printf '\nA `cat` that shows you the whole file also counts. A partial read (a Read with\n'
  printf 'limit, head) does not, nor does a command whose output was too large and was\n'
  printf 'saved to a file, nor a read sent in the same message as this write; loads by\n'
  printf 'another agent do not count. If the playbook changed since you read it, read it\n'
  printf 'again; if Read answers that the file is unchanged, cat the whole file.\n'
  printf '\nPlaybooks capture this project'\''s canonical patterns for this kind of file.\n'
  printf 'Reading them first avoids re-discovering already-solved problems.\n'
  printf '\nAfter reading, retry this Write/Edit.\n'
  # Name the actual file the agent / human reader can inspect — works both at
  # an installed `.claude/hooks/` location and when the hook runs from the
  # vendor repo (dogfood, CI, manual debug).
  printf '\n(Hook: %s)\n' "${BASH_SOURCE[0]}"
} >&2

exit 2
