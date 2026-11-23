# Tasks: Script the setup checks, the bug-trail chores and the review diff file

**Input**: Design documents from `specs/016-setup-trail-scripts/` (spec.md, plan.md, research.md R1–R17, data-model.md, contracts/preflight.md, contracts/trail.md, contracts/review-diff.md, quickstart.md)

**Prerequisites**: plan.md, spec.md

**Tests**: Requested (FR-018, SC-003 to SC-006): offline bash suites `tests/preflight`, `tests/trail` and new cases in `tests/step`. Each story's tests are written with its script code and must pass before the story is done.

**Rules for every task** (project `.claude/CLAUDE.md`, constitution): Bash 3.2, no jq, no Python, `set -euo pipefail`, `LC_ALL=C`, nothing read is evaluated or executed; shellcheck clean; no added line may match `secret-scan.sh` (name the rules, never quote their prefixes; build test samples by concatenation at run time, as `tests/ship` does); no `/feat`-only words in `harness.md`, `rebase.md`, `move.md`; never edit `CHANGELOG.md`, versions, `.release-please-manifest.json`, `sizes.tsv` or a `sizes-start`/`sizes-end` block; agent report formats unchanged; do not commit.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: different files, no dependency on an incomplete task
- Paths are relative to the worktree root; scripts live in `.apm/skills/feat/scripts/` (called `$S/` below)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test harnesses and wiring for the two new scripts, so every later task has somewhere to run.

- [X] T001 [P] Create `tests/preflight/run.sh` and `tests/preflight/bin/gh` (stub `gh` answering `repo view --json nameWithOwner --jq …` and `api repos/<o>/<r>/issues/<N> --jq …` from case variables, logging its calls). The harness (modelled on `tests/ship/run.sh`) builds a template repo plus a bare `origin`, copies both per case, lays out a scratch skill tree `<base>/.claude/skills/feat/scripts/` holding a copy of `preflight.sh` and a stub `tracker.sh` (its `check` line and exit come from the case), `feat-*.md` agents in `<base>/.claude/agents/`, a scratch `HOME`, a second worktree for the brief search, golden outputs in `tests/preflight/expected/` rewritten with `UPDATE=1`, and `case_run`/`expect_exit`/`expect_line` helpers. Ends with no cases yet but passes when run.
- [X] T002 [P] Create `tests/trail/run.sh` with `tests/trail/fixtures/` and `tests/trail/expected/`: a throwaway bug dir per case, a scratch git repo in which `secret-scan.sh worktree` is run on each redacted file (exit 0 expected), `expect_exit`/golden helpers (`UPDATE=1`), and a loop that fails when a `SECRET_VENDOR` name from `$S/secret-scan.sh` has no sample in the test. Samples and key values are built by concatenation at run time. No cases yet; runs clean.
- [X] T003 Wire `mise.toml`: add tasks `test:preflight` (`bash tests/preflight/run.sh`) and `test:trail` (`bash tests/trail/run.sh`) beside `test:ship`; add `shellcheck tests/preflight/run.sh tests/preflight/bin/gh` and `shellcheck tests/trail/run.sh` to `tasks.lint.run` (the scripts are already under the `$S/*.sh` glob); add both to the lint description.
- [X] T004 [P] Add `- run: mise run test:preflight` and `- run: mise run test:trail` to `.github/workflows/check.yml` after `mise run test:ship`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The two script skeletons every story fills in.

**CRITICAL**: No user story work begins until this phase is complete.

- [X] T005 [P] Create `$S/preflight.sh` skeleton per contracts/preflight.md: header comment (usage, exit codes, output keys), `set -euo pipefail`, `LC_ALL=C`, an `emit key value` helper that prints one line with control characters replaced by spaces, `die_usage` (`preflight: usage: …`, exit 2) and `stop` (`stop: <why>`, exit 1) helpers, argument parsing for `<feat|fix> [<argument>] [slug=<words>]` and the worktree mode dispatch (`worktree` as first word after the skill), `git rev-parse --show-toplevel` (not a repo: `preflight: error: …`, exit 2), everything on stdout. `slug=` with anything but a `/fix` symptom is refused (exit 2). No step bodies yet.
- [X] T006 [P] Create `$S/trail.sh` skeleton per contracts/trail.md: header, `set -euo pipefail`, `LC_ALL=C`, source `secret-scan.sh` from its own directory (missing: `trail: error: …`, exit 2, as `tracker.sh` does), subcommand dispatch for `rotate`, `sections`, `slug`, `redact` with `trail: usage: …` (exit 2) on a wrong argument count, unknown subcommand, a missing bug dir or file, or a symlink; nothing on stderr. Subcommand bodies are stubs.

**Checkpoint**: both scripts parse, shellcheck clean, and the harnesses run.

---

## Phase 3: User Story 1 - Setup runs as a few scripted calls (Priority: P1) MVP

**Goal**: One preflight call classifies the argument, finds and reads the brief, checks the install and reads a `/fix` issue; a second call after `EnterWorktree` renames the branch.

**Independent Test**: `bash tests/preflight/run.sh` cases for every argument kind of both skills, brief fields, install checks, issue lookups and worktree mode pass offline.

### Implementation for User Story 1

- [X] T007 [US1] In `$S/preflight.sh`, implement argument classification (FR-001, contract table "Argument kinds"): `empty` (usage line, exit 0, nothing else), exact `resume`, `rebase` alone or followed by one whitespace-free word (`rebase target:`), issue references accepted only when owner matches `[A-Za-z0-9][A-Za-z0-9-]*`, repository `[A-Za-z0-9._-]+` other than `.` and `..`, number `[1-9][0-9]*`, and for a URL host exactly `github.com` with nothing after the number but an optional `/`, `#…` or `?…`; other `http(s)://` URLs are `github: no`; anything else a symptom (`/fix`) or idea (`/feat`; `kind: idea`, pointer `/brief "<arg>"`). Refusals (a brief or `…specs/briefs/<x>.md` path or a file whose first line starts `# Brief:` given to `/fix`; an issue or idea given to `/feat`) print `kind:`, `pointer:`, `stop:`, exit 1 and check nothing else. Longer arguments starting with `resume` or `rebase` are a symptom or idea.
- [X] T008 [US1] In `$S/preflight.sh`, implement the brief lookup and fields (FR-002, R11, contract "Brief fields"): an existing file as given, else `<name>` (no `specs/briefs/` prefix, no `.md`) matching `[a-z0-9][a-z0-9-]*`, searched as `specs/briefs/<name>.md` under this checkout's top level then every other `git worktree list --porcelain` path; several matches print `brief: several` and `candidate:` lines, exit 0, nothing else; none prints `stop:`, `pointer:` and one `searched:` line per path, exit 1. Fields from the header (lines before the first `## `): `title:`, `size:` (`normal` as medium, `big` as large; `tiny` and `huge` stop with their pointers), `size note:`, `short name:` (must match `[a-z0-9][a-z0-9-]*`), `map:`, `issue:`, `behaviour: <n> lines`, `acceptance: <n> lines` (non-blank lines, not printed; 0 stops with `stop: brief lacks <…>`), and `brief in checkout: yes|no` (exactly `<top>/specs/briefs/<short name>.md`). Brief text is printed as data after its key only.
- [X] T009 [US1] In `$S/preflight.sh`, implement the install check (FR-003, R4, contract "Bug extension version"): `.specify/` at the top level; the `feat-*` agents as `feat-<x>.md` or `feat-<x>.agent.md` in the first of the agents dir three levels above the script (logical and resolved path), `<top>/.claude/agents`, `$HOME/.claude/agents`; for `/fix` also `.specify/extensions/bug/` or a `speckit-bug-{assess,fix,test}` skill in `<top>/.claude/skills` or `$HOME/.claude/skills`; print `install: ok` and, for `/fix`, `bug extension: <version|unknown>` read from the first line of exactly two spaces plus `version:` inside the column-0 `extension:` mapping of `.specify/extensions/bug/extension.yml` (never `speckit_version:`), quotes stripped, kept only when it matches `[A-Za-z0-9][A-Za-z0-9._-]*`. A miss prints `stop: <what is missing>`, exit 1.
- [X] T010 [US1] In `$S/preflight.sh`, implement the `/fix` issue lookup (FR-006, R10): `gh repo view --json nameWithOwner --jq .nameWithOwner` once, then `gh api repos/<o>/<r>/issues/<N> --jq '[.author_association, .title] | @tsv'` with the checked parts only; print `kind: issue`, `github: yes|no`, `title:` and `author:` (the association only when `<o>/<r>` is the current repo; `unknown` elsewhere and for a non-GitHub URL, whose `title:` is its last path segment without query or fragment; `user` for a symptom); a gh failure prints `stop:` with gh's first line, exit 1. Order of steps per kind follows the contract table "Steps per kind".
- [X] T011 [US1] In `$S/preflight.sh`, implement worktree mode (FR-008, contract "Worktree mode"): refuse (exit 2, `preflight: usage: …`) a short name not matching `[a-z0-9][a-z0-9-]*`, a slug not matching it or over 40 characters, a last argument other than `on` or `off`; print `worktree: <top>`; `/fix`: `<top>/.specify/bugs/<slug>` present prints `stop: slug <slug> is taken (bug dir); run setup again`, exit 1; rename with `git branch -m <short-name|fix-<slug>>` (already the target prints `branch: <name>`; failure prints `stop: can't rename the branch to <name>: <git's first line>`, exit 1); when `on` and `<top>/.logistics.yml` is missing, print `flag: - [!] tracker: .logistics.yml is not in the worktree; commit and push it (board moves skipped)`. No network call.
- [X] T012 [US1] Add `tests/preflight/run.sh` cases (SC-004) for every argument kind of both skills: empty, `resume`, `rebase`, `rebase 12`, `resume button crashes` and `rebase breaks on merge commits` (symptom for `/fix`, idea for `/feat`), `#N`, `owner/repo#N`, the GitHub URL forms and another URL, a brief path and a short name, refusals with `pointer:` lines and exit 1, `../x#1` and a `github.com.evil` URL (not an issue), an argument holding `'` and `$(touch pwned)` (printed as data, no file created).
- [X] T013 [US1] Add `tests/preflight/run.sh` cases for the brief: fields with line counts, `normal` as medium and `big` as large, `tiny` and `huge` (exit 1), missing fields and an empty Behaviour (exit 1), a name in no worktree (`searched:` lines), a name matching in two worktrees (`brief: several`, `candidate:`), `brief in checkout: yes|no`, hostile text in the title printed as data.
- [X] T014 [US1] Add `tests/preflight/run.sh` cases for install and issue: missing `.specify/`, missing agent (plain and `logistics:`-prefixed accepted), missing bug extension for `/fix`, `bug extension:` read from the `extension:` mapping and not from `speckit_version`, `unknown` when absent; issue title and author in the current repo, another repo (`unknown`), a non-GitHub URL, a symptom (`user`), and a gh failure (exit 1).
- [X] T015 [US1] Add `tests/preflight/run.sh` cases for worktree mode: rename success, a rerun on the target branch (`branch:` only), bad short name, bad slug (also 41 characters), bad `on|off` (all exit 2), a local branch of that name (exit 1), the bug dir present in the worktree (exit 1), the `flag:` line when `on` and `.logistics.yml` is missing, no `flag:` line when `off`, not a repo (exit 2), and no network call (a failing stub `git` remote does not matter).

**Checkpoint**: classification, brief, install, issue and worktree mode work and are tested; hooks, base and slug are next.

---

## Phase 4: User Story 2 - Hooks and base are checked as data, with clear stops (Priority: P1)

**Goal**: Preflight fetches the default branch, runs the board check and reads the hooks as data from that branch's `extensions.yml`.

**Independent Test**: preflight against `extensions.yml` fixtures, a failing fetch, a failing board check and an unreachable remote returns the right lines and exit codes.

### Implementation for User Story 2

- [X] T016 [US2] In `$S/preflight.sh`, implement the board check and the base (FR-005, R15, contract "Default branch"): when `.logistics.yml` exists run the skill's `tracker.sh check` (a failure prints `stop:`, exit 1; `board: <line>` or `board: off`); find the default branch as `step.sh`'s `default_branch` does (copy it, name `$S/step.sh` in a comment: `git symbolic-ref -q --short refs/remotes/origin/HEAD` minus `origin/`, else the `ref: refs/heads/<x>` line of `GIT_TERMINAL_PROMPT=0 git ls-remote --symref origin HEAD`; an empty name, a leading `-` or a name `git check-ref-format --branch` does not return unchanged: `preflight: error: no default branch found`, exit 2); print `default:`; `git fetch origin <default>` (a failure prints `stop:`, exit 1; `fetch: ok`). Runs only for the kinds the contract table names, after classification and refusals.
- [X] T017 [US2] In `$S/preflight.sh`, implement the `extensions.yml` reader (FR-004, R2, R3, contract "Hooks"): source is `git show refs/remotes/origin/<default>:.specify/extensions.yml` for a brief, issue or symptom (checked first with `git cat-file -e`; absent means no hooks) and the checkout's file for `resume` and `rebase`; a line-based reader of the YAML subset Spec Kit writes (block mappings and sequences, indented or not, plain or quoted scalars, comments, `{}`/`[]` empties, continuation lines of keys it does not read) that reads only the event key, `enabled` (`true/false/yes/no/on/off`, any case; absent is enabled; `false` ignored), `extension`, `command`; anything else, a tab in the indent, an event key outside `[a-z][a-z0-9_]*`, or an `extension` or `command` outside `[A-Za-z0-9][A-Za-z0-9._-]*` prints `stop: <source> can't be read as data (line <n>); it may hide a hook that commits`, exit 1. Never evaluates anything it reads.
- [X] T018 [US2] In `$S/preflight.sh`, implement hook classification and output (FR-004, R3): "would branch or commit" on the lowercased names (extension `git`; or `git`, `pr`, `tag`, `worktree` as a `.`/`-`/`_`-separated word of extension or command; or `commit`, `branch`, `push`, `merge`, `rebase`, `checkout`, `switch`, `release`, `publish` anywhere in either); print `hook won't run:` (`/feat` only) and `hook would branch or commit:` lines as `<key>: <extension>.<command> → run it by hand: /<command, dots as hyphens>` (no command: `<key>: <extension>` and no manual command), `hooks allowed:` (`none` when empty); a hook enabled under several keys prints once per key; per-skill and per-key placement as research R3 (`/feat` `rebase`: implement part only).
- [X] T019 [US2] Add `tests/preflight/run.sh` cases for hooks: enabled, `enabled: false`, indented and indentless lists, `{}`, empty file, no file, a hostile command value and a bad event key (exit 1), an unparseable file (exit 1), `push`, `autocommit` and `open-pr` flagged, a committing hook present only on the fetched origin listed and a local-only one not (brief, issue, symptom), `resume` and `rebase` reading the checkout's file, `/fix` listing only branch-or-commit hooks.
- [X] T020 [US2] Add `tests/preflight/run.sh` cases for base and exit codes: board check failing (exit 1), `.logistics.yml` absent (`board: off`), fetch failing (exit 1), no `origin/HEAD` found through `ls-remote --symref`, a hostile default branch name (exit 2), unreachable remote (exit 2), usage error (exit 2), hostile `extensions.yml` text printed as data with no file created, and that a refused argument makes no git network call. Add a grep case that `preflight.sh` has no `eval`, no `mapfile`/`readarray`, no associative arrays and no `${var,,}` (bash 3.2).

**Checkpoint**: preflight mode 1 is complete for `/feat` and for `/fix` except the slug.

---

## Phase 5: User Story 3 - `/fix` slug is unique across dir, local and remote (Priority: P1)

**Goal**: Preflight builds `<N>-<words>` and dedupes it against the bug dir, local branches and remote branches in one `ls-remote`.

**Independent Test**: in throwaway repos with a bare remote, each clash kind in turn gives the next free suffix, and an unreachable remote exits 2.

### Implementation for User Story 3

- [X] T021 [US3] In `$S/preflight.sh`, implement the slug base and normalisation (FR-008, R1, R13, contract "Slug"): issue `<N>-<first three title words>` (two when over 40; `<N>` alone when the title has no `[a-z0-9]` word), symptom the `slug=<words>` argument, non-GitHub URL its last path segment; lowercase, every run of `[^a-z0-9]` to `-`, trimmed at both ends, cut to 40 at a `-`; a symptom or URL base that normalises to nothing is `bug`.
- [X] T022 [US3] In `$S/preflight.sh`, implement the clash check and print `slug:`: one `GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin 'fix-*'` (failure: `preflight: error: …`, exit 2) with its `refs/heads/` names kept; candidates `<base>`, `<base>-2`, `<base>-3`, … with the base trimmed (a trailing `-` dropped) so the slug stays at most 40 characters; a candidate is taken when `git cat-file -e` finds `.specify/bugs/<slug>` in `refs/remotes/origin/<default>` or `HEAD`, `refs/heads/fix-<slug>` exists locally, or the kept list holds exactly `refs/heads/fix-<slug>`; the first free one is printed.
- [X] T023 [US3] Add `tests/preflight/run.sh` cases for the slug: a free slug, a clash with the bug dir in the origin tree, in `HEAD`, a local branch and a remote branch (each gives `-2`; two clashes give `-3`), exactly one `ls-remote` call whatever the clashes (counted through a wrapper on `PATH`), the 40-character cap with a suffix, a title with no word (`<N>`), symptom words that normalise to nothing (`bug`), a non-GitHub URL's last segment, an unreachable remote (exit 2), and `slug=` refused for a non-symptom.

**Checkpoint**: all three P1 stories pass `mise run test:preflight`.

---

## Phase 6: User Story 4 - Bug reports are redacted by the same rules as the scan (Priority: P2)

**Goal**: `trail.sh redact <file>` rewrites a report so the secret scan no longer matches it, and prints the count.

**Independent Test**: each scan rule and short key values pass through `redact`, then `secret-scan.sh`, exit 0.

### Implementation for User Story 4

- [X] T024 [US4] In `$S/trail.sh`, implement `redact` private-key blocks and vendor tokens (FR-011, R5, contract "redact" rules 1 and 3): a block starts at a line matching the scan's `private-key` rule and ends at the first line holding the end marker (part of the block) or, whichever comes first, the first blank line or closing code fence (kept) or end of file, and becomes one `<redacted>` line; each `SECRET_VENDOR` prefix other than `private-key` with its token characters `[A-Za-z0-9_/+=.-]*` becomes `<redacted>`, keeping a leading non-word character of the openai-key rule; rules read from `secret-scan.sh`'s variables, never copied.
- [X] T025 [US4] In `$S/trail.sh`, implement `redact` key values (contract rule 2): for each `SECRET_KEY` match (any case) followed by `=` or `:` and a value, replace the value with `<redacted>` keeping key and separator; quoted values with their quotes; an unquoted value after a key that is the line's first token (after indent, optional `- `, `export ` or an opening quote) runs to the end of the line keeping a trailing ` #` comment; after a key inside a line it stops at whitespace or one of `,;&)}]"'<>`; leave alone no value (end of line, `""`, `''`) and a bare type or null word after `:` (`token: str`). Implement with bash/sed/awk portable to 3.2 and BSD.
- [X] T026 [US4] In `$S/trail.sh`, finish `redact` (contract rule 4 and write): last, any line the scan's `secret_line_rule` still matches becomes `<redacted>`; print the replacement count; write the file (temp file in the same dir, then `command mv -f`) only when the count is not 0, so a clean file stays byte-identical, keeping the final newline or its absence and `\r` line ends; refuse a symlink; a second run prints `0`.
- [X] T027 [US4] Add `tests/trail/run.sh` cases for `redact` (SC-003, FR-012): a sample for every `SECRET_VENDOR` name and for the key rule, each redacted file passing `secret-scan.sh worktree` (exit 0); `password=hunter2`, the table of contract rule 2 line by line (multi-word value, indented, after `- ` and `export `, with a trailing ` #` comment, `url?token=abc&x=1`, `token = getToken()`); `token:` at line end, `token: str` and `password: ""` unchanged; a private-key block (begin through end line) as one line; a block with no end line ending at the blank line, then at a closing fence; a prose mention of the begin marker keeping every later line and section; a secret inside a code excerpt; a clean file byte-identical with count 0; a second run printing 0 and leaving the file unchanged; CRLF and no-final-newline files; symlink and missing file exit 2.

**Checkpoint**: `redact` is complete and tested.

---

## Phase 7: User Story 5 - Report renames, headings and slugs are checked by script (Priority: P2)

**Goal**: `trail.sh rotate`, `sections` and `slug` replace the assessor's and implementer's hand renames and comparisons.

**Independent Test**: each subcommand run in a throwaway bug dir with fixtures prints the contract's output.

### Implementation for User Story 5

- [X] T028 [US5] In `$S/trail.sh`, implement `rotate <bug dir> <assessment|test|fix>`: `<report>.md` absent prints `none`; present is renamed to `<report>-<n>.md` with `n` = 1 + the highest existing `<report>-<n>.md` (1 when none) and the new absolute path printed; a symlink at either name refused; bad report name is usage (exit 2).
- [X] T029 [US5] In `$S/trail.sh`, implement `sections <file> <assessment|test>` (contract table): `assessment` requires a line starting `# Bug Assessment:`, `**Verdict**`, `**Severity**`, `## Symptom`, `## Reproduction`, `## Suspected Code Paths`, `## Root Cause Hypothesis`, `## Proposed Remediation`, `## Open Questions`; `test` requires `**Result**` and `## Checks Performed`; `## ` headings match the whole line (trailing spaces ignored), `**…**` parts anywhere in a line; print `Sections: ok` or `Sections: error: <file name> lacks <part>, <part>, …` in the table's order.
- [X] T030 [US5] In `$S/trail.sh`, implement `slug <bug dir> <slug> <file> [<printed slug>]`: the printed slug and the file's first `- **Slug**:` bullet value each lose backticks and a trailing ` (<note>)` then surrounding spaces; print `ok` when the bullet equals `<slug>`, the printed slug (when given) equals `<slug>` and the file resolves (`pwd -P`) under the resolved bug dir; else `mismatch (<printed slug, else the bullet value, else none>)`; a missing file is a mismatch.
- [X] T031 [US5] Add `tests/trail/run.sh` cases for `rotate` (none, one earlier report, `-1` and `-3` present giving `-4`, each of the three report names), `sections` (complete ok, each part missing in turn, several missing, trailing spaces on a heading), `slug` (ok, backticks and a trailing note, any disagreement, file outside the bug dir, without the printed slug, a missing bullet, a missing file), usage exits, and a bash 3.2 grep (no `eval`, `mapfile`, `${var,,}`, associative arrays) on `trail.sh`.

**Checkpoint**: `mise run test:trail` passes.

---

## Phase 8: User Story 6 - Code reviewers read the diff from a file (Priority: P2)

**Goal**: `step.sh` writes the review diff to `reports/review.diff` and names it in each code reviewer's spawn block; the reviewer reads it.

**Independent Test**: `bash tests/step/run.sh` shows the file equals the printed diff, is rewritten later and absent for an empty diff.

### Implementation for User Story 6

- [X] T032 [US6] In `$S/step.sh`, add `diff_write` (FR-015, R6, contracts/review-diff.md): after the first `spawn_group` of `review_batch` and in `spawn_7e`, write `git -C <top> diff --no-color --no-ext-diff <base> --` to `${RPATH%/*}/review.diff` through a temp file and `mv -f`, refusing a symlink (`step: error:`), once per call; print `diff file: <path>` right after `diff:` in every code-reviewer block and not in the inputs file; an empty diff writes nothing and spawns no reviewer. Update the header comment's key list.
- [X] T033 [US6] In `$S/step.sh`, print `trail script: <SDIR>/trail.sh` after the existing keys on the `/fix` spawns of the assessor (assess and test) and of the implementer in bug mode (R7), as `ship script:` is printed for the shipper.
- [X] T034 [US6] Add `tests/step/run.sh` cases (SC-005) and refresh `tests/step/expected/` goldens with `UPDATE=1` (then review `/usr/bin/git diff tests/step/expected`): a review boundary writes `reports/review.diff` equal to `git diff <base>`; a later boundary rewrites it; an empty diff writes none and spawns none; 7e names the same file; a symlink at the path is an error; the file is ignored by git and absent from `state.sh snapshot`; `diff file:` and `trail script:` keys appear in the goldens. Run `mise run test:step`.
- [X] T035 [P] [US6] Update `.apm/agents/feat-code-reviewer.agent.md` (FR-016): take either `diff file:` or `diff:`; with a file, read it (in parts when long) and run no git command to find the diff; run the `diff:` command only without a file (`/tiny`); still read the tree to verify each finding; report format unchanged.

**Checkpoint**: `mise run test:step` passes.

---

## Phase 9: User Story 7 - The replaced prose is gone and the docs match (Priority: P3)

**Goal**: The old prose and the new scripts do not both exist; docs describe the new scripts; lint guards it.

**Independent Test**: `mise run lint`, `mise run test:preflight`, `mise run test:trail` and the other offline tests pass.

### Implementation for User Story 7

- [X] T036 [P] [US7] Update `.apm/agents/feat-bug-assessor.agent.md` (FR-013, FR-017): replace the rename, slug and section rules and the whole Redaction paragraph (key and prefix list) with calls `bash '<trail script>' rotate|sections|slug|redact …` (path from the `trail script:` key; `slug`, `redact` and `sections` in one turn); `Assessment: none (…)` skips all three and reports `Sections: ok`; no printed `Slug:` line means `slug` without the fourth argument; test mode reports `redact`'s count on `Redacted:` (`none` for 0); report format unchanged.
- [X] T037 [P] [US7] Update `.apm/agents/feat-implementer.agent.md` bug mode (FR-013, FR-017): `rotate … fix` before the stage, then `slug` (no printed slug, so no fourth argument) and a silent `redact` on `fix.md` after it, each one plain `bash '<trail script>' …` call; report format unchanged.
- [X] T038 [P] [US7] Update `.apm/skills/feat/SKILL.md` (FR-017, plan "Skills, harness, agents"): Harness values gain *Preflight script*; *Commands besides the tracker* name it instead of "git for the worktree"; *Artifacts the orchestrator reads* become the brief's fields as preflight prints them; setup becomes 0 Claude Code check, 1 `bash '<preflight script>' feat '<argument>'` (lines read as data; exit 1: show `stop:` and `pointer:`; several candidates: ask, run again; `resume` and `rebase` as today after step 3), 2 `CLAUDE.md` and memory, 3 hook gate from the `hook …:` lines (gate shape and answers kept, reading rules cut), 4 board line and the building move as its own `tracker.sh set-status` call; Phase 2 step 1 is `EnterWorktree` then one Bash call `bash '<preflight script>' feat worktree '<short name>' '<on|off>' && S init … && S log … && T feat '<state file>' setup` (a `[!]` line is logged with the next boundary call and flagged at the first gate); add the quoting rule (every value from `$ARGUMENTS` or a preflight line in single quotes, `'` as `'\''`); update step numbers in Harness values (*Board-check step*, *Building move*); Phase 7 spawn block names `diff file:`. Delete the prose the scripts replace (brief lookup, classification, install, fetch, hook reading, `git branch -m`).
- [X] T039 [P] [US7] Update `.apm/skills/fix/SKILL.md` (FR-017): Harness values gain *Preflight script* and *Trail script*; *Commands besides the tracker* drop `gh issue view`, `gh api …`, `git ls-remote` and keep `gh repo view --json nameWithOwner,visibility` and `ls -d` for `rebase`; setup: 1 Claude Code check, 2 the model picks 2–4 slug words for a symptom then one preflight call (judgement refusals and the non-GitHub URL trust rule stay prose), 3 `CLAUDE.md`, 4 hook gate from `hook would branch or commit:` lines, 5 board line, 6 `EnterWorktree` then `bash '<preflight script>' fix worktree '<slug>' '<on|off>' && S init fix … && S log … && T fix '<state file>' setup` with `slug:`, `title:`, `author:`, `bug extension:`, `hooks allowed:` from mode 1; the quoting rule; Phase 4 names `diff file:`. Delete the replaced prose (`author_association`, slug building, `ls-remote --heads`, `git branch -m`, hook reading).
- [X] T040 [P] [US7] Update `.apm/skills/feat/references/harness.md`: the preflight script joins the thin-orchestrator exceptions; Fresh base says the preflight script runs the fetch. Keep it free of `/feat`-only words (`specifier`, `planner`, `tasker`, `spec.md`, `brief`, `phase <n>`, `/feat`), and check `rebase.md` and `move.md` still pass the lint grep.
- [X] T041 [US7] Edit `mise.toml` lint `run` (after T003, T036–T039): add `! grep -Eq 'worktree list --porcelain|author_association|ls-remote --heads|git branch -m|enabled: false' .apm/skills/feat/SKILL.md .apm/skills/fix/SKILL.md` and `! grep -Eq 'gh\[opsur\]_|xox\[bp\]-|github_pa\[t\]_|next free .n.|backticks and a trailing note' .apm/agents/feat-bug-assessor.agent.md .apm/agents/feat-implementer.agent.md` (write the patterns so the lint line itself matches neither the scan nor its own grep; tune against the final prose); name the new greps in the lint description; extend `tasks."test:apm"` to check `preflight.sh` and `trail.sh` land with the package.
- [X] T042 [P] [US7] Update `docs/workflow.md` (FR-019, outside any `sizes-start`/`sizes-end` block): Roles (coordinator: preflight), `0 Setup` rewritten around the two preflight calls, `7 Code review` (`reports/review.diff`), `/fix` Roles (assessor and implementer chores through `trail.sh`, redaction by the scan's rules). No diagram change (no phase or gate changes); confirm `mise run diagrams` leaves `docs/img` unchanged.
- [X] T043 [P] [US7] Update `CONTRIBUTING.md` line 36 scripts list: add `preflight.sh` (setup checks, hooks as data, `/fix` slug, worktree rename), `trail.sh` (rotate, sections, slug, redact for the bug trail) and the missing `ship.sh`; and add `tests/preflight` and `tests/trail` to the tests description if listed.
- [X] T044 [P] [US7] Update `.claude/CLAUDE.md` shell bullet: name `preflight.sh` and `trail.sh` under the Bash 3.2 / no jq / no Python rule and add `mise run test:preflight` and `mise run test:trail` to the offline tests list. Check README.md and docs for any other scripts list that needs the two names (e.g. `grep -rn 'ship.sh' README.md docs`).

**Checkpoint**: replaced prose is gone, docs match, lint wired.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [X] T045 Run `mise run lint` and fix findings (shellcheck on both scripts and all new tests, the new greps, the harness/rebase/move `/feat`-word grep, actionlint on `check.yml`).
- [X] T046 Run `mise run test:preflight`, `mise run test:trail`, `mise run test:step`, then `mise run test:secret-scan`, `test:tracker`, `test:ship`, `test:state`, `test:story`, `test:sizes`, `test:spec-number`, `test:measure`, and `mise run test:apm`; all exit 0.
- [X] T047 Run `bash .apm/skills/feat/scripts/secret-scan.sh worktree .` on the full change (new scripts, tests, docs, agents) and confirm no added line matches a rule; the only expected hit is the user's own Brief copy in `specs/016-setup-trail-scripts/feat-state.md`, left untouched.
- [X] T048 Run the by-hand steps of `specs/016-setup-trail-scripts/quickstart.md` in a scratch clone (no-such-brief stop lines, `fix '#29'` key lines, `redact` count 2 then 0), and confirm `/usr/bin/git status` shows only files related to this feature.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (1)**: none. **Foundational (2)**: after Setup, blocks all stories.
- **US1 (3) → US2 (4) → US3 (5)**: all in `preflight.sh` and `tests/preflight/run.sh`, so strictly sequential; US2 and US3 depend on US1's classification and the step order of the contract table.
- **US4 (6) → US5 (7)**: both in `trail.sh` and `tests/trail/run.sh`, sequential. The trail track (T006, T024–T031) is independent of the preflight track (T005, T007–T023): the two can run in parallel.
- **US6 (8)**: `step.sh` only; independent of US1–US5 (T033 only prints the path). T035 depends on nothing.
- **US7 (9)**: after the scripts it describes: T036 and T037 after US4/US5 (T031), T038–T039 after US1–US3 and US6, T041 after T003 and T036–T039, docs after the behaviour is final.
- **Polish (10)**: after all.

### Within a story

Script task, then its tests, in the same order; a failing test is fixed in the script before the story is closed.

### Parallel Opportunities

- T001, T002, T004 together; T005 with T006.
- Preflight track (US1–US3) alongside trail track (US4–US5) and US6, by different people or sessions.
- In US7: T036, T037, T038, T039, T040, T042, T043, T044 touch different files.

### Parallel Example

```text
Track A: T005 → T007–T015 → T016–T020 → T021–T023      (preflight.sh, tests/preflight)
Track B: T006 → T024–T031                               (trail.sh, tests/trail)
Track C: T032–T035                                       (step.sh, tests/step, code reviewer)
Then: T036–T044 in parallel where marked, T041 after the prose edits, then T045–T048.
```

---

## Implementation Strategy

### MVP First

The three P1 stories are the preflight script; setup works end to end only with all three (US1 + US2 + US3), then the skills call it (T038, T039). MVP slice: T001–T023 (preflight and its tests) with T003 wiring `test:preflight`; validate with `mise run test:preflight`.

### Incremental Delivery

1. Setup + Foundational (T001–T006).
2. US1, US2, US3 (T007–T023): preflight tested, not yet called by the skills.
3. US4, US5 (T024–T031): trail tested.
4. US6 (T032–T035): review diff file.
5. US7 (T036–T044): prose removed, skills and agents call the scripts, docs and lint.
6. Polish (T045–T048).

The plan's "Order of work" (trail, step, preflight, agents and skills, wiring and docs) is an equally valid sequence of the same tasks.

## Notes

- Do not commit; the orchestrator's later phases do.
- Quote every task's pointers to contracts rather than restating them where a contract table holds the rule; when a contract and this file differ, the contract wins and the difference is a finding.
