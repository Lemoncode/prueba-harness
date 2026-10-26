---
name: import-knowledge
description: 🍋 Translate existing documentation — the project's docs/playbooks/, a folder, a personal or global skill, a single file, a URL or a repository — into this project's Claude Code rules (.claude/rules), client skills (.claude/skills) and reference docs (docs/reference), through a plan the human approves before anything is written. Use when the human runs /import or asks to import, migrate or bring knowledge in from a source. It translates text that exists; it never infers conventions from the code.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [architect]
trigger-condition: the human runs /import or asks to import knowledge from a source
---

# Import Knowledge

Brings documentation into the three channels Claude Code already loads on its own, so
the project's knowledge reaches every agent without a Lemony-only concept. The source
can be anything written down; what it becomes depends on what each part of it says.

## The channels

- **Rule** — what a kind of file must look like (naming, structure, the patterns a
  file follows). It lives in `.claude/rules/<topic>.md`, with `paths:` globs naming
  the files it governs. Claude Code injects it whenever any agent reads or edits a
  matching file — the writer, and also the Reviewer, the Orchestrator and the
  Architect — so each rule is held to 8,000 characters, frontmatter included. A
  convention the source declares mandatory but gives no path for is still a rule,
  with a glob broad enough for the files it governs (`src/**`, `**/*.ts`): as a skill
  it would become optional, and as an unconditional rule (no `paths:`) it would ride
  on every request of every role.
- **Client skill** — how to do a task (cut a release, handle a dependency PR, run the
  app). It lives in `.claude/skills/<topic>/SKILL.md` with `name`, `description` and
  `origin: client` in its frontmatter. Claude Code loads it only when its description
  fits the task at hand, so the description says, in the words of the task, when to
  use it.
- **Reference doc** — what a rule cannot carry within its cap: rationale, long
  examples, full tables. It lives in `docs/reference/<topic>.md`, named like its rule,
  and the rule cites it by its repo-root path on a line of its own:
  ``Detail: `docs/reference/<topic>.md` — `Read` it before <when it is needed>.``
  Never under `.claude/rules/` (every `.md` there loads as a rule) and never as a
  file-relative link (an agent resolves it against its working directory).
- **Dropped** — a part that is none of these for this project: a duplicate of
  another part, guidance for a stack the project does not use, history. The plan
  lists it with the reason, so nothing disappears unseen.

Classification follows content, not the source's metadata or file boundaries: a
playbook with `applies_to` may describe a procedure, one without it may be a mandatory
convention, and one document often splits into a rule, a skill and a reference doc.

## Translate, never author

Every line of a rule, skill or reference doc comes from the source. Condensing is
choosing — what an agent needs while it writes such a file stays in the rule, the rest
moves to the reference doc — and shortening the source's own sentences. It never adds
a convention, example, name or command the source does not contain: imported text
becomes a standing instruction for every agent, and a line nobody wrote has no owner
to ask about it. Keeping the source's wording where possible is what lets the human
trace each line back.

Shortening takes words out of a source sentence; what is left still says what that
sentence said. Rephrasing to save space is where meaning drifts, so a shortened point
keeps its shape: a mistake the source lists is named as that mistake, not restated
through its remedy; two points stay two, never merged into one check that holds for
neither; a condition stays on its instruction wherever the instruction appears, so a
reference doc that repeats a point of its rule to give the reason copies the point's
sentence whole; and a code span or example is copied as the source writes it, never
generalized into a placeholder the source does not have. A point that does not fit
shortened this way moves whole to the reference doc.

What comes from this project rather than the source: the `paths:` globs, fitted to
where such files actually live here (`git ls-files`), the reference-doc line above,
one opening line in the reference doc naming the rule it details, and the target of
each reference a source being imported makes to another one or to itself ("the
`testing` playbook", "this playbook", its file named or linked, in a code span too):
the reference is kept and names where the part it cites landed — the rule, reference
doc or skill, by its repo-root path — since the plan offers the sources for deletion
and a pointer left as written sends an agent looking for a file that is gone. A
reference to a source an earlier import brought in, named in a live item's `source:`,
names that live item the same way. A reference to a part the import drops, or to a
document outside the import, keeps its target, by its repo-root path where the source
links it relative to its own file, since an agent resolves a path against its working
directory. Inferring
conventions from the code is another job: [`extract-conventions`](.claude/skills/extract-conventions/SKILL.md) writes a draft
under `.lemony/extract/`, and that draft enters this skill as a source like any other
file.

## Provenance

Every staged rule, reference doc and `SKILL.md` starts with frontmatter that records
where it came from: `source:` (the path as the human gave it, repo-relative or `~/…`;
for a remote source, as `.claude/skills/import-knowledge/remote-sources.md` says; a
list when parts of several sources were merged) and `imported:` (today,
`YYYY-MM-DD`), next to the channel's own keys. Frontmatter costs nothing on a rule or
a skill — Claude Code strips it before the model sees them — while an HTML comment in
a skill would reach the model.

## Formatting

A project has a formatter when its `package.json` names one (prettier, biome, dprint)
in its dependencies or scripts, the formatter's config file sits at its root, or its CI
workflow runs one. Then
`rules apply` would land the staged text unformatted, so `Read`
`.claude/skills/import-knowledge/formatting.md` before the first `rules measure` and
format the staged files as it says, after every change and before every measure. The
plan then quotes the sizes of the text that lands.

## Planning pass

1. **Read the sources.** A file; every `.md` under a folder; the project's playbooks
   (`docs/playbooks/`, or the directory `paths.playbooks` names in
   `harness.config.yml`) — each playbook, not their `README.md`, which is the format
   template; a personal or global skill, `~/.claude/skills/<name>/`. A skill's other
   files (scripts, templates, references) travel with it unchanged into its staged
   directory, copied with links followed (`cp -RL`); only its `SKILL.md` gets the
   provenance. A URL or a repository link is a remote source: `Read`
   `.claude/skills/import-knowledge/remote-sources.md` first, which says how to fetch
   it and what changes for the text it brings.
2. **Read what is live in the project**: `.claude/rules/`, the skills under
   `.claude/skills/`, `docs/reference/`, the playbooks still enforced (unless they are
   what is being imported), the ADRs still in force (`docs/adr/` not wholly superseded
   or deprecated) and the file Claude Code loads as project memory — `CLAUDE.md`, or
   `AGENTS.md` when there is no `CLAUDE.md` — following its `@path` imports.
3. **Stage the draft** in `.lemony/import/<YYYYMMDD-HHMMSS>/`: `rules/` holds the
   rules (`.md`), `skills/` one directory per skill with its `SKILL.md`, `reference/`
   the reference docs, and `plan.md` sits next to them; nothing else, no symlink, no
   two paths that differ only in case. The directory is gitignored and outside
   `.claude/`, where Claude Code asks the human's permission for every Write; the
   layout is flat, never a nested `.claude/` whose `rules/` Claude Code could take for
   the project's own. Write each file you draft there with the Write tool, and change
   it with Edit: Claude Code shows the human each one as a file to read, where a shell
   command that writes them (a heredoc, a redirection, a script) is one command
   holding all their text, which no permission rule can allow, so the human is asked
   again on every import. Claude Code refuses your Write to a `.md` whose name starts
   with `summary`, `report`, `findings` or `analysis` (a `reporting` rule): Write that
   file under a name with a leading `_` and rename it with `mv`, which carries no
   text. Nothing outside the directory is written in this pass. An
   earlier staging directory left there stays as it is; mention it in the report, and
   whether any of its files already sits, identical, at its target: that import was
   partially applied, and the live rule or skill it replaced may already be gone. One
   whose `plan.md` names a remote source and has no `## Written` section is never
   reported as partially applied — a re-import of unchanged files looks the same,
   and its remote text may never have been approved — but say whether any of its
   files sits, identical, at its target.
   One whose `plan.md` has a `## Written` section went through a writing pass whose
   apply failed, so its approval was given and its ADRs recorded: report it as
   written, whatever its source, since only `rules apply` finishes it — and, whatever
   its source, also as partially applied when any of its files sits, identical, at
   its target.
4. **Format and measure.** Format the staged files when the project has a formatter
   (see Formatting above), then measure with `.claude/hooks/lib/lemony.sh rules measure --staged=<staging dir>`:
   each rule's size, the project files it matches, the heaviest per-path total with the
   staged rules in place, and the existing skill each staged one would replace. It
   exits non-zero while a staged rule is above the cap — condense it, moving more to
   its reference doc — or while a staged skill takes the name of one of Lemony's own
   skills (`origin: vendor`) — rename it, since replacing it would run the imported
   text where Lemony's flow expects its own and `lemony update` would fight the
   change. A refusal naming a path in the staging directory is a staging that breaks
   the layout above: fix it there. Measure again after each fix. Any other failure
   prints its reason; report it and stop. The plan quotes these numbers; an estimate
   is not a measurement. Run the command as written, from the repository root, with
   nothing chained to it: the tool result already shows a non-zero exit, and to
   Claude Code's permissions a longer command, or the launcher by its absolute path,
   is a different command, so the human is asked again after allowing this one.
5. **Check against what is live.** A staged rule or skill that contradicts a live ADR,
   rule, client skill or enforced playbook is a clash; the human decides it, so state
   the document, the point, how they disagree and what superseding it would do: a
   live rule or client skill is replaced by the staged item taking its name; an
   enforced playbook joins the sources the human may delete; an ADR is superseded by
   a new one ([`write-adr`](.claude/skills/write-adr/SKILL.md)). Keeping both is a deliberate exception, and changing the
   import edits the staged item. Content already in the project-memory file, or
   contradicting it, is an overlap: it is paid on every request and the two copies
   drift or disagree, so propose what to trim or correct there — the human edits that
   file, never this skill — or drop the part from the import. A staged rule or
   reference doc named like an existing one replaces it, and a staged skill replaces
   the existing skill directory whole; say which. If a task in flight follows a spec the import contradicts, name
   the task.
6. **Write `plan.md`** in the staging directory, by item — what the human approves or
   rejects: a rule together with the reference doc it cites (either one alone leaves
   a citation pointing at nothing, or detail nobody is told to read), or a skill.
   Each item lists the source sections it holds, its target path, characters, and
   globs for a rule; a dropped section gets a row with the reason. Rejecting one
   section of an item is a requested change to that item. Then the measure output; a
   `## Overlaps` section with one bullet per passage of the project-memory file the
   import repeats or contradicts, quoting it, or `None.`; the clashes; the
   replacements; each reference between sources renamed to where the part it cites
   landed, and each one that keeps its target (a dropped part, a document outside the
   import); and the sources inside the repo that the import now covers entirely
   — the human may delete them (an imported playbook left in place keeps its old hook
   enforcing it next to the new rule); the import never does. With a remote source,
   what `.claude/skills/import-knowledge/remote-sources.md` adds. The plan has no
   `## Files awaiting the human's reading`: only a revision pass writes it, since an
   item without remote text that no change touched is approved with the plan.
7. **Report** to the Orchestrator: the staging directory, a one-line summary, each
   clash and any earlier staging directory found. Writing waits for the human's
   approval.

## Revision pass

Dispatched with the staging directory and the human's decisions, make each change
they ask for in the staging directory and nowhere else, before anything is written,
so the writing pass makes none and none is made twice. For an item holding remote
text, `Read` `.claude/skills/import-knowledge/remote-sources.md` and follow its
revision pass. For any other item, make the change the human asked for in the staged
item, and in each reference another staged item makes to an item the change renames,
and measure again. A rule the change pushes over the cap is condensed as in
planning step 4 — the rest of the rule, never the text the change asked for — since
the human reads the result before it is written. Report that the change could not be
made when condensing cannot fit it, or when the rule needs its reference doc and the
human rejected it, and leave the staging as it was before that decision, so dropping
the change needs no other pass. A rejected item without remote text stays as staged;
the writing pass removes it.
Report with its full text under its staged path, marked changed, each file
that needed words the human did not ask for — a rule condensed to fit the cap — and
each file the human was shown before that this pass changed again, since an earlier
approval of it no longer covers it; name the other files you changed. Bring `plan.md`
up to date, and list under its
`## Files awaiting the human's reading`, by staged path, each file a revision pass of
this import has shown in full — those listed before included, and no other file, so
an import finished in another session asks the human for those alone.
Dispatched again with further decisions, change only what they name and what they
force (a condensed rule, a `Detail:` line, a reference naming an item they rename);
the rest is what the human has read.

## Writing pass

Dispatched again with the human's decision and the staging directory, apply exactly
what was approved — the staged text, not a new draft, since the human approved those
words. A revision pass already made every change the human asked for, so make none
here: the renames and the references below are the only text you edit. An item
holding remote text lands exactly as staged: its revision pass also made every rename,
and the decision approves each of its files by its final path. One whose files are not
all approved that way stays out, and the report says it awaits the human's approval of
its files; so does an item with a file that `plan.md` lists under
`## Files awaiting the human's reading` and the decision does not approve by its
staged path. Any
item without remote text that supersedes a live rule or client skill is renamed in the staging
directory to the live one's path, subdirectories included — a rule together with its
reference doc, the path on its `Detail:` line and the reference doc's opening
sentence naming the rule; a skill's directory together with its `name:`; and each
reference a staged item without remote text, itself included, makes to it — and
measured again, so the output shows it replacing the live one; name in the report a
live reference doc any superseding item leaves in place, one holding remote text
included. An item that supersedes an ADR lands
only once the new ADR is recorded; if [`write-adr`](.claude/skills/write-adr/SKILL.md) declined or reported a clash of its
own, the item stays out and the report says why. An item whose clash is still
undecided stays out too. Remove from the staging directory every item
that does not land — rejected, awaiting the approval of its files, held back by
[`write-adr`](.claude/skills/write-adr/SKILL.md), or with its clash still undecided — a skill as its whole directory; the
report lists each with the reason, since applying removes the staging directory, and
names any ADR [`write-adr`](.claude/skills/write-adr/SKILL.md) recorded for it: the ADR the new one supersedes, if any, is
already marked superseded, and nothing implements the new one. A reference a landing
item makes to a removed item goes back to the target its source wrote, by its
repo-root path where the source links it relative to its own file, since the path it
names is never written. An item holding remote text lands as staged, so the report
names each of its references to a removed or renamed item instead.
If no item is left, remove the staging directory and report that nothing landed.
Otherwise add to `plan.md` a `## Written` section: each item left, by the path it
lands at; each rename; each item removed, with the reason; each reference changed;
and each ADR [`write-adr`](.claude/skills/write-adr/SKILL.md) recorded. A staging whose apply fails is kept, and the section tells
a later session that its ADRs are recorded and its renames and removals made, so
`rules apply` alone finishes it.
Then run `.claude/hooks/lib/lemony.sh rules apply --staged=<staging dir>`:
it copies the rules, skills and reference docs into place (a skill replaces its
directory whole), removes the staging directory and lists what it wrote. One command
asks the human once, where a Write per file under `.claude/` would ask for each. It
writes nothing on what `measure` refuses, an empty staging, or a target path holding
a symlink or an entry of the wrong kind. If it exits non-zero, report its message and
stop, writing nothing else: after "nothing applied" the staging directory is intact;
after "partially applied" it is kept too, so the same command finishes the import
once the cause is fixed, and an item counts as landed only once a run lists it;
after "applied", every item landed and only the staging directory is left. Name any
ADR [`write-adr`](.claude/skills/write-adr/SKILL.md) recorded for an item that did not land, for the same reason.
`CLAUDE.md` and `AGENTS.md` stay as they are whatever the plan proposed. Report each
path written.

## Uncontemplated Scenarios

When a case doesn't clearly fit:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This isn't covered by the import-knowledge skill. I did [approach]
   because [reason]. Want to refine the skill?"
3. Offer to add a rule for the case.
