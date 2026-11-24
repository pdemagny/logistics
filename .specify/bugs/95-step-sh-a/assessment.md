# Bug Assessment: step.sh wedges on a boundary call made before its report exists

- **Slug**: 95-step-sh-a
- **Created**: 2026-11-24
- **Source**: pasted text (pdemagny/logistics#95, https://github.com/pdemagny/logistics/issues/95, host github.com, allowlisted; read with `gh issue view`, no further page fetched)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

Title: "step.sh: a boundary call made before the report is written records a hard gate that can neither be retried nor resumed".

In a `/feat` run, a phase 7 review-fixes implementer ran its own boundary call (`7-fixes <report>`) before writing its report. `step.sh` printed `hard:` / `- report missing: 7-fixes.md` and logged a hard gate. Once the report was written, the same call (by the agent, then by the orchestrator as the slip fallback) failed with `step: error: no boundary is open (hard:)`. `step.sh resume` then printed `soft`, `resume: 7 Code review` and fresh phase 7 reviewer spawns: the open hard gate was never shown, and nothing in the state file records dropping it.

Expected (from the report):
- a boundary call whose report does not exist yet is refused without writing state, so the agent can write it and call again;
- once the report exists, calling again decides normally (or at least re-prints the decision, as harness.md "Slip fallback" promises);
- `resume` shows an open hard gate, or logs that it dropped it.

The report names three causes (A: `check_report` fails a missing new report outside reviewer batches; B: `accept` re-prints only on matching sums and a hard decision has no open boundary; C: `do_resume`/`owed_fixes` never consider an unanswered hard gate) and suggests a fix for each, with a test each. Related: #92, #82.

## Symptom

A boundary call made before its report exists records a hard gate (`[!]` and `[x] … [hard] — report missing` Log lines); writing the report and calling again then dies with `step: error: no boundary is open (hard:)` (logging a `- [!] step:` line each time), and `resume` silently skips the open hard gate and restarts phase 7's review on a fresh snapshot. Expected: the early call is refused without state, the later call decides, and resume shows (or logs dropping) an unanswered hard gate.

## Reproduction

Reproduced in this worktree with a scratch script under the system temp dir that reuses `tests/step/run.sh`'s setup and helpers (throwaway repo, fixture state `feat`, Size small, `Current phase: 7 Code review`):

1. `step.sh resume <sf>`, then the phase 7 batch call with fixtures `code-reviewer/7a+7b-rule2` and `code-reviewer/7c+7d+7e-zero` → `soft`, auto-applied B1, B2, a `feat-implementer` spawn with `boundary: 7-fixes …/reports/7-fixes.md`.
2. `step.sh feat <sf> 7-fixes <reports>/7-fixes.md` with no report → `hard:` / `- report missing: 7-fixes.md` / `answer call: 7-fixes …`; Log gains `- [!] 7 review fixes — report missing: 7-fixes.md` and `- [x] 7 review fixes [hard] — report missing: 7-fixes.md`.
3. Same call, report still absent → the same decision re-printed (exit 0).
4. Write `7-fixes.md` (fixture `implementer/fix-pass`), same call → exit 1, `step: error: no boundary is open (hard:)`; Log gains `- [!] step: step: error: no boundary is open (hard:)`.
5. `step.sh resume <sf>` → `soft`, `resume: 7 Code review`, `spawn: feat-code-reviewer` (row 7a+7b, report `7-7a+7b-2.md`); no mention of the hard gate.

## Suspected Code Paths

- `.apm/skills/feat/scripts/step.sh:1268-1281` `check_report()` — a missing or empty new report calls `fail_check` (logs `[!]` and a hard reason) unless `DEFER_MISS` (reviewer batches only).
- `.apm/skills/feat/scripts/step.sh:1230-1234` `fail_check()` — `qlog` of the `[!]` line and `reason`.
- `.apm/skills/feat/scripts/step.sh:4248-4300` `do_boundary()` — `accept` then `check_report` for every single-report boundary; no check for an absent report before anything is logged.
- `.apm/skills/feat/scripts/step.sh:415-432` `record_sums()` — records a missing report with an empty hash, so once the file exists the sums no longer match.
- `.apm/skills/feat/scripts/step.sh:459-483` `accept()` — re-prints only on equal words and sums; a hard decision has no issued `boundary:`, so `RC_ISSUED` is empty and line 469 dies `no boundary is open (hard:)`.
- `.apm/skills/feat/scripts/step.sh:3059-3080` `owed_fixes()` — the `- [x] 7 review fixes [hard] — report missing: …` line matches `- [x] 7 review fixes — *`? No: it matches the loop's `"- [x] $2 — "*` pattern only when the `[hard]` tag is absent; the issue's bash -x trace shows `owed_fixes: return 1`, which leads `next_step` to `review_batch`. Exact branch to confirm in the fix (either the `[hard]` line is read as the last fixes line and is not a retry line, or the gate check above returns 1).
- `.apm/skills/feat/scripts/step.sh:4314-4330` `do_resume()` / `resume_next()` (1731) — never call `open_gate`, so an unanswered hard gate is not shown on resume.
- `.apm/skills/feat/scripts/step.sh:717-760` `open_gate()` — already finds the latest unanswered gate (would report this one); the resume path just does not use it.
- `.apm/skills/feat/references/harness.md:90-98` "Slip fallback" — promises a decided call re-prints its decision; does not list `refused:` among the first lines a block may start with.
- `.apm/agents/feat-implementer.agent.md` (and every agent that makes its own boundary call since 7e63f63) — says to call once the report is written; the script does not enforce it.

## Root Cause Hypothesis

Three compounding defects, all confirmed by the reproduction (confidence: high). (A) `check_report` treats an absent new report on a non-batch boundary as a failed report check, logging a hard gate, instead of refusing the premature call. (B) `accept`'s re-print rule keys on report sums, and a missing report is recorded with an empty hash, so the call made after the report is written matches no record; with the hard decision having no issued boundary it dies, and each failure adds a `- [!] step:` line. (C) the resume path (`do_resume` → `resume_next` → `next_step`) never consults `open_gate`, and `owed_fixes` returns 1 for the hard `report missing` entry, so `next_step` runs a fresh `review_batch`, dropping the unanswered hard gate without a trace. The trigger became common with 7e63f63 (agents run their own boundary call); the same `check_report` path serves every single-report boundary of both `/feat` and `/fix` (e.g. `fix:1`, `fix:2`, `fix:3`, `fix:4-fixes`).

## Proposed Remediation

**Preferred**: fix all three parts in `step.sh`, with tests.

- A: in `do_boundary`, after `accept` and before any `qlog` or `check_report`, when the boundary is not a reviewer batch and a new report path is absent or empty (honouring the `RENUM` lookup `check_report` does), set `refuse "report missing: <name>: write it, then call again"` and return, so nothing is logged or recorded and the same call can be made again. Keep `fail_check` for a report that exists but fails its checks (changed since checked, unparsable, …). Add `refused:` to harness.md's slip-fallback list of parseable first lines (and the agents' last-step wording, if they need to act on it), so a refused block is not read as a slip.
- B: in `accept`, when the recorded decision is a hard `report missing` one and the report now exists, do not die: drop the stale record match and decide again (or, minimally, re-print on matching words alone). With A in place this only covers state files written before the fix.
- C: in `do_resume` (both skills), call `open_gate` before `resume_next`; when a hard gate is open, print it (the verdict, its reasons and `answer call:`) instead of the next step, matching harness.md "Resume" ("show the gate it printed"). Make `owed_fixes` not read a `[hard] — report missing` fixes line as fixes done.

**Alternatives**:
- A via `DEFER_MISS`-like handling for every boundary (a missing report is a reason only, re-spawn the agent): heavier, and it still logs.
- C minimal: keep restarting the phase but log `- [!] <phase> — open hard gate dropped by resume`: preserves the trail but still bypasses the gate the user never answered.

**Files likely to change**:
- `.apm/skills/feat/scripts/step.sh`
- `tests/step/run.sh`
- `tests/step/expected/` (new goldens for the three cases)
- `.apm/skills/feat/references/harness.md` (slip fallback: `refused:` as a parseable first line; resume showing an open gate)

**Tests to add or update**:
- A: a `7-fixes` (and a `/fix` single-report boundary, e.g. `fix:2`) call with no report → `refused: report missing: …`, state file unchanged; then the report written and the same call → normal decision.
- B: a state file whose record holds a hard `report missing` decision, the report now present, same call → decided (not `no boundary is open`).
- C: `resume` on a state file whose Log ends with an unanswered `[hard]` gate → the gate shown, no reviewer spawn; existing resume goldens unchanged.

## Risks & Considerations

- `refused:` on a boundary call is a new output for agents and the coordinator: the harness slip fallback and agent last-step text must accept it, or the coordinator will treat it as a slip (which, by remaking the call once the report exists, happens to work).
- Changing resume to show open hard gates affects every resume; other existing goldens (`tests/step/expected/`) may change where a fixture ends on an unanswered hard gate.
- A report that is present but empty: decide whether it is "missing" (refused) or a failed check (hard); the current `-s` test treats both as missing.
- Shared rules: keep `/feat`-only words out of harness.md (`mise run lint` greps them); Bash 3.2 and shellcheck constraints apply.

## Open Questions

- [NEEDS CLARIFICATION: should an empty (zero-byte) report be refused like an absent one, or stay a hard failed check?] — recommended: refuse both, as `check_report` already treats them alike.
- [NEEDS CLARIFICATION: on resume with an unanswered hard gate, show it (preferred) or restart the phase and log the drop?] — recommended: show it, as harness.md "Resume" already says.
