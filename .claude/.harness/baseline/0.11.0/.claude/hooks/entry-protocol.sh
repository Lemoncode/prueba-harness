#!/usr/bin/env bash
# Lemony — Claude Code SessionStart hook (startup|clear|compact).
#
# Delivers the entry protocol, `.claude/agents/entry-protocol.md`, to the main
# session as `additionalContext`. Claude Code gives a SessionStart hook's
# context to the main session only, never to a sub-agent, so the dispatcher the
# Orchestrator acts on stops riding in every sub-agent request (a rules file
# loads into all of them). Not on `resume`: the transcript already carries the
# copy, and a second one would duplicate it.
#
# Replies on stdout with JSON and exits 0, always:
#   - the file as `additionalContext`;
#   - past Claude Code's 10,000-character cap on hook output, the same reply
#     plus a `systemMessage` asking the human to trim: Claude Code saves the
#     output to a file and the model sees its path and a 2 KB preview, so the
#     session still has the dispatcher, degraded;
#   - the file missing, empty or unreadable: a `systemMessage` for the human and an
#     `additionalContext` that sends the model to the Orchestrator's dispatch.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Stdin guard: run by hand (no pipe), the hook does nothing.
if [ -t 0 ]; then
  PAYLOAD=""
else
  PAYLOAD="$(cat 2>/dev/null || true)"
fi
[ -n "$PAYLOAD" ] || exit 0

PROTOCOL_REL=".claude/agents/entry-protocol.md"
# The project root, not the session's current directory, which a `cd` moves.
PROJECT_ROOT="$(pwd)"
# shellcheck source=lib/project-root.sh
if [ -f "$SCRIPT_DIR/lib/project-root.sh" ] && [ -r "$SCRIPT_DIR/lib/project-root.sh" ]; then
  source "$SCRIPT_DIR/lib/project-root.sh"
  project_root
fi
REPO_ROOT="$PROJECT_ROOT"
PROTOCOL="$REPO_ROOT/$PROTOCOL_REL"
# Claude Code's cap on a hook's output, in characters of the JavaScript string
# (UTF-16 code units).
CAP=10000

reply() {
  # $1 additionalContext, $2 systemMessage (empty: none).
  if [ -n "$2" ]; then
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
      "$(printf '%s' "$2" | json_string)" \
      "$(printf '%s' "$1" | json_string)"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
      "$(printf '%s' "$1" | json_string)"
  fi
}

# A regular, readable file only: a FIFO would hang the session start. An empty
# one is no protocol either: Claude Code drops an empty context without a word.
CONTENT=""
if [ -f "$PROTOCOL" ] && [ -r "$PROTOCOL" ]; then
  CONTENT="$(cat "$PROTOCOL" 2>/dev/null)"
fi
case "$CONTENT" in
  *[![:space:]]*) ;;
  *) CONTENT="" ;;
esac
if [ -z "$CONTENT" ]; then
  HUMAN="Lemony — the entry protocol $PROTOCOL_REL is missing, empty or unreadable, so this session has no dispatcher. Run \`lemony repair\` to restore it.
(Hook: ${BASH_SOURCE[0]})"
  MODEL="Lemony — the entry protocol $PROTOCOL_REL is missing, empty or unreadable, so it was not loaded. Dispatch this session by the Dispatch and Task-fit assessment sections of .claude/agents/orchestrator.md instead, and tell the human that the entry protocol is missing and that \`lemony repair\` restores it."
  if [ "$JSON_STRING_LIB" -eq 0 ]; then
    printf '%s\n' "$MODEL"
    exit 0
  fi
  reply "$MODEL" "$HUMAN"
  exit 0
fi

if [ "$JSON_STRING_LIB" -eq 0 ]; then
  # No encoder: plain stdout still reaches the model as context.
  printf '%s\n\n(.claude/hooks/lib/json-string.sh is missing, so this protocol came as plain text; tell the human to run `lemony repair`.)\n' "$CONTENT"
  exit 0
fi

# UTF-16 length, byte-wise: every byte that is not a UTF-8 continuation byte
# starts a character, and a 4-byte one (a lead byte from 0xF0) is two units.
# Exact for valid UTF-8; a file in another encoding can be off by a few units,
# and the model reads it garbled anyway.
chars=$(printf '%s' "$CONTENT" | LC_ALL=C tr -d '\200-\277' | wc -c)
astral=$(printf '%s' "$CONTENT" | LC_ALL=C tr -cd '\360-\367' | wc -c)
LENGTH=$((chars + astral))

if [ "$LENGTH" -gt "$CAP" ]; then
  reply "$CONTENT" "Lemony — the entry protocol $PROTOCOL_REL is $LENGTH characters, over Claude Code's $CAP-character limit on hook output: the model sees only its first 2 KB and the path to the rest. Trim your edits to the file below $CAP characters.
(Hook: ${BASH_SOURCE[0]})"
  exit 0
fi

reply "$CONTENT" ""
exit 0
