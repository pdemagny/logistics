# Feature Specification: Script the setup checks, the bug-trail chores and the review diff file

**Feature Branch**: `setup-trail-scripts`

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "Script the setup checks, the bug-trail chores and the review diff file (issue pdemagny/logistics#29; part of epic #31)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Setup runs as a few scripted calls (Priority: P1)

Someone runs `/feat` or `/fix`. Today the coordinator classifies the argument, finds the brief, checks the installation and the Spec Kit hooks, fetches, reads the issue's title and author association and builds a unique `/fix` slug, one model call at a time (median 4 calls for `/feat`, 8 for `/fix`, up to 17). With this feature, one preflight call before the worktree exists returns all of that as key lines, including the unique `/fix` slug, and one call after the worktree exists renames the branch and checks the board file. Setup takes 3 coordinator calls before the first spawn (preflight, worktree creation, worktree mode chained with state init and tracker setup), 4 for `/feat` with a board issue (the building move stays its own tracker call), plus reading the project's `CLAUDE.md` and showing the hook gate when one applies.

**Why this priority**: It is the largest share of the gain (fewer calls, no drifting prose) and the entry point of every run.

**Independent Test**: Call the preflight with each argument kind, for each skill, against throwaway repos and a stub `gh`, and check the key lines and the exit code.

**Acceptance Scenarios**:

1. **Given** an argument that is a brief (path or short name found in this checkout or any worktree), **When** `/feat` preflight runs, **Then** it prints the kind `brief`, the brief's fields (size, short name, and `behaviour: <n> lines` and `acceptance: <n> lines`, not the lines themselves), and whether it is this checkout's `specs/briefs/<name>.md`; `normal` reads as medium and `big` as large.
2. **Given** a brief of size `tiny` or `huge`, or one missing fields, **When** preflight runs, **Then** it exits 1 with a line saying why.
3. **Given** an issue argument (`#N`, `owner/repo#N`, URL) given to `/feat`, or a brief given to `/fix`, **When** preflight runs, **Then** it exits 1, names the kind and prints the pointer to the right command.
4. **Given** the arguments `resume`, `rebase`, `rebase <PR>`, a symptom, or no argument, **When** preflight runs, **Then** it prints that kind and exits 0 (rebase targets are not picked here). `resume` is the exact word and `rebase` the word alone or followed by one whitespace-free word; a longer argument starting with either (`resume button crashes`) is a symptom for `/fix` and an idea for `/feat`.
5. **Given** `.specify/`, the `feat-*` agents (plain or `logistics:`-prefixed) or, for `/fix`, the bug extension is missing, **When** preflight runs, **Then** it exits 1 and names what is missing.
6. **Given** a `/fix` argument that is a GitHub issue of the current repo, **When** preflight runs, **Then** it prints the issue's title and the report author's association; for an issue elsewhere or a non-GitHub URL the association is `unknown`, for a symptom it is `user`. An `owner/repo#N` or `https://github.com/<o>/<r>/issues/<N>` whose parts are not a valid owner, repository and issue number (`../x#1`) is not an issue of any repo: it is read as another URL or a symptom.
7. **Given** a `/fix` issue or symptom, **When** preflight runs (before the worktree exists), **Then** it builds, dedupes and prints the unique slug (`slug:`), because the `/fix` state file path holds the slug and the call that creates the state file must already know it.
8. **Given** the worktree is entered, **When** `preflight.sh <skill> worktree` runs, **Then** it checks its arguments (exit 2 on a bad short name, slug or `on|off`), renames the branch (`<short-name>` or `fix-<slug>`; exit 1 when a local branch of that name exists), for `/fix` exits 1 when the bug dir exists in the worktree, and prints a `[!]` line if the board is on and `.logistics.yml` is not in the worktree.

---

### User Story 2 - Hooks and base are checked as data, with clear stops (Priority: P1)

Before any worktree exists, preflight fetches the default branch and reads the Spec Kit hooks as data from that branch's `.specify/extensions.yml` (the file the run's worktree will hold), so the user sees only what matters at the hard gate and the run starts from a fresh base.

**Why this priority**: These are the checks that stop a run safely; a hook that commits or a stale base are costly misses.

**Independent Test**: Run preflight against `extensions.yml` fixtures (enabled, `enabled: false`, unparseable), a failing stub fetch, a failing board check and an unreachable remote, and check the exit codes.

**Acceptance Scenarios**:

1. **Given** hooks in `extensions.yml`, **When** `/feat` preflight runs, **Then** it lists those that won't run and those that would branch or commit (by the name rule of FR-004: `push`, `autocommit`, `open-pr` all match), as the two sections of the gate; for `/fix` it lists those that would branch or commit. Each hook shows its event key, extension and command; an `enabled: false` entry is ignored.
2. **Given** an `extensions.yml` that cannot be parsed, or whose event key, `extension` or `command` holds characters outside its pattern, **When** preflight runs, **Then** it exits 1 (it may hide a hook that commits).
3. **Given** a committing hook that only the fetched default branch's `extensions.yml` holds (the local checkout is stale), **When** preflight runs for a brief, issue or symptom, **Then** the hook is listed at the gate.
4. **Given** `.logistics.yml` exists and the board check fails, **When** preflight runs, **Then** it exits 1.
5. **Given** `git fetch origin <default>` fails, **When** preflight runs, **Then** it exits 1.
6. **Given** a usage error, a directory that is not a git repo, or an unreachable remote during the slug check, **When** preflight runs, **Then** it exits 2.
7. **Given** hostile content in a title, brief or `extensions.yml`, **When** preflight runs, **Then** nothing is executed or evaluated and the content is printed as data lines.

---

### User Story 3 - `/fix` slug is unique across dir, local and remote (Priority: P1)

For a `/fix` run, preflight (before the worktree exists, since the state file path holds the slug) builds `<N>-<2-3 title words>` from an issue, from the words the model picked for a symptom, or from a non-GitHub URL's last path segment, in lowercase `[a-z0-9-]` of at most 40 characters. It appends `-2`, `-3`, ... while the bug dir (in the fetched default branch or `HEAD`), the local branch `fix-<slug>` or the remote branch exists. Worktree mode then only renames the branch, which fails when the local branch exists, and checks the bug dir in the worktree; a remote branch created in the seconds between the two calls is caught at push.

**Why this priority**: A clash found at push time wastes a whole run.

**Independent Test**: In throwaway repos with a bare remote, create each clash kind in turn and check the slug gets the next free suffix.

**Acceptance Scenarios**:

1. **Given** the bug dir, a local branch or a remote branch already uses the slug, **When** preflight runs, **Then** it prints the slug with the first free `-n` suffix.
2. **Given** the remote is unreachable, **When** preflight runs for a `/fix` issue or symptom, **Then** it exits 2 rather than risk a clash at push time.
3. **Given** a long title, **When** the slug is built, **Then** it is at most 40 characters of `[a-z0-9-]`; a title with no letter or digit word gives `<N>` alone, and symptom words that normalise to nothing give `bug`.
4. **Given** the bug dir or the local branch `fix-<slug>` appeared after preflight, **When** worktree mode runs, **Then** it exits 1 naming the clash.

---

### User Story 4 - Bug reports are redacted by the same rules as the scan (Priority: P2)

The assessor and the implementer in `/fix` call `trail.sh redact <file>`, which rewrites the whole file, replacing every secret-looking value with `<redacted>`, and prints the count. It reuses the secret scan's vendor prefixes and key names, so there is one list. A key's value is redacted whatever its length (`password=hunter2` becomes `password=<redacted>`), a vendor token becomes `<redacted>` alone, a private-key block becomes one `<redacted>` line, and a key with no value (`token:` at line end, `token: str`, `password: ""`) is left alone. The assessor runs it on `assessment.md` and `test.md` and reports the `Redacted:` count as today; the implementer runs it on `fix.md` silently.

**Why this priority**: It removes a hand copy that already drifted and a late hard stop, but the run works without it.

**Independent Test**: Pass a fixture for each scan rule, and for key values below the scan thresholds, through `redact` and run the scan on the output.

**Acceptance Scenarios**:

1. **Given** a file with a value for each scan rule, **When** `redact` runs, **Then** the output never matches the secret scan.
2. **Given** `password=hunter2`, **When** `redact` runs, **Then** the line is `password=<redacted>`.
3. **Given** a vendor token or a private-key block, **When** `redact` runs, **Then** the token becomes `<redacted>` and the block (the private-key begin line through its end line) becomes a single `<redacted>` line.
4. **Given** `token:` at the end of a line, `token: str` or `password: ""`, **When** `redact` runs, **Then** those lines are unchanged.
5. **Given** a file with nothing secret, **When** `redact` runs, **Then** it is byte-identical and the count is 0.
6. **Given** a secret inside a code excerpt, **When** `redact` runs, **Then** it is redacted too (every line is covered).
7. **Given** a line whose first token is the key and whose value is unquoted and holds spaces (`password: correct horse battery staple`, also after an indent, `- `, `export ` or an opening quote), **When** `redact` runs, **Then** the value is redacted to the end of the line (`password: <redacted>`), keeping only a trailing ` #` comment; a key inside a line (`url?token=abc&x=1`) still stops at whitespace or punctuation.

---

### User Story 5 - Report renames, headings and slugs are checked by script (Priority: P2)

The assessor and the implementer stop renaming earlier reports and comparing slugs by hand. `trail.sh rotate <bug dir> <assessment|test|fix>` renames an existing report to `<report>-<n>.md` with the next free `n`. `trail.sh sections <file> <assessment|test>` checks the required parts and prints today's `Sections:` line. `trail.sh slug <bug dir> <slug> <file> [<printed slug>]` compares the slug given, the one the stage printed (backticks and a trailing note stripped) and the report's `- **Slug**:` bullet, checks the file sits under the bug dir, and prints `ok` or `mismatch (<printed>)`.

**Why this priority**: Saves about 2.4 calls per assessor spawn and about 1 per implementer spawn.

**Independent Test**: Run each subcommand in a throwaway bug dir with fixtures.

**Acceptance Scenarios**:

1. **Given** `assessment.md` and `assessment-1.md` exist, **When** `rotate` runs for `assessment`, **Then** the former becomes `assessment-2.md`; with no earlier report nothing is renamed.
2. **Given** a report missing a required part, **When** `sections` runs, **Then** the printed `Sections:` line says so; a complete one prints the passing line.
3. **Given** matching slugs, **When** `slug` runs, **Then** it prints `ok`; **given** a printed slug in backticks with a trailing note, it is stripped before comparing; **given** any disagreement or a file outside the bug dir, it prints `mismatch (<printed>)`.

---

### User Story 6 - Code reviewers read the diff from a file (Priority: P2)

At each review boundary, `step.sh` writes the diff it already prepares to `<artifact dir>/reports/review.diff` (ignored, never committed), overwriting it each time and writing nothing when the diff is empty. The reviewer's spawn block names it under `diff file:`, next to the diff command, and each reviewer reads that file instead of running git to find the diff; it still reads the tree to verify findings. `/tiny` keeps passing a diff command, and the reviewer takes either input, running the command only when it has no file.

**Why this priority**: About 3 git calls per reviewer spawn (355 spawns measured).

**Independent Test**: Run the `step.sh` review boundary in fixtures and compare the file with the printed diff.

**Acceptance Scenarios**:

1. **Given** a non-empty diff at the review boundary, **When** `step.sh` runs, **Then** `reports/review.diff` holds the same diff it prints and the spawn block has a `diff file:` line.
2. **Given** a later review boundary, **When** `step.sh` runs, **Then** the file is rewritten.
3. **Given** an empty diff, **When** `step.sh` runs, **Then** no file is written and no reviewer is spawned.
4. **Given** `/tiny`'s review spawn with only a diff command, **When** the reviewer runs, **Then** it uses the command.

---

### User Story 7 - The replaced prose is gone and the docs match (Priority: P3)

`/feat`, `/fix`, the assessor, the implementer and the code reviewer lose the prose the scripts replace (including the assessor's key and prefix list), each skill's Harness values name the script paths, agents receive `trail.sh`'s path in their prompt, and `docs/workflow.md` and the scripts list in the docs describe the new scripts.

**Why this priority**: Without it the old and new rules would both exist.

**Independent Test**: `mise run lint` greps that the replaced prose is gone; the offline tests pass.

**Acceptance Scenarios**:

1. **Given** the change is complete, **When** `mise run lint` runs, **Then** shellcheck is clean on the new scripts and tests and the grep for the replaced prose finds none.
2. **Given** the change is complete, **When** `mise run test:preflight` and `mise run test:trail` run, **Then** they pass offline, with the other offline tests.

### Edge Cases

- A brief name matching in several worktrees, or in none.
- An issue URL that is not on GitHub; an issue in another repo.
- An `extensions.yml` with no hooks, an empty file, or only `enabled: false` hooks.
- A secret spanning no line break next to a key with no value on the same line.
- A private-key block with no end line, or a report that only mentions the begin marker in prose: the block ends at the first end line, or at the first line that is neither key body nor a `Proc-Type:`/`DEK-Info:` header (a blank line, a code fence, a heading, a bullet, prose), whichever comes first (the end line is part of the block; the other line is kept), so the rest of the report survives even with a heading or a bullet right after the mention.
- `rotate` when `assessment-1.md` and `assessment-3.md` exist (`assessment-4.md`: the highest n plus one).
- `slug` called without the optional printed slug.
- `redact` run twice (second count 0, file unchanged).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `preflight.sh <feat|fix> <arg> ...` MUST classify the argument as brief, issue, symptom, `resume`, `rebase [PR]`, empty, or a refused kind (a brief to `/fix`; an issue or idea to `/feat`) and print the pointer to the right command for refused kinds. `resume` MUST be the exact word and `rebase` the word alone or followed by one whitespace-free word; anything longer is a symptom or idea. An issue reference MUST be accepted only when its owner matches `[A-Za-z0-9][A-Za-z0-9-]*`, its repository `[A-Za-z0-9._-]+` other than `.` and `..`, its number `[1-9][0-9]*`, and, for a URL, the host is exactly `github.com` with nothing after the number but an optional `/`, `#…` or `?…`; anything else is another URL or a symptom.
- **FR-002**: For a brief, it MUST print size, short name and the number of non-blank lines of Behaviour and of Acceptance (`behaviour: <n> lines`, `acceptance: <n> lines`, not the lines), refuse `tiny` and `huge`, refuse a brief with either section empty, read `normal` as medium and `big` as large, and say whether the brief is this checkout's `specs/briefs/<name>.md`; it MUST search this checkout and every worktree.
- **FR-003**: It MUST check `.specify/`, the `feat-*` agents (plain or `logistics:`-prefixed) and, for `/fix`, the bug extension.
- **FR-004**: It MUST read `.specify/extensions.yml` as data (event key, `enabled`, `extension`, `command`; `enabled: false` ignored) and report, for `/feat`, the hooks that won't run and those that would branch or commit, and for `/fix`, those that would branch or commit; an unparseable file, or an event key outside `[a-z][a-z0-9_]*` or an `extension` or `command` outside `[A-Za-z0-9][A-Za-z0-9._-]*`, MUST exit 1. For a brief, an issue or a symptom it MUST read the file from the fetched `origin/<default>` tree (absent there: no hooks); for `resume` and `rebase`, from the checkout. A hook would branch or commit when its extension is `git`, when its extension or command has a word starting with `git`, or `pr`, `pull`, `tag` or `worktree`, as one of its `.`, `-` or `_`-separated words, or when either contains `commit`, `branch`, `push`, `merge`, `rebase`, `checkout`, `switch`, `release`, `publish`, `pullrequest`, `amend`, `squash` or `cherry` anywhere (so `autocommit`, `gitflow`, `create-pull-request` and `cherry-pick` match); a false positive only adds a line to the gate.
- **FR-005**: It MUST run the board check when `.logistics.yml` exists, and fetch `origin <default>`, finding the default branch as `step.sh` does (`origin/HEAD`, else `ls-remote --symref`, the name checked; none found: exit 2); a failed board check or fetch MUST exit 1.
- **FR-006**: For `/fix` from a GitHub issue it MUST print the title and author association (`unknown` outside the current repo or for a non-GitHub URL; `user` for a symptom).
- **FR-007**: Output MUST be key lines. Exit 0 means go on; exit 1 means stop with a line saying why (missing install, refused kind, `tiny`/`huge` brief, brief missing fields, failed board check, failed fetch, unparseable `extensions.yml`, unreadable issue, in worktree mode a branch that can't be renamed or a bug dir already in the worktree); exit 2 means the script could not run (usage, including a bad worktree-mode argument, not a git repo, no default branch, remote unreachable for the slug check).
- **FR-008**: For a `/fix` issue or symptom, mode 1 MUST build, dedupe and print the unique slug as specified in User Story 3, using `git ls-remote --heads origin` for the remote check and exiting 2 if the remote is unreachable (mode 1, not worktree mode: the `/fix` state file path holds the slug, so the call that creates it must already know it). `preflight.sh <feat|fix> worktree <short-name|slug> <on|off>` MUST first refuse (exit 2) a short name not matching `[a-z0-9][a-z0-9-]*`, a slug not matching it or over 40 characters, and a last argument other than `on` or `off`; then rename the branch to `<short-name>` or `fix-<slug>` with `git branch -m` (exit 1 when it fails, such as when a local branch of that name exists), for `/fix` exit 1 when the bug dir exists in the worktree, and print a `[!]` line when the board is on and `.logistics.yml` is not in the worktree. It makes no network call.
- **FR-009**: Issue titles, issue bodies, briefs and `extensions.yml` MUST be treated as data: never executed or evaluated, printed as data lines. The coordinators MUST write every value taken from `$ARGUMENTS` or a preflight line into a Bash command inside single quotes, each `'` written as `'\''`.
- **FR-010**: `trail.sh` MUST provide `rotate`, `sections`, `slug` and `redact` with the behaviour in User Stories 4 and 5.
- **FR-011**: `trail.sh redact` MUST source the secret scan's rules (one list), add only the stricter value matching, keep the key name, and leave the secret scan's behaviour unchanged.
- **FR-012**: After `redact`, the secret scan MUST NOT match the file, for every scan rule and for key values below its thresholds.
- **FR-013**: The assessor MUST call `rotate`, `sections`, `slug` and `redact` (reporting `Redacted:` as today, on `assessment.md` and `test.md`); the implementer MUST call `rotate`, `slug` and `redact` (on `fix.md`, silently); their report formats do not change. When the assessor writes no assessment (`Assessment: none`), it skips `slug`, `redact` and `sections` and reports `Sections: ok`; when the stage printed no slug, it calls `slug` without the printed slug.
- **FR-014**: Each chore MUST be one plain `bash <script> ...` call, with no `$(...)`, heredocs or redirections, so it works in a worktree and for an agent without Edit.
- **FR-015**: `step.sh`'s diff preparation MUST write the diff to `<artifact dir>/reports/review.diff` (ignored by git), overwrite it at each review boundary, write none for an empty diff, and print the path under `diff file:` in the reviewer's spawn block, not in the inputs file.
- **FR-016**: The code reviewer MUST take either `diff file:` or `diff:` and run the command only without a file; `/tiny` MUST keep passing the command.
- **FR-017**: The prose these scripts replace MUST be removed from `/feat`, `/fix`, the assessor, the implementer and the code reviewer, and each skill's Harness values MUST name the script paths; `harness.md`, `rebase.md` and `move.md` MUST stay free of `/feat`-only words.
- **FR-018**: The scripts MUST live in `.apm/skills/feat/scripts/`, be Bash 3.2 with no jq and no Python, be shellcheck clean, and have offline tests in `tests/preflight` and `tests/trail` (throwaway repos, stub `gh`, fixtures) wired to `mise run test:preflight`, `mise run test:trail` and `mise run lint`; `step.sh`'s tests cover FR-015.
- **FR-019**: `docs/workflow.md` and the docs' scripts list MUST describe the new scripts; diagrams change only if a phase or gate changes.
- **FR-020**: Out of scope and unchanged: picking `rebase` targets, the `tasks.md` reader, other spawn-list files, `/tiny`'s and `/brief`'s setup, a `measure.py` metric, the model's judgement calls in setup, and the stages between the chores.

### Key Entities

- **Preflight result**: key lines for the argument kind, brief fields, install and hook findings, base state, issue title and association, plus an exit code.
- **Hook entry**: event key, `enabled`, extension and command, from `extensions.yml`.
- **Slug**: `<N>-<words>` (`<N>` alone when the title has no word; a symptom's words or a non-GitHub URL's last segment, `bug` when they normalise to nothing), `[a-z0-9-]`, at most 40 characters, with a numeric suffix on clash; built by preflight mode 1.
- **Bug trail report**: `assessment.md`, `test.md`, `fix.md` in a bug dir, with earlier ones rotated to `<report>-<n>.md`.
- **Review diff file**: `reports/review.diff`, the diff of the current review boundary.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the first `/feat` and `/fix` runs after merge, setup takes 3 coordinator calls before the first spawn, 4 for `/feat` with a board issue (the building move stays its own tracker call), from medians of 4 and 8, checked by hand.
- **SC-002**: On those runs, code reviewers make no git calls to find the diff, checked by hand.
- **SC-003**: For every secret-scan rule and for short key values, 100% of redacted fixtures pass the scan, and a file with nothing secret comes out unchanged.
- **SC-004**: Every argument kind of both skills, every exit code case (0, 1, 2), and every slug clash kind has a passing offline test.
- **SC-005**: A review boundary's file equals the printed diff, is rewritten at the next boundary, and is absent for an empty diff, in tests.
- **SC-006**: `mise run lint`, `mise run test:preflight`, `mise run test:trail` and the other offline tests pass, and the replaced prose appears nowhere in the skills and agents.
- **SC-007**: The assessor's and implementer's chores average no hand-run `mv`/`ls` calls (from about 2.4 and 1 per spawn).

## Assumptions

- `tracker.sh check` and `secret-scan.sh` keep their current interfaces; `trail.sh` sources the latter as `tracker.sh` does.
- The coordinator still handles the judgement calls in setup (refusing a refactor, a backport or several bugs in one report, the `/tiny` offer, a symptom's slug words) and passes the symptom's words to preflight mode 1 (`slug=<words>`).
- The hook gate is still shown by the model, which logs the user's answer.
- "Would branch or commit" is detected by names only (the event key, extension and command, by FR-004's rule); the hook's description and prompt are not read, so a committing hook whose names hold none of the listed words passes the gate unflagged, where today's model reading the whole entry might catch it.
- Over-redacting code excerpts (`token = getToken()`) is acceptable, since the code is in the repo.
- `fix.md` redaction needs no count in the implementer's report; the shipper's scan still guards the commit.
- `reports/review.diff` is covered by the existing ignore rule for reports, or a rule is added with the change.
