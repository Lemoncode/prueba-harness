---
name: spec-compliance-check
description: 🍋 Walk an L1 spec point by point against the implementation and emit a per-requirement pass/fail verdict. Use during review of an SDD task to prove every EARS requirement (including unwanted-behavior paths) is satisfied and tested — a durable audit trail. Complements `senior-review` (quality) with traceability (coverage of intent).
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [reviewer]
---

# Spec Compliance Check

[`senior-review`](.claude/skills/senior-review/SKILL.md) judges whether the code is _good_; this skill proves it does what the
**spec said** — every requirement, point by point. It produces a traceability matrix:
a durable audit trail mapping each requirement to its implementation and its test.
Only meaningful for **L1 (SDD) tasks** that have a spec under
`.claude/state/tasks/<id>/spec/`; skip it for L2.

## Process

### 1. Load the spec

Read all three spec artifacts for the task:

- `requirements.md` — the **EARS** requirements (ubiquitous / event-driven /
  state-driven / optional-feature / **unwanted-behavior**), each numbered with
  acceptance criteria.
- `design.md` — the intended files, interfaces, approach, edge cases.
- `tasks.md` — the atomic checklist grouped under risk-sized step headers, each
  item referencing the requirements it satisfies.

### 2. Trace each requirement to the implementation

For **every** numbered requirement (do not sample — enterprise audit trails are
exhaustive):

1. Locate where the change implements it (file + symbol).
2. Locate the test that proves it (the test whose assertion maps to the acceptance
   criteria).
3. Decide the verdict:
   - **PASS** — implemented **and** covered by a test that asserts the acceptance
     criteria.
   - **PARTIAL** — implemented but the test is missing or doesn't assert the criteria.
   - **FAIL** — not implemented, or the behavior contradicts the requirement.

Pay special attention to **unwanted-behavior** requirements (`If … then …`) — these
are the ones implementations quietly skip. Each needs a test that drives the bad input
and asserts the rejection/guard.

### 3. Check for drift

- **Unspecified additions**: implementation behavior with no backing requirement →
  either scope drift (a `T3` discovery) or a missing requirement.
- **Design divergence**: the change took an approach `design.md` didn't describe —
  note it; if it invalidates a design decision, that's a discovery.

### 4. Emit the matrix

Destination: the full-pass **issue comment**. In your return summary — and always on
a per-step review, which posts no comment — carry only the counts + the failing
rows, per the Reviewer's verdict-size rule.

```
## Spec Compliance — task #<id>

| Req | Summary | Status | Implementation | Test |
| --- | --- | --- | --- | --- |
| R1 | <ubiquitous …> | ✅ PASS | `x.service.ts:42` | `x.service.spec.ts` |
| R7 | <If invalid → reject> | ⚠️ PARTIAL | `x.service.ts:80` | — (no test) |
| R9 | <state-driven …> | ❌ FAIL | — | — |

**Covered**: <n>/<total>  ·  **Partial**: <n>  ·  **Failing**: <n>
**Verdict**: compliant / non-compliant — <one-line reason>
```

A `FAIL` or `PARTIAL` is a review finding routed back to the Implementer. If a
requirement is itself wrong, ambiguous, or contradicted by reality, that's a
**discovery** — run [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md), don't quietly mark it PASS or rewrite the spec
yourself.
