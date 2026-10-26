---
description: 🍋 Capture a non-blocking defect found mid-task as a tracked stub, without leaving the current task.
allowed-tools: Read, Bash
---

# /spinoff

Park an **independent, non-blocking** defect you noticed while working on the current
task — capture it as a tracked stub and **keep going**. This is _not_ the blocking /
out-of-scope case (that is a **T3 SCOPE_DRIFT** discovery, which pauses the task via
[`raise-discovery`](.claude/skills/raise-discovery/SKILL.md)); `/spinoff` never pauses. It is also not for feature ideas — those
go to `/define`.

`$ARGUMENTS` is the defect: the one-line symptom, plus any detail (where you saw it, a
code pointer). If empty, ask one short question to capture the symptom, then proceed.

## Procedure

1. **Identify the parent task** (best-effort): the task in flight. Run
   `.claude/hooks/lib/lemony.sh status --local` and read its `Active task:` line — it
   derives the id from the live branch (`harness/<id>-<slug>`, the `harness/closeout-<id>`
   record branch, or the branch being rebased while a rebase has HEAD detached). If it
   reads `(none)`, or the command fails, capture with no parent (a deferred stub).

2. **Capture the stub** with the `spinoff` CLI verb via the launcher. In one call it
   opens a `harness:managed` + `harness:status:pending` issue (the level is decided at
   pickup, not now — **no** fit-assessment, **no** spec, **no** deep root-cause here:
   that would derail the current task) and emits a `followup_captured` event linking the
   stub to its parent:

   ```bash
   .claude/hooks/lib/lemony.sh spinoff \
     --title="<one-line symptom>" \
     --body="<where it was found; a code pointer if you have one>" \
     --parent=<current task id> \
     --severity=<low|medium|high|critical> \
     --kind=architecture-drift
   ```

   Omit `--parent` when there is no active task; omit `--severity` unless you can infer
   it cheaply (it is best-effort and never blocks capture). Omit `--kind` for an ordinary
   defect — its one value, `architecture-drift`, is for `docs/architecture.md` map staleness:
   it tags the stub `harness:architecture-drift` so pickup routes it to the
   Architect's [`update-architecture`](.claude/skills/update-architecture/SKILL.md) instead of a code change. The stub creation is
   **fail-loud** — a non-zero exit means the issue did not open, so surface it; do not
   pretend the defect was captured. The telemetry emit is **best-effort** — if only that
   fails you'll see a `Warning:` but the stub still stands.

3. **Return to the current task.** Report the captured stub (`#<id>`) in one line and
   resume exactly where you were. The stub waits in the backlog as
   `harness:status:pending` to be picked up later — at pickup it gets its fit-assessment
   (L1/L2/L3) and starts the flow from the captured context.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by /spinoff. I applied [approach] because
   [reason]. Want to update the command?"
3. Offer to add a new rule for the case.
