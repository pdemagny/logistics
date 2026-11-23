# Bug Verification: Reviewer reports left unwritten, and one missing report cancels the batch's reformat turn

- **Slug**: 82-reviewer-reports
- **Tested**: 2026-11-23
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The assessment's reproduction no longer reproduces: with 7c's slip and 7d's report missing, `step.sh` now answers `reformat` with a 7c reformat spawn plus a fresh 7d review spawn (logged `fresh spawn 1 of 1`), where the pre-fix `step.sh` (HEAD) gave `hard:` with `report missing: 7-7d.md` and no reformat. The step suite and every other `mise run` check pass. The six report-writing agents carry the rule; the model-behaviour half (an agent actually writing its report) is not testable offline.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix), pre-fix control | Scratch script in the system temp dir: reuses the setup and helpers of `tests/step/run.sh`, runs a `/feat` 7 medium batch with 7a, 7b, the 7c slip fixture (`Performance (7c):` then `none`), 7d present or absent, against HEAD's `step.sh` and the worktree's | pass | HEAD: 7d present gives reformat for 7c; 7d absent gives `hard:` with `report missing: 7-7d.md` and `unparsable: 7-7c.md`, no spawn (symptom reproduced). Worktree: 7d absent gives `reformat` with a 7c reformat spawn, a fresh 7d `mode: review` spawn, and a `boundary:` call with `sum=` for 7a and 7b only |
| Log of the re-spawn | same scratch run, state file tail | pass | `- [!] 7 Code review — report missing: 7-7d.md; fresh spawn 1 of 1` after the 7c reformat line |
| New / updated tests | `mise run test:step` | pass | `step: all cases pass`, includes the 7 new cases (`batch-missing*`, `feat7e-missing`, `fix4-missing`): second miss hard, other failed check hard, snapshot change hard, 7e and `/fix` 4 variants |
| Agent rule present | `grep` for the rule in `.apm/agents/feat-*.agent.md` | pass | code-reviewer, design-reviewer, specifier, planner, tasker, bug-assessor each carry it; the two reviewers limit "no report path" to a request with no `report:` key and no path; shipper and brief-reviewer untouched, as the assessment recommends |
| Regression suite | `mise run test:apm`, `test:state`, `test:story`, `test:sizes`, `test:ship`, `test:tracker`, `test:spec-number`, `test:measure`, `test:trail`, `test:preflight`, `test:secret-scan` | pass | all exit 0 |
| Lint / type-check | `mise run lint` | pass | exit 0 (shellcheck, actionlint, prompt greps, harness `/feat`-word grep); the README marketplace notice is informational |

## Output Excerpts

```
HEAD step.sh, 7d missing:
hard:
- report missing: 7-7d.md
- unparsable: 7-7c.md: line 2 (Performance (7c)) — not a "- " item at column 0

Worktree step.sh, 7d missing:
reformat
spawn: feat-code-reviewer   row: 7c   mode: reformat   from: .../7-7c.md
spawn: feat-code-reviewer   row: 7d   mode: review     report: .../7-7d.md
log: - [!] 7 Code review — report missing: 7-7d.md; fresh spawn 1 of 1

mise run test:step: step: all cases pass
```

## Residual Risks

- The agent half (a reviewer writing its report with Write instead of handing it back) is model behaviour; only the prompt text was checked, not a live run.
- As fix.md notes, a Log line between a respawn and its boundary call that `reformat_keys` does not skip (for example `- [!] tracker:`) renews the reformat and respawn allowances; unchanged behaviour for the reformat turn.
- The `/feat` and `/fix` coordinators' reading of a `reformat` verdict that holds a fresh `mode: review` spawn was checked in `harness.md` and the goldens only, not in a live run.

## Recommendation

Close the bug: the reproduction is fixed (pre-fix control reproduces it, post-fix gives the per-group respawn plus the reformat turn), and all test and lint tasks pass. Watch the next `/feat` or `/fix` reviewer batch for a live confirmation that the agents write their own reports.
