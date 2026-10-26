# `ui-handoff.md` — the design contract

The artifact the Orchestrator authors at DEFINE (via the `grill-ui` interview) and the implementer builds from when implementing. It lives at
`.claude/state/tasks/<id>/spec/ui-handoff.md`, a sibling of the spec, owned by the Orchestrator; the UI Designer critiques it at DEFINE and reviews the built UI against it at REVIEW.

**It captures DECISIONS and targets, not know-how.** How to apply tokens to a stack, avoid generic
"AI slop", or meet WCAG lives in the implementer's and reviewer's skills. This file says _what to
build_ and _how it should look and feel_, at a level the implementer can execute and the review can
check.

## Two principles that shape every section

- **Graduated altitude.** Default to **decisions-altitude**: reference the design system, name the
  variant, state the few things that matter. Drop to the full **component anatomy** (below) ONLY for
  a genuinely novel or critical component. Don't freeze what the implementer's model already knows.
- **Text-first.** Screens travel as a text inventory + a nav/flow map + per-screen structural intent.
  The implementer generates the pixels from that + the tokens + the anti-slop know-how. A visual
  tool, if the designer used one, is a private DEFINE aid — not a consumed contract.

Every section is **N/A-able** per task: mark a section N/A rather than padding it.

---

## Template

```markdown
# UI handoff — #<id> <topic>

**Status**: in_progress | completed

> Owned by the Orchestrator (authored via `grill-ui`). Sibling of the spec. The implementer builds
> from this via the `build-ui` skill; the design QA lens checks the built UI against it at REVIEW.
> Decisions-altitude; text-first; tokens by reference.

## 1. Personas / users served

<!-- Who this serves and the context that shapes design. Consume docs/personas.md if present;
     never restate it wholesale — capture only what drives a design decision here. -->

## 2. Aesthetic direction

**Tone preset**: controlled | impact | innovative | (none)
**Dials**: variance = low|medium|high · motion = low|medium|high · density = low|medium|high
**Brand references**: <sites/products admired, and what to take from each>
**Voice / feel**: <a few words — e.g. "calm, precise, trustworthy">

<!-- See "Direction language" below for what the presets and dials mean. The dials are the
     verifiable contract; the review checks the built UI against them. -->

## 3. Screen inventory + nav / flow

<!-- The screens/surfaces this task adds or changes, and how the user moves between them.
     Text or a mermaid flow diagram. No pixels. -->

## 4. Per-screen layout

<!-- For each screen: regions, hierarchy, what draws the eye first. Words, not mockups. -->

## 5. Components

<!-- Decisions-altitude by default: name the component, the variant, and the states that matter.
     Use the full anatomy (below) ONLY for a novel or critical component. -->

## 6. States

<!-- Empty / loading / error / success / edge content for the task's surfaces. -->

## 7. Responsive / breakpoints

<!-- The behavior that actually changes across breakpoints for this task. -->

## 8. Motion / interaction

<!-- Motion appetite (from the dial) + the few interactions that carry meaning. -->

## 9. Accessibility

<!-- Target level (default WCAG 2.1 AA) + task-specific a11y decisions. The audit and the
     how-to are skills; capture only decisions here. -->

## 10. Microcopy

<!-- The actual words for the task's key labels and messages, inline. Voice follows §2. -->

## 11. Token reference

Reference the token file — `docs/design-tokens.json`, or the path `design_tokens.file` names in
`harness.config.yml` — the single, client-owned source of truth, a 3-tier
W3C-DTCG model (`primitive` → `semantic` → `component`). **Never inline token values here; point at
the file.** If the project has no token file yet, the interview offers to scaffold one (derived from
the answers) or to connect a design tool; if the human declines both, say so and capture it as an
open question — never invent a token set silently. `lemony design-tokens validate` flags raw
colours/dimensions in source that should reference a token.

## Open questions

<!-- Anything the interview left unresolved. If a fork has more than one valid answer and the user
     can't resolve it, raise a discovery rather than guess. -->
```

---

## Direction language (for §2)

The aesthetic direction is expressed as three explicit **dials**, optionally seeded by a **tone
preset**. Dials are reproducible and review-verifiable; they exist to fight the generic defaults a
model reaches for unprompted.

### Dials

- **Variance** — _conventional ↔ expressive._ How far the design departs from safe, system-default
  patterns.
  - **low** — predictable, system-like, fast to build; risks looking generic.
  - **medium** — distinctive but restrained; a clear point of view without flamboyance.
  - **high** — bold, characterful, memorable; more build cost and more ways to get it wrong.
- **Motion** — _still ↔ animated._ Appetite for transition and animation.
  - **low** — minimal, functional transitions only.
  - **medium** — purposeful motion on key interactions.
  - **high** — rich, choreographed motion as part of the identity.
- **Density** — _airy ↔ compact._ Information density and use of whitespace.
  - **low** — spacious, generous whitespace, few elements per view.
  - **medium** — balanced.
  - **high** — dense, data-rich, efficient for expert/repeat use.

### Tone presets (optional shorthand)

A preset seeds default dial values as a starting point; the user can override any dial after.

| Preset         | variance | motion | density | Feel                                               |
| -------------- | -------- | ------ | ------- | -------------------------------------------------- |
| **controlled** | low      | low    | medium  | Calm, trustworthy, enterprise; clarity over flair. |
| **impact**     | high     | medium | low     | Bold, memorable, marketing-forward; few big moves. |
| **innovative** | high     | high   | medium  | Novel, dynamic, cutting-edge; motion as identity.  |

---

## Component anatomy (for §5, novel/critical components only)

Drop to this fuller shape ONLY when a component is genuinely new to the project or critical enough
that the review needs a fixed reference. For everything else, decisions-altitude (name + variant +
states-that-matter) is enough.

1. **Description / when to use** — what it is and when to reach for it.
2. **Variants** — the variants and when each applies.
3. **Props / properties** — the inputs that change its appearance or behavior.
4. **States** — default / hover / active / focus / disabled / loading / error, as applicable.
5. **Anatomy / layout** — the internal regions and their arrangement (text).
6. **Behavior / interaction** — what it does on interaction, including motion.
7. **Accessibility** — role, keyboard interaction, focus handling, screen-reader announcement.
8. **Do's and Don'ts** — the traps specific to this component.
