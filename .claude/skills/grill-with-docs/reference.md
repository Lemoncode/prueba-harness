# Grill With Docs — Reference

## PRD Output Template

Save to `./docs/prds/<topic>-<date>.md`. Create `docs/prds/` lazily if it doesn't exist.

**Same file for WIP and final** — distinguished only by the `Status:` field:

- `Status: in_progress` while the grill is paused. The file includes the **WIP-specific sections** described below alongside the structured template.
- `Status: completed` when the grill closes. The WIP-specific sections are removed; their content gets distributed into the structured sections (User Stories, Decisions, etc.).

**Fallback path**: `~/.claude/plans/<slug>-<date>.md` — used ONLY when there is genuinely no project workspace (see the narrow rule in SKILL.md: the mere absence of git or of a `docs/` folder is NOT a reason to fall back — ask if unsure). The file structure is identical; only the location differs.

```markdown
# PRD: <topic>

**Date**: YYYY-MM-DD
**Mode**: validation | co-creation
**Status**: in_progress | completed

## Problem Statement

<!-- What problem does this solve? From the user's perspective. -->
<!-- What was discovered from codebase exploration. -->

## User Stories

<!-- Extensive list covering all aspects of the feature. -->

1. As a <actor>, I want <feature>, so that <benefit>

## Product / UX Decisions

<!-- User-facing decisions with reasoning. -->

- **<Decision area>**: <choice> — because <reasoning>

## Technical Decisions

<!-- Technical decisions with reasoning. -->

- **<Decision area>**: <choice> — because <reasoning>

## Testing Decisions

<!-- What to test and how, per area. -->

- **<Area>**: <what to test and approach>

## Out of Scope

<!-- Explicitly excluded to prevent scope creep. -->

- <Thing that will NOT be addressed>

## Discarded Alternatives

<!-- Options considered and rejected, with reasons. -->

- **<Alternative>**: discarded because <reason>

## Assumptions

<!-- Things assumed true but not validated. -->

- <Assumption that could change and invalidate decisions>

## Risks

<!-- Concerns flagged during the grill, not decisions. -->

- <Risk and its potential impact>

## Open Points

<!-- Branches not explored or unresolved. -->

- [ ] <Open point to explore in the future>

## Next Steps

- [ ] Hand off to the Spec Author (`prd-to-spec`) to turn this PRD into a spec.
- [ ] <Other actions if needed>
```

### Status values

- `in_progress` — grill paused, can be resumed.
- `completed` — all branches resolved or user said enough.

### WIP-specific sections (only present while `Status: in_progress`)

While the grill is paused, the PRD file ADDS these working sections at the top (between frontmatter and the structured sections). They coexist with whatever structured content is already filled in:

````markdown
## Decisions closed

| #   | Decision | Value | Why |
| --- | -------- | ----- | --- |
| 1   | ...      | ...   | ... |

## Open decisions — priority order

1. **<Branch>**: <where we are, what's pending>.
2. ...

## Side tasks pending

<!-- Things that need doing before/after fully closing: refactors, file moves, hook installs -->

- ...

## Resume prompt

Exact prompt for next session:

```
grill-with-docs — resume <topic>. Read ./docs/prds/<topic>-<date>.md. Start at decision #N. Keep grilling mode — one question at a time, do NOT auto-decide.
```
````

When the grill completes (`Status: completed`): distribute the content from these working sections into the structured PRD sections (User Stories, Decisions, etc.) and remove the WIP-only sections. Same file.

---

## Question categories

### Product / UX questions

Push the user beyond technical thinking:

- **User**: Who uses it? What problem? How do they solve it today?
- **Flow**: Happy path? Mistakes? How to go back?
- **User edge cases**: Abandoned mid-flow? Poor connection? Mobile?
- **Value**: Why this over the alternative? The "aha moment"?
- **Prioritization**: If only one thing, what? What postpones?
- **User stories**: For each decision, "As a X, I want Y, so that Z".

### Technical questions

- **Functional gaps**: What if X happens and it's not handled?
- **Trade-offs**: Chose A, why not B? Volume / load?
- **Technical edge cases**: Connection drops? Corrupted data? Concurrency?
- **Scalability**: 10 users vs 10k vs 10M?
- **Alternatives**: Considered Z instead of Y? Gain / lose?
- **Security**: Malicious user does X — protection?
- **Operations**: Deploy? Monitor? Rollback?
- **Testing**: What deserves tests? Approach? What NOT to test?

### Strategic / commercial questions (use when productizing)

- **Unit economics**: Cost per use? Pricing? Margin?
- **Onboarding cost**: How long to install for new customer? What does that imply for pricing?
- **TAM constraints**: Are there segments excluded (privacy, residency, regulation)?
- **Anti-copy**: What stops a competitor or customer from copying?
- **Lock-in**: What makes the customer stay? What makes them leave?
- **Failure modes**: Where does the product NOT serve well? Documented?

### Meta questions (both modes)

- **Assumptions**: What are you assuming? What if false?
- **Dependencies**: What must exist first? Who else affected?
- **Simplification**: Simpler version delivering 80% of value?
- **Scope**: Explicitly out? Looks in-scope but shouldn't be?

---

## Tone calibration

### Level 1 — Curious-collaborative (default)

> "Interesting that you chose JWT. What led you to that decision?"

Use when: user engaged, thoughtful answers, thinking actively.

### Level 2 — Challenging

> "You say JWT, but your app is monolithic without inter-service comms. Do you actually need stateless tokens or does it add complexity without value?"

Use when: surface-level answers, conventional wisdom without reasoning.

### Level 3 — Provocative-constructive

> "Why JWT? Give me a real reason, not 'because everyone uses it'. Server-side sessions with Redis solve your case with half the complexity."

Use when: shallow answers persist, user needs a strong push.

**Never go beyond level 3.** Always constructive.

### Escalation signals

- _"I don't know"_ → present options with trade-offs, don't just push.
- _"Because it's standard"_ → challenge with concrete alternative.
- Thoughtful but incomplete → follow up on the gap.
- Deep, well-reasoned → acknowledge and move to next branch.

---

## Documentation grounding — when to write what

| Artifact                  | When to touch                                                         | Where it lives                                                                        | Format                                                                            |
| ------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `CONTEXT.md`              | A domain term is clarified or a new term emerges                      | Repo root (or per-context if multi-context)                                           | [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md)                                          |
| `CONTEXT-MAP.md`          | Multiple contexts emerge in the same repo                             | Repo root                                                                             | See CONTEXT-FORMAT.md                                                             |
| `NNNN-slug.md`            | All three triggers met: hard-to-reverse + surprising + real trade-off | `docs/adr/`                                                                           | [ADR-FORMAT.md](./ADR-FORMAT.md)                                                  |
| PRD (this skill's output) | Continuously during the grill                                         | `./docs/prds/<topic>-<date>.md` (or `~/.claude/plans/<slug>-<date>.md` if no project) | Template above. `Status: in_progress` while WIP, `Status: completed` when closed. |

Create directories lazily — `CONTEXT.md` only when the first term is captured, `docs/adr/` only when the first ADR is needed.

---

## Cross-references with other skills

In the harness, the grill output (PRD) feeds the Spec Author:

```
grill-with-docs → PRD → prd-to-spec → spec (requirements/design/tasks) → spec-to-issue → GitHub issue
```

| Scenario                                         | Next skill                                                             |
| ------------------------------------------------ | ---------------------------------------------------------------------- |
| PRD completed → needs a spec                     | [`prd-to-spec`](.claude/skills/prd-to-spec/SKILL.md) (Spec Author)     |
| Spec ready → needs the externalized GitHub issue | [`spec-to-issue`](.claude/skills/spec-to-issue/SKILL.md) (Spec Author) |
| Bug spotted during grilling                      | [`triage-issue`](.claude/skills/triage-issue/SKILL.md)                 |

Mention the relevant option in the "Next Steps" section of the PRD.

---

## What this skill explicitly does NOT do

- **It does NOT auto-decide.** Every decision goes through `AskUserQuestion`. Recommendations live INSIDE options, not as closed decisions in the plan.
- **It does NOT close the plan unilaterally.** Before closing, confirm with the user.
- **It does NOT batch documentation updates.** `CONTEXT.md` and ADRs are touched inline as decisions land.
- **It does NOT impose architecture.** The user (or their project's conventions) drives architecture; the grill helps articulate it.
- **It does NOT silently consume time.** When the conversation passes ~10 branches, offer a checkpoint to pause or prioritize.
