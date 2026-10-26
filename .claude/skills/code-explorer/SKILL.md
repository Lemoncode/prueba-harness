---
name: code-explorer
description: 🍋 Systematically map a large or unfamiliar codebase and return a structured orientation — entry points, modules, data flow, conventions, and the seams where bugs live. Read-only; it explores and reports, it never edits. Use when the Architect (or another agent, via the Orchestrator) needs to get oriented before a decision, a spec, or a deep change in a codebase no one has in context.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [architect]
trigger-condition: orienting in a large or unfamiliar codebase
---

# Code Explorer

## Core Principle

Before you can decide, spec, or change anything safely in an unfamiliar codebase, you
need a map. This skill produces that map: a structured, evidence-based orientation a
fresh sub-agent can build on. It is **read-only** — it reads, traces, and reports; it
never edits. Its value is the same fresh-context anti-bias as any sub-agent: it sees the
code as it is, not as someone hoped it was.

## Process

Work outside-in. Cite real paths and symbols — an orientation that can't be checked is
worthless.

**Start from the map if there is one.** If the repo keeps `docs/architecture.md`, read it
first — it is the maintained high-level map of the system's shape (contexts, boundaries,
seams). Use it as your baseline: don't re-derive what it already states; deep-dive only
where it is thin or stale for the question at hand. If it is **absent**, map from scratch
as below — and never suggest creating it (it is the client's choice). When the
map contradicts the code in an area you read (the map says X, the code does Y), call out the
staleness in your report's **Notes** so the Architect (your invoker, who owns the map) can
reconcile it via [`update-architecture`](.claude/skills/update-architecture/SKILL.md) — don't silently trust either side.

1. **Frame the question.** What is the exploration _for_? "Where does auth happen?",
   "How does a request flow end to end?", "Is there already a solution to X?" Scope the
   sweep to the question — don't map the whole repo when one slice is asked for.
2. **Find the entry points.** The manifest (`package.json` scripts, `bin`, `main`), the
   server bootstrap, the route table, the CLI dispatcher, the test setup. These anchor
   everything else.
3. **Map the modules and their boundaries.** The top-level structure, what each
   significant module owns, and how they depend on each other. Note the **seams** —
   where modules talk (HTTP, events, shared state, serialization). Most bugs live here.
4. **Trace the critical path(s).** Follow the one or two flows the question cares about
   from entry to effect (request → handler → service → store → response). Name the files
   and functions on the path.
5. **Read the conventions.** Naming, file layout, error handling, the test strategy,
   and any `CLAUDE.md` / `CONTEXT.md`, rules (`.claude/rules/`) and reference docs
   (`docs/reference/`) the repo already documents. An agent
   that follows existing conventions is far less likely to raise a false discovery.

## Report

A concise orientation, not a file dump — the conclusion, with paths to verify it:

```
## Code map — <scope of the exploration>

**Entry points**: <files/commands>
**Key modules**: <module → what it owns> (the few that matter)
**Critical path**: <entry → … → effect, with file:symbol references>
**Seams**: <module boundaries / integration points; where to test first>
**Conventions**: <naming, layout, error handling, test strategy, docs that exist>
**Notes for the task**: <existing solutions, risks, open questions>
```

If the exploration surfaces a genuine T1–T6 case (e.g. the change already exists —
T4 EXISTING_SOLUTION, or the codebase makes the plan infeasible — T5), that's a
**discovery**: run [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) rather than burying it in the report.

## Uncontemplated Scenarios

When a case doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This isn't covered by the code-explorer skill. I did [approach] because
   [reason]. Want to refine the skill?"
3. Offer to add a rule for the case.
