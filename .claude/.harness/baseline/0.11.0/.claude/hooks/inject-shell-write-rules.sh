#!/usr/bin/env bash
# Lemony — Claude Code PreToolUse + PostToolUse/PostToolUseFailure hook (Bash: rules
# of the files a shell command changed).
#
# Claude Code injects a project rule (.claude/rules/**/*.md) after a Read, Edit or
# Write of a file its `paths:` cover, never after a shell command that writes one
# (here-doc, `sed -i`, a script). This hook delivers those rules for Bash. Before the
# command (PreToolUse) it takes a snapshot of the project's working tree: `git status`
# with the size and mtime of each path it lists, kept in .lemony/shell-writes/ under
# the call's tool_use_id. After it — PostToolUse, or PostToolUseFailure when the
# command exits non-zero (`cat > x.ts …; npm test` going red) — it takes another; a
# file changed when it is new in the list or its size or mtime moved. Only then does
# it ask the lemony CLI (`rules match --stdin`) which rules cover the changed files,
# and inject, as `additionalContext`, the ones the agent does not have yet: a line
# naming the files and asking the agent to check them against the rules, then each
# rule's whole text while the context stays within Claude Code's 10,000-character
# cap, and a line naming the rule file to Read for each one that does not fit. Every
# agent, with no role filter. Exit 0 always: it never blocks a command.
#
# What the agent has is read from its own transcript (lib/tool-loads.sh, shared
# with the gates): a Read or cat of the rule file, Claude Code's own injection, or
# an earlier injection by this hook. When the transcript cannot be read, the hook's
# own record of what it injected to that agent decides instead, which errs towards
# injecting a rule again, never towards leaving one out.
#
# Injects nothing (exit 0) when jq or git is missing, the payload has no usable
# tool_use_id or agent_id, the tree is not a git checkout, .lemony/ is not writable,
# the PreToolUse snapshot is missing, the repo has no .claude/rules, or the CLI
# cannot match. A snapshot is given up when `git status` takes over 1 s or lists over
# 2,000 paths (a build directory git does not ignore), and the hook then rests for
# 10 minutes rather than pay that on every call. Not seen: a command left running in
# the background, files git ignores, files outside the project, a file written and
# restored within the command; a file another agent changed while the command ran
# is taken for this one's.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() {
  printf '[inject-shell-write-rules] %s\n' "$*" >&2
}

# shellcheck source=lib/project-root.sh
source "$SCRIPT_DIR/lib/project-root.sh" || {
  warn 'lib/project-root.sh missing, skipping'
  exit 0
}
# shellcheck source=lib/tool-loads.sh
source "$SCRIPT_DIR/lib/tool-loads.sh" || {
  warn 'lib/tool-loads.sh missing, skipping'
  exit 0
}

if [ -t 0 ]; then
  PAYLOAD=""
else
  PAYLOAD="$(cat 2>/dev/null || true)"
fi
[ -n "$PAYLOAD" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

TAB="$(printf '\t')"
# Fields joined by a unit separator: read collapses runs of a whitespace IFS, so an
# empty agent_id between tabs would shift the session_id into its place.
US=$'\x1f'
NL=$'\n'
{ IFS="$US" read -r EVENT TOOL TOOL_USE_ID TRANSCRIPT_PATH AGENT_ID SESSION_ID; } <<EOF
$(printf '%s' "$PAYLOAD" | jq -r '[.hook_event_name, .tool_name, .tool_use_id, .transcript_path, .agent_id, .session_id]
  | map(. // "" | tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")' 2>/dev/null)
EOF
[ "${TOOL:-}" = "Bash" ] || exit 0
[[ "${TOOL_USE_ID:-}" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
[ -z "${AGENT_ID:-}" ] || [[ "$AGENT_ID" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

project_root
ROOT="$PROJECT_ROOT"
STATE_DIR="$ROOT/.lemony/shell-writes"
SNAPSHOT="$STATE_DIR/$TOOL_USE_ID"
# Set when a snapshot is given up: no snapshot is taken before then (epoch seconds).
RESTING="$STATE_DIR/resting-until"
MAX_PATHS=2000

# Optional locks off: a plain `git status` refreshes the index and takes
# .git/index.lock, which made a parallel agent's `git add` fail.
GIT=(git --no-optional-locks -C "$ROOT")

# The size and mtime of every path `git status` lists under the root, one
# `<size>\t<mtime>\t<path>` line each, the path relative to the root (git's -z
# output, so no path is quoted; a path holding a tab or a newline is left out).
# Lemony's own scratch is left out too. Returns 1 when git fails, takes over 1 s or
# lists over MAX_PATHS paths.
snapshot() {
  local out="$1" list rc entry path_ prefix count=0
  list="$out.paths"
  # git prints paths from the repository's top, which a project in a subdirectory
  # (a monorepo package) is not.
  prefix="$("${GIT[@]}" rev-parse --show-prefix 2>/dev/null)" || return 1
  # git itself in the background, not a function: the watchdog must kill git, not
  # a subshell that leaves it running.
  "${GIT[@]}" status --porcelain=v1 -z -uall --no-renames --ignore-submodules=all -- . \
    >"$list.z" 2>/dev/null &
  local git_pid=$!
  (
    trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM
    sleep 1 &
    sleeper=$!
    wait "$sleeper"
    kill "$git_pid" 2>/dev/null
  ) &
  local watchdog=$!
  # Silenced: bash reports a job the watchdog killed ("Terminated") on stderr.
  { wait "$git_pid"; } 2>/dev/null
  rc=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  if [ "$rc" -ne 0 ]; then
    rm -f "$list.z"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    count=$((count + 1))
    [ "$count" -le "$MAX_PATHS" ] || break
    path_="${entry:3}"
    path_="${path_#"$prefix"}"
    case "$path_" in
      "" | *"$TAB"* | *"$NL"* | .lemony/*) continue ;;
    esac
    printf '%s\0' "$path_"
  done <"$list.z" >"$list"
  rm -f "$list.z"
  if [ "$count" -gt "$MAX_PATHS" ]; then
    rm -f "$list"
    return 1
  fi
  if [ -s "$list" ]; then
    # Asked of stat itself, not of the OS (a Mac can have GNU coreutils first on
    # PATH), and by the `-c` it will use: BusyBox has `-c` but no `--version`, and
    # its `-f` reports the filesystem. `--` keeps a path that starts with a dash from
    # reading as an option.
    if stat -c %s -- /dev/null >/dev/null 2>&1; then
      (cd "$ROOT" && xargs -0 stat -c "%s$TAB%y$TAB%n" -- <"$list" 2>/dev/null) >"$out"
    else
      (cd "$ROOT" && xargs -0 stat -f "%z$TAB%Fm$TAB%N" -- <"$list" 2>/dev/null) >"$out"
    fi
  else
    : >"$out"
  fi
  rm -f "$list"
  return 0
}

case "${EVENT:-}" in
  PreToolUse)
    mkdir -p "$STATE_DIR" 2>/dev/null && [ -w "$STATE_DIR" ] || exit 0
    if [ -f "$RESTING" ]; then
      read -r resting_until <"$RESTING" 2>/dev/null || resting_until=0
      case "$resting_until" in "" | *[!0-9]*) resting_until=0 ;; esac
      now="$(date +%s 2>/dev/null)"
      case "$now" in "" | *[!0-9]*) now=0 ;; esac
      # A marker further out than one rest (a clock that ran ahead) is spent too.
      [ "$now" -ge "$resting_until" ] || [ "$resting_until" -gt $((now + 600)) ] || exit 0
      rm -f "$RESTING"
    fi
    trap 'rm -f "$SNAPSHOT.tmp" "$SNAPSHOT.tmp.paths" "$SNAPSHOT.tmp.paths.z"' EXIT
    # Snapshots whose PostToolUse never came (an interrupted command) and records of
    # old sessions are swept now and then, not on every call.
    if [ $((RANDOM % 50)) -eq 0 ]; then
      find "$STATE_DIR" -type f -mmin +1440 -exec rm -f {} + 2>/dev/null
    fi
    if snapshot "$SNAPSHOT.tmp"; then
      mv -f "$SNAPSHOT.tmp" "$SNAPSHOT" 2>/dev/null
    else
      echo $(($(date +%s) + 600)) >"$RESTING" 2>/dev/null
      warn "git status took over 1 s or listed over $MAX_PATHS paths in $ROOT; resting 10 minutes"
    fi
    exit 0
    ;;
  PostToolUse | PostToolUseFailure) ;;
  *) exit 0 ;;
esac

[ -f "$SNAPSHOT" ] || exit 0
BEFORE="$SNAPSHOT.before"
mv -f "$SNAPSHOT" "$BEFORE" 2>/dev/null || exit 0
AFTER="$SNAPSHOT.after"
trap 'rm -f "$BEFORE" "$AFTER" "$AFTER.paths" "$AFTER.paths.z"' EXIT
snapshot "$AFTER" || exit 0

# A path that is now a directory, or gone, is not a file the command wrote.
CHANGED=()
while IFS= read -r path_; do
  [ -n "$path_" ] && [ -f "$ROOT/$path_" ] && CHANGED+=("$ROOT/$path_")
done <<EOF
$(awk -F '\t' 'FILENAME == ARGV[1] { seen[$0] = 1; next } !($0 in seen) { print $3 }' "$BEFORE" "$AFTER")
EOF
[ ${#CHANGED[@]} -gt 0 ] || exit 0

RULES_REPO="${CLAUDE_PROJECT_DIR:-}"
[ -n "$RULES_REPO" ] && [ -d "$RULES_REPO" ] || RULES_REPO="$ROOT"
[ -d "$RULES_REPO/.claude/rules" ] || exit 0

MATCH_OUT="$(printf '%s\n' "${CHANGED[@]}" \
  | (cd "$RULES_REPO" && "$SCRIPT_DIR/lib/lemony.sh" rules match --stdin --base="$ROOT") 2>/dev/null)" || {
  warn 'could not match the rules (is the lemony CLI installed?), injecting nothing'
  exit 0
}
[ -n "$MATCH_OUT" ] || exit 0

RULES=()
SEEN="|"
while IFS="$TAB" read -r rule _; do
  [ -n "$rule" ] || continue
  case "$SEEN" in
    *"|$rule|"*) ;;
    *) RULES+=("$rule"); SEEN="$SEEN$rule|" ;;
  esac
done <<EOF
$MATCH_OUT
EOF
[ ${#RULES[@]} -gt 0 ] || exit 0

# The fallback record: one `<cksum>\t<rule>` line per rule injected to this agent,
# so a rule edited since counts as not injected.
RECORD=""
if [[ "${SESSION_ID:-}" =~ ^[A-Za-z0-9_-]+$ ]]; then
  RECORD="$STATE_DIR/injected/$SESSION_ID-${AGENT_ID:-main}"
fi
rule_stamp() {
  printf '%s\t%s' "$(cksum <"$1" 2>/dev/null | awk '{ print $1 "-" $2 }')" "$1"
}

LOADED=()
OWN_TRANSCRIPT=""
if tool_loads_own_transcript "${TRANSCRIPT_PATH:-}" "${AGENT_ID:-}" \
  && [ -n "${TRANSCRIPT_PATH:-}" ] && [ -r "$OWN_TRANSCRIPT" ] \
  && tool_loads_scan "$OWN_TRANSCRIPT" "" "${RULES[@]}"; then
  if [ ${#LOADED_TARGETS[@]} -gt 0 ]; then
    LOADED=("${LOADED_TARGETS[@]}")
  fi
elif [ -n "$RECORD" ] && [ -r "$RECORD" ]; then
  for rule in "${RULES[@]}"; do
    grep -Fxq -- "$(rule_stamp "$rule")" "$RECORD" 2>/dev/null && LOADED+=("$rule")
  done
fi

MISSING=()
for rule in "${RULES[@]}"; do
  have=0
  if [ ${#LOADED[@]} -gt 0 ]; then
    for loaded in "${LOADED[@]}"; do
      [ "$loaded" = "$rule" ] && have=1
    done
  fi
  [ "$have" -eq 1 ] || MISSING+=("$rule")
done
[ ${#MISSING[@]} -gt 0 ] || exit 0

# The files each missing rule covers, relative to the root: `<rule>\t<file>` lines.
PAIRS="$(
  while IFS="$TAB" read -r rule file; do
    for missing in "${MISSING[@]}"; do
      [ "$rule" = "$missing" ] && printf '%s\t%s\n' "$rule" "${file#"$ROOT"/}"
    done
  done <<EOF
$MATCH_OUT
EOF
)"

FILES_ARGS=()
i=0
for rule in "${MISSING[@]}"; do
  FILES_ARGS+=(--rawfile "r$i" "$rule")
  i=$((i + 1))
done

RULE_PATHS="$(printf '%s\n' "${MISSING[@]}")"
# Claude Code keeps a hook's additionalContext inline up to 10,000 UTF-16 units
# (measured on 2.1.294); past it the model gets a 2 KB preview. Prints the hook's
# JSON reply, then one line per rule whose whole text it carries.
REPLY="$(jq -n -r --arg pairs "$PAIRS" --arg paths "$RULE_PATHS" --arg event "$EVENT" \
  --argjson cap 10000 "${FILES_ARGS[@]}" '
  def units: [explode[] | if . > 65535 then 2 else 1 end] | add // 0;
  def listed: if length > 20 then (.[:20] | join(", ")) + ", and \(length - 20) more" else join(", ") end;
  ($pairs | split("\n") | map(select(. != "") | split("\t") | {rule: .[0], file: .[1]})) as $pairs
  | ($paths | split("\n") | map(select(. != ""))) as $rules
  | ($ARGS.named) as $named
  | "This command changed \($pairs | map(.file) | unique | listed), which the project rules below cover. Check what it wrote against them before you go on, and fix what does not follow them." as $head
  | "\n\nThese rules did not fit here; Read each one before you go on:" as $pointer_head
  | [range(0; $rules | length) as $i | {
      rule: $rules[$i],
      full: "\n\nContents of \($rules[$i]):\n\n\($named["r\($i)"])",
      pointer: "\n  - \($pairs | map(select(.rule == $rules[$i]) | .file) | listed): Read(file_path=\"\($rules[$i])\")"
    }] as $blocks
  | reduce range(0; $blocks | length) as $i ({text: $head, pointers: [], full: []};
      ([$blocks[$i + 1:][] | .pointer] | add // "") as $rest
      | (.text + $blocks[$i].full) as $with
      | if ($with | units)
           + (if $rest != "" or (.pointers | length) > 0
              then $pointer_head + (.pointers | add // "") + $rest | units
              else 0 end) <= $cap
        then .text = $with | .full += [$blocks[$i].rule]
        else .pointers += [$blocks[$i].pointer]
        end)
  | ({hookSpecificOutput: {hookEventName: $event,
      additionalContext: (.text + (if (.pointers | length) > 0 then $pointer_head + (.pointers | add) else "" end))}}
     | tojson),
    .full[]
' 2>/dev/null)" || exit 0
[ -n "$REPLY" ] || exit 0

printf '%s\n' "${REPLY%%"$NL"*}"

# Only a rule whose whole text went out counts as injected; a stamp already there is
# not added again.
if [ -n "$RECORD" ] && [ "$REPLY" != "${REPLY%%"$NL"*}" ]; then
  mkdir -p "$(dirname "$RECORD")" 2>/dev/null \
    && while IFS= read -r rule; do
      [ -n "$rule" ] || continue
      stamp="$(rule_stamp "$rule")"
      grep -Fxq -- "$stamp" "$RECORD" 2>/dev/null || printf '%s\n' "$stamp"
    done <<EOF >>"$RECORD"
${REPLY#*"$NL"}
EOF
fi
exit 0
