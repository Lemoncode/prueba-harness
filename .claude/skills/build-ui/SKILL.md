---
name: build-ui
description: 🍋 The implementer's method for building UI from a ui-handoff.md — apply the project's design tokens to whatever stack the repo uses, build without generic "AI slop", and ship accessible by construction. Stack-agnostic — it owns the process and the token contract, not per-framework guides. Use when implementing a task that touches UI and a ui-handoff.md exists.
origin: vendor
vendor_version: '0.11.0'
phase: during-implementation
invoked-by: [implementer]
---

# Build UI

The implementer's **build method**: turn a `ui-handoff.md` (the design contract) plus
`docs/design-tokens.json` (the token source of truth — or the path `design_tokens.file` names
in `harness.config.yml`, when set; read that file wherever this skill says
`docs/design-tokens.json`) into UI code that applies the
project's tokens correctly, carries the design's point of view instead of generic
defaults, and is accessible by construction.

## What this skill owns — and what it deliberately doesn't

It owns the **harness-stable layer**: the tokens-as-code contract, the build process,
and the stack-agnostic principles. It does **not** reproduce per-framework know-how —
how to theme Tailwind v4, configure MUI's `createTheme`, or wire vanilla-extract. You
already know the stacks, and you read `package.json` to confirm which one this repo
uses. A frozen per-stack guide would rot the moment the ecosystem moves (a Tailwind
v3→v4 jump turns it into a lie); the live model does not. So this skill names the
**substrate space** and lets you map any tool — present or future — onto it.

## The process

1. **Read the inputs.** `ui-handoff.md` (under `.claude/state/tasks/<id>/spec/`) is your
   obligatory design input — the dials, screens, components, states, motion, a11y target
   and microcopy. `docs/design-tokens.json` is the token source of truth (§11 of the
   handoff points at it). Read both before writing UI.
2. **Identify the substrate.** Read `package.json` and the styling config to place the
   repo in one of the three archetypes below. The archetype, not the tool name, drives
   how you apply tokens.
3. **Apply tokens through the substrate.** Build the screens and components from the
   handoff at the direction its dials set — referencing tokens, never raw values.
4. **Pull the craft resources as you build.** Read [anti-slop.md](./anti-slop.md) before
   generating any visual code, and [accessibility.md](./accessibility.md) when you build
   anything interactive or visual. They load on demand — don't inline their content here.
5. **Self-validate before signalling done.** Run `lemony design-tokens validate` (it flags
   raw colours/dimensions in source that should reference a token) and re-read the
   handoff's dials and targets against what you built.

## Tokens-as-code — the contract

`docs/design-tokens.json` is the **single, client-owned source of truth** (or the path
`harness.config.yml` names in `design_tokens.file`, when set — read that file instead), a 3-tier
W3C-DTCG model: **primitive** (raw scale values) → **semantic** (intent: `color.surface`,
`space.inset.md`) → **component** (a component's specific slots). Two rules hold on every
stack:

- **Reference semantic or component tokens; never primitives, never raw literals.** A
  component reads `color.surface`, not `gray.50` and never `#fff`. Raw values in source
  are what `design-tokens validate` catches.
- **Dark mode (and any theme) is an override, not a fork.** Swap the values behind the
  semantic layer; the component code stays identical. You never branch component logic on
  the theme.

## Substrate archetypes

Identify which one the repo is, then apply tokens that way. Each snippet is
**illustrative, not normative** — it names the space so you can map the actual tool.

**1. CSS custom properties (runtime cascade).** Token → `--var` → `var()`. The cascade
carries theming; an override re-declares the variable.

```css
:root {
  --color-surface: #ffffff; /* from semantic token color.surface */
  --space-inset-md: 12px;
}
[data-theme='dark'] {
  --color-surface: #1a1a1a; /* dark mode = override the var, the .card below is untouched */
}
.card {
  background: var(--color-surface);
  padding: var(--space-inset-md);
}
```

_Space: vanilla CSS, Sass, CSS Modules._

**2. Central config/theme object a library consumes.** Tokens populate one theme object;
components read it through the library's API (`className`, `sx`, `styled`), never literals.

```ts
export const theme = {
  colors: { surface: tokens.color.surface },
  space: { insetMd: tokens.space.inset.md },
};
// usage: <Box sx={{ bg: 'surface', p: 'insetMd' }} /> — the library resolves it, no hard-coded values
```

_Space: Tailwind (`config` / `@theme`), MUI / Chakra / Mantine (`createTheme`),
styled-components / Emotion._

**3. Compiled type-safe contract (zero-runtime CSS-in-TS).** Tokens become a typed
contract resolved at build; a missing token is a compile error, not a silent fallback.

```ts
export const vars = createThemeContract({
  color: { surface: null },
  space: { insetMd: null },
});
export const light = createTheme(vars, {
  color: { surface: tokens.color.surface },
  space: { insetMd: tokens.space.inset.md },
});
// components consume `vars.color.surface`; the type system rejects an unknown token
```

_Space: vanilla-extract, Panda CSS, StyleX, Linaria._

**Orthogonal axis — static-build ↔ dynamic-runtime theming.** Independent of the
archetype: a single fixed theme can compile away entirely, while multi-tenant / white-label
products need tokens to live as CSS variables or context so they switch at runtime. Pick the
side the product needs; it cross-cuts all three archetypes.

**Out of scope for now — native substrates.** React Native / Compose / SwiftUI map tokens
to a native style object; recognised as a fourth archetype but not covered here yet.

## When the handoff contradicts reality

If building reveals that the `ui-handoff.md` contradicts the codebase, is missing a
decision with more than one valid answer, or asks for something that already exists, **do
not improvise** — raise it through the implementer's discovery channel so the designer or
the human resolves it, then resume. An independent defect unrelated to your change is a
side finding, not a blocker.

## Cross-references

```
grill-ui → ui-handoff.md → implementer (build-ui) → REVIEW (design-critique + a11y-audit) → merge gate
```

You consume `ui-handoff.md`; the REVIEW design lens checks what you built against it. The
[`design-critique`](.claude/skills/design-critique/SKILL.md) skill mirrors [anti-slop.md](./anti-slop.md)'s principles and [`a11y-audit`](.claude/skills/a11y-audit/SKILL.md)
mirrors [accessibility.md](./accessibility.md)'s — when you change a principle here, keep its
review twin in step.

---

See also:

- [anti-slop.md](./anti-slop.md) — the craft layer: how to build the design's point of view
  into the code instead of generic defaults.
- [accessibility.md](./accessibility.md) — WCAG 2.1 AA implementation patterns.
