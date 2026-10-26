---
name: task-closeout
description: 🍋 Close out a finished task — record it in history.md, archive the task spec + discoveries, activate the Architect for durable capture (ADRs, the architecture map, conventions), and finalize via a dedicated closeout PR. Use when the Orchestrator finalizes an approved+merged task, mentions "closeout", "close the task", or "wrap up the issue".
origin: vendor
vendor_version: '0.11.0'
invoked-by: [orchestrator]
---

# Task Closeout

## Core Principle

Closeout is **archive-on-done through a dedicated PR**. The durable memory of
a finished task — its spec and its resolved discoveries — is **archived live**, not
deleted, so a future agent reads the decisions instead of doing git archaeology. The
genuinely architectural decisions rise further, to ADRs. And the closeout record reaches
the base branch **only through a PR**, never a direct push — the same branch isolation
every other change obeys.

Three moves, in this order:

1. **Activate the Architect** — closeout is its reliable end-of-task checkpoint.
   In cold blood, no resume pressure, it drives durable capture: [`write-adr`](.claude/skills/write-adr/SKILL.md) (HITL offer
   per resolved discovery), [`update-architecture`](.claude/skills/update-architecture/SKILL.md) (automatic, when the map exists), and
   the conventions offer (HITL, once per task). The canon outlives any task folder.
2. **Archive, don't delete** — `git mv` the spec + `discoveries.md` into
   `_archive/<id>/`; drop only `progress.md` (true scratch). The high-value memory stays
   live and grep-able.
3. **Land via a PR** — the `history.md` append, the archival move, and any new ADR ride a
   dedicated `harness/closeout-<id>` PR that self-merges **only on green checks**
   (through `.claude/hooks/lib/merge-pr.sh`). No direct push to the base.

Run this only when the **Reviewer has approved** and the task PR is merged. The merge is a
human decision (the merge gate) — closeout never merges the task; it **confirms** the
merge, then records it.

## Preconditions

- The Reviewer posted an explicit approval (the task passed `in-review`) — or the human
  merged before it did (a `/resume` that finds the task PR merged): the human's merge,
  confirmed below, stands in for it.
- **The task PR is merged — confirmed against GitHub, not the conversation.**
  `gh pr view <pr> --json state,mergedAt,baseRefName` must report `"state": "MERGED"`
  **into the default branch** — or into a stacked partition sibling's branch whose own PR
  then merged into the default branch (it landed through it); merged into a sibling's
  branch that has not landed → stop and say so (`.claude/agents/partition.md`) — regardless of
  how it was merged (GitHub UI, CLI, or the Orchestrator running `gh pr merge` after the
  human authorized it). If it is not `MERGED`, stop — the task stays at `in-review`
  until the human merges.
- **SDD only:** the PRD for this task is `Status: completed` — [`grill-with-docs`](.claude/skills/grill-with-docs/SKILL.md)
  normally sets this when the grill closed; if it's still `in_progress`, flip it now.
  (This is the latest point the PRD can be marked done.) An L2 or architecture-drift
  task has no PRD and no spec: skip this, and every step below that names them.
- **No discovery is left open.** If `discoveries.md` exists, every entry must carry a
  resolved `**Resolution**` block (`Decision` / `Resumed at` filled) and no
  `harness:discovery:*` label may remain on the issue. An unresolved discovery means a
  sub-agent is still paused — run [`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md) before closing out.
- **The `harness:status:closeout-pending` label exists on the remote.** `install` /
  `update` / `repair` create it during label sync; an install that predates this label
  needs one `lemony repair` first, or the park step's label flip will fail.

## Why post-merge (don't archive early)

Archival is **destructive** and must wait until the task PR is merged. Until that merge,
the task can re-enter iteration — a Reviewer rejection, or human review comments at the
gate — and that re-work needs the spec **live** in `tasks/<id>/spec/`. Archiving
pre-merge would pull the spec out from under an in-flight fix. So every step below runs
**after** the merge is confirmed.

## Process

Closeout runs **on the default branch, after the merge** — the task PR brought the
branch (spec + code) onto it. Land there first so the closeout branch forks from the
merged base: `git checkout <default> && git pull`.

**A closeout is retry-safe: re-running this skill from the top is how a half-done one
resumes.** A session can end at any step, and `/resume` only says "run `task-closeout`".
So before step 1, find how far an earlier run got, and every step below skips the
effect it finds already done:

1. **The record PR** — `gh pr view harness/closeout-<id> --json state` (a branch name
   resolves the PR even once the branch is deleted). `MERGED` → go to step 6. `OPEN` →
   check out the branch and go to step 5's executor line. `CLOSED` (closed unmerged —
   someone rejected the record) → stop and ask the human: redo the record (on their
   yes, delete the old branch with `git push origin --delete harness/closeout-<id>` and
   `git branch -D harness/closeout-<id>`, then continue at item 2 — not the top: the
   closed PR still answers to the branch name until a new one exists) or
   finish it by hand; never reopen or recreate it on your own. No PR (the error says
   `no pull requests found`) → continue. Any other error (auth, network) → stop and
   say so: guessing "no PR" would open a second record.
2. **The record branch** — if `harness/closeout-<id>` exists locally
   (`git branch --list harness/closeout-<id>`) or on origin
   (`git ls-remote --heads origin harness/closeout-<id>`), check it out now, before
   step 1 (`git fetch origin harness/closeout-<id>` first; when both exist, bring the
   local one up to origin's with `git pull --ff-only`, and stop and ask if they
   diverged), so the re-run sees what the earlier run already wrote — when the checkout
   refuses because of local changes (a Resolution recorded on the base), `git stash`,
   check out, `git stash pop` (a conflicting pop: stop and ask — the stash is kept).
   Otherwise stay on the base.

### 1. Activate the Architect for durable capture

Closeout is the Architect's **reliable activation point**: in cold blood, after
the merge, with no paused sub-agent pulling toward "just unblock me", it drives the three
durable-capture skills the on-demand triggers otherwise lose. Each one **no-ops cleanly
when its skill isn't installed**, so this step is safe everywhere.

The three differ in **who decides** — and the asymmetry is deliberate:

- **[`write-adr`](.claude/skills/write-adr/SKILL.md) — HITL offer, per resolved discovery.** Walk the **resolved** entries in
  `discoveries.md` and **offer** the ones that settled a real decision (not a trivial
  clarification) as candidate ADRs, then dispatch the **Architect** ([`write-adr`](.claude/skills/write-adr/SKILL.md), fresh
  context) on the ones the human accepts. Offer liberally — closeout does **not** apply
  the ADR criterion itself; the Architect owns the three tests (hard to reverse /
  surprising without context / a real trade-off) and **declines** the ones that fail, so
  a generous offer costs only a "no". If there are no resolved discoveries, or none
  qualify, skip — never pad the canon with reversible or obvious decisions. An ADR is
  **net-new canon**: the human curates what enters, so it stays an offer. An Architect
  that reports a **clash** with a live ADR or convention wrote nothing: run the clash loop
  in `.claude/agents/orchestrator.md` §"Architect (on-demand)" — everything it lands
  rides this same closeout PR.

- **[`update-architecture`](.claude/skills/update-architecture/SKILL.md) — automatic dispatch, no pre-offer.** Only when
  `docs/architecture.md` exists (the skill installs solely then). Dispatch the
  **Architect** ([`update-architecture`](.claude/skills/update-architecture/SKILL.md), fresh context) with the task's **PR number**
  (it runs `gh pr diff <pr>` itself) plus the **path** of the task's `spec/design.md`
  (still live here — archival is
  step 4 below). The Architect reads the change, makes
  the smallest true edit if the system's **shape** moved (referencing any ADR just
  written — `see ADR-NNNN`), or reports **no-op** when nothing architectural changed.
  There is **no human prompt here**: the map must _track reality_, not be curated, and the
  edit is reviewed in the closeout PR diff like any other change. Run this **after**
  [`write-adr`](.claude/skills/write-adr/SKILL.md) so the map can cite the new ADR numbers.

- **Extract or adjust conventions — HITL offer, once per task.** A single reflective
  offer: did this task surface a **convention** the code follows that no rule or
  client skill states yet, or a live one worth adjusting, that **no
  `T6 CONVENTION_CONFLICT` already routed** mid-task? (A conflict blocks a sub-agent
  and is handled in the moment; this catches the _non-blocking_ learning that would
  otherwise be lost.) On the human's "yes", dispatch the **Architect** (fresh context)
  with [`extract-conventions`](.claude/skills/extract-conventions/SKILL.md) to draft new ones — its draft goes through `/import`, whose
  plan the human approves — or [`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) to adjust a live one. Like an
  ADR, a convention is curated canon, so it stays an offer; decline costs only a "no".
  A clash [`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) reports goes through the same clash loop.

Any artifact written — an ADR, the architecture edit, a convention — lands in the
working tree and rides the closeout PR below: `git add` each path the Architect reports
as soon as it reports it, so a closeout cut short and run again still commits it in
step 5. An extracted draft is not one of them: it is gitignored, and
importing it is a change of its own. Give the human its path, finish the closeout, and
leave `/import <draft path>` to them afterwards, on its own branch.

On a re-run (the record branch checked out above), the earlier run's artifacts are
already there: don't re-offer an ADR for a discovery that already has one on the
branch, the map edit re-runs as a no-op, and the conventions offer is not repeated when
a staged or committed convention change, or an extract draft under `.lemony/extract/`
from this closeout, shows the earlier run already made it.

An L2 or architecture-drift task has no `spec/design.md`: hand [`update-architecture`](.claude/skills/update-architecture/SKILL.md)
only the PR number.

### 2. Branch for the record

```bash
git checkout -b harness/closeout-<id>
```

Skip this when the record branch is already checked out (a re-run). All of closeout's
writes go on this branch — nothing touches the base directly.

### 3. Append one line to `history.md`

`.claude/state/history.md` is the append-only, committed changelog — one entry per
finished task. Add the task with whatever metrics you actually have:

```markdown
## #<id> — <topic> (<start-date> → <end-date>)

Cycle: <h> | Iter: <review rounds> | Bugs 14d: <n/a until measured>
```

Record only metrics you can back up. Rich telemetry (tokens, post-merge bugs) is
populated once the telemetry/event machinery is authored in a later phase; until
then, leave those as `n/a` rather than inventing numbers.

Skip the append when `history.md` already has a `## #<id> —` heading: an earlier run
of this closeout wrote it.

### 4. Archive the spec + discoveries; drop the scratch

Move the durable memory into the archive and remove only the ephemeral scratch. The
existence guards keep this **idempotent** — a retried closeout (e.g. crash mid-run) that
already archived skips the move rather than erroring on an existing destination:

```bash
mkdir -p .claude/state/tasks/_archive/<id>
# Move the durables only if not already archived (retry-safe):
if [ -d .claude/state/tasks/<id>/spec ]; then
  git mv .claude/state/tasks/<id>/spec .claude/state/tasks/_archive/<id>/spec
fi
# discoveries.md only exists if the task raised one — move it conditionally:
if [ -f .claude/state/tasks/<id>/discoveries.md ]; then
  # Stage first: a Resolution recorded after the merge must ride the move.
  git add .claude/state/tasks/<id>/discoveries.md
  git mv .claude/state/tasks/<id>/discoveries.md .claude/state/tasks/_archive/<id>/discoveries.md
fi
# Drop everything that remains under tasks/<id>/ — progress.md plus any straggler an
# Implementer left. --ignore-unmatch: a re-run finds nothing tracked left there.
git rm -r -q --ignore-unmatch .claude/state/tasks/<id>/
```

An L2 or architecture-drift task has no `spec/`: the guard skips it, and only
`discoveries.md` (if the task raised one) is archived. When an earlier run already
removed `tasks/<id>/`, `--ignore-unmatch` makes the `git rm` a no-op.

`spec/` and `discoveries.md` survive **live** under `_archive/<id>/` (grep-able), plus in
git history and the GitHub issue. `progress.md` (the pause-point bitácora) and any other
working scratch are gone. A UI task's **`ui-handoff.md`** is a sibling **inside**
`spec/`, so the single `git mv` of `spec/` archives it with the rest — no special
handling.

### 5. Open the closeout PR and self-merge on green

Commit the record, push the branch, open a PR, and self-merge it **through the
checks-precondition executor** — never a bare `gh pr merge`. There is no standing human
authorization on this path, so the precondition stands alone: **the executor merges
only on green; every other outcome takes one of the exits below** (some end in a
human's informed decision — what never happens is an autonomous merge on not-green).
The executor verifies the check status the platform reports for
the PR, waiting — bounded (`merge.checks_timeout_secs`, default ~10 min) — for pending
checks:

```bash
git commit -m "closeout(<id>): archive task state, record in history.md"
git push -u origin harness/closeout-<id>
gh pr create --base <default> --head harness/closeout-<id> \
  --title "closeout(<id>): <topic>" --body "Closeout record for #<id>."
.claude/hooks/lib/merge-pr.sh harness/closeout-<id> --squash --delete-branch
```

On a re-run, skip what is already done: no commit when an earlier run already committed
the record and this one wrote nothing new, and no `gh pr create` when the PR exists — the
preamble's `OPEN` jumps straight to the `merge-pr.sh` line. `git push` is safe to repeat.

(If the human recorded a standing merge answer at this task's merge gate — a
`merge.allow_no_checks: true` line sitting uncommitted in `harness.config.yml` —
stage it into the record commit above: the answer rides the closeout PR to the base.)

The closeout PR **must not** carry `Closes #<id>` — the task PR already auto-closed the
issue on merge; closeout only flips the label and finalizes.

Act on the executor's exit code:

- **0 — merged.** Continue to step 6 (finalize).
- **10 — checks red.** Red does **not** automatically mean the base is broken — look at
  what failed (`gh run view` / the check's output), then take one of three exits:
  1. **Failure in the closeout's own files** (format/lint on the moved docs): fixable
     by you alone — run the formatter, commit, push, re-run the executor; green ⇒
     self-merge normally. No human interruption; fixing format on your own docs-only PR
     is harmless and autonomous.
  2. **Failure in the base** (main was already broken): **park** and surface with the
     diagnosis — the human's informed merge-on-red decision is legitimate precisely
     here, since the red isn't this PR's (on their explicit yes, re-run with
     `--force`). Free side effect: every closeout is a broken-main detector.
  3. **Can't tell:** **park** and surface what you saw — in doubt, the human.

  The uniform rule stands: **never merge on red alone** — no "it's only docs"
  exception (automatic exceptions are how the bug comes back).

- **20 — no checks reported (after the grace window).** Never merge alone, whatever the
  cause — don't auto-classify (no CI, CI dead, path filters all look identical). The
  once-per-repo memory is the **standing answer only**: if `merge.allow_no_checks: true`
  is recorded (or sits uncommitted on this branch, staged per step 5), the executor
  applies it itself — you won't see exit 20. A **one-shot** yes given at an earlier
  merge (including this task's merge gate) authorized **that merge only** and does
  **not** carry over — never re-apply it here on your own. Seeing exit 20 means no
  standing answer exists, so ask: "I saw no checks on the closeout PR — merge?". A
  standing answer ("this repo has no CI — merge without checks") is recorded as
  `merge.allow_no_checks: true` in `harness.config.yml` — add the line on this very
  closeout branch, push, and re-run the executor (it reads the working tree, and the
  answer lands on the base with the record). A one-shot yes ⇒ re-run with `--force`.
  No human available ⇒ **park**.
- **30 — checks still pending past the bound.** **No merge**: **park**. The closeout is
  docs-only archival — leaving it pending blocks nothing already merged.
- **1 (or any other non-zero) — no verdict.** Read the executor's stderr: either the
  check status could not be read (`gh`/auth/network — the precondition is
  unverifiable), or the merge attempt itself was rejected (branch protection requires
  human approval, a conflict). Both ⇒ **park**, surfacing that stderr — a
  protection-parked record PR is merged by the human by hand.

**Park:** flip the issue to `harness:status:closeout-pending` —
`gh issue edit <id> --remove-label harness:status:in-review --remove-label harness:status:in-progress --add-label harness:status:closeout-pending`
— tell the human the closeout PR is open, why it did not merge (the executor's output — failing checks, no checks,
pending past the bound, or protection), and stop. The task issue is **already closed** (the
task PR's `Closes #<id>` fired on its merge), so `/resume` finds the parked closeout only
by listing closed issues too (`--state all`) — a default open-only queue would miss it. A
later `/resume` runs this skill again from the top: its preamble re-runs the executor on the
still-open PR, or goes to step 6 once it is merged. (Authority for the RESUME entry: the
Orchestrator.)

### 6. Finalize (once the closeout PR is merged)

Reached from step 5, or from the preamble on a re-run. When the preamble found the record
PR **still open**, it re-ran the executor on it first (step 5's `merge-pr.sh` line,
verbatim): a park on pending or red checks is transient
and may have settled green — a repeat not-green outcome just re-parks. Then confirm the
closeout PR merged (`gh pr view <pr> --json state,mergedAt` → `MERGED`; on a
`/resume`, pass the deterministic branch `harness/closeout-<id>` as `<pr>` — the
merge-confirm accepts a branch name in place of a PR number), land the merged base
(`git checkout <default> && git pull`), then:

```bash
git push origin --delete harness/<id>-<slug>   # delete the task branch (skip if already gone)
gh issue close <id>                            # belt-and-suspenders if the merge didn't auto-close it
```

Then **emit `task_done`, and only after it flip the issue to `harness:status:done`** —
both happen here, in finalize, exactly once (the parked → `/resume` path also lands here,
so it is the single emit point for either path). The order is what makes a re-run safe: a
session cut between the two leaves the issue at its old status, so `/resume` lists it and
re-runs this skill — the other order would leave it `done`, listed nowhere, its
`task_done` lost. So first check this checkout's log, and skip the emit when it already
holds one for this task (an earlier run emitted, then stopped before the flip):

```bash
grep '"task_id":"<id>"' .claude/state/events.jsonl | grep -q '"type":"task_done"'
```

Exit 0 → already emitted: skip the emit. Otherwise emit — you compute the envelope
(cycle time, review rejections, level) as the Orchestrator running this skill; the fields
and the `emit` command line are in `.claude/agents/orchestrator.md` §"Closeout". `events.jsonl` is
local-only/gitignored, so the emit never dirties the base. An emit that still fails
after one correction (a refused field, a missing `user.email`): warn with its error and
go on — a lost event must not leave the issue un-flipped. For a partition part, tick the
parent row (next) before the flip too, so a cut there still re-lists the task.

**If the task is a part of a partitioned feature** — its issue body (read it with
`gh issue view <id> --json body`; the issue is closed by now) carries a
`Part <k> of #<parent>` trace line — update the parent **partition-plan** issue here, in
the same finalize and before the `done` flip below. Tick your row with
`lemony issue-body set-row`, never by retyping the parent body — every other row is a
sibling's, and a retyped body can drop one. One Bash call, chained with `&&`:

```bash
p=<parent>; t=$(mktemp -d) &&
gh issue view "$p" --json body --template '{{.body}}' > "$t/old.md" &&
.claude/hooks/lib/lemony.sh issue-body set-row --part=<k> --merged=<id> < "$t/old.md" > "$t/new.md" &&
gh issue edit "$p" --body-file "$t/new.md" &&
rm -rf "$t" && echo "issue-body: #$p written"
```

It sets your row to `- [x] Part <k> — <slice> → #<id> merged` and leaves every other line
as it was (CRLF too); without the closing `issue-body: #<parent> written` line, nothing
was written. Then re-read the parent (`gh issue view <parent> --json body`) to
confirm the tick is present — if another row moved underneath you (a sibling closing
out elsewhere), redo it **once** on the fresh body; still absent, or the verb refuses
(no row for your part, a row naming another child) → leave the tick to the human and
say so. Idempotent on a retried finalize: an already-ticked row comes back as it was,
and the all-ticked check still runs. The edit mechanics are
the "Editing the plan and child bodies" section of `.claude/agents/partition.md`. When the tick
leaves **every** row ticked (merged or dropped), close the parent with a summary comment
(`gh issue close <parent> --comment "<what shipped, part by part>"`) — mechanical, no
human prompt: each part's merge already passed the human gate; a parent the human already
closed takes the tick and the close is a no-op. A parent with unticked rows stays open;
`/resume` surfaces its next part. The contract is the Orchestrator's companion
`.claude/agents/partition.md`.

Then flip:
`gh issue edit <id> --remove-label harness:status:in-review --remove-label harness:status:in-progress --remove-label harness:status:closeout-pending --add-label harness:status:done`
(`in-progress` too: a human may merge during rework; removing a label the issue lacks is a
no-op; if the command errors, re-read the labels and redo the flip — gh applies the add
and the removes separately).

### 7. Report

Return a one-line summary: the task id, the `history.md` entry, the archive path
(`_archive/<id>/`), any ADR raised, confirmation that the issue is closed (or that
closeout is parked at `closeout-pending` awaiting the record PR's merge), and — for a
partition part — that the parent row was ticked (and the parent closed, on the last
part).

## Scope note

In this build, closeout records to `history.md`, archives the spec + discoveries, raises
ADRs, finalizes via the closeout PR, and emits `task_done` at finalize. Session/metrics
accounting beyond `task_done` is not wired — closeout is the place it will attach.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by the task-closeout skill. I applied
   [approach] because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case.
