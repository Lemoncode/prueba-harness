# Review PR — reference

## Review threads already on the PR

Step 0 reads every review thread with one GraphQL query, following every page
(`--paginate` fills `$endCursor`). Each thread brings its opening comment and its
three latest replies — where an author says "fixed in …" or "intentional":

```bash
gh api graphql --paginate \
  -f owner=<org> -f name=<repo> -F number=<number> \
  -f query='query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 50, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            isResolved isOutdated path line originalLine subjectType
            opening: comments(first: 1) { nodes { url body diffHunk author { login } } }
            latest: comments(last: 3) { totalCount nodes { url body author { login } } }
          }
        }
      }
    }
  }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]'
```

Reduce each thread to a block like this for the analysis:

```
[unresolved, outdated] src/foo.ts — line 57 in the thread's original commit
<url of the opening comment>
written on:
  <last 4 lines of the opening comment's diffHunk — more when it spans a range>
@reviewer: <opening body, first ~600 characters, newlines kept>
(2 earlier replies not shown)
@author (reply): <latest reply, first ~300 characters>
```

- Where it sits: `line`; on an outdated thread `line` is `null`, so write
  `line <originalLine> in the thread's original commit` — a line of an older version,
  not of the current diff. A file-level thread (`subjectType: FILE`) has no line:
  write the path alone.
- `written on`: the code the thread was posted on, from its `diffHunk` — what "the
  same code" is matched against, and how an outdated thread's problem is found in the
  code its lines became.
- Replies: the latest ones only, oldest first, skipping the opening comment when it is
  also among them (a thread with no reply has `totalCount: 1`). When `totalCount` is
  above 4, say how many earlier replies are not shown.

## Changed files of a large PR

When `gh pr diff` fails on the size limit (HTTP 406) or the PR changes more than the
100 files `gh pr view --json files` returns (`changedFiles` above 100), read the files
from REST, every page —
each carries its own patch:

```bash
gh api --paginate repos/<org>/<repo>/pulls/<number>/files \
  --jq '.[] | {filename, status, patch}'
```

A file with no `patch` (binary, empty, or too large) is not reviewed; name the
non-empty ones in the dry-run.

## Analysis agent prompt

Pass this to each pass's `Explore` sub-agent — or, as a Reviewer or with no `Agent`
tool (SKILL.md §2), walk it yourself. The five lenses are a **checklist one agent
walks**, not a fan-out.

```
You are reviewing a GitHub PR diff. Find real issues worth posting as inline review
comments. Walk these five lenses in order; a finding can come from any of them:

1. Security — injection, auth/authz gaps, secret exposure, unsafe input reaching a
   sink, OWASP-class issues.
2. Silent failures — swallowed errors, empty catch, a fallback that hides a bug, a
   return where it should throw.
3. Spec compliance — does the diff match the stated intent (issue/spec/PR)? Scope
   drift, missing acceptance criteria.
4. Test gaps — logic-bearing code with no test; a bug fix with no regression test;
   assertions that don't pin the behavior.
5. Senior quality — correctness, edge cases, naming, N+1s, convention violations.

Judge "against convention" using the project context below and the project's rules:
`Read` each rule file listed below before judging. Each one is a convention for the
files its `paths:` frontmatter covers, or for every file when it has none.

Some points are already on the PR, as review threads (listed below) — every thread
counts, whoever started it. Before returning a finding, check it against them.

The same point is the same problem at the same code: the lines the thread sits on, or
the code those lines became. The same kind of problem in another function, file or
instance is a different point.

Then give the finding a status:

- "already-posted" — the PR already holds this point. Either the thread is unresolved
  and you have nothing to add that it or its replies do not already say; or the
  thread is resolved and its problem is still there as it was written on (compare
  with "written on"): the human closed it, fixed or not, and that decision stands —
  even if nearby lines moved. A residual the thread's replies already discuss or
  accept is already posted too.
- "follow-up" — the thread is unresolved and you have something to add that neither
  the thread nor its replies say: part of the problem remains after a partial fix, or
  a consequence the thread did not state. Say exactly what is new. It is never a
  restatement of the thread.
- "new" — no thread makes this point. It is also "new" when a resolved thread's code
  was rewritten (it no longer reads as "written on") and the new code brings the
  problem back: set "thread" to that thread, so the comment can link it.

When unsure between "already-posted" and anything else, it is not "already-posted":
report the finding. A point wrongly held back is lost; a repeat the human can skip.

Do NOT flag:
- Style preferences not in the project context or its rules.
- TODOs explicitly marked as such.
- Changes that are clearly intentional from the diff context.

Return ONLY a JSON array (no markdown, no preamble). Return [] if the diff is clean —
do not manufacture findings. `line` is the line number in the file on the right side
of the diff — never a position in the diff text — and `severity` is exactly one of
`critical`, `important`, `suggestion`.

## Project context
<PROJECT_CONTEXT>

## Project rules
<RULES — one path per line, or "none">

## Already on the PR (review threads)
<THREADS — one block per thread, or "none">

## Changed files
<FILES>

## Diff
<DIFF>
```

## Follow-on pass addendum

Every pass after the first gets the prompt above plus this, with every finding the
earlier passes returned:

```
## This is a follow-on pass: find what the earlier passes missed

Earlier passes over this same diff already found the findings listed under "Already
found in this run" below. They are reported; do not return them again, reworded or
not — the same point is the same problem at the same code.

Your job is only what they missed. Walk the five lenses again over the WHOLE diff,
deliberately looking where the earlier findings are NOT: files and hunks they never
touch, lenses they barely used, and the second instance of a problem they found once.

The bar does not drop because this is a later pass: return only real issues worth an
inline comment, and return [] when nothing real is missing. An empty result is the
expected, good outcome once the review is complete. Code a comment explains as
deliberate is not a finding.

## Already found in this run
<FOUND — the JSON array of the earlier passes' findings>
```

## Output schema

```json
[
  {
    "file": "src/foo.ts",
    "line": 42,
    "side": "RIGHT",
    "lens": "security|silent-failure|spec-compliance|test-gap|senior-quality",
    "severity": "critical|important|suggestion",
    "title": "Short title (max 60 chars)",
    "issue": "What is wrong and why it matters",
    "suggestion": "How to fix it (specific, not generic)",
    "status": "new|follow-up|already-posted",
    "thread": "URL of the thread's opening comment"
  }
]
```

Empty result: `[]`. `thread` is the matched thread's URL, exactly as given: present on
every `follow-up` and `already-posted` finding and on a `new` one that brings a
resolved thread's problem back; absent on any other `new` finding.

`line` must exist on the right side of the diff for that file. `side` is `"RIGHT"` for
added or modified lines.

## Comment body format

Each GitHub review comment body:

````markdown
**<title>** _(<lens>)_

<issue>

```suggestion
<new line content>   ← optional, only for a single-line replacement
```
````

## Dry-run table

| #   | Status | Sev | File | Line | Problem | Suggestion |
| --- | ------ | --- | ---- | ---- | ------- | ---------- |

Severity emoji: 🔴 `critical` · 🟠 `important` · 🟡 `suggestion`.

## GitHub API — batch review

All selected `new` comments go in a **single** API call (one review thread, not N):

```bash
gh api repos/<org>/<repo>/pulls/<number>/reviews \
  --method POST \
  --field commit_id=<headRefOid> \
  --field body='' \
  --field event=COMMENT \
  --field 'comments[][path]=src/foo.ts' \
  --field 'comments[][line]=42' \
  --field 'comments[][side]=RIGHT' \
  --field 'comments[][body]=**Title** _(silent-failure)_ …' \
  --field 'comments[][path]=src/bar.ts' \
  --field 'comments[][line]=23' \
  --field 'comments[][side]=RIGHT' \
  --field 'comments[][body]=**Title** _(security)_ …'
```

Repeat the four `comments[]...` fields per selected `new` finding.

A `new` finding that brings a resolved thread's problem back ends its body with
`Previously raised in <thread URL>.`

## GitHub API — follow-up reply

A selected `follow-up` is posted as a reply in its thread, one call per thread, with
the same body format. The comment id is the number at the end of the thread's URL
(`…#discussion_r<id>`):

```bash
gh api repos/<org>/<repo>/pulls/<number>/comments/<id>/replies \
  --method POST \
  --field body='**Title** _(silent-failure)_ …'
```
