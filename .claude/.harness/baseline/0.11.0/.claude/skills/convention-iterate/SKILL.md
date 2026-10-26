---
name: convention-iterate
description: 🍋 Change a project convention — a rule under .claude/rules/, a client skill, the reference doc a rule cites — the way the human decided, after checking the change against the live decisions. Use when the Orchestrator routes a T6 CONVENTION_CONFLICT resolution that changes a convention to the Architect, when the human asks to change a convention ("change our convention for X"), or when they accept the closeout offer to adjust one. The human chooses the direction; this skill renders it.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [architect]
trigger-condition: a T6 CONVENTION_CONFLICT resolution changes a project convention, or the human asks to adjust one
---

# Convention Iterate

**Run by the Architect.** The Orchestrator dispatches the Architect (Task tool, fresh
context) with this skill; a main session that finds it in its own skill listing
dispatches the Architect instead of running it.

## Core Principle

A project's conventions are its own: the human decides what they say, and this skill
writes the decision into them. It never picks the direction — by the time it runs, the
human chose to change the convention rather than the spec ([`resolve-discovery`](.claude/skills/resolve-discovery/SKILL.md)) or
asked for the change (the closeout offer).

## Where conventions live

- **Rule** — `.claude/rules/<topic>.md`, with `paths:` globs naming the files it
  governs; Claude Code injects it whenever any agent reads or edits one of them. Held
  to 8,000 characters, frontmatter included.
- **Reference doc** — `docs/reference/<topic>.md`, the detail a rule cites on its
  `Detail:` line.
- **Client skill** — `.claude/skills/<name>/SKILL.md` with `origin: client`: how to do
  a task. A skill with `origin: vendor` is Lemony's own, not a project convention —
  `lemony update` would undo an edit to it; report the conflict instead of editing.
- **A project still migrating** may hold the convention in a playbook its old hooks
  enforce (`docs/playbooks/`, or the directory `paths.playbooks` names in
  `harness.config.yml`). Change it there, in place; moving it into a rule is
  `/import`'s job, not this one.

When the discovery does not name the file, find it: for a file the task changes,
`.claude/hooks/lib/lemony.sh rules match --path=<path>` names the rules that cover
it; a client skill is the one whose description fits the task.

## Before any write — check the live decisions

Search the ADRs still in force — every `docs/adr/NNNN-*.md` not wholly `superseded` or
`deprecated`; a _partially_ superseded ADR is live for the points it does not name as
superseded — the other rules, client skills and reference docs, the playbooks still
enforced, and the project-memory file (`CLAUDE.md`, or `AGENTS.md` when there is no
`CLAUDE.md`) for what the change contradicts. If anything clashes, **stop before
writing** and report each clash — the document, the point, how they disagree. The human
decides: supersede it, keep it as a deliberate exception, or change this convention
change instead.

- **Supersede an ADR** → that is [`write-adr`](.claude/skills/write-adr/SKILL.md)'s outcome, never yours: a convention says
  _how_, it cannot be what an ADR is superseded _by_. Report it; the Orchestrator runs
  [`write-adr`](.claude/skills/write-adr/SKILL.md) first.
- **Another rule, client skill or reference doc** → propose its edit in the same
  change.
- **A playbook still enforced** → propose its edit in the same change, in place; if
  an import already covers it, name it instead as a source the human may delete — left
  in place, its old hook keeps handing agents the text the change replaced.
- **The project-memory file** → name the passage; the human edits that file, never
  this skill.

When you are dispatched **with the human's decision** on a clash (it arrives in the
spawn prompt), that clash is settled: apply it instead of reporting it again. A
decision to supersede an ADR is settled only once that ADR's `Status` says
`superseded by` — if it does not yet, write nothing and report that the superseding ADR
comes first. Any other clash still stops you.

## Process

1. **Read both sides.** The convention's text in conflict and the spec requirement
   that collides with it — or, for a closeout adjustment, what the human asked to
   change. State the contradiction precisely.
2. **Draft the smallest change** that says what the human decided. An exception the
   decision names stays an exception, written next to the rule it qualifies, not a
   rewrite of it. Add nothing the decision does not say — no further constraint,
   example or rewording of what it leaves alone: the change reaches every agent as the
   human's own words. If saying it takes words the human did not decide, stop and
   report the new text, writing nothing, so the human sees it first. Keep the
   frontmatter as it is — `paths:`, and `source:` /
   `imported:` on an imported file — unless the decision changes which files the rule
   governs. If the decision holds only for this task, it is not a convention: say so,
   write nothing, and name where it belongs (the spec, or an ADR when the reason
   should outlive the task).
3. **Write it.** A file under `.claude/` goes through a staging directory, since
   Claude Code asks the human before every Write there, and `rules apply` asks once:
   1. `mkdir -p .lemony/import/<YYYYMMDD-HHMMSS>` — the staging directory (`<dir>`).
   2. Copy each live file you change into it under the path it has below
      `.claude/rules/` or `docs/reference/`, creating its directory first: a rule to
      `<dir>/rules/<path>`, the reference doc it cites to `<dir>/reference/<path>`. A
      skill is copied whole, since applying replaces its directory whole:
      `mkdir -p <dir>/skills && cp -RL .claude/skills/<name> <dir>/skills/<name>`.
      Edit the copies. When the project has a formatter (its `package.json` names
      prettier, biome or dprint, the formatter's config file sits at its root, or its
      CI workflow runs one),
      `Read` `.claude/skills/import-knowledge/formatting.md` and format the copies as
      it says: `rules apply` lands them byte for byte.
   3. `.claude/hooks/lib/lemony.sh rules measure --staged=<dir>`. A refusal naming a
      path in the staging directory is a copy that broke the layout above: fix it
      there and measure again. It also exits non-zero while a staged rule is above
      the cap, or a staged skill takes the name of one of Lemony's own: whatever its
      message suggests, fitting the cap takes words the human did not decide (moving
      detail to the reference doc), and a vendor skill is not edited here — stop and
      report, writing nothing, so the human sees it first. On exit 0, check that its
      output lists every file you changed: one it leaves out sits outside `rules/`,
      `skills/` and `reference/`, and would not land — move it there and measure
      again.
   4. `.claude/hooks/lib/lemony.sh rules apply --staged=<dir>` — it copies the
      staged files into place and removes `<dir>`. If it exits non-zero, report its
      message and stop.

   Whenever you stop before applying, or `rules apply` says nothing applied, remove
   `<dir>` (`rm -rf <dir>`): left under
   `.lemony/import/`, the next `/import` would take it for an unfinished import.

   A reference doc changed alone, or a playbook, is edited in place.

4. **Return** the paths changed and a one-line summary to the Orchestrator — for a T6,
   confirmation that the change resolves it, so it can record the resolution and
   resume the paused sub-agent against the corrected convention.

## Report

Return to the Orchestrator one of these:

- **Written** — the paths written, a one-line summary, and — for a T6 — confirmation
  it resolves the cited discovery.
- **Nothing written, the human decides first** — each clash with a live decision; an
  ADR to supersede that is not marked yet; new text the decision did not cover (a
  wording, or what fitting the cap takes), quoted; or a vendor skill in conflict.
- **Not a convention** — where the decision belongs instead; no edit.
- **Applied, staging left** — `rules apply` said every file is in place but the
  staging directory could not be removed: report it as written, and give the
  directory's path for the human to remove.
- **Apply failed** — `rules apply`'s message. After "nothing applied", nothing
  changed. After "partially applied", the staging directory is kept and a skill it
  replaces may already be gone: give its path, and say the paused sub-agent stays
  paused until the cause is fixed and
  `.claude/hooks/lib/lemony.sh rules apply --staged=<dir>` finishes the change.

## Uncontemplated Scenarios

When a case doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This isn't covered by the convention-iterate skill. I did [approach]
   because [reason]. Want to refine the skill?"
3. Offer to add a rule for the case.
