# Bug Fix: step.sh accepts an unproven "Analyze: ran" from the tasker

- **Slug**: 97-tasker-reports-analyze
- **Fixed**: 2026-11-24
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The tasker report gains an `Analyze metrics:` line copied from analyze's
`**Metrics:**` block (`none` when analyze did not run). `step.sh` validates its
shape and turns phase 5 hard when `Analyze: ran` comes without it or with
`none`; tasker step 2 now says that anything short of analyze's report is
`not run`.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | `Analyze metrics` in the tasker schema (optional key), `pwant` shape check, `dec_feat_5` reason `analyze not run (ran without its metrics)` |
| `.apm/agents/feat-tasker.agent.md` | modified | step 2 reworded (running analyze means reaching its report; any shortfall is `not run (<why>; cross-checked by hand)`), new format line, digest and last-run rules |
| `.apm/skills/feat/SKILL.md` | modified | phase 5 hard reasons name `ran` without analyze's metrics |
| `docs/workflow.md` | modified | phase 5 prose names the metrics line |
| `tests/step/fixtures/agents/tasker/match.md` | modified | gains a metrics line so the soft cases stay soft |
| `tests/step/fixtures/agents/tasker/ran-no-metrics.md` | added | `Analyze: ran` with no metrics line |
| `tests/step/run.sh` | added tests | three new cases |
| `tests/step/expected/feat5-no-metrics.*`, `feat5-metrics-none.*`, `fmt-tasker-metrics.*` | added | goldens |

## Diff Highlights (optional)

```bash
pwant 'Analyze metrics' '^(none|[0-9]+ requirements, [0-9]+ tasks, [0-9]+(\.[0-9]+)?% coverage, [0-9]+ ambiguities, [0-9]+ duplications, [0-9]+ critical)$'
...
elif ! pget 'Analyze metrics' || [[ $V == none ]]; then
  reason 'analyze not run (ran without its metrics)'
```

## Tests Added or Updated

- `tests/step/run.sh` "feat 5 hard: analyze ran without its metrics" (`feat5-no-metrics`) — `ran` with no metrics line is a hard gate.
- `tests/step/run.sh` "feat 5 hard: analyze ran with metrics none" (`feat5-metrics-none`) — same output as the missing case.
- `tests/step/run.sh` "format: Analyze metrics outside its format" (`fmt-tasker-metrics`) — a malformed line is unparsable and asks for a reformat.
- `feat5-soft`, `feat5-decrease` and the other `tasker/match` users keep their goldens unchanged.

## Local Verification

- Commands run: `mise run lint` → pass; `mise run test:apm` → pass; `mise run test:step`, `test:state`, `test:sizes`, `test:ship`, `test:preflight`, `test:trail`, `test:tracker`, `test:story`, `test:spec-number`, `test:measure` → all pass.
- Manual checks: the new goldens read `- [x] 5 Tasks [hard] — analyze not run (ran without its metrics)` and the reformat reason `line 10 (Analyze metrics) — a value outside its format`.

## Deviations from Assessment

- The metrics line follows the fields analyze's `**Metrics:**` block actually has (requirements, tasks, coverage, ambiguities, duplications, critical), not the assessment's example (critical/high/medium/low counts), so the tasker copies numbers rather than computing them.
- A malformed metrics line is unparsable (a reformat, as every other field outside its format) rather than a hard gate; missing or `none` beside `ran` is the hard gate.
- The hard reason reads `analyze not run (ran without its metrics)`, the assessment's `analyze not run` with the cause added.
- The optional cross-check of severity counts against `Open findings` is not done: analyze's metrics carry only a critical count, and a count mismatch after fixes would give false hard gates.
- `today-layout.md` is left as is: that case is unparsable at `Wrote:` before any gate, and a new line would only shift its golden line numbers.

## Follow-ups

- `specs/013-step-command/contracts/agent-formats.md` still shows the old tasker format; it is a shipped spec's record and was left untouched.
