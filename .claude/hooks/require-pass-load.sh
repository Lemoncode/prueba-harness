#!/usr/bin/env bash
# Lemony — Claude Code PreToolUse hook (review pass load proof).
#
# On a Write/Edit of a review ledger (`.claude/state/tasks/<id>/review-ledger/*.json`),
# read the passes the record lists — each `"name": "<pass>"` whose skill is installed at
# `.claude/skills/<pass>/SKILL.md` — and require, for each, a load of that SKILL.md in
# the WRITING agent's own transcript, by the rule lib/tool-loads.sh applies: the body of
# that skill sent by the `Skill` tool (the project's skill, not a personal one of the same
# name), or the file's whole text in a tool result (a `Read`, or a `cat` however written;
# a partial, piped, captured or persisted-as-preview output is not a load). A pass is its
# procedure, so a ledger may only attest a pass whose procedure this agent loaded. Blocks
# (exit 2) naming each pass that was not loaded.
#
# Own transcript: inside a sub-agent the payload carries `agent_id`, and the agent's
# tool calls live in `<transcript>/subagents/agent-<agent_id>.jsonl` (the payload's
# `transcript_path` is the parent session's); in the main session it is
# `transcript_path` itself. A sibling sub-agent's load never counts.
#
# Fails open (exit 0, with a warning where a check was skipped) when jq or the shared lib
# is missing, the tool is not Write/Edit, the path is not a ledger, the record lists no
# installed pass, the payload's agent_id is malformed, or the transcript is unreadable or
# could not be scanned — like `require-rule-on-create.sh`, it is an enforcement layer,
# not a gate of last resort; the ledger validator still checks the record.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/tool-loads.sh
source "$SCRIPT_DIR/lib/tool-loads.sh" || {
  printf '[require-pass-load] lib/tool-loads.sh missing, skipping the check\n' >&2
  exit 0
}

warn() {
  printf '[require-pass-load] %s\n' "$*" >&2
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

TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)"
case "$TOOL" in
  Write|Edit) ;;
  Bash)
    # The load check reads the record a Write or Edit carries; a shell write into the
    # ledger directory would skip it, so it is refused and sent to the Write tool.
    COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    case "$COMMAND" in
      *review-ledger/*) ;;
      *) exit 0 ;;
    esac
    # A ledger is a .json under a review-ledger directory; source files of a module that
    # happens to be named review-ledger (`src/review-ledger/x.ts`) are not.
    # A copy into the directory itself (`cp x <ledger dir>/`) lands a ledger too.
    LEDGER_DIR_RE='state/tasks/[^/[:space:]]+/review-ledger/?\.?'
    TARGET_RE='review-ledger/[^[:space:];&|<>"'"'"']*\.json'
    WRITE_RE="(>>?\\|?|(^|[^A-Za-z0-9_-])tee([[:space:]]+-a)?)[[:space:]]*[\"']?[^[:space:];&|]*${TARGET_RE}|(^|[;&|[:space:]])(cp|mv|install|sed[[:space:]]+-i[^;&|]*|perl([[:space:]]+-[A-HJ-LN-Za-z0-9]+)*[[:space:]]+-[A-HJ-LN-Za-z0-9]*i[^;&|]*)[[:space:]][^;&|]*(${TARGET_RE}|${LEDGER_DIR_RE})[\"']?[[:space:]]*($|[;&|])"
    if [[ "$COMMAND" =~ $WRITE_RE ]]; then
      {
        printf 'Write the review ledger with the Write tool (Edit to correct it), not from the shell:\n'
        printf 'the check that each pass it lists was loaded runs on those two tools.\n'
        printf '\n(Hook: %s)\n' "${BASH_SOURCE[0]}"
      } >&2
      exit 2
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac

FILEPATH="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$FILEPATH" ] || exit 0

# Match on the repo-relative path; a path outside the repo is never this repo's ledger. The
# repo root is the toplevel of the session's cwd (the payload's, else ours), so a hook fired
# from a subdirectory still sees the ledger.
CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd)"
TOPLEVEL="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT="${TOPLEVEL:-$CWD}"

# A path can reach the repo through a symlink (`/tmp` → `/private/tmp`, a linked home), and
# git prints the toplevel physically, so the file path is tried against the toplevel in
# both spellings and against the cwd as given.
REL=""
LOGICAL_TOPLEVEL=""
case "$CWD" in
  "$TOPLEVEL" | "$TOPLEVEL"/*) ;;
  *)
    # The cwd's own spelling of the toplevel: strip the part below it, physically measured.
    BELOW=""
    PHYSICAL_CWD="$(cd "$CWD" 2>/dev/null && pwd -P || true)"
    if [ -n "$TOPLEVEL" ] && [ -n "$PHYSICAL_CWD" ]; then
      BELOW="${PHYSICAL_CWD#"$TOPLEVEL"}"
      [ "$BELOW" != "$PHYSICAL_CWD" ] && LOGICAL_TOPLEVEL="${CWD%"$BELOW"}"
    fi
    ;;
esac
for root in "$TOPLEVEL" "$LOGICAL_TOPLEVEL" "$CWD"; do
  [ -n "$root" ] || continue
  case "$FILEPATH" in
    "$root"/*)
      REL="${FILEPATH#"$root"/}"
      break
      ;;
  esac
done
if [ -z "$REL" ]; then
  case "$FILEPATH" in
    /*)
      case "$FILEPATH" in
        */review-ledger/*.json) warn "ledger path outside the session's repo, allowing $FILEPATH" ;;
      esac
      exit 0
      ;;
    *) REL="${FILEPATH#./}" ;;
  esac
fi

LEDGER_RE='^\.claude/state/tasks/[^/]+/review-ledger/[^/]+\.json$'
if ! [[ "$REL" =~ $LEDGER_RE ]]; then
  case "$REL" in
    */review-ledger/*.json) warn "not a ledger path this hook reads, allowing $FILEPATH" ;;
  esac
  exit 0
fi

# The record the write leaves behind: a Write's content; an Edit applied to the file on
# disk (its old string replaced, as the tool does), or its new string when there is no file.
if [ "$TOOL" = "Edit" ] && [ -r "$FILEPATH" ]; then
  TEXT="$(printf '%s' "$PAYLOAD" | jq -r --rawfile disk "$FILEPATH" \
    '.tool_input as $i | ($disk | split($i.old_string // "") | join($i.new_string // ""))' 2>/dev/null)"
else
  TEXT="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)"
fi

if [ -z "$TEXT" ]; then
  warn "could not read the record being written, allowing $FILEPATH"
  exit 0
fi

LISTED=()
SKILLS_DIR="$REPO_ROOT/.claude/skills"
if [ -d "$SKILLS_DIR" ]; then
  for skill_dir in "$SKILLS_DIR"/*/; do
    [ -f "${skill_dir}SKILL.md" ] || continue
    name="$(basename "$skill_dir")"
    # Pass names are kebab-case; anything else cannot be a ledger pass and is no regex.
    [[ "$name" =~ ^[a-z0-9-]+$ ]] || continue
    if printf '%s' "$TEXT" | grep -E -q "\"name\"[[:space:]]*:[[:space:]]*\"$name\""; then
      LISTED+=("$name")
    fi
  done
fi
[ ${#LISTED[@]} -gt 0 ] || exit 0

TRANSCRIPT_PATH="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null)"
AGENT_ID="$(printf '%s' "$PAYLOAD" | jq -r '.agent_id // empty' 2>/dev/null)"
TOOL_USE_ID="$(printf '%s' "$PAYLOAD" | jq -r '.tool_use_id // empty' 2>/dev/null)"
tool_loads_own_transcript "$TRANSCRIPT_PATH" "$AGENT_ID" || {
  warn "unexpected agent_id, allowing $FILEPATH"
  exit 0
}

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -r "$OWN_TRANSCRIPT" ]; then
  warn "transcript not accessible, allowing $FILEPATH"
  exit 0
fi

TARGETS=()
for name in "${LISTED[@]}"; do
  TARGETS+=("$REPO_ROOT/.claude/skills/$name/SKILL.md")
done
tool_loads_scan "$OWN_TRANSCRIPT" "$TOOL_USE_ID" "${TARGETS[@]}" || {
  warn "could not scan the transcript, allowing $FILEPATH"
  exit 0
}

# A skill body counts when its base directory is this repo's skill directory, compared
# physically: Claude Code names it by the session's cwd, which may be a symlinked spelling.
pass_loaded() {
  local name="$1" t own
  own="$(cd "$REPO_ROOT/.claude/skills/$name" 2>/dev/null && pwd -P)"
  if [ -n "$own" ] && [ ${#LOADED_SKILL_DIRS[@]} -gt 0 ]; then
    for t in "${LOADED_SKILL_DIRS[@]}"; do
      [ "$(cd "$t" 2>/dev/null && pwd -P)" = "$own" ] && return 0
    done
  fi
  if [ ${#LOADED_TARGETS[@]} -gt 0 ]; then
    for t in "${LOADED_TARGETS[@]}"; do
      [ "$t" = "$REPO_ROOT/.claude/skills/$name/SKILL.md" ] && return 0
    done
  fi
  return 1
}

MISSING=()
for name in "${LISTED[@]}"; do
  pass_loaded "$name" || MISSING+=("$name")
done
[ ${#MISSING[@]} -gt 0 ] || exit 0

{
  printf 'The ledger %s lists review passes this agent never loaded:\n\n' "$REL"
  for name in "${MISSING[@]}"; do
    printf '  - %s\n' "$name"
  done
  printf '\nA pass is the procedure in its SKILL.md, so a ledger attests only a pass whose\n'
  printf 'procedure this agent loaded (the Skill tool, or a Read or cat of the whole file):\n\n'
  for name in "${MISSING[@]}"; do
    printf '  Skill(skill="%s")   or   Read(file_path="%s/.claude/skills/%s/SKILL.md")\n' "$name" "$REPO_ROOT" "$name"
  done
  printf '\nLoad each one, run it over the diff, update its entry with what it found, and\n'
  printf 'retry this write. Loads by another agent do not count, nor does a command whose\n'
  printf 'output was too large and was saved to a file, nor a load sent in the same message\n'
  printf 'as this write. If Read answers that the file is unchanged, cat the whole file.\n'
  printf 'A Skill call counts only when the project'\''s skill answered it: when a personal\n'
  printf 'skill of the same name shadows it, Read the SKILL.md instead.\n'
  printf '\n(Hook: %s)\n' "${BASH_SOURCE[0]}"
} >&2

exit 2
