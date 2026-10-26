---
name: a11y-audit
description: 🍋 The accessibility-QA review lens for the UI Designer — deterministic-first and tool-orchestrating. Measures contrast from tokens, rides the project's a11y lint, runs axe on the rendered DOM when testable, then judges only what tools can't (focus management, live regions, alt-text quality, reduced motion). Use at REVIEW when a task touched UI, alongside design-critique.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [ui-designer]
---

# Accessibility Audit

Judge the **accessibility** of an implemented UI change against the WCAG target the
`ui-handoff.md` §9 set (default WCAG 2.1 AA). This is the **objective, measurable** half of
design QA — the subjective half (does it carry the design's point of view?) is the
[`design-critique`](.claude/skills/design-critique/SKILL.md) skill, run alongside this one. The build twin is the implementer's
`build-ui/accessibility.md`: this lens checks what that resource asks the implementer to
build accessible by construction. When you change an axis below, keep its build twin in step.

The method is **deterministic-first and tool-orchestrating**: gather evidence with tools
before you judge, and reserve your own judgment for what no tool can decide. A clear verdict
must not depend on whether the optional tools are present — the tiers degrade gracefully.

## The tiered method

Run the tiers in order; each adds evidence the next builds on.

- **T0 — token-pair contrast (always available, deterministic).** Run
  `lemony design-tokens contrast`. It computes the WCAG ratio of every foreground/background
  token pair — including any dark-mode override — and exits non-zero on a pair below its
  floor. This is the one a11y measurement doable offline, because colour comes from the
  token file. It is complementary to `lemony design-tokens validate` (validate proves colour
  is a token reference; contrast proves the pair meets its floor). When the project declares
  `design_tokens.verify` in `harness.config.yml`, the same command also runs the design
  system's own verifier and forwards its report — read that output as T0 evidence too.
- **T1 — source a11y lint (rides the project).** The project's own linter usually carries an
  accessibility plugin (`eslint-plugin-jsx-a11y`, Svelte's or Vue's a11y rules). Run the
  project's `lint`; don't reimplement it. Read what it flags.
- **T2 — axe on the rendered DOM (when testable).** If the repo can render components in a
  test (vitest-axe / jest-axe, Storybook + axe, or Playwright + `@axe-core/playwright`), run
  axe over the changed views and read the violations. Browser-driven is simply the strongest
  variant of this tier — opportunistic, **not required**. If nothing can render the DOM, skip
  T2 and say so in the report; the verdict still stands on T0/T1/T3.
- **T3 — judgment (you).** Decide what the tools cannot: focus management on route and dialog
  changes, live-region announcements, keyboard patterns for custom widgets, meaning not
  carried by colour alone, **alt-text quality** (a tool sees that `alt` exists; only judgment
  sees whether it is meaningful), and reduced-motion. T3 also triages and interprets the
  T1/T2 output against the handoff — a lint rule a project disabled on purpose is not your
  finding.

## The axes — tier coverage plus what judgment adds

Each axis names which tier catches it and what remains for T3.

### Semantic HTML first

Mostly T1/T2 (a clickable `<div>`, a skipped heading level, missing landmarks surface in
lint/axe). T3 confirms the right element was used for the meaning, not just a passing rule.

### Colour and contrast

T0 measures it from tokens — the deterministic floor (text ≥ 4.5:1, large ≥ 3:1, non-text
≥ 3:1), including dark mode. T3 checks the rendered pair where colour is _not_ from a token
(an image-on-text overlay, a hardcoded value `validate` already flags).

### Keyboard operability

T2/axe catches missing focusability; T3 walks the actual order, confirms a **visible** focus
indicator meets the non-text floor, that there is no keyboard trap, and that focus is managed
on dynamic change (dialog open returns focus on close; route change moves it sensibly).

### ARIA — only when semantics fall short

T1/T2 flag invalid ARIA and `aria-hidden` on focusable content. T3 judges whether ARIA was
reached for where a native element would have done, and whether state attributes
(`aria-expanded`, `aria-selected`, `aria-current`) actually track the real state.

### Forms

T1/T2 catch an unlabelled field. T3 confirms errors are identified **in text** and linked to
the field (not colour alone), and required/invalid state is in the accessibility tree.

### Images, icons and media

A tool sees that `alt` is present or absent; **T3 judges whether it is meaningful** — a
decorative image is empty-`alt`, a meaningful one conveys its purpose, an icon-only control
has an accessible name.

### Motion and time

Largely T3: is `prefers-reduced-motion` honoured for non-essential animation (mirrors the
motion judgment in [`design-critique`](.claude/skills/design-critique/SKILL.md))? Nothing flashes more than three times a second; no
tight time limit without a way to extend it.

### Touch and pointer targets

T2 can measure target size; T3 confirms interactive targets meet the 24×24 CSS px minimum
(WCAG 2.2 SC 2.5.8, Level AA) — 44×44 is the WCAG 2.1 AAA enhanced size and the comfortable
touch target — and adjacent targets are spaced so they aren't mis-tapped.

## Confidence gating

Raise a finding when a tool flags it, or when you are **>80% confident** of a T3 judgment
issue. A measured T0/T1/T2 failure is not a confidence call — report it. Don't pad the report
with rules the project deliberately disabled.

## Report

```
## Accessibility Audit — <task name>

**Target**: <WCAG level from ui-handoff §9>
**T0 contrast**: ✅ pass / ❌ <failing pairs>
**T1 a11y lint**: ✅ / ❌ <violations> / N/A
**T2 axe (rendered DOM)**: ✅ / ❌ <violations> / skipped — <why>
**T3 judgment**: <findings, or "none">

**Verdict**: approve / changes requested — <one-line reason>
```

"Changes requested" routes back to the Implementer (transient — no label). If the handoff §9
is silent on a genuinely ambiguous decision, raise a discovery ([`raise-discovery`](.claude/skills/raise-discovery/SKILL.md)) rather
than guessing. An independent defect unrelated to this change is a side finding
([`note-side-finding`](.claude/skills/note-side-finding/SKILL.md)).
