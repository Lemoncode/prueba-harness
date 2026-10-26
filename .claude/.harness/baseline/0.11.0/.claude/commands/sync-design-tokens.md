---
description: 🍋 Sync design tokens between docs/design-tokens.json and the design tool (import or export).
allowed-tools: Read, Write, Edit, Bash, Task, Skill
---

# /sync-design-tokens

Sync the project's design tokens with its design tool. This command only **starts the flow** —
it does not redefine it. The authority is the **[`design-tool-sync`](.claude/skills/design-tool-sync/SKILL.md)** skill, run by the UI
Designer; follow the steps there.

`$ARGUMENTS` selects the direction:

- `import` — pull the tool's variables into `docs/design-tokens.json` (the primary flow). The
  CLI maps them to the 3-tier model and prints a diff; you present it and the human curates
  which slice lands before it is written.
- `export` — project the JSON to the tool as an additive upsert (creates and updates, never
  deletes tool-only variables). Preview the plan, push on confirmation, then record the drift
  baseline only after the push succeeds.
- _empty_ — check the drift state (`lemony status`) and, if an export is pending and the tool
  is connected, offer `export`; otherwise report the current state. `status` shows no drift
  line both when there is no token file and when the file cannot be read or fails
  validation — tell the two apart with `lemony doctor`'s `design-tool-drift` check.

The design tool is a **projection** of the canonical JSON, never a peer source of truth.
Detect the tool at runtime: read the `com.lemony.design-tool` binding at the root of
`docs/design-tokens.json`; if no tool is declared, the project is pure-code and there is
nothing to sync. If the declared tool's MCP server is not connected, skip gracefully with a
note — the deterministic drift check still works without it. When `harness.config.yml` sets
`design_tokens.file`, the path it names is the token file wherever this command says
`docs/design-tokens.json`.

The human reviews every write (to the JSON and to the tool). Never sync silently.
