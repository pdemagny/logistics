# Tasks: Configurable gates

**Input**: `specs/020-configurable-gates/` (spec.md, plan.md, research.md, data-model.md, contracts/gates.md, contracts/config.md, contracts/prompts.md, quickstart.md)

**Prerequisites**: plan.md, spec.md

**Tests**: Requested by the spec (FR-020, SC-001, SC-003, SC-005, SC-009): each behaviour task is paired with its `tests/<suite>` case. Shipped scripts stay Bash 3.2, no jq, no Python, shellcheck clean. No task branches or commits (the workflow owns git). Never edit `CHANGELOG.md`, `sizes.tsv` or a `sizes-start`/`sizes-end` block; diagrams are unchanged (research R14).

**Organization**: Grouped by user story. The parser, the `Gates:` field and the `step.sh` plumbing are foundational because every story needs them. Paths are relative to the repo root; `SCRIPTS` = `.apm/skills/feat/scripts`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- Rule for existing goldens: no existing `tests/step/expected` golden changes (SC-001); only new goldens for new forms.

---

## Phase 1: Setup

**Purpose**: Check the baseline before touching scripts.

- [X] T001 Run `mise run lint`, `mise run test:tracker`, `mise run test:preflight`, `mise run test:state` and `mise run test:step` on the unchanged tree and note that all pass (baseline for SC-001); no file changes.
- [X] T002 [P] Read `specs/013-step-command/contracts/gates.md` and `step-cli.md` next to `specs/020-configurable-gates/contracts/gates.md` so the amended rows (answers table `changed`, `note: plan amended after gate 3`) are known before editing `SCRIPTS/step.sh`; no file changes.

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: The one parser, the recorded field, and the `step.sh` helpers every story applies.

**CRITICAL**: No user story starts before this phase is done.

- [X] T003 Port `SCRIPTS/tracker.sh` to Bash 3.2 (research R3): remove `declare -A` and `${name,,}`, guard every possibly empty array expansion; keep today's `tracker:` behaviour.
- [X] T004 Extend `parse_config` in `SCRIPTS/tracker.sh` (research R2–R4, contracts/config.md): track the current top-level section and skill; accept `tracker` and `gates` in any order, each at most once; run the tracker completeness checks (`missing tracker.<key>`, `bad project number`) only when `tracker` was seen; `RE_KEY` takes letter or digit keys; accept a phase value that is a plain `soft|hard|auto` (bare or quoted) or a one-line `{ <size>: <value>, … }` mapping with sizes `small|medium|large`, optional ` # comment`; settable phases `feat` 2–7 and `fix` 1–4.
- [X] T005 Add the `gates <feat|fix>` subcommand to `SCRIPTS/tracker.sh` (`cmd_gates`, config on stdin, no `gh`, no repo read): print `tracker: gates <tokens>` with canonical tokens (phases ascending, plain `<skill>.<n>=<v>` or size tokens `<skill>.<n>.<size>=<v>` in small, medium, large order, `auto` cells left out) or `tracker: gates none`; wrong arguments give usage and exit 2; update the usage text.
- [X] T006 [P] Add valid-section cases to `tests/tracker/run.sh` (and fixtures under `tests/tracker/fixtures/`): both forms, both skills, comments and quoted values, `gates` before and after `tracker`, a mapping naming all three sizes giving three tokens, an `auto`-only section giving `none`, an empty `gates:`, `gates` on a `tracker`-only text giving `none`, `gates` with no or a bad skill argument giving usage; plus the Bash 3.2 construct grep that `tests/step/run.sh` already uses.
- [X] T007 Add the `Gates=` field to `SCRIPTS/state.sh` (`init feat` and `init fix`): default `none`; accept only `none` or canonical tokens of the init's skill (phases ascending, one plain token or size tokens in small, medium, large order, each once, one space between); else `state: error: Gates must be none or canonical <skill> gate tokens, not: <value>`; write `- Gates: <value>` after `- Issue:`; make `set` refuse `Gates` (usage lists the fields it takes, as today).
- [X] T008 Add the optional gate argument to `phase2-mode <state file> [<3|4>]` in `SCRIPTS/state.sh` (research R12, data-model table): with `3` or `4` it names the gate carrying a soft phase 2's summary; anything else is usage; without it keep today's Size rule.
- [X] T009 [P] Add cases to `tests/state/run.sh` (with `tests/state/expected/`): init with and without `Gates=` (plain and size tokens), a bad token, the other skill's token, a duplicate, an out-of-order value, plain and sized for one phase; `set … Gates …` refused; `phase2-mode` with `3` on a small state (`soft 3 open`, then `closed` after an answered gate 3), with `4` on a large state (`soft 4 open`), with a bad gate (usage), and without it (existing cases unchanged).
- [X] T010 Read the `- Gates:` header in `read_state` of `SCRIPTS/step.sh` into `F_GATES`; after `load_state`, die with `step: error: Gates: <value> is not a canonical <skill> gates value` on a non-canonical value; a missing field or `none` means every gate `auto` (FR-011); the canonical check is a small copy of the one in `state.sh` (plan, Constitution III).
- [X] T011 Add the cell helpers to `SCRIPTS/step.sh` (data-model "Applying a cell"): `gate_cfg <n> <size>` (token `<skill>.<n>.<size>`, else `<skill>.<n>`, else `auto`, into `GC`), `in_force <n> <holds>`, `size_gate <n> <holds> <reason>` (soft sets `SOFTENED=1`, hard adds `gates: hard`, `US<n>: gates: hard` at `/feat` 6), the `SOFTENED` and `TR_GATES` state variables, and the `; gates: soft` suffix applied to a soft Log line when `SOFTENED`.
- [X] T012 Add the gate-3 helpers to `SCRIPTS/step.sh` (research R8): `gate3_stops` (`in_force 3 (Size large)` or the cell is `hard`), `G3STOP` (the latest tagged `3 Plan` Log line holds the reason `large` or `gates: hard`), and split `plan_rows` into `plan3_rows` (`assumption <k> needs you`, `constitution: …`, `blocker`, `checklist item`, `fact missing: unchecked checklist items`) and the other small/medium rows.
- [X] T013 Pass `gate3_stops`' gate (3 or 4) at the four `st phase2-mode` calls of `SCRIPTS/step.sh`, and make the Log readers (`plan_facts`, `assess_facts`, `log_apply`, `design_ids`, `review-summary`) skip a `gates: soft` segment, `shipped-verdict` read only a `3 Test` line's first word, and `apply_answer feat:6` keep testing the `tasks done: ` prefix (data-model "Log lines", Readers).
- [X] T014 Add the comparison helpers `same_run <a> <b>` and `same_verdict <a> <b> [plan3]` to `tests/step/run.sh` (contracts/gates.md, Tests): `same_run` asserts identical stdout and Log lines; `same_verdict` asserts identical verdict, reasons and gate Log line once `; gates: soft` and `large` are cut (with `plan3`, also the `plan3_rows` reasons of the medium side); add a way for a case to write a `- Gates:` line after `- Issue:` in its fixture state file.
- [X] T015 Add `tests/step` case 1 (SC-001): confirm every existing golden is unchanged, and `same_run` of one existing case per gate (`feat` 2–7, `fix` 1–4) with `Gates: none` against no field, in `tests/step/run.sh`.
- [X] T016 Add `tests/step` case 15 (FR-011) in `tests/step/run.sh`: a non-canonical `Gates:` (bad token, the other skill's, out of order, plain and sized for one phase) gives `step: error`; and case 16: a `.logistics.yml` whose `gates:` says otherwise than the field leaves the decision unchanged (the field wins, the file is not read for gates).

**Checkpoint**: parser, field and helpers exist; no gate decision changed yet; `mise run test:tracker`, `test:state` and `test:step` pass.

---

## Phase 3: User Story 1 - Soften a gate that size makes hard (Priority: P1) MVP

**Goal**: `soft` removes only the size reasons; every other reason still stops the gate; `soft` at a gate with no size reason is `auto`.

**Independent Test**: `feat.6.large=soft` on a large fixture with passing checks goes on; with a design problem or a check failing after the retry it stops without `large`; a medium fixture gives today's output.

- [X] T017 [US1] In `SCRIPTS/step.sh` `dec_feat_3` and `review_gate` (gates 3, 4, 5, 7), replace each `reason large` / `$SC == large` / `$SC != large` row-skipping test with `size_gate` / `in_force` so a `soft` cell evaluates exactly the small/medium rows; gate 3 stops only on `gate3_stops` and, when it does not, prints `- [x] 3 Plan — merged with 4; <facts>` (plus `; gates: soft` when `soft` removed `large`) and goes to phase 4 (FR-004, FR-005).
- [X] T018 [US1] In `SCRIPTS/step.sh` gate 4, choose the rows from the size reason and `G3STOP` per research R8's table (size reason in force or not, gate 3 stopped or not), skipping `plan3_rows` when gate 3 stopped, and print `note: plan amended after gate 3` when `G3STOP` and a `3 Plan — amended` line follows (contracts/gates.md, 4 Design review).
- [X] T019 [US1] In `SCRIPTS/step.sh` gate 5, gate 7 and `/fix` 4, apply `size_gate` to the `large` row and add the `; gates: soft` suffix to their soft Log lines (`…[; gates: soft]`, `…[; untested: …][; gates: soft]`); at gate 5, set the size from the task count first, as today.
- [X] T020 [US1] In `SCRIPTS/step.sh` gate 6, apply `size_gate` to `US<n>: large` and put `; gates: soft` on the last story's line only (`- [x] 6 Implement [soft] — tasks done: <n> (<k> not verified); checks pass; gates: soft`); earlier stories log no gate line; the retry row stays soft.
- [X] T021 [US1] In `SCRIPTS/step.sh` `/fix` 1, apply the cell for the assessment's `Proposed size` to the `proposed size <s>` row (soft drops it on every size; no cell applies when the assessment did not parse), add `; gates: soft` to the soft pass line when `Proposed size` was not small and the cell is `soft`, and keep every other row.
- [X] T022 [US1] Make `soft` at `/feat` 2, `/fix` 2 and `/fix` 3 produce the `auto` output in `SCRIPTS/step.sh` (FR-009), with no code path that reads the cell there except by `hard` (T028).
- [X] T023 [P] [US1] Add `tests/step` case 2 (FR-009, FR-023, SC-009) in `tests/step/run.sh`: `same_run` of `feat.2=soft`, `fix.2=soft`, `fix.3=soft` against no field; `feat.4.large=soft` and `feat.4.small=hard` on a medium fixture against no field; `fix.1.small=hard` on a medium bug against no field; `feat.6.small=soft` on large against no field.
- [X] T024 [P] [US1] Add `tests/step` case 3 (SC-003, SC-004) in `tests/step/run.sh`: `same_verdict` of `<n>.large=soft` on a large fixture against no field on medium for `feat` 3 (merged), 4, 5, 7 (after 7e) and `fix` 4, each clean and with one always-hard reason (`rec: user`, HIGH, `S` finding, security risk area); gate 4 takes two fixtures with an assumption that needs you, one with gate 3 merged (`feat.3.large=soft feat.4.large=soft`, identical) and one with gate 3 stopped (`feat.4.large=soft` alone, gate 3 answered `approved`, plus a `rec: user` finding; `same_verdict … plan3`).
- [X] T025 [P] [US1] Add `tests/step` case 7 and case 9 (soft part) in `tests/step/run.sh` with goldens in `tests/step/expected/`: `feat.3.large=soft` large gives the merged record with `; gates: soft`, phase 4's spawn, then gate 4 (`auto`) holds `large` and the `plan3_rows` reasons; `feat.6.large=soft` large gives no gate line for earlier stories, the last story's line with the mark (golden), and a design problem or checks failing after the retry still stop (`same_verdict` against medium).
- [X] T026 [P] [US1] Add `tests/step` case 11 (soft part) in `tests/step/run.sh` with a golden: `fix.1.medium=soft` on a medium bug meeting every soft condition gives the soft line with `; gates: soft`; the same bug with `Confidence: medium` is hard with no `proposed size` reason.

**Checkpoint**: US1 works; `mise run test:step` passes. This is the MVP.

---

## Phase 4: User Story 2 - Force a gate to stop (Priority: P1)

**Goal**: `hard` adds the reason `gates: hard` at any settable gate for the run's size; `feat.3: hard` gives the large gate 3 form on small and medium.

**Independent Test**: `feat.3: hard` on a small fixture ends the plan phase in a hard gate with reason `gates: hard`, then the design review runs as today.

- [X] T027 [US2] In `SCRIPTS/step.sh` `dec_feat_3`, add the reason `gates: hard` (after `large` when in force, then 013's large reasons) so `feat.3` hard on small or medium gives `- [x] 3 Plan [hard] — gates: hard[; <other reasons>]; <facts>` and on large `large; gates: hard`; keep the answers (`approved` → phase 4, `changed` → planner `amend` then `- [x] 3 Plan — amended; <facts>`), resume and done-phase handling the same for every gate 3, and change the `changed` answer's validity to "when gate 3 stopped".
- [X] T028 [US2] In `SCRIPTS/step.sh` add `gates: hard` after the table's reasons at `/feat` 2 and `/fix` 2, and `gates: hard` at gates 4, 5, 7 and `/fix` 1, 4 right after the size reason's place (first when the size reason is not in force); at gate 7 the 7a–7d call (token `7`) adds none, the gate comes after 7e.
- [X] T029 [US2] In `SCRIPTS/step.sh` gate 6, add `US<n>: gates: hard` on the branch where checks pass and there is no design problem (after `US<n>: large` when both), so each story stops; the retry row stays soft with any value.
- [X] T030 [US2] In `SCRIPTS/step.sh` `dec_fix_3`, add the `TR_GATES` flag (research R10): with `hard` for the run's size, a verified verdict, or a first `failed` with retry unused, gives `- [x] 3 Test [hard] — gates: hard; verdict: <verified or failed>`; any other hard `3 Test` gate ends with `gates: hard` after its reasons; `approved` re-runs the verdict's row once with `TR_GATES` 0 so no second stop occurs; `changed` keeps its rule.
- [X] T031 [P] [US2] Add `tests/step` cases 4, 8 and 14 in `tests/step/run.sh` with goldens: `feat.2=hard` small (`approved` → phase 3); `feat.4=hard` and `feat.5=hard` small with their rows; `fix.4=hard` small.
- [X] T032 [P] [US2] Add `tests/step` cases 5 and 6 in `tests/step/run.sh` with goldens: `feat.3=hard` small gate 3 line; `approved` → phase 4 with `spec assumptions: kept as recommended` after a soft phase 2; `changed` → planner `amend` then `3 Plan — amended; <facts>` → phase 4; `resume` at the open gate (`phase2-mode: soft 3 open`); gate 4 skips `plan3_rows` and prints the note after an amend; `feat.3.large=hard` large gives `large; gates: hard`.
- [X] T033 [P] [US2] Add `tests/step` cases 9 (hard part), 10, 11 (hard part), 12 and 13 in `tests/step/run.sh` with goldens: `feat.6=hard` small gives `US1: gates: hard` after each story and the retry stays soft; `feat.7=hard` medium has no stop at token 7 and `gates: hard` after 7e; `fix.1=hard` small; `fix.2=hard` with `approved` → phase 3; `fix.3=hard` verified, first failed, unaccounted items and partial paths as listed in contracts/gates.md.
- [X] T034 [US2] Add the `tests/step` check for US2 scenario 8 and FR-023 in `tests/step/run.sh`: a cell `hard` for small only on a medium or large run gives `same_run` with no field.

**Checkpoint**: US1 and US2 both work; `mise run test:step` passes.

---

## Phase 5: User Story 3 - Gates fixed for the run, safe to resume (Priority: P1)

**Goal**: The gates are read once at setup from `origin/<default>`, shown, recorded in state as `Gates:`, and used by every later boundary and resume.

**Independent Test**: Start a run with gates set, change `.logistics.yml`, resume: the logged gates apply; a state file with no `Gates:` resumes as all `auto`.

- [X] T035 [US3] Add `step_gates` to `SCRIPTS/preflight.sh` (mode 1, kinds brief, issue, symptom, after `step_base`): `git cat-file -e refs/remotes/origin/<default>:.logistics.yml` failing gives `gates: none`; else pipe `git show` of that blob into `bash <tracker.sh> gates <skill>`; a non-zero exit gives `stop: origin/<default>:<its line without "tracker: error: ">` (exit 1), otherwise `gates: <tokens>`; add the `gates` key slot right after `board`; resume and rebase print no `gates:` line (FR-010, FR-014).
- [X] T036 [P] [US3] Update `tests/preflight/run.sh`, its stub tracker (answers `gates` from a case file and records stdin and arguments) and `tests/preflight/expected/`: origin with a gates section gives `gates:` with the stub's tokens, stdin is origin's blob (not the checkout's file) and the argument is the skill; no file on origin gives `gates: none`; the stub's error gives the stop line; resume and rebase print no `gates:`; goldens of brief, issue and symptom runs gain the `gates: none` line after `board:` and nothing else changes.
- [X] T037 [US3] Edit `.apm/skills/feat/references/harness.md`: add the "Gates in force" paragraph under `## Gates` (show `Gates in force (from origin/<default>:.logistics.yml): <value>` when not `none`; pass `'Gates=<value>'` to `S init`; fixed for the run; `gates: hard` and `gates: soft` meanings; "`large` or `gates: hard`" wherever a skill renders a gate differently for `large`), and add `- Gates: <setup's gates: value>` to the state template (`S set` unchanged); keep `/feat`-only words out (`specifier|planner|tasker|spec.md|brief|phase [0-9]|/feat`).
- [X] T038 [P] [US3] Edit `.apm/skills/feat/SKILL.md` per contracts/prompts.md: Setup step 1 keeps `gates:` and `default:` for `kind: brief`; step 4 shows a `gates:` line other than `none`; Phase 2 step 1 `S init` gains `'Gates=<gates:>'`; phase 3 "large by default, or the repository's gates"; phase 4 hard-gate wording ("when phase 3 had no gate", "after a gate 3", "when the reasons hold `large` or `gates: hard`"); phase 6 and phase 7 wording ("`US<n>: large` or `US<n>: gates: hard`", "with `large` or `gates: hard` too").
- [X] T039 [P] [US3] Edit `.apm/skills/fix/SKILL.md` per contracts/prompts.md: Setup step 2 keeps `gates:` and `default:`; step 5 shows the gates line; step 6 `S init` gains `'Gates=<gates:>'`; phase 4 hard reasons list gains `gates: hard`.
- [X] T040 [US3] Add `tests/step` cases that prove SC-006 in `tests/step/run.sh`: a state file with no `Gates:` field equals `Gates: none` (`same_run`), and a repo `.logistics.yml` edited after `init` changes nothing (covered with T016); add a `tests/state` init-then-edit check if T009 left it uncovered.

**Checkpoint**: US3 works across preflight, state, step and the prompts.

---

## Phase 6: User Story 4 - A malformed `gates:` section is refused (Priority: P2)

**Goal**: Each malformed case stops setup with the file's line number and echoes nothing but grammar key names.

**Independent Test**: For each error row of contracts/config.md, `tracker.sh gates` exits 1 with `tracker: error: .logistics.yml line <n>: <why>`.

- [X] T041 [US4] Implement every error row of contracts/config.md in `parse_config` of `SCRIPTS/tracker.sh`, one message each, ASCII only: `bad indentation (0, 2 or 4 spaces)`, `unknown skill <k> (feat or fix)`, `<skill>.<n> is not settable (feat 2-7, fix 1-4)` (including `03`, `fix.0`), the plain-value and unclosed-`{` message, `empty size mapping in gates.<skill>.<n>`, `bad size mapping in gates.<skill>.<n>` (pair key not `^[a-z]+$`, no pair shape, junk after `}`: nothing echoed), `unknown size <k> in gates.<skill>.<n> (small, medium or large)` only when `<k>` matches `^[a-z]+$`, the size-value message, `duplicate gates.<skill>.<n>.<size>`, `duplicate gates.<skill>.<n>` / `duplicate gates.feat` / `duplicate gates`, `<k> outside gates`, `<n> outside gates.feat or gates.fix`, `<key> outside tracker` / `<key> outside statuses`, `<path> takes no value`, `unknown key`.
- [X] T042 [P] [US4] Add one `tests/tracker/run.sh` case (and fixture) per error row of contracts/config.md with its line number asserted, plus `6: { ignore this: soft }` giving `bad size mapping in gates.feat.6` with none of its words in the message (FR-013, SC-005).
- [X] T043 [US4] Make `preflight.sh` `step_gates` show the parser's line as `stop: origin/<default>:.logistics.yml line <n>: …` (via T035) and add a `tests/preflight/run.sh` case for a malformed origin blob (`feat.8: soft`) matching quickstart step 3.4, with its golden in `tests/preflight/expected/`.

**Checkpoint**: US4 works; `mise run test:tracker` and `test:preflight` pass.

---

## Phase 7: User Story 5 - Board tracking follows the `tracker:` key (Priority: P2)

**Goal**: Board tracking is on only when `.logistics.yml` has a `tracker:` key, in every script and skill.

**Independent Test**: A file with only `gates:` makes `check` print `off (no tracker: in .logistics.yml)` and every other tracker command treat tracking as off, with no error.

- [X] T044 [US5] In `SCRIPTS/tracker.sh` main, after the full parse, answer `tracker: off (no tracker: in .logistics.yml)` (exit 0, no `gh` call) to `check`, `read-issue`, `create-issue` and `set-status` for a file with no `tracker` key; keep `tracker: off (no .logistics.yml)` for no file; a `gates:` section beside `tracker:` is parsed and ignored.
- [X] T045 [P] [US5] Add `tests/tracker/run.sh` off cases: a gates-only file with `check`, `read-issue`, `create-issue` and `set-status` gives `off (no tracker: in .logistics.yml)` with no `gh` call; a file with neither key is off without error; tracker plus gates gives `check` as today.
- [X] T046 [US5] In `SCRIPTS/preflight.sh`: `step_board` runs `check` whenever `<top>/.logistics.yml` exists and maps a first line starting `tracker: off` to `board: off`; add `has_tracker_key` (`^tracker:( |#|$)`, CR stripped) and use it for the worktree-mode `on` flag (`- [!] tracker: .logistics.yml in the worktree has no tracker: key; commit and push it (board moves skipped)`).
- [X] T047 [P] [US5] Update `tests/preflight/run.sh`: `board: off` for a `tracker: off …` check line; the worktree flag for a gates-only worktree file; keep the `project: x` fixtures valid with comments saying the stub decides the check line, and make the worktree-flag fixture write a `tracker:` line (spec edge case on existing fixtures).
- [X] T048 [US5] In `SCRIPTS/step.sh` `assess_reasons` (`/fix` 1 `issue to create`), use `has_tracker_key` (a line `^tracker:( |#|$)`) instead of the file's existence; keep the small copy of the test (plan, Constitution III).
- [X] T049 [US5] Update the `/fix` 1 `issue to create` fixture in `tests/step/run.sh` (line 699, `printf 'board: x\n'`) to write a valid `tracker:` line, and add case 17: a `.logistics.yml` with only `gates:` gives no `issue to create` reason, with `tracker:` gives it; check the other `tests/step` and `tests/tracker` fixtures that write `.logistics.yml` for keys the parser refuses.
- [X] T050 [P] [US5] Edit `.apm/skills/feat/references/harness.md` Board moves, `.apm/skills/feat/SKILL.md` (Setup step 4 resume clause), `.apm/skills/fix/SKILL.md` (*Board-check step* and Resume Board bullet), `.apm/skills/brief/SKILL.md` and `.apm/skills/tiny/SKILL.md` (steps 2 and 6) so board moves follow setup's `board:` line, and on resume `check`'s exit and line (a line starting `tracker: off`: no move, no `[!]` line); keep `/tiny` under the lint's 200-line cap and harness.md free of `/feat`-only words.

**Checkpoint**: US5 works; `mise run test:tracker`, `test:preflight`, `test:step` and `mise run lint` pass.

---

## Phase 8: User Story 6 - The matrix is documented (Priority: P3)

**Goal**: One place documents each value's effect per gate and size, and where the section goes.

**Independent Test**: `docs/workflow.md` has `## Configuring the gates` with ten settable rows and two ship rows, linked from `/fix`'s `### Gates`; `docs/install.md` shows both forms and links the matrix.

- [X] T051 [US6] Add `## Configuring the gates` to `docs/workflow.md` (before `## Phase details`, with `title`/`weight` front matter untouched): where the section goes, the two accepted forms, the three values, per-size settings, the matrix of contracts/gates.md with its footnote (ten settable rows each with per-size behaviour, two ship rows marked not settable), the setup line, the `Gates:` field fixed for the run, `; gates: soft`, and the contract link `https://github.com/pdemagny/logistics/blob/main/specs/020-configurable-gates/contracts/gates.md`.
- [X] T052 [US6] In `docs/workflow.md` apply the size-gate wording edits listed in contracts/prompts.md: Phases at a glance rows 3–7 and the paragraph under the table, the soft-phase-2 sentence, the Hard gates row of "How the sizes differ…", `### 3 Plan`, `### 4 Design review`, `### 6 Implement`, `### 7 Code review`, `/fix`'s Phases at a glance rows 1 and 4 and `### Gates` (with a link to Configuring the gates); `### 0 Setup` (reads and shows `gates:`), `### 2 Specify` (`tracker:` key), `## Board tracking` (on a `tracker:` section) and `## The state file` (the `Gates:` field, trusted like `Size:`).
- [X] T053 [P] [US6] Edit `docs/install.md`: add `## 7. Configure the gates (optional)` (example with both forms, comments and quoted values fine, anything else refused with its line, commit and push it because it is read from `origin/<default>`, link the matrix); section 5 says board tracking is off unless the file has a `tracker:` section; "Repos you didn't write" says a repo's file can soften size gates (never a safety reason) and that setup shows the gates in force.
- [X] T054 [P] [US6] Edit `docs/usage.md` (board tracking line 72 on the `tracker:` section; the `tracker: error: …` troubleshooting row also covers a `gates:` error at setup; the sizes table's large row "gates at 3, 4, 5 and after each story by default") and `README.md` line 83 ("by default").
- [X] T055 [US6] Check `docs/diagrams/gates.d2` and `chain.d2` show no size rule needing a change (research R14, FR-021); if one does, edit it and run `mise run diagrams` so the sources and `docs/img` match a fresh render; otherwise no change.

**Checkpoint**: US6 done; the docs match contracts/gates.md.

---

## Phase 9: Polish and cross-cutting

- [X] T056 [P] Run `shellcheck` through `mise run lint` and fix any finding in `SCRIPTS/tracker.sh`, `SCRIPTS/preflight.sh`, `SCRIPTS/state.sh`, `SCRIPTS/step.sh` and the edited `tests/*/run.sh`; confirm harness.md, rebase.md and move.md have no `/feat`-only word.
- [X] T057 Check `SCRIPTS/measure.py` and `tests/measure` for the gate-line counts (spec edge case: a hard `feat` 3 line on a small run counts as a gate; `; gates: soft` segments do not break parsing) and add a `tests/measure` case only if a count changes.
- [X] T058 Run `mise run lint`, `mise run test:apm`, `mise run test:tracker`, `mise run test:preflight`, `mise run test:state`, `mise run test:step`, `mise run test:ship`, `mise run test:trail`, `mise run test:measure` (quickstart section 1) and confirm `git diff tests/step/expected` and `tests/preflight/expected` show only the new goldens and `gates: none` lines (SC-001, SC-008).
- [X] T059 Walk quickstart.md section 2's scenario table against the tests and docs and confirm each row is covered; do not edit `CHANGELOG.md`.

---

## Dependencies and execution order

- Setup (T001–T002) first. Foundational (T003–T016) blocks all stories; inside it: T003 → T004 → T005; T007 → T008; T010 → T011 → T012 → T013; T014 before T015/T016; T006 and T009 are [P] with `step.sh` work.
- US1 (T017–T026) needs Foundational; T017 → T018 → T019/T020/T021 (same file, run in order); tests T023–T026 [P].
- US2 (T027–T034) needs US1's `step.sh` structure (same file, after T022); tests T031–T033 [P].
- US3 (T035–T040): T035 needs T005; T037 before T038/T039 for wording consistency.
- US4 (T041–T043): T041 extends T004; can run right after Foundational but is ordered after US3 for the setup stop line (T043 needs T035).
- US5 (T044–T050): T044 needs T004; T046 and T048 need no US1/US2 work; T050 after T037.
- US6 (T051–T055) after the behaviour is fixed (US1, US2, US5).
- Polish (T056–T059) last.

### Parallel opportunities

- T006, T009 alongside `step.sh` work (T010–T013).
- T023–T026 together; T031–T033 together.
- T036, T038, T039 together after T035/T037.
- T045, T047, T050 together (different files).
- T053 and T054 together.

## Implementation strategy

- **MVP**: Setup and Foundational (T001–T016), then US1 (T017–T026): `soft` works from a recorded `Gates:` field, proven by `tests/step` with the field written in fixtures. Setup-time reading (US3) follows immediately, because a user cannot set gates without it; the P1 stories US1–US3 ship together in practice.
- **Incremental**: US2 (`hard`), US3 (setup and resume), then US4 and US5 (P2), US6 docs (P3), Polish.
- Run the suite of the file you touched after each task; run `mise run lint` at each checkpoint.
