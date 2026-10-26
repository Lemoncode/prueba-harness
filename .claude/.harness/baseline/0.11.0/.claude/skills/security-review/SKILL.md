---
name: security-review
description: 🍋 Security review of a change — OWASP-style vectors plus AI/LLM-specific risks. Checks input validation, authorization/IDOR, injection, secrets & logging, transport/headers, dependencies, prompt-injection where an LLM is in the loop, shell and subprocess use, money movement, destructive writes, and executable surface. Every risk class a change can be declared under names one section, and a declaration handed over with the invocation deepens that section. Use after `senior-review` on any change touching user input, auth, data access, money, destructive writes, a subprocess, file permissions, or an LLM.
origin: vendor
vendor_version: '0.11.0'
phase: post-implementation
invoked-by: [reviewer]
---

# Security Review

Review the change for security risk with **fresh context**. Scope the depth to what
the change touches — a pure refactor of internal logic needs a lighter pass than a new
endpoint or an LLM call. The checklist below is the generic floor. Flag only findings
you're confident are real, ranked by severity.

The project's own security rules (deployment model, auth scheme, secret tooling) are
Claude Code rules, and they reach you through the `Read` tool: `Read` each file the
change adds or modifies (not a lockfile or generated output) whole, not only its diff
(a `cat` brings none). A surface such as auth,
secrets or deployment can be governed by a rule scoped to other paths: when the change
reaches one, look for that rule under `.claude/rules/`, and read any reference doc a
rule cites for it. Until the project migrates its playbooks (`docs/playbooks/`), read
the ones that cover the work at hand.

## Declared risk surfaces

Your invocation may carry a **declaration**: the kind of damage this change can do, named
at the structuring moment — before a line of it was written — and approved by a human, as a
class paired with the group or the file it was declared against. When one reaches you, it
is a **floor for depth, never a bound on scope**:

- Every section below still runs. The declaration says where to press harder, not what to
  skip: it was written before the code existed, so it cannot know what the diff ended up
  touching. Deriving the surface from the change itself remains your job.
- For each declared class, go to the section whose heading carries it. Every class in the
  vocabulary names **exactly one** section below — the backticked class at the end of the
  heading (`` ## 2. Authorization … — `auth` ``) — and a guard pins that the set of classes
  in these headings and the vocabulary are the same set, so no heading ends in
  `` — `token` `` unless `token` is a class. Go deep there: read the declared file whole
  rather than sampling its diff, and follow the vector out of the change into the code it
  reaches.
- A declared class that matches **no heading** is drift between the vocabulary and this
  checklist — a guard should have caught it — not a class you may skip. Review it against
  the project's rules you received and the generic floor, and **name it in the report** as
  covered without a dedicated section, so the gap surfaces as a gap and not as silence.
- Damage the vocabulary could not name arrives as prose rather than a class — an
  `unclassified: <path> — <what it can do>` line, or the rationale of a group that left its
  tag off. That is a declaration, not a gap: take the prose as the brief and review that
  path against it.

**No declaration is not a clean bill of health.** A declaration of `none` is a claim that
the change touches no such surface; a _missing_ declaration is no claim at all — the task
may simply predate the section. In both cases scope the depth from the change itself,
exactly as you would without one, and never report a surface as absent on the strength of a
declaration alone.

## 1. Input validation at boundaries

- Every entry point (request body, query/path params, headers, file, env, third-party
  response) validates **shape, type, required-ness, and max length** before use.
- External strings are validated/converted at the boundary, not asserted into the
  internal type.
- No mass-assignment: unexpected fields are rejected, not spread into a model.

## 2. Authorization (not just authentication) — `auth`

- **Authentication** (who are you?) and **authorization** (are you allowed?) are
  distinct checks — a valid session is not permission.
- **Ownership / IDOR**: a resource fetched by id verifies it belongs to the caller. An
  auth guard never substitutes for the ownership check.
- Privileged actions check role/scope server-side, never trusting a client claim.
- **Session & token handling**: a token is verified before it is trusted — signature and
  algorithm pinned (never `none`, never caller-chosen), `exp`/`iss`/`aud` checked, claims
  never read from an unverified decode. Sessions rotate on login and privilege change,
  and logout/revocation invalidates server-side, not just client-side (cookie flags: §5).

## 3. Injection

- **SQL/NoSQL**: parameterized queries / validated ids; never interpolate user input
  into a query, never pass a raw request object to a query (object-injection).
- **Path**: a path built from user input is resolved and then proven to stay under a
  fixed base — `join`/`resolve` alone are not that proof (`join` normalizes `..` through,
  `resolve` lets an absolute segment discard the base); absolute and `..` segments are
  rejected rather than stripped, and `realpath` is used where symlinks can exist.
  Shell-command construction is §8.
- **Output/XSS**: rendered user content is escaped by default; raw-HTML sinks
  (`dangerouslySetInnerHTML`, server-generated HTML/PDF) sanitize at render time.

## 4. Secrets & logging — `secrets`

- No secret, token, password, key, or PII in code, logs, or error messages (a
  never-log redaction list is configured; emails in failure logs are hashed).
- **At rest**: a secret lives in the platform's secret store or a file only the app can
  read (0600) — never a world-readable config, an image layer, or the repo (`.env`
  gitignored; `.env.example` placeholders only). Passwords are stored under a slow KDF
  (argon2/bcrypt/scrypt), never a bare or fast hash.
- **In transit**: a secret never rides in a URL or query string (proxies, browser history
  and `Referer` capture those) — header or body over TLS only (§5) — and a leaked one has
  a rotation path that does not require a deploy.
- Constant-time comparison for secrets/tokens (no `===` on a hash); strong randomness
  for generated keys.

## 5. Transport, headers & CSRF

- Security headers present (nosniff, frame-options/ deny, HSTS in prod).
- CORS is closed by default; opened only deliberately for known origins.
- Cookie-based sessions set `httpOnly`, `secure` (prod), and `SameSite` (CSRF
  defense); token/header auth flows are not CSRF-susceptible.

## 6. Dependencies & exposure

- `npm audit` (or the ecosystem equivalent) clean at moderate+; the change adds no
  vulnerable dependency.
- No source maps served publicly in production; no debug/verbose error bodies leaking
  internals to clients.

## 7. AI / LLM-specific (when an LLM is in the loop)

- **Prompt injection**: untrusted content (user text, fetched pages, tool output) is
  treated as data, not instructions; system prompts are not overridable by user input.
- **Output handling**: LLM output is validated/escaped before it drives an action
  (code execution, a query, a shell command, a network call) — never `eval`'d or run
  unchecked.
- **Secret/PII exposure**: no secret or excessive PII placed in a prompt sent to a
  third-party model; tool/function access from the model is least-privilege.
- **Resource limits**: token/cost/loop bounds on agentic calls to prevent runaway use.

## 8. Shell & subprocess — `shell-process`

- **Argument construction**: no untrusted input concatenated into a command string;
  arguments go as an array to an exec-style API (`execFile`/`spawn` without
  `shell: true` — and on Windows a `.cmd`/`.bat` target is shell-parsed regardless),
  never through a shell. An array is not sufficient on its own: a value that can begin
  with `-` is read by the binary as a flag, so untrusted values sit after `--` or are
  validated against a known form.
- **Spawn surface**: every new subprocess is deliberate — the binary resolved from a
  known path rather than the inherited `PATH`, and the child running with no more
  privilege than the caller (no `sudo`, setuid, or elevated container).
- **Secrets across the boundary**: a secret never travels as a command-line argument —
  argv is world-readable in `ps`. It goes via the child's environment (pruned to what the
  child needs), stdin, or a file descriptor.
- **Child I/O**: the child's output is untrusted input at a boundary (§1 — and §7 as well
  if it reaches an LLM) before it drives anything; its exit code is checked, not assumed;
  and it cannot hang or flood the parent unbounded (timeout, kill, output cap).

## 9. Money, billing & pricing — `payments`

- **Idempotency**: every charge, refund, or transfer is idempotent under retry
  (idempotency key, provider-side dedup) — a replayed webhook or a double submit cannot
  move money twice.
- **Amount & currency integrity**: amount and currency come from the server-side record,
  never from the client; arithmetic is in integer minor units (no floats), the rounding
  rule is explicit, and totals are recomputed rather than trusted.
- **Bounds & entitlement**: amounts, quantities and discounts are range- and sign-checked
  server-side — no negative charge, no refund above what was captured, no coupon reused
  or stacked past its rule — and access a payment buys is granted on settled state and
  revoked when that state reverses.
- **Provider trust boundary**: webhooks are signature-verified against the **raw** request
  body (a JSON body parser mounted ahead of the route silently breaks this) and
  replay-windowed; state transitions (pending → paid → refunded) are enforced server-side
  and written to an audit trail (who, what, when).

## 10. Destructive writes & data — `data-loss`

- **Scoped deletes and updates**: every delete or bulk update carries a bounding
  predicate (tenant/owner/id) that is proven non-empty at runtime, not merely present in
  the source — an `undefined` id the ORM silently drops, or a filter built from a request
  that arrives `{}`, is a collection-wide call wearing a `where`.
- **Irreversibility**: a migration or schema change has a tested rollback, or is
  explicitly one-way and says so; a destructive data migration runs behind a
  backup/snapshot step. Soft-delete where a human may need to recover — and where it is
  used, every read path filters deleted rows and records holding personal data still
  have a real erasure path, not an indefinite tombstone.
- **Atomicity**: writes that must succeed together are transactional or idempotently
  replayable — a partial failure cannot leave data half-written and report success.
- **On disk**: a write replaces a file atomically (temp + rename), never truncates or
  deletes a path the change did not create, and never follows a symlink to do it. Any
  destructive path is proven non-empty before use — a path variable that can be empty
  turns a scoped delete into a root-relative one.

## 11. Executable surface — `executable-mode`

- **Permission changes**: no `chmod`/exec-bit change beyond what the feature needs;
  neither the file nor the directory holding it becomes world-writable (a 0755 script in
  a 0777 directory is replaceable), and no write-then-execute path — a file the app
  writes is never later executed without a trust decision.
- **Install-time surface**: files laid down by an installer or updater carry the minimum
  mode; a hook or script that gains executable mode is reviewed as code that runs, not
  as data.
- **What can run**: a change to what the system executes unattended — a new entry point,
  hook, cron or launch agent, service unit, `postinstall`, or a changed interpreter
  shebang — is named in the report with who can write to it and what triggers it, even
  when it looks routine. How this change spawns a process is §8.

## Report

```
## Security Review — <task name>

**Declared surfaces**: <class → where you pressed> | none declared | no declaration handed over
**Critical**: <vector — file:line — fix> | none
**High**: <…> | none
**Medium**: <…> | none
**Low / hardening**: <…> | none

**Verdict**: no blocking issues / <N> issues to fix before merge
```

A finding that the **spec** mandated an insecure approach is a **discovery** (the spec
needs a human decision) — run [`raise-discovery`](.claude/skills/raise-discovery/SKILL.md) rather than silently complying.
