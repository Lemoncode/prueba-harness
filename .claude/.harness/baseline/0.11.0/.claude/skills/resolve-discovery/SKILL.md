---
name: resolve-discovery
description: 🍋 Mediate a raised discovery with the human and resume the paused sub-agent. Use when the Orchestrator receives a "Discovery D00x raised" summary — it pauses the task, arbitrates the T1–T6 question with the human, routes the artifact update to its owner, records the resolution, and re-invokes the paused sub-agent with the decision.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [orchestrator]
---

# Resolve Discovery

## Core Principle

This is the **resolving** half of the interrupt-on-discovery protocol; the sub-agent
side is [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md). The Orchestrator is the only one who talks to the human and
the only one who moves labels, so it owns mediation end to end: pause the task,
arbitrate, route the fix to whoever owns the artifact, record the decision, and resume
the sub-agent that stopped. The discovery is not closed until the paused sub-agent has
been re-invoked with the decision.

You run this when a sub-agent returns a summary of the shape
`Discovery D001 (T2/UNSPECIFIED_DECISION) raised — see tasks/<id>/discoveries.md`.

## Process

### 1. Pause the task

The sub-agent already wrote the entry and stopped. Record where it stopped and flip
state:

1. In the discovery's section in `.claude/state/tasks/<id>/discoveries.md`, add a
   `paused_from:` line capturing the status the task is leaving (`spec-in-progress`,
   `in-progress`, or `in-review`) — this is the state you'll resume to. You write this,
   not the sub-agent.
2. Reflect the pause onto the GitHub issue with the `discovery` CLI verb. In one
   fail-loud call it flips the status label (mutually exclusive)
   `harness:status:<current> → harness:status:paused-for-clarification`, adds the
   discovery flag `harness:discovery:T<n>` (presence-based, multiple allowed), and posts
   a comment with the entry so the pause is visible on GitHub, not just in local state:

   ```bash
   .claude/hooks/lib/lemony.sh discovery pause \
     --task-id=<id> --tier=T<n> --status=<current> \
     --agent="<the agent + subtask from the entry's Subtask context>" \
     --note="<one-line gist of the question>"
   ```

   The comment records `--status` as the status to resume to and `--agent` (one line,
   like `--note`) as who stopped: when the entry did not reach another machine (item 3's
   push failed, or was skipped), the comment is all a resume there has.

   Keep `--note` to a single line — the full `Plan says / Reality / Question` entry
   lives in `discoveries.md`; the comment only needs a pointer-gist (omit `--note`
   entirely and it links to the file). The label flip is **load-bearing**: a non-zero
   exit means it did not land — surface it and retry, do **not** proceed as if the task
   were paused. The comment is best-effort; if only it fails you'll see a `Warning:` but
   the pause still stands. The Orchestrator creates the issue at the start of
   `spec-in-progress`, before any sub-agent runs, so the issue always exists by the time
   a discovery is raised — even a spec-time T2 during [`prd-to-spec`](.claude/skills/prd-to-spec/SKILL.md).

3. Let the entry travel with the branch: commit **only** `discoveries.md` and push,
   best-effort — a failure warns, never blocks (the pause already stands):

   ```bash
   git add .claude/state/tasks/<id>/discoveries.md
   git commit -m "discovery(<id>): pause on D<nnn>" -- .claude/state/tasks/<id>/discoveries.md \
     && git reset -q -- .claude/state/tasks/<id>/discoveries.md
   git push -u origin HEAD   # best-effort; a spec-time pause is the branch's first push
   ```

   The pathspec keeps any other staged or unstaged work out of the commit; the reset
   re-syncs the index, which a pre-commit hook that rewrites files leaves stale after a
   pathspec commit (`git status` would show the file as `MM`). Skip this
   step when `progress.md` records `Auto-commit: off`: that mode promises the human zero
   commits until their OK, so the entry stays local and the comment carries the facts.

### 2. Mediate with the human

Read the entry. Present it faithfully — the `Plan says` / `Reality` / `Proposed` /
`Question` — and ask the human the single question it poses. Add your own read if it
helps, but **do not decide for them**: a discovery exists precisely because the choice
has consequences worth a human's call. If the human's answer raises a _new_ fork, that
is a second discovery — append it, don't fold it in.

### 3. Route the artifact update to its owner

The agent that **created** an artifact is the one that updates it. Map the decision to
the artifact it changes, then invoke that owner (fresh context, Task tool) with the
decision **stated in full** — at this moment it exists nowhere on disk; the entry's
`**Resolution**` block is only written at step 4 — plus the `discoveries.md` entry
**by path** for the surrounding context (it reads the entry itself):

| Artifact changed by the decision                                                                                                                                      | Owner to invoke                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/requirements.md`, `spec/design.md`, `spec/tasks.md`                                                                                                             | **Spec Author** — except a task's checkbox: `- [ ]` → `- [x]` is the Implementer's done-mark at green (the Orchestrator's on a checkpoint `ok`), never a spec edit                                                                                                                                                                                                  |
| Implementation code, `progress.md`, `notes.md`                                                                                                                        | **Implementer** (often just the resumed sub-agent)                                                                                                                                                                                                                                                                                                                  |
| A child issue's trace lines, a triage issue's fix plan, the parent partition-plan issue                                                                               | **Orchestrator** (you) — trace lines and plan rows through `lemony issue-body`, never retyped: the "Editing the plan and child bodies" section of `.claude/agents/partition.md` (an oversize discovery answered "partition"); a triage fix plan is re-authored, its trace lines kept by the recipe of [`triage-issue`](.claude/skills/triage-issue/SKILL.md) step 7 |
| `docs/adr/NNNN-<slug>.md`, `docs/architecture.md`, a convention (`.claude/rules/`, a client skill, `docs/reference/`, or a playbook the project has not migrated yet) | **Architect** (on-demand) — [`write-adr`](.claude/skills/write-adr/SKILL.md) to record the decision, [`update-architecture`](.claude/skills/update-architecture/SKILL.md) to keep the map true, [`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) for a `T6 CONVENTION_CONFLICT`                                                                   |

Not every resolution needs an artifact update first. If the decision is simply "do X"
with no change to the contract, skip straight to recording it and resuming. If it
changes the contract (a spec requirement, an ADR), the owner updates the artifact
**before** the paused sub-agent resumes, so it resumes against the corrected source.
An Architect that reports a **clash** with a live ADR or convention wrote nothing: run
the clash loop in `.claude/agents/orchestrator.md` §"Architect (on-demand)" before you
resume.

### 4. Record the resolution

Append a `**Resolution**` block under the discovery's existing header (append-only —
do not edit the raise fields). When the entry is not on this machine (the pause's push
failed or was skipped, and the resume took its facts from the issue comment), create the
entry first so the decision still reaches `_archive/`, with exactly what the comment
gives — never invent the category or the raise date:

```markdown
## D<nnn> — T<n> (rebuilt) · raised <the comment's date>

<the comment's one-line gist>

Full entry not on this machine — rebuilt from the issue comment.
```

`D<nnn>` is the next free id in this file, `T<n>` the tier the comment names
(`Discovery T<n> raised`). Then append the block below under the entry — the original
one, or the one you just rebuilt:

```markdown
**Resolution** (Orchestrator)

- **Decision:** <the human's call, stated plainly>
- **Artifact updated:** <file + owner who changed it, or "none — decision only">
- **Resumed at:** <YYYY-MM-DD> — <agent> re-invoked from `paused_from: <state>`
```

When `/resume` found the task PR already merged ("merged while paused"), nothing is
re-invoked and nothing is dispatched in §3: write
`Artifact updated: none — PR merged while paused; follow-up #<n>` (or `none` when the
decision needs no change) and `Resumed at: <YYYY-MM-DD> — none, PR merged while paused`
(authority: the Orchestrator's RESUME).

If the original entry reaches this file after you rebuilt it (the pausing machine
pushes it late), it arrives as a merge conflict in `discoveries.md` — both entries
append at the end. Resolve it with
`.claude/hooks/lib/lemony.sh discovery merge-rebuilt --task-id=<id>`, never by hand: it
keeps the original, moves the Resolution under it byte for byte — the human's decision
must reach `_archive/` exactly as recorded — and drops the rebuilt one; then `git add`
the file and continue the merge or rebase. If it refuses (a conflict of any other
shape), don't hand-merge the entries: stop and ask the human.

### 5. Resume and clear the flag

1. Reflect the resume onto the issue with the same `discovery` CLI verb — it removes
   the `harness:discovery:T<n>` flag and flips the status back to `paused_from`
   (`in-progress`, `in-review`, or `spec-in-progress`):

   ```bash
   .claude/hooks/lib/lemony.sh discovery resume \
     --task-id=<id> --tier=T<n> --status=<paused_from>
   ```

   Same fail-loud contract: a non-zero exit means the flag/status did not flip back.

2. Re-invoke the paused sub-agent (fresh context) with: the issue, the task-state
   paths, a one-line gist of the decision (the full `**Resolution**` block now
   lives in the `discoveries.md` entry — reference it), and the updated artifact's
   **path**. It reads the files itself and picks up from where it stopped.

## Closeout invariant

At [`task-closeout`](.claude/skills/task-closeout/SKILL.md), **no `discoveries.md` entry may lack a `Resolution` block** with
`Decision` / `Resumed at` filled, and **no `harness:discovery:*` label may remain** on
the issue. An unresolved discovery means a sub-agent is still paused — the task is not
done. If you find one at closeout, resolve it first.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by the resolve-discovery skill. I applied
   [approach] because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case.
