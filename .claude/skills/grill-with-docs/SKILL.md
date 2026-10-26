---
name: grill-with-docs
description: 🍋 Relentlessly interview the user about a plan or design until shared understanding is reached, grounded in existing code and documentation. Drills decision by decision, presents alternatives with trade-offs, updates CONTEXT.md inline and offers ADRs sparingly. Produces a PRD (and resumes WIP grills across sessions). Use when the user wants to stress-test a plan, define product requirements, or formalize a design grounded in their project.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [orchestrator, architect]
attribution:
  - source: mattpocock/skills
    author: Matt Pocock
    url: https://github.com/mattpocock/skills
    license: MIT
    copyright: Copyright (c) 2026 Matt Pocock
    relationship: derived-from
    note: grill workflow and decision-by-decision interview structure
---

# Grill With Docs

## Core Principle

Push the user to think deeper. Drill every decision branch. Present concrete alternatives with trade-offs — don't just ask open questions. The goal is not validation; it's helping the user discover a better design through structured interrogation, grounded in the project's existing code and documentation.

## Hard rules (the meta-feedback from past sessions)

1. **NEVER auto-decide.** Every structural decision (architecture, naming, file structure, storage, tooling, agents, scope, etc.) goes through `AskUserQuestion`. "My recommendation: X" is fine as an OPTION in a question — never as a closed decision in the plan.
2. **One question at a time.** Always. Wait for the answer before continuing.
3. **Recommend, never impose.** When proposing alternatives, mark one with `(Recommended)` and explain why. The user chooses.
4. **Don't close the plan unilaterally.** Even if you think the grill is done, ASK the user before closing. A WIP plan is acceptable; a falsely-closed plan is not.
5. **Update artifacts inline as decisions land.** `CONTEXT.md` and `ADRs` get touched when the moment is right, not batched at the end.

## Mode Detection

Detect automatically from what the user provides:

- **Validation** — user brings a structured plan with decisions already taken → challenge and verify.
- **Co-creation** — user brings a vague idea or wish → build the design together through questions and proposals.

If ambiguous, ask whether the user wants the plan challenged or built together.

## Workflow

### 1. Setup

- Announce that by default you'll briefly explore the codebase and docs to ground your questions, and that the user can opt out.
- If allowed, do quick reconnaissance:
  - Project structure, stack, conventions
  - `CLAUDE.md`, `CONTEXT.md`, `CONTEXT-MAP.md` if present
  - `docs/architecture.md` if present — the maintained map of the system's shape; orient
    the grill against it so proposals don't contradict existing boundaries/seams. Trust it
    for the big picture; verify against code where a decision actually turns on it. It is
    **absent by default and that is fine** — grill as today, and never push the user to
    create it (it is **not** one of the files this skill creates lazily below).
  - `docs/adr/` if present
  - The project's conventions — the rules under `.claude/rules/` (each one's `paths:`
    says what it governs), the client skills under `.claude/skills/` (by their
    descriptions) and `docs/reference/` if present. Until the project migrates its
    playbooks (`docs/playbooks/`), read the ones that cover the work at hand.
- Detect mode (validation vs co-creation).

### 2. Phase A — Big Picture

High-level questions first. Validate direction before diving into details. Cover both **technical** and **product/UX** perspectives.

Examples:

- "Does the overall approach make sense?"
- "Are there fundamental assumptions worth challenging?"
- "Who's the actual user / customer / audience here?"

### 3. Phase B — Branch by Branch

Identify the key decisions. Walk them one at a time.

For each branch:

- Ask the question (with concrete alternatives + trade-offs).
- Wait for the answer.
- Resolve and close the branch.
- If sub-branches emerge, note them and ask whether they're worth exploring now.

**Checkpoints**: after closing important branches, offer pending points to the user explicitly:

> "We've closed branches A, B, C. There are 5 open points left: [list]. Want to keep grilling all, prioritize some, or pause here?"

### 4. Co-creation Approach — Socratic + proposals

When the user doesn't have a formed opinion, NEVER leave it open-ended. Present alternatives:

> "You have these options: A (pros/cons), B (pros/cons), C (pros/cons). My recommendation: B because X. But you decide."

This helps the user learn through forced trade-off comparison, not just decide blindly.

### 5. Documentation Grounding (the "with-docs" part)

While grilling, weave in documentation updates as decisions crystallize.

#### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   ├── adr/
│   │   ├── 0001-event-sourced-orders.md
│   │   └── 0002-postgres-for-write-model.md
│   └── prds/
│       └── checkout-flow-2026-05-22.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   ├── adr/                          ← system-wide decisions
│   └── prds/                         ← system-wide PRDs
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files and directories lazily — only when there's something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed. Same for `docs/prds/` when the first PRD lands. **`docs/architecture.md` is the exception — never create it here.** It is client-owned; only the Architect's [`update-architecture`](.claude/skills/update-architecture/SKILL.md) skill ever edits it (and only when the file already exists).

#### Challenge against the glossary

When the user uses a term that conflicts with `CONTEXT.md`, call it out immediately:

> "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

#### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose precise canonical names:

> "You're saying 'account' — do you mean the Customer or the User? Those are different things."

#### Discuss concrete scenarios

When domain relationships are being discussed, stress-test with specific scenarios. Invent edge cases that force the user to be precise about boundaries.

#### Cross-reference with code

When the user states how something works, verify against code. If contradicted, surface it:

> "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

#### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch — capture it as it happens. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` is a glossary, NOT a spec or scratch pad. Never put implementation details there.

#### Offer ADRs sparingly

Only offer an ADR when ALL THREE are true:

1. **Hard to reverse** — meaningful cost of changing later.
2. **Surprising without context** — future reader will ask "why this way?".
3. **Result of a real trade-off** — genuine alternatives existed and one was picked for specific reasons.

Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md). If any of the three is missing, skip.
Before writing one, check it against the live ADRs and conventions exactly as
[`write-adr`](.claude/skills/write-adr/SKILL.md) step 2 does, and put any clash to the human in the grill itself.

### 6. Closing

When branches are exhausted or the user says they've had enough:

- Generate the PRD at `./docs/prds/<topic>-<date>.md` relative to the **project working directory**, creating `docs/prds/` lazily. This does NOT require a git repo or a pre-existing `docs/` — an ordinary project folder is enough.
- The file uses a `Status:` frontmatter field: `in_progress` while the grill is WIP, `completed` when closed. SAME FILE, just different status.
- **Location fallback (narrow)**: use `~/.claude/plans/<slug>-<date>.md` ONLY when there is genuinely no project workspace — e.g. the CWD is the home directory, or the grill is abstract and tied to no repo. The mere absence of git or of a `docs/` folder is NOT a reason to fall back. **If unsure whether the CWD is the right home for the PRD, ASK the user where to put it — never silently use the plans fallback.** A PRD that lands in `~/.claude/plans/` is invisible from the user's working directory and causes confusion later.
- See [reference.md](./reference.md) for the PRD template (and the WIP-specific sections used while `Status: in_progress`).
- **Before writing**: confirm with the user that the grill is done. NEVER autoclose.

## Tone

**Adaptive**. Start curious-collaborative. If the user gives shallow answers ("because", "I don't know"), escalate intensity. Always constructive, never hostile.

Three levels (full detail in [reference.md](./reference.md)):

1. **Curious-collaborative** (default).
2. **Challenging** (when user gives surface answers).
3. **Provocative-constructive** (when shallow thinking persists).

**Never go beyond level 3.** Use proposals, not insults.

## Pause & Resume

First-class workflow. Same file as the final PRD — just a different `Status:`.

### Pausing mid-grill

When the user signals they want to stop for now ("let's continue tomorrow", "leave it here", or similar):

1. **DO NOT close the plan unilaterally.** Ask the user how to proceed.
2. Save state to the PRD path chosen per the Closing location rule (`./docs/prds/<topic>-<date>.md` in the project workspace; the `~/.claude/plans/` fallback only when there is no project — ask if unsure). Set `Status: in_progress`.
3. Add the WIP-specific sections to the same file (see reference.md): "Decisions closed", "Open decisions" (priority order), "Side tasks pending", "Resume prompt".
4. The Resume prompt must be the exact text the user can re-invoke later, e.g.:
   ```
   grill-with-docs — resume <topic>. Read <path-to-PRD>. Start at decision #N. Keep grilling mode — one question at a time, do NOT auto-decide.
   ```
5. Only after confirming with the user → end the turn.

### Resuming

When the user re-invokes the skill to pick a grill back up:

1. Locate the in_progress PRD file (the user usually provides the path).
2. Read it fully — especially "Decisions closed" and "Open decisions".
3. Confirm with the user where to resume: which decisions are closed, which open one comes next, and whether to keep that order.
4. Continue branch-by-branch.

### Completing

When the grill closes:

- Flip `Status: in_progress` → `Status: completed`.
- Distribute the content of the WIP sections into the structured PRD sections (User Stories, Decisions, etc.) and remove the WIP-only sections.
- Same file. No moves between paths.

## Codebase Exploration

- **At start**: brief project reconnaissance (single bash listing + read of `CLAUDE.md`, `CONTEXT.md`, project root). NEVER deep-dive unprompted.
- **During**: on-demand when a question can be answered by code or by reading a rule/doc.
- **User opt-out**: respected if requested at setup.
- **Watch for existing partial work**: if the user has been iterating on adjacent ideas, surface what already exists (don't reinvent).

## Scope

Covers BOTH technical and product/UX. Don't assume product decisions are resolved unless the user explicitly says so. Many technical users benefit from being pushed on UX, business model, pricing, anti-copy, onboarding cost, etc.

## "Beyond the basics" — proactive risk surfacing

If the user explicitly asks for it ("go beyond the basics", "what am I not seeing"), or if you detect they're treating a strategic question as a technical one, surface 4-6 strategic risks/blind-spots they haven't named. Examples:

- Cost / unit economics at scale (token spend, licensing).
- Data residency / compliance for selling to regulated industries.
- Anti-copy / IP protection if productizing.
- Onboarding cost per customer (affects pricing).
- Documented failure modes ("this is NOT for X").
- Continuous-improvement mechanisms.

Prioritize the ones most likely to kill the project if ignored.

## Uncontemplated scenarios

When a question or situation doesn't clearly fit these rules:

1. Apply the closest matching approach with explicit reasoning.
2. **Flag it**: "This scenario isn't covered by the skill. I applied X because Y. Want me to add a rule?".
3. Offer to update the skill.

## Cross-references with other skills

In the harness, the grill output (PRD) feeds the Spec Author:

```
grill-with-docs → PRD → prd-to-spec → spec (requirements/design/tasks) → spec-to-issue → GitHub issue
```

| Scenario                                                          | Next skill                                                             |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------- |
| PRD completed → needs a spec (EARS requirements / design / tasks) | [`prd-to-spec`](.claude/skills/prd-to-spec/SKILL.md) (Spec Author)     |
| Spec ready → needs the externalized GitHub issue                  | [`spec-to-issue`](.claude/skills/spec-to-issue/SKILL.md) (Spec Author) |
| Bug spotted during exploration                                    | [`triage-issue`](.claude/skills/triage-issue/SKILL.md)                 |

Mention the relevant option in the "Next Steps" section of the PRD output.

---

See also:

- [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md) — format for the project glossary.
- [ADR-FORMAT.md](./ADR-FORMAT.md) — format for Architecture Decision Records.
- [reference.md](./reference.md) — PRD template, question categories, tone calibration details.
