# Implementation Plan: Script the ship

**Branch**: `ship-script` | **Date**: 2026-11-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-ship-script/spec.md` (issue #57; part of epic #31)

## Summary

A new bash script, `.apm/skills/feat/scripts/ship.sh`, runs every
mechanical step of the shipper in two calls over three modes. `prepare`
checks the notes file the model wrote, numbers the spec dir (ship mode),
stages each commit's paths, scans the staged lines for secrets, commits,
fetches and rebases onto `origin/<default>`, and writes a handoff file;
in rebase mode it commits the check fixes and the Log lines first.
Between the calls the model runs the project's checks and, in ship and
fix mode, fixes what fails (rebase mode lists a failure under `Not
verified:` and commits nothing more). `publish` folds those fixes into
their commits, rechecks the number (renumbering with fixup and
autosquash, in the PR's own files only), runs the WIP check and the
range secret scan, builds the PR body and runs the secret rules over it
(as `prepare` does over each commit message), pushes (with a lease in
rebase mode, after checking the PR's head and repo, resetting to the
lease when refused) and opens the PR, titled with `prepare`'s last
commit, or edits it. Any stop prints the shipper's report unchanged and
writes it to the report path, inside a guarded `reports/`; a blocked
`prepare` puts the tree back as it found it, and a blocked `publish`
can run again (stories 1–4).

The shipper agent keeps the docs, the notes (and a file of the
implementers' not-verified items), the checks, the two calls and the
report; the fallback for a session that refuses the call becomes one `!
cd … && bash ship.sh prepare … && bash ship.sh publish …` line in ship
and fix mode, holding only paths and fixed words (stories 5, 6). `step.sh` prints the script's path in
the ship spawn block and both skills name it as a harness value; its
parser does not change, and new tests/step cases parse the script's own
output.

## Technical Context

**Language/Version**: bash 3.2 or later for `ship.sh` (step.sh's
construct limits: no `declare -A`, `mapfile`, `${v,,}`, `declare -n`,
`[[ -v ]]`, `;;&`, `|&`; empty arrays as `${a[@]+"${a[@]}"}`;
case-insensitive matching through `shopt -s nocasematch`); the same for
the one-line fix to `secret-scan.sh` (research R16); Markdown prompts

**Primary Dependencies**: none new. `git` (`fetch`, `add`, `commit -F`,
`commit --fixup`, `rebase -i --autosquash --autostash` with
`GIT_SEQUENCE_EDITOR=:`, `rebase --abort`, `reset --keep`, `mv`, `grep
-l -F`, `push -u`, `push --force-with-lease`, `status --porcelain -z`,
`diff --name-only --diff-filter=U`), `gh` (`repo view`, `pr create`, `pr
view`, `pr edit`; `pr list` and `api` through `spec-number.sh`), and the
shipped `spec-number.sh`, `secret-scan.sh`, `state.sh` (`restore-phase`,
`review-summary`, `shipped-verdict`, `report-path` as the `reports/`
guard) called with `bash`, and `secret-scan.sh` also sourced for
`secret_rule` as tracker.sh does, interfaces unchanged (FR-003); `gh pr
view --json headRefName,url,body` with gh's own `--jq`

**Storage**: files directly in the artifact dir's `reports/` (the notes
and not-verified file the model writes, the handoff, the report), guarded
by `state.sh report-path` (R18), scratch files in the run's git dir,
deleted on exit

**Testing**: new `tests/ship/run.sh` with a stub `tests/ship/bin/gh`, one
template repo and bare origin built once per run and copied per case
(`cp -R`), target under 30 s for `mise run test:ship` (R17), goldens in
`tests/ship/expected/` (`UPDATE=1` rewrites and exits non-zero, as
tests/step), checks on the repo itself (commits and their files, index,
origin's refs, gh calls, PR body), a bash 3.2 construct grep;
`mise run test:ship` and a `check.yml` step; tests/step cases fed by
tests/ship's goldens and its ship spawn goldens regenerated for the new
key; `mise run test:apm`, `mise run lint`; [quickstart.md](quickstart.md)

**Target Platform**: Claude Code sessions running `/feat` and `/fix`
(Linux, macOS with `/bin/bash` 3.2 included); the `check` workflow
(ubuntu-latest)

**Project Type**: prompt package (skills and subagents) with helper
scripts

**Performance Goals**: none claimed (spec assumption 5): the aim is that
the same steps run the same way every time

**Constraints**: the report format and step.sh's shipper parser
unchanged (FR-015); stage by path only, never `reports/`, no closing
keyword in a commit, never merge, force only with the lease in rebase
mode, never push the default branch (FR-012); secret rules over commit
messages and the PR body (FR-023); writes in `reports/` only through
the state tool's guard (FR-024); a blocked `prepare` leaves nothing
committed or staged and nothing pushed (FR-005); the fallback line
holds only paths and fixed words (FR-016); nothing read is evaluated; no convention
option and no subject check (FR-009); `harness.md`, `rebase.md`,
`move.md` hold no `/feat`-only words; the agent file under 252 lines
and free of the strings lint greps it for

**Scale/Scope**: 1 new script (~950 lines) and its tests (~45 cases);
`step.sh` (1 line) and its spawn goldens; `secret-scan.sh` (a few
lines); 1 agent rewritten; both skills, `rebase.md`; `mise.toml`, CI;
`docs/workflow.md`, one row of `docs/usage.md`, one list in
`CONTRIBUTING.md`, `.claude/CLAUDE.md`; ~50 tasks

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
| --------- | ----- | ------ |
| I. Thin coordinators | the coordinators gain one path to pass (`ship script`, printed by step.sh for `/feat` 8 and `/fix` 5, a harness value for `rebase`); they read no code and run nothing new; the work goes into the agent and a script it calls | pass |
| II. The user decides at gates | gates unchanged: `PR: blocked` lines still reach the user as a hard-gate error or, for the fallback, a command the user runs; the script never merges and never resolves a conflict, which stays with the rebase-mode implementer and the move gate | pass |
| III. One source of truth | the ship's git rules move from the agent's prose (three modes, partly repeated) into one script; the script's path is a harness value named once per skill and used by `rebase.md` by name; sizes.json untouched (same agent, same row) | pass |
| IV. Fixed report formats | the shipper's format is unchanged; the agent, step.sh's spawn key, the skills' harness values and tests/step change in one commit (FR-019); the format is now produced by the script, and tests/step parses that output | pass |
| V. Small and plain | a new script, as the spec asks: bash, shellcheck-clean, offline tests under `tests/ship`; the agent file shrinks; no new dependency | pass |

Distribution: `ship.sh` lives in `.apm/skills/feat/scripts/`, shipped
whole by APM, the plugin and `install.sh`; `test:apm` checks it. No agent
added: `plugin.json` unchanged.

Post-design re-check: pass. No service, permission or dependency added:
the git and gh commands are the ones the shipper runs today, now inside a
script. Exposure narrows: `/feat`'s ship now scans the staged lines and
the pushed range for secrets as `/fix` and rebase mode already do, and
every mode now runs the same rules over commit messages and the PR body;
a `!` fallback line no longer carries `git add …`, `git commit -m …` or
any model or implementer text, only quoted paths; the script refuses to
push the default branch and, in rebase mode, a PR of another branch or
repo; its writes stay in a `reports/` the state tool guards. A `bash ship.sh …` call names no `git`, so the session's worktree
guard no longer sees each git command: that is the brief's stated aim
(FR-016), and the script's rules (FR-012) take over what the prose
asked. Size trigger: none.

## Project Structure

### Documentation (this feature)

```text
specs/014-ship-script/
├── plan.md                          # this file
├── research.md                      # decisions R1–R18
├── data-model.md                    # artifact dir, notes grammar, not-verified file, handoff, outputs, blocked lines, PR body, commit messages
├── quickstart.md                    # validation steps
├── contracts/
│   ├── ship-cli.md                  # call, flags by mode, exit codes, prepare and publish per mode, rules
│   └── agent-and-coordinators.md    # the agent rewrite, step.sh's key, skills, rebase.md, docs, mise and CI
└── tasks.md                         # phase 5
```

### Source code (repository root)

New:

```text
.apm/skills/feat/scripts/ship.sh
tests/ship/run.sh
tests/ship/bin/gh
tests/ship/expected/*.out
```

Changed:

```text
.apm/agents/feat-shipper.agent.md        # rewritten around the two calls
.apm/skills/feat/scripts/step.sh         # `ship script:` in the ship spawn block
.apm/skills/feat/scripts/secret-scan.sh  # ${1,,} → nocasematch (bash 3.2)
.apm/skills/feat/SKILL.md                # Harness values: Ship script; 8. Ship
.apm/skills/fix/SKILL.md                 # Harness values: Ship script; 5. Ship
.apm/skills/feat/references/rebase.md    # step 5: the ship script
tests/step/run.sh                        # cases on tests/ship's goldens
tests/step/expected/*.out                # the ship spawn's new key
mise.toml                                # test:ship, lint, test:apm
.github/workflows/check.yml              # mise run test:ship
docs/workflow.md                         # 8 Ship, the rebase push, the /fix shipper bullet
docs/usage.md                            # the `! cd … && git …` troubleshooting row only
CONTRIBUTING.md                          # test:ship in the offline test list only
.claude/CLAUDE.md                        # test:ship, ship.sh in the scripts sentence
```

`docs/usage.md` and `CONTRIBUTING.md` are touched only where they name
the fallback line or list the offline tests (design review D9).

**Structure Decision**: one script beside the three it calls, in the
`feat` skill's `scripts/` (shipped whole, used by `/fix` through
`../feat/scripts/` like `state.sh`); its tests in `tests/ship/` like
every other script's.

## Design

How each requirement is met; the details are in the contracts.

- **Interface (FR-001, FR-002)**: `ship.sh <prepare|publish>
  <ship|fix|rebase>` with one long-flag set for both calls, mode-checked;
  the artifact dir and the issue come from the state file; the
  implementers' items come by `--not-verified-file`
  ([ship-cli.md](contracts/ship-cli.md), research R1, R13).
- **Calls into the existing tools (FR-003)**: `bash <spec-number> next |
  check`, `bash <secret-scan> staged | range`, `bash <state-script>
  restore-phase | review-summary | shipped-verdict`; their exit codes and
  first lines map to the blocked lines of
  [data-model.md](data-model.md#blocked-lines).
- **prepare (FR-004, FR-005, FR-006)**: notes parsed in full first;
  numbering with byte-exact backups (R5); staging per commit, fixup for a
  subject already committed, staged scan, commit (R6); fetch and one
  autosquash rebase, then the unmerged-files check (R7); the handoff,
  whose `Commits:` gives the PR title. `Brought in:` in rebase mode only.
  A block resets to the start, undoes the numbering, and writes the
  report.
- **publish (FR-006, FR-007, FR-008)**: the handoff checked, its `Head:`
  rewritten at each HEAD change so a retry works (R3); check fixes folded
  as fixups (ship, fix; rebase mode folds nothing, R7); the number recheck
  and renumber, in the PR's own files (R8); one autosquash onto the
  recorded base; WIP check and range scan on that base (R9); the body
  built and scanned, then the push and `gh pr create` (title from the
  handoff, never a draft), or the PR's head and repo checked, the lease
  push, reset on refusal, and the body edit (R10).
- **Notes and handoff (FR-009, FR-010)**: the grammar in
  [data-model.md](data-model.md#notes-file), key lines by one pattern;
  rebase mode's notes hold only the check-fix subject; the Log commit is
  the script's.
- **PR body (FR-011)**: sections in
  [data-model.md](data-model.md#pr-body); the implementers' items come
  from the not-verified file (R13).
- **Rules (FR-012, FR-013, FR-014)**: stage by path, `reports/` dropped and
  unstaged, closing keywords refused (R11), the default branch never
  pushed (R1), conflicts aborted and listed, an autostash conflict
  reported with its stash kept (R12), unclaimed files on `Left
  uncommitted:`.
- **Public text (FR-023)**: `secret_rule`, sourced from secret-scan.sh,
  over each commit message in the notes parse and the PR body before the
  push (R9).
- **Writes (FR-024)**: notes, not-verified file and report directly in
  the artifact dir's `reports/` (physical path), `state.sh report-path`
  as the guard (R18).
- **Output (FR-015)**: the shipper's report, written by the script to the
  report path at its final location and printed (R2).
- **Fallback (FR-016)**: the agent's rule for a refused call, paths and
  fixed words only, `'\''` quoting (R14).
- **Agent (FR-017), coordinators (FR-019)**: no fix in rebase mode, the
  main change last in the notes, script output as data;
  [agent-and-coordinators.md](contracts/agent-and-coordinators.md); the
  script's path from step.sh's spawn block and the *Ship script* harness
  value (R15).
- **Bash 3.2 (FR-018)**: construct limits, a grep in tests/ship over
  `ship.sh` and `secret-scan.sh`, and secret-scan's `${1,,}` replaced
  (R16).
- **Tests (FR-020, FR-021)**: tests/ship, tests/step on its goldens,
  `test:apm`, lint (R17, [quickstart.md](quickstart.md)).
- **This PR (FR-022)**: its body carries `Closes #57` and `Part of #31`;
  no commit message carries a closing keyword (this run ships with the
  installed shipper, spec assumption 1).

## Order of work

1. `ship.sh` skeleton: flags, usage, path resolution, the `reports/`
   guard and default-branch check, notes parser with `secret_rule`,
   handoff, report writer; tests/ship harness (template repo copied per
   case, the stub gh) and the notes and usage cases.
2. Ship mode prepare and publish, with numbering, staging, scans, rebase,
   renumber, push, PR body (US1), then the stop cases (US4).
3. Fix mode (US2), rebase mode (US3).
4. `secret-scan.sh`'s bash 3.2 fix and the construct grep.
5. step.sh's key, tests/step cases and regenerated goldens; the agent
   rewrite; the skills, `rebase.md` (US5, US6), all in one commit.
6. `mise.toml`, CI, docs.

## Complexity Tracking

No constitution violation to justify.
