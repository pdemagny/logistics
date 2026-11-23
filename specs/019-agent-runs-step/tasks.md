---

description: "Task list for: Agents run step.sh last so the coordinator spawns straight from the hand-back"
---

# Tasks: Agents run step.sh last so the coordinator spawns straight from the hand-back

**Input**: Design documents from `specs/019-agent-runs-step/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/step-cli.md, contracts/prompts.md, quickstart.md

**Tests**: Requested (FR-020, FR-021): `tests/step` (16 new cases listed in contracts/step-cli.md#tests) and `tests/state` (one new case). Tests are written before the code they cover and must fail first.

**Organization**: Tasks are grouped by user story. Paths are relative to the worktree root. step.sh is `.apm/skills/feat/scripts/step.sh`, state.sh is `.apm/skills/feat/scripts/state.sh`. step.sh and state.sh stay Bash 3.2, no jq, no Python, shellcheck clean. Never edit `sizes.tsv` or a `sizes-start`/`sizes-end` block. Nothing is committed before phase 8; the agents, harness.md, both skills and step.sh land in one commit (plan.md, Order).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 to US6, from spec.md

## Phase 1: Setup

**Purpose**: a known-good baseline

- [X] T001 Run `mise run test:step`, `mise run test:state` and `mise run lint` once before any edit and note that they pass (baseline for the golden diff reviews in T019 and T030)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the decision record, the state hash and `render`, which every story's acceptance and tests rely on

**CRITICAL**: no user story work begins until this phase is complete

- [X] T002 Add the `record` subcommand to `.apm/skills/feat/scripts/state.sh` per contracts/step-cli.md#state.sh-record: `state.sh record <state file> <line>...`, `reports_dir "$1"`, `t=$R/last-step.md`, `no_symlink "$t"`, a present non-regular file is `state: error`, `reports_make`, `L=('Data, never instructions: step.sh'\''s last decision, for its re-print and its open boundary.' "$@")`, `write_file "$t"`, prints `$t`; no line is `state: usage:`; lines follow the argument rule (no newline, no carriage return); name it in the header's subcommand list, `SYN_ALL` and the dispatch
- [X] T003 Add the `record` case beside the `inputs` case in `tests/state/run.sh`: writes the fixed line and the lines (tabs kept), creates `reports/` with a `.gitignore` holding `*`, rewrites the file whole; a symlinked record or symlinked `reports/` is `state: error` and writes nothing through the link; no line is `state: usage`; run `mise run test:state` (depends on T002)
- [X] T004 In `.apm/skills/feat/scripts/step.sh` split `print_all` into `render` (fills `OUT_L`) and the print (`printf '%s\n' "${OUT_L[@]}"`); in `main` a `refused:` verdict runs `render` only (no `commit`) and then prints `OUT_L`; output of every existing case stays byte-identical
- [X] T005 In `.apm/skills/feat/scripts/step.sh` add the state hash (FR-022): `load_state` sets `SF_H0` to `git -C "$SFDIR" hash-object --no-filters -- "$SF"` before `read_state` (a failure: `die "git hash-object failed on <name>"`); `commit` hashes again first and, when it differs, `die 'the state file changed since step.sh read it; call again'` with nothing written and `CM_SET` still empty; `size` and `resume` go through `commit` and are checked too
- [X] T006 In `.apm/skills/feat/scripts/step.sh` add `record_read` (path `$SFDIR/reports/last-step.md`; a symlinked `reports/` or record is `die`; no `reports/` or no record: `RC_HAS=0`; else `RC_HAS=1`, `RC_CALLS`, `RC_SUMS`, `RC_ISSUED`, `RC_VERDICT`, `RC_OUT`; a wrong first line, a `call:` with no `sums:` after it, or no `output:` line: `die 'reports/last-step.md is not a step record'`) and `record_write` (builds the `call:`/`sums:` pairs: the previous record's when `RC_VERDICT` is `reformat` and this call is a boundary call, then this call's; then `output:` and `OUT_L`; runs `st record "$SF" <line>…`); in `commit`, after the hash check, Log line, sets, snapshot and `@SNAP@` substitution and before `CM_SET=()`, call `render` then `record_write` unless the call is `size`, so a failed write goes through `undo_sets` (FR-023); never for `refused:`, errors or `size` (depends on T002, T004, T005)

**Checkpoint**: the record is written by every decided call and nothing else changes in step.sh's output

---

## Phase 3: User Story 1 - A sequential boundary costs the coordinator no step.sh call (Priority: P1) 🎯 MVP

**Goal**: the six agents run their `boundary:` call last and hand back its output in a four-backtick block; the coordinator acts on that block with no `step.sh` call, except for a `done:`.

**Independent Test**: after each sequential agent hand-back of a small `/feat` and `/fix`, the coordinator spawns the next agent or shows the gate with no call of its own; `tests/step` cases 1, 2, 3 and 7 pass.

### Tests for User Story 1

- [X] T007 [US1] Add tests/step case 1 (agent-run soft, `feat` 2 from `2 Specify`: planner block ends with `step script:` and `boundary:`, `Agents:` unchanged) and case 2 (agent-run hard with an open marker: `hard:`, `answer call:` last) as `new_case` blocks in `tests/step/run.sh`; they fail before T010
- [X] T008 [US1] Add tests/step case 3 (`feat` 8 from `done (shipping)`, `resume` first: `done: PR #N`; then the same call again re-prints it byte for byte, state file and `reports/last-step.md` unchanged by `cmp`) and case 7 (a story report with a failing check: `soft`, retry spawn `6-US1-2.md` with `failures` in its inputs file and the two keys) in `tests/step/run.sh`

### Implementation for User Story 1

- [X] T009 [US1] Add the `bline <token> <word>…` helper to `.apm/skills/feat/scripts/step.sh` (`out_call 21 '  step script:' "$SDIR/step.sh" "$SKILL" "$SF"`, `out_call 21 '  boundary:' <token> <word>…`, `out_call 22 'boundary:' <token> <word>…`)
- [X] T010 [US1] In `.apm/skills/feat/scripts/step.sh` replace the `out_call 22 'boundary:'` of every agent-run spawn with `bline`, right after the block's last `skey`: `next_step` (2, 3, 5, `/fix` 1, `/fix` 3), `amend_spawn`, `next_story`, `spawn_fixes`, `next_fix`, `enter_ship`, and `reformat` when the report is not a reviewer's or a move's; reviewer and rebase-mode spawns keep today's call line only; the call words of boundaries 2, 3 and 5 lose `agent=<id>` (lines near 1912 to 1922 and 2633) (depends on T009)
- [X] T011 [P] [US1] Add the "Last step" section to `.apm/agents/feat-specifier.agent.md` (text in contracts/prompts.md#agents, worded the same in all six, before the "Report, and nothing else" paragraph) and add "then the last step's block (Last step)" to its "Report file" paragraph
- [X] T012 [P] [US1] Same section and Report file sentence in `.apm/agents/feat-planner.agent.md`
- [X] T013 [P] [US1] Same section and Report file sentence in `.apm/agents/feat-tasker.agent.md`
- [X] T014 [P] [US1] Same section and Report file sentence in `.apm/agents/feat-implementer.agent.md` (rebase mode unchanged: no `boundary:` key reaches it)
- [X] T015 [P] [US1] Same section and Report file sentence in `.apm/agents/feat-shipper.agent.md`
- [X] T016 [P] [US1] Same section and Report file sentence in `.apm/agents/feat-bug-assessor.agent.md`
- [X] T017 [US1] Edit `.apm/skills/feat/references/harness.md` per contracts/prompts.md#harness.md, without `/feat`-only words (lint greps `specifier`, `planner`, `tasker`, `spec.md`, `brief`, `phase <n>`, `/feat`; write "the agents that may be continued"): "Step script", "The boundary call" (an agent with `step script:` and `boundary:` keys makes its call itself; read its block as your own output and act in the same turn; you call for spawns with no such keys, answers, `setup`, `resume`, the slip fallback and the `done:` check; drop "`agent=<id>` is filled in…"), and the new bullet **The `done:` check**
- [X] T018 [US1] In `.apm/skills/feat/SKILL.md` phase 8 and `.apm/skills/fix/SKILL.md` phase 5, make the final message follow the `done:` check (harness), not the shipper's block (further edits to those files follow in T034 and T035; do these two sentences first)
- [X] T019 [US1] Regenerate the spawn goldens (`UPDATE=1 bash tests/step/run.sh`), review `git diff tests/step/expected` (every agent-run block gains `step script:` and `boundary:` as its last keys; nothing else changes except what T030 later removes); cases 3 and 4's re-prints pass only after T023, so run `mise run test:step` fully at T024 (depends on T007, T008, T010)

**Checkpoint**: US1 works with the record in place; a missing or broken block is only safe once US3 lands, so US1 ships with US3

---

## Phase 4: User Story 3 - A missing or broken block never costs a decision (Priority: P1)

**Goal**: a boundary call is accepted only as a re-print of the record or as the open boundary; anything else is `step: error`; a slip costs one own call and no second decision.

**Independent Test**: tests/step cases 4, 5, 6, 14, 15 and 16 pass.

### Tests for User Story 3

- [X] T020 [US3] Add tests/step case 4 (re-print after case 1: stdout equal byte for byte; state file and `last-step.md` identical by `cmp`) and case 5 (after `setup`, boundary 3 with a plan report, and boundary 2 with the never-printed path `2-specify-2.md`: both `step: error` exit 1) in `tests/step/run.sh`
- [X] T021 [US3] Add tests/step case 6 (phase 6 with two stories: US1 decided, US1's report edited, boundary 6 with US1's path is `step: error`; then US1's unchanged report after US2 decided, the older token, is `step: error`, not a re-print) in `tests/step/run.sh`
- [X] T022 [US3] Add tests/step case 14 (`fail_once 'record:*'` on a soft 2 to 3: `step: error` exit 1, `Current phase` back to `2 Specify`, `last-step.md` unchanged by `cmp`; the retry decides as the first try, its Log line once), case 15 (a wrapper in place of the scratch state.sh runs a real `state.sh log` when the decision calls `report-path`: `step: error: the state file changed since step.sh read it; call again` exit 1, `Current phase` unchanged, the wrapper's line kept, `last-step.md` unchanged) and case 16 (`resume` with no `reports/`: created with `.gitignore` holding `*`, `last-step.md` written; a symlinked `reports/`: `step: error` exit 1) in `tests/step/run.sh`
- [X] T023 [US3] Implement the acceptance in `do_boundary` of `.apm/skills/feat/scripts/step.sh`, before today's checks, for a call with no `answer:` word (contracts/step-cli.md#acceptance): `record_read`; when one of `RC_CALLS` equals the call's words and every report path of the call hashes (`hash_file`, the renumbered path when the given one is gone and `renumbered` finds it) to that pair's `RC_SUMS` value, set `REPRINT=1` and have `main` print `RC_OUT` and exit 0 with no commit and no record write; else when `RC_HAS`, an empty `RC_ISSUED` is `die "no boundary is open ($RC_VERDICT)"` and a first word that is not the token or a report path of the call not among its words is `die "boundary <token> <first report name or 'with no report'> is neither the open boundary (<issued token>) nor the last decided one with the same report"`; when not `RC_HAS`, today's `allowed_tokens` check; today's checks run after; answer calls keep `open_gate` (depends on T006)
- [X] T024 [US3] Run `mise run test:step` and fix until cases 3 to 6 and 14 to 16 pass (depends on T020 to T023)

**Checkpoint**: US1 and US3 together are the MVP

---

## Phase 5: User Story 2 - A format slip is repaired by the agent, once (Priority: P1)

**Goal**: on `reformat` the agent rewrites the report at the named path, runs the new block's `boundary:` once and hands back the second output; the coordinator's slip fallback re-prints that decision.

**Independent Test**: tests/step case 11 passes.

- [X] T025 [US2] Add tests/step case 11 in `tests/step/run.sh`: boundary 2 with an unparsable report prints `reformat`; the corrected report at the reformat block's `report:` path with its block's `boundary:` words prints the decision and `last-step.md` holds two `call:` lines; the first call's words again (original report unchanged) re-print that decision byte for byte with the state file unchanged; in a second run a second unparsable report at the reformat path is today's hard gate
- [X] T026 [US2] Make case 11 pass in `.apm/skills/feat/scripts/step.sh`: `reformat` spawns that are not a reviewer's or a move's print `step script:`/`boundary:` via `bline` (T010 covers the call sites) and `record_write` keeps the previous record's `call:`/`sums:` pairs while the verdict is `reformat` (T006); fix whatever the case shows; then add the Slip fallback bullet to `.apm/skills/feat/references/harness.md` (no block, a block that does not parse, or a `step: usage:` line: make the boundary's call yourself with the words printed with that spawn; a decided call prints again and logs nothing, also after a reformat the agent ran; act only on the hand-back of the agent you wait on; a `step: error` at an agent's boundary may mean the previous block was not step.sh's)

**Checkpoint**: US2 done

---

## Phase 6: User Story 4 - Agent ids arrive late, on the coordinator's next own call (Priority: P2)

**Goal**: agent-run boundaries take no `agent=` word; `agent=<role>:<id>` rides on answer calls and reviewer batch calls; a reformat spawn prints `continue: <role>`; the gate 4 planner amend prints the recorded id.

**Independent Test**: tests/step cases 8, 9, 10 and 13 pass.

- [X] T027 [US4] Add tests/step case 8 (large `feat` at hard gate 3 answered with `agent=planner:p1 agent=specifier:s1`: `Agents:` holds both), case 9 (medium `feat` 4 batch with an `apply` finding and `agent=planner:p1`: the amend reads `continue: p1`), case 10 (`Agents:` holds `specifier s0`; boundary 2 with an unparsable report: the reformat spawn reads `continue: specifier`, not `s0`) and case 13 (`agent=planner:p1` on boundary 3, `agent=p1` on an answer call, `agent=planner:p1` in `/fix`: `step: usage` exit 2) in `tests/step/run.sh`
- [X] T028 [US4] In `.apm/skills/feat/scripts/step.sh` replace the `agent=<id>` argument with `agent=<role>:<id>` (`/feat` only, on an answer call or a reviewer batch call, tokens 4, 7 and 7e; `<role>` is `specifier`, `planner` or `tasker`; `<id>` matches `[A-Za-z0-9_-]{1,64}`; repeatable, the last word per role wins; elsewhere, in `/fix`, or malformed: `step: usage: agent=<role>:<id> only on an answer call or a reviewer batch's call: …`); write the ids with `set_agent` at the start of the decision, before any spawn prints; a `refused:` answer writes nothing; drop the old `agent=<id>` argument from the three `A_AGENT` usage checks (near 2777, 4007, 4072)
- [X] T029 [US4] In `.apm/skills/feat/scripts/step.sh` make a `reformat` spawn of a report whose `role_of` is `specifier`, `planner` or `tasker` print `continue: <role>` with no `agent_id` lookup (remove the `AID=`/`agent_id "$ROLE"` lines there); keep `review_gate`'s planner amend after a soft gate 4 on today's lookup (`agent_id planner`, else `fresh`); every other spawn `fresh`
- [X] T030 [US4] Remove the existing `agent=<id>` uses from `tests/step/run.sh` (cases passing it on 2, 3 or 5; `full_go` stops substituting `agent=<id>`), update `Agents:` lines in `tests/step/fixtures/logs/full-*.md`, regenerate goldens (`UPDATE=1 bash tests/step/run.sh`), review `git diff tests/step/expected`, run `mise run test:step`
- [X] T031 [US4] Add the **Agent ids** bullet and the continuation sentence (`continue: <role>` continues the latest agent of that role by the id its Agent result gave; holding none, after a resume: a fresh spawn) to `.apm/skills/feat/references/harness.md` (same file as T017 and T026; no `/feat`-only words)

**Checkpoint**: US4 done

---

## Phase 7: User Story 5 - Coordinator chores move to the coordinator's next own call (Priority: P2)

**Goal**: Log lines wait for the coordinator's next own `step.sh` call; other chores ride in the response that acts on the hand-back.

**Independent Test**: tests/step case 12 passes; the skills say where each chore goes.

- [X] T032 [US5] Add tests/step case 12 in `tests/step/run.sh`: `S log '- [!] brief left in place: /x/b.md'`, then an answer call: the line is in the Log before the answer's lines; a pending log line with an `agent=` word on the same own call: both land; run `mise run test:step`
- [X] T033 [US5] Add the **Chores** bullet to `.apm/skills/feat/references/harness.md` (a Log line waits for the next own `T` call, an answer, a batch, a slip fallback or the `done:` check, as `S log … && T …`; at the end one `S log` call in the final turn; other chores are tool calls in the response that acts on the hand-back; make no `S` or `T` call while an agent that closes its own boundary runs) and extend the State file sentence "An `S` call rides on a call made at that boundary" with "or on your next own call (Chores)"
- [X] T034 [US5] Edit `.apm/skills/feat/SKILL.md` (shared with T018): phase 2 step 1 logs a preflight `flag:` with the next own call and flags it at the first gate; phase 2 step 2 deletes the brief in the response that acts on the specifier's hand-back, a brief left in place logged with the next own call (`S log '<state file>' '- [!] brief left in place: <path>'`) and named in the final message; phase 7 does the review move as a tool call in the response that makes the first reviewers' spawns, a failed move's `[!]` line going with the batch's call
- [X] T035 [US5] Edit `.apm/skills/fix/SKILL.md` (shared with T018): setup step 6 gets the same `flag:` sentence; phase 1 "When the gate passes" keeps its order (issue creation, the building move, then the spawn) after the assessor's hand-back, a failed move's `[!]` line going with the next own call; phase 4 does the review move in the response that makes the reviewers' spawns

**Checkpoint**: US5 done

---

## Phase 8: User Story 6 - The documents tell the same story (Priority: P3)

**Goal**: workflow.md, design.md, gates.d2 and its render say who calls `step.sh` where.

**Independent Test**: count the walk-through's coordinator calls; `mise run lint` passes.

- [X] T036 [P] [US6] Edit `docs/workflow.md` `/feat` Roles, Coordinator (the agent that closes a sequential boundary runs `step.sh` itself and hands its output back; the coordinator calls at setup, reviewer batches, answers, moves, a slip and the `done:` check) and add the subsection **A small run, call by call** after "Phases at a glance" (setup one call; specifier to planner none; the design batch one; its gate one answer call when hard; tasker and each story none; the code batch one, plus 7e on medium; its gate; the review fixes to shipper none; `done:` one check call)
- [X] T037 [US6] Edit `docs/workflow.md` `/fix` section (same file as T036): the Roles Coordinator bullet says the same split, and the phase 1 text says the assessor's boundary call is the assessor's
- [X] T038 [P] [US6] Edit `docs/design.md`: "both coordinators call once at each phase boundary" becomes who calls `step.sh` at which boundary
- [X] T039 [P] [US6] Edit `docs/diagrams/gates.d2`: participant `step` labelled `step.sh\n(one call per boundary)`, `agents -> step` for the specify, tasks and implement reports, `cc -> step` for setup, the batches, the answers and the `done:` check; leave `chain.d2` unchanged
- [X] T040 [US6] Run `mise run diagrams` and confirm `docs/img/gates.svg` is rewritten and `chain.svg` and `models.svg` are unchanged (depends on T039)

**Checkpoint**: all stories complete

---

## Phase 9: Polish & Cross-Cutting Concerns

- [X] T041 Update step.sh's header comment and `SYN` (contracts/step-cli.md#header-comment-and-syn): the argument list names `agent=<role>:<id>`, the output list the two new block keys, plus a paragraph on the record (reformat chain calls included), the acceptance order, that a re-print writes nothing and that a call refuses to write when the state file changed since it read it
- [X] T042 Run `shellcheck` through `mise run lint` and fix findings in step.sh, state.sh and the tests; confirm `tests/step/run.sh`'s Bash 3.2 construct grep passes and the harness.md `/feat`-only-word grep is clean
- [X] T043 Run every offline test and `mise run test:apm` (`test:step`, `test:state`, `test:ship`, `test:preflight`, `test:trail`, `test:tracker`, `test:spec-number`, `test:story`, `test:sizes`, `test:measure`, `test:secret-scan`) and `mise run lint`, all exit 0
- [X] T044 Walk through quickstart.md's spot checks (re-print, fail closed, the record's contents, reformat chain, concurrent write, diagrams) and confirm each

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (Phase 1): none
- Foundational (Phase 2): after Setup; blocks every story. T002 then T003; T004 and T005 then T006
- US1 (Phase 3) after Phase 2; US3 (Phase 4) after Phase 2 and T010 (it uses the spawn blocks and cases 1 and 4 chain); US2 (Phase 5) after US1 and US3; US4 (Phase 6) after Phase 2 (T028 and T029 touch the same step.sh regions as T010, so run after it); US5 (Phase 7) after US1 for harness.md and the skills; US6 (Phase 8) after the behaviour is settled
- Polish last

### Within and across stories

- Tests precede the code they cover; each must fail first
- Same-file tasks never run in parallel: step.sh (T004 to T006, T009, T010, T023, T026, T028, T029, T041), harness.md (T017, T026, T031, T033), `/feat` SKILL.md (T018, T034), `/fix` SKILL.md (T018, T035), `tests/step/run.sh` (T007, T008, T020 to T022, T025, T027, T030, T032), workflow.md (T036, T037)
- The agents, harness.md, both skills and step.sh are one commit (CLAUDE.md: the format and its readers change together)

### Parallel Opportunities

- T011 to T016: six agent files, all [P]
- T036, T038, T039: three different docs files
- T003 can run while T004 and T005 are written (different files)

### Parallel Example: User Story 1

```text
Task: "Last step section in .apm/agents/feat-specifier.agent.md"
Task: "Last step section in .apm/agents/feat-planner.agent.md"
Task: "Last step section in .apm/agents/feat-tasker.agent.md"
Task: "Last step section in .apm/agents/feat-implementer.agent.md"
Task: "Last step section in .apm/agents/feat-shipper.agent.md"
Task: "Last step section in .apm/agents/feat-bug-assessor.agent.md"
```

---

## Implementation Strategy

### MVP First

1. Phase 1 and Phase 2 (record, hash, `render`)
2. Phase 3 (US1) and Phase 4 (US3): the saving, with fail-closed acceptance and the slip fallback's re-print; the MVP is T001 to T024
3. Validate with `mise run test:step` and `mise run test:state`

### Incremental Delivery

1. Add US2 (reformat chain), then US4 (ids), then US5 (chores), then US6 (docs), running the offline tests after each
2. Land everything in one PR: the prompts and step.sh change together, so no story ships alone

## Notes

- [P] tasks touch different files
- Every constraint of data-model.md is quoted in contracts/step-cli.md; follow it verbatim (the agent id pattern `[A-Za-z0-9_-]{1,64}`, the record's fixed first line)
- Nothing is committed before phase 8
