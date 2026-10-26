---
name: silent-failure-hunter
description: 🍋 Hunt for silently swallowed errors and dangerous fallbacks in a change — the failures that hide bugs instead of surfacing them. Five focused passes over the diff. Use during review when a change touches error handling, async flows, or boundary parsing, before `security-review`.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [reviewer]
---

# Silent Failure Hunter

The most expensive bugs are the ones that never raise their hand. This skill is a
focused pass for **silent failures** — code that hides a problem instead of surfacing
it. The principle it enforces: **errors should fail loudly,
at the point of the problem, with a message that names it.** Make five passes over the
diff; for each finding, state the failure mode and the loud alternative.

## Pass 1 — Empty / swallowing catches

- `catch` blocks that do nothing, only `console.log`, or `return null/undefined/[]`
  without rethrowing or handling.
- `.catch(() => {})` on a promise.
- `try` wrapping logic where the `catch` masks the real failure.

> A `catch` is for _handling_ an error (recover, translate, add context, rethrow) —
> not for making it disappear. An expected no-op (idempotent retry) is fine **only**
> with a comment stating the intent.

## Pass 2 — Dangerous fallbacks

- `value ?? defaultThatHidesAbsence` / `value || fallback` where the fallback masks a
  missing-data bug instead of failing.
- Optional chaining (`a?.b?.c`) that silently yields `undefined` where the value was
  required — the bug surfaces three layers later, detached from its cause.
- `try { JSON.parse(x) } catch { return {} }` — a parse failure becomes empty data.

## Pass 3 — Inadequate logging / observability

- An error is caught and handled but **never logged**, so it's invisible in
  production.
- Logged at the wrong level (`debug`/`info` for a real error) so it's filtered out.
- The log message lacks the context to act on it (no id, no operation, no cause).

## Pass 4 — Propagation issues

- A floating promise (no `await`, no `.catch`) whose rejection is lost.
- `Promise.all` where one rejection silently aborts siblings (vs `allSettled` when
  partial success matters) — or the reverse, swallowing a failure that should abort.
- An async function whose error path returns a _success-shaped_ value.
- An error translated to a generic message that erases the original cause (no `cause`
  chain).

## Pass 5 — Missing handling at boundaries

- External/untrusted input (API response, file, env var, user input) used without
  validation, so a malformed value flows in as a silent bad state rather than a loud
  rejection.
- A `switch`/branch with no `default` for an unexpected value.
- A required env var read with a silent fallback instead of failing fast at startup.

## Report

```
## Silent Failure Hunt — <task name>

**Empty/swallowing catches**: <file:line — failure → loud fix> | none
**Dangerous fallbacks**: <…> | none
**Inadequate logging**: <…> | none
**Propagation**: <…> | none
**Missing boundary handling**: <…> | none

**Verdict**: clean / <N> silent failures to fix
```

For each finding, give the loud alternative concretely (`throw new Error(\`… ${id}\`)`instead of`return null`). If the "silent" path is intentional, it must carry a comment
saying so — absent that comment, treat it as a finding.
