# /feat state: Script the setup checks, the bug-trail chores and the review diff file

- Branch: setup-trail-scripts Worktree: /home/pierre/Projects/logistics/.claude/worktrees/brief-29
- Size: medium
- Agents: specifier aed15d365948256fa, planner ace2a5d976dd15d5d, tasker a7d941427d8c1eb7e (for SendMessage)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, never co-authored; PR body says Closes #29, never a commit message. In this worktree call /usr/bin/git directly, one plain command per call (no heredocs, pipes, $(…)); shell is zsh, rm/cp/mv are -i aliases (use command rm -f etc.). The rtk hook rewrites gh/mise/cat calls: type rtk gh …, rtk mise …, in a response of their own. Scripts in .apm/skills/feat/scripts/: Bash 3.2, no jq, no Python, shellcheck clean, offline tests under tests/<name> wired in mise.toml; mise run lint and the offline tests (mise run test:*) and mise run test:apm before committing. sizes.json is the source of sizes.tsv and the generated blocks (mise run diagrams); never edit between sizes-start/sizes-end, CHANGELOG.md, versions or .release-please-manifest.json by hand. Keep /feat-only words out of harness.md, rebase.md, move.md. Agent frontmatter has no model/effort/tools/color. Update docs/workflow.md and the scripts list in the docs; new docs pages need title and weight.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #29

## Brief

- Size: medium — ~50–55 tasks expected: two new Bash 3.2 scripts (`preflight.sh` with two modes for two skills, `trail.sh` with four subcommands), each with offline tests, a diff file from `step.sh`'s existing `diff_prep`, and prose removed from `/feat`, `/fix`, the assessor, the implementer and the code reviewer
- Short name: setup-trail-scripts
- Kind: feat
- Issue: #29

## Why
`/feat` and `/fix` still do mechanical work in prose, and prose drifts and
costs calls. For whoever runs the two skills:
- Setup classifies the argument, checks the installation and the Spec Kit
  hooks, fetches, finds the brief, reads the issue's title and author
  association, and builds a unique `/fix` slug, one model call at a time.
- The assessor redacts secrets from its reports by following a key and
  prefix list written in prose. That list is a hand copy of
  `secret-scan.sh`'s rules and already drifted once (#38 widened it to
  catch up). A missed value is caught only at the very end, when the
  shipper's scan stops the ship or `tracker.sh create-issue` refuses the
  issue body, and someone then fixes the report by hand.
- The assessor and the implementer rename earlier reports, check report
  headings and compare slugs by hand.
- Each code reviewer finds its own way to the diff that `step.sh` already
  prepared.

Part of epic #31 (rules to scripts for reliability; fewer model calls).

## Today
Measured on every run transcript on disk (88 `/feat`, 23 `/fix`, all
versions, counted with a one-off script, not `measure.py`):
- Setup, coordinator model calls before the first spawn: median **8** for
  `/fix`, **4** for `/feat` (up to 17 and 16). Failed calls in setup are
  rare (median 0).
- Code reviewer (355 spawns): about **3** git calls each (diff, status, log)
  to find and read the diff, out of a median of ~8 calls. Since #28,
  `step.sh`'s `diff_prep` already runs `git add -N`, the merge-base and the
  empty check, and prints `diff: git diff <base>`. Each reviewer then runs
  it again itself.
- Assessor (67 spawns): about **2.4** `mv`/`ls` calls per spawn for the
  report renames; implementer about 1.
- Redaction: rule text in `.apm/agents/feat-bug-assessor.agent.md`
  ("Redaction"), applied by the model to the output sections of
  `assessment.md` and `test.md` only. `fix.md` is not redacted.

## Behaviour
- **`preflight.sh <feat|fix> <arg> …`** (before `EnterWorktree`), one call
  for what setup can know before the worktree exists:
  - the argument's kind: brief (path or short name, searched in this
    checkout and every worktree, as `/feat` setup step 1 does today),
    issue (`#N`, `owner/repo#N`, URL; GitHub or not), symptom, `resume`,
    `rebase [PR]`, empty, or a kind the skill refuses (a brief given to
    `/fix`, an issue or idea given to `/feat`), printed with the pointer to
    the right command;
  - for a brief, its fields (size, short name, behaviour, acceptance;
    `tiny` and `huge` refused; `normal` and `big` read as medium and
    large) and whether it is this checkout's `specs/briefs/<name>.md`
    (the deletion rule after phase 2);
  - the installation checks: `.specify/`, the `feat-*` agents (plain or
    `logistics:`-prefixed), and for `/fix` the bug extension;
  - the Spec Kit hooks from `.specify/extensions.yml`, read as data,
    replacing `/feat` setup step 4 and `/fix` setup step 5: for `/feat`,
    those that won't run and those that would branch or commit, as the two
    sections of today's gate; for `/fix`, those that would branch or
    commit. It reads each hook's event key, `enabled` (an `enabled: false`
    entry is ignored), `extension` and `command`. A file it can't parse
    stops the run (exit 1): it may hide a hook that commits. The model
    shows them at the hard gate and logs the user's answer;
  - the board check (`tracker.sh check`) when `.logistics.yml` exists;
  - `git fetch origin <default>` (the fresh base);
  - for `/fix` from a GitHub issue: its title and the report author's
    association (`unknown` outside the current repo or for a non-GitHub
    URL; `user` for a symptom).
  - Output is key lines the coordinator reads, the convention `step.sh`
    uses. Exit 0: go on. Exit 1: stop, with a line saying why: a missing
    install, a kind the skill refuses, a `tiny` or `huge` brief, a brief
    missing fields, a failed board check (it stops today), a failed
    `git fetch` (a stale base is what the fetch prevents), an unparseable
    `extensions.yml`. Exit 2: the script could not run (usage, not a git
    repo, the remote unreachable for the slug check).
- **`preflight.sh <feat|fix> worktree …`** (after `EnterWorktree`), chained
  with `S init … && T <skill> … setup` in one Bash call: renames the branch
  (`<short-name>` or `fix-<slug>`), checks that `.logistics.yml` is in the
  worktree (the `[!]` line when not), and for `/fix` builds the unique
  slug: `<N>-<2–3 title words>` from an issue, from the words the model
  picked for a symptom, or from a non-GitHub URL's last path segment;
  lowercase `[a-z0-9-]`, at most 40 characters; `-2`, `-3`, … while the
  bug dir, the local branch `fix-<slug>` or the remote branch exists. The
  remote check stays today's `git ls-remote --heads origin fix-<slug>`,
  run by the script: setup fetches only `<default>`, so local `origin/fix-*`
  refs can be stale. If the remote is unreachable, the script stops
  (exit 2) rather than risk a clash at push time.
- Setup then takes about three coordinator calls in both skills
  (preflight, `EnterWorktree`, worktree + init), plus reading the
  project's `CLAUDE.md` and the hook gate when one applies.
- **`trail.sh`**, called by the assessor and the implementer in `/fix`:
  - `rotate <bug dir> <assessment|test|fix>`: renames an existing report to
    `<report>-<n>.md`, the next free `n`;
  - `sections <file> <assessment|test>`: checks the required parts and
    prints today's `Sections:` line;
  - `slug <bug dir> <slug> <file> [<printed slug>]`: compares the slug
    given, the one the stage printed (backticks and a trailing note
    stripped) and the report's `- **Slug**:` bullet, and checks that the
    file sits under the bug dir; prints `ok` or `mismatch (<printed>)`;
  - `redact <file>`: rewrites the whole file in place, replacing every
    secret-looking value with `<redacted>`, and prints the count. It
    sources `secret-scan.sh` for the vendor prefixes and the key names,
    as `tracker.sh` does. A key's value is redacted whatever its length or
    form, so redaction is stricter than the scan. The key name stays
    (`password=hunter2` → `password=<redacted>`; today's prose replaced the
    key too), since `<redacted>` can't match the scan. A vendor token
    becomes `<redacted>` on its own, and a private-key block, from
    its begin line to its end line, becomes one `<redacted>` line. A key with
    no value (`token:` at the end of a line, `token: str`, `password: ""`)
    is left as it is.
  - The assessor runs `redact` on `assessment.md` and `test.md` and
    reports its `Redacted:` count as today; the implementer runs it on
    `fix.md` silently (no report change; the shipper's scan still guards
    the commit). Every line is covered, code excerpts included.
- **Review diff file**: `step.sh`'s `diff_prep` also writes the diff to
  `<artifact dir>/reports/review.diff` (ignored, never committed),
  overwritten at each review boundary and not written when the diff is
  empty (no reviewer is spawned then). The reviewers' spawn block names
  it under its own `diff file:` key, and each reviewer reads it instead of
  running git to find the diff. The reviewer still reads the tree to
  verify findings.

## Out of scope
- Picking `/feat rebase` and `/fix rebase` targets (#42): preflight only
  recognises `rebase [PR]` as the argument's kind.
- The `tasks.md` reader for the implementer (#55).
- Writing the other spawn-list inputs to files (#69).
- `/tiny`'s and `/brief`'s own setup.
- A setup-calls metric in `measure.py`.
- The judgement calls in setup: refusing a refactor, a backport or several
  bugs in one report, the `/tiny` offer, and choosing a symptom's slug
  words stay with the model.
- What the assessor and implementer do between the chores (the stages,
  reproduction, classification) and the Resume flow after the argument is
  classified.

## Alternatives rejected
- Doing nothing — the prose redaction list already drifted once (#38), a
  miss surfaces only as a hard stop at ship or issue creation, and `/fix`
  setup takes a median of 8 calls.
- `review-diff.sh` as its own script, as the issue first proposed — #28
  gave `step.sh` the diff prep (`diff_prep`); a second script would
  duplicate it. `step.sh` writes the file instead.
- Preflight as `step.sh` subcommands — `step.sh` is already about 4,000
  lines and its calls start from a state file, which doesn't exist yet at
  setup. A separate script keeps both smaller.
- One preflight call for the whole of setup — `EnterWorktree` is a tool
  only the model can call, so the checks that need the worktree run in a
  second mode after it.
- Redaction as a mode of `secret-scan.sh` — `secret-scan.sh` stays a
  read-only check, which the shipper and the tracker rely on;
  `trail.sh` sources its rules instead, so there is still one list.
- Redacting only command-output sections, as today's prose says — the
  script would have to know each report's section names and could miss
  one; over-redacting a code excerpt (`token = getToken()`) costs little,
  because the code is in the repo.
- Redacting only what the scan flags (its length thresholds) — that leaves
  short real secrets such as `password=hunter2` (7 characters).
- Redacting the assessor's reports only — `fix.md` also quotes output and is
  committed with the fix.
- A setup metric in `measure.py` — the gain is a few calls per run; a
  hand check on the first runs after merge is enough.
- Splitting into two briefs (preflight; `trail.sh` plus the diff file) —
  #29 is one issue, both halves share the Harness values, docs and lint
  work, and the whole stays medium: one `/feat` run is cheaper than two.
- Checking the remote slug against fetched `origin/fix-*` refs — setup
  fetches only `<default>`, so those refs can be stale; `ls-remote` stays.
- A `Redacted:` count in the implementer's report — it would change a
  report format `step.sh` parses; the shipper's scan guards `fix.md`.

## Acceptance
- `/feat` and `/fix` setup call `preflight.sh` (both modes), and the setup
  prose it replaces is gone: argument classification, brief lookup and
  field check, installation checks, hook reading, fetch, title and
  author, slug building and dedupe, branch rename, `.logistics.yml` check.
- The assessor and the implementer call `trail.sh rotate`, `sections`,
  `slug` and `redact`, and the prose they replace is gone, the assessor's
  key and prefix list included.
- Tested: for each `secret-scan.sh` rule and for key values below its
  thresholds, a report passed through `trail.sh redact` never matches
  `secret-scan.sh` (the test runs the scan on the output), and a report
  with nothing secret comes out unchanged.
- Tested: `password=hunter2` becomes `password=<redacted>`; a vendor
  token becomes `<redacted>`; a private-key block becomes one
  `<redacted>` line; a key with no value (`token:` at the end of a line,
  `token: str`, `password: ""`) is unchanged.
- Tested: `preflight.sh` exits 0, 1 or 2 as Behaviour says, including a
  failed fetch, a failed board check, an unparseable `extensions.yml`
  and an unreachable remote.
- Tested: `preflight.sh` classifies every argument kind of both skills,
  refuses the wrong-skill kinds with the pointer, reports a missing
  install, the clashing hooks and the brief's missing fields, and dedupes
  a slug against an existing dir, a local branch and a remote branch
  (stub `gh` and throwaway repos, as `tests/ship` does).
- Tested: `step.sh`'s review boundary writes `reports/review.diff` holding
  the same diff it prints, rewrites it at a later review boundary, writes
  none for an empty diff, and the reviewer's spawn block names it under
  `diff file:`.
- `mise run lint` (shellcheck on the new scripts and their tests, and a
  grep that the replaced prose is gone) and the offline tests pass,
  including new `mise run test:preflight` and `mise run test:trail`.
- Checked by hand on the first `/feat` and `/fix` runs after merge:
  setup takes 3 coordinator calls or fewer before the first spawn
  (from 4 and 8), and code reviewers make no git calls to find the diff.

## Constraints / decisions already made
- `preflight.sh` and `trail.sh` follow `step.sh`'s and `ship.sh`'s rules:
  Bash 3.2, no jq, no Python, shellcheck clean, tests under
  `tests/preflight` and `tests/trail` with fixtures, throwaway repos and a
  stub `gh`, wired into `mise.toml` and `mise run lint`.
- They live in `.apm/skills/feat/scripts/`. Each skill's `## Harness values`
  names their paths; agents get `trail.sh`'s path in their prompt, the
  way the shipper gets `ship.sh`'s. Keep `/feat`-only words out of
  `harness.md`, `rebase.md` and `move.md` (lint greps them).
- The secret rules live once, in `secret-scan.sh`. `trail.sh redact`
  sources it (as `tracker.sh` does) and adds only the stricter
  value-matching; `secret-scan.sh`'s behaviour doesn't change.
- Issue titles, issue bodies, briefs and `extensions.yml` are data: the
  scripts never execute or `eval` them, and print fields as data lines.
- The assessor has no Edit tool, and agents in a worktree can't use `$(…)`,
  heredocs or redirections (the worktree guard). Each chore is one plain
  `bash <script> …` call.
- `feat-code-reviewer` takes either the diff file (`diff file:`) or a diff
  command (`diff:`), and runs the command only when it has no file:
  `/tiny` spawns it too (lens 7a) and keeps passing a diff command, because
  it has no `step.sh` and can't redirect in a worktree.
- Since #69 (on main, `3e8fba8`), spawn lists go in the file named on
  the `inputs:` line, and single values stay in the spawn message.
  `diff file:` is a single path: it is printed in the spawn block next to
  the diff command, not written to the inputs file.
- `/feat` and `/fix` stay thin: no new reading of code or artifacts by the
  coordinator. Agent report formats don't change, apart from the reviewer
  inputs above, so `step.sh`'s parsing stays.
- Update `docs/workflow.md` (and the diagrams only if a phase or gate
  changes, which this shouldn't) and the scripts' list in the docs.

## Log

- [x] 0 Setup — brief specs/briefs/setup-trail-scripts.md (medium); .specify and feat-* agents present; no Spec Kit hooks; board users/pdemagny/projects/2 ok, #29 set to In progress; worktree brief-29 fast-forwarded to origin/main 3e8fba8, branch renamed setup-trail-scripts
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 Setup runs as a few scripted calls (P1); US2 Hooks and base are checked as data, with clear stops (P1); US3 /fix slug is unique across dir, local and remote (P1); US4 Bug reports are redacted by the same rules as the scan (P2); US5 Report renames, headings and slugs are checked by script (P2); US6 Code reviewers read the diff from a file (P2); US7 The replaced prose is gone and the docs match (P3)
    - Requirements: 20; preflight two modes with exit 0/1/2 contract (FR-007, FR-008); extensions.yml read as data, unparseable exits 1 (FR-004); trail.sh redact sources secret-scan rules and keeps key names (FR-011, FR-012); review.diff written by step.sh under diff file: (FR-015); tests in tests/preflight and tests/trail (FR-018)
    - Spec assumptions: 1. tracker.sh check and secret-scan.sh keep their interfaces (recommended: keep as written); 2. reports/review.diff is covered by the existing reports ignore rule, else one is added (recommended: keep as written); 3. coordinator passes a symptom's slug words to worktree mode (recommended: keep as written)
    - Unchecked checklist items: none
- [x] 3 Plan — merged with 4; assumptions needing you: 1, 2; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [hard] — D7, D9, D10, D11, D15, D16, D21, D22 need you; assumption 1 needs you; assumption 2 needs you
    - D1 research.md: R3 "Would branch or commit" (and plan.md: Design, Hooks) — The "would branch or commit" rule only matches the words git, commit and branch, so an enabled hook that pushes, merges, tags, rebases, switches branch or opens a PR (`release.push`, `ext.open-pr`, `autocommit`) lands on `hooks allowed:` and agents run it with no gate. Today the model judges "would create a branch or commit"; the script turns that into a fixed list that is narrower than the clash it guards
    - D2 plan.md: Design, `preflight.sh` (steps order) and contracts/preflight.md: Steps per kind — Mode 1 reads `.specify/extensions.yml` (and checks `.specify/`) in the current checkout, but the worktree EnterWorktree creates is the just-fetched `origin/<default>`, and that tree's file is the one the run's agents see. A committing hook that exists on origin but not in a stale or dirty local checkout skips the gate (and a local-only hook gets gated for nothing). The plan already uses that tree for the slug check (`git cat-file -e` on `refs/remotes/origin/<default>`)
    - D3 contracts/trail.md: redact, rule 2 (and research.md: R5 step 2) — `trail.sh redact` stops an unquoted value at the first whitespace, so `password: correct horse battery staple` (YAML, .env-style or log lines) becomes `password: <redacted> horse battery staple` and three quarters of the secret stays in a committed report. Rule 4 doesn't catch the rest because what is left no longer matches the scan
    - D4 contracts/preflight.md: Argument kinds (issue row) and plan.md: Design, Issue (R10) — The parts of `owner/repo#N` and `https://github.com/<o>/<r>/issues/<N>` go into `gh api repos/<o>/<r>/issues/<N>` with no stated character check. An `owner` of `..` or a URL with extra segments can point that authenticated GET at another API path, and its `--jq` output then prints as `title:`/`author:`
    - D5 contracts/preflight.md: Worktree mode — Worktree mode takes `<short-name>` and `<slug>` again from the coordinator's command line but the contract never re-validates them. They become a branch name (`git branch -m`), a path (`<top>/.specify/bugs/<slug>`) and an `ls-remote` pattern, so a slip or injected value (`../x`, `*`, a leading `-`) reaches git and the filesystem unchecked
    - D6 research.md: R2 (and plan.md: Design, Hooks) — The hook reader validates the charset of `extension` and `command` only. The event key is printed too (`hook …: <key>: …`, `hooks allowed: <key>: …`) and its value is copied into the state file's `Allowed Spec Kit hooks`, so a crafted key is the one read field that isn't held to the fail-closed rule
    - D7 spec.md / plan.md: `trail.sh` redact (rules come from `secret-scan.sh`) — Redaction covers only the scan's rules, so command output that quotes an `Authorization: Bearer …` header, a JWT or a URL with credentials (`https://user:pass@host`) passes both `redact` and the shipper's scan and is committed in the bug trail. This is not a regression (today's prose list is the same), but the feature makes redaction look complete
    - D8 plan.md: Design, Slug (R1, R13) and worktree mode — Slug dedupe runs one `git ls-remote` per candidate suffix, so each clash adds a network round trip (unbounded in the number of clashes) — rec: apply
    - D9 plan.md: Summary (R1 resolution) and Design, preflight worktree mode; spec.md: US3, FR-008 — Worktree mode rebuilds the `/fix` slug checks that mode 1 just ran (bug dir, local branch, a second `ls-remote`), which adds a network call, a late-clash exit-1 path and test cases for a window of a few seconds — rec: user (FR-008 and US3 acceptance 2 say worktree mode runs the remote check and exits 2, so this changes a requirement)
    - D10 spec.md: US1 AC7, US3 AC1-2, FR-008 vs plan.md: Summary, Design (Slug) — Spec and plan disagree on where the `/fix` slug is built: spec US1 AC7, US3 AC1-2 and FR-008 say worktree mode builds and prints the unique slug, while plan R1 moves the build to mode 1 and makes worktree mode only re-check and stop on a clash (exit 1, or 2 when the remote is unreachable). The plan notes the conflict, but spec.md was not amended, so tasks and tests derived from the spec would target the wrong mode — rec: user (changes requirements and an acceptance scenario, and departs from the brief's wording)
    - D11 spec.md: SC-001, US1; plan.md: Skills, harness, agents (`/feat` SKILL) — SC-001 and US1 promise 3 coordinator calls before the first spawn, but `/feat` setup step 5 also runs the building move (`tracker.sh set-status building <ref>`, a separate coordinator call; `step.sh` has no set-status), and the plan keeps it as its own call in setup step 4. With a board and an issue, `/feat` is 4 calls: preflight, building move, EnterWorktree, worktree call. `/fix` waits for the assess gate, so it is 3 — rec: user (changes a success criterion)
    - D12 plan.md: Design (`preflight.sh`, first bullet); plan.md: Skills, harness, agents (`/feat` and `/fix` setup) — Quoting is left open. `$ARGUMENTS` goes in as one single-quoted argument and the values preflight prints (`title:`, `author:`) go into `S init … '<title>'`. A symptom with an apostrophe ("doesn't save") or an issue title with one breaks the quote, and a title is untrusted text the coordinator pastes into a Bash command — rec: apply
    - D13 contracts/preflight.md: Argument kinds — Argument kinds `resume` and `rebase` are not told apart from a symptom or idea that starts with those words ("resume button crashes", "rebase breaks on merge commits"). Today the model judges it; the contract table says only `rebase [<PR, URL or branch>]` — rec: apply
    - D14 plan.md: Design (`preflight.sh`); contracts/preflight.md: exit 2 "no default branch found" — The default branch is used by every mode-1 step (`git fetch origin <default>`, `origin/<default>` tree check) but the plan never says how preflight finds it. `step.sh` `default_branch` (step.sh:1382) already does it: `refs/remotes/origin/HEAD`, else `ls-remote --symref origin HEAD`, then `check-ref-format --branch` and a leading `-` refused (a remote-supplied name reaches git); `ship.sh` lines 117-124 validate the same way. `step.sh` is not sourceable, so preflight needs its own copy — rec: apply
    - D15 spec.md: FR-004, US2 AC1; research.md: R3 — "Would branch or commit" is defined only in research R3, as a name test (extension `git`, or `git`, `commit` or `branch` as a word of the extension or command). Today's model reads the whole entry, so a committing hook with another name (a `sync` extension with a `push-all` command) passes the gate unflagged. Spec FR-004 and US2 name the category without defining it, so the acceptance cannot be checked, and the control is weaker than today's — rec: user (weakens a control the gate has today)
    - D16 spec.md: Edge Cases; contracts/trail.md: redact rule 1 — `redact` with a private-key block that has no end line redacts to the end of the file (plan, contract trail.md, R5). A report that merely mentions the begin marker in prose (a bug about key handling, or about this scan) loses everything after it: the Slug bullet, Proposed Remediation, the sections `sections` then reports missing. The spec's edge case lists "a block with no end line" but gives no result — rec: user (relaxes what a redact run removes; whether a blank line may end a block is the user's call)
    - D17 plan.md: Skills, harness, agents (`feat-bug-assessor`); contracts/trail.md: Exit codes — `trail.sh sections`, `slug` and `redact` exit 2 on a missing file, but the assessor's "unintelligible report" path writes no assessment.md (`Assessment: none (...)`, and the section check is `ok`). The plan's assessor bullet says only that the rules "become calls", so the agent would call them on a file that is not there. The same bullet should say what to do when the stage printed no `Slug:` line (the optional fourth argument) — rec: apply
    - D18 spec.md: Edge Cases; research.md: R8 — Spec edge case "rotate when assessment-1.md and assessment-3.md exist (next free n)" reads as `-2`, while R8 and the contract choose highest plus one (`-4`). The brief also says "next free n" — rec: apply
    - D19 plan.md: Design (install check); contracts/preflight.md: output keys — The `bug extension:` version line is under-specified. In `.specify/extensions/bug/extension.yml` the version is `  version: "1.0.2"` nested under `extension:`, and the file also holds `requires: speckit_version:`, so a grep for `version:` can match the wrong line — rec: apply
    - D20 contracts/preflight.md: Slug (`/fix`) — Slug edge cases: an issue title with no `[a-z0-9]` word gives `29` (after trimming `29-`), and `slug=` words that normalise to nothing give an empty slug. The contract's `bug` fallback covers only a non-GitHub URL — rec: apply
    - D21 spec.md: FR-002, US1 AC1; contracts/preflight.md: output keys `behaviour:`, `acceptance:`; research.md: R11 — Spec FR-002 and the contract print every Behaviour and Acceptance line of the brief to the coordinator, but the coordinator uses none of them: the state file copies the brief from its path, and preflight already checks both sections are non-empty. Each printed line stays in the coordinator's context for every later call of the run — rec: user (FR-002 and an acceptance scenario name these fields)
    - D22 plan.md: Every added line passes the secret scan — Ship will stop at the secret scan: `secret-scan.sh worktree specs/016-setup-trail-scripts` fails today on spec.md line 80 and feat-state.md line 122, both quoting the private-key begin marker (confirmed by running it). The plan names the problem but leaves who rewords them open, and the state file's Brief section has no script writer — rec: user (the Brief section is the user's text)
    - answer: approved (user: "ok")
    - answer: fix D9 (user: "ok")
    - answer: fix D10 (user: "ok")
    - answer: fix D11 (user: "ok")
    - answer: fix D15 (user: "ok")
    - answer: fix D16 (user: "ok")
    - answer: leave D7 (user: "ok")
    - answer: fix D21 (user: "ok")
    - answer: fix D22 (user: "ok")
    - outcome: picked D1, D2, D3, D4, D5, D6, D8, D9, D10, D11, D12, D13, D14, D15, D16, D17, D18, D19, D20, D21, D22; rejected D7 (user: "ok")
- [x] 3 Plan — amended (D1, D2, D3, D4, D5, D6, D8, D9, D10, D11, D12, D13, D14, D15, D16, D17, D18, D19, D20, D21, D22); assumptions needing you: 7; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [soft] — 48 tasks; story.sh: match; analyze ran
- [x] move — 3e8fba8 → a9496ae (before 6 Implement): checks pass; not verified: none
    - resolved: specs/016-setup-trail-scripts/ — no WIP commit (auto mode refused it); the run's work is untracked only and main does not touch it, the branch sat at the merge base, so the rebase was a fast-forward with the files left in place, unstaged as before
- [x] 6 US1 — not verified: none
    - wrote: .apm/skills/feat/scripts/preflight.sh
    - wrote: .apm/skills/feat/scripts/trail.sh
    - wrote: tests/preflight/run.sh
    - wrote: tests/preflight/bin/gh
    - wrote: tests/preflight/expected
    - wrote: tests/trail/run.sh
    - wrote: tests/trail/fixtures/.gitkeep
    - wrote: tests/trail/expected/.gitkeep
    - wrote: specs/016-setup-trail-scripts/tasks.md
- [x] 6 US2 — not verified: none
    - wrote: tests/preflight/expected/board-fail.out
    - wrote: tests/preflight/expected/hooks-feat.out
    - wrote: tests/preflight/expected/hooks-fix.out
    - wrote: tests/preflight/expected/hooks-hostile.out
    - wrote: tests/preflight/expected/hooks-rebase.out
    - wrote: tests/preflight/expected/hooks-resume.out
    - wrote: specs/016-setup-trail-scripts/tasks.md
- [x] 6 US3 — not verified: none
    - wrote: specs/016-setup-trail-scripts/tasks.md
- [x] 6 US4 — not verified: none
    - wrote: specs/016-setup-trail-scripts/tasks.md
    - wrote: tests/trail/fixtures/keys.md
    - wrote: tests/trail/fixtures/blocks.md
    - wrote: tests/trail/fixtures/prose.md
    - wrote: tests/trail/fixtures/code.md
    - wrote: tests/trail/fixtures/clean.md
    - wrote: tests/trail/expected/redact-rules.md
    - wrote: tests/trail/expected/redact-keys.md
    - wrote: tests/trail/expected/redact-blocks.md
    - wrote: tests/trail/expected/redact-prose.md
    - wrote: tests/trail/expected/redact-code.md
- [x] 6 Implement [hard] — US4: design problem
    - answer: changed (user: "ok — add the backtick to the value-end characters, in trail.sh and contract rule 2, with a code-span test")
- [x] 6 US4 — not verified: none
    - wrote: tests/trail/fixtures/span.md
    - wrote: tests/trail/expected/redact-span.md
    - wrote: specs/016-setup-trail-scripts/contracts/trail.md
    - wrote: specs/016-setup-trail-scripts/tasks.md
- [x] 6 US5 — not verified: none
    - wrote: specs/016-setup-trail-scripts/tasks.md
- [x] 6 US6 — not verified: none
    - wrote: specs/016-setup-trail-scripts/tasks.md
    - wrote: tests/step/expected/diff-file.out
    - wrote: tests/step/expected/diff-file.log
- [x] 6 US7 — not verified: none
    - wrote: specs/016-setup-trail-scripts/tasks.md
- [x] 6 Implement [soft] — tasks done: 48 (0 not verified); checks pass
- [x] move — a9496ae → 314e49c (before 7 Code review): checks pass; not verified: none
    - resolved: (whole tree) — the WIP commit was refused by the permission classifier, so the move ran as `git checkout -m -B setup-trail-scripts origin/main` (a 3-way merge of the uncommitted work onto main, no commit, no pre-move ref); a backup of the staged work before the move is tree object 0b5af84; the branch now tracks origin/main
    - resolved: .apm/agents/feat-bug-assessor.agent.md, feat-code-reviewer.agent.md, feat-implementer.agent.md, .apm/skills/feat/scripts/step.sh, docs/workflow.md, tests/step/run.sh — main (#74 reformat reasons, #76 state file out of the snapshot) and the run changed separate hunks; merged with no conflict, all checks green
- [!] 7 Code review — report missing: 7-7d.md
- [x] 7 Code review [hard] — report missing: 7-7d.md; unparsable: 7-7c.md: line 2 (Performance (7c)) — not a "- " item at column 0
    - answer: back to 7 (user: "back to 7, and file the issue")
- [!] 7 Code review — unparsable: 7-7d.md: line 1 (Cuts (7d)) — an empty field (write none); reformat 1 of 1
- [x] 7 Code review [hard] — B1, B3, S2, S3, S4 need you; S1 security; S2 security; S3 security; S4 security
    - B1 .apm/skills/feat/scripts/trail.sh:265-278 — redact's private-key block runs until an END line, a blank line or a fence, so a report that names the begin marker in a paragraph or list with no blank line after it loses every following line up to the next blank line, required headings and `**Verdict**`/`**Severity**` bullets included; the assessor runs `redact` before `sections`, which then reports them missing (the `prose.md` fixture only passes because a blank line follows the mention) — rec: user (the spec's edge case fixes the end rule as written; changing it is a spec change)
    - B2 .apm/skills/feat/scripts/preflight.sh:2-3 — the header comments name `specs/016-setup-trail-scripts/contracts/preflight.md` and `.../trail.md`, but phase 8 renames the spec dir to `specs/NNN-setup-trail-scripts/` and ship.sh's number_dir calls rewrite_dir, which rewrites only files inside the artifact dir and `.specify/feature.json` (ship.sh:719-723, 740-751), so both references go stale at ship; no other shipped script names a spec path — rec: apply
    - B3 .apm/skills/feat/scripts/preflight.sh:869-873 — the /fix coordinator must guess the kind before the call (it adds `slug=` only for what it judges a symptom), while preflight classifies on its own and refuses `slug=` for any other kind and requires it for a symptom (exit 2); where the two disagree, e.g. `/fix rebase fails` (preflight: kind rebase, target `fails`) or `/fix ../x#1` (preflight: symptom), the run stops on a usage line instead of going on — rec: user (the contract makes `slug=` required for a symptom and refused otherwise)
    - S1 .apm/skills/feat/scripts/preflight.sh — A hook named `gitflow` lands on `hooks allowed:` even though FR-004 says it matches ("so `autocommit` and `gitflow` match"). `git` is checked only as a whole `.`/`-`/`_`-separated word and is not in the substring list, so an extension or command `gitflow` (no separator) passes would_commit and agents run it without the gate
    - S2 .apm/skills/feat/scripts/preflight.sh — would_commit's name list still misses common hook names that commit or open a PR: `create-pull-request` and `pull_request` (their words are `pull` and `request`, never `pr`), `amend`, `squash`, `cherry-pick`. Such an enabled hook is allowed with no gate (D1's concern, beyond FR-004's fixed list)
    - S3 .apm/skills/feat/scripts/trail.sh — `redact` leaves a multi-line value in place. When a first-token key's value is a YAML block scalar (`password: |` or `>`) or an unclosed quote (a `.env` `KEY="…` spanning lines), only the first line is replaced. The following lines hold the secret with no key, rule 4 does not match them, and they stay in a committed report
    - S4 .apm/skills/feat/scripts/trail.sh — `redact` keeps all but the first word of a multi-word unquoted value after a key in the middle of a line: a log line such as `INFO login password=correct horse battery` becomes `password=<redacted> horse battery`. D3 named log lines, but the built rule covers only a key that is the line's first token
    - R1 .apm/skills/feat/scripts/preflight.sh:681-682 — `cut40` hands its result back in the global `N`, and `slug_base` then copies it with `B="$N"` right after the call; nothing says the call set `N` — rec: skip (the helpers already document `N = ...` in their headers, and the pattern is used the same way elsewhere in the file)
    - R2 .apm/skills/feat/scripts/trail.sh:173,215 — `lead` means two things in neighbouring functions: a flag (0 or 1) in `redact_keys`, a character in `redact_vendors` — rec: skip (both are function-local and short; no confusion in practice)
    - answer: approved (user: "ok")
    - answer: fix B1 (user: "ok")
    - answer: fix B3 (user: "ok")
    - answer: fix S2 (user: "ok")
    - answer: fix S3 (user: "ok")
    - answer: leave S4 (user: "ok")
    - outcome: picked B1, B2, B3, S1, S2, S3; rejected S4 (user: "ok"), R1 (as recommended), R2 (as recommended); untested: US6-4 /tiny's reviewer with only a diff command uses it
- [x] 7 review fixes — B1 → applied; B2 → applied; B3 → applied; S1 → applied; S2 → applied; S3 → applied; S4, R1, R2 → left (user); performance: none; checks: rtk mise run lint → pass, rtk mise run test:apm → pass, rtk mise run test:preflight ::: test:trail ::: test:secret-scan ::: test:step ::: test:ship ::: test:state ::: test:story ::: test:sizes ::: test:tracker ::: test:spec-number ::: test:measure → pass, bash .apm/skills/feat/scripts/secret-scan.sh worktree on the new fixtures, goldens and both test scripts → pass; not verified: none
    - wrote: tests/trail/fixtures/adjacent.md
    - wrote: tests/trail/fixtures/multiline.md
    - wrote: tests/trail/expected/redact-adjacent.md
    - wrote: tests/trail/expected/redact-multiline.md
    - wrote: specs/016-setup-trail-scripts/contracts/trail.md
    - wrote: specs/016-setup-trail-scripts/contracts/preflight.md
    - wrote: specs/016-setup-trail-scripts/spec.md
    - wrote: specs/016-setup-trail-scripts/research.md
- [x] 8 Ship
