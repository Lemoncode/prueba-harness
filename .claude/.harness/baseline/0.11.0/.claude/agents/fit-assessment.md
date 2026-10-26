# Task-fit assessment — the dial

> Vendor reference doc. The **canonical, operative nudge criterion** lives in
> `.claude/agents/orchestrator.md` (§"Task-fit assessment") — that file is the hat, always
> loaded, so it is the single source the Orchestrator acts on. This doc is the
> fuller model and worked examples behind that one-paragraph rule; when the two
> ever drift, `.claude/agents/orchestrator.md` wins.

The harness is a **dial, not an on/off switch**. Every
incoming task lands at one of three levels of ceremony. The Orchestrator (an
LLM) classifies — there is **no runtime scorer** (a keyword heuristic would be
less accurate and would bias toward the expensive failure; a data-driven scorer
is a later-phase revisit once telemetry exists).

## The three levels

| Level                | Ceremony                                                     | For                                                                    | Path               |
| -------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------- | ------------------ |
| **L1 — full SDD**    | Grill → spec → human gate → implement → review → merge gate  | Real features; anything whose intent is worth pinning down before code | DEFINE (`/define`) |
| **L2 — lightweight** | Issue + branch + implement (TDD) + light review → merge gate | Small bugs that still deserve a record and a reviewer, not a spec      | TRIAGE (`/triage`) |
| **L3 — bypass**      | None — no issue, no task state, no review                    | Typos, mechanical renames, lockfile bumps, comment fixes               | `/bypass`          |

The gradient is **cost of ceremony vs. cost of a missed mistake**. L1 spends the
most ceremony because a misunderstood feature is the most expensive thing to
discover at review (or in production). L3 spends none because there is nothing a
spec or a reviewer would catch that the change itself doesn't already make
obvious.

## The criterion: specifiable, verifiable, or reviewable

A task **deserves the harness** (L1 or L2) if it is at least **one** of:

- **Specifiable** — you could write down, ahead of time, what "done" means in a
  way that could be wrong. If there's a spec worth agreeing on before code, it's
  L1.
- **Verifiable** — there's a behaviour a test could pin down (a red test today,
  green after). If the change has a testable contract, it earns at least L2.
- **Reviewable** — a second reader could catch a real mistake in it. If the diff
  has judgement in it (logic, naming that encodes intent, an edge case), a
  reviewer adds value.

If a task meets **none** of the three — there's nothing to specify, nothing a
test would meaningfully assert, nothing a reviewer would catch — it's **L3**.

**When in doubt, keep it in the harness.** A wasted bit of ceremony is cheaper
than an unreviewed bug. The nudge toward `/bypass` is a single, discardable
question — it never blocks.

## L1 vs. L2: spec or no spec

Both run the branch → PR → human merge gate; the difference is the **front half**:

- **L1** when the _intent_ is what's at stake — a feature, a behaviour change, a
  decision that a human should sign off on _before_ code exists. The spec, not
  the code, is the source of truth, so the approval gate sits at the head of
  implementation.
- **L2** when the intent is obvious but the _fix_ still wants a record and a
  reviewer — a bug with a clear root cause. Skip the spec and its gate; keep the
  issue, the branch, the TDD loop, and the review.

The mechanical marker: an L1 task carries `harness:sdd`; an L2 task does not (its
absence is what selects the lightweight path).

## Worked examples

| Task                                                  | Specifiable?                         | Verifiable?                    | Reviewable? | Level  |
| ----------------------------------------------------- | ------------------------------------ | ------------------------------ | ----------- | ------ |
| "Add SSO login with role-based access"                | yes — many decisions to pin          | yes                            | yes         | **L1** |
| "Export the report as CSV"                            | yes — column set, escaping, encoding | yes                            | yes         | **L1** |
| "Pagination returns the wrong total on the last page" | no spec needed                       | yes — red test on the boundary | yes         | **L2** |
| "Null deref when the user has no avatar"              | no                                   | yes — reproduce then fix       | yes         | **L2** |
| "Rename `usr` → `user` across the module"             | no                                   | no — mechanical                | barely      | **L3** |
| "Fix a typo in a log string"                          | no                                   | no                             | no          | **L3** |
| "Bump the lockfile after `npm audit fix`"             | no                                   | no                             | no          | **L3** |

The borderline cases are the interesting ones. A "rename" that also changes a
public API is **L2** (a reviewer should see the call-site churn). A "typo fix" in
a user-facing error message that other code matches on is **L2** (something could
break). The properties, not the surface verb, decide.

## Escape hatches

- **`/bypass`** — force L3 on a task the dial would otherwise pull into the
  harness. It emits exactly one `l3_bypass` telemetry event (so misclassification
  is observable later) and then does the work with no issue, no task state, no
  review. The escape hatch is deliberate and recorded, not silent.
- **`/hotfix`** — an urgent L2 that skips the _human-wait_ gates (no approval
  pause) while the Reviewer still runs asynchronously. The urgency buys speed,
  not the loss of a second pair of eyes; the retroactive issue and a short
  postmortem are backfilled after the fire is out.

Both are documented inline in their command files (`commands/bypass.md`,
`commands/hotfix.md`) — the concrete mechanic lives with the command; the
classification logic stays here and in `.claude/agents/orchestrator.md`.
