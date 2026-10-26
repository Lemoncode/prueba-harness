---
name: test-gap-report
description: 🍋 Structural test-gap analysis of a change — which logic-bearing files lack a dedicated test, and which behaviors are untested. Walks the coverage matrix, not the runtime. Use during review to find missing tests before they become regressions; distinct from `verify` (which runs the suite) and `senior-review` (which judges the tests that exist).
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [reviewer]
---

# Test Gap Report

A **structural** gap analysis: which files in the change _should_ have a dedicated test
and don't, and which behaviors are untested. This is separate from [`verify`](.claude/skills/verify/SKILL.md) (which
_runs_ the suite) and from [`senior-review`](.claude/skills/senior-review/SKILL.md) (which judges whether the tests that exist
are meaningful). Coverage numbers are a weak proxy — this walks the **coverage matrix**
by file role instead.

## Process

### 1. Classify each changed file

For every file the change adds or modifies, `Read` it whole, not only its diff, and
decide whether it needs a dedicated test using the coverage matrix. The `Read` tool
also brings the project's rules for that path (Claude Code injects each
`.claude/rules/` file whose `paths:` cover it; a `cat` brings none), which may name
roles of their own; for a test the change should have added,
`.claude/hooks/lib/lemony.sh rules match --path=<path>` names the rules for its path:
`Read` those. Until the project migrates its playbooks (`docs/playbooks/`), read the
ones that cover the work at hand. The matrix:

**Always needs a dedicated `*.spec.*`** (it carries logic — conditionals, loops,
transformations, calculations):

| Role                      | What to cover                                          |
| ------------------------- | ------------------------------------------------------ |
| service / use-case        | happy path, expected errors, edge cases                |
| mapper / transformer      | every field, optional/nullable, empty collections      |
| helper / util / validator | boundary values, error conditions                      |
| hook                      | state transitions, side effects, cleanup               |
| component                 | renders expected content, interactions, conditional UI |
| processor / reducer       | each input/event type, unknown input                   |

**Covered by integration (no dedicated spec needed)** — wiring, not logic:
type-only models, thin route/api wrappers, simple stores, constants, config. A file
here with **branching logic** is promoted to "always test."

### 2. Find the gaps

For each file in the "always" set:

1. Does a co-located `*.spec.*` exist?
2. If yes, does it cover the **behaviors** the change introduced (not just the ones
   that were already there)? A new branch / error path / edge case added by this change
   needs a new test even if the file already had a spec.
3. **User-visible flows** (navigation / form / list / auth) added or modified → is
   there an E2E test, or is one warranted per the project's rules for its end-to-end
   specs (`rules match` on such a path)?

### 3. Report

Destination: the full-pass **issue comment**. In your return summary — and on a
per-step review that added this pass, which posts no comment — carry only the counts +
the gaps, per
the Reviewer's verdict-size rule (a REJECT lifts the cap entirely).

```
## Test Gap Report — <task name>

| File | Role | Spec? | Gap |
| --- | --- | --- | --- |
| `order.service.ts` | service | ✅ | error path for empty cart untested |
| `slug.util.ts` | util | ❌ | no spec — boundary cases untested |
| `cart.view.tsx` | component | ✅ | covered |

**Missing specs**: <n>  ·  **Partial coverage**: <n>
**E2E**: needed / present / N/A
**Verdict**: adequately covered / <n> gaps to close
```

Report gaps; do **not** silently write the missing tests yourself (that's the
Implementer's loop). A gap is a finding routed back. If closing a gap reveals the
behavior itself is unspecified, that's a **discovery** — run [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md).
