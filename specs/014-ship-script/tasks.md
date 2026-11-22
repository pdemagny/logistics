# Tasks: Script the ship

**Input**: Design documents from `specs/014-ship-script/` (spec.md, plan.md, research.md R1–R18, data-model.md, contracts/ship-cli.md, contracts/agent-and-coordinators.md, quickstart.md)

**Prerequisites**: plan.md, spec.md

**Tests**: Requested (FR-020, FR-021): offline tests in `tests/ship/` with throwaway repositories and a stub `gh`; `tests/step` cases on the script's output. Within each story, write its test cases first and see them fail.

**Organization**: Tasks are grouped by user story. Stories are in priority order (US1, US4 P1; US2, US3, US6 P2; US5 P3). Paths are from the worktree's top level. `ship.sh` is one file, so its tasks run in order; `[P]` marks tasks on other files.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The test harness and the task wiring every later task relies on.

- [X] T001 Create `tests/ship/run.sh`, `tests/ship/bin/gh` and `tests/ship/expected/`: build one template repo plus a bare origin once per run, copy per case (`cp -R`), a case runner with golden compare (`UPDATE=1` rewrites and exits non-zero, as `tests/step/run.sh`), checks on commits, index, origin refs, gh calls and PR body, elapsed-time print (R17); the stub `gh` handles `repo view`, `pr create`, `pr view --json`, `pr edit`, `pr list`/`api`, reading case files from `SHIP_CASE` and logging each call (plan Testing; quickstart section 5)
- [X] T002 [P] Add `[tasks."test:ship"]` (`bash tests/ship/run.sh`) and the `shellcheck tests/ship/run.sh tests/ship/bin/gh` line to the `lint` task in `mise.toml`
- [X] T003 [P] Add `- run: mise run test:ship` after `test:secret-scan` in `.github/workflows/check.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The script's frame: flags, paths, guards, notes parser, handoff, report. No story works without it.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Create `.apm/skills/feat/scripts/ship.sh` (Bash 3.2, no jq, no Python; no `declare -A`, `mapfile`, `${v,,}`, `declare -n`, `[[ -v ]]`, `;;&`, `|&`; `nocasematch` for case-insensitive matching): `ship.sh <prepare|publish> <ship|fix|rebase>`, the long-flag parse of contracts/ship-cli.md (required, refused and repeatable flags by mode, one value without newline or CR), exit 2 with one `ship: usage: …` stderr line, `--worktree` check against `git rev-parse --show-toplevel`, the branch to push equal to `--default` as a usage error in every mode, a rebase or merge in progress as `! ship: a rebase or merge is in progress` (R1; FR-001, FR-002, FR-012)
- [X] T005 In `.apm/skills/feat/scripts/ship.sh` add path resolution and the `reports/` guard: numbered-dir resolution of `--state`, `--notes`, `--not-verified-file`, `--report` (R4), physical-dir check that they sit directly in the artifact dir's `reports/`, `bash <state-script> report-path` as the guard for a symlinked `reports/`, `.gitignore` or target, `reports/.gitignore` kept exactly `*` (no second copy of the guard), then `source` of `--secret-scan` for `secret_rule` with `! secret scan: could not run (cannot source <path>)` on failure (R9, R18; FR-024)
- [X] T006 In `.apm/skills/feat/scripts/ship.sh` add the notes parser and the not-verified file parser exactly as data-model.md "Notes file" and "Not-verified file": the key-line pattern `^(Commit: .+|Body:|Docs:( none)?|Summary:|Points to look at:( none)?|Not verified:( none)?)$`, `Commit:` paths (`- <path>` items, at least one except in rebase mode where the paths are the `--check-fix` flags), subject non-empty and at most 200 characters, duplicate subjects refused, path rules (not absolute, no `..` component, not starting with `-`, no control character), `reports/` paths dropped, each key but `Commit:` at most once, closing keywords refused case-insensitively in subjects and bodies (R11), `secret_rule` over each commit message (`! secret scan: commit <k> matches <rule>`), every failure as `! ship: notes: <reason> (line <n>)` before anything is staged (FR-009, FR-010, FR-023)
- [X] T007 In `.apm/skills/feat/scripts/ship.sh` add the handoff file (written by `prepare` next to the notes with the fixed lines `Mode`, `Base`, `Start`, `Head`, `Number`, `Lease`, `Artifact dir`, `Commits:`; read by `publish`; `Head:` rewritten through temp file and `mv -f` at each HEAD change; the three blocked lines for missing, unreadable and moved) and the report writer: the shipper's report format unchanged (`PR:`, `Command for the user:`, `Conflicts:`, `Commits:`, `Left uncommitted:` from `git status --porcelain -z`, `Docs updated:`, `Wrote:`, `Not verified:`), written to `--report` through the guard and printed, scratch files in the git dir removed on exit (R2, R3; FR-006, FR-013, FR-015)
- [X] T008 [P] Fix `.apm/skills/feat/scripts/secret-scan.sh`: replace `${1,,}` with `shopt -s nocasematch` matching so it runs on Bash 3.2, interface unchanged (R16; FR-018, spec assumption 3)
- [X] T009 Add to `tests/ship/run.sh` the usage and foundation cases: missing flag, a flag refused in the mode, branch equal to `--default` in ship and in rebase mode, `--notes` or `--report` outside `reports/`, symlinked `reports/` and target file, an emptied `reports/.gitignore` put back to `*`; malformed notes (missing key, `Commit:` with no path, unknown key, `Not verified: see below` inside `Summary:` read as text, `Commit:` with a `reports/` path); closing keyword in a subject and in a body; a secret in a subject and in a `Body:` line; missing handoff; the Bash 3.2 construct grep over `ship.sh` and `secret-scan.sh` (FR-020)

**Checkpoint**: The script parses, guards and reports; stories can begin.

---

## Phase 3: User Story 1 - Ship a feature through the script (Priority: P1) MVP

**Goal**: `prepare` then `publish` in ship mode produce the numbered commits, the pushed branch and the PR.

**Independent Test**: In a throwaway repo with the stub `gh`, run both calls in ship mode with a notes file and a state file; check commits, order, pushed branch, PR body and report lines.

- [X] T010 [US1] Add to `tests/ship/run.sh` the ship-mode cases and goldens `ship-pr`, `ship-prepare`: two commits with exactly their paths and order, numbered dir, handoff, push, `gh pr create` args (title is the last `prepare` subject, no `--draft`), body sections in order, `Closes #N` from `Issue:`, no `Issue:` line gives no closing line, a check fix between the calls folded into its commit, a new check-fix `Commit:` added between the calls leaving the title unchanged, a renumber at `publish` (another `specs/NNN-*` on main) with the new path in every pushed commit and a file outside the PR naming the old path left unchanged and listed on `Left uncommitted:` and under the points to look at, `prepare` run twice committing nothing twice, no `Brought in:` in ship output (spec US1 AC 1–4)
- [X] T011 [US1] In `.apm/skills/feat/scripts/ship.sh` implement ship `prepare` numbering: unnumbered artifact dir → `bash <spec-number> next`, `git mv` or `mv`, path rewrite in the artifact dir and `.specify/feature.json` with byte-exact backups so it can be undone (R5)
- [X] T012 [US1] In `.apm/skills/feat/scripts/ship.sh` implement staging and commits (R6): record `Start`, `git reset -q`, per notes commit `git add -- <paths>` only (never `-A`, `.`, `-u` or a glob), unstage `reports/`, `bash <secret-scan> staged`, `git commit -F` from a file in the git dir with no attribution line, `--fixup` for a subject already committed, `! ship: nothing to commit` (FR-004, FR-012)
- [X] T013 [US1] In `.apm/skills/feat/scripts/ship.sh` implement fetch and rebase: `git fetch origin <default>`, `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash --autostash origin/<default>`, the unmerged-files check after every rebase that exits 0 (R7, R12), the handoff with `Commits:` in notes order, prepare's output (`Prepared:`, `Notes:`, `Commits:`, `Left uncommitted:`)
- [X] T014 [US1] In `.apm/skills/feat/scripts/ship.sh` implement ship `publish` before the push: handoff checks, notes and not-verified file parsed again, fold check fixes as `--fixup` commits or new commits (R7), `bash <spec-number> check <default> <dir name>` with `keep` or `renumber MMM` (renumber limited to the artifact dir, `.specify/feature.json` and files the PR already changes, with fixups, R8), one autosquash onto the recorded `Base`, `Head:` rewritten at each HEAD change (FR-006, FR-007)
- [X] T015 [US1] In `.apm/skills/feat/scripts/ship.sh` implement ship `publish` finish: WIP check, `bash <secret-scan> range <Base> HEAD` (R9), the PR body of data-model.md (Summary, `### Code review` from `state.sh review-summary <state> 7`, points to look at, `### Not verified` implementers' then model's items or `none`, numbered state-file link from `gh repo view`, `Closes <issue>` only for a valid `Issue:` ref), `secret_rule` over the body, `git push -u origin <branch>`, `gh pr create --body-file` titled from the handoff and never a draft, the report with `PR: <url>` (R10; FR-007, FR-011, FR-023)

**Checkpoint**: Ship mode ships end to end; T010 cases pass.

---

## Phase 4: User Story 4 - Blocked and conflicted ships stop cleanly (Priority: P1)

**Goal**: Every failed precondition stops without a half-shipped state and says so in the report format.

**Independent Test**: One throwaway-repo test per cause, each checking no new commit, empty index, dir back unnumbered (prepare), origin unchanged, and no `!` line holding a secret's value.

- [X] T016 [US4] Add to `tests/ship/run.sh` the stop cases and goldens `ship-blocked`, `ship-conflict`: spec-number error, secret scan match, secret scan that cannot run, secret in the PR body (from `Summary:`), WIP commit, refused push (ship), conflict in ship mode, autostash conflict (`PR: conflict`, stash kept), `reports/` paths never staged, an unclaimed file on `Left uncommitted:`, `gh pr create` failing after the push then `publish` again opening the PR, `publish` retried after a block starting from the recorded HEAD (spec US4 AC 1–11; FR-020)
- [X] T017 [US4] In `.apm/skills/feat/scripts/ship.sh` implement the prepare block path: any `PR: blocked` in `prepare` runs `git reset -q <Start>`, undoes the numbering from its backups, pushes nothing, writes and prints the report, exit 1 (FR-005, R5, R6)
- [X] T018 [US4] In `.apm/skills/feat/scripts/ship.sh` implement conflicts (R12): record `git diff --name-only --diff-filter=U`, `git rebase --abort` (rebase mode adds `git reset --keep <lease>`), print `PR: conflict` with `Conflicts:`, never resolve; an exit-0 rebase leaving unmerged files is the autostash case: files on `Conflicts:`, stash left, no abort, nothing pushed (FR-014)
- [X] T019 [US4] In `.apm/skills/feat/scripts/ship.sh` implement the publish block path and blocked-line table of data-model.md ("Blocked lines": WIP, refused push, gh failures, secret in PR body, handoff lines): nothing pushed on a block before the push, commits kept and `Head:` matching HEAD so `publish` can run again, a `gh pr create` failure after the push retried without a second push, first error line only on any `!` line (R3, R10; FR-005, FR-012)

**Checkpoint**: US1 and US4 together are the MVP; all T009, T010 and T016 cases pass.

---

## Phase 5: User Story 2 - Ship a bugfix through the script (Priority: P2)

**Goal**: The same two calls in fix mode: no numbering, one `fix(...)` commit, `Fixes <ref>`.

**Independent Test**: Both calls in fix mode in a throwaway repo with the stub `gh`; check the single commit, the body's verdict and the `Fixes` line.

- [X] T020 [US2] Add to `tests/ship/run.sh` the fix-mode cases and golden `fix-pr`: one `fix(...)` commit, bug dir not numbered, `**Shipped verdict:**` line as `state.sh shipped-verdict` prints it (with the user-decision suffix when not `verified`), `Fixes <ref>` and never `Closes`, `--security-bug yes` with a secret staged → blocked before any commit (spec US2 AC 1–3)
- [X] T021 [US2] In `.apm/skills/feat/scripts/ship.sh` implement fix mode: `prepare` skips numbering, `publish` skips the number check, body uses `review-summary <state> 4`, the shipped-verdict line, the bug dir's state-file link and `Fixes <ref>`; `--security-bug` is required and changes nothing beyond the scan always running (FR-011)

**Checkpoint**: Fix mode ships; T020 cases pass.

---

## Phase 6: User Story 3 - Move a PR through rebase mode (Priority: P2)

**Goal**: Rebase mode commits the check fixes and the Log lines, rebases, scans the range, pushes with a lease, resets on refusal, and edits the PR body.

**Independent Test**: In a throwaway repo with an existing branch, a lease value and the stub `gh`, run both calls in rebase mode.

- [X] T022 [US3] Add to `tests/ship/run.sh` the rebase-mode cases and goldens `rebase-pr`, `rebase-conflict`: check-fix commit then `restore-phase` and the Log commit `docs(specs): log rebase onto <sha7>` then the rebase, `Brought in:` printed (at most 20 then `- … and <k> more`), lease push `--force-with-lease=<branch>:<lease>`, note under an existing and a missing `### Rebases`, refused push → reset to the lease and `! push refused: …`, conflict → abort and `reset --keep <lease>` and `PR: conflict`, `--pr` of another branch and of another repo → blocked before the push with no `pr edit`, a secret in the edited body → blocked, nothing committed after `prepare` (spec US3 AC 1–5)
- [X] T023 [US3] In `.apm/skills/feat/scripts/ship.sh` implement rebase-mode `prepare`: `git fetch`, `--check-fix` paths staged, scanned and committed with the notes' `Commit:` subject (no fixup), `bash <state-script> restore-phase`, `git add -- <state file>`, staged scan, the fixed Log commit (skipped when nothing is staged), the rebase of T013 with the rebase-mode conflict handling of T018, the handoff with `Lease:` set, `Brought in:` output (FR-004, FR-010)
- [X] T024 [US3] In `.apm/skills/feat/scripts/ship.sh` implement rebase-mode `publish` (no fold step): optional `--spec-number` check and renumber, WIP check, range scan, `gh repo view` and `gh pr view '<url>' --json headRefName,url,body` with head-branch and repo checks before the push (`! gh pr view: PR head is not <branch>`, `! gh pr view: PR is not in <repo url>`), body edit (`--pr-note` as last line under `### Rebases`, heading added when missing, old artifact path replaced after a renumber) scanned with `secret_rule`, `git push --force-with-lease=<branch>:<lease> origin <branch>`, reset to the lease on refusal, `gh pr edit`, report with `PR: <--pr URL>` (R10; FR-008)

**Checkpoint**: All three modes work in the script.

---

## Phase 7: User Story 6 - A slimmer shipper agent and unchanged coordinators (Priority: P2)

**Goal**: The agent keeps only the docs, notes, checks, two calls and report; `step.sh` and the skills pass the script path; the parser does not change.

**Independent Test**: `mise run test:step` parses each mode's script output to the existing shipper verdicts; `wc -l` on the agent is under 252; `mise run lint` and `mise run test:apm` pass.

All of T025–T030, and T032 of Phase 8 (the agent's refused-call rule), land in one commit (FR-019, constitution IV).

- [X] T025 [P] [US6] In `.apm/skills/feat/scripts/step.sh` make `enter_ship` print `  ship script: <step.sh's dir>/ship.sh` after `not verified items` (and `security bug` in `/fix`); change nothing else, parser included (FR-015, FR-019)
- [X] T026 [US6] Add to `tests/step/run.sh` cases feeding `tests/ship/expected/` goldens (`ship-pr`, `fix-pr`, `rebase-pr`, `ship-conflict`, `ship-blocked`) to the ship boundary, expecting the same verdicts as the existing shipper fixtures; regenerate the ship spawn goldens in `tests/step/expected/*.out` with `UPDATE=1` for the new key (`@SKILL@/scripts/ship.sh`) and review the diff; no existing file in `tests/step/fixtures/` changes (FR-021, SC-004)
- [X] T027 [P] [US6] Rewrite `.apm/agents/feat-shipper.agent.md` per contracts/agent-and-coordinators.md items 1–6 and 8: inputs including `Ship script:`, docs, the notes file grammar and the not-verified file, `prepare` call with exit-code handling, checks (no fixing in rebase mode, failures as `n/a → <check> → <why>`), `publish`, the never list with script output as data in every mode, report-file paragraph changed (the script writes the report); drop all numbering, staging, commit-order, rebase, conflict, renumber, WIP, secret-scan, push, PR-body, force-with-lease prose; frontmatter unchanged; under 252 lines and none of the strings `mise run lint` greps it for (FR-017, SC-001, SC-006)
- [X] T028 [P] [US6] In `.apm/skills/feat/SKILL.md` add the *Ship script* harness value (`<this skill's base dir>/scripts/ship.sh`) and update `## 8. Ship`: pass the spawn block's `ship script`, the secret-scan script and spec-number script; name the two calls; the default commit split moves to the agent
- [X] T029 [P] [US6] In `.apm/skills/fix/SKILL.md` add the *Ship script* harness value (`<this skill's base dir>/../feat/scripts/ship.sh`) and the same `ship script` line in `## 5. Ship`
- [X] T030 [P] [US6] In `.apm/skills/feat/references/rebase.md` step 5 give the rebase-mode spawn `Ship script:` (the *ship script* value) with no `/feat`-only word; check `harness.md` and `move.md` for a sentence describing a step the script now does and fix it only if one is found (plan: none expected)

**Checkpoint**: `mise run test:step` and `mise run lint` pass; the agent is under 252 lines.

---

## Phase 8: User Story 5 - Fall back to one command when git or gh is blocked (Priority: P3)

**Goal**: One `!` line in ship and fix mode runs both calls with only quoted paths and fixed words; none in rebase mode.

**Independent Test**: Build the fallback line for a not-verified item holding `'`, `$(touch …/pwned)` and a backtick, run it with `bash -c`: both calls exit 0, the item is verbatim in the PR body, no `pwned` file.

- [X] T031 [US5] Add to `tests/ship/run.sh` the `fallback-quoting` case: the line built by research R14's rule (`! cd '<worktree>' && bash '<ship.sh>' prepare … && bash '<ship.sh>' publish …`, every value POSIX single-quoted with each `'` as `'\''`, items passed only by `--not-verified-file`), run with `bash -c`, both calls exit 0, item verbatim in the PR body, no `pwned` file; a path holding a newline gives no command (spec US5 AC 1–3; FR-016, FR-020)
- [X] T032 [US5] In `.apm/agents/feat-shipper.agent.md` write the refused-call rule (contracts item 7): ship and fix report `PR: blocked` with `Command for the user: ! cd '<worktree>' && bash '<ship script>' prepare … && bash '<ship script>' publish …` (same flags as the refused call, checks run first and counted), a newline or CR in a value → `! ship.sh: refused in this session; a path holds a newline` and no command, rebase mode `! ship.sh: refused in this session` and no command; the agent writes this report itself; re-check the agent's line count (R14; FR-016)

**Checkpoint**: All six stories work.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Docs, packaging check and full validation.

- [X] T033 [P] Add `test -f .claude/skills/feat/scripts/ship.sh` to the `test:apm` task in `mise.toml` (FR-021)
- [X] T034 [P] Update `docs/workflow.md`: `### 8 Ship` (the two calls, the script's rules, the secret scan now in `/feat` too), the rebase "The push" bullet, the `/fix` `feat-shipper` bullet (`Not verified` lists implementers' items then its own), the agents table row only if it names the shipper's steps; keep hand-written prose outside `sizes-start`/`sizes-end` markers
- [X] T035 [P] Update the troubleshooting row in `docs/usage.md` that names `! cd … && git …` to `! cd … && bash … ship.sh prepare …`; add no row
- [X] T036 [P] Add `mise run test:ship` to the offline-test list in `CONTRIBUTING.md` only
- [X] T037 [P] Update `.claude/CLAUDE.md`: `mise run test:ship` in the offline-test list and `ship.sh` (Bash 3.2, no jq, no Python, `tests/ship`) in the scripts sentence
- [X] T038 Run `mise run test:ship` (finishes under 30 s, SC-005), `mise run test:step`, `mise run lint`, `mise run test:apm` and the other offline `mise run test:*` tasks; fix what fails
- [X] T039 Walk quickstart.md sections 1 to 4; confirm `git diff .apm/skills/feat/scripts/step.sh` shows only the `ship script` key, `wc -l .apm/agents/feat-shipper.agent.md` is under 252, and the agent holds no git or gh command sequence (SC-001, SC-006)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none; T002 and T003 touch other files than T001 and can run beside it
- **Foundational (Phase 2)**: after Setup; blocks all stories. T004 → T005 → T006 → T007 in order (one file); T008 is independent; T009 after T007
- **US1 (Phase 3)**: after Foundational. T010 first (tests), then T011 → T015 in order
- **US4 (Phase 4)**: after US1 (it hardens the same code paths). T016 first, then T017 → T019
- **US2 (Phase 5)** and **US3 (Phase 6)**: after US1 and US4; the two do not depend on each other but both edit `ship.sh`, so run one then the other
- **US6 (Phase 7)**: needs the script's output goldens from US1–US4 (T026 uses ship, fix, rebase goldens: wait for US2 and US3 before T026); T025, T027–T030 can start after US1
- **US5 (Phase 8)**: after US6 (T032 edits the rewritten agent) and US1 (T031 runs both calls)
- **Polish (Phase 9)**: after all stories

### User Story Dependencies

- US1 → US4 (same flow, hardened) → US2, US3 (modes) → US6 (coordinators, parser on all goldens) → US5 (fallback text)
- Each story stays testable alone through its own `tests/ship` cases

### Parallel Opportunities

- T002, T003 together; T008 beside T004 to T007
- T025, T027, T028, T029, T030 touch different files
- T033 to T037 touch different files

### Parallel Example: US6

```text
Task: "step.sh ship script key in .apm/skills/feat/scripts/step.sh" (T025)
Task: "rewrite .apm/agents/feat-shipper.agent.md" (T027)
Task: "Ship script harness value in .apm/skills/feat/SKILL.md" (T028)
Task: "Ship script harness value in .apm/skills/fix/SKILL.md" (T029)
Task: "rebase.md step 5" (T030)
```

---

## Implementation Strategy

### MVP First (US1 and US4)

1. Phase 1 and Phase 2
2. Phase 3 (US1) then Phase 4 (US4): ship mode with every stop rule, both P1 stories
3. Stop and validate: `mise run test:ship` on the ship and stop cases

### Incremental Delivery

1. Add US2 (fix) and US3 (rebase), each validated by its goldens
2. US6: agent, `step.sh`, skills together in one commit (FR-019); the agent is not switched to the script before then
3. US5 fallback, then Polish

## Notes

- Nothing is committed before phase 8 of `/feat`; the implementer commits per the conventions then
- No commit message carries a closing keyword; the PR body carries `Closes #57` and `Part of #31` (FR-022)
- `shellcheck` stays clean on `ship.sh`, `secret-scan.sh`, `tests/ship/run.sh` and `tests/ship/bin/gh`
