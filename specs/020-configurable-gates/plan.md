# Implementation Plan: Configurable gates

**Branch**: `configurable-gates` | **Date**: 2026-11-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/020-configurable-gates/spec.md` (issue #34), amended for per-size keys

## Summary

`.logistics.yml` gains an optional `gates:` section: per phase, a plain
value (every size) or a one-line `{ <size>: <value>, … }` mapping, parsed
by `tracker.sh`'s strict parser through a new `gates <skill>` subcommand
(config on stdin, no `gh`). Setup (`preflight.sh` mode 1) reads the file
as committed on `origin/<default>`, the tree the worktree is branched
from, and prints `gates: <tokens> | none`; the coordinator shows it with
its source and passes it to `state.sh init` as `Gates=`, which writes a
`- Gates:` header field nothing later changes (`feat.3=hard
feat.6.large=soft`). `step.sh` reads only that field and applies the cell
for the run's size (at `/fix` 1, the proposed size) where each gate's
table adds its size reason: `soft` drops the size reason and evaluates the
small/medium rows, `hard` adds `gates: hard`, `auto` is today's code path;
softened soft lines end `; gates: soft`. Board tracking becomes "the file
has a `tracker:` key" in `tracker.sh`, `preflight.sh`, `step.sh`, the
skills and the docs. The gate matrix goes into `docs/workflow.md`, sourced
from this feature's amending contract.

## Technical Context

**Language/Version**: Bash 3.2 or later for `step.sh`, `state.sh`,
`preflight.sh` and now `tracker.sh` (its two Bash 4 constructs removed);
Markdown prompts and docs

**Primary Dependencies**: none new; `git cat-file`/`git show` as
`preflight.sh` uses them for hooks

**Storage**: one header line in the state file (`- Gates: …`); the
repository's `.logistics.yml` on `origin/<default>`

**Testing**: `tests/tracker`, `tests/preflight`, `tests/state`,
`tests/step` (17 case groups, most by comparing two runs of one fixture:
[contracts/gates.md](contracts/gates.md#tests-teststep)); `mise run lint`,
every `mise run test:*`, `mise run test:apm`; [quickstart.md](quickstart.md)

**Target Platform**: Claude Code sessions running `/feat`, `/fix`,
`/brief`, `/tiny` (Linux, macOS `/bin/bash` 3.2); the `check` workflow

**Project Type**: prompt package (skills and subagents) with helper scripts

**Performance Goals**: no extra coordinator turn or tool call per run (the
value rides on preflight's existing call and `S init`'s existing command);
one extra `tracker.sh` process at setup, only when origin has a
`.logistics.yml`; one header field read per `step.sh` call

**Constraints**: FR-002/SC-001: with no field, `none`, or only cells of
other gates or sizes, every existing `tests/step` golden unchanged;
coordinators never read the file (FR-017); harness.md free of
`/feat`-only words; Bash 3.2, no jq, no Python, shellcheck clean; agent
report formats unchanged

**Scale/Scope**: step.sh (~110 lines), tracker.sh (~90), preflight.sh
(~30), state.sh (~40), harness.md and the four skills (a few sentences
each), three docs pages, four test suites; ~45 tasks (medium, upper end)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
| --------- | ----- | ------ |
| I. Thin coordinators | the coordinators carry one printed value into `S init` and show one line; parsing is in `tracker.sh`, reading at setup in `preflight.sh`, writing in `state.sh`, applying in `step.sh` | pass |
| II. The user decides at gates | `soft` removes only size reasons; every judgement and safety reason, and every report-check failure, still stops; `hard` only adds stops; ship is not settable | pass |
| III. One source of truth | one parser (`tracker.sh`); the field written once by `state.sh init`, read by `step.sh`; the gate-3 rule for a run with gates in `step.sh` only (`phase2-mode` takes its gate from it; its no-argument default, today's Size rule, is kept only for callers and tests that pass no gate, and the `tests/step` oracles that use it keep fixtures with no `Gates:` cell); the shared coordinator paragraph in harness.md; the matrix cites the contract. Two small copies, as `default_branch` already is (scripts can't source each other): the `tracker:` line test in `step.sh` and `preflight.sh`, the canonical-value check in `state.sh` and `step.sh` | pass |
| IV. Fixed report formats | agent report formats unchanged; preflight's new `gates:` key and `phase2-mode`'s optional argument change their contracts, the skills and the tests together | pass |
| V. Small and plain | no new script or file in `.apm/`; one `tracker.sh` subcommand, a few `step.sh` helpers, one named flag; offline tests for each path, mostly comparisons rather than goldens | pass |

Distribution: no file added to or removed from `.apm/`, no agent added;
`plugin.json`, `apm.yml`, `install.sh` unchanged. sizes.json untouched.

Post-design re-check: pass. No service, dependency, permission or network
exposure added (`tracker.sh gates` calls nothing; the config stays
untrusted data, never evaluated, values from an enum). Size trigger: none.

## Project Structure

### Documentation (this feature)

```text
specs/020-configurable-gates/
├── plan.md            # this file
├── research.md        # decisions R1–R18 (R17, R18: the two design reviews, settled)
├── data-model.md      # gate setting, Gates field, cell lookup, Log lines, phase2-mode, board switch
├── quickstart.md      # validation
├── contracts/
│   ├── gates.md       # amends 013's gates.md (and two step-cli.md lines); the matrix; tests/step cases
│   ├── config.md      # .logistics.yml grammar and errors, tracker.sh, preflight.sh, state.sh
│   └── prompts.md     # harness.md, skills, docs
└── tasks.md           # phase 5
```

### Source code (repository root)

```text
.apm/skills/feat/scripts/tracker.sh     # parse_config: gates section with plain and flow-mapping values, free top-level order; gates <skill>; off without tracker:; Bash 3.2
.apm/skills/feat/scripts/preflight.sh   # step_gates (origin blob → tracker.sh gates <skill>); gates key slot; step_board off; worktree flag on the tracker: key
.apm/skills/feat/scripts/state.sh       # init Gates= (canonical, default none); header; set refuses it; phase2-mode [<3|4>]
.apm/skills/feat/scripts/step.sh        # F_GATES read and checked; gate_cfg, in_force, size_gate, gate3_stops, G3STOP; plan3_rows; gates 2–7 and /fix 1–4; TR_GATES; soft mark; note condition; has_tracker_key
.apm/skills/feat/references/harness.md  # Gates in force paragraph; Gates in the state template; board moves on setup's board: line
.apm/skills/feat/SKILL.md               # keep gates: and default:, show, Gates= in S init; resume board clause; phases 3, 4, 6, 7 wording (large or gates: hard)
.apm/skills/fix/SKILL.md                # keep gates: and default:, show, Gates= in S init; resume board clause (two places); phase 4 reasons list
README.md                               # line 83: "by default"
.apm/skills/brief/SKILL.md              # board tracking on the tracker: key
.apm/skills/tiny/SKILL.md               # same (steps 2 and 6)
docs/workflow.md                        # ## Configuring the gates; "by default" on the size rules; board tracking; setup; state file
docs/install.md                         # ## 7. Configure the gates (optional); section 5; repos you didn't write
docs/usage.md                           # board tracking line; troubleshooting row; sizes table large row "by default"
tests/tracker/run.sh (+ fixtures)       # gates cases, error rows, off cases, bash 3.2 grep
tests/preflight/run.sh, expected/       # gates step, board off, worktree flag; stub tracker answers gates; goldens gain gates: none
tests/state/run.sh, expected/           # init Gates, set refused, phase2-mode with a gate
tests/step/run.sh, expected/            # same_run / same_verdict helpers; new goldens for new forms; the issue-to-create fixture writes tracker:
```

**Structure Decision**: no new file outside `specs/` and test goldens.

## Design

Details: [contracts/gates.md](contracts/gates.md),
[contracts/config.md](contracts/config.md),
[contracts/prompts.md](contracts/prompts.md), [data-model.md](data-model.md),
[research.md](research.md).

- **Parser (FR-001, FR-013, FR-014; R2–R4)**: `parse_config` tracks the
  current top-level section and skill; `tracker` and `gates` in any order;
  the tracker completeness checks only when `tracker` was seen; `RE_KEY`
  takes letter or digit keys; a phase value is a plain value or a one-line
  `{ … }` mapping, split on `,` into `<size>: <value>` pairs, each pair key
  checked against `^[a-z]+$` before a message names it (else `bad size
  mapping`, nothing echoed); the error rows of config.md, one message each. `cmd_gates <skill>` prints the canonical
  tokens. `declare -A st` and `${name,,}` go; empty-array expansions are
  guarded.
- **Board switch (FR-015, FR-016; R5)**: `tracker.sh` main: no `tracker`
  key → `off (no tracker: in .logistics.yml)` for every subcommand but
  `gates`. `preflight.sh` `step_board` maps `tracker: off…` to `board:
  off`; worktree flag on `has_tracker_key`. `step.sh` `assess_reasons` uses
  `has_tracker_key`. Skills and docs reworded (prompts.md); harness.md's
  board sentence reads setup's `board:` line, and on resume `check`'s exit
  and line (no move when it starts `tracker: off`), the clause repeated in
  `/feat` Setup step 4 and `/fix`'s *Board-check step* and Resume Board
  bullet. Fixtures: `tests/step`'s
  `board: x` becomes a `tracker:` line; `tests/preflight`'s `project: x`
  files stay (the stub decides the check line) with comments, the
  worktree-flag one writes a `tracker:` line.
- **Setup (FR-010, FR-012; R1, R16)**: `preflight.sh` `step_gates` after
  `step_base` for kinds brief, issue, symptom; key `gates` after `board`.
  `/feat` and `/fix` keep it with `default:`, show `Gates in force (from
  origin/<default>:.logistics.yml): <value>` when not `none` (harness), and
  pass `'Gates=<gates:>'` to `S init`. `state.sh init` checks the
  canonical form and writes `- Gates:`; `set` refuses it.
- **Applying (FR-002–FR-009, FR-011, FR-023; R7–R11)**: `read_state` reads
  `- Gates:` into `F_GATES`; a check after `load_state` dies on a
  non-canonical value. `gate_cfg <n> <size>` finds the cell (size token,
  else plain, else `auto`); `size_gate` replaces each `reason large` /
  `reason "$u: large"` / `proposed size` row; `in_force` replaces the `$SC
  == large` / `$SC != large` row-skipping tests in `dec_feat_3` and
  `review_gate`; `gates: hard` after the table's reasons at `feat` 2 and
  `fix` 2. Gate 3 stops on `gate3_stops`; gate 4 picks its rows from the
  size reason and `G3STOP` (research R8's table), `plan_rows` split into
  `plan3_rows` and the rest (a large gate 4 with `feat.4` soft after a
  stopped gate 3 skips `plan3_rows`: the exception FR-004 and SC-003
  name); the note's condition is `G3STOP`. Every coordinator line that
  renders a hard gate by `large` also reads `gates: hard` (prompts.md). `fix` 3:
  `TR_GATES` (R10). The soft mark on the lines of data-model.md.
  `review_boundary`'s token-7 call adds nothing.
- **phase2-mode (FR-007; R12)**: `step.sh` passes `gate3_stops`' gate (3
  or 4) at its four `st phase2-mode` calls; `state.sh` uses it. Its
  no-argument default (today's Size rule) stays only for callers and tests
  that pass no gate: the `tests/step` oracles `log-readers-agree` and
  `queries` keep fixtures with no `Gates:` cell, and a case whose state
  file carries one passes the gate to the oracle.
- **Contract and docs (FR-019–FR-022; R13–R15)**: contracts/gates.md is the
  source (it also amends two lines of 013's `step-cli.md`);
  `docs/workflow.md` `## Configuring the gates` holds its matrix and links
  it; the size-gate sentences listed one by one in prompts.md (workflow.md
  lines 97, 180, 330, 364, 412, 468, 775 and the Phases at a glance rows;
  README line 83; usage.md line 301) read "by default" or link the
  section; install.md section 7; usage.md; diagrams unchanged.

## Testing

`tests/step` asserts SC-001, SC-003, FR-009, FR-023 and SC-009 by
comparing two runs of one fixture (`same_run`: identical output;
`same_verdict`: identical verdict, reasons and gate line once the size and
the `; gates: soft` mark are set aside; with `plan3`, the medium side's
`plan3_rows` reasons too, for SC-003's gate-4 fixture whose gate 3
stopped), not by a golden per cell. New
goldens exist only for the forms this feature adds (a `gates: hard` gate,
the soft mark, the small gate 3 and its answers, the `fix.3` hard row and
its answer). `tests/tracker` takes one case per error row, plus a pair key with spaces
(`{ ignore this: soft }` → `bad size mapping`); `tests/state`
and `tests/preflight` cover the field and the setup line
([contracts/config.md](contracts/config.md)).

## Decisions taken with the user

1. **The `Gates:` field is trusted like `Size:`** (kept by the user at the
   phase 3–4 gate). It sits in the state file, which any phase agent can
   edit and which the reviewer snapshot leaves out on purpose (the
   coordinator writes it while reviewers run), so an edit could soften the
   run's later gates with no `files changed outside the reports` reason.
   `Size:` has the same exposure today. The plan keeps that trust model,
   refuses a non-canonical value, and says so in contracts/gates.md
   (Trust), contracts/config.md (`state.sh`) and `docs/workflow.md`'s `##
   The state file`; guarding both fields is a follow-up issue, not this
   feature.
2. **The design review's D1–D7 are applied** (research R18); D2 rewords
   FR-004, US1 scenario 4 and SC-003 (gate 4 skips the plan rows when gate
   3 stopped, on large with `feat.4` soft too).

Every other decision beyond the spec is the planner's, recorded in
research.md (R2 the skill argument, R3 the Bash 3.2 port, R4 the error
wording, R6 canonical values and no folding, R10 the `fix.3` flag, R12
`phase2-mode`'s argument, R13 013's files unedited, R14 diagrams
unchanged, R16 the shown line).

## Order

`tracker.sh` and `tests/tracker` (the parser the rest relies on);
`state.sh` and `tests/state`; `step.sh` and `tests/step` (the existing
goldens first, unchanged, then the comparison helpers, then the new
cases); `preflight.sh` and `tests/preflight`; harness.md and the skills;
docs; `mise run lint` and every suite.

## Complexity Tracking

No constitution violation; nothing to justify.
