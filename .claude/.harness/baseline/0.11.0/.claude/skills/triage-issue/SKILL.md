---
name: triage-issue
description: 🍋 Triage a bug or issue by exploring the codebase to find root cause, then create a GitHub issue with a TDD-based fix plan (or, given an existing issue number, update that issue instead). Use when user reports a bug, wants to file an issue, mentions "triage", or wants to investigate and plan a fix for a problem.
origin: vendor
vendor_version: '0.11.0'
invoked-by: [orchestrator]
---

# Triage Issue

## Core Principle

Investigate first, ask later. Find the root cause through codebase exploration
before asking the user anything. Minimize questions, maximize diagnosis.

## Input

An **existing issue number** is optional. Pass it when the defect is already tracked —
a captured stub, or any issue the triage should fill in rather than duplicate. With it,
the skill runs in **reuse mode**: step 1 reads the problem from that issue, steps 2–5
are the same, and steps 6–7 update that issue instead of creating one. Reuse mode never
opens a second issue. Without a number, the skill creates the issue.

Reuse mode is for an **open** issue that is not a spec: if the issue is closed or
carries `harness:sdd` (its body is the spec), stop and say so instead of rewriting it.

## Process

### 1. Capture the problem

Get a brief description from the user. If they haven't provided one, ask ONE
question: "What's the problem you're seeing?" In reuse mode the issue already states
it: read it (`gh issue view <number> --json title,body`) and ask only if it is too thin
to start from. The title is the symptom; the body may add where it was seen.

Do NOT ask follow-up questions. Start investigating immediately.

### 2. Explore and diagnose

Deeply investigate the codebase to find:

- **Where** the bug manifests (entry points, UI, API responses)
- **What** code path is involved (trace the flow)
- **Why** it fails (the root cause, not just the symptom)
- **What** related code exists (similar patterns, tests, adjacent modules)

Look at:

- Related source files and their dependencies
- Existing tests (what's tested, what's missing)
- Recent changes to affected files (`git log`)
- Error handling in the code path
- Similar patterns elsewhere that work correctly

### 3. Identify the fix approach

Determine:

- The minimal change needed to fix the root cause
- Which modules/interfaces are affected, and **which files the fix will change**
- What behaviors need to be verified via tests
- Whether this is a regression, missing feature, or design flaw

### 4. Design TDD fix plan

Create an ordered list of RED-GREEN cycles (vertical slices):

- **RED**: a specific test that captures the broken/missing behavior
- **GREEN**: the minimal code change to make that test pass

Rules:

- Tests verify behavior through public interfaces, not implementation details
- One test at a time (NOT all tests first, then all code)
- **Durability**: describe behaviors and contracts, not internal structure. A good
  fix plan reads like a spec, a bad one reads like a diff

For TDD philosophy → see the **tdd** skill. The project's own test recipes come with
the rules for its spec files: `.claude/hooks/lib/lemony.sh rules match --path=<path>`
on a spec path names them: `Read` those. Until the project migrates its playbooks
(`docs/playbooks/`), read the ones that cover the work at hand.

### 5. Declare the risk surfaces

This is the declaration of **what kind of damage this change can do**, made at the
structuring moment, outside the Reviewer, and visible to the human before execution. A
full-SDD task makes the same declaration as `[risk: …]` tags on the group headers of its
`tasks.md`, which lives on the task branch. Here it lives in the **issue body**. A tool
that wants every declaration reads both places.

One line per surface — a class paired with **one concrete file the fix changes**, never
a module in the abstract — using the same vocabulary as [`prd-to-spec`](.claude/skills/prd-to-spec/SKILL.md); each class names
what kind of damage the surface can do:

<!-- risk-vocabulary:start -->

| Class             | Surface                                                          |
| ----------------- | ---------------------------------------------------------------- |
| `auth`            | authentication, authorization, session or token handling         |
| `payments`        | money movement, billing, pricing                                 |
| `shell-process`   | shell invocation, subprocess spawning, argument construction     |
| `data-loss`       | writes, deletes, migrations, anything that can destroy user data |
| `secrets`         | credentials, keys, tokens — at rest or in transit                |
| `executable-mode` | file permissions, exec bits, anything that changes what can run  |

<!-- risk-vocabulary:end -->

A fix that carries one class into three files declares three lines:

```
## Risk surfaces
- data-loss: src/storage/sync.ts
- shell-process: src/hooks/run-hook.ts
```

A fix that touches no such surface carries the section with a single line — `- none` —
never an omitted section: the absence of a declaration and a declaration of absence are
different claims, and only the second is auditable. `- none` is a claim about the change,
so make it only when it is true.

Declare it **now**, before the fix is written: a surface named afterwards describes what
happened, it does not declare what could. The human reviews it with the rest of the draft
in the next step and edits it in the issue like any other section — that review is the
first thing the section buys. The second comes at review time: the Reviewer hands the
declared surfaces to [`security-review`](.claude/skills/security-review/SKILL.md), which presses hardest where they point. Nothing
checks it automatically.

If a surface has no home in the vocabulary, declare it as `unclassified` and say what it
can do:

```
- unclassified: src/queue/drain.ts — replays messages, can double-deliver
```

**Never fold it into `- none`.** `- none` claims no such surface exists, and that claim
would be false — an unnameable surface is the one most worth seeing. Do not invent a
one-off class either, and do not edit the table here: it is vendor-owned — generated into
this skill and [`prd-to-spec`](.claude/skills/prd-to-spec/SKILL.md) from one source, so the two always agree — and a local edit
is discarded on the next update. Say in the next step that the vocabulary came up short,
so the human can decide whether it grows.

### 6. Confirm with the user

Present the issue draft: problem summary, root cause analysis, TDD fix plan, and the
declared risk surfaces.
Ask: "Does this look right? Should I create the issue?" In reuse mode ask instead:
"Does this look right? Should I update issue #<number>?"

### 7. Create (or, in reuse mode, update) the GitHub issue

After confirmation, create with `gh issue create` and the `harness:managed` label.

In reuse mode, update the existing issue instead — never `gh issue create`. The new
body replaces the old one, and the old body's **trace lines** must survive it
byte-identical — a trace line is a one-line link to another issue, such as
`Discovered during #<parent>`, which ties a captured stub to the task it came from.
Don't retype them: you write the triage sections, and
`lemony issue-body keep-trace` carries the trace lines to the top. Read the current body
first (`gh issue view <number> --json body`) and fold the rest of it (where it was seen,
a code pointer) into `## Problem`. If the old body is already a triage of this shape (an
earlier pickup stopped before the branch step), replace its sections rather than
folding them in. Then:

1. `mkdir -p .lemony/tmp && mktemp -d .lemony/tmp/issue-body.XXXXXX` — note
   the directory it prints (`<dir>` below). It is inside the repo and gitignored, so
   the Write tool can use it without a permission prompt.
2. Write the triage body (`## Problem` … `## Affected`, the structure below) to
   `<dir>/new.md` with your **Write** tool — never through the shell (no heredoc, no
   `echo`): a line of prose the shell reads as syntax can cut the body short or run as
   a command.
3. Write it to the issue as **one** Bash call:

```bash
n=<number>; t=<dir> &&
gh issue view "$n" --json body --template '{{.body}}' > "$t/old.md" &&
.claude/hooks/lib/lemony.sh issue-body keep-trace --old="$t/old.md" < "$t/new.md" > "$t/body.md" &&
gh issue edit "$n" --add-label harness:managed &&
gh issue edit "$n" --body-file "$t/body.md" &&
rm -rf "$t" && echo "triage-issue: body written to #$n"
```

Keep the `&&` chain — a failed step stops before the write — and never pipe the
verb's output straight into `gh issue edit`, which writes an empty body when the step
before it fails. Done means the last line printed `triage-issue: body written to #<n>`;
without it nothing was written — report the error, don't rewrite the body by hand.
`harness:managed` is usually there already; adding it again is harmless.
Leave every other label alone: the status labels
belong to whoever called this skill.

Use a structure like:

```
<in reuse mode, keep-trace puts the old body's trace lines here>

## Problem
<one-paragraph summary of the observed behavior>

## Root cause
<the actual cause, traced to file:line>

## Fix plan (TDD)
- [ ] RED: <test capturing behavior 1> → GREEN: <minimal change>
- [ ] RED: <test capturing behavior 2> → GREEN: <minimal change>

## Risk surfaces
- <class>: <path the fix writes to>

## Affected
<modules / interfaces touched>
```

Print the issue URL and a one-line summary of the root cause.

## Uncontemplated Scenarios

When a scenario doesn't clearly fit these rules:

1. Apply the closest matching approach with reasoning
2. **Flag it**: "This scenario isn't covered by the triage-issue skill. I applied
   [approach] because [reason]. Want to update the skill?"
3. Offer to add a new rule for the case
