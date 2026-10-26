---
name: tdd
description: 🍋 Test-driven development with red-green-refactor loop. Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
origin: vendor
vendor_version: '0.11.0'
phase: during-implementation
invoked-by: [implementer]
attribution:
  - source: mattpocock/skills
    author: Matt Pocock
    url: https://github.com/mattpocock/skills
    license: MIT
    copyright: Copyright (c) 2026 Matt Pocock
    relationship: derived-from
    note: the red-green cycle, the behavior-over-implementation core principle, the vertical-slice ("tracer bullet") framing, mock-at-system-boundaries guidance, and the ADR three-tests nudge
---

# Test-Driven Development

## Core Principle

Tests verify behavior through public interfaces, not implementation details. Code
can change entirely; tests shouldn't break. A good test reads like a specification —
"user can checkout with valid cart" tells you exactly what capability exists.

## Workflow

### 0. Preflight (mandatory — before writing any code or test)

1. Load the project knowledge that does not arrive on its own. The project's rules
   (`.claude/rules/`) reach you after you `Read` or edit a file their `paths:` cover.
   Two channels do not arrive that way:
   - a client skill under `.claude/skills/` whose description fits this task — invoke
     it;
   - a reference doc that a rule you received cites (`docs/reference/<topic>.md`) for
     the part you are about to write — `Read` it.

   Until the project migrates its playbooks (`docs/playbooks/`), read the ones that
   cover the work at hand. When the project has none of these, go on: a missing one is
   not a blocker.

2. Declare the test environment explicitly:

   | This file type…                             | Use…                                               |
   | ------------------------------------------- | -------------------------------------------------- |
   | Pure logic, service, hook (no DOM)          | Node spec (`*.spec.ts`) — `environment: 'node'`    |
   | React component, DOM interaction, rendering | Browser spec (`*.browser.spec.tsx`) — real browser |

   State aloud: "This is a [type] test → [node/browser] mode, because [reason]."

3. Output preflight log: "Skills/refs loaded: [list]. Test environment: [node/browser].
   Proceeding."

### 1. Planning

Before writing any code:

- Confirm with user what interface changes are needed
- Confirm with user which behaviors to test (prioritize — you can't test everything)
- List the behaviors to test (not implementation steps)
- Get user approval on the plan

Ask: "What should the public interface look like? Which behaviors are most important
to test?"

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet — proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior
- When the behaviors belong to a `tasks.md` task, its checkbox is the task's
  done-marker: flip `- [ ]` → `- [x]` when the task's **last** behavior is GREEN
  (the suite passing), and commit (or stage) it with the task's code

### 4. Refactor

After all tests pass, look for refactor candidates:

- Never refactor while RED — get to GREEN first
- Run tests after each refactor step

## Capture decisions worth remembering (ADR nudge)

A green test proves _what_ the code does. It rarely captures _why_ this
implementation was chosen over the alternatives. After a cycle (or at the end of a
feature), ask: did this step embed a decision that will look arbitrary to a future
reader?

Three signals — if **all three** are true, write an ADR (`docs/adr/NNNN-slug.md`):

1. **Hard to reverse** — changing your mind later costs real work (data migration,
   public API break, cross-module refactor, downstream client coordination).
2. **Surprising without context** — a future reader will see the code and wonder
   "why on earth did they do it this way?"
3. **Result of a real trade-off** — there were genuine alternatives and you picked
   one for specific reasons (not "the obvious thing").

Common triggers inside a TDD cycle:

- A defensive cap or limit (depth, budget, retries, page size). The _value_ you
  picked is the artifact most likely to drift later; the reason is rarely in the code.
- A "consistency at every level" rule — easy to write, easy for a future patch to
  break without noticing.
- A non-obvious algorithm/data structure picked to satisfy a perf or budget test.
- A deliberate **no-test** decision — "we are intentionally not covering X because the
  cost outweighs the value." Future contributors will add the missing test and break
  the design.
- A boundary or scope decision: "this concern lives in module A, not module B."

If only one or two signals hit, a `// Why: …` comment at the call site is usually
enough. The bar for an ADR is "this decision will outlive my memory of writing it".

When in doubt, flag it: "I made a non-trivial trade-off about X. Want me to draft an
ADR?" — let the user decide. (The Architect's [`write-adr`](.claude/skills/write-adr/SKILL.md) skill owns the ADR format;
numbering is sequential under `docs/adr/`.)

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is the biggest TDD
mistake.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
```

Tests written in bulk test _imagined_ behavior. You outrun your headlights,
committing to test structure before understanding the implementation. Each vertical
cycle informs the next — because you just wrote the code, you know exactly what
behavior matters.

## When NOT to Apply TDD

Not everything needs red-green-refactor:

- **Validation schemas** — declarative, self-validating
- **Configuration** (routes wiring, test config) — no logic to test
- **Type definitions / interfaces** — no runtime behavior
- **Re-exports / barrel files** — just wiring
- **Constants and enums** — declarative
- **Middleware wiring** — the middleware logic is tested, the wiring isn't
- **Pass-through wrappers** — re-exporting a library without added logic
- **Database migrations** — DDL scripts, validated by execution
- **Static content** — i18n strings, templates, fixed content
- **Logger / env config setup** — pure configuration
- **Prototypes / spikes** — ask the user: "Do you want tests for this spike?"

**Always test**: mappers (even small ones), services with business logic,
repositories (integration), routes (API behavior), components (user interaction).

## Mocking Strategy

**`vi.spyOn` as default** — mock at system boundaries only (external APIs, databases,
time/randomness). Don't mock your own modules' internals. DI only when it genuinely
adds value. The project's own mocking recipes come with the rules for its spec files,
or a reference doc they cite.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching rule with reasoning
2. **Flag it**: "This scenario isn't covered by the tdd skill. I applied [rule]
   because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case
