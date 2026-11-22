# Feature Specification: Script the ship

**Feature Branch**: `ship-script`

**Created**: 2026-11-22

**Status**: Draft

**Input**: User description: "Script the ship: `ship.sh` runs the shipper's git and gh steps in all three modes" (brief `specs/briefs/ship-script.md`, issue #57)

## Overview

The shipper is the phase that turns a finished run into a pull request: `/feat` phase 8, `/fix` phase 5, and rebase mode in both. It has the least judgement of any agent, yet a small model must follow about 150 lines of git prose correctly every time. This feature moves every mechanical step into one tested script, so the model keeps only the work that needs a model: updating docs, writing the notes file, running the project's checks and fixing failures. The aim is reliability by construction, not token or time savings; no shipper misfire has been seen.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ship a feature through the script (Priority: P1)

A maintainer finishes a `/feat` run. The shipper updates the docs, writes the notes file, and calls the script twice: `prepare` numbers the spec directory, stages by path, scans for secrets, commits, and rebases onto the default branch; after the model has run the checks, `publish` rechecks the number, runs the WIP check and the range secret scan, pushes, and opens the PR.

**Why this priority**: It is the main path and the one with the most steps (numbering, renumbering, fixup and autosquash). Without it the feature delivers nothing.

**Independent Test**: In a throwaway repository with a fake `gh`, run `prepare` then `publish` in ship mode with a notes file and a state file. Verify the commits, their order, the pushed branch, the PR body and the report lines.

**Acceptance Scenarios**:

1. **Given** a worktree with changes and a notes file listing two commits with their paths, **When** `prepare` runs in ship mode, **Then** the spec directory is numbered, each commit contains exactly its listed paths, the branch is rebased onto the default branch, and a handoff file is written next to the notes.
2. **Given** a successful `prepare`, **When** `publish` runs, **Then** the number is rechecked, the WIP check and range secret scan pass, the branch is pushed, a PR is opened, and the output has `PR: <url>`, `Commits:`, `Left uncommitted:`, `Docs updated:`, `Wrote:` and `Not verified:`.
3. **Given** another run took the same number on the default branch while this one was in flight, **When** `publish` rechecks, **Then** the spec directory is renumbered with a fixup and autosquash, and the pushed history has the new number everywhere.
4. **Given** a state file with an `Issue:` line, **When** the PR is opened, **Then** its body holds the model's Why and Behaviour, the code review part, the points to look at, `Not verified` (implementers' items, then the model's, or `none`), the numbered state-file link, and `Closes <issue>`.

---

### User Story 2 - Ship a bugfix through the script (Priority: P2)

A maintainer finishes a `/fix` run. The same two calls run in fix mode: no numbering, one `fix(...)` commit, the secret scan before committing, and a PR body built from the model's summary and the shipped verdict, ending with `Fixes <ref>`.

**Why this priority**: Same machinery as P1 with fewer steps; it extends the script to the second coordinator.

**Independent Test**: Run both calls in fix mode in a throwaway repository with a fake `gh`; check the single commit, the body's verdict and the `Fixes` line.

**Acceptance Scenarios**:

1. **Given** a fix-mode notes file with one commit, **When** `prepare` and `publish` run, **Then** the spec directory is not numbered, one commit is made, and the PR body holds the symptom, root cause, fix and verdict from the model's summary plus the shipped verdict as the state tool prints it.
2. **Given** a state file `Issue:` ref, **When** the PR is opened, **Then** the body ends with `Fixes <ref>`, not `Closes`.
3. **Given** a security bug, **When** `prepare` runs, **Then** the secret scan still runs before anything is committed.

---

### User Story 3 - Move a PR through rebase mode (Priority: P2)

After the base moved, a rebase-mode run commits the move's check fixes and the Log lines, rebases, scans the range, and pushes with a lease. If the push is refused, the script resets to the lease. It edits the PR body under `### Rebases`.

**Why this priority**: The riskiest prose (force-with-lease, reset to the lease) is in this mode; scripting it is the main reliability gain, but runs are rare.

**Independent Test**: In a throwaway repository with an existing branch, a lease value and a fake `gh`, run both calls in rebase mode; check the lease push, the refused-push reset and the edited body.

**Acceptance Scenarios**:

1. **Given** check-fix paths and a check-fix subject in the notes, **When** `prepare` runs in rebase mode, **Then** the check-fix commit is made, then the Log commit (`docs(specs): log rebase onto <sha>`, after the state tool restores the phase), then the rebase.
2. **Given** a successful `prepare`, **When** `publish` runs, **Then** the push uses a lease on the branch and the recorded lease value, and the PR body gets the PR note under `### Rebases`.
3. **Given** the lease push is refused, **When** `publish` runs, **Then** the branch is reset to the lease, `PR: blocked` is reported with its single `!` line, and nothing else is pushed.
4. **Given** a project check fails after `prepare` in rebase mode, **When** the shipper goes on, **Then** it fixes nothing: the failure is listed under the shipper's `Not verified:` as `n/a → <check> → <why>`, and nothing is committed after `prepare`.
5. **Given** a `--pr` URL whose head branch is not the run's branch, or whose repository is not the current one, **When** `publish` runs, **Then** it reports `PR: blocked` before the push and edits no PR body.

---

### User Story 4 - Blocked and conflicted ships stop cleanly (Priority: P1)

Whenever a precondition fails, the script stops without leaving a half-shipped state, and says so in the shipper's report format.

**Why this priority**: The value of scripting is that failures are handled the same way every time; the safety rules must hold from the first release.

**Independent Test**: One throwaway-repository test per cause: spec number error, secret scan match, secret scan failure, WIP commit, refused push, closing keyword in a commit, missing handoff file, conflict in ship mode, conflict in rebase mode.

**Acceptance Scenarios**:

1. **Given** any `PR: blocked` cause during `prepare`, **When** it is hit, **Then** nothing stays committed, whatever was staged is unstaged, and nothing is pushed.
2. **Given** a commit message holding a closing keyword (`Closes`, `Fixes`, …), **When** the notes are checked, **Then** the script reports `PR: blocked` before staging anything.
3. **Given** `publish` runs and the handoff file is missing, **When** it starts, **Then** it reports `PR: blocked` and pushes nothing.
4. **Given** the rebase hits a conflict, **When** it stops, **Then** the script records the conflicted files, aborts the rebase (in rebase mode also `reset --keep <lease>`), pushes nothing, and prints `PR: conflict` with `Conflicts:`. It never resolves a conflict.
5. **Given** the notes name `reports/` paths, **When** `prepare` runs, **Then** `reports/` is never staged.
6. **Given** a changed file no commit claims, **When** the report is printed, **Then** it appears on `Left uncommitted:`.
7. **Given** a rebase that exits 0 but whose autostash pop conflicts, **When** the script checks the tree, **Then** it prints `PR: conflict` with the conflicted files, leaves the stash in place, and pushes nothing.
8. **Given** a commit message, the assembled PR body or the edited rebase-mode body matches a secret rule, **When** the script checks it (the messages in the notes check, the body before the push), **Then** it reports `PR: blocked` naming the commit or the PR body and the rule, never the value, and pushes nothing.
9. **Given** the branch to push is the default branch, **When** either call starts, **Then** it stops as a usage error and does nothing.
10. **Given** a notes, report or not-verified path outside the artifact dir's `reports/`, a symlinked `reports/`, `.gitignore` or target file, **When** either call starts, **Then** it refuses before writing anything.
11. **Given** `publish` stopped `PR: blocked` after it changed HEAD (fixups, renumber), **When** `publish` runs again, **Then** it starts from the recorded HEAD instead of refusing.

---

### User Story 5 - Fall back to one command when git or gh is blocked (Priority: P3)

When git or gh is blocked in the session, the shipper offers the user one `!` line in ship and fix mode that runs both calls. Rebase mode offers no command, since it would be a force-push.

**Why this priority**: A rare path, made rarer because a call to the script does not name git.

**Independent Test**: Produce the fallback line for ship and fix mode and run it; for rebase mode check that none is offered.

**Acceptance Scenarios**:

1. **Given** git or gh is blocked in ship or fix mode, **When** the shipper reports `PR: blocked`, **Then** its single `!` line is `! cd '<worktree>' && bash '<ship.sh>' prepare … && bash '<ship.sh>' publish …`, and the checks the agent ran before count for it.
2. **Given** rebase mode, **When** git or gh is blocked, **Then** no command is offered.
3. **Given** an implementer's not-verified item holding `'`, `$(…)` or a backtick, **When** the fallback line is built and run, **Then** the line holds only paths and fixed words (the items go by file), runs as written, and nothing in an item is evaluated.

---

### User Story 6 - A slimmer shipper agent and unchanged coordinators (Priority: P2)

The shipper agent file loses the prose for every step the script runs and keeps the docs step, the notes file, the checks, the two calls and the report. The coordinator's parser and the report format do not change.

**Why this priority**: The agent change is what makes the small model's job simple; it depends on P1 to P3.

**Independent Test**: The step tool's parser run on each mode's script output matches the existing shipper fixtures; the packaging test confirms the script ships.

**Acceptance Scenarios**:

1. **Given** each mode's script output, **When** the step tool parses it, **Then** it produces the same digest as on the existing shipper fixtures, with no parser change.
2. **Given** the packaged distributions, **When** the package test runs, **Then** it confirms the script is included.
3. **Given** the spawn inputs and harness values, **When** a ship is spawned, **Then** the script path is passed, and the agent, the step tool's spawn inputs, the harness values and the step tests changed together.

---

### Edge Cases

- The notes file is malformed (missing key, `Commit:` with no paths, unknown key): `PR: blocked` before anything is staged.
- A listed path does not exist or has no change: reported as blocked or left out of the commit, never staged blindly.
- A secret scan fails to run (not only a match): treated as blocked.
- A WIP commit is found in the range at `publish`: blocked, nothing pushed.
- The default branch has a conflicting change during the number recheck's rebase: `PR: conflict`.
- `gh pr create` fails after a successful push: reported as blocked with the PR not opened.
- `prepare` re-run after a partial failure: it must not double-commit (the earlier state was cleaned up by the blocked rule).
- The state file has no `Issue:` line: the closing line is left out; no empty keyword.
- A model-written commit subject names a closing keyword in any case or form: refused.
- A check-fix commit added by `publish` (ship, fix) comes after the main change in the notes: the PR title stays the last subject `prepare` committed.
- A file outside the PR names the old spec path when `publish` renumbers: it is left unchanged and listed for the user.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide one script with two subcommands, `prepare` and `publish`, over three modes (`ship`, `fix`, `rebase`), invoked as `ship.sh <prepare|publish> <ship|fix|rebase> …`. The exact flags are the plan's call.
- **FR-002**: The script MUST take as arguments the values the shipper is given today: worktree, default branch, state file, notes file, the numbering, secret-scan and state tool paths, and by mode `Security bug`, branch, PR URL, lease, check-fix paths and the PR note; the implementers' not-verified items come as the path of a file (FR-016). It MUST read the rest (spec directory, issue ref) from the state file.
- **FR-003**: The script MUST call the existing numbering, secret-scan and state tools rather than redo their work.
- **FR-004**: `prepare` MUST check the notes before staging anything; in ship mode it numbers the spec directory, then it stages by path from the notes, runs the secret scan, commits, fetches and rebases onto `origin/<default>`. In rebase mode it commits the check fixes and the Log lines first.
- **FR-005**: Any `PR: blocked` during `prepare` MUST leave nothing committed, unstage what was staged, and push nothing.
- **FR-006**: `prepare` MUST write a handoff file next to the notes under `reports/` holding the number it gave, the lease and the commits made. `publish` MUST read it and, when it is missing, report `PR: blocked` and push nothing. Whenever `publish` changes HEAD it MUST record the new HEAD in the handoff, so a `publish` run again after a block starts from there.
- **FR-007**: `publish` MUST recheck the number (renumbering with fixup and autosquash when it differs), run the WIP check and the range secret scan, push, and open the PR through `gh pr create` with a body assembled from the state file and the notes. A renumber MUST rewrite the old path only in the artifact dir, `.specify/feature.json` and the files the PR already changes; any other file naming the old path is left unchanged and listed on `Left uncommitted:` and under the points to look at. The PR is never a draft; its title is the last subject `prepare` committed (from the handoff), never one `publish` added.
- **FR-008**: In rebase mode `publish` MUST check, before the push, that the `--pr` URL's head branch is the run's branch and its repository the current one (`PR: blocked` otherwise); push with a lease on the branch and the recorded lease value, reset to the lease when the push is refused, and edit the PR body under `### Rebases` with the PR note the spawn gets. In rebase mode the shipper fixes no failing check: a failure goes under its `Not verified:` as `n/a → <check> → <why>`, and nothing is committed after `prepare`.
- **FR-009**: The notes file MUST have fixed keys: `Commit: <subject>` each followed by its paths (`- <path>`) and an optional body; `Docs:`, `Summary:`, `Points to look at:` and the model's own `Not verified:` items. The model writes every commit subject and decides the split; the script MUST take no convention options and check no subject format.
- **FR-010**: In rebase mode the notes MUST carry only the check-fix commit's subject. The Log commit is fixed in the script: restore the phase through the state tool, then `docs(specs): log rebase onto <sha>`.
- **FR-011**: The PR body MUST hold the model's `Summary:` prose (Why and Behaviour for ship mode; symptom, root cause, fix, and verdict with its checks for fix mode), the `### Code review` part as the state tool prints it, the shipped verdict as the state tool prints it (fix mode), `Not verified` (implementers' items, then the model's, or `none`), the points to look at, the numbered state-file link, and `Closes <issue>` (ship mode) or `Fixes <ref>` (fix mode) from the state file's `Issue:` line.
- **FR-012**: The script MUST stage by path and never run `git add -A`; never stage `reports/`; refuse a closing keyword (`Closes`, `Fixes`, …) in a commit message; never merge; never force-push outside rebase mode's lease; never push the default branch (a branch equal to the default branch is a usage error in every mode, before anything is done).
- **FR-013**: Any changed file no commit claims MUST be listed on `Left uncommitted:`.
- **FR-014**: On a conflict the script MUST record the conflicted files, abort the rebase (in rebase mode also `reset --keep <lease>`), push nothing, and print `PR: conflict` with `Conflicts:`. It MUST NOT resolve a conflict. A rebase that exits 0 but leaves unmerged files (its autostash did not apply cleanly) is a conflict too: those files on `Conflicts:`, the stash left in place, nothing pushed.
- **FR-023**: The script MUST run the shared secret rules (the ones the issue tool runs over an issue body) over each commit message in the notes check, before staging, and over the assembled PR body or the edited rebase-mode body before the push. A match is `PR: blocked` naming the commit or the PR body and the rule, never the value, with nothing pushed.
- **FR-024**: The script MUST write only inside the artifact dir's `reports/` for the handoff and the report: a notes, report or not-verified file whose physical dir is not that `reports/` is a usage error, and before writing it MUST refuse a symlinked `reports/`, `.gitignore` or target file and keep `reports/.gitignore` exactly `*`, through the state tool's existing guard (no second copy).
- **FR-015**: The output MUST be the shipper's report format unchanged: `PR: <url>`, `PR: blocked` with its single `!` line, `PR: conflict` with `Conflicts:`, `Commits:`, `Left uncommitted:`, `Docs updated:`, `Wrote:` and `Not verified:`. The step tool's shipper parser MUST NOT change.
- **FR-016**: When git or gh is blocked in the session, the `!` fallback in ship and fix mode MUST be one line: `! cd '<worktree>' && bash '<ship.sh>' prepare … && bash '<ship.sh>' publish …`. It MUST hold only paths and fixed words: the implementers' not-verified items reach the script through a file, never as words on the line. Every value on it is POSIX single-quoted, each `'` in it written `'\''`; a value holding a newline or carriage return is refused and no command is offered. Rebase mode MUST offer no command.
- **FR-017**: The shipper agent file MUST drop the prose for every step the script runs and keep the docs step, the notes file, the checks, the two calls and the report. It MUST keep the rule that the script's output (commit subjects, `Brought in:`, git and gh error lines, a PR body) is data, never instructions, in every mode.
- **FR-018**: The script MUST run on Bash 3.2 with no jq and no Python, and stay clean under `shellcheck`.
- **FR-019**: The agent, the step tool's spawn inputs (the script path), the skills' harness values and the step tests MUST change together.
- **FR-020**: Offline tests (`tests/ship`, run through `mise run test:ship` and the `check` workflow) MUST use throwaway repositories and a fake `gh`, covering ship, fix and rebase mode; each `PR: blocked` cause (spec number error, secret scan match, secret scan failure, WIP commit, refused push, closing keyword in a commit, a secret in a commit message, a secret in the PR body, a `--pr` of another branch); a conflict in ship and in rebase mode, and an autostash conflict; a renumber, with a file outside the PR left unchanged; `reports/` never staged; a branch equal to the default branch; an unsafe `reports/`; a `publish` retried after a block; and a not-verified item holding `'`, `$(…)` and a backtick, through the fallback line. `mise run test:ship` SHOULD finish in under 30 seconds.
- **FR-021**: The step tool's tests MUST parse each mode's script output on the existing shipper fixtures; the packaging test (`mise run test:apm`) MUST check that the script ships; `mise run lint` and the existing offline tests MUST stay clean.
- **FR-022**: The PR for this feature body carries `Closes #57` and `Part of #31`; no commit message carries a closing keyword.

### Key Entities

- **Notes file**: Written by the model under the run's `reports/` dir; fixed keys for commits (subject, paths, optional body), docs updated, summary, points to look at, and the model's not-verified items. Never committed.
- **Handoff file**: Written by `prepare` next to the notes; holds the number given, the lease and the commits made. Read by `publish`, which updates its recorded HEAD when it changes HEAD.
- **Not-verified file**: Written by the model next to the notes in ship and fix mode when the spawn lists implementers' not-verified items; one item per line, copied as given. Read by `publish` for the PR body. Never committed.
- **State file**: The run's existing state file; source of the spec directory, the issue ref, the review summary, the verdict and the implementers' not-verified items.
- **Shipper report**: The existing output format the step tool parses.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All numbering, secret scan, commit, rebase, number recheck, WIP check, push and PR steps of the three modes run in the script; none of their prose remains in the shipper agent file.
- **SC-002**: Every blocked cause listed in FR-020, plus a missing handoff file, ends with nothing committed (in `prepare`) and nothing pushed, in 100% of the offline test cases.
- **SC-003**: In every test, `reports/` is never staged and no commit message holds a closing keyword.
- **SC-004**: The step tool parses the script's output for all three modes on the existing shipper fixtures with no parser change and no fixture change.
- **SC-005**: The new offline tests, the packaging test, lint and the existing offline tests pass in the `check` workflow with `shellcheck` clean.
- **SC-006**: The shipper agent file is shorter than today's 252 lines and holds no step-by-step git instructions.

## Assumptions

1. The skills installed in the main checkout run the current shipper, so the `/feat` run that builds this ships with the old agent; this is expected, not a defect. (recommended: keep as written)
2. Conflict resolution stays with the rebase-mode implementer (`references/move.md`); the script only reports. (recommended: keep as written)
3. The numbering, secret-scan and state tools keep their current interfaces; the script only calls them. (recommended: keep as written)
4. No commit-convention checks (subject format) are added, since conventions vary by project. (recommended: keep as written)
5. Issue #2 (long ship times) stays open; no token or time savings are claimed. (recommended: keep as written)
6. When the state file has no `Issue:` line, the closing line is omitted. (recommended: keep as written)
7. The PR is never a draft (today's "draft if the conventions say so" goes, as a convention option FR-009 refuses); its title is the last subject `prepare` committed, and the model puts the main change last in the notes. (approved at the plan gate)
