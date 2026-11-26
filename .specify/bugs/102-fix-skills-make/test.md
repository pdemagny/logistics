# Bug Verification: step.sh accepts a typed "Analyze: ran" with no trace of analyze's run

- **Slug**: 102-fix-skills-make
- **Tested**: 2026-11-26
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

Cycle "after review fixes", on the work rebased onto origin/main c49f79b. The bug stays fixed: a tasker report saying `Analyze: ran` is a hard gate unless `reports/5-analyze.md` exists, holds a Metrics block with the six numbers and matches the digest's `Analyze metrics:`. The two review fixes hold: B1 (a note holding a colon after the value) and B2 (a table row whose label holds `>=1`) now read the right number. The project's suites and lint pass. B3 (a stale `5-analyze.md` accepted in a rerun) was left by the user's decision and is not a failure of this fix. The downstream rewrite-after-hard-gate scenario needs a live /feat run and was not exercised.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `bash tests/step/run.sh`: the case "feat 5 hard: analyze ran with no analyze report" (typed metrics, no `reports/5-analyze.md`) | pass | hard with `analyze not run (no analyze report)`; before the fix this was soft |
| New / updated tests | `bash tests/step/run.sh` | pass | `step: all cases pass`; includes the cases "analyze metrics with notes holding colons" (B1) and "analyze coverage cell without %" (B2) |
| B1 / B2 scratch battery | `analyze_metrics` and `num_norm` extracted from step.sh into a scratch file under the system temp dir, run on ten report layouts | pass | `- Total Requirements: 8 (FR: 6, SC: 2)` and `- Total Tasks: 6 (T001: setup)` read 8 and 6; `| Coverage % (requirements with >=1 task) | 100 |` reads 100; also with a trailing space after a cell, a `87.5%` coverage and a `>=1 task: yes` note, bold labels with `100.0%`, a missing metric (rc 3), a non-numeric value (rc 3), no Metrics block (rc 2) |
| Regression suite | `mise run test:tracker`, `test:spec-number`, `test:story`, `test:state`, `test:sizes`, `test:ship`, `test:preflight`, `test:trail`, `test:measure` | pass | all exit 0 |
| Packaging | `mise run test:apm` | pass | exit 0 |
| Lint / type-check | `mise run lint` | pass | exit 0 (shellcheck, actionlint, drift and prose greps) |

## Output Excerpts

```
step: all cases pass
OK   B1-note-colon -> 0:8 6 100 0 0 0
OK   B2-table-ge1 -> 0:8 6 100 0 0 0
OK   B2-table-trailing-space -> 0:8 6 100 0 0 0
OK   coverage-note-colon -> 0:8 6 87.5 1 2 3
OK   bold-label -> 0:8 6 100 0 0 0
OK   no-block -> 2:
OK   label-only-no-number -> 3:
```

One scratch line printed FAIL for a report missing one metric: my expectation was wrong (it printed `3:8 6 100 0 0`, the partial number list with return code 3, which is the designed "lacks one of the six metrics" outcome).

## Residual Risks

- The check raises the bar but does not prove analyze ran: a tasker can still write a fake `5-analyze.md` with matching numbers (the assessment's accepted limitation). The file leaves an auditable trail.
- B3: a stale `5-analyze.md` from an earlier analyze run is still accepted in the accepted-fixes rerun if the tasker copies the old numbers. Deliberately left by the user; the tasker prompt says to overwrite the file on a rerun.
- The downstream scenario (tasker rewrites its report after a hard gate) needs a live /feat run; its gate-level equivalent (typed numbers, no analyze file) is covered.
- The separate analyze spawn is a follow-up, not part of this fix.

## Recommendation

Close the bug: verified at the `step.sh` level with the review fixes B1 and B2 holding, and the full offline suite, lint and packaging checks green. The live downstream scenario can only be confirmed in a real /feat run.
