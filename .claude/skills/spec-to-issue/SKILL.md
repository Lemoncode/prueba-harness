---
name: spec-to-issue
description: 🍋 Fill a managed issue's body with the externalized spec. Use when the Spec Author publishes the completed spec into the GitHub issue the Orchestrator already created, mentions "fill the issue", "spec-to-issue", or "externalize the spec into the issue".
origin: vendor
vendor_version: '0.11.0'
phase: pre-implementation
invoked-by: [spec-author]
---

# Spec to Issue

## Core Principle

The GitHub issue **is** the spec, externalized. The Orchestrator already created it (a
skeleton with the harness labels) at the start of `spec-in-progress` and gave the task
its permanent `<id>`. This skill does one thing: replace that skeleton body with the
real spec, so the issue reads as a self-contained spec on GitHub.

Run this **after** [`prd-to-spec`](.claude/skills/prd-to-spec/SKILL.md) has produced `requirements.md` + `design.md` +
`tasks.md` under `.claude/state/tasks/<id>/spec/`.

## Preconditions

- The issue already exists (the Orchestrator created it) and `<id>` is known.
- A spec exists at `.claude/state/tasks/<id>/spec/{requirements,design,tasks}.md`.
- `gh` is authenticated and `task_storage.type` is `github` (see `harness.config.yml`).

You do **not** create the issue, rename any folder (the id is real from the start —
there is no `draft-<slug>`), or touch labels. Issue creation and the entire label
lifecycle belong to the Orchestrator.

## Process

### 1. Build the body and replace the skeleton — mechanically

**A copy never passes through your Read/Write path.** The body carries `requirements.md`
and the skeleton's trace lines, and both must arrive byte-identical — a copy retyped by
a model can truncate, reformat or "fix" what it carries, and it looks done. So you
write only the summary; `cat` copies the requirements, and
`lemony issue-body keep-trace` carries the trace lines (a task that is a part of a
partitioned feature has `Part <k> of #<parent>`, and `Depends on #<sibling> …`, at the
top of the skeleton — how the parent plan, `/resume`, and closeout find the task's place
in the partition; dropping them orphans the part). Three steps:

1. `mkdir -p .lemony/tmp && mktemp -d .lemony/tmp/issue-body.XXXXXX` — note
   the directory it prints (`<dir>` below). It is inside the repo and gitignored, so
   the Write tool can use it without a permission prompt.
2. Write the summary — one paragraph: the capability and why, from the PRD — to
   `<dir>/lead.md` with your **Write** tool. Never through the shell (no heredoc,
   no `echo`): a line of prose the shell reads as syntax can cut the summary short
   or run as a command. Keep the name: Claude Code refuses a sub-agent's Write to a
   `.md` whose name starts with `summary`, `report`, `findings` or `analysis`.
3. Build and write the body as **one** Bash call:

```bash
id=<id>; t=<dir>; spec=".claude/state/tasks/$id/spec" &&
gh issue view "$id" --json body --template '{{.body}}' > "$t/old.md" &&
{ printf '## Summary\n\n' && cat "$t/lead.md" && printf '\n' &&
  cat "$spec/requirements.md" &&
  printf '\n## Design\n\nSee `%s/design.md`.\n\n## Tasks\n\nSee `%s/tasks.md`.\n' "$spec" "$spec"; } > "$t/new.md" &&
.claude/hooks/lib/lemony.sh issue-body keep-trace --old="$t/old.md" < "$t/new.md" > "$t/body.md" &&
gh issue edit "$id" --body-file "$t/body.md" &&
gh issue view "$id" --json body --template '{{.body}}' > "$t/stored.md" &&
{ cmp -s "$t/body.md" "$t/stored.md" || { diff -a -u "$t/body.md" "$t/stored.md";
  echo "spec-to-issue: #$id stores a different body (- sent, + stored)"; false; }; } &&
rm -rf "$t" && echo "spec-to-issue: body written to #$id"
```

The result reads as a self-contained spec on GitHub — the trace lines first, the
summary, the requirements in full (under their own `# Requirements — …` heading), and
links back to the committed design and tasks. Keep the `&&` chain: a step that fails
stops it before `gh issue edit`, so the skeleton stays as it was. **Never pipe the
verb's output straight into `gh issue edit`** — a failure mid-pipe writes an empty body.
**Done means the last line printed `spec-to-issue: body written to #<id>`**; without
it, the step did not finish, whatever the exit code says: a failure before
`gh issue edit` leaves the skeleton, one after it leaves whatever body GitHub stored,
and the block is safe to run again. Then report the error to the Orchestrator; don't
compose the body by hand instead.

One failure is yours to fix. GitHub stores a body byte for byte except a C0 or C1
control character other than tab, line feed and carriage return: raw, or spelled as
a `\u` escape (`\u001b`, `\u009b`; either case, even after a second backslash), it
is stored in caret notation (`^[`, `\^[`), inside code spans and fences too. When the
chain prints `stores a different body` over such a line, rewrite the line where it
came from — `<dir>/lead.md` or `requirements.md` — so it carries no such character,
and run the block again. In prose, name the character ("ESC (U+001B)"). In code,
spell it in a form GitHub keeps — `\x1b`, `\e` or `\033`, whichever the code's
language reads; where the code has to show the `\u` form (JSON, or a span about that
escape), leave it out of the code and describe it in the prose beside it, or move a
sample that must stay exact to `design.md`, which the issue links instead of copying.
Any other difference is not this case: report it with the diff.

This overwrites the `🚧 Spec in progress …` skeleton the Orchestrator wrote at issue
creation. Labels are untouched — the issue still carries `harness:managed` +
`harness:sdd` + `harness:status:spec-in-progress`; the Orchestrator flips it to
`spec-ready` after you hand back.

### 2. Hand back to the Orchestrator

Return a short confirmation. From here the **Orchestrator** flips the status label to
`harness:status:spec-ready`, commits and pushes the task state to the branch, and runs
the human approval gate. This skill transitions no labels.

## Ownership boundary

- **Spec Author** (this skill): fills the issue **body** from the committed spec.
- **Orchestrator**: created the issue, owns every label transition
  (`spec-in-progress → spec-ready → in-progress → in-review → done`), and closes it at
  closeout.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching approach with reasoning.
2. **Flag it**: "This scenario isn't covered by the spec-to-issue skill. I applied
   [approach] because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case.
