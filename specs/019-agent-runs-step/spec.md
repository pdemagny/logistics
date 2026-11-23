# Feature Specification: Agents run step.sh last so the coordinator spawns straight from the hand-back

**Feature Branch**: `agent-runs-step`

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "Agents run step.sh last so the coordinator spawns straight from the hand-back" (brief `specs/briefs/agent-runs-step.md`, issue #88, part of epic #31)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A sequential boundary costs the coordinator no `step.sh` call (Priority: P1)

A user runs `/feat` or `/fix`. When an agent that closes a boundary on its own (specifier, planner, tasker, implementer, shipper, bug assessor) finishes, it runs the boundary call of its own spawn block as its last step and ends its hand-back with the output, verbatim, in one fenced block. The coordinator reads the verdict and the next spawn(s) from that block and acts at once, with no `step.sh` call and no extra model turn to carry the output across.

**Why this priority**: This is the whole saving: each coordinator call re-reads 120-160k tokens of context, and 18-25 of them per `/feat` run exist only to carry `step.sh`'s output to the next spawn.

**Independent Test**: Run a small `/feat` and a small `/fix`. After each sequential agent hand-back, the coordinator spawns the next agent or shows the gate without a `step.sh` call of its own. The coordinator's `step.sh` calls appear only at reviewer fan-outs, hard gates, answer calls, `rebase` and the one `done:` check before the final message.

**Acceptance Scenarios**:

1. **Given** a specifier that wrote its report, **When** it hands back, **Then** its last step was the spawn block's `boundary:` call and its hand-back ends with the output in one fenced block.
2. **Given** a hand-back whose block says `soft`, **When** the coordinator reads it, **Then** it gives the one-line summary and the printed spawn(s) in the same turn, with no `step.sh` call.
3. **Given** a hand-back whose block says `hard:`, `base: moved` or `step: error`, **When** the coordinator reads it, **Then** it acts as it does today on its own `step.sh` output (the gate, `read:`, the error gate).
4. **Given** a hand-back whose block ends with `done:` (the shipper's), **When** the coordinator reads it, **Then** it runs that boundary's `boundary:` call itself (after any pending `S log`, in the same command) and acts on its own output: the final message when that output is the same `done:` (a re-print), else what that output says.
5. **Given** an implementer whose checks failed, **When** its hand-back arrives, **Then** the block carries today's retry spawn and the coordinator makes that retry spawn.
6. **Given** the boundary list (`/feat`: specifier, planner, tasker including amends continued with `SendMessage`, each implementer story and its check retries, the review-fixes implementer, the shipper; `/fix`: assessor in assess and test, bug-mode implementer, review-fixes implementer, shipper), **When** any of them reports, **Then** the same rule applies with no exception.

---

### User Story 2 - A format slip is repaired by the agent, once (Priority: P1)

When `step.sh` answers `reformat` to an agent's own boundary call, the agent writes the corrected report to the path the reformat spawn block names, runs that block's `boundary:` line once, and hands back the second output, whatever it says. The agent acts on no other verdict and never changes its work or its writes to turn a gate soft.

**Why this priority**: Without it, a format slip turns every agent-run boundary into a coordinator round trip. The limit (reformat only, once) keeps the agent from widening what it does unseen.

**Independent Test**: Feed a boundary a malformed report: the first output is `reformat`, the second is the decision. Feed it a second malformed report: the second output is today's hard gate.

**Acceptance Scenarios**:

1. **Given** a report with an unparsable line, **When** the agent runs `boundary:` and gets `reformat`, **Then** it rewrites the report at the named path, runs the new block's `boundary:` line once and hands back that output.
2. **Given** a second miss, **When** the agent hands back, **Then** the block is today's hard gate and the agent does nothing more.
3. **Given** a `hard:` verdict from the first call (a refused write, a missing `Wrote:` file), **When** the agent hands back, **Then** it hands the block back as is and changes nothing.
4. **Given** an agent's reformat ended in a decision and its block did not parse, **When** the coordinator makes the slip-fallback call with the `boundary:` words it holds (the original spawn's, naming the first report path), **Then** `step.sh` re-prints the second call's decision.

---

### User Story 3 - A missing or broken block never costs a decision (Priority: P1)

If a hand-back has no `step.sh` block, or the block does not parse (truncated, paraphrased, tabs turned into spaces), the coordinator runs that boundary's `boundary:` call itself, as today. `step.sh`, called again with the last decided boundary's report, prints that decision again from its decision record (verdict, spawns, `boundary:` and `answer call:` lines) without deciding or logging twice. Only the latest hand-back, from the agent the coordinator waits on, is spawned from.

**Why this priority**: The saving is safe only if a slip falls back to today's behaviour with no double decision and no stale spawn.

**Independent Test**: Run a boundary, then call it again with the same report: the second output equals the first, and the Log and header are unchanged. Call with a stale token and a different report: `step: error`.

**Acceptance Scenarios**:

1. **Given** a decided boundary, **When** `step.sh` is called again with the same token and the same report path and sum, **Then** it re-prints the recorded decision and leaves the Log, the header and the decision record unchanged.
2. **Given** a token that is neither the open one (the next spawn the last decision issued) nor the last decided boundary's, **When** `step.sh` is called, **Then** the result is `step: error`.
3. **Given** the last decided boundary's token with a different report path or sum, **When** `step.sh` is called, **Then** the result is `step: error`, not a decision.
4. **Given** an older boundary's token, **When** called, **Then** it never re-prints that older decision.
5. **Given** a decision reached through a reformat, **When** `step.sh` is called with the words of any call of that reformat chain (every call since the last output that was not `reformat`) and its reports unchanged, **Then** it re-prints that decision.

---

### User Story 4 - Agent ids arrive late, on the coordinator's next own call (Priority: P2)

An agent-run boundary takes no `agent=<id>` word, because the agent does not know its own id. A reformat spawn of the specifier, planner or tasker always prints `continue: <role>`, with no id lookup: the coordinator continues that role's latest agent, by the id its `Agent` result gave. The coordinator passes `agent=<role>:<id>` words, taken from the `Agent` results, on its next own `step.sh` call (an answer call at a hard gate, or a fan-out boundary); `step.sh` records them in `Agents:` then, and the one continuation that looks an id up, the planner amend after a soft gate 4, prints the id its own batch call recorded. `/fix` makes no continuations and needs no ids.

**Why this priority**: It removes the one reason specifier, planner and tasker boundaries would stay coordinator-run (about 4-6 calls per `/feat` run), and every `/feat` continuation follows such a call.

**Independent Test**: Reformat a specifier report and read `continue: specifier`, whatever `Agents:` holds. Make a gate 4 batch call carrying `agent=planner:<id>` with an `apply` finding, then read the state file's `Agents:` line and the planner amend's `continue:` line carrying the id.

**Acceptance Scenarios**:

1. **Given** a specifier, planner or tasker boundary whose verdict is `reformat`, **When** the reformat spawn prints, **Then** it reads `continue: <role>` (`continue: specifier` for the specifier).
2. **Given** an answer call or a fan-out boundary call with `agent=<role>:<id>` words, **When** `step.sh` runs, **Then** `Agents:` records them.
3. **Given** a gate 4 batch call carrying `agent=planner:<id>`, **When** it prints the planner amend, **Then** the amend's continuation prints that id.
4. **Given** a `/fix` run, **When** any boundary runs, **Then** no id is needed or recorded.

---

### User Story 5 - Coordinator chores move to the coordinator's next own call (Priority: P2)

The chores the coordinator chains before a boundary call today keep their owner but change timing. Log lines (`[!] brief left in place`, a preflight `flag:`) go with its next own `step.sh` call. Other chores at a moved boundary (deleting the brief after phase 2, the review move before phase 7) are extra tool calls in the same response as the next spawn, so they cost no model call of their own.

**Why this priority**: Without a home for them, the chores would be dropped or would bring back the coordinator call this change removes.

**Independent Test**: Carry a chained log line on the next own call and find it in the Log. Run a small `/feat` and see the brief deleted and the review move done in the same response as the next spawn.

**Acceptance Scenarios**:

1. **Given** a pending log line, **When** the coordinator makes its next own `step.sh` call with the line, **Then** the line lands in the Log.
2. **Given** a moved phase 2 or phase 7 boundary, **When** the coordinator spawns, **Then** the chore runs as a tool call in that same response.

---

### User Story 6 - The documents tell the same story (Priority: P3)

`harness.md`, `/feat`, `/fix`, the six agent files and `docs/workflow.md` say it consistently: the coordinator spawns from the hand-back, the slip fallback, where ids and chores go. A walk-through of a small `/feat` run in `docs/workflow.md` shows one coordinator `step.sh` call per fan-out, gate and answer, plus the `done:` check, and none per sequential spawn. The `/fix` section's Roles and phase 1 text says the same for `/fix`.

**Why this priority**: The behaviour lives in prompts; the documents must carry it, but they are worth nothing before the script and agents work.

**Independent Test**: Read the walk-through and count the coordinator `step.sh` calls against the fan-outs, gates, answers and the `done:` check; run `mise run lint`.

**Acceptance Scenarios**:

1. **Given** the six agent files (specifier, planner, tasker, implementer, shipper, bug assessor), **When** read, **Then** each ends with a fixed last step: run `boundary:`, act on `reformat` only, end with the verbatim block. Reviewers are unchanged.
2. **Given** `harness.md`, **When** read, **Then** it holds the shared rules in named values with no `/feat`-only words, and `/feat` and `/fix` fill them.
3. **Given** a change to `/feat`'s gates or chain, **When** the diagrams are checked, **Then** `gates.d2`, `chain.d2` and their renders in `docs/img/` are updated.

---

### Edge Cases

- The hand-back's block is truncated or paraphrased, or its last line's key (`boundary:`, `answer call:`) is not followed by a tab: the coordinator runs the boundary call itself (slip fallback); it never spawns from a partial block.
- A coordinator gets a hand-back from an older agent than the one it waits on: it ignores it for spawning, and a re-print always returns that boundary's recorded decision.
- A stale token carries the right report: still `step: error` unless it is the open token or the last decided boundary's with the same report path and sum.
- The agent's `boundary:` call fails, is refused or is not run (a non-zero exit, no output): the agent adds no block and says so on the digest's last line; the block is only ever a copy of that request's Bash result. The coordinator treats it as a missing block.
- A well-formed block the agent wrote without running the call (from memory, from an earlier call, after a refused Bash) is caught at the next `step.sh` call (`no boundary is open` or `neither the open boundary…`): a `step: error` at an agent's boundary may mean the previous hand-back's block was not `step.sh`'s.
- A `done:` in a hand-back is the one verdict no later call checks, so the coordinator checks it with its own call (a re-print when the block was `step.sh`'s) before the final message.
- A reformat the agent ran ends in a decision, and the coordinator's slip fallback names the original spawn's report path: the decision is re-printed, since the record keeps every call of the reformat chain.
- A coordinator `S` or `T` call writes the state file while an agent's `step.sh` call is deciding (a `size` mid-spawn, a `/feat resume` in a second session): that `step.sh` call writes nothing and ends in `step: error` (the state file changed since it read it), and the retry decides on the new state; no update is lost silently.
- `reports/` is missing (a resume on another clone): `step.sh` creates it with its `*` `.gitignore`, as `state.sh report-path` does, before writing the decision record; a symlinked `reports/` or record is a `step: error`.
- Writing the decision record fails: the header fields the call set are put back, as for any failed commit, so the retry decides as the first try.
- A pending log line and an `agent=` word on the same own call: both land.
- A reviewer fan-out, `rebase`, and a hard-gate answer call are unchanged and stay coordinator calls.
- An implementer whose checks fail repeatedly: each retry is a new spawn with its own boundary, decided as today.
- `model` and `effort` copied wrongly from a hand-back are not detectable and are accepted as a risk.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: At every boundary closed by one agent (`/feat`: specifier, planner, tasker, each implementer story and its check retries, the review-fixes implementer, the shipper; `/fix`: assessor in assess and test, bug-mode implementer, review-fixes implementer, shipper), the agent MUST run the `boundary:` line of its own spawn block as its last step, after writing its report, and end its hand-back with the output verbatim in one fenced block. The block MUST only ever be a copy of that Bash result: when the call was refused, failed or not run, the agent adds no block and says so on the digest's last line.
- **FR-002**: The coordinator MUST read the verdict and spawn blocks from the hand-back and act as it does on its own `step.sh` output today: `soft` gives the one-line summary and the printed spawn(s) in the same turn with no `step.sh` call; `hard:` the gate; `base: moved` `read:`; `step: error` the error gate. On a block ending with `done:`, the coordinator MUST first run that boundary's `boundary:` call itself (chained after any pending `S log`) and act on its own output: the final message when it is the same `done:` (a re-print), else what it says.
- **FR-003**: On `reformat`, the agent MUST write the corrected report to the path the reformat spawn block names, run that block's `boundary:` line once, and hand back the second output whatever it says; a second miss is today's hard gate.
- **FR-004**: The agent MUST act on no verdict other than `reformat`, and never change its work or writes to turn a gate soft. An implementer's failed-checks verdict is handed back as is and the coordinator makes the retry spawn `step.sh` printed.
- **FR-005**: `step.sh` MUST print `step script:` and the `boundary:` words as keys of the spawn block, so the existing rule "every key of the spawn block goes into the prompt" carries them to the agent without a new rule. The words are as printed today (tab-separated, each single-quoted).
- **FR-006**: The six agent files (specifier, planner, tasker, implementer, shipper, bug assessor) MUST each end with one fixed last-step section: run `boundary:`, act on `reformat` only, end with the verbatim block. Reviewers MUST stay unchanged.
- **FR-007**: When a hand-back has no `step.sh` block, or the block does not parse, the coordinator MUST run that boundary's `boundary:` call itself. A block parses only when its first line is a verdict `step.sh` prints and its last line starts `boundary:` or `answer call:` followed by a tab, or `done:`, or the block is the one `step: error:` line.
- **FR-008**: `step.sh`, given the last decided boundary's token with the same report path and sum, or the words of any call of the reformat chain that led to that decision (every call since the last output that was not `reformat`) with its reports unchanged, MUST print that decision again from the decision record (verdict, spawns, `boundary:` and `answer call:` lines) without deciding again and without changing the Log, the header or the record.
- **FR-009**: `step.sh` MUST accept a boundary call only when its token is the open one (the next spawn the last decision issued), or when it is a re-print (FR-008) whose report path and sum match the decision record. Anything else, such as a stale token with a different report or a token or report path the last decision never issued, MUST be a `step: error`, not a decision.
- **FR-010**: The coordinator MUST spawn only from the hand-back of the agent it is waiting on, and a re-print MUST always return that boundary's recorded decision, never an older one.
- **FR-011**: An agent-run boundary MUST take no `agent=<id>` word. A reformat spawn of the specifier, planner or tasker MUST print `continue: <role>`, with no id lookup; the coordinator continues that role's latest agent by the id its `Agent` result gave (holding none, after a resume: a fresh spawn).
- **FR-012**: The coordinator MUST pass `agent=<role>:<id>` words, from the `Agent` results, on its next own `step.sh` call (an answer call at a hard gate, or a fan-out boundary), and `step.sh` MUST record them in `Agents:` then. The planner amend after a soft gate 4, the one continuation that looks an id up, MUST print the id its own batch call recorded (`continue: fresh` when none is recorded, as today). `/fix` needs no ids.
- **FR-013**: Log lines the coordinator chains before a boundary call today (`[!] brief left in place`, a preflight `flag:`) MUST go with its next own `step.sh` call and land in the Log.
- **FR-014**: Other chores at a moved boundary (deleting the brief after phase 2, the review move before phase 7) MUST be extra tool calls in the same response as the next spawn. The coordinator still owns them.
- **FR-015**: Reviewer fan-outs (`/feat` phases 4, 7 and 7e, `/fix` phase 4) and `rebase` MUST keep the coordinator's `step.sh` call.
- **FR-016**: `step.sh` MUST remain the only decider and, with `state.sh`, the only writer of the state file; every line it prints is data. The report-file and `Wrote:` rules are unchanged.
- **FR-017**: `step.sh` MUST stay Bash 3.2 with no jq and no Python and stay shellcheck clean; `harness.md` MUST stay free of `/feat`-only words.
- **FR-018**: `harness.md`, `/feat` and `/fix` MUST say that the coordinator spawns from the hand-back, the slip fallback, and where ids and chores go, and `/feat` and `/fix` MUST stay thin, with no new coordinator work besides reading the block.
- **FR-019**: A walk-through of a small `/feat` run in `docs/workflow.md` MUST show one coordinator `step.sh` call per fan-out, gate and answer, plus the `done:` check, and none per sequential spawn; the `/fix` section's Roles bullet and its phase 1 text MUST say who calls `step.sh` the same way; `gates.d2`, `chain.d2` and their renders in `docs/img/` MUST be updated with any change to `/feat`'s phases or gates.
- **FR-020**: `tests/step` MUST cover: an agent-run boundary (soft, hard, `done:`) with no `agent=` word, and the `done:` boundary called again (the coordinator's check) re-printing it; the same boundary called again with the same report (re-print, Log, header and record unchanged); a token or report path not issued by the last decision, and a stale token with a different report (`step: error`); an implementer's failed-checks verdict from an agent-run boundary printing today's retry spawn; `agent=<role>:<id>` on an answer call and on a fan-out boundary filling `Agents:`, and the gate 4 planner amend printing the id; `continue: <role>` on a reformat spawn of those roles; a reformat run by the agent ending in the second boundary's decision, the original spawn's words then re-printing it, and a second miss in today's hard gate; a chained log line carried by the next own call landing in the Log; a failed record write putting the header fields back; a state file changed during the call (`step: error`, nothing written); a missing `reports/` created with its `.gitignore`.
- **FR-021**: `mise run lint` and every offline test MUST pass.
- **FR-022**: `step.sh` MUST refuse to write (a `step: error`, no Log line, field or record written by the decision) when the state file changed between its read and its commit, so a second writer's update is never lost silently.
- **FR-023**: The decision record MUST be written through the same guard as `state.sh report-path`: an unsafe artifact dir name, a symlinked `reports/`, `.gitignore` or record is refused; a missing `reports/` is created with its `.gitignore` holding `*`, so the record is never committed. It MUST be written as part of the commit, so a failed write puts back the header fields the call set.

### Key Entities

- **Boundary**: the point between two phases or spawns, closed by one `step.sh` call that decides soft, hard, done, reformat, moved base or error.
- **Spawn block**: what `step.sh` prints for a next spawn (report path, model, effort, inputs, `step script:`, `boundary:`).
- **Hand-back block**: `step.sh`'s output as the agent ends its hand-back with it, verbatim, in one fenced block.
- **Decision record**: `reports/last-step.md` beside the state file (ignored, never committed): the last decided call, plus the earlier calls of its reformat chain, each with its report sums, and the output as printed; the source of the open token (the next spawn the last decision issued) and of re-prints. The state file's Log keeps today's lines and gains none.
- **Agents line**: the state file's `Agents:` record of `<role>:<id>` used for continuations.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a small `/feat` run, the coordinator makes a `step.sh` call only at reviewer fan-outs, hard gates, answers, `rebase` and the one `done:` check, and none per sequential spawn, down from 18-25 such calls per run.
- **SC-002**: A slip (missing, truncated or paraphrased block) costs one own call and never a second decision: re-calling with the last decided report leaves the Log and header byte for byte unchanged.
- **SC-003**: A stale or never-issued token is rejected in 100% of the `tests/step` cases and is never decided.
- **SC-004**: The planner amend after a soft gate 4 carries the id its batch call recorded, and every reformat continuation of the specifier, planner or tasker reads `continue: <role>`.
- **SC-005**: `mise run lint` and every offline test pass, with `step.sh` still Bash 3.2, no jq, no Python.
- **SC-006**: After merge, not blocking the PR: over at least five runs of each skill, `mise run measure --compare-since <merge date>` shows coordinator `step.sh` calls only at fan-outs, gates, answers and the one `done:` check, and subagent calls per spawn rising by at most about 2.

## Assumptions

- Agents keep Bash (their `disallowedTools` do not remove it), and their spawn block carries the step script path, the skill, the state file and the `boundary:` words as printed.
- Slips are the threat, not a malicious agent; the fail-closed check, the slip fallback and the coordinator's `done:` check cover them (a made-up block is caught at the next `step.sh` call, a made-up `done:` by that check). A wrong `model` or `effort` copied from a hand-back is an accepted risk.
- `measure.py` is unchanged: its existing coordinator "chores" column is the measure.
- Out of scope: foreground spawns and the waiting turns (#87, built separately), fan-out boundaries run by an agent or a workflow script (#56), the implementer's own call count (#55).
- No signed `step.sh` output, no lint check for the agent files' last-step wording, no new argument for chained log lines: `tests/step` and the code review cover the contract.
- The shipper's boundary joins the rule (it prints `done: PR #N`) so there is no exception in the agent files or coordinators.
- The agent writes its report before running `boundary:`, so the report and `Wrote:` rules hold.
