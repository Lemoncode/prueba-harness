---
name: senior-review
description: 🍋 Post-implementation code & test quality review — the "is it good?" half (mechanical gates + execution belong to `verify`). Checks test meaningfulness, integration seams, TypeScript async/type pitfalls, and a self-review checklist, gated by confidence. Use after `verify`, with fresh context, to judge the quality of just-implemented code.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [reviewer]
---

# Senior Review

Judge the **quality** of the code just implemented, with **fresh context** — review
it as if it were someone else's work. This is the "**is it good?**" half of review;
the "**does it work?**" half (build, type-check, lint, tests, coverage, audit, and a
real run) is the [`verify`](.claude/skills/verify/SKILL.md) skill, which the Reviewer runs **first**. Do not re-run the
gates here — assume [`verify`](.claude/skills/verify/SKILL.md) passed and focus on judgment. Work each phase in order.

## Confidence gating

Only raise a finding you are **>80% confident** is a real problem. State your
confidence when it's borderline. A review that flags everything trains the reader to
ignore it; a review that flags only what matters gets acted on. Style nitpicks the
formatter/linter already owns are not findings.

## The project's conventions

`Read` each file the change adds or modifies (not a lockfile or generated output),
whole, not only its diff. The project's rules for that path reach you with the `Read`
tool (Claude Code injects each `.claude/rules/` file whose `paths:` cover it), and they
are the conventions this review judges against; a `cat` of the file or its diff hunk
brings none. For a path you cannot `Read` — a deleted file, or one
the change should have added — `.claude/hooks/lib/lemony.sh rules match --path=<path>`
names the rules that cover it: `Read` those. When a rule cites a reference doc for the
point you are judging, `Read` that too. Until the project migrates its playbooks
(`docs/playbooks/`), read the ones that cover the work at hand.

## Phase 1 — Test quality

[`verify`](.claude/skills/verify/SKILL.md) confirmed the suite passes; here you judge whether the tests are _meaningful_.

1. Identify the logic-bearing files in the change (services, mappers, hooks,
   processors, helpers, components).
2. For each, open its `*.spec.ts(x)` and verify:
   - Happy path covered.
   - At least one **error** case covered.
   - At least one **edge** case (empty input, null, boundary value).
   - **Arrange / Act / Assert** structure present.
   - `toStrictEqual` used (not `toEqual` / `toBe`) — `toStrictEqual` catches
     `undefined` properties the others miss.
   - Assertions test **behavior**, not the mock (no mock-and-assert, no over-mocking
     of internal modules).
3. **User-visible flow**: if the change adds/modifies a navigation / form / list /
   auth flow, is there an end-to-end test (or was one updated)? Whether one is
   warranted is the project's call: the rules for its end-to-end specs say so where it
   has them (`rules match` on such a path, as above).
4. If a spec is missing or shallow, that is a finding — name the file and the gap.

## Phase 2 — Integration seams

Most bugs live at module boundaries, not inside modules. Identify the seams this
change touches — event pipelines, cross-module boundaries, API↔UI contracts,
producer→consumer handoffs. For each seam touched, confirm there is at least one test
that **crosses the boundary**, not just a unit test inside one module.

## Phase 3 — TypeScript async & type pitfalls

Read the diff for the failure modes the compiler does not catch on its own:

- [ ] **Floating promises** — every async call is `await`ed or deliberately handled;
      no fire-and-forget that should have been awaited.
- [ ] **Missing `await` in `try`** — an un-awaited promise inside `try/catch` escapes
      the catch.
- [ ] **`any` / unsafe casts** — no `as any`, no `as unknown as T` smuggling past the
      type system; assertions are justified.
- [ ] **Non-null assertions (`!`)** that hide a genuinely possible null.
- [ ] **Unhandled rejection paths** — `Promise.all` vs `allSettled` chosen
      deliberately; one rejection doesn't silently drop the rest.
- [ ] **Boundary types** — external/untrusted input is validated and narrowed at the
      boundary, not asserted into the internal type.

## Phase 4 — Self-review checklist

Read the diff fresh, as if it were someone else's:

- [ ] No N+1 calls or unnecessary work in loops.
- [ ] Subscriptions, intervals, and event listeners cleaned up on teardown.
- [ ] No silent error swallowing (a `catch` that does nothing, optional chaining that
      hides a bug) — for a deeper pass, the [`silent-failure-hunter`](.claude/skills/silent-failure-hunter/SKILL.md) skill.
- [ ] External/user input validated at system boundaries.
- [ ] Errors fail **explicitly** with a message that identifies the problem.
- [ ] No dead code or unused variables.
- [ ] Comments only where logic is non-obvious (not narrating every line).

## Phase 5 — Report

Output a concise verdict the Orchestrator can act on:

```
## Senior Review — <task name>

**Test quality**: ✅ / ⚠️ <missing/shallow specs>
**User-visible flow**: ✅ tested / N/A / ⚠️ <gap>
**Integration seams**: ✅ covered / ⚠️ <uncrossed boundary>
**TS async/types**: ✅ / ⚠️ <finding>
**Self-review**: <findings, or "none">

**Verdict**: approve / changes requested — <one-line reason>
```

If a finding is about the spec itself (the spec is wrong or silent on a case), that is
a **discovery**, not a rejection: run [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) instead of failing the change.
