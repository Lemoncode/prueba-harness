#!/usr/bin/env bash
# Discover playbooks from two layers and expose lookup helpers used by the
# require-playbook and suggest-playbook hooks.
#
# Layers:
#   - Local:  <repo_root>/docs/playbooks/<topic>.md          (committed)
#   - Global: <home>/.claude/playbooks/<topic>.md            (per-developer)
# A local file shadows the global one for the same topic (filename stem).
#
# Frontmatter (the playbook format):
#   applies_to:  list of bash globs    → file paths that REQUIRE this playbook
#   keywords:    list of regex strings → prompts that SUGGEST this playbook
# Both lists are optional and independent; missing/empty lists are no-ops.
#
# Frontmatter is read with a SINGLE awk pass over every discovered playbook
# (`_scan_frontmatter_tsv`), not one `yq` fork per playbook (the
# per-file fork dominated hook latency, blowing the <50ms p99 target past ~5
# playbooks). awk is also the only YAML reader now: the keyword format is
# constrained to the awk-parseable subset (no `\b`/`\d` escape
# sequences), so `yq`'s extra fidelity was unused while its ~10-30ms cold fork
# was pure cost. jq remains the keyword regex engine (Oniguruma, case-insensitive),
# batched into one invocation across all keywords. Without jq, suggestion lookups
# return zero matches (fail open) — init.sh prints a doctor warning when it is missing.
#
# Bash 3.2 compatibility (intentional design — do not revert): macOS still
# ships `/bin/bash` 3.2 (no associative arrays, no `globstar` shopt, no `**`
# in case patterns). The helpers below avoid all three by (a) tracking
# shadowed topics in a `|topic|topic|` string and (b) converting each
# applies_to glob into a POSIX-ERE regex matched with `[[ =~ ]]`, which works
# identically on 3.2 and 4+. Switching to `shopt -s globstar` would silently
# regress on stock macOS — keep the regex path even when bash 4+ is present.

# Resolve the two playbook lookup dirs into PLAYBOOKS_LOCAL_DIR / PLAYBOOKS_GLOBAL_DIR
# from `harness.config.yml`'s `paths` block (config-driven):
#   paths.playbooks         → local layer, repo-relative   (default docs/playbooks)
#   paths.playbooks_global  → global layer, ~ expanded     (default ~/.claude/playbooks)
#
# Read directly with ONE awk pass — ~2ms, far under a node CLI shell-out (~40ms,
# which would breach the per-fire budget) and with no materialized state file to
# go stale before an `update` command exists (P7). Falls back to the baked
# defaults when the config, its `paths` block, or a key is absent or commented
# out (fresh clone, the vendor repo dogfooding itself, an un-customized install),
# and when the config is not a regular file.
_resolve_playbook_dirs() {
  local repo_root="$1"
  local home_dir="$2"
  PLAYBOOKS_LOCAL_DIR="$repo_root/docs/playbooks"
  PLAYBOOKS_GLOBAL_DIR="$home_dir/.claude/playbooks"

  local config="$repo_root/harness.config.yml"
  # `-f` as well as `-r`: a FIFO is readable, and awk on it would hang the hook.
  { [ -f "$config" ] && [ -r "$config" ]; } || return 0

  # One awk pass: within the top-level `paths:` block, emit `<key>\t<value>` for
  # the (uncommented) `playbooks` / `playbooks_global` entries — inline comments
  # and surrounding quotes stripped. Any column-0 line ends the block.
  local key value local_rel="" global_raw=""
  while IFS=$'\t' read -r key value; do
    case "$key" in
      playbooks) local_rel="$value" ;;
      playbooks_global) global_raw="$value" ;;
    esac
  done < <(awk -v sq="'" '
    function unquote(v,   q) {
      q = substr(v, 1, 1)
      if (length(v) >= 2 && (q == "\"" || q == sq) && substr(v, length(v), 1) == q) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    /^[^[:space:]]/ { in_paths = ($0 ~ /^paths:[[:space:]]*$/) ? 1 : 0; next }
    in_paths != 1 { next }
    {
      line = $0
      sub(/#.*$/, "", line)
      if (match(line, /^[[:space:]]+(playbooks|playbooks_global)[[:space:]]*:/)) {
        key = line; sub(/^[[:space:]]+/, "", key); sub(/[[:space:]]*:.*$/, "", key)
        val = line; sub(/^[[:space:]]+[A-Za-z_]+[[:space:]]*:[[:space:]]*/, "", val)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        val = unquote(val)
        if (val != "") print key "\t" val
      }
    }
  ' "$config" 2>/dev/null)

  [ -n "$local_rel" ] && PLAYBOOKS_LOCAL_DIR="$repo_root/$local_rel"
  if [ -n "$global_raw" ]; then
    # Expand a leading `~`/`~/`; honor an absolute path; treat anything else as
    # repo-relative (matches the local layer's contract).
    case "$global_raw" in
      "~") PLAYBOOKS_GLOBAL_DIR="$home_dir" ;;
      "~/"*) PLAYBOOKS_GLOBAL_DIR="$home_dir/${global_raw#\~/}" ;;
      /*) PLAYBOOKS_GLOBAL_DIR="$global_raw" ;;
      *) PLAYBOOKS_GLOBAL_DIR="$repo_root/$global_raw" ;;
    esac
  fi
}

# Populate ALL_PLAYBOOKS as an array of absolute playbook paths (one per topic,
# local shadowing global). `README.md` is filtered out — `docs/playbooks/README.md`
# is the convention document, not a playbook.
discover_playbooks() {
  ALL_PLAYBOOKS=()
  local repo_root="$1"
  local home_dir="$2"
  _resolve_playbook_dirs "$repo_root" "$home_dir"
  local local_dir="$PLAYBOOKS_LOCAL_DIR"
  local global_dir="$PLAYBOOKS_GLOBAL_DIR"
  local seen_topics="|"

  shopt -s nullglob

  local f base topic
  if [ -d "$local_dir" ]; then
    for f in "$local_dir"/*.md; do
      [ -f "$f" ] || continue
      base="${f##*/}"
      topic="${base%.md}"
      [ "$topic" = "README" ] && continue
      seen_topics="${seen_topics}${topic}|"
      ALL_PLAYBOOKS+=("$f")
    done
  fi

  if [ -d "$global_dir" ]; then
    for f in "$global_dir"/*.md; do
      [ -f "$f" ] || continue
      base="${f##*/}"
      topic="${base%.md}"
      [ "$topic" = "README" ] && continue
      case "$seen_topics" in
        *"|${topic}|"*) continue ;;
      esac
      ALL_PLAYBOOKS+=("$f")
    done
  fi
}

# Emit a TSV stream of `applies_to` and `keywords` list items for EVERY given
# playbook path in a single awk pass: one line per item, `<file>\t<field>\t<value>`,
# with surrounding single or double quotes stripped. This is the batched replacement for
# the old per-file/per-field reader: at K playbooks the hooks went from K (or
# 2K) subprocess forks to exactly one.
#
# awk reads the leading `---` frontmatter block of each file (resetting on
# `FNR==1`, stopping at the second `---`). Supports the documented subset —
# block lists (`field:\n  - item`) and inline lists (`field: [a, b]`) of scalar
# strings. It does NOT process YAML escape sequences inside double-quoted
# strings; keywords are constrained to that subset (no `\b`/`\d`
# word boundaries). A file with no frontmatter contributes nothing.
#
# `FILENAME` is the path exactly as passed (ALL_PLAYBOOKS holds absolute paths),
# so callers can key matches straight back to the playbook file. `nextfile` is
# avoided — it is a GNU awk extension absent from the BSD awk macOS ships.
_scan_frontmatter_tsv() {
  [ "$#" -gt 0 ] || return 0
  # `sq` carries a literal single quote into the awk program without breaking the
  # surrounding bash single-quotes — used by `unquote` to strip either quote style
  # (YAML allows both; the reader honors single AND double).
  awk -v sq="'" '
    function unquote(v,   q) {
      q = substr(v, 1, 1)
      if (length(v) >= 2 && (q == "\"" || q == sq) && substr(v, length(v), 1) == q) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    FNR == 1 { block = 0; done = 0; in_field = "" }
    done { next }
    /^---[[:space:]]*$/ {
      block++
      if (block >= 2) { done = 1 }
      next
    }
    block != 1 { next }
    {
      # Inline list: `applies_to: [a, b]` / `keywords: [a, b]`
      if (match($0, /^(applies_to|keywords)[[:space:]]*:[[:space:]]*\[/)) {
        fname = $0; sub(/[[:space:]]*:.*$/, "", fname)
        s = $0; sub(/^[^[]*\[/, "", s); sub(/\][[:space:]]*$/, "", s)
        n = split(s, arr, ",")
        for (i = 1; i <= n; i++) {
          v = arr[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          v = unquote(v)
          if (v != "") print FILENAME "\t" fname "\t" v
        }
        in_field = ""
        next
      }
      # Block list header: `applies_to:` / `keywords:` (no value on the line)
      if (match($0, /^(applies_to|keywords)[[:space:]]*:[[:space:]]*$/)) {
        in_field = $0; sub(/[[:space:]]*:.*$/, "", in_field)
        next
      }
      # A different top-level key ends the active block field.
      if (match($0, /^[[:alpha:]_][[:alnum:]_-]*[[:space:]]*:/)) { in_field = ""; next }
      # List item under the active field.
      if (in_field != "" && match($0, /^[[:space:]]*-[[:space:]]+/)) {
        v = substr($0, RSTART + RLENGTH)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        v = unquote(v)
        if (v != "") print FILENAME "\t" in_field "\t" v
      }
    }
  ' "$@" 2>/dev/null
}

# Convert a bash glob into an anchored POSIX-ERE regex. Supported subset:
#   `**/`        — zero or more path components (so `**/x` matches `x` at root
#                  too; this is what users intuitively expect even though bash
#                  globstar would require at least one component)
#   `**`         — any sequence including `/`
#   `*`          — any sequence within a single path component (`[^/]*`)
#   `?`          — any single non-separator character
#   `[abc]`      — character class, passthrough
#   `[!abc]`     — negated class, translated to `[^abc]` (bash syntax → ERE)
#   `{a,b,c}`    — alternation, becomes `(a|b|c)`. Empty alternatives
#                  (`{,X}`, `{X,}`, `{,}`) emit a regex BSD ERE rejects, so
#                  the pattern silently never matches — pick a different
#                  glob (e.g. `Dockerfile*` instead of `Dockerfile{,.}*`).
#   `\X`         — literal X (escape)
# Regex metacharacters that aren't glob operators (`.`, `(`, `)`, `|`, `+`,
# `^`, `$`) are escaped so the user's pattern is interpreted as a glob, not a
# regex. Nested or unbalanced braces produce an undefined pattern that
# `[[ =~ ]]` rejects silently (the playbook is treated as non-matching) —
# acceptable per fail-open. For richer matching, extend the translator.
#
# Result is returned in the global `GLOB_RE`, NOT printed: callers run this once
# per applies_to glob (5×K times at K playbooks), and a `regex="$(glob_to_regex)"`
# command substitution would fork a subshell each time — the dominant cost of
# the require hook at scale. Assigning a global keeps it fork-free.
glob_to_regex() {
  local glob="$1"
  local re=""
  local len=${#glob}
  local i=0
  local in_class=0
  local in_brace=0
  local ch next nextnext
  while [ $i -lt $len ]; do
    ch="${glob:$i:1}"
    next="${glob:$((i + 1)):1}"
    nextnext="${glob:$((i + 2)):1}"
    if [ $in_class -eq 1 ]; then
      re+="$ch"
      [ "$ch" = "]" ] && in_class=0
      i=$((i + 1))
      continue
    fi
    case "$ch" in
      '*')
        if [ "$next" = "*" ]; then
          # `**/` should match zero or more leading path components so
          # `**/Dockerfile` matches a top-level `Dockerfile` too. Consuming
          # the trailing slash here emits `(.*/)?`; a bare `**` (no slash)
          # falls back to `.*`.
          if [ "$nextnext" = "/" ]; then
            re+="(.*/)?"
            i=$((i + 3))
          else
            re+=".*"
            i=$((i + 2))
          fi
        else
          re+="[^/]*"
          i=$((i + 1))
        fi
        ;;
      '?')
        re+="[^/]"
        i=$((i + 1))
        ;;
      '.')
        re+="\\."
        i=$((i + 1))
        ;;
      '[')
        in_class=1
        # Bash glob negation `[!…]` → ERE `[^…]`. Consume the `!` as the
        # leading char of the class so the rest passes through verbatim.
        if [ "$next" = "!" ]; then
          re+="[^"
          i=$((i + 2))
        else
          re+="["
          i=$((i + 1))
        fi
        ;;
      '{')
        in_brace=1
        re+="("
        i=$((i + 1))
        ;;
      '}')
        if [ $in_brace -eq 1 ]; then
          re+=")"
          in_brace=0
        else
          re+="\\}"
        fi
        i=$((i + 1))
        ;;
      ',')
        if [ $in_brace -eq 1 ]; then
          re+="|"
        else
          re+=","
        fi
        i=$((i + 1))
        ;;
      '\')
        re+="\\$next"
        i=$((i + 2))
        ;;
      '('|')'|'|'|'+'|'^'|'$')
        re+="\\$ch"
        i=$((i + 1))
        ;;
      *)
        re+="$ch"
        i=$((i + 1))
        ;;
    esac
  done
  GLOB_RE="^${re}$"
}

# Normalize an absolute payload file path to a repo-relative one, assigning the
# result to the global REPO_RELATIVE_PATH. `applies_to` globs are repo-relative
# (what the frontmatter documents and every shipped playbook assumes), but Claude
# Code sends `file_path` ABSOLUTE — so without this every glob that does not start
# with `**/` can never match and the playbook it guards is silently inert: the
# `**/` idiom compiles to a leading `(.*/)?` that happens to swallow the whole
# absolute prefix, hiding the problem behind the one glob shape that appears to work.
#
# Fast path: a fork-free textual prefix strip, correct whenever `pwd` (repo_root)
# and the payload path agree on symlink resolution — the overwhelmingly common
# case (repos live under an unsymlinked $HOME). Fallback (only when the textual
# strip finds no prefix): the two producers may disagree on symlink resolution
# (macOS /tmp → /private/tmp; repo_root is `$(pwd)`, filepath is the tool
# payload), so resolve both sides with `pwd -P` — bash-3.2-safe, no `realpath`
# dependency — and retry. A path genuinely outside the repo keeps its absolute
# form; callers MUST treat a still-absolute result as "outside the repo" and skip
# matching, because an absolute path does not reliably fail to match a
# repo-relative glob: a leading `**/` compiles to an optional `(.*/)?` that
# swallows the whole absolute prefix, so `**/src/**/*.ts` would otherwise match
# `/some/other/repo/src/app.ts` and gate a write in an unrelated repository.
_relativize_to_repo() {
  local repo_root="$1"
  local filepath="$2"

  # Fast path: quoted prefix forces a literal (non-glob) strip.
  REPO_RELATIVE_PATH="${filepath#"$repo_root"/}"
  [ "$REPO_RELATIVE_PATH" != "$filepath" ] && return 0

  # Fallback: resolve symlinks on both sides and retry. `cd` may fail for a
  # not-yet-created parent dir on a new-file Write, or a path outside the repo —
  # in either case fall through to keeping the original absolute path.
  local dir="${filepath%/*}" base="${filepath##*/}" real_root real_dir
  real_root="$(cd "$repo_root" 2>/dev/null && pwd -P)" || real_root=""
  real_dir="$(cd "$dir" 2>/dev/null && pwd -P)" || real_dir=""
  if [ -n "$real_root" ] && [ -n "$real_dir" ]; then
    local real_path="$real_dir/$base"
    REPO_RELATIVE_PATH="${real_path#"$real_root"/}"
    [ "$REPO_RELATIVE_PATH" != "$real_path" ] && return 0
  fi

  # Genuinely outside the repo (or unresolvable): keep the original path.
  REPO_RELATIVE_PATH="$filepath"
}

# Populate MATCHED_PLAYBOOKS with playbooks whose `applies_to` list contains a
# glob that matches the given file path. One awk fork reads every playbook's
# frontmatter; glob→regex translation and matching are in-process (no fork).
playbook_scan_for_path() {
  local repo_root="$1"
  local home_dir="$2"
  local filepath="$3"
  MATCHED_PLAYBOOKS=()

  discover_playbooks "$repo_root" "$home_dir"
  # Guard the iteration: macOS bash 3.2 errors on `"${arr[@]}"` when arr is
  # empty under `set -u`, even though arr was explicitly initialized to `()`.
  [ ${#ALL_PLAYBOOKS[@]} -gt 0 ] || return 0

  # Match repo-relative globs against a repo-relative path, not the absolute
  # payload path. One-time normalization — the fast path is fork-free.
  _relativize_to_repo "$repo_root" "$filepath"
  local match_path="$REPO_RELATIVE_PATH"

  # Still absolute => the target lives outside the repo root, so no
  # repo-relative glob applies to it. Bail BEFORE the match loop rather than
  # relying on the globs not to match: a leading `**/` becomes an optional
  # `(.*/)?` which swallows any absolute prefix, so `**/src/**/*.ts` matches
  # `/elsewhere/src/app.ts` and the hook blocks a write in another repository
  # until this repo's playbooks are read. Enforcement stops at the repo edge.
  case "$match_path" in
    /*) return 0 ;;
  esac

  local file field value seen="|"
  GLOB_RE=""
  while IFS=$'\t' read -r file field value; do
    [ "$field" = "applies_to" ] || continue
    [ -n "$value" ] || continue
    # A playbook with two matching globs must appear once (the old per-file
    # loop `break`ed on first match) — track which files already matched.
    case "$seen" in *"|${file}|"*) continue ;; esac
    glob_to_regex "$value"
    if [[ "$match_path" =~ $GLOB_RE ]]; then
      MATCHED_PLAYBOOKS+=("$file")
      seen="${seen}${file}|"
    fi
  done < <(_scan_frontmatter_tsv "${ALL_PLAYBOOKS[@]}")
}

# Populate MATCHED_KEYWORD_PLAYBOOKS with playbooks whose `keywords` list
# contains a regex matching the prompt. A single jq invocation tests the prompt
# (passed as a JSON-safe --arg, newlines intact) against every keyword regex
# with jq's Oniguruma engine (case-insensitive), avoiding macOS BSD grep regex
# limits and the old one-fork-per-keyword cost. Distinct matching
# files are emitted in first-seen (discovery) order.
playbook_scan_for_prompt() {
  local repo_root="$1"
  local home_dir="$2"
  local prompt="$3"
  MATCHED_KEYWORD_PLAYBOOKS=()

  discover_playbooks "$repo_root" "$home_dir"
  command -v jq >/dev/null 2>&1 || return 0
  [ ${#ALL_PLAYBOOKS[@]} -gt 0 ] || return 0

  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    MATCHED_KEYWORD_PLAYBOOKS+=("$file")
  done < <(
    _scan_frontmatter_tsv "${ALL_PLAYBOOKS[@]}" \
      | jq -Rn --arg prompt "$prompt" -r '
          reduce ( inputs
                   | split("\t")
                   | select(length >= 3 and .[1] == "keywords")
                   | .[2] as $re | .[0] as $file
                   # try/catch keeps a single malformed regex from aborting the
                   # whole batch — it just fails to match, preserving the
                   # per-keyword fail-open the one-fork-per-keyword loop had.
                   | select(try ($prompt | test($re; "i")) catch false)
                   | $file
                 ) as $hit ([]; if any(.[]; . == $hit) then . else . + [$hit] end)
          | .[]
        ' 2>/dev/null
  )
}
