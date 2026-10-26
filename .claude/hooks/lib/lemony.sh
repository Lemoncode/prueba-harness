#!/usr/bin/env bash
# Lemony — CLI launcher.
#
# The harness's hooks, agents and commands invoke the telemetry CLI (`lemony
# emit …`). Calling the bare `lemony` binary is fragile: an `npx …` install
# leaves nothing on PATH, and a Node version manager (fnm/nvm) drops the
# global bin when the active version changes, so `command -v lemony`
# silently fails and telemetry is skipped.
#
# This launcher resolves the CLI deterministically, preferring the project-local
# devDependency bin (which survives PATH / Node-manager churn because it lives in
# the repo's own `node_modules`), then a global install:
#
#   1. <repo-root>/node_modules/.bin/lemony   — the devDependency (canonical)
#   2. a `lemony` on PATH                      — a global install
#
# Deliberately NO `npx` fallback: the package is private on GitHub Packages, so an
# `npx @lemoncode/lemony` in a hook (no `GITHUB_TOKEN` in the env) can't auth and
# would 401 or, worse, hang the SessionEnd hook on a network stall with no timeout —
# the exact reason init.sh avoids npx too. When neither resolves, fail fast with exit
# 127 and a one-line hint; callers (session-close, …) fail open on that.
#
# Call it with the CLI args, e.g. `.claude/hooks/lib/lemony.sh emit …`. It
# `exec`s the resolved CLI, so its exit code and stderr are the CLI's own — callers
# keep their existing fail-open / forward-the-error handling. Not a lifecycle hook
# (no stdin envelope, no exit-2 block) — a thin dispatcher.
set -u

# Repo root from the launcher's own location (.claude/hooks/lib/ → up three), so
# resolution is independent of the caller's cwd and of any git state.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

LOCAL_BIN="$ROOT/node_modules/.bin/lemony"
if [ -x "$LOCAL_BIN" ]; then
  exec "$LOCAL_BIN" "$@"
elif command -v lemony >/dev/null 2>&1; then
  exec lemony "$@"
else
  echo "lemony: CLI not found — add the devDependency (\`npm i -D @lemoncode/lemony\`) or install it globally. Skipping." >&2
  exit 127
fi
