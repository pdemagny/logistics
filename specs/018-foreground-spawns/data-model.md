# Data model: foreground spawns

No stored data. Three things the code reads or computes.

## Setting

`CLAUDE_CODE_FORK_SUBAGENT`, read from the environment of the shell the
script runs in (`${CLAUDE_CODE_FORK_SUBAGENT:-}`), never from a settings
file.

| Value | Meaning | preflight (mode 1) | `install.sh check` |
|---|---|---|---|
| `0` | foreground opt-in | no note | `ok` |
| `1` | keep background, chosen | no note | `note` |
| unset or empty | undecided | `spawn note:` | `note` |
| anything else | treated as chosen | no note | `note` |

Worktree mode never prints the note. The value never changes an exit code
and is never printed.

## Spawn batch (measure.py)

- **ids**: the `tool_use` ids of the spawn blocks of one coordinator call
  (one `message.id`), for the names in `WAIT_TOOLS` = `SPAWN_TOOLS` +
  `("SendMessage",)`.
- **open → closed**: open while one of its ids has no `tool_result` yet;
  closed by the last one. A newer batch replaces an open one.
- **first call after**: the first counted coordinator call with a new
  `message.id` after the batch closed (synthetic and API-error records are
  not calls, as today).

## Text-only turn after a spawn

A batch's first call after whose `tools` list is empty once the session is
read. Per run: `after_spawn` = how many batches have one (int, 0 when there
is no batch). Per block: the median over the runs, like every coordinator
figure; `--compare-since` diffs it.
