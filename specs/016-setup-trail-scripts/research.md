# Research: setup-trail-scripts

No `NEEDS CLARIFICATION` was left in the Technical Context. The decisions
below are the ones the spec did not take.

## R1 Where the `/fix` slug is built

- **Decision** (now spec US3, FR-008): mode 1 builds and dedupes the slug
  (it takes the symptom's words as `slug=<words>`), with one `git ls-remote`
  and exit 2 when the remote is unreachable. Worktree mode makes no network
  call: `git branch -m fix-<slug>` fails (exit 1) when the local branch
  appeared since, and the bug dir in the worktree is checked (exit 1). A
  remote branch created in the seconds between the two calls is caught at
  push.
- **Rationale**: the chain runs worktree mode and `S init fix '<state
  file>' …` in one Bash call, and the `/fix` state file is
  `.specify/bugs/<slug>/feat-state.md`: the slug must be known when the call
  is written, and the worktree guard forbids `$(…)` to carry it across. Mode
  1 can see every clash: the new worktree's tree is `origin/<default>` just
  fetched (checked with `git cat-file -e`, `HEAD` too), branches are shared
  between worktrees, and `ls-remote` is the same call. A second
  `ls-remote` in worktree mode would cost a network call, an exit path and
  tests for a window of seconds.
- **Alternatives considered**: worktree mode builds the slug, then a fourth
  call for `S init` (misses SC-001's 3 calls for `/fix`); re-running the
  remote check in worktree mode (cost above);
  worktree mode running `state.sh init`, `log` and `step.sh setup` itself
  (couples preflight to both scripts' argument forms); a placeholder in the
  state file path that `state.sh` resolves (a new rule in `state.sh` for one
  caller).

## R2 Reading `extensions.yml` without a YAML library

- **Decision**: a line reader for the subset Spec Kit's PyYAML dump writes:
  top-level keys at column 0 (only `hooks:` is read; other sections are
  skipped whole); under `hooks:`, event keys at one indent, each with `{}`,
  `[]`, `null`, `~`, nothing, or a block sequence (indented or at the key's
  own indent, PyYAML's default); items `- key: value` and their keys at the
  item indent; lines deeper than a key are its continuation (folded long
  strings, `|`/`>` blocks) and are skipped, except under `extension`,
  `command` or `enabled`, where they are unparseable. Plain, `'…'` and `"…"`
  scalars; comments and blank lines skipped. `enabled` takes
  `true|false|yes|no|on|off` (any case) or is absent (enabled). Anything else
  (a tab in the indent, a flow mapping or list with content, an anchor,
  alias or tag on a read key, a stray line) exits 1, as does an event key
  outside `[a-z][a-z0-9_]*` or an `extension`/`command` outside
  `[A-Za-z0-9][A-Za-z0-9._-]*` (each is printed, and the allowed keys go into
  the state file). A missing or empty file, or `hooks: {}`, has no hooks.
- **Source**: for a brief, an issue or a symptom, the file in
  `refs/remotes/origin/<default>` after the fetch (`git cat-file -e`, then
  `git show <ref>:.specify/extensions.yml` into a variable read line by
  line), since that tree is the one the run's worktree and agents get; a
  stale or dirty checkout would hide a committing hook added on origin. For
  `resume` and `rebase` (no fetch) the checkout's file.
- **Rationale**: the brief forbids Python and jq; the file is untrusted
  data, so the reader must fail closed: a file it can't read may hide a hook
  that commits (FR-004).
- **Alternatives considered**: grepping for `extension:`/`command:` lines
  (can't tell event keys or `enabled: false` apart reliably); `yq` (a new
  dependency).

## R3 "Would branch or commit"

- **Decision** (spec FR-004): an enabled hook whose extension is `git`;
  whose extension or command has a word starting with `git`, or `pr`,
  `pull`, `tag` or `worktree`, as one of its `.`, `-` or `_`-separated
  words; or whose extension or command contains `commit`, `branch`, `push`,
  `merge`, `rebase`, `checkout`, `switch`, `release`, `publish`,
  `pullrequest`, `amend`, `squash` or `cherry` anywhere (so `autocommit`,
  `gitflow`, `release.push`, `ext.open-pr`, `create-pull-request` and
  `cherry-pick` match). Matched in lowercase. Short words
  (`pr`, `tag`) count only as whole words, so `prompt` or `stage` don't
  match. `/feat`: such hooks under `before_implement`
  or `after_implement`; every hook under `before_`/`after_` `specify`,
  `plan`, `tasks`, `analyze` is "won't run" (the git ones included); on
  `rebase` only the implement part. `/fix`: such hooks under any key. The
  enabled hooks in neither list are `hooks allowed:` (for `/feat`, those
  under the implement keys).
- **Rationale**: today's prose names "the git extension's" hooks; the brief
  limits the script to the event key, `enabled`, `extension` and `command`,
  so the rule can only use names (a spec Assumption: a committing hook with
  none of these words in its names passes unflagged). The word list covers
  every git write a hook could make (push, merge, tag, rebase, switch, open a
  PR, release); a false positive only adds a line to the gate.
- **Alternatives considered**: `git`, `commit`, `branch` only (narrower
  than the clash it guards); listing every implement hook (noisy gate);
  reading `description` (free text, larger attack surface); an allow-list
  of names (every new extension would hit the gate).

## R4 Checking that the agents are installed

- **Decision**: look for `feat-<x>.md` or `feat-<x>.agent.md` in
  `<script dir>/../../../agents` (logical and resolved paths), then
  `<top>/.claude/agents`, then `$HOME/.claude/agents`. `/feat` needs
  specifier, planner, design-reviewer, tasker, implementer, code-reviewer,
  shipper; `/fix` needs bug-assessor, implementer, code-reviewer, shipper.
- **Rationale**: the coordinator checked its agent list, which a script
  can't see. The three install layouts put the agents beside the skills: APM
  and `install.sh` in `<base>/.claude/{skills,agents}`, the plugin in
  `<plugin>/.apm/{skills,agents}` (`.agent.md` names), which is what
  "plain or `logistics:`-prefixed" stood for.
- **Alternatives considered**: keep the check with the model (a call kept
  and the brief puts it in preflight); `claude plugin list` (slow, and not
  for APM installs).

## R5 Redaction

- **Decision**, per file, in this order:
  1. a line matching the `private-key` rule starts a block that ends at the
     first line holding `-----END` (included), or just before the first
     line that is neither key body nor a `Proc-Type:`/`DEK-Info:` header (a
     blank line, a code fence, a heading, a bullet, prose; kept), whichever
     comes first, else at end of file; the block becomes one `<redacted>`
     line. A prose mention of the begin marker thus costs that one line,
     not the rest of the report;
  2. each `SECRET_KEY` match (case-insensitive, leftmost first, scanning on
     after each replacement): the value after it becomes `<redacted>`. A
     quoted value is replaced with its quotes (`"<redacted>"` would match the
     quoted rule again). An unquoted value after a key that is the line's
     first token (after the indent, an optional `- `, `export ` or an
     opening quote) runs to the end of the line, minus a trailing ` #`
     comment, so `password: correct horse battery staple` loses all four
     words (YAML, `.env` and log lines); an unquoted value after a key inside
     a line runs to whitespace or one of ``,;&)}]"'<>`` (`url?token=abc&x=1`).
     No value is left as is: end of line, `""`, `''`, and
     after a `:` separator a bare type or null word (`str`, `string`, `int`,
     `integer`, `bool`, `boolean`, `bytes`, `number`, `any`, `object`,
     `none`, `null`, `nil`, `undefined`, `true`, `false`, any case);
  3. each other `SECRET_VENDOR` rule, case-sensitive: the prefix and its
     following token characters (`[A-Za-z0-9_/+=.-]*`) become `<redacted>`;
     a match that starts with a non-word character (the openai-key rule's lead)
     keeps it;
  4. a line `secret_line_rule` still matches becomes `<redacted>`.
  The count is the number of replacements. `<redacted>` contains no prefix
  and starts with `<`, so a second run finds nothing (count 0).
- **Rationale**: one list (FR-011), the key name kept, any value length
  (`password=hunter2`), the US4 cases, and step 4 makes FR-012 hold by
  construction whatever a rule adds later.
- **Alternatives considered**: only what the scan flags (rejected in the
  brief); replacing whole lines on every match (loses the key name and the
  context the gate quotes); no type-word exception (`token: str` must stay,
  US4.4); a block without an end line running to end of file (a prose
  mention would erase the rest of the report); unquoted values always
  stopping at whitespace (leaves most of a passphrase).

## R6 The review diff file

- **Decision**: written after the batch's first `spawn_group` (its report
  path proves `reports/` exists, is a real dir and holds the `*`
  `.gitignore`), to `reports/review.diff` beside it, by `git -C <top> diff
  --no-color --no-ext-diff <base> --` into a temp file, then `mv -f`; a
  symlink is refused. `spawn_7e` writes it the same way (a resumed 7e may
  have no earlier file). An empty diff writes nothing; a stale file from an
  earlier boundary is left (no reviewer is spawned to read it).
- **Rationale**: `state.sh snapshot` already leaves `reports/` out, so the
  file doesn't trip the reviewers' read-only check; `--no-color
  --no-ext-diff` keep a user's git config from changing the bytes.
- **Alternatives considered**: a `state.sh` subcommand (git diff in the
  state writer); deleting a stale file (code for a file no one reads).

## R7 How agents get `trail.sh`'s path

- **Decision**: `step.sh` prints `trail script: <SDIR>/trail.sh` on the
  `/fix` assess, test and bug-mode fix spawns, as it prints `ship script:`.
- **Rationale**: the brief says "the way the shipper gets ship.sh's"; the
  coordinator passes every key of a spawn block, so no skill prose is needed.

## R8 `rotate` numbering

- **Decision**: `n` = the highest existing `<report>-<n>.md` + 1 (with -1 and
  -3 present, -4).
- **Rationale**: the trail stays in order; reusing a gap would file a later
  attempt under an earlier number.

## R9 Several briefs match

- **Decision**: `brief: several`, one `candidate:` line each, exit 0, no
  other check; the coordinator asks and runs mode 1 again with the chosen
  path (rare, so the extra call doesn't count against SC-001).

## R10 Issue title and author

- **Decision**: `gh repo view --json nameWithOwner --jq .nameWithOwner`,
  then `gh api repos/<o>/<r>/issues/<N> --jq '[.author_association, .title]
  | @tsv'` with the parts checked per R17; a non-zero gh exit stops (exit 1)
  with gh's first line.
- **Rationale**: one gh call gives both values; `tracker.sh read-issue`
  was only another way to the title. `@tsv` escapes tabs and newlines.

## R11 The brief's fields

- **Decision** (spec FR-002): mode 1 prints the title, size, size note,
  short name, map, issue, and `behaviour: <n> lines` / `acceptance: <n>
  lines` (non-blank lines; 0 stops), so the coordinator no longer reads the
  brief file at setup.
- **Rationale**: the coordinator uses none of the section lines (the state
  file copies the brief from its path); each printed line would stay in its
  context for the rest of the run. The count keeps the validation visible.

## R12 The `.logistics.yml` warning

- **Decision**: worktree mode prints `flag: - [!] tracker: .logistics.yml is
  not in the worktree; commit and push it (board moves skipped)` and the
  chain goes on; the coordinator logs that line on the next boundary call
  (`S log … && T …`) and flags it at the first gate.
- **Rationale**: the line appears in the same call that creates the state
  file, so it can't be in that call's `S log`.

## R13 Slug words from an issue title

- **Decision**: the normalised title's first three words, two when
  `<N>-w1-w2-w3` is over 40 characters, then cut to 40 at a `-`. A title
  with no `[a-z0-9]` word gives `<N>` alone (a valid slug); symptom words or
  a URL segment that normalise to nothing give `bug`.
- **Remote check**: one `git ls-remote --heads origin 'fix-*'`, its names
  kept in a list, every candidate checked against it locally, so a run of
  clashes costs no extra round trip. The pattern is `fix-*` rather than
  `fix-<base>*`: a suffixed candidate trims the base to stay within 40
  characters, so it need not start with the whole base.

## R14 Test layout and secret samples

- **Decision**: as `tests/ship`: a template repo and bare origin copied per
  case, `bin/gh` first on PATH answering from the case's dir, golden outputs
  with `UPDATE=1`. `tests/preflight` runs the script from a scratch
  `.claude/skills/feat/scripts/` beside a stub `tracker.sh` and a scratch
  `.claude/agents/`, with `HOME` pointing at a scratch dir. Secret samples are
  built by concatenation at run time, so no tracked file matches the scan the
  shipper runs.

## R15 Finding the default branch

- **Decision**: preflight carries a copy of `step.sh`'s `default_branch`
  (`.apm/skills/feat/scripts/step.sh`, named in a comment above the copy):
  `git symbolic-ref -q --short refs/remotes/origin/HEAD` stripped of
  `origin/`, else the `ref: refs/heads/<x>` line of
  `GIT_TERMINAL_PROMPT=0 git ls-remote --symref origin HEAD`; an empty name,
  a leading `-`, or a name `git check-ref-format --branch` doesn't return
  unchanged is refused (exit 2, `no default branch found`).
- **Rationale**: the name comes from the remote and reaches `git fetch` and
  `git show`; `step.sh` and `ship.sh` already validate it this way.
  `step.sh` can't be sourced (it runs on load), so the copy is the one
  place the rule repeats.
- **Alternatives considered**: a shared sourced helper (a third file and a
  `step.sh` refactor for ten lines).

## R16 Quoting values into Bash commands

- **Decision**: both skills and the preflight contract carry one rule: every
  value from `$ARGUMENTS` or a preflight line goes into a Bash command inside
  single quotes, each `'` written `'\''`. Tested with an argument holding an
  apostrophe and `$(touch pwned)`.
- **Rationale**: a symptom (`doesn't save`) or an issue title holds
  apostrophes, and a title is untrusted text the coordinator pastes into `S
  init … '<title>'`.

## R17 Telling argument kinds apart

- **Decision**: `resume` is the exact word; `rebase` the word alone or
  followed by one whitespace-free word; anything longer is a symptom or an
  idea. An issue is `#N`, `owner/repo#N` or
  `https://github.com/<o>/<r>/issues/<N>` with `<o>` matching
  `[A-Za-z0-9][A-Za-z0-9-]*`, `<r>` `[A-Za-z0-9._-]+` and not `.` or `..`,
  `<N>` `[1-9][0-9]*`, the host exactly `github.com` and nothing after `<N>`
  but an optional `/`, `#…` or `?…`. Anything else is the other-URL kind
  (author `unknown`) or a symptom (author `user`).
- **Rationale**: "resume button crashes" is a bug report, not a resume; and
  the parts go into the authenticated `gh api repos/<o>/<r>/issues/<N>`, so
  `..` or extra segments could point that GET at another API path.
