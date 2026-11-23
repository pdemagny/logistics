# Research: agents run step.sh last

No `NEEDS CLARIFICATION` was left in the Technical Context; each entry below
is a decision the spec left to planning.

## R1. The decision record: one file beside the reports, not new Log lines

- **Decision**: after every decided call (setup, resume, a boundary call,
  an answer call; never `size`, `refused:`, `step: error` or `step:
  usage`), step.sh writes the whole of what it printed, plus the call that
  produced it (and the earlier calls of its reformat chain, R3), to
  `<artifact dir>/reports/last-step.md` (overwritten each time; format in
  [data-model.md](data-model.md#decision-record)). It is the spec's
  "Decision record", the source of the open token and the re-print: the
  call's token, its report paths and their sums, and the decision as
  printed. The Log keeps the lines it gets today and gains none.
- **Rationale**: a re-print must be the decision as printed, byte for byte
  (SC-002), and the spawn blocks it holds (report paths, inputs files,
  snapshot tokens) can't be rebuilt from the Log: deciding again reads a
  Log and a `Current phase` the first decision already changed. The
  output has to be stored somewhere, so it is stored once, and the issued
  `boundary:` line inside it gives the open token for free. `reports/` is
  already ignored, never committed, left out of the reviewers' snapshot,
  and moves with the artifact dir when the shipper numbers it. step.sh
  already writes a file there itself (`review.diff`, `diff_write`).
- **Alternatives considered**: a Log sub-line per decision with token,
  report and sum (the output would still need a file, so the fact would
  live twice; every `expected/*.log` golden would change; the Log the PR
  links gets one machine line per boundary; state.sh's sub-line readers
  would need checking); deciding again and relying on `commit`'s repeat
  check (the Log and `Current phase` already moved, so the second decision
  can differ, and new report paths or inputs files could be issued).

## R2. Writing the record

- **Decision**: `record_write` in step.sh is the last part of `commit`:
  after the Log line, the field sets, the snapshot and the `@SNAP@`
  substitution, `render` fills the output lines once (`print_all` split
  into render and print, so the record and stdout are the same lines),
  then `record_write` passes the record's lines to a new `state.sh record
  <state file> <line>…`, and only then is `CM_SET` cleared. `state.sh
  record` is `inputs`' twin: `reports_dir` (an unsafe dir name, a
  symlinked `reports/` or `.gitignore`, a non-directory `reports/`
  refused), the record path no symlink and a regular file when present,
  `reports_make` (a missing `reports/` created, its `.gitignore` made to
  hold `*`), then `write_file` (temp file in the same dir, `mv -f`) with
  its fixed first line before the lines. A failure is a `step: error`.
- **Rationale**: written inside the commit, a record never names a
  decision the Log does not hold, and a failed write goes through
  `undo_sets` like any other commit failure: the fields the call set
  (`Current phase`, `Size`, `Agents`) are put back, the previous record
  stays (`write_file` writes nothing on failure), its issued line still
  admits the same call, and the retry decides as the first try, its Log
  lines not written twice (`commit`'s repeat check). The `reports/` guard
  lives once, in state.sh, used by `report-path`, `inputs` and `record`:
  the record copies step.sh's whole output (a `base: fetch-failed: <git
  message>` included), and the `*` `.gitignore` is what keeps it out of
  every commit. A missing `reports/` (a resume on another clone, where the
  ignored dir never came along) is created, not an error.
- **Alternatives considered**: writing the record before the commit (a
  failed commit would leave a re-printable decision that was never
  logged); writing it after `commit` returns (a failed write would leave
  `Current phase` advanced with no record of the decision, `CM_SET`
  already cleared); step.sh's own `mktemp`/`mv -f` with two `-L` tests
  (skips the unsafe-name check and the `.gitignore`, and dies on a missing
  `reports/`); writing no record when `reports/` is missing (the next call
  then falls back to `Current phase` for no reason; creating the dir is
  what `report-path` already does).

## R3. Which call is accepted

- **Decision**: for a boundary call (no `answer:` word), in this order:
  1. **Re-print**: one of the record's `call:` lines has words equal to
     the call's words, and each report path of the call hashes to the
     value its `sums:` line holds now (a renumbered path read where
     `check_report` reads it): print the record's output, exit 0, write
     nothing. The record holds one `call:`/`sums:` pair per call of the
     reformat chain that led to its decision: when the previous record's
     output was `reformat` and this call is a boundary call, its pairs are
     kept before this call's; any other decided call starts a new chain.
     A chain holds at most two calls (a second miss is a hard gate).
  2. **Open**: the record's issued `boundary:` line (the first output line
     starting `boundary:` + tab) has the call's token, and every report
     path of the call is one of that line's words: decide as today.
  3. Anything else: `step: error`. No issued line (the last output was a
     hard gate, `done:` or `stop:`): `step: error: no boundary is open
     (<the last output's verdict>)`; else `step: error: boundary <token>
     <report name> is neither the open boundary (<issued token>) nor the
     last decided one with the same report`.
  With no record at all (a run started before this change and never
  resumed since), step 2 is today's check: `Current phase` allows the
  token (`allowed_tokens`). Answer calls keep today's check (`open_gate`).
  The report key check (`key_ok`) and `allowed_tokens` stay, behind step 2.
- **Rationale**: FR-008 to FR-010. Report paths are compared, not whole
  lines, because one issued line is answered by a call with fewer words:
  merge rule 1's review-fixes call with no report and `dropped:` words.
  The re-print is tried first because it is the only call that may name a
  token that is no longer open. An older boundary can't re-print: the
  record holds only the last decision. The reformat chain is kept because
  an agent that ran its own reformat hands back the second call's output,
  while the coordinator holds only the first spawn's `boundary:` words
  (the first report path): without the first pair, its slip-fallback call
  would name neither the record's call nor the open token, and a slip
  after a format slip would reach the error gate instead of re-printing
  (US2, US3, SC-002).
- **Alternatives considered**: comparing the full word list with the
  issued line (refuses the `dropped:` call); letting the fallback after an
  agent-run reformat reach the error gate and the user answer `back to N`
  (a gate for a slip the record can absorb in a few lines); failing every
  call when the
  record is missing (every existing `tests/step` case starts from a fixture
  state with no record, and a run updated mid-way would stop; `resume`
  writes a record, so the fallback lasts until the next resume or
  decision at most).

## R4. The spawn block's new keys

- **Decision**: a spawn whose boundary that one agent closes gets two last
  keys: `step script:` with three tab-separated words (step.sh's path, the
  skill, the state file) and `boundary:` with the same tab-separated words
  as the call line printed after the blocks. The agent's command is `bash`
  followed by every word of the two keys, each single-quoted. They are
  printed for the rows of the specifier, planner (first run and amend),
  tasker, implementer in story, fix and bug mode, shipper, and bug assessor
  in assess and test mode, including their reformat spawns; never for a
  reviewer (its batch shares one call) or a rebase-mode implementer
  (`move`, `repair`, the ship conflict's move). The call line after the
  blocks stays, for the coordinator's slip fallback.
- **Rationale**: FR-005. The words before the token are given, not
  inferred: the implementer and the shipper serve both skills, and the
  state file moves at ship. Keeping `boundary:` identical to the call line
  means one form to read. `step script:`'s other uses (`ship script:`,
  `trail script:`) hold a path only, but those scripts take their own
  arguments; this one's first three words are fixed per run.
- **Alternatives considered**: a `skill:` and a `state file:` key (two more
  keys to copy for the same command); the agent taking the skill from its
  prompt (ambiguous for the two shared agents); printing the keys in every
  block (reviewers would run a batch call alone; move spawns are outside
  the spec's list, R10).

## R5. Agent ids

- **Decision**:
  - The word is `agent=<role>:<id>`, `<role>` one of `specifier`,
    `planner`, `tasker`, `<id>` as today's rule (`[A-Za-z0-9_-]`, at most
    64); several per call. It is taken on an answer call and on a reviewer
    batch call (`/feat` 4, 7, 7e), `/feat` only; anywhere else, in `/fix`,
    or in today's form `agent=<id>`, it is a `step: usage` line. The ids
    are written to `Agents:` before the decision prints anything, so the
    same call's continuation carries them.
  - The coordinator passes, on each of those calls, the latest id the
    Agent tool returned for each of the three roles it has spawned in this
    session (continued agents keep their id), so no bookkeeping of "not
    yet passed" is needed: `set_agent` replaces a role's entry.
  - A reformat spawn of the specifier, planner or tasker (`/feat` only)
    prints `continue: <role>` with no lookup, whatever `Agents:` holds.
    The coordinator continues the latest agent of that role, by the id
    its `Agent` result gave; holding none (after a resume), it spawns
    fresh.
  - The planner amend after a soft gate 4 keeps today's lookup (the id,
    else `continue: fresh`): it is printed by the batch call, which sets
    the planner's id first.
- **Rationale**: FR-011, FR-012, SC-004. A reformat spawn of those roles
  follows a boundary the agent itself closed, so the `Agents:` line can
  hold an older agent's id; the agent whose report is reformatted is the
  latest one of its role, which only the coordinator knows. An
  agent-run reformat is made by the agent; a coordinator-made one
  continues the agent whose `Agent` result it just read. So no id is
  looked up for it, and nothing needs dropping from `Agents:`. `/fix`
  never prints a continuation.
- **Alternatives considered**: dropping a role's id when its boundary
  decides at 2, 3 or 5, rendering an empty `Agents:` as `none`, and
  printing `continue: <role>` only when the lookup found nothing (about 15
  more lines and one more test for the same result); telling fresh and
  continued spawns apart by reading the issued block's `continue:` (more
  parsing for a case the coordinator's next call fixes anyway); keeping
  `agent=<id>` on boundaries 2, 3 and 5 (rejected by the brief: those
  boundaries move to the agent).

## R6. The hand-back block

- **Decision**: the agent ends its hand-back with step.sh's stdout, every
  line as printed, tabs included, in one block fenced with four backticks
  (step.sh can print a report line holding three). The coordinator takes a
  block as parsed when its first line is a verdict step.sh prints
  (`soft`, `hard:`, `reformat`, `stop:`, `step: error:`) and its last line
  starts `boundary:` or `answer call:` followed by a tab, or `done:`, or
  the block is the one `step: error:` line. Anything else, a `step:
  usage:` line, or no block is a slip: the coordinator makes that
  boundary's call itself. The block is only ever a copy of the agent's
  Bash result: a refused, failed or unrun call gives no block and a word
  on the digest's last line. A block that ends with `done:` gets the
  coordinator's own check (R13).
- **Rationale**: FR-007. Every output of a boundary call ends with one of
  those three lines (the goldens: hard and override-able soft with
  `answer call:`, soft and reformat with `boundary:`, `done:` after a
  ship or a stop), so a truncated block fails the check. The tab after the
  key is the same test the issued-line definition uses: the coordinator
  takes later call words (`answer call:`, a batch's `boundary:`) from the
  block's lines, and a model that turned the tabs into spaces would pass
  "starts with `boundary:`" and then fail the next call as `step: usage`
  or split a path with a space, with no source left for the words. A
  usage line is the agent's own malformed command, not a decision. A
  well-formed block the agent made up rather than copied is not caught
  here but at the next `step.sh` call (`no boundary is open`, or
  `neither the open boundary…`), so harness.md says a `step: error` at an
  agent's boundary may mean the previous block was not step.sh's.
- **Alternatives considered**: a terminator line in every step.sh output
  (one more line in every output for what the last line already tells);
  signing the output (rejected by the brief).

## R7. The agents' last step

- **Decision**: one section, worded the same in the six agent files,
  placed just before the report format ("Report, and nothing else"), so
  the prompt still ends with the format (constitution IV). It runs only
  when the request gave a `boundary:` key, so the implementer in rebase
  mode and `/feat rebase`'s spawns are untouched. Text in
  [contracts/prompts.md](contracts/prompts.md#agents).
- **Rationale**: FR-001, FR-003, FR-004, FR-006. "End with" in FR-006 is
  the agent's last action; constitution IV fixes where the prompt ends.
- **Alternatives considered**: a section after the format block (breaks
  IV); a lint grep for the wording (rejected by the brief).

## R8. Coordinator chores

- **Decision**:
  - Log lines the coordinator chains before a boundary call today (a
    preflight `flag:`, `[!] brief left in place: …`, a failed board move's
    `[!]` line) are chained (`S log … &&`) before its next own `T` call: an
    answer call, a reviewer batch call, a slip-fallback call or the
    `done:` check (R13). A run that ends on an own call's output with such
    a line still pending logs it with one `S log` call in the final turn.
  - Deleting the brief after phase 2 and the review move are tool calls in
    the response that acts on the hand-back (with the next spawn, or with
    the gate message when the verdict is hard).
  - `/fix`'s issue creation and building move after a passed assess gate
    stay where they are: between the hand-back and the implementer's
    spawn, no agent running.
  - The user's `size <s>` while an agent runs waits for its hand-back and
    is made before the next spawn.
  - step.sh backs that timing rule (FR-022): `load_state` takes the state
    file's `git hash-object` (`git -C <state file dir> hash-object
    --no-filters`) before `read_state`; `commit` hashes it again before
    its first write and, when the two differ, dies `the state file
    changed since step.sh read it; call again` with nothing written by
    the decision (the error's own `- [!] step:` line is logged as for any
    error). Before `commit`, step.sh only runs state.sh's read-only
    queries and its `reports/` writers, so its own run never changes the
    file between the two hashes.
- **Rationale**: FR-013, FR-014, FR-022. The state file has two writers
  that may now run at once: the agent's `step.sh` call and any coordinator
  `S` or `T` call. Every write of the coordinator's should happen while no
  agent of this run is running; the brief's threat is slips, and a slip
  here (a `size` or `S log` mid-spawn, a `/feat resume` in a second
  session while a background agent still runs) would be a lost update:
  the Log or `Current phase` loses the agent's decision while the record
  says it was decided. The hash compare turns that into a `step: error`
  the user sees, and the retry decides on the new state. Hashing before
  the read fails safe: a write between the hash and the read is reported
  too. The window left is the milliseconds between the second hash and
  the end of `commit`, and a state.sh writer's own read-to-`mv` window.
  The size waits because its call is the one coordinator write a user can
  trigger mid-spawn; as today, a size applies from the next boundary's
  spawns.
- **Alternatives considered**: a `mkdir` lock on `<state file>.lock` in
  step.sh's `commit` and state.sh's writers (closes the last window too,
  but adds a lock's life cycle: stale locks after a kill, a busy error in
  every writer, their tests; chosen against at the design gate); no check
  (the prompt rule alone, silent on a slip); `S log` in the same response
  as the spawn (the spec puts log lines on the next own call).

## R9. Reviewer batches, `rebase`, moves

- **Decision**: unchanged: reviewer batches (`/feat` 4, 7, 7e; `/fix` 4)
  and `rebase` keep the coordinator's call (FR-015); a rebase-mode spawn
  printed by the base check or a ship conflict (`move`, `repair`) carries
  no `boundary:` key, so the coordinator makes its call as today.
- **Rationale**: the spec's boundary list names neither moves nor
  repairs; a move's `undone` gate and its `read:` are the coordinator's
  already.

## R10. Permissions, dependencies, exposure

- **Decision**: no new dependency, service or permission. The agents run
  one more `bash '<script>' …` from the skill's `scripts/`, as the
  implementer, the assessor and the shipper already do (`trail.sh`,
  `ship.sh`); the base check's `git fetch` moves from the coordinator's
  Bash to the agent's, in the same session and settings.
- **Size trigger**: none.

## R11. Tests and goldens

- **Decision**: `UPDATE=1 bash tests/step/run.sh` regenerates every spawn
  golden (two new keys per agent-run block; `agent=<id>` gone from the
  boundary lines of 2, 3 and 5); cases that pass `agent=<id>` on boundaries
  2, 3 and 5 drop it, and `full_go`'s placeholder substitution goes. New
  cases, one per FR-020 item, are listed in
  [contracts/step-cli.md](contracts/step-cli.md#tests). Each new case
  starts with `setup` or a first call, so a record exists; the existing
  single-call cases keep exercising the no-record path. The failed record
  write uses the existing `fail_once` wrapper (`fail_once 'record:*'`);
  the changed state file uses the same kind of wrapper, which runs a real
  `state.sh log` on the state file before passing the decision's
  `report-path` call through. tests/state gets one `record` case beside
  the `inputs` one.
- **Rationale**: the goldens are reviewed with `git diff
  tests/step/expected`; the new cases follow the existing `new_case`,
  `put`, `run`, `call_line`, `check` pattern.

## R12. Documents and diagrams

- **Decision**: `docs/workflow.md`: the `/feat` coordinator's role
  paragraph and a short walk-through of a small run, call by call; in the
  `/fix` section, the Roles Coordinator bullet ("As in `/feat`, it holds
  the gates `step.sh` decides …") and the phase 1 text, which say who
  calls `step.sh` the same way; `docs/design.md`: the
  sentence saying both coordinators call step.sh at each boundary.
  `gates.d2` (who calls step.sh: the agents at sequential boundaries, the
  coordinator at reviewer batches, answers, setup and the `done:` check)
  and its render
  change; `chain.d2` stays: it draws what is checked before what, and no
  phase or gate changes.
- **Rationale**: FR-019 asks for the diagrams to follow any change to
  phases or gates; `gates.d2` also draws the calls, which change.

## R13. The `done:` check

- **Decision**: when a hand-back's block ends with `done:` (the
  shipper's, in either skill), the coordinator makes that boundary's call
  itself before the final message: the words of the `boundary:` line
  printed with the shipper's spawn, chained after any pending `S log`
  (`S log … && T …`), in the final turn it makes anyway. Its own output
  decides: the same `done:` (a re-print, R3) gives the final message;
  anything else is acted on as usual (a decision when the block was made
  up and the boundary is still open, a `step: error` when it is neither
  open nor re-printable). No change in step.sh: the re-print already
  covers it, including a renumbered artifact dir (`main` finds the moved
  state file from the report path, and the record moved with
  `reports/`).
- **Rationale**: FR-002, Assumptions. Every other verdict is checked by
  the next `step.sh` call; `done:` has no next call, so a made-up `done:
  PR #N` would end the run with no PR and the fail-closed check never
  run. The check costs one coordinator call per run, which the final turn
  already makes when a log line is pending.
- **Alternatives considered**: listing a made-up `done:` as an accepted
  risk next to a wrong model or effort (chosen against at the design
  gate: it ends the run, unlike a wrong model); keeping the shipper's
  boundary coordinator-run (an exception in the agent files and
  coordinators the spec rules out).
