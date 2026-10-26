---
name: verify
description: 🍋 Mechanical verification of a change — the "does it work?" gate. Runs build, type-check, lint, tests + coverage, and dependency audit, then exercises the real code path. Use before signaling a change done (Implementer) and at the start of review (Reviewer, fresh context). Pairs with `senior-review`, which judges quality.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [implementer, reviewer]
---

# Verify

The "**does it work?**" gate: a fixed, mechanical sequence with a pass/fail verdict.
No judgment — that is [`senior-review`](.claude/skills/senior-review/SKILL.md)'s job. The **Implementer** runs `verify` before
signaling a change done; the **Reviewer** runs it again first thing, with fresh
context, because re-running the gates yourself is the anti-bias point — never trust
that they passed.

## Detect the ecosystem first

The gates are **language-agnostic**; only the commands differ. Read the project to
pick them — do not assume Node:

| Manifest present               | Ecosystem                              | Gate commands (typical)                     |
| ------------------------------ | -------------------------------------- | ------------------------------------------- |
| `package.json`                 | **Node/TS** (the worked example below) | `node --run <script>`                       |
| `pyproject.toml` / `setup.cfg` | Python                                 | `ruff`, `mypy`, `pytest`                    |
| `go.mod`                       | Go                                     | `go build`, `go vet`, `go test`             |
| `Cargo.toml`                   | Rust                                   | `cargo build`, `cargo clippy`, `cargo test` |

Prefer the project's declared scripts/tasks over raw tool invocations (a
`package.json` `scripts` entry, a `Makefile` target, a `justfile` recipe) — they
encode the project's intended flags.

## The gate sequence — stop at the first failure

Run in order; a failure halts the sequence (a green later gate is meaningless if an
earlier one is red). Node/TS shown as the worked example:

1. **Build** — `node --run build` (skip if the project has no build step, e.g. a
   pure app run with `tsx`).
2. **Type-check** — `node --run check-types` (`tsc --noEmit`).
3. **Lint** — `node --run lint` (oxlint). Warnings are not failures unless the
   project treats them as errors.
4. **Tests + coverage** — `node --run test` (`vitest run`). Run with coverage when
   the project exposes it (`node --run test:coverage`); coverage is reported, not a
   hard gate (no thresholds unless the project sets one).
5. **Audit** — `npm audit --audit-level=moderate` (or the ecosystem's equivalent).
   Report advisories; a moderate+ vulnerability introduced by this change is a
   finding.

## Execution — exercise the real path

Type-checks and a green suite do not prove the code runs. Identify the project's
**archetype** (from its manifest/deps) and exercise it for real:

| Archetype         | How to exercise                                                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Backend / API** | Start the service; hit the affected endpoint with `curl` / an HTTP client; inspect the response and the server logs.                                                    |
| **Frontend SPA**  | Start the dev server; drive the browser to the changed view; verify rendered output and the console (no errors). Browser specifics → the project's skill for it, below. |
| **SSR**           | Start the server; request the affected route; verify the rendered HTML and that hydration runs without console errors.                                                  |
| **CLI**           | Run the command on a real fixture; check stdout/stderr and the exit code.                                                                                               |
| **Library**       | Call the public API on a fixture, or import the built artifact; confirm exports resolve.                                                                                |
| **Worker / job**  | Trigger the job; observe the side effect (queue, DB row, emitted event).                                                                                                |
| **Monorepo**      | Do the above for the **affected** package(s) only.                                                                                                                      |

The exact launch command is the project's, not the harness's — infer it from the
manifest scripts. When the project has a client skill for running or exercising it
(under `.claude/skills/`, found by its description), invoke it and follow its
launch/browser steps. Until the project migrates its playbooks (`docs/playbooks/`),
read the ones that cover the work at hand. Check both the happy path and the error
output (unexpected warnings/errors even when the happy path worked).

## Report

```
## Verify — <task name>

**Build**: ✅ / ❌ / N/A
**Type-check**: ✅ / ❌
**Lint**: ✅ / ⚠️ <warnings>
**Tests**: ✅ <N passing> / ❌ <failure>
**Coverage**: <reported, or N/A>
**Audit**: ✅ / ⚠️ <advisories>
**Execution**: ✅ <archetype + what was exercised> / ❌ <what broke>

**Verdict**: works / does not work — <one-line reason>
```

This block is your working record; a capped return summary condenses it to the
verdict line (plus any ❌ detail — failures are signal, never trimmed).

On a failure, read the **full** error, find the origin (not where it surfaced), fix
the root cause, and re-run from the failed gate. If a failure reveals the spec itself
is wrong or silent, that's a **discovery** — run [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md), don't paper over
it.
