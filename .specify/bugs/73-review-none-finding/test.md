# Bug Verification: Review merge turns a `- none` item into a finding the user must answer

- **Slug**: 73-review-none-finding
- **Tested**: 2026-11-23
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The original symptom no longer reproduces: a 7a+7b report whose Bugs, Spec and Security lists are a bare header plus `- none` now merges to 0 findings and a soft gate, the same output as the all-`none` report. With the fix removed from a scratch copy, the same input still gives `refused: B1, B2, S1 need an answer`. `mise run test:step`, `mise run lint` and `mise run test:apm` all pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | scratch copy of the worktree under the system temp dir; `tests/step/fixtures/agents/code-reviewer/7a+7b-zero.md` replaced by the `- none` fixture (the assessment's steps); `bash tests/step/run.sh` against the goldens | pass | all cases pass, including `override-after-review`, which ships with `answer: approved (user: "ship it")` |
| Reproduction (pre-fix control) | same scratch copy with the fix's block removed from `pclose` in step.sh (and the design dash-none case removed from run.sh) | fail, as expected | `override-after-review` prints `refused: B1, B2, S1 need an answer`: the symptom is real and the fix is what removes it |
| Mixed report | scratch copy, Bugs = one real `rec: apply` finding, Spec and Security = `- none` | pass | the gate follows the real finding (`answered`, spawns the review-fix implementer); no `none` finding, no hard gate, no refusal |
| New tests | `mise run test:step` (cases `code-dash-none`, `design-dash-none`) | pass | `step: all cases pass` |
| Regression suite | `mise run test:step` | pass | no existing golden changed |
| Lint / shellcheck | `mise run lint` | pass | exit 0 |
| APM package test | `mise run test:apm` | pass | exit 0 |

## Output Excerpts

```
[test:step] $ bash tests/step/run.sh
step: all cases pass

pre-fix control (scratch):
FAIL answers: an override after a soft 7 with nothing to apply: override-after-review: stdout differs from expected/override-after-review.out
  output:
refused: B1, B2, S1 need an answer
```

## Residual Risks

- A list holding `- none` next to real items is left as before (out of scope in the assessment); not exercised here beyond the mixed case across different lenses.
- The "write `none` for an empty field or section" wording of the other agents' formats was not changed; step.sh now tolerates the form for all of them.
- No source file was edited; scratch copies were removed.

## Recommendation

Close the bug: verified. The reproduction fails without the fix and passes with it, and the project's checks pass.
