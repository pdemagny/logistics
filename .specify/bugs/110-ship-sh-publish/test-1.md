# Bug Verification: ship.sh publish pushes onto a stale base when main moved during the checks

- **Slug**: 110-ship-sh-publish
- **Tested**: 2026-11-27
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The symptom no longer reproduces: with origin/main advanced between prepare and publish, `ship.sh publish` pushes nothing, opens no PR and reports `PR: conflict` with `Conflicts: none` (exit 1), in ship, fix and rebase mode. The new tests fail when the `base_check` call is disabled (publish then exits 0 and opens the PR, the original bug), and lint and the ship, step and apm suites pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `mise run test:ship` (cases "stop: main moved since prepare (ship)", "(fix)", "rebase: main moved since prepare resets to the lease"): prepare, advance origin/main from outside, publish | pass | exit 1, `PR: conflict`, `Conflicts: none`, nothing pushed, no `pr create`, HEAD unchanged; rebase mode back on the lease. Same sequence as the assessor's scratch repro, run through the repo's own harness (stub gh, real state.sh, secret-scan.sh, spec-number.sh) |
| Reproduction without the fix (mutation) | copy of tests/ship and scripts under the temp dir, the `base_check` call in `publish()` replaced by `:`, `bash tests/ship/run.sh` | fail as expected | "stop: main moved since prepare (ship)" fails: exit 0, `PR: https://github.com/o/r/pull/42`, i.e. the original bug; the test does detect it |
| Retry path | "stop: main moved after the push, publish again still opens the PR" | pass | a retry after a post-push `gh pr create` failure still opens the PR |
| Renumber-at-publish cases | "ship: renumbered at publish" and "stop: a gh failure after a renumber, …" | pass | the two modified tests, assertions and `ship-renumber.out` unchanged |
| Ship tests | `mise run test:ship` | pass | 65 cases |
| step.sh | `mise run test:step` | pass | `step: all cases pass`; step.sh already accepts `PR: conflict` and routes it to the move (shipper schema `^(https?://...|blocked|conflict)$`, `Conflicts:` not validated) |
| APM | `mise run test:apm` | pass | exit 0 |
| Lint | `mise run lint` | pass | exit 0 (shellcheck, actionlint, drift and wording greps) |

## Output Excerpts

```
ok stop: main moved since prepare (ship)
ok stop: main moved since prepare (fix)
ok stop: main moved after the push, publish again still opens the PR
ok rebase: main moved since prepare resets to the lease
ship tests: 65 cases in 16s
```

Mutation run (base_check call disabled):

```
FAIL stop: main moved since prepare (ship): exit 0, want 1
PR: https://github.com/o/r/pull/42
```

## Residual Risks

- A failed `git fetch` in publish is not covered by a test of its own; it uses the same `fetch_default`/`gx` path as prepare, which blocks with `! git fetch: …`.
- The race is narrowed, not removed: a merge right after the push still conflicts on GitHub; `/feat rebase` remains the remedy (stated in docs/workflow.md).
- No cap on the ship-mode move-then-ship-again loop when main keeps moving (a recorded follow-up).
- Not exercised end to end with a real `gh` and a live GitHub remote; the stub `gh` was used.
- `PR: conflict` with `Conflicts: none` now has a second meaning, documented in the shipper agent and move.md.

## Recommendation

Close the bug: verified. The reproduction is covered by tests that fail without the fix and pass with it, and no regression appeared in the ship, step or apm suites or in lint.
