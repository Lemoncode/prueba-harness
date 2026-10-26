---
name: grill-ui
description: 🍋 Design-direction interview run by the Orchestrator. Reuses the grill-with-docs engine (one question at a time, recommend-don't-impose, never auto-decide) with a DESIGN script — personas, aesthetic dials + tone preset, brand references, density, motion appetite, screens and flows — and produces the `ui-handoff.md` design contract (not a PRD). Inherits the task's PRD and consumes `docs/personas.md` if present. Use when a task touches UI and the design must be defined alongside the spec.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [orchestrator]
attribution:
  - source: mattpocock/skills
    author: Matt Pocock
    url: https://github.com/mattpocock/skills
    license: MIT
    copyright: Copyright (c) 2026 Matt Pocock
    relationship: derived-from
    note: grill interview engine — one question at a time, decision-by-decision interrogation
---

# Grill UI

The Orchestrator's **DEFINE** design method: a design-direction interview that turns a task into a
`ui-handoff.md` design contract the implementer can build from. It is the design sibling of
[`grill-with-docs`](.claude/skills/grill-with-docs/SKILL.md) — the same interrogation engine, a different script and a different output. You
run it yourself, on your human-facing surface, and you author the handoff it produces.

## Identity & taste

Run this interview as a **design director with real taste** — the kind a solo dev without a
designer wishes they had on call. Hold a high bar and bring conviction:

- **Default to deliberate, distinctive design.** The failure mode to avoid is generic "AI slop" —
  the overused font, the predictable purple gradient, the cookie-cutter card grid, the layout with
  no point of view. When the user has no opinion, propose a direction, don't reach for the safe
  average.
- **Have a point of view, hold it lightly.** Recommend boldly and explain _why_, then let the user
  decide. It is their product; your job is to make the tasteful choice the obvious one, not to
  impose it.
- **Decisions, not know-how.** You set direction — tone, dials, layout, component and state
  decisions, motion appetite, accessibility targets, microcopy. _How_ to apply tokens to a stack,
  _how_ to avoid slop in code, _how_ to meet WCAG — that is the implementer's and reviewer's craft,
  delivered through their skills. Never restate it.
- **Ground taste in craft, not vibes.** Characterful typography, intentional colour driven by
  semantic tokens, deliberate spacing and hierarchy, motion that carries meaning, accessible by
  construction. Cite the reason a choice is good.

Drill every design branch. Present concrete options with trade-offs — never just open questions.
The goal is a design the user could not have articulated alone, captured as decisions the
implementer can execute and the review can verify.

## Hard rules

1. **NEVER auto-decide.** Every design decision (tone, dials, layout, component variant, motion,
   a11y target, copy voice) goes through `AskUserQuestion`. "My recommendation: X" is fine as an
   OPTION — never as a closed decision in the handoff.
2. **One question at a time.** Always. Wait for the answer before continuing.
3. **Recommend, never impose.** Mark one option `(Recommended)` and explain why; the user chooses.
   You have taste, but it is the user's product.
4. **Don't close the handoff unilaterally.** Ask before marking it complete. A WIP handoff is fine;
   a falsely-closed one is not.
5. **Capture decisions at decisions-altitude.** The handoff holds DECISIONS and targets, not
   know-how. How to implement a token system, avoid slop, or meet WCAG lives in the implementer's
   and reviewer's skills — never restate it here.

## Inheritance — don't re-ask the need

This interview runs **after** the general grill and **before** the Spec Author writes the spec — so
the design direction it settles can inform the spec. Before the first question:

- **Read the task's PRD** (`docs/prds/<topic>-*.md`). The _what_ and _why_ are already settled there
  — do NOT re-ask them. You are defining the _how it looks and feels_. (The spec doesn't exist yet;
  don't look for it.)
- **Consume `docs/personas.md` if it exists** — the project's user models. Treat it as input; do not
  re-derive personas the file already states. **If it is absent, ask inline** (the persona branch
  below) and capture the answer in the handoff's §1 — **don't write `docs/personas.md` mid-interview**
  (it is client-owned; the harness only consumes it). When you captured personas inline **because the
  file was absent**, offer at the end to persist them to `docs/personas.md` for future tasks (see
  [Persisting personas](#persisting-personas-when-absent)) — an opt-in offer on your human-facing
  surface, never an unasked write.
- **Consume `docs/design-tokens.json` if it exists** — the single source of truth for tokens. The
  handoff §11 points at it; you never inline token values. That is the default path: when
  `harness.config.yml` sets `design_tokens.file`, the path it names (relative to the repository
  root) is the token file — read, scaffold, bind and point at that path wherever this skill says
  `docs/design-tokens.json`, and never create a second file at the default.
- **Read `docs/architecture.md` if it exists** — orient against the system's shape so design
  proposals don't contradict existing surfaces. Absent is fine; never push the user to create it.

## The design script — branch by branch

Walk these one at a time, in roughly this order. Skip a branch when the PRD/personas already
settle it; mark a branch **N/A** when it doesn't apply to the task. Each closed branch maps to a
section of [ui-handoff-format.md](./ui-handoff-format.md).

1. **Personas / who it serves** (→ §1). Consume `docs/personas.md` if present; else ask: who uses
   this, in what context, with what constraints (device, expertise, frequency)? Capture only what
   shapes design decisions. If you asked inline because the file was absent, offer to persist them at
   the end ([Persisting personas](#persisting-personas-when-absent)).
2. **Aesthetic direction** (→ §2). The heart of the interview. Start from an optional **tone
   preset** (`controlled` / `impact` / `innovative`) as shorthand that seeds defaults, then set the
   three explicit **dials** — **variance** (conventional ↔ expressive), **motion** (still ↔
   animated), **density** (airy ↔ compact). Gather **brand references** (sites/products the user
   admires and why) and any voice/feel words. The dials are the canonical, verifiable direction
   language — see [ui-handoff-format.md](./ui-handoff-format.md) §2 for the full definitions.
3. **Screens & flows** (→ §3). Enumerate the screens/surfaces this task adds or changes; map the
   navigation / user-flow between them in text or mermaid. **Text-first** — no pixels.
4. **Per-screen layout** (→ §4). For each screen, the structural intent: regions, hierarchy, what
   draws the eye first. Words, not mockups.
5. **Components** (→ §5). Name the components and the variant/states that matter. **Graduated
   altitude**: decisions-altitude by default (name the variant + the states that matter); the full
   component anatomy ONLY for a genuinely novel or critical component.
6. **States** (→ §6). Empty / loading / error / success / edge content for the task's surfaces.
7. **Responsive** (→ §7). Breakpoint behavior that actually changes for this task.
8. **Motion / interaction** (→ §8). Motion appetite (from the dial) + the few interactions that
   carry meaning. Not an animation catalogue.
9. **Accessibility** (→ §9). Target level (default WCAG 2.1 AA) + any task-specific a11y decisions.
   The _audit_ and _how-to_ are skills — capture only decisions here.
10. **Microcopy** (→ §10). The actual words for the task's key labels/messages, **inline**. Voice
    follows §2; no separate copy artifact.
11. **Tokens** (→ §11). Point at `docs/design-tokens.json`. If the project has no token file yet,
    don't invent one mid-interview — surface it at the end as an opt-in offer
    ([Design-tokens & design-tool on-ramp](#design-tokens--design-tool-on-ramp-when-absent)); if the
    human declines, capture it as an open question.

After important branches, offer a checkpoint:

> "We've set direction, screens, and components. Three branches remain: states, responsive,
> accessibility. Keep going, prioritize, or pause here?"

## Co-creation — Socratic + proposals

When the user has no formed design opinion, NEVER leave it open. Present alternatives with
trade-offs and a recommendation:

> "For variance you have: **low** — safe, system-like, fast to build, risks generic;
> **medium** — distinctive but restrained; **high** — bold and memorable, more build cost and
> more ways to get it wrong. Recommendation: medium for an internal tool, high for a landing
> page. Which fits?"

This teaches through forced trade-off comparison rather than blind choice.

## Output — `ui-handoff.md`

The interview produces **`ui-handoff.md`** under `.claude/state/tasks/<id>/spec/`, a sibling of the
Spec Author's `requirements.md` / `design.md` / `tasks.md`. You **own** it. Use the canonical
**11-section** contract in [ui-handoff-format.md](./ui-handoff-format.md).

- A `Status:` field marks WIP vs done: `in_progress` while the design is being defined,
  `completed` when closed. **Same file**, just a different status.
- Update it **inline** as branches close — don't batch at the end.

## Persisting personas (when absent)

`docs/personas.md` is **client-owned**: the harness consumes it, never imposes it. So when the
file was **absent** and you gathered personas inline (§1 above), don't write it mid-interview — the
choice to keep a persistent user-model doc is the human's. Make it an explicit offer instead:

1. **Offer at the end.** Once the design is defined, ask on your human-facing surface whether to
   persist the inline personas to `docs/personas.md` for future tasks. Opt-in, never unasked.
2. **On yes, write a minimal `docs/personas.md`** from the personas already captured in §1 — the
   client's own words, not an invented cast. Keep it a skeleton the client can grow: one short block
   per persona (who they are, their context/device, expertise, frequency, the goals and constraints
   that shape design). Create `docs/` if absent. This is the client's real content, surfaced from
   their own answers — never a vendor template, never personas the harness guessed.
3. **On no, write nothing:** the inline personas live on in the handoff's §1 for this task, and the
   next UI task will simply ask again.

## Design-tokens & design-tool on-ramp (when absent)

`docs/design-tokens.json` and a design-tool connection are **client-owned inputs** — the harness
consumes them if present and otherwise leaves them alone, the same regime as personas. For a repo
adopting the harness fresh, that silence is a dead end: no tokens, no way in. So when either is
**absent**, don't dead-end at a silent open question — make an explicit, opt-in offer at the end, on
your human-facing surface. Never scaffold or connect unasked.

### Tokens absent → offer to scaffold

When the project has **no `docs/design-tokens.json`**, offer once, after the design is defined:

1. **Offer at the end.** Ask whether to scaffold a starter `docs/design-tokens.json` from the
   direction just defined, or keep it as an open question in §11.
2. **On yes, derive from the answers.** Build a minimal 3-tier DTCG file (`primitive` → `semantic`
   → `component`) from what the human actually stated — the colours, type, spacing and radii that
   came out of the aesthetic-direction branch (§2) and the components branch (§5). This is the
   client's own direction, surfaced as tokens — **never a vendor template**, never a palette the
   harness guessed.
3. **Offer to cover the gaps too.** The interview rarely names every token. Ask a follow-up: for the
   aspects the conversation **did not cover**, do they want a sensible **starter** set generated (a
   neutral scale, default spacing and radii) so the file is usable from day one, or only the tokens
   the answers implied? Opt-in — the human chooses how far to go, and you never pad the file unasked.
4. **Validate before closing.** After writing, run `lemony design-tokens validate` and fix anything
   it flags, so the scaffolded file is well-formed (3-tier, aliases resolve) — a scaffold that fails
   the validator is worse than none.
5. **On no, write nothing:** capture the missing token file as an open question in §11, exactly as
   before. The next UI task simply asks again.

### No design tool → offer to connect

When `docs/design-tokens.json` carries no `com.lemony.design-tool` binding — or there is no tokens
file at all — offer to **connect a design tool** (e.g. a Figma or Pencil bridge) so tokens can
round-trip between the repo and the tool:

1. **Offer, opt-in.** Ask whether to connect a design tool now, or **stay pure-code** (tokens live
   only in the repo). Most repos are happy pure-code — recommend that unless the human wants a
   visual tool in the loop.
2. **On yes,** write the `com.lemony.design-tool` binding (the provider) into `docs/design-tokens.json`
   and run the first import to bootstrap tokens from the tool. The [`design-tool-sync`](.claude/skills/design-tool-sync/SKILL.md) skill and the
   `sync-design-tokens` command own the mechanics — you point the human at them; you don't
   re-implement the bridge here.
3. **Skip gracefully.** If the tool's MCP bridge isn't connected, say so and fall back to the open
   question — never block the interview on an unavailable tool.
4. **On no, stay pure-code:** write no binding. The design tool is only ever a projection of
   `docs/design-tokens.json`, never a peer source of truth — declining costs nothing.

## Pause & Resume

Design definition is part of completing the spec, not a separate state. Pausing and resuming use
the lifecycle you already own — don't invent a parallel mechanism:

- **Pausing**: write `ui-handoff.md` with `Status: in_progress` and the sections closed so far,
  record the sub-state `awaiting design definition` in the task's `progress.md`, and park the task.
  Confirm with the user before ending the turn.
- **Resuming**: `/resume <id>` re-enters via that sub-state. Read the in-progress `ui-handoff.md`,
  confirm which sections are closed and which branch comes next, then continue.
- **Completing**: flip `Status: in_progress` → `Status: completed`, then remove the
  `harness:needs-design` flag at/before `spec-ready`.

## Tone

**Adaptive**, like the general grill. Start curious-collaborative; escalate when answers are shallow
("I don't know", "whatever looks good"); never go beyond constructive provocation. You bring taste
and conviction — push for a real direction, but the user decides.

## When the design is underspecified

If a design decision needs input the PRD left open with more than one valid answer and the user
can't resolve it in the interview, **capture it as an open question** in the handoff rather than
guess, and mark the handoff `Status: in_progress` until it is settled — never close a design on a
guessed fork.

## Cross-references

```
grill-ui → ui-handoff.md → implementer (build-ui) → REVIEW (design-critique + a11y-audit) → merge gate
```

The implementer reads `ui-handoff.md` as its obligatory design input; the REVIEW design lens checks
the built UI against it. The [`build-ui`](.claude/skills/build-ui/SKILL.md), [`design-critique`](.claude/skills/design-critique/SKILL.md), and [`a11y-audit`](.claude/skills/a11y-audit/SKILL.md) skills carry the
know-how and the audits — this skill only defines the contract.

---

See also:

- [ui-handoff-format.md](./ui-handoff-format.md) — the canonical 11-section `ui-handoff.md` contract,
  the dials + tone-preset definitions (§2), and the graduated component anatomy.
