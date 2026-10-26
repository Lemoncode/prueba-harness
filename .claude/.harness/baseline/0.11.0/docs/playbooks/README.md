# Playbooks

> **Retiring.** Lemony 0.12.0 removes the playbook machinery: the hooks that enforce
> playbooks stop, and the global layer below goes away with nothing to replace it. Your
> files stay; nothing reads them. Conventions now live in Claude Code's own channels:
> rules (`.claude/rules/`), client skills (`.claude/skills/`) and reference docs
> (`docs/reference/`). Move this folder's playbooks into them with
> `/import docs/playbooks/` (or the directory `paths.playbooks` names) in a Claude Code
> session: it shows a plan and writes nothing until you approve it. Until 0.12.0 the hooks
> keep enforcing them as described below.

This folder holds your project's **playbooks** — project-agnostic documents describing
*how to build* a category of software here (a backend service, an SPA, a testing
strategy, a release flow). Agents read them as canonical patterns while implementing and
reviewing.

Playbooks are **yours**. The harness defines *where to look* and *the format*; it ships
**no** playbook content (you own your architecture). This file documents the lookup
convention — it is safe to keep, edit, or replace.

## The lookup convention

A playbook is found by its **topic filename**, `<topic>.md`, across two layers:

1. **Project-local** — `docs/playbooks/<topic>.md` (here). Committed with the repo.
2. **Global** — your personal, generic playbooks at `~/.claude/playbooks/` (default).

> Both locations are **configurable** in `harness.config.yml`: `paths.playbooks`
> (repo-relative) moves this local layer, `paths.playbooks_global` (absolute or
> `~`-based) moves the global one. The hooks read those keys on every fire, so a
> change takes effect immediately — no install or restart. Leave a key unset to
> keep the default. Both keys are deprecated: 0.12.0 removes them, and `lemony doctor`
> warns on a value other than the default.

Lookup is **local → global**, and a **local file overrides** the global one for the same
topic. There is **no index or manifest** — the filename *is* the registry (an index only
drifts out of sync). A missing playbook is **not an error**: skills that consult one
degrade gracefully when it's absent.

Common topics: `run.md` (how to launch the app), `testing.md`, `e2e.md`, `<stack>.md`.
Use whatever topic names your skills and team reach for.

## Enforcement (P5 slice 2)

Two Claude Code hooks read this folder on every turn:

- **`require-playbook.sh`** (`PreToolUse` on `Write`/`Edit`) — blocks the call when the
  target file path matches a playbook's `applies_to` glob list and that playbook has not
  been read in this conversation. The block message names the exact playbook(s) to read
  and the path. After reading, the agent retries the Write/Edit.
- **`suggest-playbook.sh`** (`UserPromptSubmit`, non-blocking) — emits a
  `<system-reminder>` when the prompt matches a playbook's `keywords` regex list and
  that playbook has not been read yet.

A playbook already here is picked up on the hooks' next fire (no install/restart); a new
convention goes to the native channels instead (see "Capturing new conventions").

> **Where they live / how to verify.** These hooks are installed in **this project's**
> `.claude/hooks/` and wired in `.claude/settings.json` (`PreToolUse` / `UserPromptSubmit`)
> — **not** in your global `~/.claude/hooks/`. To confirm enforcement is active, run
> `lemony doctor` (its `hooks` check reports it) or inspect `.claude/settings.json`.
> Checking `~/.claude/hooks/` gives a **false negative**. Note that a playbook with only
> `keywords` (no `applies_to`) is suggest-only **by design** — it never blocks a Write/Edit.

## Format at a glance

```markdown
---
name: testing
applies_to:
  - "**/*.spec.ts"
  - "**/*.bench.ts"
keywords:
  - "vitest"
  - "test runner"
status: active
---

# Testing

(canonical patterns here…)
```

- `name` (required) — kebab-case, equals the filename stem.
- `applies_to` (optional) — bash globs. **Files matching any glob require this playbook.**
- `keywords` (optional) — case-insensitive regexes (Oniguruma). **Prompts matching any regex suggest this playbook.**

`applies_to` and `keywords` are independently optional: a playbook can be require-only,
suggest-only, both, or neither.

## What belongs here (and what doesn't)

A playbook is **project-agnostic**: it uses placeholder names (`@org/x`, `<your-app>`,
`getResourceById`) and describes the *pattern*, never this codebase's real symbols.

Project-**specific** rules — a business rule, a quirk of one app, a one-off integration —
do **not** go in a playbook. They belong in `CLAUDE.md`, a project-local ADR
(`docs/adr/`), or `CONTEXT.md`.

## Capturing new conventions

New conventions go straight to the native channels, not here:

- write a rule, client skill or reference doc yourself, or
- ask the **Architect** to capture a pattern the code already follows: its
  [`extract-conventions`](.claude/skills/extract-conventions/SKILL.md) skill drafts it, and `/import` turns the draft into rules, client
  skills and reference docs. A spec that collides with a convention is a
  `T6 CONVENTION_CONFLICT`, which its [`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) skill resolves. The Architect
  proposes; you decide.
