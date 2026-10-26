---
name: prd-to-spec
description: 🍋 Turn a completed PRD into a task spec — requirements.md (EARS), design.md, and tasks.md. Use when the Spec Author decomposes a PRD into an implementable specification, mentions "write the spec", "EARS requirements", or "requirements/design/tasks".
origin: vendor
vendor_version: '0.11.0'
phase: pre-implementation
invoked-by: [spec-author]
---

# PRD to Spec

## Core Principle

A spec is a contract, not a diff. It says **what** must be true and **why**, never
**how** line by line. The PRD captured intent through grilling; this skill turns that
intent into three artifacts an Implementer can build against and a Reviewer can check
against — without re-interviewing the human.

The Spec Author runs with **fresh context**. That is the point: if the PRD is too
vague to write a testable requirement from, the PRD is not done. Do not paper over
the gap by guessing — surface it (see "When the PRD is insufficient").

## Inputs and outputs

- **Input**: a PRD at `docs/prds/<topic>-<date>.md` (owned by the Orchestrator via
  [`grill-with-docs`](.claude/skills/grill-with-docs/SKILL.md)). This skill **consumes** the PRD — it never edits or closes it.
- **Output**: three files under `.claude/state/tasks/<id>/spec/`. The Orchestrator
  created the issue and the task branch before invoking the Spec Author, so `<id>` is
  real from the start — there is no `draft-<slug>` holder:
  - `requirements.md` — EARS requirements with acceptance criteria
  - `design.md` — files, functions, approach, the spec gate decisions, edge cases,
    testing
  - `tasks.md` — atomic, ordered checkbox tasks, grouped under risk-sized step headers

## Process

### 1. Read the PRD in full

Read the whole PRD, plus any `CONTEXT.md` glossary terms and `docs/adr/` it
references. Identify: the user stories, the decisions already closed, what's
explicitly out of scope, and the assumptions/risks flagged. The closed decisions are
constraints — the spec must honor them, not relitigate them.

### 2. Write `requirements.md` (EARS)

Express every requirement in **EARS** (Easy Approach to Requirements Syntax). EARS is
five sentence patterns — pick the one that fits each requirement:

| Pattern               | Template                                                           | Use for                                           |
| --------------------- | ------------------------------------------------------------------ | ------------------------------------------------- |
| **Ubiquitous**        | The `<system>` shall `<response>`.                                 | Always-active properties, invariants              |
| **Event-driven**      | When `<trigger>`, the `<system>` shall `<response>`.               | A response to a specific event/input              |
| **State-driven**      | While `<state>`, the `<system>` shall `<response>`.                | Behavior that holds during a state                |
| **Optional-feature**  | Where `<feature>`, the `<system>` shall `<response>`.              | Behavior that exists only if a feature is present |
| **Unwanted-behavior** | If `<unwanted condition>`, then the `<system>` shall `<response>`. | Error handling, invalid input, failure paths      |

Complex requirements combine patterns, outer-clause first:
_"While `<state>`, when `<trigger>`, the system shall `<response>`."_

Rules:

- **Number every requirement** (`R1`, `R2`, …) so design and tasks can reference them.
- **Always include the unwanted-behavior path.** A spec with no `If … then …`
  requirements is almost always incomplete — error and invalid-input handling is
  where bugs live.
- **One requirement, one shall.** Split compound sentences.
- **Testable, not vague.** "shall respond quickly" is not a requirement; "shall
  respond within 200ms" is.
- Group requirements under the user story or capability they serve.
- Add a short **Acceptance criteria** list per capability — the observable facts a
  Reviewer checks.

Template:

```markdown
# Requirements — <topic>

> Source PRD: docs/prds/<topic>-<date>.md

## <Capability / user story>

- **R1** (event): When <trigger>, the system shall <response>.
- **R2** (unwanted): If <invalid condition>, then the system shall <response>.
- **R3** (ubiquitous): The system shall <invariant>.

### Acceptance criteria

- [ ] <observable fact a reviewer can verify>
```

### 3. Write `design.md`

The _how_, at the level a competent implementer needs — not a transcript of the code.

```markdown
# Design — <topic>

## Approach

<2–5 sentences: the shape of the solution and why, honoring the PRD's closed decisions.>

## Spec gate decisions

- **D1 — <the call, in one line>.** [deviates]
  <alternatives considered, the one taken and why, what it commits the human to>
- **D2 — <the call, in one line>.** [open]
  <…>

## Files

- `path/to/file.ts` — <created|modified> — <what it holds>

## Functions / interfaces

- `functionName(args): ReturnType` — <contract: what it guarantees, which Rs it serves>

## Edge cases

- <edge case> → <intended behavior> (maps to R#)

## Testing approach

- <what to test and at which level — unit / integration; what NOT to test and why>
```

Honor the project's conventions for structure, naming and the testing pyramid: the
rules that reached you as you read the code this spec touches, the rules for the files
it will create (`.claude/hooks/lib/lemony.sh rules match --path=<path>` names them), the
reference docs they cite, and any client skill whose description fits. Until the
project migrates its playbooks (`docs/playbooks/`), read the ones that cover the work
at hand. If the design would contradict one, that's a discovery, not a silent
deviation (T6).

**`## Spec gate decisions` is mandatory.** It is what the human reads at the approval
gate: `lemony spec-cover` renders the gate's one-screen cover from it, so a call that is
not here is a call the human never sees. List **every call you made that the source (the
PRD, or the issue when there is none) did not** — an interpretation, an addition, a
narrowing, a default you picked — one entry each:

- The entry opens with a bold headline, `**D<n> — <the call, in one line>.**`, numbered
  from `D1` in file order, then exactly one **origin tag** in brackets. The body follows
  on the next lines: the alternatives, the one you took and why, the consequence the
  human signs.
- The tag is closed — the cover goes red on a missing or unknown one:

| Tag          | The call…                                                                                                                                                                                           |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deviates`   | narrows, reinterprets or departs from the source, a blueprint or a convention. A contradiction of a closed decision or a convention is still a discovery first (T6); once resolved, record it here. |
| `preference` | is a human-taste axis: naming, the language code and docs are written in, layout, tooling, a library pick.                                                                                          |
| `open`       | settles something the source leaves open and that does not fit the two above.                                                                                                                       |

- The cover lists `deviates` first, then `preference`, then `open` — the first two are
  the calls most often reversed after approval. When a call fits two tags, pick the one
  listed first.
- A call too large to make yourself — one with more than one valid option that changes
  what the requirements say — is still a T2 discovery (§When the PRD is insufficient),
  not an `open` entry.
- **None is said, not implied**: a spec that follows its source as written keeps the
  heading with the single line `None — the spec follows its source as written.` A
  missing section is not "none".
- The section is part of the approved spec. A later amendment (a discovery resolved
  after the gate) does not have to add an entry.

### 4. Write `tasks.md`

Atomic, ordered checkboxes. Each task is a **vertical slice** (a behavior, not a
layer) so the Implementer can run TDD red→green per task. Reference the requirements
each task satisfies.

Group the tasks under **risk-sized step headers**. In step-by-step mode the loop runs
one implement→review→human-checkpoint cycle **per group**, so the grouping decides how
often the human is interrupted; the human approves it at the spec gate with the rest
of the spec. Grouping criterion:

1. **Risk isolates — hard rule.** A task gets its own group iff it concentrates risk:
   a new seam, a hard-to-reverse decision, a data-loss or security surface.
2. **Runnable surface closes — soft rule.** Among trivial stretches, prefer group
   boundaries that leave something the human can run at the checkpoint. Never invent
   a group to fabricate a demo.
3. **Soft cap: 4 tasks per group**, exceedable only with explicit justification in
   the group's rationale (e.g. "5 identical mechanical renames").
4. **Every group header carries a one-line boundary rationale** so the grouping is
   auditable at the spec gate.
5. **A group whose risk has a name carries it as a machine-readable tag.** When the
   damage a group can do is one the vocabulary below names, the header ends with
   `[risk: <class>]` — the **last element of the line**, after the rationale; multiple
   classes are comma-separated (`[risk: data-loss, secrets]`).
   The vocabulary names what kind of damage the surface can do:

   <!-- risk-vocabulary:start -->

   | Class             | Surface                                                          |
   | ----------------- | ---------------------------------------------------------------- |
   | `auth`            | authentication, authorization, session or token handling         |
   | `payments`        | money movement, billing, pricing                                 |
   | `shell-process`   | shell invocation, subprocess spawning, argument construction     |
   | `data-loss`       | writes, deletes, migrations, anything that can destroy user data |
   | `secrets`         | credentials, keys, tokens — at rest or in transit                |
   | `executable-mode` | file permissions, exec bits, anything that changes what can run  |

   <!-- risk-vocabulary:end -->

   The tag keys on **damage, not on which rule made the group**. A group that isolates
   a new seam or a hard-to-reverse decision is a risk isolate under rule 1 and still
   carries **no tag**, because no class names that damage — and absence is itself the
   declaration ("nothing here does one of those things"), never an omission.

   If a group's damage has no class in the vocabulary, **leave the tag off and name that
   damage in the group's rationale** — rule 4 already requires a rationale, and damage
   named in prose beats a wrong class in a tag. Then say so in your handoff summary, in
   one line, so the human can decide whether the vocabulary should grow. Do **not** pick
   the nearest class (the self-check below rejects it), do not invent a one-off class,
   and do not edit the table here: it is vendor-owned — generated into this skill and
   [`triage-issue`](.claude/skills/triage-issue/SKILL.md) from one source, so the two always agree — and a local edit is
   discarded on the next harness update.

   The tag is what the **human approves at the spec gate**: approving the spec approves
   the grouping _and its tags_, so a wrong tag is a spec defect, not a review defect.
   That approval is where its force starts, and a reader now depends on it: at review the
   tags are handed to [`security-review`](.claude/skills/security-review/SKILL.md), which deepens the section named for each class
   instead of inferring the surface from the diff. And a script reads them: the review
   evidence ledger's validator (`lemony review-ledger validate`) checks every tag on the
   group under review against the vocabulary and reports one outside it as
   `unknown-risk-class` — a spec defect that reaches the human, never a silent drop.

```markdown
# Tasks — <topic>

## Group 1 — <name> _(<one-line boundary rationale>)_

- [ ] T1 — <smallest behavior that proves the path end-to-end> (R1)
- [ ] T2 — <next behavior> (R2)

## Group 2 — <name> _(<one-line boundary rationale>)_ [risk: data-loss]

- [ ] T3 — <error path> (R2, R3)
- [ ] **T4 — <a task that needs detail>.**
      <detail prose, as many indented lines as it needs, with the ref list
      ending the last one> (R3, R4)
```

**Ref list — one rule, read by a script.** A task's requirement refs are one
comma-separated `(R<n>, R<m>)` group that **ends a line**: the end of the task's first
line, or the end of one continuation line (a line of its own, or the end of a detail
line). Nothing after the closing paren on that line, not even a period. No ranges —
`(R1–R4)` is not a list, write `(R1, R2, R3, R4)` — and no prose inside the parens.

**Mentions.** A `(R<n>` on the task's first line, or right after the title's bold
close, is always read as the declaration: it is reported if it does not end the line,
even when a list ends a later line. Keep every other `(R<n>)` mention in detail prose
**mid-line**. When two lists end continuation lines the validator cannot tell which is
the declaration and reports the task; on a task that declares no list, the one
line-ending mention is read as its declaration, and a mid-line one is reported. An
aside that must open a parenthesis with a requirement id opens it with `per` —
`(per R42, …)` — because a bare `(R42…` falls under the rules above exactly like a
declaration, and can be elected over the real list, sometimes silently. A `per` aside
is never read, so it never stands in for the list: the task still declares its own.

The review evidence ledger's validator enumerates each group's review slice from these
refs; a task it cannot read is reported as `malformed-task-refs` — a spec defect that
pauses the loop, never read as "declares none".

The checkbox itself is the **Implementer's done-marker**: it flips `- [ ]` → `- [x]`
when the task reaches green, with the task's commit. Write every task `- [ ]`; the same
validator reports a task still `[ ]` in a group the loop has passed
(`unticked-completed-task`), so the file tracks the progress its shape promises.

**Line shapes — read by the same script.** A task line is `- [ ]` or `- [x]` and a bare
`T<n>` id, at the task list's own indentation; a group header is exactly `## Group <n>`,
numbered from 1, with `Group` in English even when the spec is written in another
language. A line that looks like one but is not — an in-progress `[-]`, a suffixed
`T12b` or `T1.1`, a numbered `1. [ ]` item, a `- T6` with no box, a task inside a `>`
quote, a `T<n>` sub-item indented under another task, `### Group 3`, `## Group 0`, a
digit-less `## Group P`, a translated `## Grupo 2 — … _(…)_` — is reported
(`malformed-task-line`, `malformed-group-header`), never skipped; a note bullet about a
task opens with
something other than its `T<n>`. Every `T<n>` is used once in the file
(`duplicate-task-id` otherwise). Detail prose may run to several paragraphs: a blank
line inside a task is fine while the next line stays indented at least to the task's
text (two spaces under `- [ ]`); less, and it is no longer the task's. Code fences and
`>` quotes are never read as tasks, but a task or header shape inside one is reported
too — a quoted sample looks exactly like a task under a fence left open — so quote
samples without a `T<n>` id or a group header.

Rules: order so the first task is a tracer bullet; never "write all tests" then
"write all code"; keep each task small enough to verify on its own. Grouping never
changes task granularity — checkboxes stay atomic and TDD runs per task; only review
and checkpoint frequency follow the groups (all-at-once mode ignores the headers).
Tasks added mid-implementation (from a discovery) take the **next free `T<n>`** (never
a suffixed `T12b`) and default to **their own group** — they are risk by definition,
and grouping rule 5 applies to them unchanged — but they are added **after** the spec
gate, and no later gate presents a group header, so their tags get no human reading at
all. Tag them for the record; do not rely on anyone
catching a wrong one.

### 5. Self-check before handing off

- [ ] Every PRD user story maps to at least one requirement.
- [ ] Every requirement is EARS-formatted and testable.
- [ ] At least one unwanted-behavior (`If … then …`) requirement exists.
- [ ] Every requirement is covered by at least one task.
- [ ] Every task sits in a group, and every group header carries a one-line
      boundary rationale.
- [ ] Every group that can do damage the vocabulary names ends its header with a
      `[risk: …]` tag; no group carries a class whose damage it cannot do.
- [ ] No closed PRD decision is contradicted.
- [ ] `design.md` has `## Spec gate decisions`: every call the source did not make is an
      entry with exactly one origin tag, or the section says `None — …`.

### 6. Emit `spec_created`

Telemetry — record that the spec landed. Count the EARS requirements in
`requirements.md` (each `R<N>` entry, e.g. `R1`, `R2`, …) and emit via Bash:

```bash
.claude/hooks/lib/lemony.sh emit spec_created \
  --task-id="<id>" \
  --topic="<slug>" \
  --requirements=<count>
```

`<slug>` is the topic part of the task branch (`harness/<id>-<slug>`). The CLI
Zod-validates the line and appends it to `.claude/state/events.jsonl`.

Then hand off to [`spec-to-issue`](.claude/skills/spec-to-issue/SKILL.md) to fill the issue body with the externalized spec.

## When the PRD is insufficient

If a requirement can't be written without choosing between >1 valid option the PRD
left open, that's a **T2 UNSPECIFIED_DECISION** discovery — the spec cannot be
self-sufficient. Do not guess. **Run the [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) skill**: write the entry to
`discoveries.md`, return the one-line summary, and stop. The Orchestrator mediates the
question with the human, the PRD/spec improves, and you are re-invoked with the
decision.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by the prd-to-spec skill. I applied
   [approach] because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case.
