# UI design (DEFINE + REVIEW) — Orchestrator companion

> Vendor companion to `.claude/agents/orchestrator.md` (the hat). **Read on
> demand, never at boot** — and never just to evaluate the activation gate: the
> gate's canonical two-part statement lives in the orchestrator's L1 step 3 and
> is evaluated there, core-only. Read this file when that gate has FIRED, when an
> implemented UI change reaches review (`tasks/<id>/spec/ui-handoff.md` exists),
> when resuming a task parked `awaiting design definition`, or on
> `/sync-design-tokens`.

UI design threads into an L1 task that touches UI — never a linear step. **The interactive
design interview is yours**: a sub-agent can't talk to the human, so at DEFINE **you** run
the [`grill-ui`](.claude/skills/grill-ui/SKILL.md) skill on your human-facing surface and author the `ui-handoff.md` contract.
The **UI Designer** sub-agent — always installed, invoked **on-demand**, your only invoker —
is your design **critic and QA**: at DEFINE it reviews the handoff you just authored (before
the Spec Author runs); at REVIEW it runs a mechanical pre-pass (the deterministic
`design-tokens` gates + the project's a11y tooling) then the [`design-critique`](.claude/skills/design-critique/SKILL.md) and
[`a11y-audit`](.claude/skills/a11y-audit/SKILL.md) judgment lenses, and returns one design verdict. You own the human dialogue, the
`ui-handoff.md` artifact, and the labels; it critiques and reports.

A third, on-demand affordance sits outside those two moments: **design-tool token sync**.
When the human runs `/sync-design-tokens` (or accepts the DEFINE offer when a drift check
shows an export is pending), dispatch the UI Designer to run its [`design-tool-sync`](.claude/skills/design-tool-sync/SKILL.md) skill.
It is human-reviewed both ways and tokens-only; the design tool is a projection of
`docs/design-tokens.json`, never a peer source of truth.

## Activation gate

Canonical statement: the orchestrator's **L1 step 3** — evaluated there, core-only,
before this file is ever read. Rationale worth keeping in mind when it fired on a
borderline call: a wasted handoff stub is cheaper than UI shipped with no design
pass.

## Design-stop offer

When the gate fires, **put `harness:needs-design`** on the issue and offer the human,
inline, in one line — three choices:

> This task touches UI. (1) **Continue** — define the design now, as part of the spec;
> (2) **Stop for handoff** — park here so a designer picks it up later; (3) **No UI after
> all** — skip design.

- **Continue** → **run [`grill-ui`](.claude/skills/grill-ui/SKILL.md) yourself** — the interactive design interview on your
  human-facing surface — authoring `ui-handoff.md` under `tasks/<id>/spec/`. Then dispatch
  the **UI Designer** (fresh context, Task tool) with the `<id>` and branch to **critique**
  the handoff, and resolve its findings — tighten the handoff, re-ask the human, or
  record an open question — before the Spec Author runs. The issue stays at
  `harness:status:spec-in-progress` — design is part of completing the spec, not a new
  lifecycle state.
- **Stop for handoff** → record the sub-state `awaiting design definition` in
  `progress.md`, commit and push the task state to the branch, and stop. The task waits
  at `spec-in-progress` (+ `harness:needs-design`) for a `/resume` (below).
- **No UI after all** → **remove `harness:needs-design`** and proceed with the ordinary
  spec flow — the gate was a false positive, which bias-to-include accepts.

## Persisting personas (offer)

`docs/personas.md` is **client-owned** — the harness consumes it, never imposes it. When your
[`grill-ui`](.claude/skills/grill-ui/SKILL.md) interview captured personas **inline** because `docs/personas.md` was **absent** (§1
of the handoff), make the offer — a human-facing choice, so it is yours:

> The design defined these personas inline. Persist them to `docs/personas.md` so future UI
> tasks reuse them? (yes / no)

- **Yes** → write a minimal `docs/personas.md` from the personas already in the handoff's §1
  — the client's own words, not an invented cast. Then continue toward spec-ready.
- **No** → write nothing; the inline personas live on in the handoff for this task. The next
  UI task simply asks again.

Only offer when the file was **absent and personas were captured inline** — never when
`docs/personas.md` already exists (it was consumed, nothing to persist) and never unasked.
This is opt-in surfacing of the client's own answers, not the harness authoring a persona set.

## Design-tokens & design-tool on-ramp (offer)

`docs/design-tokens.json` and a design-tool connection are **client-owned inputs** — consumed if
present, never imposed. When `harness.config.yml` sets `design_tokens.file`, the path it names is
the token file wherever this file says `docs/design-tokens.json`; never create a second file at
the default. A repo adopting the harness fresh has neither, and silence there is a dead
end. So when your [`grill-ui`](.claude/skills/grill-ui/SKILL.md) interview finds **either absent**, surface it as an opt-in offer (a
human-facing choice, so it is yours) rather than only an open question:

- **No `docs/design-tokens.json`** → offer to **scaffold** a starter token set derived from the
  direction the interview just settled (the client's own colours/type/spacing, not a vendor
  template), plus an opt-in follow-up to generate a sensible starter set for the aspects the
  interview didn't cover. On **yes**, write the file and run `lemony design-tokens validate` before
  closing; on **no**, capture it as an open question.
- **No `com.lemony.design-tool` binding** → offer to **connect a design tool** (write the binding +
  first import via the UI Designer's [`design-tool-sync`](.claude/skills/design-tool-sync/SKILL.md) skill / `/sync-design-tokens`), or **stay
  pure-code**. Skip gracefully if the tool's MCP bridge is unavailable; never connect unasked.

The mechanics live in the [`grill-ui`](.claude/skills/grill-ui/SKILL.md) skill; you run the offers on your human-facing surface. Only
offer when the input is **absent** — never re-offer a token file or binding that already exists.

## Label put/remove

`harness:needs-design` is an **orthogonal presence flag** (same family as
`harness:architecture-drift`), never a status:

- **Put** it as soon as the gate classifies the task as touching UI and design is not
  yet complete.
- **Remove** it the moment `ui-handoff.md` is **complete** — at or before the flip to
  `harness:status:spec-ready`. **Complete** = the handoff carries **this task's** design
  decisions (its sections hold real content, not the verbatim placeholder template), the UI
  Designer's critique **passed** (or you resolved its findings), and **no** open design fork
  remains (an open fork means design is still open — keep the label and resolve it first).
  Ensure the label is gone **before** flipping to `spec-ready`: a spec-ready task never
  carries `harness:needs-design`.

## `awaiting design definition` sub-state + /resume re-entry

A task parked at "stop for handoff" sits at `harness:status:spec-in-progress` with
`progress.md` recording the sub-state `awaiting design definition`. It is the design
analogue of the step-by-step `awaiting human checkpoint` line — execution state, not a
label. `/resume <id>` re-enters there: check out the branch, read the captured context,
resume the [`grill-ui`](.claude/skills/grill-ui/SKILL.md) interview yourself to finish `ui-handoff.md`, dispatch the UI Designer
to critique it, then remove `harness:needs-design` and continue toward spec-ready. The resume
queue surfaces the parked design (`resume.md` lists `spec-in-progress` too).

## REVIEW — the design lens

When an implemented UI change reaches review (L1 step 8), invoke the **UI Designer** as
a **distinct lens** alongside the Reviewer (code). The **durable "this task touched UI"
signal is the existence of `tasks/<id>/spec/ui-handoff.md`** — `harness:needs-design` is
already gone by spec-ready, so it can't be the cue; the handoff artifact persists and
survives a cold `/resume`, so it is what to check. Either lens rejecting routes back to
the Implementer (rejection is transient — no dedicated label); both passing reaches the
single human merge gate (two inputs, one gate).

The UI Designer's lens mirrors the Reviewer's own shape — a **mechanical pre-pass** (the
deterministic `lemony design-tokens validate` + `lemony design-tokens contrast` gates, plus the
project's a11y tooling), then **judgment** ([`design-critique`](.claude/skills/design-critique/SKILL.md) + [`a11y-audit`](.claude/skills/a11y-audit/SKILL.md)), returning
**one design verdict** with findings grouped by source (tokens / accessibility / craft).
The Reviewer's code lens stays design-unaware; you still see exactly two review inputs.

**Deterministic vs judgment, by level.** The two deterministic gates are cheap, agent-free
facts, so they run **per-step** on UI-touching steps in step-by-step mode (a bad contrast
in step 2 must not ride to step 6 — see the orchestrator's §"Step-by-step implementation");
the project's a11y lint rides the per-step lint the same way. The **judgment lenses run
full-pass only** — design is holistic, and a mid-component critique is noise. There is no
per-step design agent and no new cap: a full-pass design rejection routes back like any
other rejection. (`lemony design-tokens validate` / `contrast` also run in CI independently of
review.)

## Closeout

`ui-handoff.md` lives in `tasks/<id>/spec/`, so closeout archives it with the rest of
the spec ([`task-closeout`](.claude/skills/task-closeout/SKILL.md) `git mv`s the whole `spec/` into `_archive/<id>/`) — no
special handling.
