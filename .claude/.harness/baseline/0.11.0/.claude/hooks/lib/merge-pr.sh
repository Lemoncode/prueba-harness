#!/usr/bin/env bash
# Lemony — agent-executed merge with a checks precondition.
#
# The one thing the harness must never do is land a PR nobody decided to land.
# A human's "merge it" silently assumes CI is green, and the closeout record PR
# merges with no human in the loop at all — so this executor makes that
# assumption explicit: it verifies the check status the platform reports for
# the PR and merges ONLY on green. Anything else — red, still pending after a
# bounded wait, or no checks at all — exits with a distinct code so the calling
# contract surfaces the real state to a human instead of merging by omission.
# Branch protection is the user's belt; the harness executes merges and cannot
# assume it is configured, so it carries its own precondition. (`gh` is the
# GitHub rendering of the platform-neutral rule "verify the check status the
# platform reports for the PR".)
#
# Usage:
#   .claude/hooks/lib/merge-pr.sh <pr-number|branch|url> [gh-pr-merge flags…] \
#       [--timeout-secs N] [--grace-secs N] [--poll-secs N] \
#       [--approve-issue N] [--force]
#
# The PR ref MUST be the first argument (enforced) — that way a value-bearing
# pass-through flag can never be misread as the PR. Flags this script consumes
# (anything else is forwarded verbatim to `gh pr merge`, e.g. --squash
# --delete-branch; `-R`/`--repo` is forwarded to the checks query TOO, so the
# PR that is verified is always the PR that is merged):
#   --timeout-secs N  max total wait for pending checks. Default: the
#                     `merge.checks_timeout_secs` key in harness.config.yml,
#                     else 600 (~10 min). Clamped up to --grace-secs.
#   --grace-secs N    window for check state to settle after a push before a
#                     verdict is trusted: zero checks at 2s means nothing, and
#                     an early green with a slow workflow still registering is
#                     just as misleading — so "no checks" (exit 20) and a green
#                     merge both wait out the grace window. Default 30.
#   --poll-secs N     poll interval while waiting (min 1). Default 10.
#   --approve-issue N stale-approve guard: before merging, read the
#                     latest APPROVE record on issue N (the Reviewer writes
#                     `Reviewed-tree:` + `Diff-fingerprint:` lines into its
#                     APPROVE comment) and verify the PR's current content is
#                     what that APPROVE reviewed. Three outcomes: tree equal →
#                     merge; tree differs but diff fingerprint equal → the
#                     base advanced (update-branch) and/or only task state
#                     under .claude/state changed → merge, informing on
#                     stderr; fingerprint differs → exit 40, never merge. The
#                     merge call is then pinned with --match-head-commit to
#                     the exact head the guard verified, so a push racing the
#                     merge is rejected by the platform, not missed by luck
#                     (a caller-supplied --match-head-commit is rejected as
#                     ambiguous). Needs to run inside a clone whose `origin`
#                     serves the PR's repo (`refs/pull/<n>/head`) — for the
#                     same reason it refuses to combine with -R/--repo: the
#                     recompute needs origin to BE the PR's repo. Any read or
#                     recompute failure refuses the merge (exit 1). The
#                     record is read from the platform and the hashes are
#                     recomputed locally — nothing is relayed by the calling
#                     agent (a relayed hash would be one confabulation away
#                     from neutralizing the guard). Trust boundary: the
#                     record is accepted only from a comment whose author
#                     association is OWNER, MEMBER, or COLLABORATOR —
#                     GitHub's own trust rings — so an outside commenter on a
#                     public repo cannot forge a verdict (the hashes are
#                     computable from the public diff). Within that ring the
#                     guard defends against accident and confabulation, not
#                     a malicious insider: every harness agent acts as the
#                     same authenticated user, so authorship cannot
#                     distinguish the Reviewer from another agent. The
#                     posting side closes that gap where Claude Code can:
#                     require-reviewer-record.sh blocks a `gh` call
#                     carrying both markers unless the hook payload names
#                     the Reviewer sub-agent — a body a script
#                     generates inside the same command stays unseen.
#   --force           skip the preconditions (checks AND stale-approve) and
#                     merge now. Reserved for a human's informed decision
#                     ("merge anyway") relayed by the calling contract — never
#                     the agent's own choice.
#
# Exit codes:
#   0    merged — verified against the platform after the merge call, never
#        inferred from gh's exit code (precondition green, or --force)
#   10   checks red — never merge on red by omission; surface the failure
#   20   no checks reported after the grace window — ask the human (a standing
#        "this repo has no CI" answer lives in `merge.allow_no_checks`)
#   30   checks still pending when the timeout elapsed — re-present, don't merge
#   40   stale approve — the PR content no longer matches what the APPROVE on
#        --approve-issue reviewed (diff fingerprint differs): re-present the
#        gate and route to re-review; a fresh APPROVE re-records the hashes
#   1    not merged, no verdict: usage error, the check status could not be
#        read (gh/auth/network failure, or a gh too old for `pr checks
#        --json` — needs gh >= 2.50), `gh pr merge` itself was rejected
#        (branch protection, conflict), or the merge call succeeded but the
#        platform did not confirm MERGED (auto-merge/merge queue pending, or
#        the state could not be read — the PR may in fact be merged) —
#        stderr says which
#   127  gh not installed — fail closed, never merge unverified
#   129/130/143  interrupted (SIGHUP/SIGINT/SIGTERM) while waiting — not
#        merged. During the `gh pr merge` call itself SIGINT/SIGHUP are
#        masked (gh inherits the ignore); SIGTERM can still kill gh (Go
#        re-arms its own handler), so a signal-killed merge re-queries the
#        platform and reports the real state — merged (0) or UNKNOWN (1),
#        never a false "not merged" on a PR that actually landed.
#
# Not a lifecycle hook (no stdin envelope, no exit-2 block) — an executor the
# agent contracts call. It fails CLOSED: on any doubt it does not merge.
set -u

# The verdict blocks print to stdout before `fail`: with a dead reader
# (`merge-pr.sh 123 | head -1`), the default SIGPIPE would kill the shell with
# 141, replacing the typed verdict (10/20/30) the calling contracts are built
# on and losing the (Hook:) self-identification. Ignoring PIPE turns those
# writes into plain EPIPE failures — the script runs `set -u` without `-e`,
# so execution still reaches `fail` and the distinct exit code survives.
trap '' PIPE

# Bash seeds SECONDS from an exported ancestor value (3.2 and 5.x alike); an
# inherited clock would void the grace window and merge an unsettled green.
SECONDS=0

warn() {
  printf '[merge-pr] %s\n' "$*" >&2
}

# Every no-merge exit self-identifies, like every hook: the transcript
# will show "refusing to merge" — the reader must see which script decided.
fail() {
  printf '(Hook: %s)\n' "${BASH_SOURCE[0]}" >&2
  exit "$1"
}

# Baked default for the pending-checks wait; `merge.checks_timeout_secs` in
# harness.config.yml overrides it. A guard test asserts this literal equals the
# canonical TS constant, so the duplication can never silently drift.
DEFAULT_TIMEOUT_SECS=600

# Repo root from the script's own location (.claude/hooks/lib/ → up three), so
# resolution is independent of the caller's cwd — same recipe as lemony.sh.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

USAGE='usage: merge-pr.sh <pr-number|branch|url> [gh-pr-merge flags…] [--timeout-secs N] [--grace-secs N] [--poll-secs N] [--force]'

require_value() {
  if [ "$2" -lt 2 ]; then
    warn "$1 requires a value — $USAGE"
    fail 1
  fi
}

require_number() {
  local value="$2"
  case "$value" in
    '' | *[!0-9]*)
      warn "$1 must be a non-negative integer (got '$value')"
      fail 1
      ;;
  esac
  # Beyond int range, `[ -lt ]` errors out and every clock comparison goes
  # false forever — the poll loop would hang instead of reaching a verdict.
  if [ "${#value}" -gt 9 ]; then
    warn "$1 is out of range (got '$value', max 9 digits)"
    fail 1
  fi
}

# The PR ref is positionally enforced as $1 so a pass-through flag's value
# (--subject "…", --body "…") can never be swallowed as the PR. An empty ref
# is rejected too: gh resolves an empty selector to the CURRENT BRANCH's PR —
# an unset caller variable would verify and merge a PR nobody named.
if [ $# -eq 0 ] || [ "${1#-}" != "$1" ]; then
  warn "the PR ref must be the first argument — $USAGE"
  fail 1
fi
case "$1" in
  '' | *[[:space:]]*)
    warn "the PR ref must be a non-empty, whitespace-free token — $USAGE"
    fail 1
    ;;
esac
PR="$1"
shift

FORCE=0
TIMEOUT_SECS=""
GRACE_SECS=30
POLL_SECS=10
APPROVE_ISSUE=""
CALLER_MATCH_HEAD=0
MERGE_ARGS=()
REPO_ARGS=()
GUARD_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-secs)
      require_value "$1" $#
      require_number "$1" "$2"
      TIMEOUT_SECS="$2"
      shift 2
      ;;
    --grace-secs)
      require_value "$1" $#
      require_number "$1" "$2"
      GRACE_SECS="$2"
      shift 2
      ;;
    --poll-secs)
      require_value "$1" $#
      require_number "$1" "$2"
      if [ "$2" -lt 1 ]; then
        warn '--poll-secs must be >= 1 (a zero interval would hammer the API)'
        fail 1
      fi
      POLL_SECS="$2"
      shift 2
      ;;
    --approve-issue)
      require_value "$1" $#
      require_number "$1" "$2"
      APPROVE_ISSUE="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    # Repo selection must reach BOTH gh invocations — checks verified on one
    # repo while merging another would defeat the whole precondition.
    -R | --repo)
      require_value "$1" $#
      REPO_ARGS=(--repo "$2")
      shift 2
      ;;
    --repo=*)
      REPO_ARGS=(--repo "${1#--repo=}")
      shift
      ;;
    # gh is pflag-based, so the attached shorthand forms are just as valid —
    # falling through to MERGE_ARGS would merge one repo's PR on another
    # repo's checks. `-R=*` must precede `-R?*` (it matches it too).
    -R=*)
      REPO_ARGS=(--repo "${1#-R=}")
      shift
      ;;
    -R?*)
      REPO_ARGS=(--repo "${1#-R}")
      shift
      ;;
    # Value-bearing gh-pr-merge flags: consume flag AND value together so a
    # value that happens to spell a script keyword is never parsed as one — a
    # PR subject of "--force" must not disarm the precondition.
    -t | --subject | -b | --body | -F | --body-file | -A | --author-email)
      require_value "$1" $#
      MERGE_ARGS+=("$1" "$2")
      shift 2
      ;;
    # Same pass-through, but tracked: the stale-approve guard pins the merge
    # to the head IT verified — two pins with different owners is ambiguous.
    --match-head-commit)
      require_value "$1" $#
      CALLER_MATCH_HEAD=1
      MERGE_ARGS+=("$1" "$2")
      shift 2
      ;;
    # gh's pflag grammar also accepts grouped/attached single-dash forms
    # (-dR owner/repo, -st "subject", -tSubject) where IT decides which argv
    # is a flag, a value, or a repo switch — re-parsing that grammar here is
    # how a keyword or a repo override could still slip through. Refuse the
    # whole class, fail closed. (Attached -R…, handled above, is the one
    # exception — it feeds BOTH gh invocations.)
    -[!-]?*)
      warn "grouped/attached single-dash flags are not supported (got '$1') — pass flags separately; repo selection as -R/--repo"
      fail 1
      ;;
    # Flags under which `gh pr merge` exits 0 WITHOUT merging (usage text,
    # auto-merge toggles): forwarding them would fabricate a "merged" verdict.
    # --auto in particular is the exact bypass this executor replaces.
    -h | --help | --help=* | --auto | --auto=* | --disable-auto | --disable-auto=*)
      warn "$1 is not supported through the executor — gh reports success without merging. $USAGE"
      fail 1
      ;;
    # pflag stops flag parsing at `--`; mirror that, or "-- --force" (the
    # defensive make-it-inert idiom) would be re-scanned as a script keyword.
    --)
      MERGE_ARGS+=("$1")
      shift
      while [ $# -gt 0 ]; do
        MERGE_ARGS+=("$1")
        shift
      done
      ;;
    *)
      MERGE_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ -n "$APPROVE_ISSUE" ] && [ "$CALLER_MATCH_HEAD" = "1" ]; then
  warn '--approve-issue pins the merge to the head the guard verified — a caller-supplied --match-head-commit is ambiguous; drop one of the two.'
  fail 1
fi

# The guard recomputes hashes from a local clone of `origin`; a -R/--repo
# target lives elsewhere, so the combination can never verify (the head
# cross-check would fail with a misleading "racing push" message). Refuse it
# honestly up front instead.
if [ -n "$APPROVE_ISSUE" ] && [ ${#REPO_ARGS[@]} -gt 0 ]; then
  warn "the stale-approve guard recomputes hashes from a local clone of origin and cannot verify a -R/--repo target — run it from a clone of the PR's repo."
  fail 1
fi

if ! command -v gh >/dev/null 2>&1; then
  warn 'gh not found — cannot verify the check status, refusing to merge.'
  fail 127
fi

# Read the `merge:` block of harness.config.yml with one awk pass (node-free,
# same recipe as playbook-scan.sh): emit `<key>\t<value>` for the uncommented
# `checks_timeout_secs` / `allow_no_checks` entries — inline comments stripped
# (on the block header too) and surrounding quotes removed. Any column-0 line
# ends the block. Absent/unreadable/non-regular config → baked defaults.
CONFIG_TIMEOUT=""
CONFIG_ALLOW_NO_CHECKS=""
read_merge_config() {
  local config="$ROOT/harness.config.yml"
  # `-f` as well as `-r`: a FIFO is readable, and awk on it would hang the merge.
  { [ -f "$config" ] && [ -r "$config" ]; } || return 0

  local key value
  while IFS=$'\t' read -r key value; do
    case "$key" in
      checks_timeout_secs) CONFIG_TIMEOUT="$value" ;;
      allow_no_checks) CONFIG_ALLOW_NO_CHECKS="$value" ;;
    esac
  done < <(awk -v sq="'" '
    function unquote(v,   q) {
      q = substr(v, 1, 1)
      if (length(v) >= 2 && (q == "\"" || q == sq) && substr(v, length(v), 1) == q) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    /^[^[:space:]]/ {
      line = $0
      sub(/#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      in_merge = (line == "merge:") ? 1 : 0
      child_indent = ""
      next
    }
    in_merge != 1 { next }
    {
      line = $0
      sub(/#.*$/, "", line)
      # Only the block DIRECT children carry policy: anchor to the indent of
      # the first child, so a key nested deeper (a sub-map, a block-scalar
      # line of prose) can never read as allow_no_checks and merge unchecked.
      if (child_indent == "" && match(line, /^[[:space:]]+[^[:space:]]/)) {
        child_indent = substr(line, 1, RLENGTH - 1)
      }
      indent = line
      sub(/[^[:space:]].*$/, "", indent)
      if (indent != child_indent) { next }
      if (match(line, /^[[:space:]]+(checks_timeout_secs|allow_no_checks)[[:space:]]*:/)) {
        key = line; sub(/^[[:space:]]+/, "", key); sub(/[[:space:]]*:.*$/, "", key)
        value = line; sub(/^[^:]*:[[:space:]]*/, "", value); sub(/[[:space:]]+$/, "", value)
        value = unquote(value)
        if (value != "") printf "%s\t%s\n", key, value
      }
    }
  ' "$config")
}
read_merge_config

if [ -z "$TIMEOUT_SECS" ]; then
  # Same >9-digit bound as require_number: an int-overflowing config value
  # would break every clock comparison and hang the loop — default instead.
  case "$CONFIG_TIMEOUT" in
    '' | *[!0-9]*) TIMEOUT_SECS="$DEFAULT_TIMEOUT_SECS" ;;
    *)
      if [ "${#CONFIG_TIMEOUT}" -le 9 ]; then
        TIMEOUT_SECS="$CONFIG_TIMEOUT"
      else
        TIMEOUT_SECS="$DEFAULT_TIMEOUT_SECS"
      fi
      ;;
  esac
fi

# The grace window is part of the total wait, never in excess of it.
if [ "$TIMEOUT_SECS" -lt "$GRACE_SECS" ]; then
  TIMEOUT_SECS="$GRACE_SECS"
fi

# Case-normalized: YAML accepts `True`/`TRUE` as the boolean, and a silently
# ignored recorded answer would re-ask the human forever.
ALLOW_NO_CHECKS=0
if [ "$(printf '%s' "$CONFIG_ALLOW_NO_CHECKS" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  ALLOW_NO_CHECKS=1
fi

# Stale-approve guard: "nothing reaches the human unreviewed" is only
# real if the content that merges is the content the APPROVE reviewed — the
# merge-gate wait is deliberately long, and any push in that window would
# otherwise merge on green without a fresh verdict. The Reviewer records the
# reviewed tree hash and a diff fingerprint in its APPROVE comment on the
# task issue; this precondition recomputes both for the PR's current head and
# applies the three-state algebra (current / base-advanced / changed). The
# fingerprint — the canonical command below, digesting changed paths + modes
# + full blob OIDs against the merge-base — exists because update-branch
# before merge is standing practice and must not invalidate verdicts: a clean
# base advance changes the tree but not the PR's own diff (verified
# empirically, including that a base edit to a file the PR also touched DOES
# change it — exactly the case that needs fresh eyes). The digest excludes
# `.claude/state`: the Reviewer writes its evidence ledger and
# `progress.md` section after posting the APPROVE, by contract, and the
# Orchestrator keeps writing task state until the merge — none of it is
# reviewed content, so a commit of it must not read as a stale approve.
# `:(top,…)` anchors the exclude at the repo root: a bare `:(exclude)` is
# cwd-relative and silently excludes nothing when the recipe runs from a
# subdirectory. `--no-abbrev` is
# load-bearing: --raw abbreviates blob OIDs to a repo-size-dependent width by
# default, so two machines could digest different bytes for the same diff.
# The parity of this command with the Reviewer's recipe (reviewer.md) is
# pinned by a guard spec — drift here silently flips every verdict to 40.
verify_approved_content() {
  local record approved_tree approved_fp value pr_meta pr_num head_oid
  local base_ref fetch_err fetched cur_tree base_oid merge_root cur_fp

  # The latest comment carrying both markers wins: a re-review posts a fresh
  # APPROVE with fresh hashes, and older records must not resurrect. Only
  # comments from GitHub's write-ish trust rings (OWNER/MEMBER/COLLABORATOR
  # author association) are considered — the hashes are computable from the
  # public diff, so on a public repo an outside commenter could otherwise
  # forge a record matching an unreviewed head. The export walks every page
  # of the thread (under --json comments gh fetches the whole comment list,
  # page after page, before it prints), so `last` is the newest qualifying
  # record however long the thread grows. stderr is captured apart so gh
  # chatter (update notices) can never pollute the record on a successful
  # read.
  record="$(gh issue view "$APPROVE_ISSUE" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json comments --jq '[.comments[] | select((.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR") and (.body | contains("Reviewed-tree:")) and (.body | contains("Diff-fingerprint:")))] | last | .body' 2>"$CHECKS_ERR")"
  if [ $? -ne 0 ]; then
    cat "$CHECKS_ERR" >&2
    warn "could not read the APPROVE record from issue #$APPROVE_ISSUE — refusing to merge."
    fail 1
  fi
  if [ -z "$record" ] || [ "$record" = "null" ]; then
    warn "no APPROVE record (Reviewed-tree/Diff-fingerprint) found on issue #$APPROVE_ISSUE — cannot verify what was reviewed; refusing to merge."
    fail 1
  fi

  # The value is the field RIGHT AFTER the marker token (never $NF: a line
  # mentioning a marker in prose, or both markers on one line, would shift a
  # last-field read), the last occurrence wins, and a CR from a web-edited
  # comment is stripped before validation. Values must be full hex object
  # names (40 hex today, 64 on a sha256 repo) — anything else is a malformed
  # record, not a verdict.
  approved_tree="$(printf '%s\n' "$record" | awk '{ sub(/\r$/, ""); for (i = 1; i < NF; i++) if ($i == "Reviewed-tree:") v = $(i + 1) } END { if (v != "") print v }')"
  approved_fp="$(printf '%s\n' "$record" | awk '{ sub(/\r$/, ""); for (i = 1; i < NF; i++) if ($i == "Diff-fingerprint:") v = $(i + 1) } END { if (v != "") print v }')"
  for value in "$approved_tree" "$approved_fp"; do
    case "$value" in
      '' | *[!0-9a-f]*)
        warn "malformed APPROVE record on issue #$APPROVE_ISSUE (Reviewed-tree/Diff-fingerprint are not hex object names) — refusing to merge."
        fail 1
        ;;
    esac
    if [ "${#value}" -ne 40 ] && [ "${#value}" -ne 64 ]; then
      warn "malformed APPROVE record on issue #$APPROVE_ISSUE (hash length ${#value}) — refusing to merge."
      fail 1
    fi
  done

  pr_meta="$(gh pr view "$PR" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json number,headRefOid,baseRefName --jq '[.number, .headRefOid, .baseRefName] | @tsv' 2>"$CHECKS_ERR")"
  if [ $? -ne 0 ]; then
    cat "$CHECKS_ERR" >&2
    warn "could not read the PR head/base from the platform — refusing to merge."
    fail 1
  fi
  IFS=$'\t' read -r pr_num head_oid base_ref <<EOF
$pr_meta
EOF
  case "$pr_num" in
    '' | *[!0-9]*)
      warn "unexpected PR metadata from gh ('$pr_meta') — refusing to merge."
      fail 1
      ;;
  esac
  case "$head_oid" in
    '' | *[!0-9a-f]*)
      warn "unexpected PR head OID from gh ('$head_oid') — refusing to merge."
      fail 1
      ;;
  esac
  if [ -z "$base_ref" ]; then
    warn 'the platform reported no base ref for the PR — refusing to merge.'
    fail 1
  fi

  # Two independent reads must agree: the platform names the head OID, and
  # origin must serve that exact commit at refs/pull/<n>/head. A mismatch is
  # a push racing this merge or an origin that is not the PR's repo — both
  # are "stop", not "pick one".
  if ! fetch_err="$(git -C "$ROOT" fetch -q origin "refs/pull/$pr_num/head" 2>&1)"; then
    printf '%s\n' "$fetch_err" >&2
    warn "could not fetch refs/pull/$pr_num/head from origin — the stale-approve guard needs a clone of the PR's repo; refusing to merge."
    fail 1
  fi
  fetched="$(git -C "$ROOT" rev-parse -q --verify FETCH_HEAD 2>/dev/null)"
  if [ -z "$fetched" ]; then
    warn 'could not resolve FETCH_HEAD after fetching the PR head — refusing to merge.'
    fail 1
  fi
  if [ "$fetched" != "$head_oid" ]; then
    warn "the platform reports PR head $head_oid but origin serves $fetched — a push may be racing this merge, or origin is not the PR's repo; refusing to merge."
    fail 1
  fi

  cur_tree="$(git -C "$ROOT" rev-parse -q --verify "$head_oid^{tree}" 2>/dev/null)"
  if [ -z "$cur_tree" ]; then
    warn "could not resolve the tree of $head_oid — refusing to merge."
    fail 1
  fi

  if [ "$cur_tree" != "$approved_tree" ]; then
    if ! fetch_err="$(git -C "$ROOT" fetch -q origin "$base_ref" 2>&1)"; then
      printf '%s\n' "$fetch_err" >&2
      warn "could not fetch the base ref '$base_ref' from origin — refusing to merge."
      fail 1
    fi
    base_oid="$(git -C "$ROOT" rev-parse -q --verify FETCH_HEAD 2>/dev/null)"
    merge_root="$(git -C "$ROOT" merge-base "$base_oid" "$head_oid" 2>/dev/null)"
    if [ -z "$base_oid" ] || [ -z "$merge_root" ]; then
      warn "could not compute the merge-base of '$base_ref' and the PR head — refusing to merge."
      fail 1
    fi
    # Canonical fingerprint command — byte-for-byte the Reviewer's recipe
    # (reviewer.md records the APPROVE side with the same pinned flags).
    # --no-literal-pathspecs: under GIT_LITERAL_PATHSPECS=1 the exclude is read
    # as a literal path, the diff comes out empty and every head digests alike.
    cur_fp="$(
      set -o pipefail
      git -C "$ROOT" --no-literal-pathspecs -c core.quotePath=true diff --raw --no-abbrev --no-renames --no-color "$merge_root" "$head_oid" -- ':(top,exclude).claude/state' \
        | git -C "$ROOT" hash-object --stdin
    )"
    if [ $? -ne 0 ] || [ -z "$cur_fp" ]; then
      warn 'could not compute the diff fingerprint of the PR head — refusing to merge.'
      fail 1
    fi

    if [ "$cur_fp" != "$approved_fp" ]; then
      echo "stale-approve: PR $PR no longer matches what the APPROVE on issue #$APPROVE_ISSUE reviewed"
      echo "(reviewed tree $approved_tree, fingerprint $approved_fp; current tree $cur_tree, fingerprint $cur_fp)."
      echo 'Content changed after the review — never merge unreviewed content: re-present the'
      echo 'merge gate and route the PR to re-review; a fresh APPROVE re-records the hashes.'
      echo "A human's informed \"merge anyway\" re-runs with --force."
      fail 40
    fi
    warn "stale-approve guard: the tree differs from the APPROVE on issue #$APPROVE_ISSUE but the diff fingerprint matches — the base advanced (e.g. update-branch) and/or only task state under .claude/state changed; merging the approved content."
  fi

  # Pin the merge to the exact head this guard verified: a push landing
  # between this read and the merge call is rejected by the platform itself.
  GUARD_ARGS=(--match-head-commit "$head_oid")
}

# The merge itself, with the caller's pass-through flags. A gh rejection
# (branch protection wants approval, a conflict) keeps its stderr but is
# normalized to exit 1, so the 10/20/30 verdict codes stay unambiguous.
do_merge() {
  # The stale-approve precondition runs before the signal mask (an operator
  # can still abort it) and is skipped by --force alone — same doctrine as
  # the checks precondition: only a human's informed decision bypasses.
  if [ "$FORCE" != "1" ] && [ -n "$APPROVE_ISSUE" ]; then
    verify_approved_content
  fi
  # A signal here must never turn into a false "not merged" on a PR that DID
  # land. Masking keeps the script alive (and covers gh for INT/HUP, which
  # inherit the ignore); Go re-arms SIGTERM, so a TERM-killed gh is resolved
  # by asking the platform below rather than by assertion.
  trap '' INT TERM HUP
  # GUARD_ARGS rides between the repo selector and the pass-through flags so
  # a caller's `--` sentinel can never demote the pin to a positional.
  if [ ${#MERGE_ARGS[@]} -gt 0 ]; then
    gh pr merge "$PR" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} ${GUARD_ARGS[@]+"${GUARD_ARGS[@]}"} "${MERGE_ARGS[@]}"
  else
    gh pr merge "$PR" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} ${GUARD_ARGS[@]+"${GUARD_ARGS[@]}"}
  fi
  local rc=$?
  # Only 128+n (n in 1..64) encodes a signal-killed child; 255 etc. from a
  # gh wrapper/shim falls through to the plain failure message below.
  if [ "$rc" -gt 128 ] && [ "$rc" -le 192 ]; then
    if gh pr view "$PR" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json state 2>/dev/null \
      | grep -q '"MERGED"'; then
      warn "gh pr merge was killed by signal $((rc - 128)), but the platform reports the PR as merged."
      exit 0
    fi
    warn "gh pr merge was killed by signal $((rc - 128)) — merge state UNKNOWN; verify the PR before retrying."
    fail 1
  fi
  if [ "$rc" -ne 0 ]; then
    warn "gh pr merge failed (exit $rc) — not merged."
    fail 1
  fi
  # gh exits 0 for outcomes that are NOT a merge (auto-merge armed, merge
  # queue enqueue on a queue-protected base). The 0 verdict is a promise the
  # calling contract acts on — so it comes from the platform, never from
  # gh's exit code alone. A definitive non-MERGED read and an unreadable
  # platform are different verdicts: only the first asserts a cause.
  local state_out view_rc
  state_out="$(gh pr view "$PR" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json state 2>&1)"
  view_rc=$?
  if [ "$view_rc" -eq 0 ]; then
    case "$state_out" in
      *'"MERGED"'*) exit 0 ;;
    esac
    warn 'gh pr merge exited 0 but the platform reports the PR as not merged (auto-merge or a merge queue may be pending) — not reporting merged.'
    fail 1
  fi
  printf '%s\n' "$state_out" >&2
  warn 'gh pr merge exited 0 but the platform state could not be read — merge state UNKNOWN; verify the PR before retrying.'
  fail 1
}

if [ "$FORCE" = "1" ]; then
  do_merge
fi

CHECKS_ERR="$(mktemp "${TMPDIR:-/tmp}/merge-pr-err.XXXXXX")"
trap 'rm -f "$CHECKS_ERR"' EXIT
# A trapped signal whose handler does not `exit` RESUMES the script after the
# handler — a cleanup-only INT/TERM trap would swallow Ctrl-C / a supervisor's
# SIGTERM and keep polling toward a merge the operator tried to cancel. The
# `exit` here fires the EXIT trap, so cleanup still happens exactly once.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Poll until green (merge), red (10), absent (20), or timeout (30). `SECONDS`
# counts from script start, so grace and timeout share one clock.
while :; do
  # Structured read: `--json bucket,name` + gh's embedded `--jq` emit
  # `bucket<TAB>name` lines, with jq's @tsv escaping tabs/newlines inside
  # values — so a check name containing a literal tab (gh's raw table printer
  # writes fields unescaped) can never shift the bucket out of OUR column 1.
  # Under --json gh exits 0 whatever the buckets say (its exporter returns
  # before the table-mode 1/8 exit logic), so the verdict rests entirely on
  # the bucket classification below; the exit-status cross-checks remain as
  # belts for the states that still produce them (no-checks/transport errors
  # return BEFORE the exporter and keep their stderr + nonzero exit; an
  # output-plus-nonzero partial read is barely reachable but stays guarded).
  # gh too old for `pr checks --json` (< 2.50) fails the invocation and lands
  # in the could-not-read branch: fail closed, with gh's own message.
  # GH_FORCE_TTY / NO_COLOR stay neutralized as a belt — --json output is
  # TTY-independent on current gh, but the guarantee costs nothing.
  CHECKS_OUT="$(GH_FORCE_TTY='' NO_COLOR=1 gh pr checks "$PR" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json bucket,name --jq '.[] | [.bucket, .name] | @tsv' 2>"$CHECKS_ERR")"
  CHECKS_STATUS=$?

  if [ -z "$CHECKS_OUT" ]; then
    # Absent checks — gh reports "no checks reported …" on stderr (or, on a
    # quiet success, nothing at all). Anything else is a real gh failure.
    if ! grep -q 'no checks reported' "$CHECKS_ERR" 2>/dev/null \
      && { [ "$CHECKS_STATUS" -ne 0 ] || [ -s "$CHECKS_ERR" ]; }; then
      cat "$CHECKS_ERR" >&2
      warn 'could not read the check status — refusing to merge.'
      fail 1
    fi
    if [ "$SECONDS" -lt "$GRACE_SECS" ]; then
      sleep "$POLL_SECS"
      continue
    fi
    if [ "$ALLOW_NO_CHECKS" = "1" ]; then
      warn 'no checks reported — merging per merge.allow_no_checks: true in harness.config.yml.'
      do_merge
    fi
    echo "no-checks: the platform reports no checks for $PR (waited ${GRACE_SECS}s). Never"
    echo 'merge alone on absent checks, whatever the cause — ask the human. A standing'
    echo 'answer ("this repo has no CI — merge without checks") is recorded once as'
    echo 'merge.allow_no_checks: true in harness.config.yml; a one-shot yes re-runs with --force.'
    fail 20
  fi

  # Classify the bucket (column 1 — ours by construction, see the read
  # above): fail/cancel → red, pass/skipping → ok, anything else (pending, …)
  # → still running. An all-skipping set is deliberately green: gh reports
  # the checks and none failed — path-filtered CI on a docs-only PR is the
  # everyday case.
  RED_LINES="$(printf '%s\n' "$CHECKS_OUT" | awk -F'\t' '$1 == "fail" || $1 == "cancel"')"
  PENDING_COUNT="$(printf '%s\n' "$CHECKS_OUT" | awk -F'\t' '$1 != "pass" && $1 != "skipping" && $1 != "fail" && $1 != "cancel" { n++ } END { print n + 0 }')"

  if [ -n "$RED_LINES" ]; then
    echo "red: failing check(s) on $PR — not merging. Surface this to the human:"
    printf '%s\n' "$RED_LINES"
    fail 10
  fi

  if [ "$PENDING_COUNT" -eq 0 ]; then
    # A green verdict is trusted only when gh agrees (exit 0 — a non-zero exit
    # alongside a clean-looking table means a truncated/partial read: doubt,
    # so no merge) and only once the grace window has elapsed (a fast check
    # can report pass while a slow workflow is still registering).
    if [ "$CHECKS_STATUS" -ne 0 ]; then
      cat "$CHECKS_ERR" >&2
      warn "gh pr checks exited $CHECKS_STATUS behind a green-looking read — refusing to merge on a partial read."
      fail 1
    fi
    if [ "$SECONDS" -ge "$GRACE_SECS" ]; then
      do_merge
    fi
  fi

  if [ "$SECONDS" -ge "$TIMEOUT_SECS" ]; then
    echo "timeout: checks still pending on $PR after ${TIMEOUT_SECS}s — not merging. Current state:"
    printf '%s\n' "$CHECKS_OUT"
    fail 30
  fi

  sleep "$POLL_SECS"
done
