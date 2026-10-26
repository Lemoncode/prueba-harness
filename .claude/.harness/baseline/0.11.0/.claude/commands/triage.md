---
description: 🍋 Force TRIAGE mode — start the L2 lightweight round-trip for a small bug.
allowed-tools: Read, Write, Edit, Bash, Task, Skill
---

# /triage

Enter **TRIAGE** mode and run the **L2 lightweight round-trip** exactly as specified
in `.claude/agents/triage.md` (the orchestrator's lazy companion). This command only
**forces the mode** — that file is the single source for the steps.

`$ARGUMENTS` is the bug report (the symptom, repro, or error). If empty, ask one
question to capture it, then proceed.

In brief (authority is the orchestrator): triage the codebase to find the root cause
draft a TDD-based fix plan and declare the risk surfaces ([`triage-issue`](.claude/skills/triage-issue/SKILL.md)), creating
the issue with
`harness:managed` (no `harness:sdd` — its absence marks the lightweight path), then
branch and scaffold `progress.md` and mark the issue `harness:status:in-progress`
(it flips to `in-review` when the PR opens), implement ([`tdd`](.claude/skills/tdd/SKILL.md)), review (the
Reviewer's full pass), and run the human merge gate before closeout.
L2 skips the spec and its approval gate, but
the branch, PR, and **merge gate are the same as L1** — no path auto-merges.

If the bug carries enough decision weight to deserve a spec, escalate to `/define`
(L1). If it's purely mechanical — nothing a test or reviewer would catch — drop to
`/bypass` (L3). See the task-fit dial (`.claude/agents/fit-assessment.md`).
