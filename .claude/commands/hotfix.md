---
description: 🍋 Urgent L2 fast-track — fix and ship now, skipping the human-wait gates; the Reviewer still runs async and the issue + postmortem are backfilled after.
allowed-tools: Read, Write, Edit, Bash, Task, Skill
---

# /hotfix

An **urgent L2** for a fire that can't wait for the normal gates (production is down,
a regression is shipping). Urgency buys **speed, not the loss of a second pair of
eyes**: the human-wait gates are skipped, but the Reviewer still runs — just
asynchronously, after the fix is out — and the record is backfilled once the fire is
out.

`$ARGUMENTS` is the incident (the symptom, the failing path). If empty, ask one
question to capture it, then proceed.

## Mechanic (do exactly this)

1. **Fix it fast, test-first.** Reproduce, write the failing test ([`tdd`](.claude/skills/tdd/SKILL.md)), make it
   green. Even under fire, the regression test is what stops the fire reigniting.
2. **Branch + PR.** Create `harness/hotfix-<slug>`, commit, push, open the PR
   referencing the incident (`Closes #<id>` in the body if the incident has a tracking
   issue, so it auto-closes on merge).
3. **Skip the human-wait gates.** Do **not** pause for an approval gate, and do
   **not** wait on the merge gate — merge/ship as soon as the test is green and CI
   passes. "As soon as CI passes" is mechanical, not a vibe: execute the merge
   through the checks-precondition executor
   (`.claude/hooks/lib/merge-pr.sh <pr> --squash` — no `--approve-issue` here:
   the hotfix review runs async, so there is no APPROVE to bind at merge time;
   the stale-approve guard belongs to the reviewed task path), which waits for green and
   refuses red or absent checks — urgency skips the _human_ wait, never the
   verification. This is the one path where you don't wait for a human to sign
   off first. On any non-zero exit (red / no checks / timeout / no verdict),
   act on the exit code exactly as the Orchestrator's "Executing an authorized
   merge — the checks precondition" section prescribes: surface the real state
   and ask. Urgency never authorizes `--force` on your own initiative — a fire
   does not lower the bar for merging on red or unverified checks. One
   adaptation: a standing no-checks answer has no closeout PR to ride on this
   path — commit the `merge.allow_no_checks: true` line onto the **hotfix
   branch** before merging, so it lands with the hotfix PR.
4. **Run the Reviewer asynchronously.** After shipping, dispatch the **Reviewer**
   sub-agent (fresh context, full pass — it runs the passes its own table owes) on the
   merged change. The review is not
   skipped — it's deferred. If it surfaces problems, file a follow-up fix (a normal
   `/triage`); the second pair of eyes still happens.

## Backfill (do this once the fire is out)

The hotfix shipped without the usual issue-first record, so reconstruct it:

- **The record issue** — if the PR carried `Closes #<id>` for an issue that is a
  `harness:status:pending` stub, that stub is the record: the merge closed it, so flip
  `pending → harness:status:done`. If that issue carries any other `harness:status:*`,
  it is a **live task** (its own branch and state): do not touch its labels — say so and
  ask the human how to record the hotfix, since marking it done would skip its closeout.
  Otherwise (no `Closes`, or it closed an issue the harness does not manage) create the
  retroactive issue — `gh issue create` with `harness:managed` and
  `harness:status:done` (no `harness:sdd`; it's L2), describing what broke and what was
  hotfixed, and link the PR — then close it (`gh issue close <id>`): the change already
  shipped, and an open issue with no live status would sit outside every queue forever.
- **Write a short postmortem** — as a comment on the record issue (or a note): what broke,
  the root cause, the fix, and why it justified skipping the gates. This is the
  audit trail the skipped ceremony would otherwise have left.

> The backfill is a **prompt instruction** in this build — there is no coded
> enforcement that the issue and postmortem actually get written (deferred until real
> `/hotfix` usage shows the prompt-only approach is insufficient). Treat it as a hard
> obligation anyway: a hotfix with no retroactive record is an unaudited change to the
> default branch.
