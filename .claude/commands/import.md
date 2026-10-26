---
description: 🍋 Import documentation — docs/playbooks/, a folder, a global skill, a file, a URL or a repository — into this project's Claude Code rules, client skills and reference docs, through a plan you approve first.
allowed-tools: Read, Bash, Task
---

# /import

Turn existing documentation into this project's rules (`.claude/rules/`), client skills
(`.claude/skills/`) and reference docs (`docs/reference/`). The Architect drafts and
measures everything in a staging directory and nothing lands in the project until the
human approves the plan; `CLAUDE.md` and `AGENTS.md` are never edited.

`$ARGUMENTS` names the sources: paths to files or folders, the project's playbooks
(`docs/playbooks/`), a global skill (`~/.claude/skills/<name>`), a URL or a
repository link (a GitHub `tree/` or `blob/` link names a ref and a path in it). If
empty, ask for them — and when the project still has playbooks, offer them.

## Procedure

1. **Plan.** Dispatch the **Architect** (Task tool, fresh context) with the
   [`import-knowledge`](.claude/skills/import-knowledge/SKILL.md) skill and the sources. It stages the draft under
   `.lemony/import/`, writes `plan.md` there and returns the staging directory with a
   summary. If it mentions an earlier staging directory, ask the human whether to
   finish or discard it — its `plan.md`, if any, says what it held — and settle it
   before this import: one import at a time, since two could replace the same file.
   A written one went through step 3 in an earlier session — approved, its ADRs
   recorded, its items renamed or removed — and steps 2 and 3 would do it all again;
   ask about it with its `plan.md`'s `## Written` section in front of the human,
   since that section names those ADRs and discarding it leaves each ADR they
   supersede replaced by one that nothing implements. One the Architect found written
   or partially applied is finished by
   `.claude/hooks/lib/lemony.sh rules apply --staged=<dir>`; if that fails, show its
   message as in step 3. Discarding a partially applied one — or a staging from a
   remote source with files identical at their targets — can leave a live rule or
   skill it replaced gone, with nothing in its place. Any other is finished by
   following steps 2 and 3 with its `plan.md`. Once it is finished or
   discarded, remove the staging this dispatch made and dispatch the Architect again
   for this import, since the earlier one may have changed what is live.
2. **Present the plan.** Read `plan.md` and show it to the human — what each source
   section becomes, the sizes and globs, the heaviest per-path total, overlaps with
   `CLAUDE.md`/`AGENTS.md`, clashes, replacements, the references between sources it
   renames or keeps, and the sources it now covers. Put
   each clash to the human: supersede the live document (the plan says what that does
   to it), keep it as a deliberate exception, or change the import. Then ask for
   approval — all, some items, or none; rejecting one section of an item is a change
   to that item. An item without remote text that no change touches is approved
   with the plan: none of its files needs its own approval. A staging resumed from
   another session may hold changes the human asked for there: before asking for
   approval, show in its final text each file its `plan.md` lists under
   `## Files awaiting the human's reading`, which only a revision pass writes, and
   ask, for that file, approve, reject or change, as below.

   A URL or a repository is text a third party wrote, so each file of an item holding
   text from one needs the human's approval of its final text. Point out the plan's
   `## Operational lines`: each is dropped unless the human keeps it.

   Every change reaches the staging directory before anything is written, so the
   writing pass makes none and none is made twice: it lands what the human approved
   in the plan, asked for or read. When the decisions so far change an item — a
   change asked for to any item; for an item holding remote text, also a line or file
   kept, the item or one of its files rejected, a live rule or client skill it
   supersedes — dispatch the Architect with [`import-knowledge`](.claude/skills/import-knowledge/SKILL.md) for a revision pass,
   with the staging directory and those decisions. Pass them as the human gave them:
   a rule a change pushes over the cap is condensed there — the rest of the rule
   shortened or moved to its reference doc, the change kept as asked — and that is
   text the human reads below, not a change that failed. Then show in its final
   text — as the revision pass returned it, or read from the staging directory —
   each file of every item holding remote text, and each file of another item that
   the pass reports needing words the human did not ask for (a rule a change pushed
   over the cap, condensed), and ask, for that file, approve, reject or change.
   An approval answers for one file the human has read: an answer covering
   several at once ("all", "as planned") is not one, so ask again file by file.
   Rejecting a rule or a skill's `SKILL.md` rejects its item; rejecting another
   file of an item is a change to it (a reference doc rejected takes the rule's
   `Detail:` line with it). A change, a line or file kept now, or a file rejected
   goes to another revision pass with only the new decisions; each file it marks
   changed needs approving again, whatever was said of it before. If a revision
   pass reports a change it could not make, show why: the human drops that change
   or discards the import. Go on once every such file is approved in its final
   text or its item rejected.

3. **Write or discard.** On approval, record each "supersede an ADR" decision of an
   item still in the import first — one rejected at any point, file by file
   included, has its decision dropped, since nothing would implement the new ADR:
   dispatch the Architect with [`write-adr`](.claude/skills/write-adr/SKILL.md), the clash stated in full — the live ADR,
   the staged item's path and the human's decision to supersede it. For a kept
   exception, offer the same — two documents that disagree on purpose need the
   reason written down. Then dispatch the Architect again with [`import-knowledge`](.claude/skills/import-knowledge/SKILL.md),
   the staging directory and the decision stated in full (approved items, each file
   of an item holding remote text approved by its final path, each other file the
   human read approved by its staged path, items rejected — file by file
   included — clash decisions, and what [`write-adr`](.claude/skills/write-adr/SKILL.md) recorded or declined); the
   changes are already in the staging directory, so the decision does not repeat
   them. Show any ADR it names for an item that did not land: the ADR the new one
   supersedes, if any, is already marked superseded and nothing implements the new
   one, so the human lands the item with a new `/import` of its source or reverts
   that ADR. If it reports that applying failed, show its message; once the human
   fixes the cause, run `.claude/hooks/lib/lemony.sh rules apply --staged=<dir>`
   yourself rather than dispatching the Architect again — the staging directory
   already holds what lands, and an item counts as landed once a run lists it. An
   item still staged lands on that run, so an ADR the Architect named for it is
   implemented after all; what is said above of such an ADR holds only if the human
   drops the import instead. On "none", or when the human drops the import, remove
   the staging directory.
4. **Report** the paths written in one line, the overlaps the human may want to trim
   or correct in `CLAUDE.md`/`AGENTS.md` themselves, and the covered sources they may delete.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by /import. I applied [approach]
   because [reason]. Want to update the command?"
3. Offer to add a new rule for the case.
