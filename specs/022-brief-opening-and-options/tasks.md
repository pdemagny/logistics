# Tasks: /brief opens an issue run with where it stands, and lays real tradeoffs out as a table

**Input**: Design documents from `specs/022-brief-opening-and-options/` (spec.md, plan.md, research.md, data-model.md, contracts/interview-output.md, quickstart.md)

**Tests**: None requested. This is prompt text with no offline test; checks are `mise run lint`, `mise run test:apm` and the manual runs in quickstart.md.

**Organization**: By user story. Edit the repo source only (`.apm/skills/brief/SKILL.md`, never `~/.claude/skills/brief/`). Never edit between `sizes-start`/`sizes-end` markers, never add a line starting with `|` to SKILL.md, and touch nothing outside the three files below.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 Read `.apm/skills/brief/SKILL.md` step 1 (the "Invoke `interview-me`" paragraph near lines 57-61 and the "From an issue" paragraph near lines 78-85), `specs/022-brief-opening-and-options/contracts/interview-output.md` and `specs/022-brief-opening-and-options/research.md` to fix the exact insertion points and wording

## Phase 2: Foundational

None: the three files are independent edits and no shared prerequisite blocks them.

## Phase 3: User Story 1 - Opening briefing on an issue run (Priority: P1) 🎯 MVP

**Goal**: The first interview message of an issue run opens with "Where it stands" (FR-001 to FR-005).

**Independent Test**: Run `/brief #N` and check the first interview message opens with the briefing and ends with the first question, in one message; plain idea, map row and tiny brief starts show none.

- [x] T002 [US1] In `.apm/skills/brief/SKILL.md`, append to the end of the "From an issue" paragraph (after the board tracking read) the passage from plan.md "SKILL.md, From an issue paragraph": begins "Hold the first interview message, not before"; preconditions are issue read (any way, pasted included), code and docs read, `/tiny` offer declined or not applicable; four bullets The ask, Today (file:line, what is missing), Already decided, Open, one or two lines each; empty bullets left out; paraphrase, neither a copy of the body nor a follow of it; hypothesis, confidence and first question follow in the same message (one stop). Leave the capability-map and tiny-brief paragraphs untouched.

**Checkpoint**: Issue starts produce the briefing; non-issue starts are unchanged.

## Phase 4: User Story 2 - Tradeoff table for a choice between roads (Priority: P2)

**Goal**: A real choice between roads shows one options-by-criteria table before the guess (FR-006, FR-007, FR-011).

**Independent Test**: A question with 3 viable options shows one table before GUESS; a yes/no question shows none.

- [x] T003 [US2] In `.apm/skills/brief/SKILL.md`, append one sentence to the "Invoke `interview-me`" paragraph (after "Skip its step 6 ..."): trigger (at least 3 viable options the interviewer would defend, or 2 differing on at least 2 criteria the user would weigh), shape (one markdown table between the question and the guess, a row per option, a column per separating criterion, recommended row marked, then the guess and strongest counter-argument), exceptions (yes/no, "keep as written", single-road get none). Describe the table in prose only: add no line starting with `|`.

**Checkpoint**: Both skill changes in place; skill growth about 15 lines or fewer (SC-004).

## Phase 5: User Story 3 - Docs describe both behaviours (Priority: P3)

**Goal**: The workflow and usage docs describe both behaviours in one or two sentences each (FR-009).

**Independent Test**: Read `docs/workflow.md` "### 1 Brief (`/brief`)" and `docs/usage.md` "## 1. Brief" and find both behaviours.

- [x] T004 [P] [US3] In `docs/workflow.md` under "### 1 Brief (`/brief`)": add one sentence after "Reads the code ... constraints." on the table (trigger, options by criteria, recommended row marked, before the guess, exceptions), and one sentence in the "From an issue ..." sentence after "records it in the brief" on the "Where it stands" opening (ask, today with file:line, decided, open; empty bullets left out; after the `/tiny` offer; first question in the same message). Do not touch any `sizes-start`/`sizes-end` region.
- [x] T005 [P] [US3] In `docs/usage.md` "## 1. Brief": add one user-facing sentence after "each with its guess attached." on the table (same trigger, shape and exceptions), and one sentence in the "From a GitHub issue" paragraph that Claude reads the code and docs the issue touches and opens with "Where it stands" (the ask, today with file:line, what is decided, what is open) followed by its first question in the same message.

**Checkpoint**: Docs match the skill.

## Phase 6: Polish and verification

- [x] T006 Run `mise run lint` and `mise run test:apm` from the worktree root and fix any failure in the three edited files
- [x] T007 Run `/usr/bin/git diff --stat origin/main` and `/usr/bin/git diff origin/main -- .apm/skills/brief/SKILL.md`: confirm only `.apm/skills/brief/SKILL.md`, `docs/workflow.md`, `docs/usage.md` and `specs/022-brief-opening-and-options/` changed, SKILL.md gained about 15 lines or fewer, none starting with `|`, nothing inside the `brief-review` markers (SC-004, SC-005, FR-010, FR-011)
- [x] T008 Walk the static checks and manual runs in `specs/022-brief-opening-and-options/quickstart.md` that can be done without a live issue (steps 5 and 6: read SKILL.md step 1 and both docs pages against FR-001 to FR-009)

## Dependencies and Execution Order

- T001 first. T002 and T003 edit the same file: run in order T002, T003. T004 and T005 run after T003 so the docs match the final skill text, and are parallel with each other (different files).
- T006 to T008 after T002 to T005.
- US1 is the MVP; US2 and US3 do not depend on US1 to be testable.

## Parallel Example

```text
T004 docs/workflow.md   ||   T005 docs/usage.md
```

## Implementation Strategy

MVP first: T001, T002, then T006 and T007 to validate the briefing alone. Add T003 (table), then T004 and T005 (docs), then rerun T006 to T008.
