---
description: 🍋 Force RESUME mode — pick up an existing harness task from its branch and state.
allowed-tools: Read, Write, Edit, Bash, Task, Skill
---

# /resume

Enter **RESUME** mode and pick up an existing task exactly as specified in
`.claude/agents/orchestrator.md` (§"Dispatch" → RESUME, and the approval gate for a
`spec-ready` pickup). This command only **forces the mode** — the orchestrator file
is the single source for the procedure.

`$ARGUMENTS` is the task `#id` or name to resume. If empty, list the open queue
(`gh issue list -l harness:status:spec-ready`,
`-l harness:status:spec-in-progress` for specs parked mid-authoring — including a UI task
parked at `awaiting design definition` (+ `harness:needs-design`), and
`-l harness:status:pending` for stubs captured by `/spinoff`,
`-l harness:status:in-progress --state all`, `-l harness:status:in-review --state all`
for tasks past review, and `-l harness:status:paused-for-clarification --state all` for
tasks stopped on a discovery the human has not answered yet — these three with
`--state all` and `--json number,title,state,stateReason`, because a merged task PR's
`Closes #<id>` closes the issue while the label stays; of their closed issues keep only
those closed as completed (`stateReason` `COMPLETED`): one closed as not planned was
abandoned on purpose), plus parked closeouts
(`-l harness:status:closeout-pending --state all` — their issue is already **closed** by
the task PR's `Closes #<id>`, so an open-only listing would miss them), and **partition
parents** (`-l harness:partition-plan` — not tasks; one with unticked parts surfaces as
"partition in progress: next part per the plan" — or "waiting on #<id> (Part <j>)" when
the next row is blocked by an in-flight child — and resuming it starts the next eligible
part, or names the blocker, per `.claude/agents/partition.md`), and ask which to pick up.
Annotate every `in-progress`, `in-review` and `paused-for-clarification` row with its
task PR's state, found by branch pattern
(`gh pr list --state all --search "head:harness/<id>-" --json number,state,headRefName,baseRefName,mergedAt`;
the orchestrator's RESUME says how to read several matches): "PR #N open — merge gate"
(`in-review`), "PR #N merged — closeout not run" (`in-progress`, `in-review`), "PR #N
merged while paused" (paused), "PR #N merged into <base> — not landed" (a stacked
partition child), "PR #N closed unmerged — decide", "closed, no PR — decide" (a closed
issue), or, for an open `in-review` one, "no PR found" (an open `in-progress` or paused
row without a PR needs no note). A closed issue whose row has no merged task PR is not
dropped: its annotation is what tells the human it is stuck.

In brief (authority is the orchestrator): an `in-progress`, `in-review` or
`paused-for-clarification` task passes the **task-PR gate first, before any checkout**
(the lookup in the queue above): merged → no task branch to check out, run
[`task-closeout`](.claude/skills/task-closeout/SKILL.md) from its top (a paused one first resolves its discovery on the default
branch, dispatching no change — one it needs becomes a `/spinoff` follow-up); closed
unmerged → offer resume / abandon / leave it; no PR → `in-review`: ask the human for the
PR number, others continue below; open → continue below. Then: for an SDD task the state and spec live
**only on the branch** until merge — `git fetch` and check out `harness/<id>-<slug>`
before reading any state (recover the branch from just `<id>` with
`git branch -r --list "origin/harness/<id>-*"`), then reload
`.claude/state/tasks/<id>/` and continue from `progress.md`. An L2 task (no
`harness:sdd`) has its branch and state the same way once it has left `pending`, with
no spec — check it out the same way, whatever its status. If origin lacks the branch
(L1 or L2), look for a local one; with none, never re-create it on your own — say the
task may live on another machine and ask whether to wait for it or redo the branch step
(authority: the orchestrator's RESUME). A `spec-ready` issue
resumes at the **approval gate** (run it — read the spec cold, never self-approve);
an `in-progress` one resumes at the active subtask — for an L2 task, at
`.claude/agents/triage.md` step 3 (implement), continuing from what the branch holds.
A `paused-for-clarification` task is waiting on the human: check out its branch, then
re-enter [`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md) at its step 2 (mediate) with the open
entry in `discoveries.md` — its `paused_from:` line is the status the task returns to,
its `Subtask context:` the agent to re-invoke. The pause commits and pushes that entry
best-effort; when it is missing here anyway (the push failed, the pause predates that,
or the task runs `Auto-commit: off`, whose pause makes no commit), take the status from the issue's
discovery comment (`Resumes to:`) and the agent from its `Paused agent:` line, and work
from its one-line gist, saying the full entry is not here. Read each line on its own: a
line the comment lacks (an older version posted it) leaves that one fact unknown — ask
the human for it, and never guess `--status`.
A `spec-in-progress` task whose
`progress.md` records `awaiting design definition` is a **UI design parked at "stop for
handoff"** (authority: `.claude/agents/ui-design.md`): re-enter by **resuming the [`grill-ui`](.claude/skills/grill-ui/SKILL.md)
interview yourself** to finish `ui-handoff.md` (the UI Designer then critiques it), then
drop `harness:needs-design` and continue toward spec-ready. When `progress.md` records
`Mode: step-by-step` (or all-at-once under auto-commit OFF), the `## Step log` carries
the step sub-state — resume
exactly there: `awaiting human checkpoint (step N/M)` re-presents that pending
checkpoint (inspect / run / OK / changes / OK+downgrade; in all-at-once under
auto-commit OFF the line carries no `(step N/M)` counter — same
re-entry). Every answer — `changes` too — resolves in the turn that records it,
after the human-delta check (orchestrator §"Checkpoint contract", item 4), through one
call, `.claude/hooks/lib/lemony.sh checkpoint <answer> …` (orchestrator
§"Checkpoint contract", item 5): it makes the commits and, step-by-step, the
`step_completed` emit together (the all-at-once gate omits `--step` and emits
nothing) — never make them by hand or copy them from `git log`. A
`fix-loop iteration K`
line re-enters the per-step implement→review loop at that iteration; an
`awaiting ledger retry (step N/M, retry 1/1)` line — or its full-pass twin
`awaiting ledger retry (full pass, retry 1/1)` — re-runs
`lemony review-ledger validate` on the sidecar on disk (`--anchor` per the
orchestrator: per-step, the `(anchor <oid>)` on the step-log line; full pass, the
fingerprint merge-base — except auto-commit OFF's pre-gate twin, which anchors
at the recorded single-group anchor, = the branch head: auto-commit OFF defers every
commit) —
green re-presents the gate
the pass feeds, red goes to that gate with the verb's lines, the single retry being spent;
either way the awaiting line stays until the human answers that gate, then is replaced
by its outcome (authority: the orchestrator §"Step-by-step implementation"). If the
Mode line carries a `(downgraded to all-at-once at step N)` suffix, the remaining tasks
run all-at-once — resume at the active subtask as usual, not via the step loop (the Step
log is then history, not sub-state).

**Cross-machine pickup of an `in-progress` task**: the branch on origin
carries the last **successful** best-effort WIP push — the Implementer pushes on
signaling done, and step-by-step pushes at each checkpoint-wait. Exception: a task
running **auto-commit OFF** defers every commit and push until a checkpoint OK
— in-flight work and its `progress.md` updates exist only in the implementing
machine's worktree, so from another machine the branch reads as of the last OK'd
group; before the first OK it is **indistinguishable from idle** (the knob record
itself is deferred — the documented price of the mode, orchestrator §"Auto-commit
OFF"). When config pins `implementation.auto_commit: off` on an L1 task (the
`harness:sdd` label; the pin never reaches an L2 task, which always commits as it
goes), or the branch's `progress.md` already carries the `Auto-commit: off` line (some
OK landed), surface the mode instead of concluding the task is idle. A discovery
pause still surfaces cross-machine via its labels and issue comment, though in this
mode the pause makes no commit, so its full `discoveries.md` entry stays machine-local.
If a **local** copy
of the branch is ahead of origin, prefer it (it is the newer state — this is what
makes same-machine resume lossless). From a **different** machine, anything committed
after the last successful push is unreachable and undetectable (origin is
self-consistent, just older): resume from the pushed state and tell the human which
state that is (`progress.md`'s last entry), so a re-run of an already-done review or
checkpoint is a conscious replay, not a silent assumption. Same machine, auto-commit
OFF, mid-implementation (`progress.md` not at `awaiting human checkpoint`): work found
**unstaged** in the worktree is **unverified by construction** — never stage or present
it on sight; the fresh Implementer confirms or redoes it. At an `awaiting` checkpoint,
unstaged work is the human's own delta instead (authority: the orchestrator §"Auto-commit
OFF"). An `in-review` one whose task PR is open resumes at the
**merge gate**: surface the open PR's review comments and run the merge-gate procedure
(route change-requests back to the Implementer, then offer to post threaded replies —
authority is the orchestrator). A `closeout-pending` task has **no task branch to check out** —
its task PR already merged and its state is archived under `_archive/<id>/`: run
[`task-closeout`](.claude/skills/task-closeout/SKILL.md) from its top, which is retry-safe and finds the record PR — if it is
still unmerged, it **re-runs the self-merge executor on it** (`.claude/hooks/lib/merge-pr.sh harness/closeout-<id> --squash --delete-branch` —
the skill's step-5 line verbatim, flags included: a bare invocation is rejected by
`gh pr merge` non-interactively and would re-park forever. The park may have been a
transient pending/red that has since settled; a repeat not-green re-parks), then goes
on to its **finalize** step (step 6) once that PR is merged — the skill owns the
finalize operations
(delete the task branch, close the issue, emit `task_done`, then flip to `done`). A
`pending` stub has **no branch
yet** — nothing to check out: read the captured context (the title is the symptom; the
body may be thin), run the task-fit assessment to choose the level, then enter that
flow. The stub is **reused, not re-created** — at L1 the orchestrator skips issue-creation,
at L2 it passes the stub's number to [`triage-issue`](.claude/skills/triage-issue/SKILL.md), which updates the stub instead — and
the `pending` label is dropped only on commit; for L2 that is the branch step, where the
stub becomes `in-progress` (authority: the orchestrator).
