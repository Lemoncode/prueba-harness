---
name: design-tool-sync
description: 🍋 The token sync connector between the canonical design-tokens.json and a design tool (Figma, Pencil, or any variables-capable tool). Provider-agnostic and runtime-detected — the tool is a projection of the JSON, never a peer source of truth. import pulls tool variables into the 3-tier JSON (human-curated); export projects the JSON to the tool as an additive upsert that never deletes. Use when syncing tokens with a design tool, or when a drift check shows an export is pending.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [ui-designer]
---

# Design-Tool Sync

Keep the design tool and the canonical `docs/design-tokens.json` in step — tokens only. The
JSON is the **single source of truth**; the design tool is a **projection** of it that can run
ahead. That asymmetry shapes everything here:

- **`import` (tool → JSON)** is the primary flow and **human-curated**: the tool cannot
  silently overwrite the source of truth, so you present the diff and the human picks the
  slice that lands.
- **`export` (JSON → tool)** is an **additive upsert**: it creates and updates variables but
  **never deletes** a tool-only variable. The JSON leads; the tool catches up.
- **drift** is one-directional and deterministic: "has the JSON changed since the last
  export?" — a pure-JSON check that needs no tool connection.

**Which file.** `docs/design-tokens.json` is the default path. When `harness.config.yml` sets
`design_tokens.file`, the path it names (relative to the repository root) is the token file:
read the binding from it and expect the CLI's import and export to act on it, wherever this
skill says `docs/design-tokens.json`. Never create a second file at the default.

You are invoked two ways: by `/sync-design-tokens` (the human's explicit handle, argument
`import` or `export`), and at DEFINE when the drift check shows an export is pending and the
current user has the tool connected.

## Detect the tool (runtime, detect-or-skip)

There is no per-provider configuration baked into the harness. Detect at runtime:

1. Read the binding at the root of `docs/design-tokens.json`:
   `$extensions["com.lemony.design-tool"]` → `{ "provider": "<tool>", "lastProjected": "<hash>" }`.
   A declared `provider` means the project syncs; **no binding means the project is pure-code
   — there is nothing to sync, stop here.**
2. Confirm the declared tool's MCP server is actually connected in this session. If the
   provider is declared but its MCP server is **not** available (a teammate's tool, a CI run,
   a disconnected session), **skip gracefully**: say so in one line and do nothing. The
   deterministic drift check still works without the tool, so detection never blocks.

You bridge the tool's MCP and the deterministic CLI. The CLI never talks to the tool; **you**
read and write tool variables over MCP and shuttle them through a provider-neutral file.

## The neutral file (the bridge)

Your per-provider adapter normalizes the tool's variables into one provider-agnostic shape the
CLI consumes (and produces). It is a third representation, distinct from both the tool's raw
variables and the DTCG JSON:

```json
{
  "schemaVersion": 1,
  "provider": "<tool>",
  "variables": [
    { "name": "primitive.color.brand", "type": "color", "value": "#3b82f6" },
    {
      "name": "semantic.color.text",
      "type": "color",
      "ref": "primitive.color.brand"
    },
    {
      "name": "semantic.color.surface",
      "type": "color",
      "value": "#ffffff",
      "modes": { "dark": "#000000" }
    }
  ]
}
```

- `name` — the variable's dotted path. Map it to/from the tool's own grouping separator.
- `value` for a literal; `ref` for an alias (the name of the variable it points at).
- `modes` — per-theme overrides (the base theme is `value`/`ref`, not repeated).
- Every `value` and mode value is a **string** — `"1024"`, not `1024` — and every `ref` a
  non-empty one; each variable carries a `value` or a `ref` (a `value` beside a `ref` is
  ignored), and `modes` is an object whose mode names are not blank nor `__proto__`. A name
  is dot-separated segments, none empty, none starting with `$`, none `__proto__`, not just
  a tier (`primitive`, `semantic`, `component`), and no two variables share one. The CLI
  refuses a file that breaks any of these, naming the variable (and the mode, for a mode
  value).

The CLI maps this to the 3-tier DTCG model: `ref` → an alias `{path}`, `modes` →
`$extensions["com.lemony.modes"]`, and the tier follows the path. A name without a tier
lands on the one tier `docs/design-tokens.json` already has it in; otherwise a variable that
is literal in every mode defaults to `primitive`, and one that is an alias in its base value
or any mode to `semantic` (a primitive is literal in every mode). A bare `ref` — or a bare
`{alias}` mode value — resolves to the tiered path its target lands at in the same neutral
file, or to the one tier the token file has it in.

## import — tool → JSON

1. **Read** the tool's variables over MCP and write them to a neutral file (a temp path).
2. **Preview** the diff (writes nothing):
   `lemony design-tokens import --from=<neutral-file>`. It prints, per token, the target tier
   and `new` / `changed` (each thing that changes, old → new: the value, the `$type`, each
   mode) / `unchanged`. When
   `docs/design-tokens.json` already fails validation it adds a `Warning:` saying so: the
   apply will refuse any slice that leaves it failing, so tell the human before curating.
3. **Present and curate.** Walk the human through it: which new tokens to take, which changes
   to accept, and — where a tool-origin name is ambiguous — whether a literal belongs in
   `primitive` or `semantic`. The human owns the slice.
4. **Apply** the agreed slice:
   `lemony design-tokens import --from=<neutral-file> --apply --only=<dotted,paths>`.
   This does the additive merge into `docs/design-tokens.json` deterministically (it
   bootstraps the file if it does not exist yet and the slice writes something). A changed
   token keeps what the neutral file does not carry — `$description`, a contrast pairing,
   other extensions — and an unchanged one is left as it is. A token the tool cannot hold
   (see export) is never written over: the preview shows it as a change from
   `(outside the sync: <why>)`, and the apply lists it as not applied. It writes nothing
   when the merged file would fail validation — typically a `semantic` alias whose
   `primitive` target is neither in the file nor in the slice: add the target to the same
   `--only`, or fix the file first. When the neutral file does not carry the target at
   all, the refusal says so: create it in the tool first, or leave out what references
   it. A fault no slice fixes, such as a `primitive` that aliases, is named the same way:
   fix that variable in the tool, or leave it out. An `--only` path no variable lands at
   is refused rather than skipped. A refusal prints the preview again, so the slice can be
   re-curated from the paths it lists. Then run `lemony design-tokens validate` to confirm
   the result is well-formed.

## export — JSON → tool

1. **Plan.** `export` refuses (exit 1) a `docs/design-tokens.json` that fails
   `lemony design-tokens validate` — fix the file first. Read the tool's current variables
   over MCP into a neutral file, then:
   `lemony design-tokens export --tool-state=<tool-state> --out=<projection-file>`. It prints
   the additive upsert plan (how many to create, how many to update — **never any deletes**)
   and writes the projection the tool should hold to `<projection-file>`. The `--tool-state`
   is optional; without it every variable is planned as a create (the upsert is idempotent by
   name either way). A tool variable named without its tier (`color.brand`) is matched to the
   path `import` lands it at (`primitive.color.brand`), so when you push, write into that
   existing variable rather than creating a tiered twin. A token a tool variable cannot hold
   is not projected: a composite (a shadow, a typography, a cubic Bézier — an object or
   array `$value`), a token whose modes the neutral format cannot carry (a mode value that
   is not text, a number or a boolean, a blank or `__proto__` mode name, a modes extension
   that is not an object), and any alias to one of those. The plan names each as "not
   projected", with why — say so to the human. `--out` takes a file path (not a pipe, nor
   the token file itself).
2. **Confirm.** Show the plan; the human approves.
3. **Push.** Write the projection's variables into the tool over MCP — create new ones, update
   changed ones, leave tool-only variables untouched.
4. **Record — only after the push succeeds.** `lemony design-tokens export --record` stamps
   the drift baseline (`lastProjected`) so `status`/`doctor` report in sync. If the push
   failed, do **not** record: the file correctly keeps reporting an export is pending.

## Drift and degradation

- `lemony status` and `lemony doctor` surface an **export-pending** state (the JSON moved past
  the last projection). This is deterministic and needs no tool — it works in CI.
- A declared-but-unavailable tool is never an error: skip with an informational note and let
  the deterministic gates carry on.

## Known limit (MVP)

Export is **additive**: it does not propagate JSON-side deletions or renames to the tool. A
variable removed or renamed in the JSON leaves its old counterpart in the tool — clean that up
by hand. This is rare and deliberate: the safe default is to never delete a designer's work.
Visual/screen sync is out of scope — this connector is tokens only.
