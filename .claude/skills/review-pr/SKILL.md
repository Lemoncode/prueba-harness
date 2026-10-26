---
name: review-pr
description: 🍋 Interactive PR review with a dry-run approval flow — fetch the diff, analyze it through the review lenses, present a numbered findings table, and post only the human-selected ones as GitHub inline review comments (or as replies in the threads already on the PR). Use at the merge gate, or to review anyone's PR — up to three analysis passes, each looking for what the earlier ones missed, so one run tells you everything at once.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [orchestrator]
---

# Review PR

## Core principle

**Show before you post.** Analyze → dry-run → human picks → post. Never submit GitHub
review comments without explicit human approval.

**Say it all in one run.** A single pass over a diff sees part of what is there — a
second run would find more, and the human would learn about the PR in instalments.
So the analysis runs in passes: each later pass is told what the earlier ones found
and looks only for what they missed, until one finds nothing or the pass limit is
reached (step 2).

**Never repeat what is already on the PR.** Each run reads the review threads already
there — whoever started them, with their replies — and the analysis knows them: a
point the PR already holds is not proposed again. A re-run on an unchanged PR
proposes nothing it can match to a thread already there, and what it holds back is
shown, not hidden.

## Workflow

### 0. Resolve the PR

- **URL** (`https://github.com/<org>/<repo>/pull/<n>`): extract `<org>/<repo>` + number.
- **Number** (`#<n>`, `<n>`): resolve the repo with `gh repo view --json nameWithOwner`.
- **No argument**: detect the open PR on the current branch with `gh pr view`.

Run in parallel:

- `gh pr diff <number> --repo <org>/<repo>`
- `gh pr view <number> --repo <org>/<repo> --json title,headRefName,baseRefName,files,changedFiles,headRefOid`
- the PR's **review threads**, every page — the GraphQL query in
  [reference.md](reference.md) (the REST comment list does not say whether a thread is
  resolved).

If the diff is empty, stop and tell the human.

A large PR can defeat the first two: `gh pr diff` refuses a diff over GitHub's size
limit (HTTP 406), and `gh pr view --json files` stops at 100 files (`changedFiles`
above 100 says it did). Then read the changed files, with a patch each, from the
paginated REST list in [reference.md](reference.md); a file listed with no patch
(binary, empty, or too large) is not reviewed — name the non-empty ones in the
dry-run.

Reduce each thread to a short block for the analysis (format in
[reference.md](reference.md)): its state (`unresolved` / `resolved`, plus `outdated`
when the code under it has changed since), where it sits, the code it was written on,
its opening comment (author and body) and its latest replies. A PR with no threads
gives an empty list.

### 1. Read project context

Read the repo's `CLAUDE.md` (and `CONTEXT.md` if present), as of the PR's head
(`headRefOid`) when the PR changes them. Summarize in ≤ 50 lines:
code-style rules, comment conventions, naming, architecture constraints. This is what
the analysis judges "against project convention" by.

Then list the project's rules for the passes. They are `Explore` sub-agents, which
Claude Code gives no rules, so they `Read` each listed file themselves. The list has
two parts:

- **The rules with no `paths:`** under `.claude/rules/`. You received them at session
  start, and the command below never prints them: add their paths yourself.
- **The rules whose `paths:` cover a changed file**, a deleted one included, and a
  renamed one under its old path too. From the repo root (past 100 files, or to get
  renames' old paths, feed it step 0's REST listing with
  `--jq '.[] | .filename, (.previous_filename // empty)'`):

  ```bash
  gh pr view <number> --repo <org>/<repo> --json files --jq '.files[].path' |
    while IFS= read -r f; do .claude/hooks/lib/lemony.sh rules match --path="$f"; done |
    sort -u
  ```

A rule the PR adds, changes or deletes: leave this checkout's copy off the list, and
when the PR keeps the rule, append its text as the PR has it after the summary,
outside its 50 lines —
`gh api -H 'Accept: application/vnd.github.raw' 'repos/<org>/<repo>/contents/<path>?ref=<headRefOid>'`
reads it without fetching the head. When the PR belongs to another repository, or the
command prints an error instead of rule paths (`lemony: CLI not found`, a missing
launcher, an older CLI without `rules`), this checkout's rules are not the PR's: send
the passes none and say so in the dry-run.

### 2. Analyze (in passes — the review lenses as a checklist)

Each pass is **one** `Explore` sub-agent given the full diff, the changed-files list,
the project context and its rule list, and the threads from step 0. Its prompt walks
the five review lenses as a checklist — **not** five separate agents:

1. **Security** — injection, auth/authz gaps, secret exposure, unsafe input reaching a
   sink, OWASP-class issues.
2. **Silent failures** — swallowed errors, empty `catch`, a fallback that hides a bug,
   a `return` where it should `throw`.
3. **Spec compliance** — does the diff do what the issue/spec/PR says, no more and no
   less? Scope drift, missing acceptance criteria.
4. **Test gaps** — logic-bearing code with no test; a bug fix with no regression test;
   assertions that don't actually pin the behavior.
5. **Senior quality** — correctness, edge cases, naming that encodes intent, N+1s,
   convention violations against step 1's summary and rule list.

The agent returns a strict JSON array of findings (see [reference.md](reference.md) for
the exact prompt and schema). It returns `[]` when the diff is clean — it must **not**
manufacture findings to seem thorough.

**Passes.** Run up to **three**, one after the other, each a fresh sub-agent:

1. The first pass: the prompt as it stands.
2. Each later pass: the same prompt plus the follow-on addendum in
   [reference.md](reference.md), with every finding the earlier passes returned (all
   statuses) as "already found in this run". It returns only what they missed.
3. Stop as soon as a pass returns no `new` or `follow-up` finding: the review is
   complete. (A pass that only matches threads already on the PR found nothing new.)

A pass that finds something is worth another look; past the third, measured on real
PRs, the passes find little that is real and start to misread intended code. So after
the third, stop — and when the third still returned findings to post, say so in the dry-run
and **offer one more pass** (step 3). Every pass after that is offered the same way,
one at a time, never run unasked.

Merge the passes' findings into one list before the dry-run, dropping a later pass's
finding that makes the same point (same problem, same code) as an earlier one — keep
the earlier one.

Each finding carries a **status** against the threads already on the PR. The same
point is the same problem at the same code — the thread's lines, or the code they
became; the same _kind_ of problem in another function is a different point. The full
rules are in the prompt ([reference.md](reference.md)); in short:

- `new` — no thread makes this point. When a resolved thread's code was rewritten and
  the new code brings its problem back, it still is `new` (a reply would stay hidden
  in the collapsed thread) and it names that thread.
- `follow-up` — an **unresolved** thread makes this point, and there is something to
  add that neither the thread nor its replies say: part of it remains after a partial
  fix, or a consequence it did not state. It names the thread.
- `already-posted` — the PR already holds this point: an unresolved thread with
  nothing to add, or a resolved thread whose problem is still there as it was written
  on (the human closed it, fixed or not — that decision stands). It names the
  thread.

**A Reviewer, or no `Agent` tool?** A Reviewer never spawns, whatever its tools (the
opening rule of the Reviewer contract, `.claude/agents/reviewer.md`), and an agent at
Claude Code's nesting depth limit has no `Agent` tool unless it is a fork. Then walk
the five lenses yourself, in this context, with the same prompt as your checklist, and
produce the same JSON array — and run the later passes yourself too, one after the
other, each with the follow-on addendum; the rest of the flow is unchanged.

### 3. Dry-run

Print the findings as a numbered table (don't post anything yet):

```
## Dry-run — <PR_TITLE> (#<NUMBER>)

| # | Status | Sev | File | Line | Problem | Suggestion |
|---|--------|-----|------|------|---------|------------|
| 1 | new | 🟠  | src/foo.ts | 42 | Swallowed error in the catch | Re-throw or log + surface |
| 2 | follow-up of <thread URL> | 🟡 | src/bar.ts | 23 | The null check moved, but `update` still skips it | Same guard in `update` |
| 3 | new — back after <thread URL> | 🟠 | src/baz.ts | 61 | The retry swallows the error again | Re-throw after the last attempt |
...

Already on the PR — not proposed again:
- src/qux.ts:88 — Unbounded query in `list` → "<thread's first line>" <thread URL> (unresolved)

Total: N findings to post (M new, K follow-ups) · A already on the PR · P passes.
Which do I post? ("all", "1,3,5", or "none")
```

When the last pass allowed still found something, add one line above the question —
"Pass <N> still found J findings to post (rows …). Run one more pass before
choosing?" —
and on a yes, run it, merge its findings, and print the dry-run again.

Only `new` and `follow-up` findings are numbered and can be selected. Each
`already-posted` finding is listed under the table by **its own** file, line and
title, with the first line and link of the thread it matched, so a wrong match is
visible; omit the list when it is empty. Replying to one of them ("still present at
`<sha>`") happens only when the human asks for it.

### 4. Human selection

Wait for the reply. Parse:

- `all` → every numbered finding.
- `none` → stop; post nothing.
- `1,3,5` or `1 3 5` → the selected indices.

Confirm the list before posting.

### 5. Post the review comments

Use `headRefOid` from step 0 as `commit_id`. Post all selected `new` comments in
**one** `gh api` call (one review thread, not N); one that names a thread links it in
its body. A selected `follow-up` is a **reply in its thread**, not a new comment — one
call per thread (two follow-ups of the same thread go in one reply), to the id at the
end of the thread's URL (`#discussion_r<id>`). See [reference.md](reference.md) for
the exact `gh api` invocations and the comment-body format.

### 6. Confirm

Report what was posted (new comments and replies, counted apart), anything that
failed, and the PR URL.

## Error handling

- `gh` not available → stop, tell the human.
- The review threads cannot be read (step 0) → say so before the dry-run, and mark
  every finding `new`: without the threads, repeats cannot be told apart.
- A `new` finding's line isn't in the diff (position mismatch) → skip that comment
  and warn. A `follow-up` needs no diff line: it is a reply.
- A post fails → show the error, and offer to retry **only the calls that failed** —
  the review and each reply are separate calls, and repeating one that succeeded
  posts it twice.

## Uncontemplated scenarios

1. Apply the closest matching rule, with reasoning.
2. Flag it: "This case isn't covered by `review-pr`; I applied [rule] because [reason].
   Want to refine the skill?"
