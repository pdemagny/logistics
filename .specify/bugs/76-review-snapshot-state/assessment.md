# Bug Assessment: Review gate goes hard when the coordinator logs to the state file during a review

- **Slug**: 76-review-snapshot-state
- **Created**: 2026-11-23
- **Source**: pasted text (GitHub issue pdemagny/logistics#76, fetched with `gh issue view` by the orchestrator)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

pdemagny/logistics#76, "Review gate goes hard when the coordinator logs a board move during the review".

On the `/fix` run for #73, phase 4 Code review, `step.sh` printed `hard:` with `- files changed outside the reports` and `- changed: .specify/bugs/73-review-none-finding/feat-state.md`. The reviewer changed no file but its report; the change was the coordinator's `S log … '- [x] tracker: #73 set to "In review"'` on the boundary call, after `step.sh` had taken the reviewers' snapshot. The harness requires `S log '- [!] <line>'` when a board move fails, and the review move runs exactly while the snapshot is open, so a failed review move always hardens the review gate (`/fix` phase 4, `/feat` phase 7), blaming nothing the reviewers did. Expected: the snapshot check ignores the state file (only `state.sh` and `step.sh` write it), with a `tests/step` case where a state-file log line added between the review spawn and its boundary keeps the gate soft.

## Symptom

Any write to the run's state file (`feat-state.md`) between a reviewer batch's `state.sh snapshot` and the boundary's `state.sh unchanged` makes `step.sh`'s review gate hard with "files changed outside the reports", even though no reviewer wrote anything but its report. Expected: state-file changes are not counted, so the gate stays soft.

## Reproduction

Reproduced with a scratch script (under the system temp dir) against the repo's `state.sh`, no source changed:

1. `git init` a scratch repo, copy `tests/state/fixtures/feat-soft-review.md` to `specs/x/feat-state.md`, commit.
2. `state.sh snapshot specs/x/feat-state.md` → token `e69de29bb2d1`.
3. `state.sh log specs/x/feat-state.md '- [x] tracker: #73 set to "In review"'` (what the coordinator does on the review move).
4. `state.sh unchanged specs/x/feat-state.md e69de29bb2d1` prints:

```
changed
- specs/x/feat-state.md
```

`step.sh`'s `snap_check` turns that output into `reason 'files changed outside the reports'` and `reason "changed: specs/x/feat-state.md"`, i.e. a hard gate. The existing `tests/state/run.sh` case "unchanged: edit to a modified file, new file, deleted file" asserts this very output (`run log "$sf" '- [x] 7 Code review — written by a reviewer'` → `changed` / `- specs/x/feat-state.md`), so today's behaviour is tested, not accidental.

## Suspected Code Paths

- `.apm/skills/feat/scripts/state.sh:manifest()` (~line 960) — builds the snapshot manifest from `git status`, leaving out only ignored files and `EX` (the state file dir's `reports/`); the state file itself is included, so any log line changes the token.
- `.apm/skills/feat/scripts/state.sh:snap_setup()` (~line 944) — computes `TOP` and `EX`; the natural place to also compute the state file's path relative to `TOP`.
- `.apm/skills/feat/scripts/state.sh:cmd_unchanged()` (~line 1024) — compares tokens and lists differing paths; inherits the manifest's scope.
- `.apm/skills/feat/scripts/step.sh:snap_check()` (~line 2505) — turns `changed` into the hard reasons `files changed outside the reports` / `changed: <path>`; used by both `/fix` phase 4 and `/feat` phase 7 boundaries (`snapshot=` on the boundary line, lines ~1784 and ~2579).
- `tests/state/run.sh` (~line 796) — the case asserting a state-file log is reported as changed.
- `tests/step/run.sh` (~line 1449, `medium7` "a file changed outside the reports") — the place for the new soft-gate case.

## Root Cause Hypothesis

The snapshot manifest covers the whole worktree except `reports/` and ignored files, so it includes the state file, which the coordinator legitimately writes (via `state.sh log`, notably the harness-required `- [!]` line for a failed review board move, and the review-move log) while the reviewer batch is open. The snapshot thus attributes coordinator writes to the reviewers. Confidence: high (reproduced; the code path is direct).

## Proposed Remediation

**Preferred**: in `state.sh`, leave the state file out of the manifest, like `reports/`: `snap_setup` also sets the state file's path relative to `TOP` (e.g. `SX`), and `manifest()` skips the record whose path equals it. Both `snapshot` and `unchanged` then ignore state-file changes, so `step.sh`'s `snap_check` needs no change and the fix covers `/fix` phase 4 and `/feat` phase 7 alike. Update the header comment of `snapshot`/`unchanged` and the docs sentence that says "any other change to the worktree is a hard gate" (`docs/workflow.md` ~line 76, and `docs/design.md` ~line 75 if it needs it) to say the state file is left out.

**Alternatives**:
- Filter the state file in `step.sh`'s `snap_check` (drop `changed: <state file>` and treat a list with only it as unchanged) — keeps `state.sh unchanged` strict but splits the rule across two scripts and leaves the token mismatch to special-case.
- Accept only appended `## Log` lines in the state file (compare the old manifest's blob with the new content) — keeps catching a reviewer that rewrites other state fields, but needs blob retrieval and line diffing in Bash 3.2; much more code for a guard the reviewers' instructions already cover.

**Files likely to change**:
- `.apm/skills/feat/scripts/state.sh`
- `tests/state/run.sh`
- `tests/step/run.sh` (plus a new `tests/step/expected/<case>.out`/`.log` pair if the case uses `check`)
- `docs/workflow.md` (and possibly `docs/design.md`)

**Tests to add or update**:
- `tests/state/run.sh`: flip the existing case so a `state.sh log` between `snapshot` and `unchanged` yields `unchanged`; keep a non-state-file change in the same window still reported.
- `tests/step/run.sh`: a `medium7` (and ideally a `/fix` phase 4) case where a state-file log line is added between the review spawn and its boundary call, expecting the soft gate, not `hard:`.

## Risks & Considerations

- Loosens the read-only-reviewer guard: a reviewer that wrote the state file (e.g. via `state.sh log`/`set`) would no longer be caught by the snapshot. Reviewers are told to write only their report; the state file is the coordinator's and `step.sh`'s, and the report owner asked for exactly this trade.
- The state file is tracked in some runs and untracked in others (bug dirs are untracked at first); the skip must match on the path relative to `TOP` either way.
- Bash 3.2, no jq/Python, shellcheck clean; `mise run lint`, `mise run test:state` and `mise run test:step` are the checks.

## Open Questions

- Should the snapshot ignore every state-file change, or only appended log lines? Recommended: every change (the report's expected behaviour; simplest; reviewers are instructed not to touch it).
