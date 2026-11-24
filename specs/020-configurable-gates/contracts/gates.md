# Contract: configurable gates (amends 013-step-command's gates.md)

This amends [`specs/013-step-command/contracts/gates.md`](../../013-step-command/contracts/gates.md)
section by section, and two lines of
[`specs/013-step-command/contracts/step-cli.md`](../../013-step-command/contracts/step-cli.md)
(read them with this file; 013's files are not edited):

- Answers table, `changed`: "`/feat` 2, 3 (large), …" reads "`/feat` 2, 3
  (when gate 3 stopped), …".
- Output, `note: plan amended after gate 3     /feat 4, large` reads
  "`/feat` 4, after a gate 3 that stopped for `large` or `gates: hard`".

Every row not named here is unchanged. It is the source of the gate rules
the `docs/workflow.md` matrix ("Configuring the gates") cites: a change to
a gate row updates both, with a `tests/step` case for each row that
changes behaviour.

## The value of a gate

`step.sh` reads the state file's `Gates:` field on every call
([data-model.md](../data-model.md#gates-field)). The value of gate `<n>` is
its cell for the size that applies: the token `<skill>.<n>.<size>=<v>`,
else `<skill>.<n>=<v>`, else `auto`. The size that applies is the run's
`Size` at the time of the decision (after a decrease the same call
applies, as at `/feat` 5); at `/fix` 1, the assessment's `Proposed size`.
A cell for another size never applies.

| Value | Effect |
| ----- | ------ |
| `auto` | 013's tables, unchanged |
| `soft` | the size reason (`large`; `proposed size <s>` at `/fix` 1) is not added; the rows small and medium evaluate are evaluated, none added or dropped, except that gate 4 skips `plan3_rows` when gate 3 stopped (FR-004, FR-007); when that removed a size reason and the gate passes soft, its Log line ends `; gates: soft` |
| `hard` | the size reason as `auto` gives it, then the reason `gates: hard` (at `/feat` 6: `US<n>: gates: hard`; at `/fix` 3: R10 of research.md) |

"The size reason is in force" means: the size gives it (`Size` large; at
`/fix` 1, `Proposed size` not small) and the value is not `soft`. Every
"Size large" branch of 013's tables that skips the other rows reads "the
size reason is in force". Every other reason, and every reason of steps
3–5 (report check, snapshot, unparsable report), still makes the gate hard
whatever the value. Settable: `/feat` 2–7, `/fix` 1–4; ship never.

Trust: the `Gates:` field, like `Size:`, is written only through
`state.sh` and read as is; `step.sh` refuses a value that is not
canonical, and nothing else guards it against an edit of the state file.

## `/feat`

### 2 Specify

`hard`: `gates: hard` after the table's reasons. `soft`: as `auto`.
Answers unchanged (`approved` with no marker and no blocker → phase 3).

### 3 Plan

| Condition | Gate |
| --------- | ---- |
| the size reason is in force, or the value is `hard` | hard: `- [x] 3 Plan [hard] — <reasons>; <facts>`, reasons in order: report-check reasons, `large` (in force), `gates: hard` (value `hard`), then 013's large reasons (`assumption <k> needs you`, `constitution: <principle>`, `blocker`, `checklist item`, `fact missing: unchecked checklist items`) |
| otherwise | no gate: `- [x] 3 Plan — merged with 4; <facts>`, plus `; gates: soft` when the value `soft` removed `large` → phase 4 |

So on small and medium with `hard`: `- [x] 3 Plan [hard] — gates: hard[;
<other reasons>]; <facts>`; on large with `hard`: `large; gates: hard[;
…]`; on large with `soft`: the merged record. The answers (`approved` →
phase 4, `changed` → planner `amend`, then `- [x] 3 Plan — amended;
<facts>`), resume and `phase2-mode` treat every gate 3 alike, whatever made
it stop. The amended record's rules (013) are unchanged.

### 4 Design review

"Gate 3 stopped" means: the latest tagged `3 Plan` line holds the reason
`large` or `gates: hard`. The plan rows that gate 3 evaluates
(`plan3_rows`): `assumption <k> needs you`, `constitution: …`, `blocker`,
`checklist item`, `fact missing: unchecked checklist items`. The other
small/medium rows: `<ids> need you`, size increase, `fact missing: <plan
fact>`, `paraphrase contradicts the brief`.

| Size reason | Gate 3 stopped | Rows evaluated after the report checks |
| ----------- | -------------- | -------------------------------------- |
| in force | yes | `large` (013's large) |
| in force | no | `large`, then `plan3_rows` (a gate 3 softened on large: its reasons are checked here) |
| not in force | no | every small/medium row (013's small/medium) |
| not in force | yes | the small/medium rows without `plan3_rows` |

`gates: hard` (value `hard`) comes right after `large`'s place (first when
`large` is not in force). `note: plan amended after gate 3`: printed when
gate 3 stopped and a `3 Plan — amended` line follows that gate line (was:
Size large). Soft Log line: `- [x] 4 Design review [soft] — auto-applied
…[; skipped …][; gates: soft]`.

### 5 Tasks

`Size large` row: `large` when in force, then `gates: hard` for `hard`.
Soft line: `- [x] 5 Tasks [soft] — <t> tasks; story.sh: match; analyze
ran[; gates: soft]`. The size from the task count is set first, as today:
a decrease to medium leaves no size reason, and the medium cell applies.

### 6 Implement

| Condition | Result |
| --------- | ------ |
| Size large row | `US<n>: large` when in force |
| value `hard`, on that same branch (checks pass, no design problem) | `US<n>: gates: hard`, after `US<n>: large` when both |
| last story, soft, Size large and value `soft` | `- [x] 6 Implement [soft] — tasks done: <n> (<k> not verified); checks pass; gates: soft` |

The retry row (a failing check, retry unused) stays soft with any value.
Stories before the last log no gate line when they pass soft.

### 7 Code review

As gate 4's size handling: `large` → in force; `gates: hard` right after
its place; the small/medium rows (`<ids> need you`, `S<n> security`,
`criterion not met: <c>`) evaluated when `large` is not in force; soft
line `…[; untested: …][; gates: soft]`. On medium and large the 7a–7d call
(token `7`) adds no `gates: hard`: the gate, and its value, come after 7e.

## `/fix`

### 1 Assess

The cell is the one for the assessment's `Proposed size`. The `Proposed
size` row: `proposed size <s>` when in force; `gates: hard` right after
its place for `hard`. When the assessment did not parse there is no
proposed size, and no cell applies (the gate is hard already). Every other
row is unchanged. Soft pass line: `- [x] 1 Assess [soft] — gate: …;
performance bug <v>[; gates: soft]` (`; gates: soft` when `Proposed size`
was not small and the cell is `soft`). `issue to create`: "board tracking"
is now "the top level's `.logistics.yml` has a `tracker:` key" (a line
`^tracker:( |#|$)`).

### 2 Fix

`hard`: `gates: hard` after the table's reasons. `approved` → phase 3, as
at any `2 Fix` gate. `soft`: as `auto`.

### 3 Test

With `hard` for the run's size, the boundary call (`dec_fix_3`, flag
`TR_GATES` 1) decides:

| Condition | Result |
| --------- | ------ |
| `Verdict: verified`, or `failed` with `cycle` `first` and `retry-used` `no` | `- [x] 3 Test [hard] — gates: hard; verdict: <verified or failed>` |
| any other hard `3 Test` gate of the call (sections, slug, report check, review fixes report without its Not verified line, unaccounted items, `partial`, `failed` after the retry) | its reasons, then `gates: hard` |

`approved` at any of them re-runs the verdict's row (013, 3 Test) with
`TR_GATES` 0, once: `verified` → `- [x] 3 Test [soft] — verified` → phase
4 or 5; `failed` (retry unused) → the retry line → phase 2; `partial` or
`failed` after the retry → its own hard gate, as today. No answer stops a
second time for `gates: hard`. `changed` keeps its rule (valid only on a
`partial: ` or `unaccounted items: ` gate). `soft`: as `auto`.

### 4 Code review

`Size large` row: `large` when in force; `gates: hard` right after its
place; the other rows already run on every size. Soft line `…[; gates:
soft]`.

## Unchanged

`/feat` 8, `/fix` 5, moves, answers' validation (except as above), the
missing-fact rule, size increase and decrease, every verdict when the
field is missing, `none`, or holds only cells of other gates or other
sizes.

## The matrix (docs/workflow.md)

Each settable gate takes one value for every size or a value per size;
each cell below applies only to runs of that size.

| Gate | Default small · medium · large | `soft` changes | `hard` changes | Always hard |
|---|---|---|---|---|
| `feat.2` Specify | soft · soft · soft | nothing (no size reason) | stops after the spec | open markers, blocker, size remark, no spec |
| `feat.3` Plan | none (merged with 4) · none · **hard** `large` | large: no gate 3, merged with 4 like small; its reasons are checked at gate 4. Small, medium: nothing | small, medium: the large gate 3, reason `gates: hard`; large: reasons `large; gates: hard`. Gate 4 then skips what gate 3 approved | when gate 3 stops: assumption needs you, constitution, blocker, checklist item (with no gate 3, these are checked at gate 4) |
| `feat.4` Design review | soft* · soft* · **hard** `large` | large: soft*. Small, medium: nothing | stops | `rec: user`, assumption needs you, constitution, blocker, size increase, paraphrase contradicts, checklist item, fact missing |
| `feat.5` Tasks | soft* · soft* · **hard** `large` | large: soft*. Small, medium: nothing | stops | CRITICAL/HIGH, analyze not run, `story.sh` mismatch, unanswered checklist, size increase, fact missing |
| `feat.6` Implement (per story) | soft* · soft* · **hard** `large` after each story | large: no stop between stories. Small, medium: nothing | stops after each story | Not verified line missing, checks fail after retry, design problem |
| `feat.7` Code review | soft* · soft* · **hard** `large` | large: soft* (applies `apply` recommendations). Small, medium: nothing | stops (after 7e on medium and large) | `rec: user`, `S` finding, criterion not met, empty diff |
| `feat.8` Ship | not settable | — | — | ship blocked |
| `fix.1` Assess (by proposed size) | soft* · **hard** `proposed size` · **hard** `proposed size` | medium, large: soft*. Small: nothing | stops | every other row: untrusted author, needs approval, security risk area, issue to create, needs reproduction, open questions, several bugs, confidence, reproduction, remediations, public behaviour change, sections, slug |
| `fix.2` Fix | soft* · soft* · soft* | nothing | stops after the fix | deviations (size increase), check fails, status, Not verified line missing |
| `fix.3` Test | soft* · soft* · soft* | nothing | stops once per test report (verified, or before the one retry) | partial, failed after retry, unaccounted items |
| `fix.4` Code review | soft* · soft* · **hard** `large` | large: soft*. Small, medium: nothing | stops | security risk area, `rec: user`, `S` finding |
| `fix.5` Ship | not settable | — | — | ship blocked |

\* soft only when nothing in the last column applies. On every gate, a
failed report check, an unparsable report or files changed outside the
reports also make it hard.

## Tests (`tests/step`)

Fixtures as today; a case writes the `- Gates:` header line after `-
Issue:` (`state.sh set` refuses the field). Three helpers keep the
goldens few:

- `same_run <a> <b>`: two cases on one fixture, differing only in the
  `Gates:` line (and, for `same_verdict`, the `Size:` line); `same_run`
  asserts identical stdout and Log lines.
- `same_verdict <a> <b>`: identical verdict line, `- <reason>` lines and
  gate Log line once `; gates: soft` is cut from it and `large` from the
  reasons (the size column and the mark are the only allowed differences;
  spawn lines may differ by size). `same_verdict <a> <b> plan3` also cuts
  the `plan3_rows` reasons from `<b>`'s reasons (case 3, gate 3 stopped,
  where both sides are hard for another reason).
- Goldens (`check`) only for a form that is new: a `gates: hard` gate, the
  soft mark, the small gate 3, the `fix.3` hard row and its answer.

Cases:

1. SC-001: no field (the existing suite, unchanged goldens); `same_run`
   of a sample of existing cases (one per gate `feat` 2–7, `fix` 1–4) with
   `Gates: none` vs no field.
2. FR-009: `same_run` `feat.2=soft`, `fix.2=soft`, `fix.3=soft` vs no
   field. FR-023, SC-009: `same_run` of `feat.4.large=soft` and
   `feat.4.small=hard` on a medium fixture vs no field; `fix.1.small=hard`
   on a medium bug vs no field; `feat.6.small=soft` on large vs no field.
3. SC-003: `same_verdict` of `<n>.large=soft` on a large fixture vs no
   field on medium for `feat` 3 (merged), 4, 5, 7 (7e) and `fix` 4, each
   clean and with one always-hard reason (`rec: user`, HIGH, `S` finding,
   security risk area). Gate 4 takes two fixtures, each with a plan fact
   that is a `plan3_rows` reason (an assumption that needs you): gate 3
   merged (`feat.3.large=soft feat.4.large=soft`, no tagged `3 Plan`
   line): identical to medium, the assumption a reason on both; gate 3
   stopped (`feat.4.large=soft` alone, the large gate 3 answered
   `approved`), with a `rec: user` finding too so both sides stop:
   `same_verdict … plan3`, the assumption a reason on medium only.
4. `feat.2=hard` small: golden (`gates: hard`, `approved` → phase 3).
5. `feat.3=hard` small: golden of the gate 3 line; `approved` → phase 4
   with `spec assumptions: kept as recommended` after a soft phase 2;
   `changed` → planner `amend`, then `3 Plan — amended; <facts>` → phase
   4; `resume` at the open gate (`phase2-mode: soft 3 open`); gate 4 then
   skips `plan3_rows` (a fixture whose 3 Plan facts hold an assumption
   that needs you: no reason at gate 4) and prints the note after an
   amend.
6. `feat.3.large=hard` large: golden `large; gates: hard`.
7. `feat.3.large=soft` large: golden of the merged record with `; gates:
   soft` and phase 4's spawn; then gate 4 (`auto`) holds `large` and the
   `plan3_rows` reasons.
8. `feat.4=hard`, `feat.5=hard` small: golden `gates: hard` with the rows.
9. `feat.6.large=soft` large: next story with no gate line; last story's
   line with the mark (golden); a design problem and checks failing after
   the retry still stop (`same_verdict` vs medium). `feat.6=hard` small:
   `US1: gates: hard` after each story; the retry stays soft.
10. `feat.7=hard` medium: no stop at token 7, `gates: hard` after 7e.
11. `fix.1.medium=soft` medium bug, every soft condition: golden of the
    soft line with the mark; `Confidence: medium`: hard, no `proposed
    size`. `fix.1=hard` small: `gates: hard`.
12. `fix.2=hard`: golden, `approved` → phase 3.
13. `fix.3=hard`: verified → golden `gates: hard; verdict: verified`,
    `approved` → `3 Test [soft] — verified`, phase 4, no second stop;
    first failed → hard, `approved` → the retry line, phase 2; unaccounted
    items → one gate ending `gates: hard`, `approved` → the verdict's row
    once; partial → `partial: …; gates: hard`.
14. `fix.4=hard` small: `gates: hard`.
15. A non-canonical `Gates:` (bad token, the other skill's, out of order,
    plain and sized for one phase) → `step: error`.
16. A `.logistics.yml` holding a `gates:` section that says otherwise than
    the field: the field wins (the file is not read for gates).
17. `/fix` 1 `issue to create`: a `.logistics.yml` with only `gates:` → no
    reason; with `tracker:` → the reason (the existing case's fixture now
    writes a `tracker:` line instead of `board: x`).
