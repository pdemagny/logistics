# Implementation Plan: Script the setup checks, the bug-trail chores and the review diff file

**Branch**: `setup-trail-scripts` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/016-setup-trail-scripts/spec.md` (issue #29, epic #31)

## Summary

Three mechanical jobs leave the models' prose for scripts:

1. **`preflight.sh`** (new, `.apm/skills/feat/scripts/`), two modes. Mode 1,
   before `EnterWorktree`, classifies the argument, finds and reads the
   brief, checks the install, runs the board check, fetches the default
   branch, reads that branch's `.specify/extensions.yml` as data, reads a
   `/fix` issue's title and author association and builds the unique `/fix`
   slug. Worktree mode, after `EnterWorktree`, validates its arguments,
   renames the branch, checks the bug dir (`/fix`) and `.logistics.yml`,
   chained with `S init … && T <skill> … setup` in the same Bash call; it
   makes no network call. Setup drops to 3 coordinator calls before the
   first spawn, 4 for `/feat` with a board issue (the building move stays its
   own tracker call).
2. **`trail.sh`** (new), four subcommands for the bug trail: `rotate`,
   `sections`, `slug`, `redact`. `redact` sources `secret-scan.sh` for its
   rules and is stricter than the scan (any key value, whatever its length).
3. **`step.sh`** writes the review diff to `<artifact dir>/reports/review.diff`
   at each review boundary and names it under `diff file:` in each code
   reviewer's spawn block; `feat-code-reviewer` reads it instead of running
   git. `step.sh` also prints `trail script:` on the `/fix` assess, fix and
   test spawns, as it prints `ship script:` for the shipper.

The prose these replace leaves `/feat`, `/fix`, the assessor, the
implementer and the code reviewer; `mise run lint` greps that it stays gone.

The `/fix` slug is built in mode 1 (spec US3, FR-008; research R1): the
state file path holds it, so the call that creates the state file must
already know it.

## Technical Context

**Language/Version**: Bash 3.2-compatible (macOS `/bin/bash`), as `step.sh` and `ship.sh`; no jq, no Python
**Primary Dependencies**: git, gh (already required; `gh api`/`gh repo view` with gh's built-in `--jq`), the existing `secret-scan.sh` (sourced) and `tracker.sh` (`check`)
**Storage**: files only: the bug dir's reports, `<artifact dir>/reports/review.diff` (ignored by the existing `reports/.gitignore` = `*`)
**Testing**: offline bash suites `tests/preflight/run.sh` and `tests/trail/run.sh` (template repo + bare origin copied per case, stub `gh` on PATH, stub `tracker.sh` in a scratch skill layout, golden outputs with `UPDATE=1`), new cases in `tests/step/run.sh`; shellcheck via `mise run lint`
**Target Platform**: Linux and macOS shells running Claude Code
**Project Type**: workflow package (skills, agents, scripts)
**Performance Goals**: setup 3 coordinator calls before the first spawn, 4 for `/feat` with a board issue (SC-001); reviewers 0 git calls to find the diff (SC-002); one `git ls-remote` per `/fix` setup whatever the clashes; `redact` on a report of a few hundred lines well under a second
**Constraints**: no `eval`, nothing read is executed; every chore one plain `bash <script> …` call (no `$(…)`, heredocs, redirections on the agent's side); every value from `$ARGUMENTS` or a preflight line single-quoted by the coordinator (`'` as `'\''`); `secret-scan.sh` unchanged; agent report formats unchanged; no `/feat`-only words in `harness.md`, `rebase.md`, `move.md`
**Scale/Scope**: 2 new scripts (~450 and ~320 lines), ~40 lines in `step.sh`, prose cuts in 2 skills, 3 agents and `harness.md`, docs and lint

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Thin coordinators | Setup work moves from the coordinator into scripts; the coordinator reads no new artifact (it stops reading the brief: preflight prints its fields and checks its sections). No new coordinator logic beyond one quoting rule. | pass |
| II. The user decides at gates | The hook gate stays a hard gate shown by the model; refusals stop with a line. The gate now reads the hooks of the tree the run will use. No gate changes. | pass |
| III. One source of truth | The secret rules stay only in `secret-scan.sh` (`trail.sh` sources them; the assessor's hand copy is deleted). Hook classification, slug rules and the brief lookup live once, in `preflight.sh`, for both skills. The default-branch lookup mirrors `step.sh`'s (named in a comment; `step.sh` can't be sourced). `sizes.json` untouched. | pass |
| IV. Fixed report formats | No agent report format changes; reviewer inputs gain `diff file:` (a spawn key, not a report field). `step.sh` and `tests/step` change together. | pass |
| V. Small and plain | Two new bash scripts, shellcheck-clean, offline-tested; each replaces prose that drifted (#38) or costs calls. A one-liner can't hold the brief lookup, the YAML subset or redaction; folding them into `step.sh` was rejected in the brief (no state file yet at setup). | pass |

Re-check after Phase 1 design: pass (no new dependency, service or agent; the design keeps every rule in one script).

## Design

### `preflight.sh` (contract: [contracts/preflight.md](contracts/preflight.md))

- Mode 1: `preflight.sh <feat|fix> [<argument>] [slug=<words>]`. The
  coordinator passes `$ARGUMENTS` as one argument inside single quotes, each
  `'` written `'\''` (lines joined with spaces); `slug=<2–4 words>` only for
  a `/fix` symptom (the model's pick), quoted the same way. Steps, each only
  for the kinds that need it (table in the contract): classify → brief
  lookup and fields → install → board check → default branch and `git fetch
  origin <default>` → hooks → issue title and author → slug. Classification
  and refusals run first so a refused argument costs no network call.
  `resume` and `rebase` run install and hooks only (today's steps 0, 2–4),
  reading the checkout's `extensions.yml`; `empty` prints the usage and
  nothing else.
- Classification (R17): `resume` is the exact word; `rebase` the word alone
  or followed by one whitespace-free word; a longer argument starting with
  either is a symptom (`/fix`) or an idea (`/feat`). An issue reference is
  accepted only when `<o>` matches `[A-Za-z0-9][A-Za-z0-9-]*`, `<r>`
  `[A-Za-z0-9._-]+` and is not `.` or `..`, `<N>` `[1-9][0-9]*`, and a URL's
  host is exactly `github.com` with nothing after `<N>` but an optional `/`,
  `#…` or `?…`; any other URL is the other-URL kind, anything else a symptom
  or idea. So only checked parts reach `gh api repos/<o>/<r>/issues/<N>`.
- Default branch (R15): a copy of `step.sh`'s `default_branch`
  (`.apm/skills/feat/scripts/step.sh`, named in a comment): `git
  symbolic-ref -q --short refs/remotes/origin/HEAD` stripped of `origin/`,
  else the `ref: refs/heads/<x>\tHEAD` line of `GIT_TERMINAL_PROMPT=0 git
  ls-remote --symref origin HEAD`; an empty name, a leading `-`, or a name
  `git check-ref-format --branch` doesn't return unchanged → exit 2
  `preflight: error: no default branch found`.
- Worktree mode: `preflight.sh feat worktree <short-name> <on|off>` and
  `preflight.sh fix worktree <slug> <on|off>` (`on` when mode 1 printed a
  board line other than `board: off`). First it refuses (exit 2, `preflight:
  usage: …`) a short name not matching `[a-z0-9][a-z0-9-]*`, a slug not
  matching it or over 40 characters, and a last argument other than `on` or
  `off`. `/fix`: `<top>/.specify/bugs/<slug>` present → exit 1. Then the
  branch: already the target → `branch: <name>`; else `git branch -m
  <name>`, whose failure (a local branch of that name exists) is exit 1 with
  git's first line. Last, the `.logistics.yml` `[!]` line when the board is
  on and the worktree lacks the file. No `ls-remote`: a remote branch created
  between the two calls is caught at push.
- Brief lookup copies `/feat` setup step 1 exactly: an existing file as
  given; else `<name>` (no `specs/briefs/` prefix, no `.md`), which must
  match `[a-z0-9][a-z0-9-]*`; `specs/briefs/<name>.md` under this checkout's
  top level, then under every other `git worktree list --porcelain` path.
  One match: fields. Several: `brief: several` and `candidate:` lines, exit 0,
  nothing else checked (the coordinator asks, then runs mode 1 again with the
  chosen path). None: exit 1 with every path searched.
- Brief fields (R11): title, size, size note, short name, map, issue, and
  `behaviour: <n> lines` / `acceptance: <n> lines` (the count of non-blank
  lines; 0 in either is `stop: brief lacks …`). The lines themselves are not
  printed: the state file copies the brief from its path.
- Install check (R4): `.specify/` at the top level; the skill's `feat-*`
  agents as `feat-<x>.md` or `feat-<x>.agent.md` in the first of: the agents
  dir three levels above the script (APM, `install.sh` and plugin layouts,
  both the logical and the resolved path), `<top>/.claude/agents`,
  `$HOME/.claude/agents`. `/fix` also: `.specify/extensions/bug/` or one of
  the `speckit-bug-{assess,fix,test}` skills in `<top>/.claude/skills` or
  `$HOME/.claude/skills`; prints `bug extension: <version>` from
  `.specify/extensions/bug/extension.yml`: the first `version:` line at
  exactly two spaces of indent inside the column-0 `extension:` mapping (so
  not `requires:`'s `speckit_version:`), quotes stripped, kept only when it
  matches `[A-Za-z0-9][A-Za-z0-9._-]*`, else `unknown` (also when absent).
- Hooks (R2, R3): source is `git show
  refs/remotes/origin/<default>:.specify/extensions.yml` for a brief, issue
  or symptom (checked first with `git cat-file -e`; absent → no hooks), the
  checkout's file for `resume` and `rebase`. A line-based reader of the YAML
  subset Spec Kit writes (block mappings and sequences, indented or not,
  plain or quoted scalars, comments, `{}`/`[]` empties, continuation lines
  of keys it doesn't read). Anything else, a tab in the indent, an event key
  outside `[a-z][a-z0-9_]*`, or an `extension`/`command` outside
  `[A-Za-z0-9][A-Za-z0-9._-]*` is unparseable: exit 1. It reads only the
  event key, `enabled`, `extension`, `command`. "Would branch or commit"
  (FR-004): extension `git`; or `git`, `pr`, `tag`, `worktree` as a `.`/`-`/`_`
  word of the extension or command; or `commit`, `branch`, `push`, `merge`,
  `rebase`, `checkout`, `switch`, `release`, `publish` anywhere in either,
  matched in lowercase. Names only: description and prompt are not read.
- Slug (R1, R13): issue `<N>-<first three title words>` (two when over 40;
  `<N>` alone when the title has no `[a-z0-9]` word); symptom the `slug=`
  words; non-GitHub URL its last path segment; a symptom or URL base that
  normalises to nothing is `bug`. Lowercase, `[^a-z0-9]` runs → `-`,
  trimmed, cut to 40 at a `-`. One `GIT_TERMINAL_PROMPT=0 git ls-remote
  --heads origin 'fix-*'` (failure: exit 2), its `refs/heads/` names kept in
  a list; then each candidate `<base>`, `<base>-2`, `-3`, … (the base trimmed
  so the whole stays ≤ 40) is taken when `origin/<default>` or `HEAD` holds
  `.specify/bugs/<slug>` (`git cat-file -e`), `refs/heads/fix-<slug>` exists
  locally, or the list holds `refs/heads/fix-<slug>` exactly. The pattern is
  `fix-*`, not `fix-<base>*`, because a trimmed candidate need not start with
  the whole base.
- Issue (R10): `gh repo view --json nameWithOwner --jq .nameWithOwner` once,
  then `gh api repos/<o>/<r>/issues/<N> --jq '[.author_association, .title] | @tsv'`
  with the checked parts. The association counts only when `<o>/<r>` is the
  current repo, else `unknown`. A gh failure exits 1 with gh's first line.
- Output: `key: value` lines in a fixed order (contract), report and user
  text only after a fixed key, control characters replaced by spaces.
  Everything goes to stdout; exit 0 go on, 1 stop (a `stop:` line), 2 could
  not run (a `preflight: usage:` or `preflight: error:` line).

### `trail.sh` (contract: [contracts/trail.md](contracts/trail.md))

- `rotate <bug dir> <assessment|test|fix>`: `<report>.md` → `<report>-<n>.md`,
  `n` = highest existing + 1 (R8); prints the new absolute path or `none`.
- `sections <file> <assessment|test>`: prints today's line,
  `Sections: ok` or `Sections: error: <name> lacks <part>, …`, which the
  agent copies into its report.
- `slug <bug dir> <slug> <file> [<printed slug>]`: strips backticks and a
  trailing ` (…)` note from the printed slug and from the `- **Slug**:`
  bullet; `ok` when both (the printed one when given) equal `<slug>` and the
  file resolves under the bug dir, else `mismatch (<printed, else the bullet,
  else none>)`.
- `redact <file>` (R5): sources `secret-scan.sh`; a private-key block → one
  `<redacted>` line, the block running from the line the `private-key` rule
  matches through the first end line, or up to (not including) the first
  blank line or closing code fence, whichever comes first, so a prose
  mention costs one line. Each `SECRET_KEY` match's value → `<redacted>`:
  quoted values with their quotes; an unquoted value after a key that is the
  line's first token (after the indent, an optional `- `, `export ` or an
  opening quote) runs to the end of the line, keeping a trailing ` #`
  comment; an unquoted value after a key inside a line runs up to whitespace
  or `,;&)}]"'<>`. Left alone: no value (end of line, `""`, `''`) and a bare
  type or null word after `:` (`token: str`). Each vendor prefix of
  `SECRET_VENDOR` with its token characters → `<redacted>` (a leading
  non-word character of the openai-key rule kept); last, any line
  `secret_line_rule` still matches becomes `<redacted>`. Prints the count;
  the file is rewritten (temp file in the same dir, then `mv -f`) only when
  the count is not 0, so a clean file stays byte-identical. Symlinks refused.

### `step.sh` (contract: [contracts/review-diff.md](contracts/review-diff.md))

- New `diff_write`: after the first `spawn_group` of `review_batch` (and in
  `spawn_7e`), writes `git -C <top> diff --no-color --no-ext-diff <base> --`
  to `${RPATH%/*}/review.diff` through a temp file and `mv -f`, refusing a
  symlink; once per call. Every code-reviewer block prints
  `diff file: <path>` right after `diff:`. An empty diff writes nothing
  (no `spawn_group` runs); a stale file from an earlier boundary stays,
  unread (R6).
- `trail script: <SDIR>/trail.sh` on the `/fix` spawns of rows 1 (assess),
  3 (test) and 2 in bug mode, after the existing keys (R7).
- Header comment: the `diff file` and `trail script` keys.

### Skills, harness, agents

- Quoting rule (R16), in both skills' setup and in the preflight contract:
  every value from `$ARGUMENTS` or a preflight line (`title:`, `author:`,
  `short name:`, `slug:`, `hooks allowed:`, …) is written inside single
  quotes with each `'` as `'\''`.
- `/feat` SKILL: Harness values gain *Preflight script*; *Commands besides
  the tracker* name it instead of "git for the worktree"; *Artifacts the
  orchestrator reads* become the brief's fields as preflight prints them.
  Setup becomes: 0 Claude Code check; 1 `bash '<preflight script>' feat
  '<argument>'`, its lines read as data (exit 1: show `stop:` and `pointer:`,
  stop; several candidates: ask, run again; `resume`, `rebase`: as today
  after step 3); 2 `CLAUDE.md`/memory; 3 the hook gate from the `hook …:`
  lines (gate shape and answers kept, the reading rules cut); 4 the board
  line and the building move, which stays its own `tracker.sh set-status`
  call (so 4 calls with a board issue). Phase 2 step 1: `EnterWorktree`,
  then one Bash call `bash '<preflight script>' feat worktree '<short name>'
  '<on|off>' && S init … && S log … && T feat '<state file>' setup`; a `[!]`
  line it printed is logged with the next boundary call (R12) and flagged at
  the first gate. Step numbers in Harness values (*Board-check step*,
  *Building move*) follow. Phase 7: the spawn block also names `diff file:`.
- `/fix` SKILL: Harness values gain *Preflight script* and *Trail script*;
  *Commands besides the tracker* drop `gh issue view`, `gh api …`, `git
  ls-remote`, keep `gh repo view --json nameWithOwner,visibility` (assess
  gate) and `ls -d` for `rebase`. Setup: 1 Claude Code check; 2 the model
  picks 2–4 slug words for a symptom, then one preflight call; the judgement
  refusals (refactor, backport, several bugs, the `/tiny` offer) and the
  non-GitHub URL trust rule stay prose; 3 `CLAUDE.md`; 4 hook gate from
  `hook would branch or commit:` lines; 5 board line; 6 `EnterWorktree`, then
  `bash '<preflight script>' fix worktree '<slug>' '<on|off>' && S init fix
  … && S log … && T fix '<state file>' setup` with the `slug:`, `title:`,
  `author:`, `bug extension:`, `hooks allowed:` values from mode 1. Phase 4:
  `diff file:`.
- `harness.md`: the *preflight script* joins the thin-orchestrator
  exceptions; Fresh base says the preflight script runs the fetch. No
  `/feat`-only words.
- `feat-bug-assessor`: the rename, slug and section rules and the whole
  Redaction paragraph (key and prefix list) become calls to `trail.sh
  rotate`, `slug`, `redact` and `sections`, path from the `trail script` key;
  `slug`, `redact` and `sections` in one turn. When it writes no assessment
  (`Assessment: none (…)`), it skips `slug`, `redact` and `sections`, reports
  `Sections: ok` and no `Slug:` mismatch; when the stage printed no `Slug:`
  line, it calls `slug` without the fourth argument. Test mode reports
  `redact`'s count on `Redacted:` (`none` for 0). Report format unchanged.
- `feat-implementer` bug mode: `rotate … fix` before the stage, `slug` and a
  silent `redact` on `fix.md` after it (no printed slug: `slug` without the
  fourth argument). Report format unchanged.
- `feat-code-reviewer`: reads the `diff file:` when given (in parts when
  long), runs the `diff:` command only without one; still reads the tree to
  verify findings. `/tiny` unchanged (it passes the command).

### Tests, lint, CI, docs

- `tests/preflight/run.sh` + `bin/gh` (+ `expected/`): scratch skill layout
  (`<base>/.claude/skills/feat/scripts/` with `preflight.sh` and a stub
  `tracker.sh` whose line and exit come from the case; agents in
  `<base>/.claude/agents/`; `HOME` a scratch dir); template repo + bare
  origin copied per case; a second worktree for the brief search. Cases: every
  argument kind of both skills; `resume button crashes` and `rebase breaks on
  merge commits` (symptom for `/fix`, idea for `/feat`); refusals with
  pointers; an argument holding `'` and `$(touch pwned)` (printed as data, no
  file created); `../x#1` and a `github.com.evil` URL (not an issue); brief
  fields with line counts, `normal`/`big`, `tiny`/`huge`, missing fields, an
  empty Behaviour, several and no match; missing `.specify/`, agent, bug
  extension; `bug extension:` version read from the `extension:` mapping, not
  `speckit_version`; hooks (enabled, `enabled: false`, indented and
  indentless lists, `{}`, empty, a hostile command, a bad event key,
  unparseable; `push`, `autocommit` and `open-pr` flagged; a committing hook
  only on the fetched origin is listed, a local-only one is not; `resume`
  reads the checkout's file); board fail; fetch fail; no `origin/HEAD`
  (found through `ls-remote --symref`) and a hostile default name (exit 2);
  issue title/author (current repo, other repo, non-GitHub URL, gh failure);
  slug dedupe against the tree, a local and a remote branch (one `ls-remote`,
  counted through a wrapper), the 40-character cap with a suffix, a title
  with no word (`<N>`), symptom words that normalise to nothing (`bug`),
  unreachable remote (exit 2); worktree mode rename, rerun on the target
  branch, bad short name / slug / `on|off` (exit 2), a local branch or bug
  dir that appeared since mode 1 (exit 1), `[!]` line; usage and not a repo
  (exit 2); a bash 3.2 construct grep.
- `tests/trail/run.sh` (+ `fixtures/`, `expected/`): every `SECRET_VENDOR`
  name must have a sample (the test fails on a new rule without one); samples
  and key values built by concatenation at run time so no tracked file
  matches the scan; each redacted file is scanned with `secret-scan.sh
  worktree` in a scratch repo (exit 0 expected); the named cases of US4,
  including a multi-word unquoted value after a leading key (also indented,
  after `- ` and `export `, and with a trailing ` #` comment) and a key inside
  a line; idempotence; byte-identical clean file; a block without an end
  (ends at the blank line or closing fence); a report that mentions the
  begin marker in prose keeps every later line and section; `rotate` with -1
  and -3; `sections` ok and missing; `slug` ok, backticks and note, outside
  the bug dir, without the printed slug; usage exits; bash 3.2 grep.
- `tests/step/run.sh`: a review boundary writes `reports/review.diff` equal
  to `git diff <base>`; a later boundary rewrites it; an empty diff writes
  none; 7e names the same file; `diff file:` and `trail script:` keys in the
  goldens (`UPDATE=1`, then review `git diff tests/step/expected`).
- `mise.toml`: `test:preflight`, `test:trail`; lint shellcheck of
  `tests/preflight/run.sh tests/preflight/bin/gh tests/trail/run.sh` (the
  scripts are under the existing glob); a grep that the replaced prose is
  gone: in both SKILL.md files `worktree list --porcelain|author_association|
  ls-remote --heads|git branch -m|enabled: false`, in the assessor and the
  implementer `gh\[opsur\]_|xox\[bp\]-|github_pa\[t\]_|next free .n.|backticks
  and a trailing note`; `test:apm` checks `preflight.sh` and `trail.sh`
  land; the lint description names the new greps.
- `.github/workflows/check.yml`: `mise run test:preflight` and
  `mise run test:trail`.
- `docs/workflow.md`: Roles (coordinator: preflight), 0 Setup rewritten
  around the two preflight calls, 7 Code review (`reports/review.diff`),
  `/fix` Roles (assessor and implementer chores through `trail.sh`, redaction
  by the scan's rules). `CONTRIBUTING.md`'s scripts line gains `preflight.sh`,
  `trail.sh` (and the missing `ship.sh`). `.claude/CLAUDE.md`'s shell bullet
  names the two scripts and their tests. No diagram changes (no phase or
  gate changes).

### Every added line passes the secret scan

The shipper scans the staged diff, so no added line may match a rule:
docs, prose and tests name the rules (`private-key`, `openai-key`, …)
instead of quoting their prefixes, and test samples are concatenated at run
time (as `tests/ship` does). This amend reworded spec.md's private-key
scenario, so `secret-scan.sh worktree specs/016-setup-trail-scripts` now flags
only feat-state.md's Brief copy, which is the user's text to reword before
phase 8.

## Project Structure

### Documentation (this feature)

```text
specs/016-setup-trail-scripts/
├── plan.md              # this file
├── research.md          # decisions R1–R17
├── data-model.md        # preflight result, hook entry, slug, trail report, review diff file
├── quickstart.md        # validation run
├── contracts/
│   ├── preflight.md     # CLI, output keys, exit codes
│   ├── trail.md         # four subcommands
│   └── review-diff.md   # step.sh's file and spawn keys
└── tasks.md             # phase 5
```

### Source Code (repository root)

```text
.apm/skills/feat/scripts/
├── preflight.sh         # new
├── trail.sh             # new
├── step.sh              # diff_write, diff file and trail script keys
└── secret-scan.sh       # unchanged, sourced by trail.sh
.apm/skills/feat/SKILL.md, .apm/skills/fix/SKILL.md
.apm/skills/feat/references/harness.md
.apm/agents/feat-bug-assessor.agent.md, feat-implementer.agent.md, feat-code-reviewer.agent.md
tests/preflight/{run.sh,bin/gh,expected/}   # new
tests/trail/{run.sh,fixtures/,expected/}     # new
tests/step/{run.sh,expected/}
mise.toml, .github/workflows/check.yml
docs/workflow.md, CONTRIBUTING.md, .claude/CLAUDE.md
```

**Structure Decision**: the scripts sit beside `step.sh` and `ship.sh` in
`.apm/skills/feat/scripts/`, so all three installers ship them with no
manifest change; `/fix` reaches them as `../feat/scripts/`.

## Order of work

1. `trail.sh` + `tests/trail` (no dependency on the rest).
2. `step.sh` review diff file and `trail script` key + `tests/step`.
3. `preflight.sh` + `tests/preflight`.
4. Agents (assessor, implementer, reviewer), then both skills and
   `harness.md`.
5. `mise.toml`, CI, docs; `mise run lint` and every `mise run test:*`.

## Complexity Tracking

No constitution violation to justify.
