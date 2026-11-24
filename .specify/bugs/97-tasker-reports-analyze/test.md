# Bug Verification: step.sh accepts an unproven "Analyze: ran" from the tasker

- **Slug**: 97-tasker-reports-analyze
- **Tested**: 2026-11-24
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The original symptom no longer reproduces: a tasker report with `Analyze: ran` and no `Analyze metrics:` line (or `none`) now gives a hard phase 5 gate with reason `analyze not run (ran without its metrics)`, where before it was soft. The new tests fail against the previous `step.sh` and pass against the fixed one, and the lint and all offline suites pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `bash tests/step/run.sh` case `feat5-no-metrics` (`tasker/ran-no-metrics.md`, `step.sh feat <state> 5 <report>`) | pass | Output is `hard:` with `analyze not run (ran without its metrics)`; the logged gate is `[hard]`; the first implementer is not spawned. |
| Reproduction control (pre-fix) | `tests/` and `.apm/` copied to a temp dir with `step.sh` taken from `HEAD`, then `bash tests/step/run.sh` | pass | The new case fails against the old script (`soft`, implementer spawned), so the test does catch the bug. |
| New / updated tests | `mise run test:step` | pass | `step: all cases pass`, including `feat5-no-metrics`, `feat5-metrics-none` (same output as the missing case) and `fmt-tasker-metrics` (malformed line asks for a reformat); `feat5-soft` and `feat5-decrease` stay soft with the metrics line added to `match.md`. |
| Format agreement | Read `speckit-analyze` SKILL.md `**Metrics:**` block against the `Analyze metrics` regex and the tasker format line | pass | The six fields (requirements, tasks, coverage %, ambiguities, duplications, critical) match analyze's block; decimal coverage is allowed. |
| Agent, step.sh, skill and docs agree | Read `git diff` of `feat-tasker.agent.md`, `step.sh`, `feat/SKILL.md`, `docs/workflow.md` | pass | Schema key is optional; step 2 reworded; digest rule names `Analyze metrics`; phase 5 hard reasons and workflow prose name it. |
| Regression suites | `mise run test:apm`, `test:state`, `test:sizes`, `test:ship`, `test:preflight`, `test:trail`, `test:tracker`, `test:story`, `test:spec-number`, `test:measure` | pass | All exit 0. |
| Lint | `mise run lint` | pass | Exit 0. The Last step paragraph check across the six agents passes. |

## Output Excerpts

```
step: all cases pass
```

```
hard:
- analyze not run (ran without its metrics)
- [x] 5 Tasks [hard] — analyze not run (ran without its metrics)
```

Control run with the old `step.sh`:

```
FAIL feat 5 hard: analyze ran without its metrics: ...
  output:
soft
...
spawn: feat-implementer
```

## Residual Risks

- Metrics are still written by the model, so a fabricated line passes. The field raises the bar but does not prove execution (noted in the assessment).
- The severity counts are not cross-checked against `Open findings` (a documented deviation).
- `specs/013-step-command/contracts/agent-formats.md` still shows the old tasker format (a documented follow-up).
- A real `/feat` run with the reworded tasker was not exercised, so the agent obeying its step 2 is untested.

## Recommendation

Close the bug: verified. The gate behaves as the assessment specifies, the tests fail without the fix and pass with it, and nothing else regressed.
