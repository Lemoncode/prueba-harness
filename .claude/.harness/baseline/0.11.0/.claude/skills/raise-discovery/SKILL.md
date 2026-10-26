---
name: raise-discovery
description: 🍋 Pause the task and escalate when reality contradicts or exceeds the plan, instead of improvising. Use when a sub-agent (Spec Author, Implementer, Reviewer, Architect) hits a T1–T6 case — a contradiction, an unspecified decision, scope drift, an existing solution, an infeasibility, or a convention conflict — and needs a human decision before continuing.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [spec-author, implementer, reviewer, architect]
---

# Raise Discovery

## Core Principle

A sub-agent does **not** improvise when reality contradicts or exceeds the plan. It
**escalates to the human** through the Orchestrator — like a compiler stopping on a
type error instead of guessing what you meant. The fresh-context sub-agent is the
sensor; the human is the arbiter. Guessing past a real ambiguity is how a confident,
wrong implementation gets built.

This skill is the **raising** half of the protocol. You write one entry, return a
one-line summary, and **stop**. You do not flip labels, you do not dialogue with the
human, and you do not resume yourself — the Orchestrator owns all of that (it runs
[`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md)) and will re-invoke you with the decision when it's settled.

## When to raise — the taxonomy (T1–T6)

| Tag    | Type                 | Raise when…                                                |
| ------ | -------------------- | ---------------------------------------------------------- |
| **T1** | CONTRADICTION        | Existing code/env contradicts the plan or spec.            |
| **T2** | UNSPECIFIED_DECISION | The plan is silent and **>1 valid option** exists.         |
| **T3** | SCOPE_DRIFT          | Implementing the plan requires touching out-of-scope work. |
| **T4** | EXISTING_SOLUTION    | The plan assumes building something that already exists.   |
| **T5** | INFEASIBILITY        | The plan is not implementable as written.                  |
| **T6** | CONVENTION_CONFLICT  | Honoring the spec would contradict a project convention.   |

**Oversize / partition is a T2.** When the scope you are structuring or implementing
hides **≥2 independently mergeable units** the plan didn't reveal — each could leave the
default branch green and shippable without the other — the plan is silent on the cut
and both "partition" and "keep together" are valid: raise it as `T2 UNSPECIFIED_DECISION`
with the candidate cut in **Proposed**. Never partition silently from inside a task.

## When NOT to raise (resolve it yourself)

Escalation is for decisions with architectural or scope impact, not for everything
unstated. Decide these yourself and note them in your normal output:

- Local naming, formatting, file layout with no downstream impact.
- Cases already covered by a project convention (a rule you received, a client skill,
  a reference doc, a playbook until the project migrates) — follow it.
- A single obviously-correct option (no genuine fork).

The bar for **T2** is the sharpest: raise only when the options are genuinely
different _and_ the choice has consequences a human would want to make. "The spec
didn't name the variable" is not a discovery; "the spec didn't say whether an empty
input errors or defaults, and both are defensible" is.

## Process

### 1. Confirm it's a real discovery

Re-read the relevant spec / PRD / convention section. If it actually answers the
question, you don't have a discovery — proceed. If, and only if, it leaves a
consequential fork open, continue.

### 2. Append an entry to `discoveries.md`

The file is `.claude/state/tasks/<id>/discoveries.md`, **append-only**. Create it with
an `# Discoveries — task <id>` heading if it doesn't exist yet. Read any existing
entries to pick the next sequential id (`D001`, `D002`, …). Append a new section —
never edit or delete a prior one:

```markdown
## D001 — T2 UNSPECIFIED_DECISION · raised <YYYY-MM-DD>

- **Subtask context:** <which agent + which subtask/step you were on>
- **Plan says:** <what the spec/PRD/plan states — quote or cite the line>
- **Reality:** <what you found that contradicts or exceeds it>
- **Proposed:** <the option(s) you see, with a one-line trade-off each>
- **Question:** <the single, precise decision the human must make>
```

Fill **every** field. The entry must be self-sufficient: the Orchestrator and the
human resolve from this file alone, without your context. Leave the `**Resolution**`
block out — the Orchestrator appends it under this same header when the decision is
made. Leave `paused_from` out too: the Orchestrator records the state being left when
it pauses the task; that is its job, not yours.

### 3. Return a one-line summary and stop

Return to the Orchestrator exactly this shape, nothing more:

```
Discovery D001 (T2/UNSPECIFIED_DECISION) raised — see tasks/<id>/discoveries.md
```

Then **stop**. Do not keep working, do not pick an option, do not transition labels.
The Orchestrator will move the task to `paused_for_clarification`, add the
`harness:discovery:T*` label, mediate with the human, and re-invoke you with the
resolution. (The issue exists from the start of `spec-in-progress`, before any
sub-agent runs, so there is always an issue to label.) When it does, you resume from
the decision in the entry's `**Resolution**` block — the `paused_from` state the
Orchestrator records at pause time tells it where you left off.

## Scope note

T6 CONVENTION_CONFLICT — the spec contradicts a project convention: a rule under
`.claude/rules/`, a client skill, a reference doc under `docs/reference/`, or a playbook
the project has not migrated yet — and
any resolution that updates an ADR, `docs/architecture.md` or a convention is owned by
the **Architect**: raise it normally, and the Orchestrator routes the artifact update
to the on-demand Architect ([`write-adr`](.claude/skills/write-adr/SKILL.md) / [`update-architecture`](.claude/skills/update-architecture/SKILL.md) /
[`convention-iterate`](.claude/skills/convention-iterate/SKILL.md)) before resuming you. Telemetry for
discoveries (a `discovery_raised` event) is deferred to a later phase; in this build the
durable record is `discoveries.md` plus the issue label.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by the raise-discovery skill. I applied
   [approach] because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case.
