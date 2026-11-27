# Bug Verification: ship.sh publish pushes onto a stale base when main moved during the checks

- **Slug**: 110-ship-sh-publish
- **Tested**: 2026-11-27
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

After the review fixes (the `pushed_at_head` helper now used by `base_check`, `lease_push` and `publish_ship`), publish still pushes nothing and reports `PR: conflict` with `Conflicts: none` when origin/<default> moved since prepare, in ship, fix and rebase modes. A retry after a post-push gh failure still works. With `base_check` disabled in a scratch copy, the bug returns. The rest of ship.sh's changed region shows no collateral damage.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `mise run test:ship` (cases: main moved since prepare (ship), (fix), main moved after the push then publish again, rebase: main moved since prepare resets to the lease) | pass | 65 cases, all `ok` |
| Bug returns without the fix | Scratch copy of tests and scripts under the temp dir, `base_check` call in `publish` replaced by `:`, `bash tests/ship/run.sh` | pass (fails as expected) | `FAIL stop: main moved since prepare (ship): exit 0, want 1`; the PR URL was printed, so the stale push happens |
| Retry after post-push gh failure | cases `gh pr create fails after the push, publish again opens the PR`, `main moved after the push, publish again still opens the PR`, `a refused push, then publish again` | pass | `pushed_at_head` skips the push on retry |
| Collateral damage review | `git diff HEAD -- .apm/skills/feat/scripts/ship.sh`, `bash -n` | pass | Only the header comment, `pushed_at_head`, `base_check`, the `lease_push` and `publish_ship` replacements and the `base_check` call in `publish` changed; nothing else touched |
| Lint | `mise run lint` | pass | exit 0 (shellcheck, actionlint, apm validation, greps) |
| Step tests | `mise run test:step` | pass | `step: all cases pass` |
| APM tests | `mise run test:apm` | pass | exit 0 |

## Output Excerpts

```
ok stop: main moved since prepare (ship)
ok stop: main moved since prepare (fix)
ok stop: main moved after the push, publish again still opens the PR
ok rebase: main moved since prepare resets to the lease
ship tests: 65 cases in 17s
```

Mutation (base_check disabled): `FAIL stop: main moved since prepare (ship): exit 0, want 1`.

## Residual Risks

- The check is a fetch followed by a push, so main can still move in the window between them; the fix narrows it, as the assessment accepted.
- Live gh and network runs were not exercised; the tests use a stub `gh` and throwaway repos.

## Recommendation

Close the bug: verified end-to-end offline, including the review fixes' refactor.
