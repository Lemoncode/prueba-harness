---
description: 🍋 L3 escape hatch — record one l3_bypass event, then do the work with no issue, no task state, no review.
allowed-tools: Read, Write, Edit, Bash(.claude/hooks/lib/lemony.sh emit l3_bypass *), Bash(git status *), Bash(git diff *)
---

# /bypass

The **L3 escape hatch**: force a task out of the harness when it has nothing to
specify, verify, or review (typo, mechanical rename, lockfile bump, comment fix). The
bypass is **deliberate and recorded** — one telemetry event so a misclassification is
observable later — but otherwise ceremony-free.

`$ARGUMENTS` is the change to make. Derive a short `<topic>` slug and a one-line
`<reason>` from it (why this is L3, not L2). If you can't tell what the change is,
ask one question first.

## Mechanic (do exactly this)

1. **Emit exactly one `l3_bypass` event** — no more, no less:

   ```bash
   .claude/hooks/lib/lemony.sh emit l3_bypass --topic="<topic>" --reason="<reason>"
   ```

   `--topic` ≤ 200 chars, `--reason` ≤ 500 chars. The CLI stamps the envelope
   (`ts`, `user`, `project`, `harness_version`) and appends one line to
   `.claude/state/events.jsonl`. This event is the **entire** record of the bypass.

2. **Do the work directly.** Make the change. That's it.

## What `/bypass` does NOT do

- **No issue** — no `gh issue create`, no `harness:*` labels.
- **No task state** — no `.claude/state/tasks/<id>/`, no branch ceremony.
- **No review** — no Reviewer, no [`senior-review`](.claude/skills/senior-review/SKILL.md), no PR gate.

If, while doing the work, the change turns out to be larger than a bypass deserves
(it touches logic, a public API, or anything a reviewer should see), **stop and
escalate**: switch to `/triage` (L2) or `/define` (L1). The single `l3_bypass`
already emitted is harmless — it's the signal that the dial was nudged.
