# Quickstart: validate the change

Run from the worktree root.

## Offline (SC-004)

```sh
mise run lint
mise run test:apm
mise run test:preflight
mise run test:step
mise run test:trail
mise run test:state
mise run test:ship
```

Expected: all pass. `tests/preflight` covers the cases of FR-012 (see
`contracts/preflight-skills.md`): project path, home path, project first
when both, each lens skill missing, an allowed hook resolved, an allowed
hook's skill missing, a hook mapping to no skill, a flagged hook's skill
found and missing, the three bug skills and one missing, `rebase` with no
lens skill installed, and resume.

## Lint guards the denial (US1 scenario 2)

Remove `Skill` from one agent's `disallowedTools` in a scratch copy of the
line (don't commit), run `mise run lint`: it fails naming that file and
`Skill`. Put it back: it passes.

## Measured spawns (SC-001, SC-002, SC-003; manual, before the PR)

1. In a throwaway project with Spec Kit, the bug extension and an allowed
   `after_implement` hook whose skill writes a marker file, run `/feat` on
   a small brief and `/fix` on a small bug through to a PR (lenses 4a,
   7b, 7c run; both assessor modes run).
2. `mise run measure -- --since <today>`: in "First request" of the
   implementer (story and bug mode), code reviewer, design reviewer and
   assessor spawns, no `skills listing` part. Note each agent's starting
   context before (a run from before the change) and after, for the PR
   body.
3. The marker file exists; the implementer's report doesn't list the hook
   on `Skipped hooks`.
4. Each lens and assessor report shows the skill's own steps ran (7c:
   measure then identify).
5. Note, for each location separately, whether a worktree spawn's read of
   a `SKILL.md` prompted for permission: one under `~/.claude/skills`, and
   one project skill under the main checkout's `.claude/skills` (a new
   run's paths point there, not into the worktree: setup runs before
   `EnterWorktree`). Only for a location that prompted, `docs/install.md`
   documents its allow rule (`Read(~/.claude/skills/**)`; the main
   checkout's skills dir).

## Setup stops (US3)

In a project without `performance-optimization` installed: `/feat <brief>`
stops at setup with `stop: skills not installed: performance-optimization
…` and the install line. With an allowed hook whose skill is missing: the
stop names the hook and `enabled: false`.

## PR body (US4 scenario 4)

`Closes #101`, the before/after starting context per changed agent, and
the post-merge check: implementer starting context ≤ 27k tokens on at
least five runs, `Not verified:` lists and code-review finding counts no
worse than before; and the two deliberate stricter setup stops (an
allowed hook whose skill can't be resolved; `/fix` needing all three bug
skills, where the extension dir alone or one skill used to pass).
