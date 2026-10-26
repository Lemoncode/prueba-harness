---
description: 🍋 Pause the current session — write a narrative resume + emit session_closed telemetry.
allowed-tools: Read, Write, Bash(.claude/hooks/session-close.sh --manual), Bash(.claude/hooks/lib/lemony.sh status --local), Bash(.claude/hooks/lib/lemony.sh checkpoint *), Bash(date -u *), Bash(git diff --stat *), Bash(git ls-files --others *)
---

# /pause

**A checkpoint answer comes first.** When the human answered a pending checkpoint
with this `/pause`, or just before it (`ok`, `changes`, `ok_downgrade`), resolve it
before step 1, whatever the auto-commit setting, exactly as the orchestrator does
at any checkpoint (§"Checkpoint contract", items 4–5): the spec check and the
human-delta revalidation first (a red one blocks the OK), on an OK under
auto-commit ON the human-delta commit, then the resolved `progress.md` line and the `checkpoint` verb.
Its commits and emit belong to the checkpoint, not to the pause.

A two-step pause:

1. **Write the resume narrative** so future-you (or whoever resumes) can pick
   up cold:
   - Read the active task's `progress.md` (if any) and the latest note under
     `.claude/state/sessions/<your-user>/` (if any) — that is where the
     narrative lives; `current-<your-user>.md` only holds session timestamps.
   - Generate a UTC timestamp slug — run `date -u +%Y-%m-%dT%H:%M:%SZ` and use
     it as `<ts>`. Pick a short topic slug from the work in progress.
   - Read the task and branch — run `.claude/hooks/lib/lemony.sh status --local`
     (local reads only, no network call): its `Active task:` and `Branch:` lines
     are read off the live branch (a task branch, the `harness/closeout-<id>`
     record branch, or the branch being rebased while a rebase has HEAD
     detached). If it fails, write `null` and `(unknown)`.
   - Write `.claude/state/sessions/<your-user>/<ts>-<topic>.md` with this
     skeleton (fill the body — what you did, where you are, the next step):

     ```markdown
     ---
     session_close_ts: <ts>
     active_task: <the `Active task:` id, or null when it reads (none)>
     branch: <the `Branch:` name without its parenthesised suffix — (unknown) as printed>
     topic: <topic>
     reason: manual
     auto_close: false
     ---

     # Session — <topic> (<ts>)

     <auto-commit OFF only — the unstaged-work line, see below>

     ## What I did

     - …

     ## Where I am

     - …

     ## Next step

     - …
     ```

   - **Auto-commit OFF: the note opens with the unstaged work.** When the task
     runs auto-commit OFF (config pins `implementation.auto_commit: off` on an L1
     task, one with a `spec/tasks.md` in its state directory, or the task's
     `progress.md` carries the `Auto-commit: off` line; an L2 task always commits as
     it goes, whatever the config pins), run — `':/'` scopes both to the whole
     repository, whatever the shell's directory:

     ```bash
     git diff --stat -- ':/' ':(top,exclude).claude/state'; \
       git ls-files --others --exclude-standard --full-name -- ':/' ':(top,exclude).claude/state'
     ```

     and make the first line under the heading say what the output is, which
     depends on where the task stands:
     - **Mid-implementation** (`progress.md` not at `awaiting human checkpoint`):
       the staged index is the last save-point (green, except the red starting
       point of a `(red human delta)` fix-loop) and everything unstaged is
       **unverified by construction** — a hand probe stopped between its mutation
       and its revert looks exactly like work in progress.
       `**Unverified (unstaged since the last save-point):** <files + stat summary>`
       — or `**Unverified:** none` when both print nothing.
     - **At an `awaiting` checkpoint**: every agent save-point was staged at
       presentation, so unstaged work is the human's own edits.
       `**Human delta (unstaged, to revalidate at the checkpoint):** <files + stat summary>`
       — or `**Human delta:** none`.

     Report only: stage, revert, or fix nothing here (a stage now is the
     mid-experiment `add` the staging protocol forbids). Task state under
     `.claude/state` is left out — it is disk-only by design in this mode.

2. **Trigger the session-close hook** so the `session_closed` event lands in
   `events.jsonl` (its `task_id` is derived from the current branch when it is
   a `harness/<id>-<slug>` or `harness/closeout-<id>` task branch, or is being
   rebased) and `current-<your-user>.md` gets its
   `last_close_ts` stamped:

   ```bash
   .claude/hooks/session-close.sh --manual
   ```

The hook prints `git status --porcelain` after emitting — it never
auto-commits. Decide what (if anything) to stage and commit before leaving.
Exception — a task running **auto-commit OFF** (orchestrator §"Auto-commit
OFF"): do **not** commit; the zero-commit deferral binds `/pause` too (an answered
checkpoint was already resolved above, by the `checkpoint` verb).
Leave the staged save-point untouched (it survives the session; staging
anything now is the mid-experiment `add` the protocol forbids), note the pause
in `progress.md` — disk-only, per the mode's contract.
