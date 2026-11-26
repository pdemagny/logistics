# Bug Verification: step.sh accepts a typed "Analyze: ran" with no trace of analyze's run

- **Slug**: 102-fix-skills-make
- **Tested**: 2026-11-26
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The bug no longer reproduces: a tasker report saying `Analyze: ran` with well-formed `Analyze metrics:` is now a hard gate unless `reports/5-analyze.md` exists, holds a Metrics block with the six numbers, and those numbers equal the digest's. The project's own suites and lint pass, and an independent scratch battery of edge cases behaved as designed. The downstream "rewrite the report after the hard gate" scenario needs a live /feat run and was not exercised; its gate-level equivalent (typed numbers, no analyze file) was.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | scratch cases built from `tests/step/run.sh`'s own setup (system temp dir): `tasker/match` digest with typed metrics and no `reports/5-analyze.md`, `step.sh feat <state> 5 <report>` | pass | prints `hard:` with `analyze not run (no analyze report)`; before the fix this was `soft` (assessment, step 2) |
| New / updated tests | `bash tests/step/run.sh` | pass | `step: all cases pass`; includes the 4 new hard cases and the soft-layout case |
| Scratch edge cases | coverage-only mismatch; critical-count mismatch; empty analyze file; metrics numbers above the Metrics heading; CRLF file; `100.0%` vs `100%`; `5-analyze.md` a directory; happy path | pass | hard on mismatches, empty, outside-block and directory; soft on CRLF, `100.0%` and the happy path |
| Regression suite | `mise run test:tracker`, `test:spec-number`, `test:story`, `test:state`, `test:sizes`, `test:ship`, `test:preflight`, `test:trail` | pass | all exit 0 |
| Packaging | `mise run test:apm` | pass | exit 0 |
| Lint / type-check | `mise run lint` | pass | exit 0 (shellcheck, actionlint, drift and prose greps) |
| Docs / prompt consistency | read the diff of `feat-tasker.agent.md`, `SKILL.md`, `docs/workflow.md` | pass | all three name the saved report and the hard reasons that `step.sh` prints |
| Downstream rewrite-after-hard-gate scenario | needs a live /feat run | not-run | not reproducible offline, as the assessment says |

## Output Excerpts

```
step: all cases pass
OK  S1 no reports/5-analyze.md at all -> hard: no analyze report
OK  S2 coverage differs -> hard: differ
OK  S4 empty analyze report -> hard: no Metrics block
OK  S5 numbers outside the block -> hard: lacks one
OK  S6 CRLF layout -> soft
OK  S7 100.0% vs 100% -> soft
OK  S9 happy path -> soft
```

One scratch case (`Analyze: not run` with no reason) went to `reformat`, because the format requires a reason after `not run`: a mistake in my scratch input, not a defect.

## Residual Risks

- The check raises the bar but does not prove analyze ran: a tasker can still write a fake `5-analyze.md` with matching numbers (the assessment's accepted limitation). The file does leave an auditable trail.
- The gate looks only at the file on disk. A digest whose `Wrote:` omits `5-analyze.md` is still soft when the file exists and matches (probed). This is consistent with the design and harmless.
- A stale `5-analyze.md` from an earlier run could match a later digest. The tasker is told to overwrite it on a rerun.
- The separate analyze spawn (the report's optional idea) is a follow-up, not part of this fix.

## Recommendation

Close the bug: verified at the `step.sh` level, with the full offline suite, lint and packaging checks green. The live downstream scenario can only be confirmed in a real /feat run.
