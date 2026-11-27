# Research: /brief opening briefing and tradeoff table

No NEEDS CLARIFICATION was left in the Technical Context; these are the
placement and wording decisions the spec leaves to the plan.

## R1. Where the briefing rule goes in SKILL.md

- **Decision**: append it to the end of step 1's "From an issue" paragraph,
  after the board tracking `read-issue` sentence.
- **Rationale**: FR-008 names that paragraph; at its end, "any of these
  ways" covers the three reads (`gh issue view`, `read-issue`, pasted) in
  one phrase (FR-004), and the rule stays out of the capability-map and
  tiny-brief paragraphs (no briefing on other starts).
- **Alternatives considered**: a new paragraph after the `/tiny` offer
  (splits the issue rules across two places); a sentence inside the
  interview-me paragraph (would read as applying to every start).

## R2. Briefing written as prose or as a fenced template

- **Decision**: prose naming the four bullets and what each holds.
- **Rationale**: the brief's fenced template costs about 7 lines; prose
  keeps the whole change within the ~15-line budget (SC-004) and the four
  labels are short enough to reproduce from prose.
- **Alternatives considered**: the fenced template from the brief (clearer
  shape, but pushes the skill past ~15 added lines together with the table
  sentence).

## R3. How the ordering is enforced

- **Decision**: the passage names its preconditions (issue read, code and
  docs read, `/tiny` offer declined or not applicable) and the same-message
  rule ("one stop").
- **Rationale**: step 1 already orders the code read and the `/tiny` offer
  before interview-me; restating them as conditions keeps the model from
  showing the briefing early or in a separate stop (FR-002).
- **Alternatives considered**: moving the issue paragraph above the code
  read (reshuffles step 1 for no behaviour gain).

## R4. Where and how the table rule goes

- **Decision**: one sentence appended to the "Invoke `interview-me`"
  paragraph; the shape is described in prose, with no example table.
- **Rationale**: FR-008 asks for one sentence in the interview paragraph;
  prose cannot match the lint greps for size and gate tables (FR-011) and
  costs fewer lines than an example.
- **Alternatives considered**: an example table (costs lines, and a header
  could drift toward the grepped ones); putting it in the "Don't agree by
  default" paragraph (that paragraph is about counter-arguments, not about
  how a question is shown).

## R5. Docs placement

- **Decision**: `docs/workflow.md` phase 1 details get the table sentence
  after the opening sentence and the briefing sentence in the "From an
  issue" sentence; `docs/usage.md` section 1 likewise in its first
  paragraph and its "From a GitHub issue" paragraph.
- **Rationale**: each behaviour sits next to the text that already
  describes the matching part of `/brief` (FR-009).
- **Alternatives considered**: a new subsection (more text than one or two
  sentences, and a new heading for a small rule).
