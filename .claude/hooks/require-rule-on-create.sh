#!/usr/bin/env bash
# Lemony — Claude Code PreToolUse hook (new-file rule gate).
#
# On a Write of a file that does not exist yet (or an Edit with an empty
# old_string, which creates it), find the project's rules
# (.claude/rules/**/*.md) whose `paths:` globs match it, and block the call (exit 2)
# while any of them has not reached the writing agent, naming the rule file to read.
#
# Why only new files: Claude Code injects a matching rule into the agent after a
# Read, Edit or Write of a file it covers — after the call, so the first Write of a
# new file never sees it, while an Edit (and a Write over an existing file) needs
# a prior Read that already brought it. A blocked call injects nothing, so the
# message points at the rule file itself. Measured on Claude Code 2.1.290; Lemony's
# own Claude Code e2e suite watches it.
#
# Which rules match is asked of the lemony CLI (`rules match`), which matches the
# way Claude Code does (the same `ignore` package): the project's rules
# ($CLAUDE_PROJECT_DIR; the working directory when it is unset), and the file's path
# relative to the project — and, when the hook runs in another git worktree of the
# same repo, also relative to the project's place in that worktree. A rule has reached the agent
# when its whole current text came back in a tool result of the agent's own
# transcript (a Read or cat of the rule file), or Claude Code injected its current
# text — lib/tool-loads.sh, shared with the other load hooks. A read sent in the
# same message as the write does not count.
#
# Fails open (exit 0) when jq is missing, the repo has no .claude/rules, the CLI
# cannot match (not installed, or it failed), the transcript is unreadable or could
# not be scanned, the payload's agent_id is malformed, or the shared lib is missing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/tool-loads.sh
source "$SCRIPT_DIR/lib/tool-loads.sh" || {
  printf '[require-rule-on-create] lib/tool-loads.sh missing, skipping the check\n' >&2
  exit 0
}

warn() {
  printf '[require-rule-on-create] %s\n' "$*" >&2
}

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
  Write) ;;
  # An Edit whose old_string is empty creates the file when it does not exist.
  Edit) [ "$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.old_string == ""')" = "true" ] || exit 0 ;;
  *) exit 0 ;;
esac

FILEPATH="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty')"
[ -n "$FILEPATH" ] || exit 0

# A relative path is the session's; the rules are the project's. Claude Code runs a
# hook from the session's current directory, which a `cd` may have moved.
case "$FILEPATH" in
  /*) ;;
  *) FILEPATH="$(pwd)/$FILEPATH" ;;
esac
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] || REPO_ROOT="$(pwd)"

# An existing file (or a symlink in its place) is not created by this Write.
if [ -e "$FILEPATH" ] || [ -L "$FILEPATH" ]; then
  exit 0
fi

# No rules directory, no rule to require — and no CLI call on the hot path.
[ -d "$REPO_ROOT/.claude/rules" ] || exit 0

# The rules are the project's. Claude Code matches a file's path from the project,
# except for a sub-agent in another git worktree of the same repo, whose paths it
# matches from the project's place in that worktree. The payload cannot tell that
# sub-agent from a session that moved into the worktree, so there the gate requires
# the rules matched from both bases: the cost of the wrong one is a read too many.
BASES=("$REPO_ROOT")
{ IFS= read -r MAIN_TOP; IFS= read -r MAIN_GIT; IFS= read -r MAIN_PREFIX; } <<EOF
$(git -C "$REPO_ROOT" rev-parse --show-toplevel --path-format=absolute --git-common-dir --show-prefix 2>/dev/null)
EOF
{ IFS= read -r HERE_TOP; IFS= read -r HERE_GIT; } <<EOF
$(git rev-parse --show-toplevel --path-format=absolute --git-common-dir 2>/dev/null)
EOF
# A git older than 2.31 echoes `--path-format=absolute` back: only absolute git dirs
# tell two checkouts of one repo.
case "$MAIN_GIT" in /*) ;; *) MAIN_GIT="" ;; esac
if [ -n "$MAIN_TOP" ] && [ -n "$HERE_TOP" ] && [ "$MAIN_TOP" != "$HERE_TOP" ] \
  && [ -n "$MAIN_GIT" ] && [ "$MAIN_GIT" = "$HERE_GIT" ]; then
  if [ -n "$MAIN_PREFIX" ]; then
    BASES+=("$HERE_TOP/${MAIN_PREFIX%/}")
  else
    BASES+=("$HERE_TOP")
  fi
fi

MATCHED=()
SEEN="|"
for base in "${BASES[@]}"; do
  MATCH_OUT="$(cd "$REPO_ROOT" && "$SCRIPT_DIR/lib/lemony.sh" rules match --path="$FILEPATH" --base="$base" 2>/dev/null)" || {
    # The project's base decides alone; a failure on the worktree's keeps its matches.
    if [ "$base" = "$REPO_ROOT" ]; then
      warn "could not match the rules (is the lemony CLI installed?), allowing $FILEPATH"
      exit 0
    fi
    warn "could not match the rules from $base, checking the project's only"
    continue
  }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$SEEN" in
      *"|$line|"*) ;;
      *) MATCHED+=("$line"); SEEN="$SEEN$line|" ;;
    esac
  done <<EOF
$MATCH_OUT
EOF
done
[ ${#MATCHED[@]} -gt 0 ] || exit 0

TRANSCRIPT_PATH="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty')"
AGENT_ID="$(printf '%s' "$PAYLOAD" | jq -r '.agent_id // empty')"
TOOL_USE_ID="$(printf '%s' "$PAYLOAD" | jq -r '.tool_use_id // empty')"
tool_loads_own_transcript "$TRANSCRIPT_PATH" "$AGENT_ID" || {
  warn "unexpected agent_id, allowing $FILEPATH"
  exit 0
}

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -r "$OWN_TRANSCRIPT" ]; then
  warn "transcript not accessible, allowing $FILEPATH"
  exit 0
fi

tool_loads_scan "$OWN_TRANSCRIPT" "$TOOL_USE_ID" "${MATCHED[@]}" || {
  warn "could not scan the transcript, allowing $FILEPATH"
  exit 0
}

MISSING=()
for rule in "${MATCHED[@]}"; do
  loaded=0
  if [ ${#LOADED_TARGETS[@]} -gt 0 ]; then
    for t in "${LOADED_TARGETS[@]}"; do
      [ "$t" = "$rule" ] && loaded=1
    done
  fi
  [ "$loaded" -eq 1 ] || MISSING+=("$rule")
done

[ ${#MISSING[@]} -gt 0 ] || exit 0

# The CLI prints paths under its own (physical) working directory.
PHYSICAL_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
{
  printf 'Before creating %s, read the project rule(s) for this kind of file:\n\n' "$FILEPATH"
  for rule in "${MISSING[@]}"; do
    printf '  - %s\n' "${rule#"$PHYSICAL_ROOT"/}"
  done
  printf '\nClaude Code adds a rule to your context when you read or edit a file it\n'
  printf 'covers, but only after the call: the first Write of a new file never has\n'
  printf 'it, and a blocked call does not add it. Read each rule now:\n\n'
  for rule in "${MISSING[@]}"; do
    printf '  Read(file_path="%s")\n' "$rule"
  done
  printf '\nA `cat` that shows you the whole file also counts. A partial read does\n'
  printf 'not, nor a read sent in the same message as this write, nor a read by\n'
  printf 'another agent. If Read answers that the file is unchanged, cat the whole\n'
  printf 'file. Then retry.\n'
  printf '\n(Hook: %s)\n' "${BASH_SOURCE[0]}"
} >&2

exit 2
