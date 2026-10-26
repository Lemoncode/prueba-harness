---
name: extract-conventions
description: 🍋 Infer the conventions this codebase already follows — how a kind of file is named, structured and tested, how a recurring task is done — and write them as a markdown draft that then goes through /import, where the human approves what becomes a rule, a client skill or a reference doc. Use when the human asks to capture how the project does something, or accepts the closeout offer to extract conventions. It writes the draft only, never a rule or a skill.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [architect]
trigger-condition: the human asks to capture how the project does something, or accepts the closeout offer to extract conventions
---

# Extract Conventions

**Run by the Architect.** The Orchestrator dispatches the Architect (Task tool, fresh
context) with this skill; a main session that finds it in its own skill listing
dispatches the Architect instead of running it.

Inferring conventions from code and translating text into rules are different jobs
with different failures: this one can misread what the code does, while
[`import-knowledge`](.claude/skills/import-knowledge/SKILL.md) must never add a line its source does not hold. So this skill
writes a **draft**, the human reads it, and `/import` turns it into rules, client
skills and reference docs through the plan the human approves. Nothing here becomes
a standing instruction on its own.

## Process

1. **Scope.** Capture what the human asked for — a kind of file, an area, a task —
   not the whole codebase. If the codebase is unfamiliar, run
   [`code-explorer`](.claude/skills/code-explorer/SKILL.md) first.
2. **Find what is already live**: `.claude/rules/`, the skills under
   `.claude/skills/` with `origin: client`, `docs/reference/`, the playbooks the old
   hooks still enforce in a project that has not migrated them, and the file Claude
   Code loads as project memory — `CLAUDE.md`, or `AGENTS.md` when there is no
   `CLAUDE.md`. A convention already written there is not drafted again. Where the
   code departs from one, list the departure in the draft instead: whether the code
   or the convention is wrong is the human's call.
3. **Find the pattern.** Read the files in scope (`git ls-files` lists them) and
   state what they share: naming, structure, the calls they make, how they are
   tested, the steps a recurring task takes. A convention is what most of them
   follow; name the files that depart from it rather than smoothing them over. Each
   convention carries its evidence — two or three repo-root paths of files that
   follow it — so the human can check the draft against the code.
4. **Say only what the code shows.** Why a convention exists goes in only when a
   comment, an ADR or a doc in the repo says so — cite it. A convention with no
   recorded reason is stated without one: an invented reason would reach every agent
   as if someone had decided it. The same goes for a ban: state what the files do
   ("Export a factory"), never what no file may do ("Do not use classes"), unless a
   doc in the repo forbids it.
   A recurring task's steps stand on their own — `/import` may make them a client
   skill, read apart from the rest of the draft — so name what a step follows instead
   of pointing at "the pattern above".
5. **Write the draft** with your **Write** tool to
   `.lemony/extract/<YYYYMMDD-HHMMSS>.md`. It is gitignored and outside `.claude/`,
   where every Write asks the human, and outside `.lemony/import/`, which holds
   `/import`'s staging directories:

   ```markdown
   # Conventions: <scope>

   Extracted from the code on <YYYY-MM-DD>, a draft for `/import`.

   ## <convention, named by what it governs>

   <what the files do, in the imperative: "Name each … ", "Test each … with …">

   - Applies to: <the files, as globs or paths>
   - Evidence: `<path>`, `<path>`
   - Departures: `<path>` (<how it differs>), or none

   ## <a recurring task>

   <its steps, numbered, as the code and scripts show them>

   ## Departures from live conventions

   - `<live rule, skill or file>`: <what it says> / <what the code does>, or none
   ```

6. **Report** to the Orchestrator: the draft path, one line on what it holds, and
   the next step — the human reads the draft, edits it if they want, and runs
   `/import <draft path>`. Never run the import yourself: its plan and its approval
   belong to the human.

## Uncontemplated Scenarios

When a case doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This isn't covered by the extract-conventions skill. I did [approach]
   because [reason]. Want to refine the skill?"
3. Offer to add a rule for the case.
