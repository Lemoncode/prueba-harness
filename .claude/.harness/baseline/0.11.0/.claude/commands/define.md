---
description: 🍋 Force DEFINE mode — start the L1 full-SDD round-trip for a new feature or idea.
allowed-tools: Read, Write, Edit, Bash, Task, Skill
---

# /define

Enter **DEFINE** mode and run the **L1 full-SDD round-trip** exactly as specified in
`.claude/agents/orchestrator.md` (§"L1 full-SDD round-trip"). This command only
**forces the mode** — it does not redefine the flow. The orchestrator file is the
single source for the steps; follow it there.

`$ARGUMENTS` is the idea or feature to define. If empty, ask one question to capture
the idea, then proceed.

The round-trip, in brief (authority is the orchestrator): grill the idea into a PRD
([`grill-with-docs`](.claude/skills/grill-with-docs/SKILL.md)) → open the task issue + branch → dispatch the Spec Author →
reach `spec-ready` → run the human approval gate → implement ([`tdd`](.claude/skills/tdd/SKILL.md)) → review
(the Reviewer's full pass) → human merge gate → closeout. Honor every human gate, never
self-approve, and move the `harness:status:*` labels per the lifecycle.

If the task turns out to be too small for the full ceremony — nothing to specify,
verify, or review — nudge toward `/triage` (L2) or `/bypass` (L3) per the task-fit
dial (`.claude/agents/fit-assessment.md`). When in doubt, keep it in the harness.

The dial's ceiling is the **partition question**: if the closed PRD bundles separable,
independently mergeable wants, the orchestrator asks — at the define's close, before
opening the task — whether to cut the feature into several issues, each its own
branch, PR and merge gate (authority: `.claude/agents/partition.md`, read on trigger).
An approved cut opens a parent partition-plan issue (`harness:partition-plan`, never a
task) and Part 1 as a normal task; later parts open at their turn.
