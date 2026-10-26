---
name: design-critique
description: 🍋 The design-QA review lens for the UI Designer — judge an implemented UI change against its ui-handoff.md design contract (dials, focal point, states, microcopy) and the point-of-view test. Confidence-gated, verdict plus route-back, no severity theatre. Use at REVIEW when a task touched UI, alongside a11y-audit.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [ui-designer]
---

# Design Critique

Judge the **design quality** of an implemented UI change, with **fresh context** — the
subjective half of design QA. The objective, measurable half (WCAG contrast, keyboard,
semantics) is the [`a11y-audit`](.claude/skills/a11y-audit/SKILL.md) skill, run alongside this one. This skill does not re-judge
accessibility; it asks whether the screen carries the **point of view the handoff chose**.

Your bar is the `ui-handoff.md` the Orchestrator authored for this task (under the task's
`spec/` directory) — its dials, focal points, component and state decisions, motion
appetite and microcopy. The build twin is the implementer's `build-ui/anti-slop.md`: this
lens checks, in judge voice, what that resource asks the implementer to build. When you
change an axis below, keep its build twin in step.

## What you judge against — and what you don't

Every finding ties to one of two anchors, never to raw preference:

- **A handoff deviation** — the build did not honour a decision the handoff made: the §2
  dials, the §4 focal point, the §6 states, the §10 microcopy, the §8 motion appetite.
- **The point-of-view test** — _could this screen have been generated for any product?_ If
  yes, it has no point of view, which is itself a failure of the handoff's chosen direction.

You do **not** flag "I would have done it differently". The UI Designer holds a point of
view but holds it lightly; a critique that relitigates settled, handoff-honouring choices
trains the reader to ignore it. If the handoff itself is wrong or silent on a case, that is
a **discovery**, not a rejection — raise it ([`raise-discovery`](.claude/skills/raise-discovery/SKILL.md)) so the designer or human
resolves it, rather than failing the change.

## Confidence gating

Only raise a finding you are **>80% confident** is a real deviation or point-of-view
failure. State confidence when borderline. Match the **variance dial**: at low variance,
restraint is correct and manufactured flair is the bug; at medium/high, the generic default
is the failure. Calibrate to the dial — don't demand maximum expression everywhere.

## The axes

For each, the question is "does the build carry the handoff's decision?" — not "is this how
I'd do it?".

### Typography

Does the type establish the handoff's hierarchy through a real scale (size, weight,
colour, space), or fall back to arbitrary sizes and one global line-height? If the direction
is expressive, does the typeface treatment actually carry it?

### Colour

Is colour driven from semantic tokens with the restraint the dial asked for — most of the
UI neutral, the accent earning attention where it carries meaning — or a reflexive
gradient/rainbow the handoff never called for?

### Space, layout and hierarchy

Does spacing come from a scale and create rhythm, with the density the §2 dial set? Is there
a deliberate focal point (§4), or a flat grid of equal-weight cards with no anchor — the
canonical slop layout?

### Depth, borders and surface

Is separation carried by space and surface first, with borders and elevation only where
they mean something — or is everything outlined and shadowed? Are radius, stroke and
elevation consistent and on-voice, from tokens?

### Motion as craft

Does motion match the §8 appetite — present where the brief is high-motion, absent where
it's low — and does each animation show a relationship (origin, change, loading) rather
than decorate? Fast and eased, not slow or bouncy-by-default?

### Responsive as craft

Are the §7 breakpoints designed — a real layout/nav/density change — rather than the
desktop layout shrunk until it breaks? Are the small-screen empty/loading/error states
first-class, with no horizontal scroll or clipped content?

### Component and state completeness

Are all the §6 states built (empty, loading, error, success, edge), or only the happy path?
Does the change reuse the design system rather than introduce a bespoke one-off next to the
system component? Is the §10 microcopy verbatim and in voice, not generic "Submit"?

## Report

Output a concise verdict the Orchestrator can act on — prose and a one-line verdict, **not**
a severity table:

```
## Design Critique — <task name>

**Against**: ui-handoff.md (<the focal decisions you checked>)

<findings — each tied to a handoff section or the point-of-view test, with confidence
when borderline; or "no design deviations">

**Verdict**: approve / changes requested — <one-line reason>
```

"Changes requested" routes back to the Implementer (transient — no label). When the handoff
is the thing at fault, raise a discovery instead. An independent defect unrelated to this
change is a side finding ([`note-side-finding`](.claude/skills/note-side-finding/SKILL.md)), not a rejection.
