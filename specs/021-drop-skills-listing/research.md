# Research: drop the skills listing (read skills by path)

Each entry: Decision, Rationale, Alternatives considered.

## R1. Hook command to skill directory (FR-006)

- **Decision**: a hook's `command` maps to a skill directory only when it
  starts with `speckit.`: the directory is the command with every `.`
  written `-` (`speckit.git.commit` → `speckit-git-commit`,
  `speckit.docs.update` → `speckit-docs-update`). A command that doesn't
  start with `speckit.`, or a hook with no `command`, maps to no
  directory.
- **Rationale**: checked against Spec Kit's own code, not guessed
  (specify-cli 1.2.1, the version `mise.toml` pins):
  `specify_cli/extensions/__init__.py`, `HookExecutor._skill_name_from_command`
  returns `speckit-` + the part after `speckit.` with dots as hyphens, and
  `""` for any other command; `_render_hook_invocation` builds the
  `/speckit-…` invocation from it. Extension install
  (`_skill_name_for_command`) writes the skill to the same directory
  name, and manifest validation (`EXTENSION_COMMAND_NAME_PATTERN`,
  `^speckit\.([a-z0-9-]+)\.([a-z0-9-]+)$`) rewrites hook references to
  that form at install. `preflight.sh`'s `RE_HOOK` already limits a command
  to `[A-Za-z0-9._-]`, so the mapped name has no `/` and no `.`: it can't
  leave the skills dir.
- **Alternatives considered**: prefixing `speckit-` to a bare command
  (what `_skill_name_for_command` does for a command name at install):
  hook rendering doesn't do it, so such a hook has no invocation today
  either; stopping on it is FR-006's "maps to no skill directory".

## R2. Where the resolver lives and what it searches (FR-003)

- **Decision**: one function in `preflight.sh`, `skill_path <name>`,
  searching `<top>/.claude/skills/<name>/SKILL.md` then
  `$HOME/.claude/skills/<name>/SKILL.md` (no `$HOME`: the project only).
  The bug-extension check's search (`dirs=…` in `step_install`) is
  replaced by calls to it, so there is one search. The printed path is the
  absolute path where the file was found, not resolved through symlinks
  (`install.sh` links skills; the link is what Claude Code reads too).
  For a new run `$top` is the main checkout, so a project skill's path is
  outside the spawn's worktree cwd; it is not rewritten for the worktree,
  and the measured spawns check it for a permission prompt as they check
  `~/.claude/skills`.
- **Rationale**: the brief's constraint; `$top` is `git rev-parse
  --show-toplevel`, absolute. A test with `-f` follows symlinks.
- **Alternatives considered**: searching plugin caches (rejected in the
  brief); resolving again in `preflight.sh … worktree` so paths point into
  the worktree (a second call needs the hook list again, and a project
  skill that isn't committed is not in the worktree).

## R3. Which skills, when (FR-004, FR-005, FR-007)

- **Decision**:
  - lens skills `security-and-hardening` and `performance-optimization`:
    both, every kind that runs the install check except `rebase` (its
    spawns, the implementer and the shipper in rebase mode, read no
    skill);
  - `/fix`: `speckit-bug-assess`, `speckit-bug-fix`, `speckit-bug-test`,
    every kind that runs the install check (rebase included: today's
    bug-extension check runs there too); each must resolve. This is
    deliberately stricter than today (the `.specify/extensions/bug` dir
    alone, or any one bug skill dir, passes), stated in docs/install.md
    and the PR body (FR-007);
  - hooks (not on `rebase`): every hook that lands in `hooks allowed:`
    must resolve; a `hook would branch or commit:` hook (`/feat`:
    `implement` ones; `/fix`: any) is resolved when its skill is found
    and never stops the run, since it is skipped unless the user allows it
    at the hook gate; `hook won't run:` hooks are not resolved.
- **Rationale**: FR-004's lists; an allowed flagged hook must still be
  runnable when the user allows it (FR-009), without a setup stop for a
  hook skipped by default.
- **Alternatives considered**: stopping on a flagged hook's missing skill
  (stops runs for hooks that won't run by default); not resolving flagged
  hooks (allowing one at the gate would then never run it).

## R4. How spawns get the paths (FR-008)

- **Decision**: the coordinator keeps setup's `skill <name>: <path>` lines
  (on resume, those its resume call printed) and adds them, as printed,
  to every spawn's prompt after its spawn block's keys. The rule is one
  bullet in `harness.md`'s "Give each one, in its prompt" list; `/feat`'s
  and `/fix`'s setup steps add `skill` lines to what they keep.
- **Rationale**: `preflight.sh` is the coordinator's call; the lines are
  short (about 7 for `/fix`); no change to `state.sh`, `step.sh`, the state
  file or `tests/step` (FR-013 keeps formats unchanged).
- **Alternatives considered**: storing the paths in the state file and
  having `step.sh` print them as spawn keys like `trail script:` (more
  files and tests change for the same lines; resume re-runs preflight
  anyway).

## R5. Stops and their text (FR-005, FR-006, FR-007)

- **Decision**: one stop per kind of miss, naming every missing item of
  that kind (texts in `contracts/preflight-skills.md`). The lens stop
  quotes `docs/install.md`'s skills CLI line as it is. The bug stop keeps
  today's "run specify extension add bug in this project" and names the
  missing skills. The hook stop names each hook (its gate label) and its
  skill, or "maps to no skill", and says to disable it in
  `.specify/extensions.yml` (`enabled: false` on its entry).
- **Rationale**: the user fixes everything in one go; the install line is
  the one users already find in the docs.
- **Alternatives considered**: one line per skill (a narrower install
  command): it would be a second pinned command to keep in step with
  `docs/install.md`.

## R6. A spawn without the line it needs

- **Decision**: setup guarantees the lines, so a missing one is a
  coordinator slip. The agent does no other work for it and never
  improvises: a reviewer or the assessor hands back `Report not written:
  no skill path for <name>` (the existing missing-report path: one fresh
  re-spawn, then the error gate); the implementer in bug mode reports
  `Status (bug mode): not-applied` with `Design problems: no skill path
  for speckit-bug-fix`; an allowed hook with no line goes on `Skipped
  hooks` as `<hook> → no skill path`.
- **Rationale**: no report format changes (FR-013); the lens never runs
  without its skill (brief).
- **Alternatives considered**: the agent searching the two dirs itself (a
  second resolver, in prose).

## R7. Output order in `preflight.sh`

- **Decision**: a new output slot for keys `skill <name>`, right after
  `hooks allowed` and before `slug`; later slots shift by one. Within it,
  lines come in emit order: lens, bug, then hooks in file order, each
  skill once.
- **Rationale**: the contract's fixed key order; `slot()` maps a key to
  its place.
