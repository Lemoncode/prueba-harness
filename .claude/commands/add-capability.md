---
description: 🍋 Activate an opt-in capability the repo reported as available — e.g. have the Architect bootstrap docs/architecture.md so update-architecture installs.
allowed-tools: Read, Bash, Task
---

# /add-capability

Activate an **opt-in** capability that `install`/`doctor` reported as _available but not
installed_. The harness reports these latent capabilities but never creates the
convention artifact on its own. This command is the **user-initiated**
"yes, add it" — it has the right agent author the artifact, then re-syncs so the gated
skill installs.

One command for **all** capabilities (no command-per-capability sprawl): it lists the
latent ones and dispatches to each one's activation behaviour.

`$ARGUMENTS` may name a capability (or its trigger file); if empty, discover and offer the
latent ones.

## Procedure

1. **Discover the latent capabilities.** Run the read-only doctor and read its
   `capabilities` check:

   ```bash
   .claude/hooks/lib/lemony.sh doctor
   ```

   If it reports **all applicable capabilities are active** (or none latent), say so and
   stop — there is nothing to add (an existing artifact means the capability is already on).

2. **Pick the capability.** Use `$ARGUMENTS` if it names one; otherwise list the latent
   capabilities the check named and ask the user **one** question — which to activate.

3. **Dispatch to the activation behaviour:**

   - **The architecture map** (`docs/architecture.md` absent → [`update-architecture`](.claude/skills/update-architecture/SKILL.md)
     latent): dispatch the **Architect** (Task tool, fresh context) with the
     **[`bootstrap-architecture`](.claude/skills/bootstrap-architecture/SKILL.md)** skill. It reads the repo and authors the first
     `docs/architecture.md` — a holistic map **fitted to this project**, read from the
     actual code, never a vendor template. When it returns, show the human
     its summary and the new file — they own the result and may edit it. If the Architect
     reports the project has no meaningful architecture to map, it writes nothing: relay
     that to the user and **end the command** — skip step 4, force nothing.

   - **Any other latent capability**: it has no guided activation. Say so plainly and
     **end the command** — do **not** fabricate the artifact. (Guided activation beyond
     the architecture map is a deliberate non-feature, not a pending seam; wiring one up
     for a future capability is its own decision.)

4. **Re-sync so the gated skill installs** — only when step 3 actually wrote the artifact.
   Run:

   ```bash
   .claude/hooks/lib/lemony.sh repair
   ```

   `repair` re-syncs at the pinned version (preserving client edits, no version bump); its
   re-scan detects the new artifact and installs the now-unlocked skill (e.g.
   [`update-architecture`](.claude/skills/update-architecture/SKILL.md)). Report what is now active in one line.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by /add-capability. I applied [approach]
   because [reason]. Want to update the command?"
3. Offer to add a new rule for the case.
