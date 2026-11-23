# Implementation Plan: Agents run step.sh last so the coordinator spawns straight from the hand-back

**Branch**: `agent-runs-step` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-agent-runs-step/spec.md` (issue #88, part of epic #31)

## Summary

Each spawn whose boundary one agent closes gets two last keys from step.sh,
`step script:` (step.sh's path, the skill, the state file) and `boundary:`
(the call words), so the coordinator's "every key goes into the prompt"
rule carries them. The six agents that close such boundaries run that call
as their last step, act on `reformat` only (once), and end their hand-back
with the output in a four-backtick block, only ever a copy of that Bash
result; the coordinator acts on that block as on its own output, and makes
the call itself when the block is missing or does not parse, and once on a
`done:` (the one verdict no later call checks). step.sh writes, as the
last part of every decided call's commit, a decision record
(`reports/last-step.md`, through a new `state.sh record` that shares
`report-path`'s guard: the call and the earlier calls of its reformat
chain, their reports' sums, and the output as printed); a boundary call is
accepted only as a re-print of that record (the words of one of its calls,
same sums: printed again, nothing written) or as the open boundary its
issued `boundary:` line names, else `step: error`. `commit` refuses when
the state file changed since step.sh read it. Agent ids move to
`agent=<role>:<id>` words on the coordinator's answer and reviewer batch
calls; a reformat spawn of the specifier, planner or tasker prints
`continue: <role>`, and the gate 4 planner amend keeps its id lookup. The
coordinator's Log lines wait for its next own call; its other chores ride
in the response that acts on the hand-back.

## Technical Context

**Language/Version**: bash 3.2 or later for `step.sh` (its construct limits,
checked by `tests/step/run.sh`'s grep); Markdown prompts; D2 for one
diagram

**Primary Dependencies**: none new; `mktemp`, `mv -f` and `git
hash-object` as step.sh uses them today

**Storage**: one file per run, `<artifact dir>/reports/last-step.md`
(ignored with `reports/`, never committed, left out of reviewer
snapshots), rewritten whole by `state.sh record` at the end of each
decided call's commit ([data-model.md](data-model.md#decision-record))

**Testing**: `tests/step/run.sh` (16 new case blocks, listed in
[contracts/step-cli.md](contracts/step-cli.md#tests); spawn goldens
regenerated); `tests/state/run.sh` (one new case block for `record`);
`mise run lint`, every `mise run test:*`, `mise run test:apm`;
[quickstart.md](quickstart.md)

**Target Platform**: Claude Code sessions running `/feat` and `/fix`
(Linux, macOS `/bin/bash` 3.2); the `check` workflow

**Project Type**: prompt package (skills and subagents) with helper
scripts

**Performance Goals**: SC-001: no coordinator `step.sh` call per
sequential spawn (18–25 per `/feat` run today), one `done:` check per run;
SC-006 measured after
merge with `measure.py` as it is

**Constraints**: step.sh stays the only decider and, with state.sh, the
only writer of the state file; Bash 3.2, no jq, no Python, shellcheck
clean; harness.md free of `/feat`-only words; `/feat` and `/fix` add only
the reading of the block; report formats, gates, verdicts and Log lines
unchanged; measure.py unchanged

**Scale/Scope**: step.sh (~150 lines added or changed), state.sh (one
subcommand, ~15 lines), 6 agent files (one section each), harness.md (~30
lines), `/feat` and `/fix` (a few sentences each), `docs/workflow.md`
(both skills' sections), `docs/design.md`, `gates.d2` and its render,
tests/step and its goldens, tests/state; ~42 tasks

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
| --------- | ----- | ------ |
| I. Thin coordinators | the coordinators make fewer calls and read only the block an agent hands back, which is `step.sh`'s output; no reading of code, reports or the record; the decision stays in step.sh | pass |
| II. The user decides at gates | gates and verdicts unchanged; the agent acts on `reformat` only and never changes its work to turn a gate soft (FR-004) | pass |
| III. One source of truth | the decision exists once, in the record step.sh wrote (the Log keeps its lines, gains no copy); the block keys and the call line come from one helper; the `reports/` guard lives once, in state.sh, used by `report-path`, `inputs` and `record`; the shared rules live once in harness.md, step.sh's rules in step.sh; sizes.json untouched | pass |
| IV. Fixed report formats | report formats unchanged; the last-step section sits before each format block, so every prompt still ends with its format; step.sh, tests/step, the agents and both skills change together | pass |
| V. Small and plain | no new script; one state.sh subcommand (`record`, beside `inputs`, reusing its guard and `write_file`); a hash compare in place of a lock; one identical section per agent; offline tests for each new path | pass |

Distribution: no file added to `.apm/`, no agent added or removed;
`plugin.json`, `apm.yml` and `install.sh` unchanged.

Post-design re-check: pass. No service, dependency or exposure added; no
new permission: the agents run one more `bash '<script>'` from the skill's
`scripts/`, as three of them already do, in the same session (research
R10). Size trigger: none.

## Project Structure

### Documentation (this feature)

```text
specs/019-agent-runs-step/
├── plan.md               # this file
├── research.md           # decisions R1–R13
├── data-model.md         # calls, spawn block, decision record, acceptance, Agents line, hand-back block
├── quickstart.md         # validation
├── contracts/
│   ├── step-cli.md       # step.sh's arguments, keys, record, acceptance, tests
│   └── prompts.md        # agents, harness.md, the two skills, docs
└── tasks.md              # phase 5
```

### Source code (repository root)

Changed:

```text
.apm/skills/feat/scripts/step.sh            # bline; agent=<role>:<id>; continue: <role> on reformat; render/record_write/record_read; acceptance; state hash check; header
.apm/skills/feat/scripts/state.sh           # record subcommand (reports_dir, reports_make, write_file); header, SYN_ALL, dispatch
.apm/agents/feat-specifier.agent.md         # Last step section; Report file sentence
.apm/agents/feat-planner.agent.md           # same
.apm/agents/feat-tasker.agent.md            # same
.apm/agents/feat-implementer.agent.md       # same
.apm/agents/feat-shipper.agent.md           # same
.apm/agents/feat-bug-assessor.agent.md      # same
.apm/skills/feat/references/harness.md      # Step script: who calls, slip fallback, done: check, agent ids, chores; continue: <role>
.apm/skills/feat/SKILL.md                   # flag: and brief chores; phase 7 review move; final message after the done: check
.apm/skills/fix/SKILL.md                    # flag: chore; phase 1 and 4 timing; final message after the done: check
docs/workflow.md                            # /feat Roles; "A small run, call by call"; /fix Roles bullet and phase 1
docs/design.md                              # who calls step.sh
docs/diagrams/gates.d2                      # agents -> step at sequential boundaries
docs/img/gates.svg                          # its render
tests/step/run.sh                           # new cases; agent=<id> removed; full_go
tests/step/expected/*.out, *.log            # regenerated
tests/step/fixtures/logs/full-*.md          # Agents: lines
tests/state/run.sh                          # record case (inline checks, as the inputs case)
```

**Structure Decision**: no new file in the repo besides goldens; the
record is a runtime file under the already-ignored `reports/`, written by
state.sh like the inputs files.

## Design

Details: [contracts/step-cli.md](contracts/step-cli.md),
[contracts/prompts.md](contracts/prompts.md), [data-model.md](data-model.md).

- **Block keys (FR-005; R4)**: `bline <token> <word>…` prints `step
  script:` and `boundary:` as the block's last keys and the call line
  after the blocks, replacing the `out_call 22 'boundary:'` of every
  agent-run spawn (specifier, planner, tasker, implementer in story, fix
  and bug mode, shipper, bug assessor; their reformat spawns). Reviewer
  and rebase-mode spawns keep today's call line only. Boundaries 2, 3 and
  5 lose `agent=<id>`.
- **Decision record (FR-008, FR-016, FR-023; R1, R2)**: `print_all`
  splits into `render` and the print; `commit` ends, after the `@SNAP@`
  substitution and before `CM_SET=()`, with `render` and `record_write`,
  so a failed write goes through `undo_sets` like any commit failure.
  `record_write` passes the `call:`/`sums:` pairs (this call's, after the
  previous record's when that record's output was `reformat`), `output:`
  and the lines to `state.sh record`, which writes them after its fixed
  line with `report-path`'s guard (`reports_dir`, `reports_make`: unsafe
  names and symlinks refused, a missing `reports/` created with its `*`
  `.gitignore`) and `write_file`. Never for `size`, `refused:`, errors.
- **State hash (FR-022; R8)**: `load_state` takes the state file's
  `git hash-object` before `read_state`; `commit` hashes it again before
  its first write and dies `the state file changed since step.sh read it`
  when they differ, having written nothing.
- **Acceptance (FR-008–FR-010; R3)**: for a call with no `answer:` word,
  first a re-print (one of the record's `call:` lines equals the words and
  each report of that call hashes to its `sums:` value: print the stored
  output, exit 0, write nothing), then the open check (the issued line's token, and every report path of
  the call among its words), else `step: error`; no record: today's
  `Current phase` check. Answer calls keep `open_gate`.
- **Agent ids (FR-011, FR-012; R5)**: `agent=<role>:<id>`, `/feat` only,
  on answer and reviewer batch calls, written before the decision prints;
  elsewhere a usage line. A reformat spawn of the specifier, planner or
  tasker prints `continue: <role>` with no lookup; the gate 4 planner
  amend keeps today's lookup (the id, else `fresh`).
- **Agents (FR-001, FR-003, FR-004, FR-006; R7)**: the Last step section
  of [prompts.md](contracts/prompts.md#agents), before each format block,
  run only when the request gave `boundary:`; the block is only ever a
  copy of that Bash result.
- **Coordinators (FR-002, FR-007, FR-010, FR-013, FR-014, FR-015, FR-018;
  R6, R8, R9, R13)**: harness.md reads the block as its own output,
  defines when it parses (the last line's key followed by a tab) and the
  slip fallback, the `done:` check, the latest hand-back rule, the
  `agent=` words, `continue: <role>` and the chores; `/feat` and `/fix`
  move the `flag:` line, the brief's deletion or log line and the review
  move to their new timing. Reviewer batches, answers, moves, `rebase` and
  the `done:` check keep the coordinator's call.
- **Docs (FR-019; R12)**: workflow.md's `/feat` role paragraph, a
  call-by-call walk-through of a small run, and the `/fix` Roles bullet
  and phase 1 text; design.md's sentence; gates.d2 and its render.
  chain.d2 unchanged: no phase or gate changes.
- **Tests (FR-020, FR-021; R11)**: the 16 cases of
  [step-cli.md](contracts/step-cli.md#tests) and the `record` case in
  tests/state, goldens regenerated and reviewed, the existing
  `agent=<id>` uses removed.

Order: state.sh's `record` and its tests/state case, then step.sh and
tests/step (the contract the prompts rely on),
then the agents, harness.md and the two skills in the same commit as
step.sh (CLAUDE.md: the format and its readers change together), then the
docs and the diagram.

## Complexity Tracking

None: the Constitution Check has no violation.
