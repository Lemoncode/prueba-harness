---
name: note-side-finding
description: 🍋 Surface an independent, non-blocking defect you spotted mid-task in your return summary instead of pausing or fixing it. Use when a sub-agent (Spec Author, Implementer, Reviewer, Architect) notices a real bug that is unrelated to its current task — the task finishes fine without touching it — so it should be parked for later, not escalated. The non-pausing sibling of raise-discovery.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [spec-author, implementer, reviewer, architect]
---

# Note Side-Finding

## Core Principle

While doing your task with fresh context, you sometimes spot a **real defect that has
nothing to do with the task you were given** — the task finishes correctly without
touching it ("while implementing the parser I noticed the unrelated CSV export drops
the last row"). You **cannot interrupt** the human (you run via `Task`, not in the
hat's conversation) and you should **not** silently fix it (it is outside your task's
scope) or pause for it (it is not blocking you). So you do neither: you **note it in
your return summary and keep going**. The Orchestrator collects it and offers the human
a `/spinoff` capture — nothing is lost, nothing is context-switched.

This is the **non-pausing** half of the discovery family. You write one bullet and
return; you do not create an issue, flip a label, write to `discoveries.md`, or stop.

## Which channel — side-finding vs discovery vs just-do-it

Pick by **two questions: does it block your task, and is it in your task's scope?**

| Situation                                                       | Channel                                                          | What you do                                                                                         |
| --------------------------------------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Defect is **in scope** for your task (your change touches it)   | **Just fix it**                                                  | Fix it in your normal work — no note, no escalation.                                                |
| Defect **blocks** your task / the plan forces it (T1–T6)        | **[`raise-discovery`](.claude/skills/raise-discovery/SKILL.md)** | Pause: write `discoveries.md`, return one line, stop.                                               |
| Defect is **independent and non-blocking** (task finishes fine) | **note-side-finding**                                            | Add a `## Side-findings` bullet, **keep working**.                                                  |
| A feature **idea** (not a defect)                               | mention it in prose                                              | No capture channel here — drop it in your summary prose; the human may pick it up and `/define` it. |

The discriminator against [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) is **blocking**: if you can complete your
task without the defect being touched, it is a side-finding (note and continue), never a
discovery (pause and stop). When genuinely unsure whether it blocks you, prefer
[`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) — a wrong pause is cheaper than coding past a real contradiction.

The same channel covers **architecturally-significant drift in `docs/architecture.md`**
— when you read the map to orient and find it states a boundary/seam the code no
longer matches, in an area your task doesn't touch. That is a defect of the _map_, not the
code: non-blocking and out of your scope, so it rides here. Tag such a bullet `kind: drift`
(see the contract below) so the Orchestrator routes it to the Architect's
[`update-architecture`](.claude/skills/update-architecture/SKILL.md) rather than a generic follow-up; don't fix the map yourself and don't
silently trust one side.

## The contract

When you have one or more independent non-blocking defects, append **one** section to
the **end of your return summary** to the Orchestrator (omit it entirely when you have
none — never emit an empty block):

```markdown
## Side-findings

- **symptom:** <one line — what is wrong>
  **location:** <file:line or the area you saw it>
  **severity:** <low | medium | high | critical — optional>
  **kind:** <drift — optional; only for architecture.md drift>
```

One bullet per finding. `symptom` and `location` are required; `severity` is your
optional read. `kind` is optional and, today, only takes the value `drift` — set it
**only** for `docs/architecture.md` map staleness (above), so the Orchestrator routes the
stub to [`update-architecture`](.claude/skills/update-architecture/SKILL.md); omit it for an ordinary code defect. Keep each to the
symptom + where you saw it — do **not** root-cause or propose a fix (the capture is
deliberately shallow; investigation happens at pickup). Everything else in your return
summary stays exactly as it was — the section is an addition, not a replacement.

Then **continue your task to its normal end** (or, if you were already done, just
return). Do not wait for a reply, do not act on the finding, do not open anything.

## What the Orchestrator does with it

It reads the `## Side-findings` block from your summary and, for each entry, makes the
same single-line `/spinoff` offer it makes for a human-mentioned defect — lean toward
offering, one-tap dismissal, never re-offered twice, never pausing. The active task is
recorded as the parent. You are not involved past returning the bullet.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching channel with reasoning (when torn between side-finding and
   discovery, default to [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) — blocking is the safe assumption).
2. **Flag it**: "This didn't clearly fit note-side-finding. I [noted it / raised it]
   because [reason]. Want to refine the skill?"
