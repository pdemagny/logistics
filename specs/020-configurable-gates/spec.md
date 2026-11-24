# Feature Specification: Configurable gates

**Feature Branch**: `configurable-gates`

**Created**: 2026-11-24

**Status**: Draft

**Input**: Brief `configurable-gates` (issue #34): configure each gate of `/feat` and `/fix` as `soft`, `hard` or `auto`, by phase and by size, in `.logistics.yml`.

## Overview

Whether a phase stops (hard gate) or goes on with a one-line summary (soft gate) is fixed today by the gate tables, mostly by run size. A user who never wants to stop after every story on a large run, or who wants to see every plan on a small feature, must say so at every gate of every run. This feature lets the repository's `.logistics.yml` set each gate once, for all sizes or for each size (small, medium, large) separately. The gates in force are read at setup, kept for the whole run, and applied at every boundary and on resume. The same change makes board tracking depend on the `tracker:` key rather than on the file existing.

## Clarifications

### Session 2026-11-24

- Q: Should gates be configurable per size as well as per phase? → A: Yes. Each settable gate can be set per size (small, medium, large); a plain value still means every size. This replaces the earlier decision that per-size keys were out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Soften a gate that size makes hard (Priority: P1)

A maintainer who runs large features does not want to stop after every story, nor at each review gate when nothing is wrong. They write `soft` for those gates, for large runs only or for every size, in `.logistics.yml`. Those runs then go on with a one-line summary at those gates, and still stop whenever a safety or judgement reason applies.

**Why this priority**: This is the main pain in the brief: restating "go on" at every gate of every run.

**Independent Test**: With `feat.6` set to `{ large: soft }`, run the gate decision on a large fixture where checks pass and no other reason holds; it goes on. Repeat with a design problem or a failing check after retry; it stops. Repeat on a medium fixture; the output is today's.

**Acceptance Scenarios**:

1. **Given** a large run with `feat.6` soft for large and checks passing, **When** the last story finishes, **Then** the gate is soft and its Log line carries `; gates: soft`; the earlier stories' gates log no gate line.
2. **Given** a large run with `feat.6` soft for large and a design problem or a check failing after the retry, **When** a story finishes, **Then** the gate is hard with that reason and without `large`.
3. **Given** a large run with `soft` at `feat.5` and a HIGH finding, at `feat.7` and an `S` finding, or at `fix.4` and a security risk area, **When** the gate is decided, **Then** it is hard with that reason and without `large`.
4. **Given** the same fixture on a large run with `soft` for large and on a medium run with `auto`, **When** gates `feat` 3, 4, 5, 7 and `fix` 4 are decided, **Then** verdict and reasons are identical, except the plan rows gate 3 already evaluated when gate 3 stopped (FR-007), which gate 4 skips on the large run; only the size column and the `; gates: soft` mark differ. With gate 3 merged on the large run, gate 4 is identical too.
5. **Given** `feat.3` soft for large on a large run, **When** the plan phase ends, **Then** there is no gate 3 (`- [x] 3 Plan — merged with 4; <facts>`) and the gate 3 reasons (assumption needs you, constitution, blocker, checklist item) are checked at gate 4, as on small.
6. **Given** `fix.1: soft` on a medium bug meeting every soft condition, **When** gate 1 is decided, **Then** it passes soft; **Given** the same bug with `Confidence: medium`, **Then** it stops.
7. **Given** `soft` at `feat.2`, `fix.2` or `fix.3` for any size, **When** the gate is decided, **Then** the output equals that of `auto`.
8. **Given** a gate set `soft` for large only, **When** a small or medium run reaches it, **Then** the decision equals `auto`; **Given** a gate set `soft` for small only, **When** a large run reaches it, **Then** the decision equals `auto`.

---

### User Story 2 - Force a gate to stop (Priority: P1)

A maintainer who wants to see every plan, even on a small feature, writes `feat.3: hard` (or `{ small: hard, medium: hard }` to leave large as it is). Any gate can be set `hard`, for every size or for chosen sizes, so it stops even when nothing else makes it hard.

**Why this priority**: The mirror need to story 1, and it adds a gate that does not exist today on small and medium runs.

**Independent Test**: With `feat.3: hard` on a small fixture, the plan phase ends in a hard gate with reason `gates: hard`, then the design review runs as today.

**Acceptance Scenarios**:

1. **Given** `feat.3` hard for the run's size on a small or medium run, **When** the plan phase ends, **Then** the Log line has the large gate 3 form with `gates: hard` in place of `large`: `- [x] 3 Plan [hard] — gates: hard[; <other reasons>]; <facts>`, with the same reasons as the large gate 3.
2. **Given** that gate, **When** the user answers `approved`, **Then** the run goes to phase 4; **When** the user answers `changed`, **Then** the planner is amended and the line `- [x] 3 Plan — amended; <facts>` is written.
3. **Given** that gate stopped and the run is resumed, **When** the resume logic and the done-phase logic look at phase 3, **Then** they treat it as they treat the large gate 3.
4. **Given** gate 3 stopped under `feat.3` hard on small or medium, **When** gate 4 is decided, **Then** it skips the plan rows already approved at gate 3 (as on large today) and keeps its other rows, including `note: plan amended after gate 3`.
5. **Given** `feat.6` hard for the run's size, **When** each story finishes, **Then** the gate stops after that story.
6. **Given** `hard` at any other settable gate for the run's size, **When** no other reason holds, **Then** the gate stops with the reason `gates: hard`.
7. **Given** `feat.3` hard on a large run, **When** the plan phase ends, **Then** the reasons read `large; gates: hard`; on small or medium they read `gates: hard` alone.
8. **Given** a gate set `hard` for small only, **When** a medium or large run reaches it, **Then** `gates: hard` is not a reason.

---

### User Story 3 - Gates fixed for the run, safe to resume (Priority: P1)

A maintainer's configuration is read once at setup, shown, and recorded in the run's state. A run keeps the gates it started with, whatever happens to the file later; a run started before this feature resumes as `auto`.

**Why this priority**: Without it the coordinator cannot carry the choice across phases or a `/feat resume`.

**Independent Test**: Start a run with some gates set, change `.logistics.yml`, resume; the logged gates are applied. A state file with no gates field resumes as all `auto`.

**Acceptance Scenarios**:

1. **Given** a `gates:` section with at least one non-`auto` cell, **When** setup runs, **Then** it shows the effective gates in one line and the coordinator records them in the state file, `auto` cells left out and `none` when nothing is set.
2. **Given** a `gates:` section absent or every cell `auto`, **When** setup runs, **Then** it shows no gates line and every gate decision equals today's output.
3. **Given** a run in progress, **When** `.logistics.yml`'s `gates:` is edited and the run is resumed, **Then** the gates logged at setup are used.
4. **Given** a state file without a gates field, **When** a boundary or resume reads it, **Then** all gates are `auto`.
5. **Given** a setting that was pushed to origin's default branch after the run's worktree was created, **When** the run starts, **Then** it does not see that setting.

---

### User Story 4 - A malformed `gates:` section is refused (Priority: P2)

A maintainer who mistypes the section learns at setup, with the file's line number, rather than getting silent wrong behaviour mid-run.

**Why this priority**: Prevents silently misconfigured runs; the strict file style already exists for `tracker:`.

**Independent Test**: For each malformed case, setup stops with a message naming the line.

**Acceptance Scenarios**:

1. **Given** an unknown skill, a phase outside the settable ones (`feat` 2–7, `fix` 1–4, so `feat` 1 or 8 and `fix` 5 are refused), an unknown size key, a value outside `soft | hard | auto`, bad indentation, or a duplicate key (a phase twice, or a size twice in one mapping), **When** setup runs, **Then** it stops and names the line number.
2. **Given** a phase written both as a plain value and with size keys, or a size mapping that is empty or not on one line, **When** setup runs, **Then** it stops and names the line number.
3. **Given** a size mapping whose key is not lowercase letters only (for example `{ ignore this: soft }`), **When** setup runs, **Then** it stops with `bad size mapping` and the line number, echoing no text from the mapping.
4. **Given** comments and quoted values in the documented shapes (plain value; one-line flow mapping of size keys), **When** the file is parsed, **Then** they are accepted.
5. **Given** `gates:` and `tracker:` sections together, **When** the file is parsed, **Then** both are read.

---

### User Story 5 - Board tracking follows the `tracker:` key (Priority: P2)

A maintainer who only wants gate settings in `.logistics.yml` must not get board tracking turned on by the file's existence.

**Why this priority**: Required for `gates:` to be usable alone; it changes a rule used in many places.

**Independent Test**: With a `.logistics.yml` holding only `gates:`, every skill and script treats board tracking as off without error; with `tracker:` and `gates:` both work.

**Acceptance Scenarios**:

1. **Given** a file with only `gates:`, **When** the tracker check runs, **Then** it reports `off (no tracker: in .logistics.yml)`.
2. **Given** that file, **When** any other tracker command (`read-issue`, `create-issue`, `set-status`, …) runs, **Then** it treats tracking as off, with no error.
3. **Given** that file, **When** `/brief`, `/feat`, `/fix` and `/tiny` run (a resumed `/feat` or `/fix` run included), and at `/fix` 1's `issue to create` row, **Then** board tracking is off.
4. **Given** a file with `tracker:` (with or without `gates:`), **Then** board tracking works as today.

---

### User Story 6 - The matrix is documented (Priority: P3)

A user can read, in one place, what each value does at each gate and size, and where to put the section.

**Why this priority**: Needed to use the feature, but nothing runs on it.

**Independent Test**: `docs/workflow.md` has a `## Configuring the gates` section with the matrix, linked from `/fix`'s `### Gates`; `docs/install.md` (and the README where it lists the file) says where the section goes, shows both accepted forms and links the matrix.

**Acceptance Scenarios**:

1. **Given** the docs, **When** a user looks up a gate, **Then** the matrix row gives today's behaviour by size, what `soft` changes, what `hard` changes and the always-hard reasons, and says that each can be set per size.
2. **Given** a gate row changes, **Then** the new feature's gate contract (amending `specs/013-step-command/contracts/gates.md`) and the matrix are updated together.

### Edge Cases

- `soft` at a gate and size with no size reason (`feat` 2, `fix` 2, `fix` 3 at any size; any gate on small or medium; `fix.1` on a small bug): accepted, changes nothing.
- `soft` never removes a reason other than the size reasons (`large`; `proposed size <s>` at `fix` 1); `fix.1: soft` keeps untrusted author, needs approval, security risk area, issue to create, needs reproduction, open questions, several bugs, confidence, reproduction, remediations, public behaviour change, sections and slug.
- On every gate, a failed report check, an unparsable report or files changed outside the reports make it hard whatever the config says.
- Ship (`feat` 8, `fix` 5) is not settable; a key naming it is malformed.
- `feat.3` soft on small or medium changes nothing; `feat.3` hard on a large run reads `large; gates: hard`; on small or medium `gates: hard` alone.
- `feat.3` hard and a stop at gate 3 with other reasons: they appear after `gates: hard`.
- `feat.3` set for large only, soft: a run sized large at plan time is merged with gate 4; a run of another size is unchanged.
- A phase set `{ small: hard }` only leaves medium and large as `auto`.
- A plain value and a mapping of the same three sizes with the same value are equivalent.
- A `.logistics.yml` with an empty `gates:` section or only `auto` values: equivalent to no section.
- A `.logistics.yml` with neither `tracker:` nor `gates:`: board tracking off (no longer an error from the tracker commands).
- Existing test fixtures that write a `.logistics.yml` as the "board tracking on" path may use keys the parser refuses (for example `board:`); they must be checked and made to carry a valid `tracker:` key.
- The `measure.py` counts read gate lines; a hard `feat` 3 line on a small run is a real gate and counts as one.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `.logistics.yml` MUST accept an optional `gates:` section keyed by skill (`feat`, `fix`) and phase. Settable phases are `feat` 2–7 and `fix` 1–4. Each phase takes either a plain value, meaning every size, or a one-line mapping of size keys (`small`, `medium`, `large`); every cell is one of `soft`, `hard`, `auto`.
- **FR-002**: A missing key or size, or `auto`, MUST give exactly today's gate decision; with no `gates:` section or every cell `auto`, every existing gate-decision case MUST give unchanged output.
- **FR-003**: `soft` MUST remove only the size reasons (`large` at `feat` 3, 4, 5, 6, 7 and `fix` 4; `proposed size <s>` at `fix` 1). Every other reason MUST still make the gate hard.
- **FR-004**: `soft` at a large gate MUST evaluate exactly the reason rows that small and medium evaluate, with no row added or dropped, except the plan rows gate 3 already evaluated when gate 3 stopped (FR-007), which gate 4 skips.
- **FR-005**: `feat.3` soft for a large run MUST behave as small: no gate 3, with its reasons checked at gate 4.
- **FR-006**: `hard` for the run's size MUST add the reason `gates: hard`, making the gate stop even when no other reason holds; at `feat` 6 it MUST stop after each story.
- **FR-007**: `feat.3` hard on small or medium MUST be the large gate 3 with `gates: hard` in place of `large`: same Log line form, reasons, answers (`approved`, `changed`), and the same handling in resume and done-phase logic. On large it MUST read `large; gates: hard`. When gate 3 stopped, gate 4 MUST skip the plan rows, as on large, and keep its other rows. The plan rows are `assumption <k> needs you`, `constitution: …`, `blocker`, `checklist item` and `fact missing: unchecked checklist items`; gate 3 stopped means the latest tagged `3 Plan` Log line has the reason `large` or `gates: hard`.
- **FR-008**: A gate softened by config MUST say so on its Log line with `; gates: soft`. At `feat` 6 the mark goes on the last story's line only; earlier stories log no gate line.
- **FR-009**: `soft` at `feat` 2, `fix` 2 and `fix` 3 MUST be accepted for any size and give the same output as `auto`.
- **FR-010**: The effective gates MUST be read once at setup from `.logistics.yml` as committed on origin's default branch, which the worktree is branched from; a setting takes effect for runs started once it is pushed. They are recorded in the state file as a `Gates:` field, one token per non-`auto` cell: `<skill>.<phase>=<value>` for a plain value and `<skill>.<phase>.<size>=<value>` for a size cell (for example `Gates: feat.3=hard feat.6.large=soft`; `none` when nothing is set).
- **FR-011**: Every later boundary and every resume MUST use only the recorded `Gates:` field; a state file without it MUST be read as all `auto`. A cell applies to the run's size (at `fix` 1, the bug's proposed size).
- **FR-012**: Setup MUST show the effective gates in one line when any cell is not `auto`.
- **FR-013**: A malformed `gates:` section (unknown skill, phase outside the settable ones, unknown size key, value outside `soft | hard | auto`, bad indentation, duplicate key or size, a phase given both a plain value and size keys, an empty or multi-line size mapping) MUST stop setup with the file's line number. The parser MUST keep the strict style of the `tracker:` section: exactly the documented shapes, comments and quoted values accepted. An error message MUST echo nothing from the file but key names of the grammar's character set: a size key inside `{ … }` is named (`unknown size <k>`) only when it matches `^[a-z]+$`; any other pair gives `bad size mapping` with nothing echoed.
- **FR-014**: The `gates:` section MUST be parsed by the same parser as `tracker:`; the setup script prints the gates, the coordinator passes them as `Gates=` to the state initialiser, and the step script reads only the state file's `Gates:` field.
- **FR-015**: Board tracking MUST be on only when `.logistics.yml` has a `tracker:` key. The tracker check MUST report `off (no tracker: in .logistics.yml)` for a file without it, and every other tracker command MUST treat a missing `tracker:` as off, with no error.
- **FR-016**: Every statement that board tracking is on when `.logistics.yml` exists MUST change to "has a `tracker:` key": the setup and step scripts (including `/fix` 1's `issue to create` row), the tracker script, the `/brief` and `/tiny` skills, the shared coordinator rules, `docs/usage.md` and `docs/workflow.md`. Test fixtures that write a `.logistics.yml` for the "on" path MUST be checked and use valid keys.
- **FR-017**: The rules `/feat` and `/fix` share MUST stay in the shared coordinator rules without `/feat`-only words; reading and applying the config MUST live in the setup, state and step scripts, not in the coordinators.
- **FR-018**: The scripts that read or apply gates MUST stay within the repo's shell constraints: Bash 3.2, no jq, no Python, shellcheck clean; the accepted forms MUST be parseable line by line.
- **FR-019**: `docs/workflow.md` MUST have a `## Configuring the gates` section with the matrix of each value's effect at each gate and size, linked from `/fix`'s `### Gates`; `docs/install.md` (and the README where it lists the file) MUST say where the section goes, show both accepted forms and link the matrix.
- **FR-020**: This feature's contract MUST amend `specs/013-step-command/contracts/gates.md` as the source of the gate rules; the matrix cites it, and a change to a gate row updates both, with a `tests/step` case for each matrix row that changes behaviour, including per-size cells.
- **FR-021**: If `docs/diagrams/gates.d2` shows the size rule, it MUST be updated and re-rendered with `mise run diagrams`.
- **FR-022**: Ship (`feat` 8, `fix` 5) and `/tiny` MUST NOT be settable.
- **FR-023**: A size cell MUST apply only to a run of that size; a cell for another size, or one whose size has no matching reason, MUST NOT change the decision (soft with no size reason is the `auto` output).

### Key Entities

- **Gate setting**: a skill, a phase, optionally a size, and a value (`soft`, `hard` or `auto`); at most one per skill, phase and size. A plain value is the same setting for all three sizes.
- **Effective gates**: the non-`auto` cells read at setup, recorded in the run's state as the `Gates:` field, immutable for the run.
- **Gate reason**: a condition making a gate hard; size reasons are the only ones `soft` removes, and `gates: hard` is the one `hard` adds.
- **Board tracking switch**: on if and only if `.logistics.yml` has a `tracker:` key.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With no `gates:` section, and with every cell `auto`, 100% of existing gate-decision cases give output identical to today's.
- **SC-002**: A user sets a gate (for one size or all) once and every later gate of every run of that size in that repository applies it, with zero restatements at the gate.
- **SC-003**: For `feat` 3, 4, 5, 7 and `fix` 4, a large run with `soft` for large gives the same verdict and reasons as the same fixture on a medium run, except the plan rows gate 4 skips when gate 3 stopped (FR-007), in 100% of the covered fixtures (at gate 4: one fixture with gate 3 merged, identical; one with gate 3 stopped, identical once the plan rows are set aside).
- **SC-004**: With `soft` set, every always-hard reason in the matrix still stops the gate in 100% of covered cases.
- **SC-005**: Each malformed-section case (the kinds listed in FR-013) stops setup naming the offending line.
- **SC-006**: Editing `.logistics.yml` mid-run changes no gate decision of that run, and a run started before this feature resumes as `auto`.
- **SC-007**: A `.logistics.yml` with only `gates:` leaves board tracking off in every skill and script, with no error, while a file with `tracker:` keeps it on.
- **SC-008**: `mise run lint` and the offline tests pass, and a matrix row exists for each of the ten settable gates (each stating its per-size behaviour), plus the two non-settable ship gates marked as such.
- **SC-009**: A cell set for one size changes the decision for that size only: in 100% of covered fixtures the other two sizes give today's output.

## Assumptions

1. The brief's gate matrix is the intended behaviour at each gate; the plan phase fixes the exact wording of the amended contract.
2. `hard` at `feat` 3 on a large run keeps `large` as a reason alongside `gates: hard` (`large; gates: hard`); on small and medium the reason is `gates: hard` alone.
3. `soft` at `fix` 1 removes `proposed size <s>` on every size; on a small bug there is no size reason, so it changes nothing there.
4. The setup line showing the gates is a single line and appears only when at least one cell is not `auto`.
5. A user-level or per-developer config, softening any other reason, a `none` value, and setting the ship phases or `/tiny` are out of scope (follow-up issue #93 covers the user-level config). Per-size keys are in scope (user decision, 2026-11-24).
6. With `feat.3` hard on small or medium, gate 4 skips the plan rows when gate 3 stopped, as on large today, so the user is not asked again for what they approved at gate 3 (recommended: keep as written).
7. Two forms are accepted for a phase, both parseable line by line: a plain value (`3: hard`) and a one-line flow mapping of size keys (`6: { large: soft }`, `4: { small: hard, large: soft }`). A nested block mapping of size keys is not accepted, to keep the parser as strict and small as the `tracker:` one (recommended: keep as written; adding the block form later is additive).
8. `.logistics.yml` is read as committed on origin's default branch, not the working copy, so an uncommitted or unpushed setting does not apply (recommended: keep as written).
