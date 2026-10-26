# Accessibility — building to WCAG 2.1 AA

Load this when you implement anything interactive or visual. The `ui-handoff.md` §9 sets
the **target** (default WCAG 2.1 AA) and any task-specific decisions; this resource is the
**implementation** layer — how to build it accessible by construction, so the [`a11y-audit`](.claude/skills/a11y-audit/SKILL.md)
review lens finds nothing to reject. Accessibility is not a pass you bolt on at the end; it
is a property of how the markup, focus, colour and motion are built.

## Semantic HTML first

The fastest path to accessible UI is the right element. A native `<button>`, `<a>`,
`<label>`, `<nav>`, `<main>`, `<ul>` carries role, keyboard behaviour and focus for free.

- **Use the element that means what you mean.** A clickable `<div>` is a bug — it has no
  role, no keyboard handler, no focusability. Use `<button>` for actions, `<a href>` for
  navigation.
- **One `<h1>` per view, headings in order.** Don't skip levels for visual sizing — size
  with tokens, structure with heading level. Screen-reader users navigate by heading.
- **Landmarks frame the page.** `<header>`, `<nav>`, `<main>`, `<footer>` give assistive
  tech a map. Reach for ARIA roles only to fill a gap native elements can't.

## Colour and contrast

This is the objective floor — measured, not judged.

- **Text contrast ≥ 4.5:1** against its background; **large text (≥ 24px, or ≥ 19px bold)
  ≥ 3:1**.
- **Non-text contrast ≥ 3:1** for UI component boundaries, icons that carry meaning, and
  the visible focus indicator.
- **Never encode meaning in colour alone.** Pair colour with an icon, label or pattern — a
  red border needs an error message, a green dot needs a "online" label.
- Because colour comes from semantic tokens, contrast is a property of the token pairing;
  check the actual rendered pair, including in dark mode.

## Keyboard operability

Everything that works with a mouse must work with a keyboard alone.

- **All interactive elements are reachable and operable by keyboard**, in a logical Tab
  order that follows the visual/reading order. Native elements give you this; custom
  widgets need `tabindex` and key handlers.
- **A visible focus indicator on every focusable element** — never `outline: none` without
  a clearly visible replacement that meets the 3:1 non-text contrast floor.
- **No keyboard traps.** Focus can always move on; if you trap it deliberately (a modal),
  provide the documented way out (Escape) and restore focus on close.
- **Manage focus on dynamic change.** Opening a dialog moves focus into it and contains it;
  closing returns focus to the trigger. Route changes move focus to a sensible anchor.
- **Honour expected keys** for the widget pattern (Enter/Space activate, arrows move within
  a composite like tabs or a menu, Escape dismisses).

## ARIA — only when semantics fall short

The first rule of ARIA is don't use ARIA when a native element would do. When you do need
it:

- **Name every control.** A visible `<label>` (associated via `for`/`id`), or
  `aria-label` / `aria-labelledby` when there is no visible text (icon-only buttons).
- **Reflect state, don't fake it.** `aria-expanded`, `aria-selected`, `aria-checked`,
  `aria-disabled`, `aria-current` must track the real state.
- **Announce async change with live regions.** A status message, toast, or validation
  result that appears without a focus change needs `aria-live` (`polite` for status,
  `assertive` only for errors) so it is announced.
- **Don't break the accessibility tree.** `aria-hidden` on focusable content, redundant
  roles, or mislabelled landmarks are worse than no ARIA.

## Forms

- **Every field has a programmatically-associated label** — not a placeholder standing in
  for one (placeholders vanish on input and fail contrast).
- **Errors are identified in text, linked to the field** (`aria-describedby`), and not by
  colour alone. Group related fields with `<fieldset>`/`<legend>`.
- **Required and invalid states are conveyed in the accessibility tree** (`aria-required`,
  `aria-invalid`), not only visually.

## Images, icons and media

- **Meaningful images need a text alternative** (`alt`) that conveys their purpose;
  **decorative images get empty `alt=""`** so they are skipped.
- **Icon-only controls need an accessible name** (see ARIA above); a standalone meaningful
  icon needs a text equivalent.

## Motion and time

- **Respect `prefers-reduced-motion`** — provide a reduced or no-motion path for non-essential
  animation. This mirrors the motion guidance in [anti-slop.md](./anti-slop.md).
- **No content that flashes more than three times per second.**
- **Don't impose tight time limits**; if one exists, let the user extend or disable it.

## Touch and pointer targets

- **Interactive targets are large enough to hit** — a minimum of 24×24 CSS px (WCAG 2.2 AA,
  SC 2.5.8); 44×44 is the WCAG 2.1 AAA enhanced size and the comfortable touch target. Space
  adjacent targets so they aren't mis-tapped.

## Self-check before done

Walk the change with these, matching the [`a11y-audit`](.claude/skills/a11y-audit/SKILL.md) review lens so nothing comes back:
keyboard-only traversal reaches and operates everything with visible focus; measured
contrast meets the floor (including dark mode); every control has an accessible name; async
updates announce; reduced-motion is honoured; targets meet the size floor. Where a decision
is genuinely ambiguous, it belonged in the handoff §9 — raise it rather than guess.
