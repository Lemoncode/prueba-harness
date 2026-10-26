---
name: bootstrap-architecture
description: 🍋 Author the first docs/architecture.md — a holistic map of the system's current shape, fitted to this project. A one-time bootstrap the Architect runs when a client opts into the architecture capability; thereafter update-architecture maintains it incrementally. The harness only does this when the human asks.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [architect]
---

# Bootstrap Architecture

## Core Principle

`docs/architecture.md` is the **living high-level map** of the system — the shape a new
engineer reads first (contexts, boundaries/ownership, integration seams, external
dependencies, data flow). This skill authors it **for the first time**: a holistic map of
the system **as it is today**, read from the actual code.

This is the one-time **bootstrap**, the opposite of the incremental [`update-architecture`](.claude/skills/update-architecture/SKILL.md):
that skill makes the smallest surgical edit after a single change; this one reads the whole
repo and writes the initial coherent map. After this lands, [`update-architecture`](.claude/skills/update-architecture/SKILL.md) (gated on
the file now existing) keeps it true incrementally.

It is **not gated** — it is available before any `docs/architecture.md` exists, because its
job is to create the first one. But the harness runs it **only when the human opts in**
(via `/add-capability`, or an explicit request), never on its own: the vendor gives the
framework, not the architecture. The map is authored **from the client's real
code**, so the harness reflects the project's shape — it never imposes one.

## What to produce

A map **fitted to this project**, not a template. The sections **emerge from the contexts
you actually find** — do **not** treat the list below as a fixed heading set to emit. These
are **lenses to look through**, not mandatory sections: cover the ones this system actually
has, drop the ones it doesn't, name them in the project's own terms. Aim for the shape, not
the detail:

- the **bounded contexts / modules** the system actually divides into, and what each owns;
- the **boundaries & ownership rules** between them ("X owns Y; others reference by id");
- the **integration seams** (sync HTTP, domain events, queues, a provider abstraction);
- the **external dependencies** that carry lock-in (a database, a broker, an auth provider);
- the **data flow** a reader would otherwise get wrong.

Keep it a **map, not a code listing**. Resist implementation detail that belongs in code,
`CLAUDE.md`, or a rule. If the project records decisions as ADRs, link the _why_
(`see ADR-NNNN`) rather than restating it — the map holds the _shape_, the ADR the _decision_.

## Process

1. **Orient over the whole repo.** Read the structure to derive the real shape — the
   top-level layout, the module/folder boundaries, the entry points, the external deps in
   the manifest, the seams between parts. Where a [`code-explorer`](.claude/skills/code-explorer/SKILL.md) map is available, start
   from it. This is a read of the **current** code, not a guess.
2. **Draft the map at the right altitude** — sections matching the contexts you found,
   each a few lines: what it is, what it owns, how it connects. Prefer a small, true map
   over an exhaustive one; the reader wants the shape.
3. **Write `docs/architecture.md`.** Create the file (and `docs/` if absent).
4. **Hand back for activation.** You do not run `repair` yourself — the map alone does not
   install the maintainer skill. Report to your invoker (the Orchestrator) that
   `docs/architecture.md` now exists, so it runs `repair`; its re-scan detects the new file
   and installs [`update-architecture`](.claude/skills/update-architecture/SKILL.md) to keep the map current. See the `/add-capability`
   command.

## Report

Return to your invoker: the sections written, a one-line summary of the shape the map now
captures, and the explicit note that [`update-architecture`](.claude/skills/update-architecture/SKILL.md) should be activated via `repair`.
If the project is too small or too uniform to have a meaningful architecture (a single-purpose
script, a flat library), **say so and write nothing** — an architecture map for a project
without architecture is noise, and the client need not have one.

## Uncontemplated Scenarios

When a case doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This isn't covered by the bootstrap-architecture skill. I did [approach]
   because [reason]. Want to refine the skill?"
3. Offer to add a rule for the case.
