#!/usr/bin/env bash
# Find which files an agent loaded in full, from its own Claude Code transcript (JSONL).
# Shared by require-playbook.sh, suggest-playbook.sh (playbooks), require-pass-load.sh
# (review-pass SKILL.md files), require-rule-on-create.sh and inject-shell-write-rules.sh
# (rules), so the five hooks credit a load by one rule.
#
# A file is loaded when its whole current text came back to the agent in one tool
# result: the output of a `cat` (alone, in a composite read, in a loop, with a glob —
# however the command was written), or a `Read` whose result holds the whole file (its
# result numbers the lines; the numbers are ignored). The evidence is what the agent
# received, not the command it ran, so these load nothing: a partial read (`head`,
# `sed -n` over part of the file, a `Read` whose `limit` stops before the end), output
# piped on, captured or redirected, a cat that did not run, an output Claude Code saved
# to a file and showed as a 2 KB preview (unless the file fits in the preview), and an
# output it cut in the middle. A range or a failing composite that still printed the
# whole file does load it.
#
# Results are compared after dropping `\r`, trailing blanks on each line, and blank lines
# at the file's start and end; the file's own leading byte order mark is dropped too, as
# Claude Code's Read drops it. A file that changed after the agent read it is not loaded
# until it reads the new text. Only tool_result blocks of `.message.content` count:
# what the model received.
#
# A rule is also loaded when Claude Code injected it: after a Read, Edit or Write of a
# file its `paths:` match, it appends a `nested_memory` attachment that sends the model
# the rule's body (frontmatter dropped) and records the file it read in `rawContent`
# (in `content` when the two are the same). The rule counts when that file text holds
# its current text — measured on Claude Code 2.1.290. An agent that read the
# rule file itself gets no injection: the Read result credits it.
#
# A rule is loaded, too, when a hook injected its current text: a hook's
# `additionalContext` is recorded as a `hook_additional_context` attachment whose
# `content` lists each hook's text (measured on Claude Code 2.1.302). This is how
# inject-shell-write-rules.sh delivers a rule after a shell command changed a file it
# covers, so the gates do not ask again for a rule it already delivered.
#
# A skill is loaded when its body reached the agent: Claude Code sends it after the
# `Skill` call as a message that opens with `Base directory for this skill: <dir>`, and
# the directory says which skill it was (a personal skill can shadow the project's under
# the same name).
#
# Two kinds of result do not count although they are in the transcript:
#   - those of the message that holds the gated call. The model wrote that call before
#     it saw them: a `Read` sent beside a `Write` returns first, yet the Write's content
#     was already decided.
#   - those before the last compaction, unless Claude Code kept that message
#     (`compactMetadata.preservedMessages`): the model holds only a summary of the rest.
#     The same goes for a rule injection.
#     A file Claude Code attaches again after the compaction (an `attachment` of type
#     `file`) is text the model received, and counts like a result.
#
# Contract:
#   tool_loads_own_transcript <transcript_path> <agent_id>
#     Sets OWN_TRANSCRIPT to the writing agent's own transcript: the sub-agent file
#     `<transcript>/subagents/agent-<agent_id>.jsonl` when the payload carries an
#     agent_id (it does only inside a sub-agent), else the session transcript — the
#     main session, including one started with `--agent`, whose payload carries
#     `agent_type` without `agent_id`. Returns 1 for an agent_id that is not a plain id
#     (OWN_TRANSCRIPT left empty): the caller warns and fails open.
#   tool_loads_scan <transcript> <tool_use_id> <target>...
#     Sets LOADED_TARGETS to the targets (paths) whose text the transcript shows in
#     full, and LOADED_SKILL_DIRS to the base directories of the skills whose body
#     reached the agent. <tool_use_id> is the payload's id of the gated call ("" when
#     there is none): the results of its message are left out. An unreadable or empty
#     target is not loaded. Returns 1 when the transcript could not be scanned (jq
#     failed): the caller warns and fails open.

tool_loads_own_transcript() {
  local transcript_path="$1" agent_id="$2"
  OWN_TRANSCRIPT=""
  if [ -n "$agent_id" ]; then
    [[ "$agent_id" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    OWN_TRANSCRIPT="${transcript_path%.jsonl}/subagents/agent-${agent_id}.jsonl"
  else
    OWN_TRANSCRIPT="$transcript_path"
  fi
  return 0
}

tool_loads_scan() {
  LOADED_TARGETS=()
  LOADED_SKILL_DIRS=()
  local transcript="$1" current="$2"
  shift 2
  local -a targets=() files=()
  local -a probes=(-e 'Base directory for this skill: ' -e '"compact_boundary"' -e '"nested_memory"' -e '"hook_additional_context"')
  local target probe narrow=1 i=0
  for target in "$@"; do
    targets+=("$target")
    if [ -f "$target" ] && [ -r "$target" ]; then
      # Read by jq itself: a text passed as an argument hits the per-argument size
      # limit (128 KB on Linux).
      files+=(--rawfile "t$i" "$target")
      # A line of the file that the JSONL holds verbatim (no quote, backslash, tab or
      # non-ASCII byte to escape) narrows the lines jq has to parse.
      probe="$(LC_ALL=C awk '
        { sub(/[ \t\r]+$/, "") }
        /^[[:print:]]+$/ && !index($0, "\"") && !index($0, "\\") && length($0) > length(best) { best = $0 }
        END { if (length(best) >= 12) print best }' "$target" 2>/dev/null)"
      if [ -n "$probe" ]; then
        probes+=(-e "$probe")
      else
        narrow=0
      fi
    fi
    i=$((i + 1))
  done

  # The gated call's message: its id, then the ids of every tool call it holds.
  local message_id="" current_calls=""
  if [ -n "$current" ]; then
    message_id="$(grep -F -e "$current" "$transcript" 2>/dev/null \
      | jq -r --arg id "$current" 'select(.type == "assistant")
          | select(any(.message.content[]?; type == "object" and .id == $id))
          | .message.id // empty' 2>/dev/null | tail -n 1)"
  fi
  if [ -n "$message_id" ]; then
    current_calls="$(grep -F -e "$message_id" "$transcript" 2>/dev/null \
      | jq -r --arg id "$message_id" 'select(.type == "assistant" and .message.id == $id)
          | .message.content[]? | select(type == "object" and .type == "tool_use") | .id // empty' \
        2>/dev/null)"
  fi

  # Raw lines are read whole with --rawfile, not with -R: jq 1.7 reads -R input in ~4 KB
  # chunks and garbles a multibyte character that straddles two of them.
  local out
  out="$(
    {
      if [ "$narrow" -eq 1 ]; then
        grep -F "${probes[@]}" "$transcript"
      else
        grep -F -e '"tool_result"' "${probes[@]}" "$transcript"
      fi 2>/dev/null || true
    } | jq -n -r --rawfile jsonl /dev/stdin --arg current "$current_calls" \
      --argjson count "${#targets[@]}" ${files[@]+"${files[@]}"} '
      def trailing: gsub("[ \t]+(?=\n|\\z)"; "");
      def unnumbered: gsub("(?<nl>\\A|\n) *[0-9]+(\t|→)"; "\(.nl)");
      def trimblank: sub("\\A\n+"; "") | sub("\n+\\z"; "");
      def text: if type == "string" then .
        elif type == "array" then map(select(type == "object" and .type == "text") | .text // "") | join("\n")
        else "" end;
      ($ARGS.named) as $named
      | [range(0; $count) | ($named["t\(.)"] // "" | sub("\\A\ufeff"; "") | gsub("\r"; "") | trailing | trimblank)] as $want
      | ($current | split("\n") | map(select(. != "")) | reduce .[] as $id ({}; .[$id] = true)) as $skip
      | [$jsonl | split("\n")[] | select(. != "") | fromjson? | select(type == "object")] as $rows
      | ([range(0; $rows | length) | select($rows[.].type == "system" and $rows[.].subtype == "compact_boundary")]
         | last // -1) as $boundary
      | (if $boundary < 0 then {}
         else ($rows[$boundary].compactMetadata.preservedMessages
               | (.allUuids // .uuids // []) | reduce .[] as $u ({}; .[$u | tostring] = true))
         end) as $kept
      | reduce (range(0; $rows | length) as $r
          | select($r > $boundary or $kept[$rows[$r].uuid // "" | tostring])
          | $rows[$r]) as $row
          ({hit: {}, dirs: {}};
           if ($row.sourceToolUseID // null) != null
              and ($skip[$row.sourceToolUseID | tostring] | not)
              and ($row.message.content | text | startswith("Base directory for this skill: "))
           then .dirs[$row.message.content | text | split("\n")[0] | ltrimstr("Base directory for this skill: ")] = true
           else
             reduce (($row.message.content? | arrays | .[]
                 | select(type == "object" and .type == "tool_result")
                 | select($skip[.tool_use_id // "" | tostring] | not) | .content | text),
               ($row | select(.type == "attachment" and .attachment.type? == "file")
                 | .attachment.content.file.content? // "" | text),
               ($row | select(.type == "attachment" and .attachment.type? == "nested_memory")
                 | .attachment.content | objects | .rawContent // .content // "" | text),
               ($row | select(.type == "attachment" and .attachment.type? == "hook_additional_context")
                 | .attachment.content | arrays | .[] | strings)) as $b (.;
               ($b | gsub("\r"; "")) as $raw
               | ($raw | trailing) as $plain
               | . as $acc
               | ([range(0; $want | length) | tostring | select(($acc.hit[.] | not) and $want[tonumber] != "")]) as $open
               | if ($open | length) == 0 then .
                 else
                   reduce ($open[] as $i | select($plain | contains($want[$i | tonumber])) | $i) as $i (.; .hit[$i] = true)
                   | . as $acc2
                   | ($open | map(select($acc2.hit[.] | not))) as $rest
                   | if ($rest | length) == 0 then .
                     else ($raw | unnumbered | trailing) as $bare
                       | reduce ($rest[] as $i | select($bare | contains($want[$i | tonumber])) | $i) as $i (.; .hit[$i] = true)
                     end
                 end)
           end)
      | (.hit | keys[] | "T\t" + .), (.dirs | keys[] | "K\t" + .)
    ' 2>/dev/null
  )" || return 1

  local kind value
  while IFS="$(printf '\t')" read -r kind value; do
    case "$kind" in
      T) LOADED_TARGETS+=("${targets[$value]}") ;;
      K) LOADED_SKILL_DIRS+=("$value") ;;
    esac
  done <<EOF
$out
EOF
  return 0
}
