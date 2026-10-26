---
name: write-adr
description: 🍋 Record an architecture decision as a numbered ADR in docs/adr/. Use when a discovery resolution (or an explicit request) settles a decision that is hard to reverse, surprising without context, and the result of a real trade-off — the three tests that earn an ADR. The Orchestrator invokes the Architect with this skill; it never writes an ADR for a decision that fails the tests.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [architect]
trigger-condition: a resolved decision is worth recording (a discovery resolution, or an explicit request)
attribution:
  - source: mattpocock/skills
    author: Matt Pocock
    url: https://github.com/mattpocock/skills
    license: MIT
    copyright: Copyright (c) 2026 Matt Pocock
    relationship: derived-from
    note: ADR format — the three-tests rubric (hard to reverse / surprising / real trade-off), the record template, and the "what qualifies" guidance
---

# Write ADR

## Core Principle

An ADR records **that** a decision was made and **why** — not how to implement it. Its
audience is a future engineer who finds the code and asks "why on earth did they do it
this way?" Most ADRs are a single paragraph. The value is in the record, not in filling
out sections.

This is the **Architect's** skill, invoked on-demand by the Orchestrator — typically
when a discovery resolution settles something durable, or on an explicit request. It is
not part of the linear implementation flow.

## When an ADR is warranted (all three must hold)

1. **Hard to reverse** — changing your mind later carries a meaningful cost.
2. **Surprising without context** — a future reader would otherwise wonder why.
3. **The result of a real trade-off** — there were genuine alternatives and one was
   chosen for specific reasons.

If a decision is easy to reverse, not surprising, or had no real alternative, **do not
write an ADR** — say so and stop. Examples that qualify: architectural shape, an
integration pattern between contexts, a technology choice that carries lock-in, a
boundary/scope decision, a deliberate deviation from the obvious path, a constraint not
visible in the code, a non-obvious rejected alternative.

## Process

1. **Confirm it qualifies.** Apply the three tests. If it fails, report that an ADR
   isn't warranted and why — don't pad the log with reversible or obvious decisions.
2. **Check it against the live decisions — before writing.** Search the ADRs still in
   force — every `docs/adr/NNNN-*.md` not wholly `superseded` or `deprecated`; a
   _partially_ superseded ADR is live for the points it does not name as superseded —
   and the project's conventions: the rules under `.claude/rules/`, the client skills
   under `.claude/skills/`, `docs/reference/` and the playbooks the old hooks still
   enforce (`paths.playbooks` and `paths.playbooks_global` in `harness.config.yml`),
   for what this decision contradicts. If anything clashes, **stop before writing**
   and report each clash — the document, the point, how they disagree. The human
   decides: supersede it, keep it as a deliberate exception, or change this decision
   instead. Don't assume the supersede: an ADR is
   this project's own call, and one that departs from a broader convention may be exactly
   the exception it records.
   - **Supersede an ADR** → in the same change, write this ADR and mark the old one
     `Status: superseded by ADR-NNNN` (or `partially superseded by ADR-NNNN`, naming the
     points), so the chain is never left to discipline.
   - **Change a convention** (a rule, client skill, reference doc or playbook) → name
     it in your report; the Orchestrator routes it to [`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) — you
     don't edit a convention from here.

   When you are dispatched **with the human's decision** on a clash (it arrives in the
   spawn prompt — whether you, [`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) or [`import-knowledge`](.claude/skills/import-knowledge/SKILL.md) reported it), that clash is
   settled: apply the decision (the supersede; the exception, which the ADR then names;
   or the convention change it named, once that change has landed) instead of reporting
   it again. A convention change that waits on this ADR is
   not a new clash. Any other clash still stops you.

3. **Number it.** Scan `docs/adr/` for the highest existing `NNNN-*.md` and increment.
   Create `docs/adr/` lazily if this is the first ADR.
4. **Write it** to `docs/adr/NNNN-<slug>.md`. Start minimal:

   ```md
   # NNNN — {Short title of the decision}

   {1–3 sentences: the context, what was decided, and why.}
   ```

   Add an optional section **only when it earns its place** (most ADRs need none):
   - **Status** (`proposed | accepted | deprecated | superseded by ADR-NNNN |
partially superseded by ADR-NNNN (<points>)`) — when the
     decision may be revisited.
   - **Considered options** — when the rejected alternatives are worth remembering.
   - **Consequences** — when non-obvious downstream effects need calling out.

5. **Link, don't duplicate.** If the decision changes the architecture, the
   [`update-architecture`](.claude/skills/update-architecture/SKILL.md) skill keeps `docs/architecture.md` current and references this
   ADR — the ADR captures the _why_, the architecture doc the _shape_. Don't restate one
   in the other.

## Report

Return to the Orchestrator: the ADR path and number, a one-line summary of the decision
and any ADR it superseded — or, if it didn't qualify, that no ADR was written and which
test it failed; or, if it clashes with a live decision, that nothing was written yet and
each clash for the human. This is the same lightweight ADR convention
[`grill-with-docs`](.claude/skills/grill-with-docs/SKILL.md) offers during a grill
(`# NNNN — title` plus 1–3 sentences, optional sections only when they earn their
place), so ADRs born either way read the same.

## Uncontemplated Scenarios

When a case doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This isn't covered by the write-adr skill. I did [approach] because
   [reason]. Want to refine the skill?"
3. Offer to add a rule for the case.
