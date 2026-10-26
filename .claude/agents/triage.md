# L2 lightweight round-trip (TRIAGE) — Orchestrator companion

> Vendor companion to `.claude/agents/orchestrator.md` (the hat). **Read on
> demand, never at boot**: when dispatch lands on TRIAGE, or when a pending
> stub's task-fit assessment lands L2 (including an `architecture-drift` stub
> routed through the L2 machinery). The orchestrator's hard rules — human
> gates, label lifecycle, fresh sub-agent context, spawn prompts by reference —
> apply here unchanged. Caller-side overrides ride in from dispatch: on a
> **pending-stub pickup** the issue already exists — **pass the stub's number to
> [`triage-issue`](.claude/skills/triage-issue/SKILL.md)** (its reuse mode): the skill updates the stub's body with its
> root-cause, fix-plan and `## Risk surfaces` output and keeps the number, never
> opening a second issue. An **architecture-drift stub** is a pending stub too, so the
> same reuse applies AND the **Architect** (running [`update-architecture`](.claude/skills/update-architecture/SKILL.md))
> replaces the Implementer in step 3.

For small bugs that don't earn the full SDD ceremony. They skip the spec and its gate,
but the branch, PR, and merge gate are the same — no path auto-merges:

1. **Triage** — invoke the [`triage-issue`](.claude/skills/triage-issue/SKILL.md) skill: investigate the codebase, find the
   root cause, draft a TDD-based fix plan, declare the change's `## Risk surfaces`,
   and create the issue with `harness:managed`
   (no `harness:sdd` — its absence is what marks the lightweight path), or, on a stub
   pickup, update the stub in reuse mode. Minimize questions. Record the number `<id>`.
2. **Branch + scaffold** — create the task branch `harness/<id>-<slug>` off the default
   branch (if it already exists — an earlier pickup stopped inside this step — check it
   out instead of creating it), then scaffold `.claude/state/tasks/<id>/progress.md` on
   it, commit it, and push the branch **best-effort** (a failed push is a warning, never
   a stop — say so):

   ```bash
   git add .claude/state/tasks/<id>/ && git commit -m "triage(<id>): scaffold"
   git push -u origin harness/<id>-<slug>
   ```

   Nothing touches the default branch until the merge gate. Then add
   `harness:status:in-progress`: from here until review the task is in flight. The label
   is what puts it in `/resume`'s queue; the pushed branch is what lets another machine
   pick it up. On a stub pickup this is the **commit point** — flip
   `harness:status:pending → harness:status:in-progress` here, not earlier, so a triage
   abandoned before this step leaves the stub in the pending queue.

3. **Implement** — invoke the **Implementer** sub-agent with the [`tdd`](.claude/skills/tdd/SKILL.md) skill (spawn by
   reference — the orchestrator's §"Sub-agent invocation"; on an architecture-drift stub the
   **Architect** with [`update-architecture`](.claude/skills/update-architecture/SKILL.md) replaces it, per the preamble). All work
   lives on the branch, and the Implementer commits as it goes: the auto-commit knob and
   its `harness.config.yml` pin belong to the L1 approval gate, which this flow does not
   have.
4. **Review** — flip `harness:status:in-progress → harness:status:in-review`, **open
   the PR** (`gh pr create`, with `Closes #<id>` in the PR body so the provider
   auto-links and closes the issue on merge), and invoke the **Reviewer** sub-agent (fresh
   context) for the full pass — it runs the passes its own table owes, so the prompt
   names no review skill (orchestrator §"Sub-agent invocation"). On rejection, route
   back; on approval, go to the merge gate. The approval is validated by contract, not by
   the review ledger: with no `tasks.md` there are no criteria to enumerate, so there is no
   ledger to validate.
5. **Merge gate** — the same human-explicit gate as L1: never auto-merge. Surface the
   PR and wait. An authorized merge executes through the same checks precondition
   as L1 (orchestrator §"Merge gate" — `.claude/hooks/lib/merge-pr.sh`, never bare
   `gh pr merge`).
6. **Closeout** — run the [`task-closeout`](.claude/skills/task-closeout/SKILL.md) skill (merge confirmed via `gh`), as in the
   orchestrator's §"Closeout".
