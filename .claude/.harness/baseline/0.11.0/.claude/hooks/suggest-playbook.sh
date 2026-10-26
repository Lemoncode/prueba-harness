#!/usr/bin/env bash
# Lemony — Claude Code UserPromptSubmit hook (playbook suggestion).
#
# Non-blocking. Scans the user's freshly submitted prompt and, when it mentions
# a topic covered by a playbook (per the `keywords` regex list in the
# frontmatter) that the main session has not loaded yet, emits a
# <system-reminder> on stdout — Claude Code attaches it as guidance for the
# agent's next turn. A playbook is loaded when its whole text came back in a tool
# result, by the rule require-playbook.sh applies (lib/tool-loads.sh). Prompts reach
# the main session only, so a sub-agent's load is never counted.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/playbook-scan.sh
source "$SCRIPT_DIR/lib/playbook-scan.sh"
# shellcheck source=lib/tool-loads.sh
source "$SCRIPT_DIR/lib/tool-loads.sh" || exit 0

if [ -t 0 ]; then
  PAYLOAD=""
else
  PAYLOAD="$(cat 2>/dev/null || true)"
fi
[ -n "$PAYLOAD" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

PROMPT="$(printf '%s' "$PAYLOAD" | jq -r '.prompt // empty')"
[ -n "$PROMPT" ] || exit 0

# The project root, not the session's current directory, which a `cd` moves.
PROJECT_ROOT="$(pwd)"
# shellcheck source=lib/project-root.sh
if [ -f "$SCRIPT_DIR/lib/project-root.sh" ] && [ -r "$SCRIPT_DIR/lib/project-root.sh" ]; then
  source "$SCRIPT_DIR/lib/project-root.sh"
  project_root
fi
REPO_ROOT="$PROJECT_ROOT"
HOME_DIR="${HOME:-$REPO_ROOT}"

playbook_scan_for_prompt "$REPO_ROOT" "$HOME_DIR" "$PROMPT"
if [ ${#MATCHED_KEYWORD_PLAYBOOKS[@]} -eq 0 ]; then
  exit 0
fi

TRANSCRIPT_PATH="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty')"

LOADED_TARGETS=()
if [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
  tool_loads_scan "$TRANSCRIPT_PATH" "" "${MATCHED_KEYWORD_PLAYBOOKS[@]}" || LOADED_TARGETS=()
fi

NEW_SUGGESTIONS=()
for pb in "${MATCHED_KEYWORD_PLAYBOOKS[@]}"; do
  loaded=0
  if [ ${#LOADED_TARGETS[@]} -gt 0 ]; then
    for t in "${LOADED_TARGETS[@]}"; do
      [ "$t" = "$pb" ] && loaded=1
    done
  fi
  [ "$loaded" -eq 1 ] || NEW_SUGGESTIONS+=("$pb")
done

if [ ${#NEW_SUGGESTIONS[@]} -eq 0 ]; then
  exit 0
fi

{
  printf '<system-reminder>\n'
  printf 'Topic detection on your prompt suggests reading these playbook(s) before planning:\n\n'
  for pb in "${NEW_SUGGESTIONS[@]}"; do
    printf '  - %s\n' "$pb"
  done
  printf '\nUse the Read tool on each. Playbooks contain this project'\''s canonical patterns\n'
  printf 'for that kind of work — reading them avoids re-discovering already-solved problems.\n'
  printf '\nIf a playbook clearly does not apply to the current context, you may skip it —\n'
  printf 'this hook errs on the side of suggesting too much rather than too little.\n'
  # Name the actual file the agent / human reader can inspect (same treatment
  # as require-playbook.sh — works both at an installed `.claude/hooks/`
  # location and when the hook runs from the vendor repo).
  printf '\n(Hook: %s)\n' "${BASH_SOURCE[0]}"
  printf '</system-reminder>\n'
}

exit 0
