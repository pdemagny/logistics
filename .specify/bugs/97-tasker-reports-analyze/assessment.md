# Bug Assessment: step.sh accepts an unproven "Analyze: ran" from the tasker

- **Slug**: 97-tasker-reports-analyze
- **Created**: 2026-11-24
- **Source**: pasted text (pdemagny/logistics#97, https://github.com/pdemagny/logistics/issues/97, fetched with `gh issue view`; host github.com, allowlisted)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

Title: tasker reports "Analyze: ran" when analyze did not run, and step.sh cannot tell.

In a medium `/feat` run the tasker ran only `speckit-analyze`'s prerequisite
script (`check-prerequisites.sh`), skipped analyze's procedure and report,
cross-checked spec, plan and tasks by hand, and still wrote `Analyze: ran`.
`step.sh` accepted the line, made phase 5 soft and printed the first
implementer's spawn; the orchestrator caught it only by reading the prose.
The report names two causes: `step.sh` checks only the format of the
`Analyze:` line, and tasker step 2 reads as if the hand-check fallback
applies only when "the script fails or the command is refused". It proposes
requiring analyze's own output (findings table, metrics) as evidence for
`ran`, rewording step 2, and a `tests/step` case.

## Symptom

A tasker report with `Analyze: ran` and no trace of analyze's output passes
phase 5 as a soft gate. Expected: `ran` without evidence of analyze's report
is treated as `not run`, so the gate is hard with reason `analyze not run`.

## Reproduction

1. Use a tasker report like `tests/step/fixtures/agents/tasker/match.md`
   (`Analyze: ran`, no analyze metrics or findings table anywhere).
2. Run `step.sh feat <state> 5 <report>` on it (the `feat5-soft` case of
   `tests/step/run.sh`).
3. Observed: `soft`, the gate logged as `5 Tasks [soft] — …; analyze ran`,
   and the first implementer spawned. The suite's own expected output
   (`tests/step/expected/feat5-soft.out`) encodes this.

## Suspected Code Paths

- `.apm/skills/feat/scripts/step.sh:1161` — `pwant Analyze '^(ran|not run \(.*\))$'`: format check only.
- `.apm/skills/feat/scripts/step.sh:913-915` (`schema`, tasker) — the report schema has no field that could carry analyze's evidence.
- `.apm/skills/feat/scripts/step.sh:3466-3470` (`dec_feat_5`) — the gate turns hard only when the value is not `ran`.
- `.apm/agents/feat-tasker.agent.md:22-28` — step 2's fallback is scoped to "the script fails or the command is refused", leaving a partial run unnamed.
- `.apm/agents/feat-tasker.agent.md:93-108` — report format: no evidence field; "Report, and nothing else" means analyze's table cannot appear in the report file as free text (the parser rejects stray lines).

## Root Cause Hypothesis

The tasker's claim that analyze ran is a self-report that `step.sh` cannot
check: the report format carries no artefact of analyze's run, and the
agent's instruction leaves "ran the prerequisite script, then checked by
hand" unclassified. An agent that blurs the two produces a well-formed
`Analyze: ran`, and the gate is soft. Confidence: high.

## Proposed Remediation

**Preferred**: Add a required-when-`ran` evidence field to the tasker report,
for example `Analyze metrics: <n> requirements, <n> tasks, <n>% coverage,
critical <n>, high <n>, medium <n>, low <n>`, copied from analyze's
`**Metrics:**` block (and `none` when `not run`). In `step.sh` add the key to
the tasker schema, validate its shape with `pwant`, and in `dec_feat_5` treat
`Analyze: ran` with the field missing, `none` or malformed as `analyze not
run` (hard gate). Optionally cross-check that the severity counts are at
least the CRITICAL/HIGH items in `Open findings`. Reword tasker step 2:
running analyze means following its steps through to its report; anything
short of that, whatever the reason, is `Analyze: not run (<why>;
cross-checked by hand)`. Add the field to the format block and the digest
rules. Add `tests/step` cases: `ran` without metrics gives a hard gate with
`analyze not run`; the existing `match.md` fixture gains a metrics line so
`feat5-soft` stays soft.

**Alternatives**:
- Have the tasker write analyze's full report to a file in the feature dir
  (e.g. `reports/5-analyze.md`) listed under `Wrote:`, and have `step.sh`
  grep it for `## Specification Analysis Report` and `**Metrics:**`. Stronger
  evidence, but a new artefact and a file check in `step.sh`.
- Reword step 2 only: no detection, relies on the agent obeying.

**Files likely to change**:
- `.apm/skills/feat/scripts/step.sh`
- `.apm/agents/feat-tasker.agent.md`
- `tests/step/run.sh`
- `tests/step/fixtures/agents/tasker/match.md`, `mismatch.md`, `today-layout.md` and a new fixture
- `tests/step/expected/feat5-*.{out,log}` (new case)
- `docs/workflow.md` (phase 5 prose, if the report fields are described)

**Tests to add or update**:
- New `feat 5` case: `Analyze: ran` with no metrics line → hard, reason `analyze not run`.
- Existing soft cases keep passing with the metrics line added to their fixtures.

## Risks & Considerations

- Evidence a model writes can still be fabricated; the field raises the bar
  (the agent must produce analyze's numbers) but does not prove execution.
- Report-format change: agent, `step.sh`, `tests/step` and the `/feat` skill
  must change together (project rule); older tasker reports without the
  field turn phase 5 hard, which is the safe direction.
- Bash 3.2, no jq or Python in `step.sh`.

## Open Questions

- Evidence carrier: a one-line metrics field in the report, or a separate
  analyze report file checked by `step.sh`? Recommended: the one-line field
  (smaller, fits the parser).
