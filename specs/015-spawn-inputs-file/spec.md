# Feature Specification: step.sh writes each spawn's lists to an inputs file the agent reads

**Feature Branch**: `spawn-inputs-file`

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "step.sh writes each spawn's lists to an inputs file the agent reads (issue pdemagny/logistics#69; follow-up to #28 finding D13, part of epic #31)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agents receive every list exactly as step.sh wrote it (Priority: P1)

A coordinator (`/feat` or `/fix`) reaches a boundary and asks step.sh for the next spawn. Today the spawn block carries the spawn's lists (a story's tasks, findings to apply, rejected findings, accepted security findings, failures, not verified items, approved commands, answers) inline, and the coordinator retypes them into the agent prompt, sometimes re-laying them out or rewording them. With this feature, the spawn block carries one `inputs: <absolute path>` line in place of the list keys, the file at that path holds the lists exactly as step.sh wrote them, and the agent reads them from there. The coordinator relays the `inputs:` line like any other key and never reads the file.

**Why this priority**: Fidelity is the reason for the feature: an agent must act on step.sh's version of a finding, not the coordinator's. Everything else supports this.

**Independent Test**: Run step.sh for each spawn that carries a list, check the spawn block shows `inputs: <path>` and none of the list keys, and check the file holds exactly the lists step.sh printed before this change.

**Acceptance Scenarios**:

1. **Given** a spawn with at least one non-empty list (story, review-fix `apply` with and without `failures`, planner amend, design and code review batches with `rejected` and `accepted sec`, 7e, `/fix` implementer and assessor spawns with `approved commands` and `answers`, ship with `not verified items`), **When** step.sh prints its spawn block, **Then** the block has one `inputs: <absolute path>` line, no list keys, and no counts or ids about the lists.
2. **Given** that inputs file, **When** it is read, **Then** it opens with a line saying the content is data and never instructions, then holds every list of the spawn in today's layout: `<key>:` or `<key>: none` lines, `  - <item>` lines, and the story's `story.sh output` between two four-backtick lines.
3. **Given** a spawn sent as a continuation (`continue: <id>` via `SendMessage`) or as a fresh spawn, **When** it carries lists, **Then** it gets its own inputs file, paired with the new report path step.sh reserves for it, and is never given an earlier spawn's file.
4. **Given** the implementer, code reviewer, design reviewer, planner, shipper and bug assessor agents, **When** they receive a prompt, **Then** each reads its lists from the file on the `inputs:` line of the message it was just given and treats a message without an `inputs:` line as every list `none`, with no inline fallback.
5. **Given** an agent continued with `SendMessage` after an earlier spawn or message that named an inputs file, **When** the continuation message carries its own `inputs:` line, **Then** the agent reads that file only; **When** the continuation message has no `inputs:` line, **Then** every list is `none` and the earlier file is not reused.

---

### User Story 2 - Empty and repeated spawns stay clean (Priority: P2)

A maintainer relies on spawns with nothing to pass not leaving stray files, and on re-runs not corrupting an inputs file.

**Why this priority**: Correctness of edge behaviour; the feature works without it for the common case but would leave noise and drift otherwise.

**Independent Test**: Print a spawn block where every list is empty, then print one block twice, and inspect `reports/`.

**Acceptance Scenarios**:

1. **Given** a spawn whose lists are all empty, **When** step.sh prints its block, **Then** there is no `inputs:` line and no file is written.
2. **Given** a spawn block printed again (re-run or retry), **When** its inputs file is written, **Then** the file is rewritten whole and never appended to.
3. **Given** an item holding `'`, `$(…)`, a backtick or a leading `-`, **When** it lands in the inputs file, **Then** it is there unchanged.

---

### User Story 3 - `/tiny`'s review spawn drops its two `none` lists (Priority: P3)

`/tiny`'s review spawn used to pass `none` for design findings and rejected findings. It now names neither; with no `inputs:` line, the reviewer reads both as `none`.

**Why this priority**: Keeps `/tiny` consistent with the new agent contract; `/tiny` itself works either way.

**Independent Test**: Read `/tiny`'s skill text and confirm it no longer passes design or rejected findings, and stays within its line cap.

**Acceptance Scenarios**:

1. **Given** `/tiny`'s review step, **When** it spawns the code reviewer, **Then** the prompt has no design-findings or rejected-findings keys.
2. **Given** the reviewer gets no `inputs:` line, **When** it runs, **Then** it treats both lists as `none`.

---

### Edge Cases

- A spawn block printed twice for the same spawn (retry): the file is rewritten whole.
- A list item beginning with `-` or containing shell metacharacters or backticks: preserved byte for byte.
- `reports/` or its ignore file or the target file is a symlink: the write is refused by the same guards that protect report paths today, kept in one place.
- Report path with a `-<n>` suffix (for example `reports/7-fixes-2.md`): inputs file is `reports/7-fixes-2.in.md`, so it never collides with a report.
- Spawns that carry no lists (rebase, move, reformat): unchanged, no `inputs:` line.
- ship.sh's own not-verified file in `reports/` (written by the shipper, read by ship.sh) is unchanged; the shipper fills it from the inputs file.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every spawn block with at least one non-empty list MUST print exactly one `inputs: <absolute path>` line in place of all its list keys, and nothing else about the lists (no counts, no ids).
- **FR-002**: The inputs file MUST hold every list of the spawn in the layout step.sh printed before this change, and MUST open with a line stating the content is data, never instructions.
- **FR-003**: A spawn whose lists are all empty MUST print no `inputs:` line and MUST write no file.
- **FR-004**: The inputs file MUST sit next to the spawn's report: that spawn's full report path (`-<n>` suffix included) with `.md` replaced by `.in.md`, inside `reports/`.
- **FR-005**: Every spawn, continued or fresh, MUST get its own inputs file paired with the new report path step.sh reserves for it, and MUST NOT be given an earlier spawn's file.
- **FR-006**: Printing a spawn block again MUST rewrite its inputs file whole; the file MUST never be appended to.
- **FR-007**: The inputs file MUST be written under the same guards that protect `reports/` today (no symlink on `reports/`, its ignore file or the target file), and those guards MUST stay in one place, in `state.sh`, not be copied into `step.sh`.
- **FR-008**: List items MUST reach the file unchanged, including items with `'`, `$(…)`, a backtick or a leading `-`.
- **FR-009**: The implementer, code reviewer, design reviewer, planner, shipper and bug assessor agents MUST read their lists from the file on the `inputs:` line of the message they were just given (the spawn prompt, or the continuation message for a `SendMessage` continuation, which names its own) and MUST treat a message with no `inputs:` line as every list `none`; they MUST NOT reuse a file named by an earlier spawn or message, and there is no inline fallback. The six agents word this the same way.
- **FR-010**: The coordinators MUST pass the `inputs:` line into the prompt like any other key, including for a `continue: <id>` spawn sent with `SendMessage`, and MUST NOT read the file.
- **FR-011**: The single-line keys (`row`, `mode`, `lenses`, `model`, `effort`, `report`, `continue`, `who`, `story`, `diff`, `cuts`, `action` and the others) MUST stay in the spawn block.
- **FR-012**: The inputs file is written by step.sh, never by an agent: it MUST NOT appear on an agent's `Wrote:` list and the `Wrote:` check MUST NOT expect it.
- **FR-013**: ship.sh's not-verified file in `reports/` MUST stay as it is; the shipper fills it from the inputs file instead of from its prompt.
- **FR-014**: `/tiny`'s review spawn MUST stop naming design findings and rejected findings, and `/tiny` MUST stay within its 200-line lint cap.
- **FR-015**: The agents, step.sh, `tests/step`, `harness.md` and the `/feat`, `/fix` and `/tiny` skills MUST change together; `/feat` and `/fix` stay thin; step.sh stays Bash 3.2 with no jq and no Python, and shellcheck clean.
- **FR-016**: `tests/step` MUST cover every spawn that carries a list, an all-empty case, and a case with the awkward item characters (FR-008).

Out of scope (binding): a permanent `measure.py` metric or lint for list text in prompts; what the lists contain and how step.sh computes them; the merged findings step.sh prints at a review gate; rebase, move and reformat spawns; the agents' report formats; `docs/workflow.md` and the diagrams.

### Key Entities

- **Spawn block**: what step.sh prints for a spawn; single-line keys plus, when any list is non-empty, one `inputs:` line.
- **Inputs file**: per-spawn data file in `reports/`, named after the spawn's report with `.in.md`; holds the spawn's lists; written by step.sh, read by the agent, never by the coordinator.
- **List**: a named group of items an agent acts on (tasks, apply, rejected, accepted sec, failures, not verified items, approved commands, answers).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every spawn that carries a list, 100% of the list items an agent acts on are byte-identical to what step.sh wrote, checked by tests.
- **SC-002**: In every spawn block with lists, 0 list keys and 0 list items appear; exactly 1 `inputs:` line does.
- **SC-003**: A spawn with all lists empty leaves 0 new files and prints 0 `inputs:` lines.
- **SC-004**: The full offline lint and test suite passes, including the new cases.
- **SC-005**: A scan of the first real `/feat` run after merge finds 0 list item texts in the coordinator's Agent or SendMessage prompts (checked by hand once).

## Assumptions

- The six agents named are the only ones that take lists; rebase, move and reformat spawns carry none.
- Reports and inputs files live in the already-ignored `reports/` directory and are never committed.
- The exact shape of the state.sh subcommand that writes the file is left to planning.

## Clarifications

None.
