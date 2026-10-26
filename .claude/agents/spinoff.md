# Mid-task capture (`/spinoff` offer) — Orchestrator companion

> Vendor companion to `.claude/agents/orchestrator.md` (the hat). **Read on
> demand, never at boot**: when the human mentions what may be an independent,
> non-blocking defect mid-task, or when a sub-agent's return summary carries a
> `## Side-findings` block.

While you (the hat) are driving the conversation — between sub-agent dispatches, at
gates, in ordinary back-and-forth — the human will sometimes mention an **independent,
non-blocking** defect: one the current task does **not** need to touch, and that doesn't
have to be fixed now ("oh, the export button is also broken on Safari"). Don't let it
evaporate and don't context-switch to it: **offer to spin it off**. The discriminator is
_independence_ — is this something the current task touches anyway?

This is distinct from three neighbours:

- **Just fix it** — if the defect is **in scope for the current task** (something this
  change already touches), fix it in the current PR. No offer, no stub — spinning off
  in-scope trivia only pollutes the backlog.
- **T3 SCOPE_DRIFT** (discovery) — when completing **the current task** _forces_ you to
  touch out-of-scope work (the task can't finish without it). That pauses via
  [`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md). `/spinoff` is the opposite: the current task doesn't need the
  defect touched, so it never pauses and keeps going.
- **`/define`** — a feature _idea_, not a defect. Route those to DEFINE, not `/spinoff`.

Calibration — **lean toward offering** so nothing slips, but keep it
frictionless and noise-free:

- Offer only when you'd bet it's a **genuine, independent defect worth a tracked issue**
  — not for every stray observation, and not for anything you can fix in place. When in
  doubt _whether to track a real independent defect_, lean toward offering; when in doubt
  _whether it's even a real, independent bug_, stay quiet.
- The offer is a **single line**, in the human's language: _"This looks like an
  independent bug — want me to `/spinoff` it and keep going?"_ One tap to dismiss; if the
  human says no, drop it and continue without comment.
- **Never re-offer the same finding twice in a session.** "Same finding" = the same
  underlying defect even if re-described; when unsure, treat a clearly new symptom as new.
  This rule is the **only** human-side dedup (the capture verb is non-idempotent by
  design — each run opens a fresh stub), so honor it.
- The offer **never pauses** the current task and never blocks on a reply — if the human
  ignores it and keeps working, so do you.

On **accept**, capture it exactly as the `/spinoff` command does — the `spinoff` CLI
verb via the launcher, with the **current task's id** as the parent (recover it the same
way `/spinoff` does — the `Active task:` line of
`.claude/hooks/lib/lemony.sh status --local`; omit `--parent` when it reads `(none)` or
the command fails):

```bash
.claude/hooks/lib/lemony.sh spinoff \
  --title="<one-line symptom>" \
  --body="<where it was seen; a code pointer if you have one>" \
  --parent=<current task id> \
  --severity=<low|medium|high|critical>
```

Stub creation is **fail-loud** (a non-zero exit means it did not open — surface it, don't
pretend it was captured); the telemetry emit is **best-effort** (a `Warning:` means only
the event failed, the stub stands). Relay the verb's own `Captured #<id>…` line (it
carries the parent link) and **return to the current task**. The stub waits in the backlog as `harness:status:pending`
for a later pickup. The human can also trigger this directly with the `/spinoff` command;
the offer is the safety net for when they don't remember it mid-flow.

## From a sub-agent (the side-finding channel)

The same offer applies when the source is **not the human but a sub-agent's return
summary**. A sub-agent runs in fresh context and cannot interrupt you, so when it spots a
defect that is **independent of its task** (the task finished fine without touching it) it
**notes it instead of pausing** — that is the [`note-side-finding`](.claude/skills/note-side-finding/SKILL.md) skill, the non-pausing
sibling of [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md). It appends a `## Side-findings` block to its summary, one
bullet per finding (`symptom` / `location` / optional `severity`), and keeps working. (A
**blocking** defect is the opposite case — the sub-agent raises a T1–T6 discovery and
stops; you handle that with [`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md), per the orchestrator's §"Discovery
mediation".)

When you **read back a sub-agent's summary**, scan for a `## Side-findings` block. For each
bullet, make the **same single-line `/spinoff` offer** as for a human-mentioned defect —
pre-filled from the bullet (`--title` ← symptom, `--body` ← location, `--severity` ← the
read if given), the active task as `--parent`. Same calibration applies verbatim: lean
toward offering, one-tap dismissal, **never re-offer the same finding twice** (a
sub-agent's finding and a later human mention of the same defect are the _same_ finding),
and it **never pauses** the task. A side-finding is a candidate for the offer, not an
auto-capture — you still make the call and the human still decides.

A bullet tagged **`kind: drift`** is `docs/architecture.md` map staleness,
not a code defect: add **`--kind=architecture-drift`** to the `/spinoff` so the stub carries
the `harness:architecture-drift` routing label and a later pickup resolves it via the
Architect's [`update-architecture`](.claude/skills/update-architecture/SKILL.md) (a targeted map-fix), not a code change. **Fallback:** if
[`update-architecture`](.claude/skills/update-architecture/SKILL.md) is not installed (the project keeps no `architecture.md`), drop the
`--kind` and capture it as a generic stub — never let the offer fail because the routing
target is absent.

Two things you own because the sub-agent can't: **(1) cross-round dedup.** A sub-agent
re-invoked with fresh context (e.g. a Reviewer you rejected and re-ran) has **no memory of
what it side-noted before** and will re-emit the same `## Side-findings` block every round.
You hold the continuous context, so dedup is yours: an identical or re-described bullet
from a later round is the _same_ finding — don't re-offer it. **(2) gate ordering.** When
the read-back lands at a gate (a Reviewer returns right before the merge gate), make the
side-finding offer **after** the gate prompt, never before — the gate decision is primary;
the offer trails it as a secondary, dismissable line so it never splits attention at the
high-stakes moment.
