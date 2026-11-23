# Quickstart: validating setup-trail-scripts

Prerequisites: `mise install` in the repo (shellcheck, gh, git). Everything
below is offline.

## Automated

```sh
mise run lint             # shellcheck (new scripts and tests), replaced-prose greps
mise run test:trail       # rotate, sections, slug, redact (+ secret-scan on every output)
mise run test:preflight   # every argument kind, exit 0/1/2, hooks, slug dedupe, worktree mode
mise run test:step        # review.diff written, rewritten, absent on an empty diff; new keys
mise run test:secret-scan && mise run test:tracker && mise run test:ship \
  && mise run test:state && mise run test:story && mise run test:sizes \
  && mise run test:spec-number && mise run test:measure
mise run test:apm         # preflight.sh and trail.sh land with the package
```

Expected: every task exits 0. Contracts: [preflight](contracts/preflight.md),
[trail](contracts/trail.md), [review diff](contracts/review-diff.md).

## By hand, in a scratch clone

1. `bash .apm/skills/feat/scripts/preflight.sh feat no-such-brief` → exit 1,
   `stop:` and one `searched:` line per checkout and worktree.
2. `bash .apm/skills/feat/scripts/preflight.sh fix '#29'` (gh logged in) →
   `kind: issue`, `title:`, `author:`, `slug: 29-…`, exit 0.
3. Write `password=hunter2` and a private-key block (the private-key
   rule's begin line through an end line) to a file under `/tmp`, run `bash .apm/skills/feat/scripts/trail.sh redact <file>` →
   prints `2`; the file reads `password=<redacted>` and one `<redacted>` line;
   a second run prints `0`.

## After merge (SC-001, SC-002)

On the first `/feat` and `/fix` runs: count the coordinator's calls before
the first spawn (3: preflight, `EnterWorktree`, worktree mode + init; 4 for
`/feat` with a board issue, the building move being its own call), and
check the code reviewers' transcripts hold no `git diff`/`git status`/`git
log` call made to find the diff.
