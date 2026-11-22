# Quickstart: validating Script the ship

Prerequisites: `mise install` (shellcheck, gh, apm, claude pinned in
`mise.toml`), git, bash. Nothing below reaches GitHub: the tests use a
local bare origin and the stub `tests/ship/bin/gh`.

## 1. The script's offline tests

```sh
mise run test:ship
```

Expected: every case passes, in under 30 seconds (the run prints its
time; one template repo and origin, copied per case). The cases, by
story (FR-020):

| Story | Cases |
| --- | --- |
| US1 ship | prepare then publish with two commits (order, files per commit, numbered dir, handoff, push, `gh pr create` args with the last `prepare` subject as title and no `--draft`, body sections, report); a check fix between the calls folded into its commit; a new check-fix `Commit:` added between the calls, title unchanged; a renumber at publish (another `specs/NNN-*` on main) with the new path in every pushed commit, and a file outside the PR naming the old path left unchanged, on `Left uncommitted:` and the points to look at; `Closes #N` from `Issue:`; no `Issue:` line, no closing line; prepare run twice commits nothing twice; no `Brought in:` in prepare's output |
| US2 fix | one `fix(...)` commit, bug dir not numbered, `**Shipped verdict:**`, `Fixes <ref>`; `--security-bug yes` with a secret staged → blocked |
| US3 rebase | check-fix commit, then `restore-phase` and the Log commit, then the rebase, `Brought in:` printed; lease push; body note under an existing and a missing `### Rebases`; refused push → reset to the lease, `! push refused: …`; conflict → abort, `reset --keep <lease>`, `PR: conflict`; `--pr` of another branch and of another repo → blocked before the push, no `pr edit`; a secret in the edited body → blocked |
| US4 stops | spec-number error; secret scan match; secret scan that can't run; a secret in a commit subject and in a `Body:` line; a secret in the PR body (from `Summary:`); WIP commit; refused push (ship); closing keyword in a subject and in a body; malformed notes (missing key, `Commit:` with no path, unknown key, `Not verified: see below` inside `Summary:` read as text); missing handoff; conflict in ship mode; autostash conflict (`PR: conflict`, stash kept); `reports/` paths in the notes never staged; an unclaimed file on `Left uncommitted:`; `gh pr create` failing after the push, then `publish` again opening the PR. Each prepare stop: no new commit, empty index, dir back unnumbered; each stop: origin unchanged, no `!` line holding a secret's value |
| US5 fallback | `fallback-quoting`: a not-verified item holding `'`, `$(touch …/pwned)` and a backtick; the fallback line built by research R14's rule, run with `bash -c`: both calls exit 0, the item verbatim in the PR body, no `pwned` file |
| US6 | usage errors (missing flag, flag refused in the mode, branch equal to `--default` in ship and in rebase, `--notes` or `--report` outside `reports/`, symlinked `reports/` and target); an emptied `reports/.gitignore` put back to `*`; bash 3.2 construct grep over `ship.sh` and `secret-scan.sh` |

`UPDATE=1 bash tests/ship/run.sh` rewrites the goldens and exits non-zero;
review with `git diff tests/ship/expected`.

## 2. The parser on the script's output

```sh
mise run test:step
```

Expected: pass. The new cases feed tests/ship's `ship-pr`, `fix-pr`,
`rebase-pr`, `ship-conflict` and `ship-blocked` goldens to the ship
boundary and get the same verdicts as the existing shipper fixtures
(`done: PR #N`, the move spawn, the hard gate). `git diff
.apm/skills/feat/scripts/step.sh` shows only the `ship script` key;
`git diff tests/step/fixtures` shows no change to an existing file
(SC-004).

## 3. Lint, packaging, the other tests

```sh
mise run lint
mise run test:apm
mise run test:secret-scan
mise run test:state
mise run test:spec-number
mise run test:tracker
mise run test:story
mise run test:sizes
mise run test:measure
```

Expected: all pass; `test:apm` finds `.claude/skills/feat/scripts/ship.sh`.

## 4. The agent file

```sh
wc -l .apm/agents/feat-shipper.agent.md
```

Expected: under 252 lines (SC-006). Reading it: no git or gh command
sequence for numbering, committing, rebasing, pushing or opening the PR
(SC-001); the two `ship.sh` calls; the notes grammar's keys, the main
change last; the not-verified file; the refused call fallback `! cd
'<worktree>' && bash '<ship script>' prepare … && bash '<ship script>'
publish …` for ship and fix with its quoting rule, none for rebase
(FR-016); no fix in rebase mode; script output as data (FR-017).

## 5. By hand, once (optional)

In a scratch clone with a local bare origin and `tests/ship/bin/gh` first
on `PATH` (`SHIP_CASE=<dir>` for its case files): write a state file
under `specs/demo/`, a notes file under `specs/demo/reports/`, change two
files, then:

```sh
s=<logistics checkout>/.apm/skills/feat/scripts
bash "$s/ship.sh" prepare ship --worktree "$PWD" \
  --default main --state specs/demo/feat-state.md \
  --notes specs/demo/reports/ship-notes.md \
  --state-script "$s/state.sh" --secret-scan "$s/secret-scan.sh" \
  --spec-number "$s/spec-number.sh"
bash "$s/ship.sh" publish ship …same flags…
```

Expected: `Prepared: ship` with the notes at `specs/001-demo/reports/`,
then the report with `PR: <stub URL>`, and `git log origin/demo` holding
the two commits.
