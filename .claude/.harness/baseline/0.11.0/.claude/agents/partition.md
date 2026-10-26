# Partition — oversized features into independently mergeable parts — Orchestrator companion

> Vendor companion to `.claude/agents/orchestrator.md` (the hat). **Read on
> demand, never at boot**: when a grill closes a PRD that looks like it bundles
> separable wants (the define's closing question), when RESUME or ORIENT lands on
> an issue carrying `harness:partition-plan`, or when a sub-agent raises an
> oversize discovery.

The task-fit dial already handles the **floor** — a task too small for the ceremony
is nudged toward `/triage` or `/bypass`. This companion is the **ceiling**: a
thorough define can produce one enormous task that, however well its groups are
cut inside, lands on **one branch and one PR**. When the work splits into several
**independently mergeable** units, the define should produce several issues —
each with its own branch, PR, merge gate, and revert — instead of one.

## The boundary: an issue is a merge unit

- A **group** (a `tasks.md` step header) is review/checkpoint cadence **inside** one
  merge unit: its tasks share a branch, everything lands in one PR, one revert takes
  it all.
- An **issue** is an **independent merge unit**: its own branch from its base, its
  own PR, merge gate, CI, and revert. Part 1 can be in the default branch while
  Part 2 is being built.
- **Promotion rule** — a group cut promotes to an issue cut **iff both sides are
  independently mergeable**: each side leaves the default branch green and shippable
  without the other (or with only earlier chain links merged). A cut that cannot
  produce independently mergeable units is **not a partition**; forcing it buys
  stacked-PR pain with no benefit.
- **Size is the symptom that triggers looking; mergeability is the criterion that
  decides.** A genuinely inseparable monolith is not partitioned — it is accepted as
  one task, or the feature is renegotiated with the human (an honest define outcome).
- **The partition is a design decision, always proposed to the human**, who
  approves, amends, rejects — or proposes different cuts. Never partition silently.

Partition is an **L1** affair: it rides the PRD → task transition of the full-SDD
round-trip. A triage (L2) task is small by construction and is never partitioned.

## When to look — soft heuristics, no threshold

Judgment, with named cues and **no binding number** (a mechanical trigger would
measure something other than what matters):

- the PRD bundles **separable wants** — capabilities a user could receive one
  without the other;
- the natural `tasks.md` grouping would exceed **~4–5 groups**;
- the grill closed decisions that **don't touch each other** — distinct seams, distinct
  files, distinct risks.

The human gate absorbs the imprecision: an over-proposal costs one "no, it goes
together"; an under-proposal is visible at the spec gate (a huge `tasks.md`), where
the human can ask. The residual failure — never proposed, never asked — is today's
behaviour; nothing gets worse.

## The closing question of the define

After the PRD closes and **before opening the task** (the Orchestrator's §"L1
full-SDD round-trip", between the grill and opening the task):

1. **Look.** Weigh the cues above against the PRD's closed decisions — that is where
   the big seams show. No cue fires → continue the round-trip as today, silently.
   There is no question to ask when nothing looks separable.
2. **Propose, at a glance.** When a cut looks real, build the proposal so it can be
   approved without re-reading the PRD: the slices, what each merges independently
   of, what each cut buys, and the **dependency shape** —
   - **siblings** — each part branches from the default branch, any order;
   - **chain** — part k+1 assumes part k merged;
   - **DAG** — a mix; name the edges.

   Present it as a compact table (the parent body's `## Plan` below is the shape) and
   ask **one** question: _approve this cut, amend it, reject it (one task as today),
   or propose different cuts?_ This is the closing question of the define
   conversation — one more question inside an existing one, not a new gate.

3. **Act on the answer.** Reject → open the single task as today. Approve (or an
   amended cut the human has OK'd) → create the **parent partition-plan issue**
   below, then open **Part 1** as a normal task in this same session (the child
   procedure below) and continue the round-trip from there — Part 1 is the task the
   define hands off.

## The parent partition-plan issue

One issue per partitioned feature: the feature's cover sheet and its at-a-glance
state. Create it with `gh issue create` — title `Partition plan — <feature>`, labels
`harness:managed` + **`harness:partition-plan`**, and **no** `harness:status:*`, no
`harness:sdd`: it is **not a task**. It never gets a branch, a spec, `progress.md`,
or an implementation; the label is the mechanical marker that keeps the task-fit
assessment and RESUME from ever treating it as implementable. Its body:

```markdown
# Partition plan — <feature>

PRD: `docs/prds/<topic>-<date>.md`

## Plan (approved <YYYY-MM-DD>)

| Part | Slice                  | Merges independently of | Depends on     | What the cut buys |
| ---- | ---------------------- | ----------------------- | -------------- | ----------------- |
| 1    | <what this part ships> | Parts 2, 3              | —              | <the benefit>     |
| 2    | <what this part ships> | Part 3                  | Part 1 (chain) | <the benefit>     |

Dependency shape: <siblings | chain | DAG — the edges are the `Depends on` column>.

## Status

- [ ] Part 1 — <slice> (not started)
- [ ] Part 2 — <slice> (not started)
```

**Precondition**: the `harness:partition-plan` label must exist on the remote —
`install`/`update`/`repair` create it during label sync; an install that predates it
needs one `lemony repair` first (a raw `gh issue create --label` has no self-heal: `gh`
fails clean on "label not found", nothing half-created).

Each `## Status` row moves through
these states: `- [ ] Part <k> — <slice> (not started)` → `- [ ] Part <k> — <slice> → #<id>
<status at opening>` when the part is opened → `- [x] Part <k> — <slice> → #<id> merged`
at the part's closeout. A part the human drops (an amendment, or partial abandonment)
becomes `- [x] Part <k> — <slice> — dropped <YYYY-MM-DD> (<why>)` — **ticked, never
deleted**, so the close rule below still fires and the plan stays readable as history (a
drop is recorded in the row alone). Amendments — changes to the cut itself — append to
`## Plan` as `Amended <YYYY-MM-DD>: <what changed and why>`; never silently rewritten. **The rows are a cache, not the truth**: the middle state is the
status at opening and is refreshed only at closeout, so before a decision that depends
on a part's state (sequential vs stacked, which part is next) confirm it against GitHub —
the child's issue state and its PR (`gh pr view <pr> --json state,mergedAt`).

### Editing the plan and child bodies — mechanically

**Every edit goes through `lemony issue-body`, never through your Read/Write path.** A
plan body is mostly rows you do not own, and a body retyped to change one line can drop
or alter the rest without a trace. The verb reads the body on stdin and prints the new
one; it never calls GitHub. An edit is three steps:

1. `mkdir -p .lemony/tmp && mktemp -d .lemony/tmp/issue-body.XXXXXX` — note
   the directory it prints (`<dir>` below; inside the repo and gitignored).
2. Only for an action that takes prose — a slice, a drop reason, an amendment: write it,
   one line, with your **Write** tool to the file its action names in the table below
   (`<dir>/slice.md`, `<dir>/why.md`, `<dir>/text.md`). Never on the command line: a
   backtick or a `$` in it is run or expanded by the shell before the verb sees it.
3. Fetch, transform and write as **one** Bash call, chained with `&&` so a refusal stops
   it before the write (never pipe the verb's output straight into `gh issue edit` — a
   failure mid-pipe writes an empty body):

```bash
p=<parent>; t=<dir> &&
gh issue view "$p" --json body --template '{{.body}}' > "$t/old.md" &&
.claude/hooks/lib/lemony.sh issue-body set-row --part=<k> --merged=<id> < "$t/old.md" > "$t/new.md" &&
gh issue edit "$p" --body-file "$t/new.md" &&
rm -rf "$t" && echo "issue-body: #$p written"
```

**Done means the last line printed `issue-body: #<parent> written`**; without it nothing
was written, whatever the exit code says.

| Edit                                  | `issue-body` action                                                                                                                           |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Open a part (the status at opening)   | `set-row --part=<k> --open=<id> --status=<status>`, plus `--stacked-on=<k-id>` on a stacked start                                             |
| A part merged (its closeout)          | `set-row --part=<k> --merged=<id>`                                                                                                            |
| A part dropped                        | `set-row --part=<k> --dropped=<YYYY-MM-DD> --why-file="$t/why.md"`                                                                            |
| An amendment                          | `amend --date=<YYYY-MM-DD> --text-file="$t/text.md"` (what changed and why); `add-row --part=<k> --slice-file="$t/slice.md"` per part it adds |
| A child's trace lines (its own body)  | `add-trace --part=<k> --parent=<parent> --slice-file="$t/slice.md"`, plus `--depends-on=<sibling>` (and `--stacked`)                          |
| The sibling a child stacked on merged | `set-depends --on=<sibling>` on the child's body                                                                                              |

Each action keeps every other byte of the body (CRLF included) and is idempotent — a
retried edit changes nothing. It refuses, with exit 1 and nothing
written, a body it cannot place the edit in — for example no `## Status` (or two), no
row or two rows for the part, a row that names another child, a merged part dropped or
reopened, a dropped part revived, a child that already names another part, or a trace
line it cannot place. A refusal is not yours to work around by hand: stop and ask the human. After
the write, re-read the parent (`gh issue view <parent> --json body`) and confirm your
row — if another row moved underneath you (two siblings closing out on two machines),
redo the edit **once** on the fresh body; still absent → stop and ask. **The one
exception** is an amendment that reshapes rows beyond these (a renamed slice,
renumbered parts): no action makes it, because it is the human's change, not a
mechanical one. Write the whole new plan body to `<dir>/new.md` with your Write tool
(after fetching `old.md` as in step 3), show the human `diff "$t/old.md" "$t/new.md"`,
and only on their OK write it with `gh issue edit "$p" --body-file "$t/new.md"` — then
re-read and check that every row you did not mean to change is still there.

## Children: normal tasks, opened at their turn

A part is opened **when its turn comes**, not at approval — mirroring the lazy spec:
a row that is never opened is a cheap exit (dropping Part 3 after shipping 1–2
costs nothing unpaid). Opening a part is the round-trip's "open the task" step
**exactly as today** — `gh issue create` with the skeleton body, labels
`harness:managed` + `harness:sdd` + `harness:status:spec-in-progress`, the branch
`harness/<id>-<slug>` — plus **trace lines at the top of the skeleton body**, which
the Spec Author's [`spec-to-issue`](.claude/skills/spec-to-issue/SKILL.md) preserves when it replaces the skeleton:

```markdown
Part <k> of #<parent> — <slice>
Depends on #<sibling> (merged | stacked — assumes it lands as-is)
```

(A root part — Part 1, or a sibling with no dependency — carries only the first line.)
Don't type them: `issue-body add-trace` writes them in the exact form every reader
matches. Make a `<dir>` and write the part's slice to `<dir>/slice.md` with your Write
tool (steps 1–2 of §Editing the plan and child bodies), then build the skeleton and
create the issue from the file:

```bash
t=<dir> &&
printf '🚧 Spec in progress — the Spec Author will fill this in.\n' |
.claude/hooks/lib/lemony.sh issue-body add-trace --part=<k> --parent=<parent> --slice-file="$t/slice.md" > "$t/skeleton.md" &&
gh issue create --title "<title>" --label harness:managed --label harness:sdd --label harness:status:spec-in-progress --body-file "$t/skeleton.md" &&
rm -rf "$t"
```

Done means it printed the new issue's URL — its number is the child's `<id>`.
Add `--depends-on=<sibling>` for a part that depends on one, and `--stacked` on a
stacked start.
Then update the parent row to `→ #<id> spec-in-progress` (`set-row --open`; see §Editing the plan and child bodies). From here the child's
lifecycle — `harness:status:*` labels, spec gate, implementation, review, merge
gate, closeout — is **unchanged**.

**The spec is authored lazily, at the part's turn**, from the PRD (the shared truth)
plus the part's **effective base** — the default branch, or, when stacked, the
previous part's head. Hand the Spec Author, by reference: the PRD path, the parent
issue, the part's row (its slice), and the effective base. The spec covers **that
slice only**; PRD decisions outside it are constraints, not scope. No spec exists
for a part before its turn, so an earlier part's landing can never invalidate one.

## Starting the next part: re-validate the cut

At each part's start, **before** opening its issue, re-read the parent and check the cut **against the current base** (cheap): do the remaining
slices still merge independently? Did an earlier part absorb or obsolete a later
slice? Did a review move the seam? The cut holds → open the part. It doesn't →
present the amendment to the human — the plan is theirs, changing it needs their
OK — and only then edit the parent (`amend`, and `set-row`/`add-row` for the `## Status` rows). What
can be invalidated is the **plan**; the per-part specs don't exist yet.

## Chain start modes — part k+1 while part k is unmerged

When the next part's dependency k is at **`in-review`** (its PR open — e.g. waiting on
another human's merge), the human chooses how to start — ask, don't assume. An earlier k
(`spec-in-progress`, `in-progress`) has nothing to stack on: there is nothing to start;
offer to resume it (`/resume #<k-id>`) in this session. A k already merged
(closeout parked or not — confirm on GitHub) makes k+1 an ordinary sequential part.

- **Sequential post-merge** (the safe default): part k+1 starts when part k is in the
  default branch. Nothing special.
- **Stacked start** (an explicit human choice, with **the assumption named at choice
  time**: stacking bets that part k lands substantially as-is — if k's review forces
  big changes, k+1 is built on sand; the developer takes that bet informed):
  - branch from **k's head**:
    `git fetch && git checkout -b harness/<id>-<slug> origin/harness/<k-id>-<k-slug>`;
  - the lazy spec is authored against the effective base = PRD + k's head;
  - at the review step, while k is still unmerged, the PR targets **k's branch as base**
    — `gh pr create --base harness/<k-id>-<k-slug>` — and the Reviewer is handed **that
    base** for its stale-approve record (the record's base is the PR's base **at review
    time**; a later base change is not by itself a content change — the landing move
    below); if k
    has merged by then, do the landing move below first and open the PR against the
    default branch as usual (`gh pr create --base` on a deleted branch fails);
  - updates from k flow by **merging in, never rebasing** — a rebase needs a force-push on
    a task branch (human-gated by house rules); merge is uglier history but safe. While k
    is unmerged the source is `origin/harness/<k-id>-<k-slug>`. The merge-in is **your**
    move at a checkpoint boundary (or the Implementer's on re-invoke, named in the spawn
    prompt), never inside a staging save-point; under auto-commit OFF it goes right
    after a checkpoint OK commit;
  - record it in the child's trace line (`stacked — assumes it lands as-is`) and the
    parent row (`→ #<id> spec-in-progress (stacked on #<k-id>)` — the status at opening,
    as every row).

  **The landing move — once k is merged (confirmed on GitHub, never inferred from the PR
  base), at the next boundary the merge-in rule above allows:** (1) if k+1's PR still
  targets `harness/<k-id>-…`, **retarget it
  yourself** — `gh pr edit <pr> --base <default>` (the platform's automatic retarget
  fires only when k's branch is deleted, whenever that happens — at k's closeout finalize,
  or at once if the human merged with auto-delete; do not depend on it either way); (2)
  `git fetch && git merge origin/<default>` into k+1 and push — the executor squashes, so
  k's commits are not ancestors of the default branch and without this merge-in k+1's
  merge-base is the old fork point and the stale-approve guard sees k's content as
  unreviewed; k's squashed changes reconcile as identical hunks; (3) update the child's
  trace line to `Depends on #<k-id> (merged)` (`issue-body set-depends --on=<k-id>`). Do this **before** the (re-)review whenever
  k has already merged, so review and gate share a base. The merge-in is an
  **update-branch**: a standing APPROVE stays valid unless the PR's own diff against the
  new base changed (a hand-resolved conflict touched k+1's hunks) — then route to
  re-review; otherwise run the executor and let its stale-approve guard arbitrate.

  **Merge-gate invariant: a part reaches its merge gate only when its PR base is the
  default branch.** Before surfacing the gate of a stacked child — live, or on a
  `/resume` of an `in-review` one — check `gh pr view <pr> --json baseRefName`. Base still
  `harness/<k-id>-…` and k unmerged → k+1 **waits at `in-review`**, and say so to the
  human: _"Part k+1 is approved but stacked on #<k-id>, still unmerged — it waits; don't
  merge it in the GitHub UI, its base is k's branch"_ (the rule binds your merge; the
  human's click needs the warning). Never merge a part into a sibling's branch: the code
  would never reach the default branch, `Closes #<id>` would not fire, and closeout would
  archive a task that never landed. k merged → the landing move above, then surface the
  gate. If the human merged k+1 into k's branch anyway, it lands only through k's PR:
  `/resume` closes it out once k's PR merges into the default branch, and until then
  says it waits (the orchestrator's RESUME, task-PR gate).

  If k's review does force big changes, surface it at once — the human decides:
  rework k+1 on the new k, wait, or drop it.

## The discovery safety net

The primary split happens at the PRD → task transition, where no artifacts exist yet
to restructure. The safety net is the existing discovery machinery: when the **Spec
Author** (structuring a child) or an **Implementer** (mid-flight) finds the scope
hides **≥2 independently mergeable units the PRD didn't reveal**, that is a
legitimate discovery — raised with [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) as **T2 UNSPECIFIED_DECISION**
(the plan is silent on the cut; partition or keep-together is the human's call) and
mediated with [`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md) as any other (the Orchestrator's §"Discovery
mediation"). On **"keep together"**: record the resolution and resume. On
**"partition"** in an L1 task the current task keeps the **first** unit and you run, in
this order:

1. **Ask the second half in the same mediation** — later-unit work already on the branch
   (commits; under auto-commit OFF, staged save-points): keep it or drop it? Name
   the commits. (A second fork that only exists because of the first answer: record it in
   the same `**Resolution**` block, no second entry.)
2. **Create the parent** partition-plan issue with the current task as Part 1 (row
   `→ #<id> <paused_from>` — `in-progress`, or `spec-in-progress` when the Spec Author
   raised it) and the remaining units as later parts.
3. **Add the trace lines at the top of the child's issue body yourself** with
   `issue-body add-trace` (§Editing the plan and child bodies) — the body is the
   externalized spec, or still the skeleton when the Spec Author raised it at spec
   time.
4. **Route the narrowing to the Spec Author** ([`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md) step 3, with the
   decision and the parent row): it narrows the spec to the slice and re-runs
   [`spec-to-issue`](.claude/skills/spec-to-issue/SKILL.md), which preserves the trace lines you just added. In step-by-step mode
   the narrowed `tasks.md` is re-presented at the next checkpoint — no new gate.
5. **Record and resume**: the Implementer re-invoke carries the keep/drop answer — it
   performs the `git revert`s by commit (never a force-push), or discards the staged
   later-unit changes under auto-commit OFF — and resumes on the narrowed slice.

On an **L2 (triage) task** — no PRD — "partition" means the task was mis-levelled: keep
the triage on its first unit (you narrow its fix plan: that is authoring, so you write
the narrowed triage body anew, and `issue-body keep-trace` carries its trace lines — the
recipe of [`triage-issue`](.claude/skills/triage-issue/SKILL.md) step 7)
and capture the rest as `/spinoff` stubs (or a `/define` when it is a real feature); **no
parent is opened** — the parent/part mechanics are L1-only. Never partition silently from
inside a task.

## RESUME and ORIENT on a partition parent

The queue listing `/resume` runs with no args includes
`gh issue list -l harness:partition-plan`. An open parent with unticked rows
surfaces as **"partition in progress: next part per the plan — Part <k>: <slice>"**, or
as **"partition in progress — waiting on #<id> (Part <j>)"** when the next row is blocked
by an in-flight child (add `, in-review — stacked start possible` when that child's PR is
open). The next part is the first row still **`(not started)`** whose
`Depends on` parts are merged — confirmed on GitHub, not from the row
(`gh issue view <id> --json state` and the child's PR, recovered from its branch
`harness/<id>-*`) — or at `in-review`, when the human takes a stacked start (above). A
row carrying `→ #<id>` is an **in-flight child, never re-opened**: it resumes **as today**
by its own id — offer to resume it (`/resume #<id>`) in this session; the parent is only
the map. If that child's issue is closed and its PR merged, the row missed its closeout
tick: if its
closeout never finished (any status label but `done` — even `in-progress`, when the
human merged during rework) run
[`task-closeout`](.claude/skills/task-closeout/SKILL.md) for it first — retry-safe, it picks up a half-done closeout where it
stopped, and ticks the row itself; otherwise tick it now (`set-row --merged`) (and close
the parent if that was the last row) and move on. **No eligible row → nothing to start
from the parent**: say so, name the blocking child,
offer to resume it. Resuming the parent itself means **starting the next part**: the
re-validation above, then the child procedure, then the round-trip continues from its
UI-design gate and Spec Author dispatch onward, unchanged.

## Closing the parent

- **Mechanical, at the last child's closeout.** [`task-closeout`](.claude/skills/task-closeout/SKILL.md)'s finalize step, on
  a task whose body carries `Part <k> of #<parent>`, ticks that row and — when every row
  is ticked, merged or dropped — closes the parent with a summary comment. No human
  prompt: each merge already passed the human gate. The skill owns the mechanics
  (`issue-body set-row`, idempotent on a retried finalize, closed-parent no-op).
- **Partial abandonment — a human close.** When the human drops the remaining
  parts, mark their rows dropped and close the parent yourself recording what shipped
  and what was dropped and why
  (`gh issue close <parent> --comment "Shipped: parts … · Dropped: parts … — <why>"`).
  Unopened rows cost nothing. An opened-but-unmerged child that is dropped is closed
  like any abandoned task: close its issue with a comment recording the drop, delete
  its branch, no closeout (there is nothing merged to record).

## Human touchpoints — zero new gate machinery

1. **Partition approval** — the only new touch: one more question at the define's
   close (cuts + dependency shape).
2. **Spec gate per child** — unchanged, at each child's turn.
3. **Stacked-start choice** — with the assumption named.
4. **Plan amendments** — re-validation or discovery → presented, human approves.
5. **Abandonment / parent close** — human; the mechanical close rides the last
   merge gate.
6. **Merge gates per child** — unchanged.
