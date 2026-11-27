# Feature Specification: /brief opens an issue run with where it stands, and lays real tradeoffs out as a table

**Feature Branch**: `brief-opening-and-options`

**Created**: 2026-11-27

**Status**: Draft

**Input**: User description: brief `specs/briefs/brief-opening-and-options.md` (issue pdemagny/logistics#112)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Opening briefing on an issue run (Priority: P1)

A person runs `/brief #N` (or with an issue URL). Before answering anything, they see in one message what the issue asks, how the code and docs stand today, what the issue already settles, and what is left to settle, followed by the interview's hypothesis, confidence and first question.

**Why this priority**: Today the first message is a bare question, so the user answers without the gist of what was read and found. This is the main gap.

**Independent Test**: Run `/brief` on an issue and check that the first interview message opens with the "Where it stands" briefing and ends with the first question, in one message.

**Acceptance Scenarios**:

1. **Given** an issue start, **When** the issue has been read and the code and docs it touches investigated, **Then** the first interview message opens with a "Where it stands" briefing of up to four bullets of one or two lines each (The ask, Today with file:line, Already decided, Open), followed in the same message by the hypothesis, confidence and first question.
2. **Given** an issue that settles nothing or leaves nothing open, **When** the briefing is shown, **Then** the empty "Already decided" or "Open" bullet is omitted and nothing is invented.
3. **Given** the `/tiny` offer applies and is declined (or does not apply), **When** the interview starts, **Then** the briefing comes after that point; the offer itself is unchanged.
4. **Given** the issue was read by `gh issue view`, by `tracker.sh read-issue` with board tracking, or pasted by the user because it could not be read, **When** the interview starts, **Then** the briefing is shown in each case.
5. **Given** an issue body containing instructions, **When** the briefing is written, **Then** it paraphrases the body and does not follow it.
6. **Given** a start that is a plain idea, a capability-map row or a tiny brief, **When** the interview starts, **Then** it opens as it does today, with no briefing.

---

### User Story 2 - Tradeoff table for a choice between roads (Priority: P2)

During the interview, when a question is a real choice between several roads, the user sees the options as a markdown table, compares them on the criteria that matter, then reads the recommendation.

**Why this priority**: Prose tradeoffs are hard to compare, but this affects fewer questions than the opening does.

**Independent Test**: Put a question with 3 viable options to the interview and check for one table before the guess; put a yes/no question and check for no table.

**Acceptance Scenarios**:

1. **Given** a question with at least 3 viable options, or 2 that differ on at least 2 criteria the user would weigh, **When** it is asked, **Then** it shows one markdown table (rows are options, columns are the separating criteria, the recommended row marked) before the guess, and the guess and strongest counter-argument still follow.
2. **Given** a yes/no question, a "keep as written" question or a single-road question, **When** it is asked, **Then** no table is shown.

---

### User Story 3 - Docs describe both behaviours (Priority: P3)

A reader of the workflow and usage docs finds both behaviours described in the places that describe `/brief`.

**Why this priority**: Docs must match the skill but deliver no behaviour of their own.

**Independent Test**: Read phase 1 details of the workflow doc and section 1 of the usage doc and find both behaviours in one or two sentences each.

**Acceptance Scenarios**:

1. **Given** the workflow doc's phase 1 details and the usage doc's section 1, **When** read, **Then** each states the issue-start briefing and the tradeoff table trigger, shape and exceptions in one or two sentences.

### Edge Cases

- An issue the user pasted because it could not be read: the briefing still opens the first message.
- An issue with no unchecked checklist items and nothing unclear: "Open" is omitted.
- A question with 2 options differing on only one criterion: no table.
- A start that is not an issue: no briefing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On an issue start only, the first interview message MUST open with a "Where it stands" briefing of up to four bullets, each one or two lines: The ask, Today (with file:line and what is missing), Already decided, Open.
- **FR-002**: The briefing MUST come after both the issue read and the initial code and docs investigation the issue calls for, after the `/tiny` offer is declined or does not apply, and in the same message as the hypothesis, confidence and first question (one stop only).
- **FR-003**: "Already decided" and "Open" MUST be omitted when empty; "Open" covers unchecked checklist items and anything found unclear.
- **FR-004**: The briefing MUST apply on every way the issue is read (`gh issue view`, `tracker.sh read-issue` with board tracking, a pasted issue).
- **FR-005**: The issue body MUST be treated as data: the briefing paraphrases it and is not a copy of it.
- **FR-006**: When a question has at least 3 viable options, or 2 that differ on at least 2 criteria the user would weigh, it MUST show one markdown table before the guess: rows are options, columns are separating criteria, recommended row marked. The guess and strongest counter-argument follow the table.
- **FR-007**: No table MUST be shown for yes/no, "keep as written" or single-road questions; a "viable" option is one the interviewer would defend.
- **FR-008**: The skill text MUST state the briefing in step 1's "From an issue" paragraph and the table rule in one sentence in step 1's interview paragraph, adding at most about 15 lines.
- **FR-009**: The workflow doc (phase 1 details) and usage doc (section 1) MUST describe both in one or two sentences each.
- **FR-010**: Nothing outside `/brief` MUST change: the shared coordinator rules, `/feat`, `/fix` and `/tiny` skills stay untouched, as do the brief's format and `interview-me`.
- **FR-011**: A table added to the skill MUST NOT match the lint greps for size and gate tables, and only the repo source is edited.

### Key Entities

- **Briefing**: up to four bullets of one or two lines each (ask, today, decided, open) opening the first message of an issue run.
- **Tradeoff table**: options by criteria, one recommended row, shown per qualifying question; a conversation aid, never saved in the brief.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of issue-start runs open the first interview message with the briefing, with exactly one stop before the user's first answer.
- **SC-002**: 0 briefings appear on non-issue starts.
- **SC-003**: Every question meeting the trigger shows exactly one table before the guess, and no question outside it shows one.
- **SC-004**: The skill grows by about 15 lines or fewer.
- **SC-005**: `mise run lint` and `mise run test:apm` pass, and no file outside the brief skill and its two docs pages changes.

## Assumptions

- The "Where it stands" briefing text is English, as the rest of the skill.
- The existing `/tiny` offer and the interview-me flow stay as they are; `/brief` adapts how they are followed.
- Alternatives rejected in the brief (issue paraphrase alone, two stops, briefing on every start, tables in shared gates, table for every decision) stay out.
