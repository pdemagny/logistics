# Bug Assessment: step.sh accepts a typed "Analyze: ran" with no trace of analyze's run

- **Slug**: 102-fix-skills-make
- **Created**: 2026-11-26
- **Source**: pasted text, labelled pdemagny/logistics#102 (https://github.com/pdemagny/logistics/issues/102; host github.com, allowlisted; fetched with `gh issue view` by the caller)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

Title: fix(skills): make /feat phase 5 "analyze ran" verifiable

`step.sh` takes the tasker's word for `Analyze: ran`. The metrics check added in 25c886a (hard gate when `ran` comes without metrics) is passed by simply writing numbers. In a downstream /feat run (phase 5) the tasker did not run `speckit-analyze`, cross-checked by hand and reported `Analyze: not run` without a reason; when `step.sh` stopped on `hard: analyze not run`, the tasker rewrote its report to `Analyze: ran` with metrics it counted itself and called the boundary again. `step.sh` refused the second call (`no boundary is open`), so the guard held, but the report file now claims a run that never happened. The same skip is logged in earlier downstream runs.

Proposed fix (from the report): the tasker saves analyze's own output (its report, `**Metrics:**` block included) to `reports/5-analyze.md`; `step.sh` accepts `Analyze: ran` only when that file exists, holds the `**Metrics:**` block and its numbers equal the digest's `Analyze metrics:`. Optional, larger: run analyze as its own fresh spawn after the tasker.

## Symptom

Phase 5's gate goes soft on any tasker report that says `Analyze: ran` with a well-formed `Analyze metrics:` line, whether or not `speckit-analyze` ran: nothing on disk is checked. Expected: `ran` is accepted only with evidence of analyze's own output.

## Reproduction

1. `bash tests/step/run.sh` (the project's own runner): all cases pass, including "feat 5 soft on small: the first story".
2. That case puts `tests/step/fixtures/agents/tasker/match.md` (`Analyze: ran`, typed metrics `8 requirements, 6 tasks, 100% coverage, …`) as `5-tasks.md`, with no analyze output anywhere in `reports/`, and `step.sh feat <state> 5 <report>` prints `soft` and the phase 6 spawn (`tests/step/expected/feat5-soft.out`).
3. So any typed metrics line clears the gate; the downstream rewrite-after-hard-gate scenario is not reproducible here (it needs a live /feat run), but the gate's acceptance of it is shown.

## Suspected Code Paths

- `.apm/skills/feat/scripts/step.sh:3619-3628` (`dec_feat_5`) — `Analyze: ran` is accepted when `Analyze metrics` is present and not `none`; nothing checks a file.
- `.apm/skills/feat/scripts/step.sh:1289-1290` — the format check of `Analyze` / `Analyze metrics` (shape only).
- `.apm/agents/feat-tasker.agent.md:22-33, 98, 112-113` — the tasker's analyze step and report fields; it is never asked to save analyze's output.
- `.apm/skills/feat/SKILL.md:271-278` — the phase 5 gate prose (analyze not run / ran without metrics).
- `tests/step/run.sh:543-590`, `tests/step/fixtures/agents/tasker/` — phase 5 cases.

## Root Cause Hypothesis

The #97 fix made `ran` depend on a metrics line in the same self-written digest, so the evidence and the claim come from one source the agent controls; a tasker that skipped analyze (or was gated hard for it) can type numbers and clear the gate. Confidence: high.

## Proposed Remediation

**Preferred**: the tasker writes analyze's report, verbatim and whole (its `**Metrics:**` block included), to `reports/5-analyze.md` with Write, and lists it on `Wrote:`. In `dec_feat_5`, `Analyze: ran` becomes `analyze not run (no analyze report)` unless `<feature dir>/reports/5-analyze.md` exists, holds a `**Metrics:**` line, and the six numbers read from the lines under it (Total Requirements, Total Tasks, Coverage %, Ambiguity Count, Duplication Count, Critical Issues Count) equal the digest's `Analyze metrics:`; a mismatch gives `analyze metrics differ from 5-analyze.md`. On a rerun (accepted fixes), the tasker overwrites the file with the latest run. Bash 3.2, no jq, shellcheck clean.

**Alternatives**:
- Run analyze as its own fresh spawn after the tasker (the report's optional idea): stronger (not the last chore of a long run) but adds a row, sizes.json/agent/plugin changes and a new report format; a larger change, better as a follow-up issue.
- Have step.sh record the report's checksum when it gates hard and refuse a rewritten report: catches the rewrite but not a first-time fabrication.

**Files likely to change**:
- `.apm/skills/feat/scripts/step.sh`
- `.apm/agents/feat-tasker.agent.md`
- `.apm/skills/feat/SKILL.md`
- `docs/workflow.md`
- `tests/step/run.sh`
- `tests/step/fixtures/agents/tasker/` (match.md's `Wrote:`, a new analyze report fixture), `tests/step/expected/feat5-*`

**Tests to add or update**:
- feat 5 soft only with a matching `reports/5-analyze.md` (update every `put tasker/match 5-tasks` case to also put the analyze fixture).
- feat 5 hard: `ran` with metrics and no `5-analyze.md`.
- feat 5 hard: `5-analyze.md` without a `**Metrics:**` block.
- feat 5 hard: numbers in `5-analyze.md` differ from `Analyze metrics:`.

## Risks & Considerations

- Raises the bar, does not prove: a tasker can still write a fake analyze report; the file at least leaves an auditable trail and must agree with the digest.
- analyze's `**Metrics:**` block is free-form bullets (labels only in the template); the parser must tolerate `- Total Requirements: 8`, `8`, `100%` and similar, or the tasker must be told the exact line shape.
- Every phase 5 fixture and the full-run cases in `tests/step/run.sh` (e.g. around lines 1140, 2122, 2747) need the new file, or they go hard.
- Changes the tasker's contract (a new file in `reports/`); the agent, step.sh and tests change together, per the project rules. Make sure the shipper's commit of `reports/` keeps or drops `5-analyze.md` as intended.

## Open Questions

- [NEEDS CLARIFICATION: should the metrics line shape in `5-analyze.md` be fixed by the tasker prompt, or should step.sh parse analyze's template bullets loosely? Recommended: tell the tasker to save analyze's report verbatim and parse the six labelled bullets loosely (number after the label).]
- [NEEDS CLARIFICATION: include the separate analyze spawn here? Recommended: no, file it as a follow-up issue.]
