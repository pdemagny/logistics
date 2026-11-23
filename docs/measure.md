---
title: Measure
weight: 35
---

# Measuring what a run costs

`measure.py` reads the session transcripts Claude Code keeps on your
machine and reports what your `/feat` and `/fix` runs cost: tokens, a
weighted cost figure, where the time went and what each agent's first
request is made of. It is how a change to the workflow is judged: measure,
change, measure again.

It only reads. It opens transcripts read-only, writes nothing but its
terminal output, makes no network call and starts no other program. It
needs Python 3.11 or later (standard library only); `install.sh check`
says whether you have it ([install.md](install.md#4-check)). Nothing else
in logistics needs Python.

## Running it

The script ships with the `feat` skill, next to `tracker.sh`
([source](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/scripts/measure.py)).
Run it from inside the repo you want to measure:

| Installed with | Command |
| --- | --- |
| APM, user level (`apm install -g`), or the dev `./install.sh` | `python3 ~/.claude/skills/feat/scripts/measure.py` |
| APM, project level | `python3 .claude/skills/feat/scripts/measure.py` |
| Claude Code plugin | `python3 ~/.claude/plugins/cache/logistics/logistics/<version>/.apm/skills/feat/scripts/measure.py` |
| A clone of logistics | `mise run measure -- [options]` |

`mise run measure -- --help` prints the options (`mise run measure --help`
shows mise's own help for the task instead). From a clone the command runs
in the clone, so it measures logistics itself unless you pass `--project`
or `--all`.

Transcripts are read from `~/.claude/projects`, or from
`$CLAUDE_CONFIG_DIR/projects` when that variable is set.

## Options

| Option | What it selects or changes |
| --- | --- |
| *(none)* | the runs of the repo you are in, including those made in its worktrees |
| `--project PATH` | the runs of the repo at PATH instead; PATH must be an existing directory |
| `--all` | every repo on the machine: one block per repo, then an `all repos` block over every run |
| `--since YYYY-MM-DD` | runs invoked on or after that date (your local time zone) |
| `--until YYYY-MM-DD` | runs invoked on or before that date |
| `--session ID` | one run's own figures instead of medians; the id is searched in every project folder, so `--project` and `--all` are ignored |
| `--compare-since YYYY-MM-DD` | the medians before that date next to those since it (the date itself counts as since), with the difference |
| `--weights FILE` | a JSON file overriding the weights, and optionally giving prices ([below](#weights-and-prices)) |
| `--strict` | exit 1 when any run in the selection was left out |

`--project` and `--all` exclude each other, as do `--session` and
`--compare-since`. `--since` and `--until` apply first, then
`--compare-since` splits what is left. Exit codes: 0 for a report
(including "no runs found"), 1 only with `--strict`, 2 for a usage error
(unknown or conflicting options, a bad date, a `--project` path that is not
an existing directory, an invalid weights file; the message is on stderr).

## Reading the report

The header says what was selected and how it was counted:

```text
measure: /feat and /fix runs in ~/Projects/my-app and its worktrees
from ~/.claude/projects, 2026-03-01 to now
runs: 7 counted (5 finished, 1 unfinished, 1 resumed), 0 left out
weights: input 1, cache read 0.1, output 5, cache write 1h 2, cache write 5m 1.25; haiku 1, sonnet 3, opus 5
```

The first line reads `on every repo (--all)` with `--all`, and `runs,
session <id>` with `--session`. The date range appears only when you bound it; a
missing side prints as `start` or `now`. A selection with no run prints
one line, `no runs found in <dir> for <repo>`, and exits 0.

### What a run is

- **A run** is one session in which `/feat` or `/fix` was invoked (also as
  `/logistics:feat` or `/logistics:fix`) and at least one `feat-*` agent
  was spawned. `/brief` and `/tiny` sessions are not runs.
- **A run starts at its invocation.** Anything earlier in the same session
  (a `/brief` before it, say) is not counted: not its model calls, its
  tools, its time or its agents. Its date is the invocation's date.
- **Finished**: a `feat-shipper` agent was spawned. Only finished runs go
  into the medians.
- **Unfinished**: no shipper. Counted in the header and listed at the end
  under `unfinished runs (not in the medians)`.
- **Resumed**: the invocation's arguments start with `resume` (`/feat
  resume`). A resumed run is its own session, holding only part of the
  work, so it is kept out of the medians whether it finished or not, and
  listed at the end under `resumed runs (not in the medians)`.
- **Left out**: a run whose transcripts lack what the numbers need. It is
  left out whole, never half counted, and listed at the end under `left
  out:` with the reason and the Claude Code version that wrote it. The
  reasons: `model call without token usage`, `event without timestamp`,
  `unreadable line`, `agent transcript missing`, `no message origin
  recorded`, `unexpected record shape` (anything else that failed while
  reading it, a recorded directory that cannot be resolved included: its
  repo then shows as `unknown`, so only `--all` and `--session` list it;
  the error text is never printed). A session with no `feat-*` agent is
  not a run, whatever its defect, and is not listed. Without `--strict` the
  other runs are reported and the exit code is 0.

### The figures

Each skill (`/feat`, then `/fix`) gets its own block. Every figure is first
worked out per run, then the block shows the median over the finished
runs (the mean of the two middle values for an even count). Medians of
shares need not add up to 100%.

**Coordinator**: the session that ran `/feat` or `/fix`.
- `model calls`, split into calls that `spawn an agent`, `chores` (tool
  calls but no agent, including a `SendMessage` to an agent already
  running) and `text only`;
- `text only after a spawn`: how many of the `text only` calls come first
  after a spawn batch. A batch is the `Agent`, `Task` and `SendMessage`
  calls of one model call; the figure counts the first call after the
  batch's last result, when it has no tool call. It shows the waiting turn
  of background spawns (the coordinator answers "agent launched, waiting"
  and a model call is spent); with foreground spawns it is about 0
  (`SendMessage` continuations aside). See
  [install.md](install.md#6-wait-for-agents-optional);
- `context, first call`, `context, median of calls`, `context, max of
  calls`: the tokens in its context (input, cache write and cache read) at
  its first call, and the median and largest over all its calls;
- `cost share`: its part of the run's cost units (coordinator plus all its
  agents make 100% of one run);
- `failed tool calls`: by tool, the **total** over the finished runs, not
  a median (a median of a rare count is nearly always 0).

**Agents**: one row per agent type, by cost share. `runs` is how many runs
the type appears in, and its other figures are medians over those runs
only. `spawns/run`; `calls/spawn` (model calls); `ctx first` (context at
its first call); `cost share`; `model min` and `tool min`, its own time
split: a gap in the agent's transcript ended by a model reply is model
time, one ended by a tool result is tool time. Per-spawn figures are the
mean over that run's spawns of the type.

**Wall clock**, in minutes and as a share of the run's duration, split
along the coordinator's own timeline, each gap between two of its events
going to what ended it:
- `agents working`: an agent's report arrived, or the notice that an agent
  ended (parallel agents count once);
- `waiting for the user`: a message you typed;
- `coordinator thinking`: a model reply;
- `coordinator tools`: a tool result, or the notice that a background
  command of the coordinator's ended.

The four add up to `run duration`, from the invocation to the run's last
event. `user answers` counts the messages you typed during the run.

**First request**, in characters, from the first spawn of each agent type
in a run: `tools` (the tool schemas), `skills listing`, `system prompt
(includes Claude Code's own)` and `instructions` (the instruction files and
how many), each with its share, then the largest tool schemas by name. A
type whose transcripts don't record it prints `not recorded`.

**Tokens (per run)**: `input`, `cache write`, `cache read` and `output`,
then `cost units` (the weighted figure below), and `USD` only when you gave
prices. Tokens print as integers below 10,000, then as `18.2k` or `1.4M`.

### Comparing (`--compare-since`)

Each figure gets three columns, `before`, `since` and `diff` (since minus
before, signed; shares as percentage points, `+3pp`), and the block heading
gives the number of runs on each side. A side with no finished run prints
`no runs`. Something on one side only (an agent type, a tool schema, a
failed tool) prints `-` on the other side and no diff, and failed tool
calls show each side's total and number of runs with no diff, since totals
over different numbers of runs don't subtract. The comparison is a
difference of medians and nothing more: with a handful of runs on each
side, read it as a hint.

## Weights and prices

Cost units weight each token kind and each model. The defaults, exactly as
`--help` and every report print them:

```text
weights: input 1, cache read 0.1, output 5, cache write 1h 2, cache write 5m 1.25; haiku 1, sonnet 3, opus 5
```

A cache write goes to the 1-hour or the 5-minute cache by the usage
record's breakdown; a write with no breakdown is weighted as 5-minute. A
model is matched by its full id, else by one of its `-`-separated parts
(`opus` in `claude-opus-5-5`). A model with no weight is weighted as the
highest model weight in effect and named after the blocks (`unweighted
models: <id> (weighted as 5)`).

`--weights FILE` overrides any of them. Every section and key is optional:

```json
{
  "tokens": { "input": 1, "cache_read": 0.1, "output": 5, "cache_write_1h": 2, "cache_write_5m": 1.25 },
  "models": { "haiku": 1, "sonnet": 3, "opus": 5, "claude-opus-5-5": 5 },
  "prices": { "opus": 5.0, "sonnet": 3.0, "haiku": 1.0 }
}
```

`tokens` takes exactly those five keys; `models` and `prices` take a model
id or part of one. Every value must be a number ≥ 0 (`true`, `NaN`,
`Infinity` and a negative number are refused with exit 2). The script
carries no price table: money appears only when you give `prices`, in USD
per million **input** tokens of that model. Then a `prices:` line follows
the weights line, and each block gets a `USD` row: tokens × token weight ×
price / 1,000,000, without the model weight (the price already stands for
the model). So with the default token weights, output costs five times
the input price and a cache read a tenth of it. A model with no price is
priced as the highest price given and named (`unpriced models:`).

## Claude Code versions

The transcript format is Claude Code's own and undocumented. The script
was written against transcripts from Claude Code 2.1.304 to 2.1.328. A run
written by another version is either read correctly or left out with its
version named; it is never half counted. Record types the script doesn't
use are ignored.

## Limits

- Duration is wall clock from the invocation to the last event, so idle
  time counts: a gate left open overnight shows as hours of `waiting for
  the user`.
- A resumed run is its own session, holding only the part of the work
  done after the resume, so it is listed apart and kept out of the
  medians; the session it resumed is counted on its own.
- Sessions are attributed to a repo from the working directory each
  transcript records. A worktree counts for its repo, but a worktree
  outside the repo's directory that no longer exists can't be traced back,
  so it counts as its own repo.
- First-request sizes are characters, not tokens, and come from each
  type's first spawn in a run.
- Messages you queue while the coordinator works, and other records that
  are neither model replies, tool results, agent reports nor your typed
  messages, end no gap in the wall clock.

## Before sharing the output

The output holds repo paths, your home directory and session ids. Before
posting it anywhere public, keep only the figures of the `all repos` block
of an `--all` run: leave out the header's paths, the per-repo blocks, and
the unfinished, resumed and left-out lists. Never post a transcript.
