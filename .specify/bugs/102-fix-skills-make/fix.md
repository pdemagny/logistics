# Bug Fix: step.sh accepts a typed "Analyze: ran" with no trace of analyze's run

- **Slug**: 102-fix-skills-make
- **Fixed**: 2026-11-26
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`/feat` phase 5 now takes `Analyze: ran` only with evidence on disk: the tasker saves analyze's own report verbatim to `reports/5-analyze.md`, and `step.sh` reads the six numbers under its Metrics line and requires them to equal the digest's `Analyze metrics:`. A missing file, a file without a Metrics block or one of the six numbers, or different numbers is a hard gate.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | `num_norm`, `analyze_metrics` (loose parse of the Metrics block: `- Label: n`, `**Label**: n`, table rows, `100%`/`100.0%`), `analyze_proof`; `dec_feat_5` calls it when `ran` comes with metrics |
| `.apm/agents/feat-tasker.agent.md` | modified | the tasker writes analyze's report verbatim to `reports/5-analyze.md` (overwritten on a rerun) and lists it on `Wrote:` |
| `.apm/skills/feat/SKILL.md` | modified | phase 5 hard-gate prose names the new reasons |
| `docs/workflow.md` | modified | phase 5 tasker section describes the saved report and the check |
| `tests/step/run.sh` | modified | `put_analyze` helper; every `tasker/match` use (cases, full runs, `many_tasks`) puts the analyze report; five new cases; `analyze.md` skipped by the gate-row format loop (it is not an agent report) |
| `tests/step/fixtures/agents/tasker/analyze.md` | added | an analyze report in its template's shape |
| `tests/step/fixtures/agents/tasker/match.md` | modified | `Wrote:` lists `reports/5-analyze.md` |
| `tests/step/expected/feat5-{no-analyze,analyze-no-block,analyze-short,analyze-differ,soft-layout}.*` | added | goldens of the new cases |

## Diff Highlights (optional)

```bash
      elif ! pget 'Analyze metrics' || [[ $V == none ]]; then
        reason 'analyze not run (ran without its metrics)'
      else
        # and they must be analyze's own, saved in reports/5-analyze.md (#102)
        analyze_proof "$V"
      fi
```

Reasons: `analyze not run (no analyze report)`, `analyze not run (no Metrics block in 5-analyze.md)`, `analyze not run (5-analyze.md lacks one of the six metrics)`, `analyze metrics differ from 5-analyze.md`.

## Tests Added or Updated

- `tests/step/run.sh` "feat 5 hard: analyze ran with no analyze report" — `ran` with metrics and no file is hard.
- "feat 5 hard: analyze report without its Metrics block" — the file without its `**Metrics:**` line is hard.
- "feat 5 hard: analyze report without one of the six metrics" — a missing bullet is hard.
- "feat 5 hard: analyze metrics differ from the analyze report" — digest 9 requirements vs file 8 is hard.
- "feat 5 soft: analyze metrics in another layout" — a `## Metrics` heading with a table, bold labels and `100.0%` still matches (loose parse).
- Every existing `tasker/match` case now puts `reports/5-analyze.md`; their goldens are unchanged.

## Local Verification

- Commands run: `bash tests/step/run.sh` → all cases pass; `mise run lint` → pass (after fixing one SC1087 in the new code); `mise run test:apm` → pass.
- Manual checks: reviewed the new goldens (hard reasons and the soft spawn as expected); no existing golden changed.

## Deviations from Assessment

- The format-check loop over `tests/step/fixtures/agents/*/` skips `analyze.md`, as it skips `tasks.md`: it is analyze's report, not a tasker digest. Not listed in the assessment's files.
- A file holding the Metrics line but missing one of the six numbers gets its own reason (`lacks one of the six metrics`) rather than the "no Metrics block" one.

## Follow-ups

- Run analyze as its own fresh spawn after the tasker (the report's optional idea); to be filed as a follow-up issue, per the user's answer.
