# Bug Verification: Review gate goes hard when the coordinator logs to the state file during a review

- **Slug**: 76-review-snapshot-state
- **Tested**: 2026-11-23
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The assessment's reproduction (snapshot, `state.sh log` on the state file, unchanged) now prints `unchanged` instead of `changed` / `- specs/x/feat-state.md`, whether the state file is tracked or untracked. A change to any other non-report file in the same window is still caught and listed. `mise run test:state`, `mise run test:step` and `mise run lint` all pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | scratch script `/tmp/t76/scratch.sh <worktree>`: fresh git repos, `state.sh snapshot`, `state.sh log` on the state file, `state.sh unchanged` | pass | `unchanged` for a log line (tracked and untracked state file), for a raw append to the state file and for a state file at the repo top; 12 of 12 checks pass |
| Reproduction control (pre-fix) | same script against `git show HEAD:` copy of `state.sh` | fail (expected) | 3 checks fail on the old script: tracked log, tracked raw edit, untracked log all print `changed`; so the script discriminates |
| Other changes still caught | same script | pass | edit of a tracked file, new file, new sibling file in the state file's dir, and a same-named `feat-state.md` in another dir are each reported; a state-file log plus a new file lists only the new file; `reports/` is still ignored |
| New / updated tests | `mise run test:state` | pass | `unchanged: edit to a modified file, new file, deleted file` ok, `all state tests passed` |
| New / updated tests | `mise run test:step` (cases `feat 7 medium: a state-file log line between the 7e spawn and its boundary stays soft` at tests/step/run.sh:1456, `fix 4 small: a state-file log line between the spawn and its boundary stays soft` at :1549) | pass | `step: all cases pass` |
| Lint / type-check | `mise run lint` | pass | exit 0, shellcheck clean; the only output is README install-line advice that does not change the verdict |
| Source untouched by this stage | `git diff --stat` | pass | the five files the fix lists (state.sh, tests/state/run.sh, tests/step/run.sh, docs/workflow.md, docs/design.md); this stage edited no source |

## Output Excerpts

```
PASS tracked: log keeps unchanged
PASS tracked: other file edit caught
PASS tracked: state log + new file lists new file only
PASS untracked: log keeps unchanged
PASS sibling file in state dir caught
PASS same basename in other dir caught
(12 PASS, 0 FAIL on the fixed state.sh; 3 FAIL on the pre-fix state.sh)

ok unchanged: edit to a modified file, new file, deleted file
all state tests passed
step: all cases pass
lint exit=0
```

## Residual Risks

- A reviewer that writes the state file is no longer caught by the snapshot. This is the trade the report author chose (the fix lists it under Follow-ups); reviewers are still instructed to write only their report.
- The scratch checks for a top-level state file and for an absolute path from a subdirectory pass on the old script too, so they confirm the fix does not break those layouts but do not prove the fix there.
- I did not run the two new `tests/step` cases against the old `state.sh` (that would mean editing source); the scratch script and the `tests/state` case cover the pre-fix failure.
- Not exercised end to end: a real `/fix` or `/feat` run with a failed board move.

## Recommendation

Close the bug: verified. The snapshot ignores every change to the state file, other worktree changes are still caught, and the state, step and lint suites are green.
