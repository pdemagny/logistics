# Quickstart: validating foreground spawns

From the worktree root.

## Offline checks (all must pass)

```sh
mise run lint            # shellcheck, the harness.md word grep, measure.py on 3.11
mise run test:preflight  # spawn note: unset, empty, 0, 1, other, refused kind, worktree mode
mise run test:measure    # every golden with the new row; sess-async-1 > 0, sess-fg-1 = 0
mise run test:step       # unchanged: the spawn block did not move (FR-002)
mise run test:apm
```

Expected: `ok` for every case; `git diff --stat -- tests/step` empty.

## install.sh check

```sh
CLAUDE_CODE_FORK_SUBAGENT=0 ./install.sh check | grep FORK   # ok line
CLAUDE_CODE_FORK_SUBAGENT=1 ./install.sh check | grep FORK   # note line
env -u CLAUDE_CODE_FORK_SUBAGENT ./install.sh check | grep FORK  # note line
```

The exit code is the same in all three (compare `echo $?` with the
variable at `0`).

## preflight by hand

```sh
env -u CLAUDE_CODE_FORK_SUBAGENT bash .apm/skills/feat/scripts/preflight.sh feat resume   # a spawn note: line (before any stop: line)
CLAUDE_CODE_FORK_SUBAGENT=0 bash .apm/skills/feat/scripts/preflight.sh feat resume        # no spawn note
```

## In Claude Code (after merge, by hand)

1. In a project, `<repo>/.claude/settings.local.json`:
   `{"env": {"CLAUDE_CODE_FORK_SUBAGENT": "0"}}`; start a new session.
2. Run `/feat <brief>`: setup shows no note; each spawn returns the agent's
   report (never "Async agent launched"), and the coordinator's next call
   is the `step.sh` boundary call.
3. A reviewer batch: the reviewers still run at the same time.
4. Without the setting: setup shows the note on every first setup call
   (until `0` or `1` is set); spawns are async.
5. `mise run measure --compare-since <merge date>`: `text only after a
   spawn` near 0 on the runs with the setting.
