#!/usr/bin/env bash
# Lemony — Claude Code PreToolUse hook (APPROVE record binding).
#
# The merge executor's stale-approve guard (lib/merge-pr.sh) trusts the latest
# comment carrying both `Reviewed-tree:` and `Diff-fingerprint:` as proof that a
# Reviewer saw that exact content. Every harness agent posts as the same user, so
# authorship cannot tell the Reviewer apart — this hook can: Claude Code puts the
# calling sub-agent's `agent_type` in the payload. On every Bash call that invokes
# `gh` and carries both markers — in the command text, or in an existing file the
# command passes as `--body-file`, `-F`, `--field body=@<file>` or `--input` — the
# call is blocked (exit 2) unless `agent_type` is `reviewer` (a Reviewer sub-agent,
# or a main session started with `--agent reviewer`). No `agent_type` means the
# main session, which never posts the record.
#
# Threat model: accident and confabulation (an Orchestrator relaying or recomputing
# a record), not a malicious insider. Not seen: a body a script generates inside the
# same command; a body fed through stdin (`< file`, a pipe) or `$(cat file)`; a file
# named through a variable or `xargs`; a post that is not a `gh` Bash call (an MCP
# tool, `curl`). A file that is unreadable or not yet written is not judged either —
# a file written in the same command is covered by the text check. Fails open:
# without jq the raw payload is grepped for the two markers and an unescaped
# `"agent_type":"reviewer"` (the command text sits in the payload with its quotes
# escaped, so it can never supply that key); a body file is then not read. A read
# that quotes both markers with their colons (`grep 'Reviewed-tree:'`) next to a
# `gh` call is blocked too — the block message says to drop the colons.

set -u

warn() {
  printf '[require-reviewer-record] %s\n' "$*" >&2
}

# Read stdin only when Claude Code is piping a payload; a developer running the
# hook interactively gets an empty payload instead of a hang on `cat`.
if [ -t 0 ]; then
  PAYLOAD=""
else
  PAYLOAD="$(cat 2>/dev/null || true)"
fi
[ -n "$PAYLOAD" ] || exit 0

TREE_MARKER='Reviewed-tree:'
FINGERPRINT_MARKER='Diff-fingerprint:'

# `gh` as a command word: at the start, or after a separator or a path slash —
# never inside another word (`ghost`, `--gh-token`).
GH_WORD_RE='(^|[^[:alnum:]_.-])gh([[:space:]]|$)'

block() {
  {
    printf 'Blocked: only the Reviewer sub-agent posts an APPROVE record (a comment carrying both\n'
    printf '`Reviewed-tree:` and `Diff-fingerprint:`). The merge executor'\''s stale-approve guard trusts\n'
    printf 'that record as proof a Reviewer saw this exact content; a record posted by anyone else\n'
    printf 'would cover content no Reviewer reviewed.\n'
    printf -- '- Do not post the record yourself, and do not route around this check (a script, another\n'
    printf '  body source, splitting the comment).\n'
    printf -- '- If a Reviewer approved but did not post, invoke the Reviewer again (fresh context) and\n'
    printf '  let it post its own verdict.\n'
    printf -- '- If you are only quoting the marker names for another reason, write them without the\n'
    printf '  trailing colon.\n'
    printf '(Hook: %s)\n' "${BASH_SOURCE[0]}"
  } >&2
  exit 2
}

# Both markers, in one text.
has_record() {
  case "$1" in
    *"$TREE_MARKER"*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *"$FINGERPRINT_MARKER"*) return 0 ;;
  esac
  return 1
}

# Strip one layer of matching outer quotes.
unquote() {
  local value="$1"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  printf '%s' "$value"
}

if ! command -v jq >/dev/null 2>&1; then
  # Unescaped keys only: inside the command's JSON string every quote is escaped.
  TOOL_BASH_RE='"tool_name"[[:space:]]*:[[:space:]]*"Bash"'
  AGENT_REVIEWER_RE='"agent_type"[[:space:]]*:[[:space:]]*"reviewer"'
  [[ "$PAYLOAD" =~ $TOOL_BASH_RE ]] || exit 0
  [[ "$PAYLOAD" =~ $GH_WORD_RE ]] || exit 0
  [[ "$PAYLOAD" =~ $AGENT_REVIEWER_RE ]] && exit 0
  has_record "$PAYLOAD" && block
  warn "jq not found — checked the command text only; a body file was not read"
  exit 0
fi

TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$TOOL" = "Bash" ] || exit 0

AGENT_TYPE="$(printf '%s' "$PAYLOAD" | jq -r '.agent_type // empty' 2>/dev/null)"
[ "$AGENT_TYPE" = "reviewer" ] && exit 0

COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$COMMAND" ] || exit 0
[[ "$COMMAND" =~ $GH_WORD_RE ]] || exit 0

has_record "$COMMAND" && block

# Body files: `--body-file <f>`, `-F <f>` (an issue/PR comment), `-F`/`--field
# key=@<f>` and `--input <f>` (a REST call), with a space or `=` before the value,
# quoted or bare. A line continued with a trailing backslash is joined first, and a
# relative file is looked up against the call's cwd and every literal `cd <dir>` in
# the command, each one read both from the call's cwd and from the `cd` before it —
# `cd a && cd b && gh … --body-file v.md` names a/b/v.md, and a `cd` in a subshell or
# a quoted string cannot shift the real path away. A `pushd`, a `cd -` or a `cd`
# through a variable is not followed.
CALL_CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$CALL_CWD" ] || CALL_CWD="$(pwd)"
JOINED="$(printf '%s\n' "$COMMAND" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }')"
VALUE_RE="(\"[^\"]*\"|'[^']*'|[^[:space:];&|)\"']+(\"[^\"]*\"|'[^']*')?)"
FILE_FLAG_RE="(^|[[:space:]])(--body-file|--input|--field|-F)([[:space:]]+|=)$VALUE_RE"
CD_RE="(^|[;&|({]|(^|[[:space:];&|(])(then|do|else))[[:space:]]*cd[[:space:]]+(--[[:space:]]+)?$VALUE_RE"

# A path as the shell would read it from the directory $1: `~/` is HOME, `/…` itself.
resolve() {
  case "$2" in
    "~/"*) printf '%s' "${HOME:-}/${2#"~/"}" ;;
    /*) printf '%s' "$2" ;;
    *) printf '%s' "$1/$2" ;;
  esac
}

BASES="$CALL_CWD"
HERE="$CALL_CWD"
while IFS= read -r match; do
  [ -n "$match" ] || continue
  dir="${match#*cd}"
  dir="${dir#"${dir%%[![:space:]]*}"}"
  case "$dir" in --*) dir="${dir#--}"; dir="${dir#"${dir%%[![:space:]]*}"}" ;; esac
  dir="$(unquote "$dir")"
  [ -n "$dir" ] && [ "$dir" != "-" ] || continue
  HERE="$(resolve "$HERE" "$dir")"
  BASES="$BASES
$(resolve "$CALL_CWD" "$dir")
$HERE"
done <<EOF
$(printf '%s\n' "$JOINED" | grep -oE "$CD_RE" 2>/dev/null)
EOF

while IFS= read -r match; do
  [ -n "$match" ] || continue
  match="${match#"${match%%[![:space:]]*}"}"
  flag="${match%%[[:space:]=]*}"
  value="${match#"$flag"}"
  value="${value#=}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="$(unquote "$value")"
  case "$flag" in
    -F | --field)
      case "$value" in
        *=@*) value="$(unquote "${value#*=@}")" ;;
        *=*) continue ;;
      esac
      ;;
  esac
  [ -n "$value" ] && [ "$value" != "-" ] || continue
  while IFS= read -r base; do
    file="$(resolve "$base" "$value")"
    [ -f "$file" ] && [ -r "$file" ] || continue
    has_record "$(cat "$file" 2>/dev/null)" && block
  done <<BASES_EOF
$BASES
BASES_EOF
done <<EOF
$(printf '%s\n' "$JOINED" | grep -oE "$FILE_FLAG_RE" 2>/dev/null)
EOF

exit 0
