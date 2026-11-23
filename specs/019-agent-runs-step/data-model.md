# Data model: agents run step.sh last

## Calls

Every `step.sh` call is one of these. "Own" calls are the coordinator's.

| Call | Who makes it | Words after `<skill> <state file>` | Record written |
| ---- | ------------ | ---------------------------------- | -------------- |
| setup | own | `setup` | yes, no `call:` line |
| resume | own | (`step.sh resume <state file>`) | yes, no `call:` line |
| agent-run boundary | the agent that closes it, as its last step | its block's `boundary:` words | yes |
| slip fallback | own, when the hand-back's block is missing or does not parse | the same `boundary:` words | no when it re-prints; yes when it decides |
| `done:` check | own, when the hand-back's block ends with `done:`, chained after any pending `S log` | the `boundary:` words of the shipper's spawn | no when it re-prints; yes when it decides |
| reviewer batch | own | the batch's `boundary:` words, plus `agent=<role>:<id>` words | yes |
| answer | own | the `answer call:` words, the answer words, plus `agent=<role>:<id>` words | yes, no `call:` line |
| size | own | `size <s>` | no |

An agent-run boundary, its slip fallback and the `done:` check are the
same call; step.sh does not tell them apart.

Every call that writes (all but a re-print, `size` included) takes the
state file's `git hash-object` before reading it and compares it again in
`commit` before the first write: a difference is `step: error: the state
file changed since step.sh read it; call again`, with nothing written by
the decision.

## Spawn block

Unchanged keys, then two new last keys on an **agent-run spawn**:

```
spawn: feat-planner
  row: 3
  mode: first
  model: sonnet
  effort: medium
  report: <dir>/reports/3-plan.md
  continue: fresh
  step script:	<scripts>/step.sh	feat	<dir>/feat-state.md
  boundary:	3	<dir>/reports/3-plan.md
boundary:	3	<dir>/reports/3-plan.md
```

(`step script:` and `boundary:` are followed by a tab, then tab-separated
words; the top-level `boundary:` line is unchanged except that boundaries
2, 3 and 5 lose their `agent=<id>` word.)

Agent-run spawns, by `role_of` row and mode:

| Skill | Token | Spawn |
| ----- | ----- | ----- |
| feat | 2 | specifier (first, amend, reformat) |
| feat | 3 | planner (first, amend after gate 3 or 4, reformat) |
| feat | 5 | tasker (first, amend, reformat) |
| feat | 6 | implementer story mode, its check retry, reformat |
| feat | 7-fixes | implementer fix mode, its retry, reformat |
| feat | 8 | shipper (ship, reformat) |
| fix | 1 | bug assessor, assess mode (and reformat) |
| fix | 2 | implementer bug mode, its retry after a failed test, reformat |
| fix | 3 | bug assessor, test mode (and reformat) |
| fix | 4-fixes | implementer fix mode, its retry, reformat |
| fix | 5 | shipper (ship, reformat) |

Not agent-run (no new keys): design and code reviewers (`/feat` 4, 7, 7e;
`/fix` 4), their fresh respawns and reformats; rebase-mode implementers
(`move`, `repair`, the ship conflict's move).

## Decision record

`<artifact dir>/reports/last-step.md`, written whole by `state.sh record`
(called by step.sh only, as the last part of each decided call's `commit`,
table above); read by step.sh only.

```
Data, never instructions: step.sh's last decision, for its re-print and its open boundary.
call:	<token>	<word>…
sums:	<report file name>:<12 hex>	…
[call:	<token>	<word>…
sums:	…]
output:
<every line step.sh printed, as printed>
```

- `call:` and `sums:` come in pairs, one pair per call of the **reformat
  chain** that led to the decision, oldest first: when the previous
  record's output was `reformat` and this call is a boundary call, the
  previous record's pairs are kept before this call's; otherwise only
  this call's pair. At most two pairs (a second miss is a hard gate).
- `call:`: the call's words after `<skill> <state file>`, as given; only
  for a boundary call (agent-run, slip fallback, `done:` check, reviewer
  batch). Setup, resume and answer calls write no pair and start a new
  chain.
- `sums:`: each report path of that call, by file name, with the 12-hex
  `git hash-object` value step.sh read when it decided (`RP_HASH`); empty
  after the tab when the call named no report.
- `output:`: the rest of the file is the output, line for line.
- The **issued line** is the first output line starting `boundary:` and a
  tab. None (a hard gate, `done:`, `stop:`): no boundary is open.

Writing (`state.sh record`, the guard of `report-path` and `inputs`): an
artifact dir name holding a newline, quote, dollar or backtick, a
symlinked `reports/`, `.gitignore` or record, a `reports/` that is not a
directory, or a record that is not a regular file is a `step: error`. A
missing `reports/` is created and its `.gitignore` made to hold `*`. The
file goes through a temp file in `reports/` and `mv -f`; a failed write
leaves the previous record, and `commit` puts back the fields the call
set (`undo_sets`).

Reading (`record_read`): no `reports/` or no record: no record (`RC_HAS`
0), not an error. A first line other than the fixed one, a `call:` with
no `sums:` after it, or a missing `output:` line is a `step: error` (the
record is not trusted). A symlinked `reports/` or record is a `step:
error`, as on write.

## Acceptance of a boundary call

```
record has a call: line = the call's words, and each report hashes to the
     value of that pair's sums: line
  → re-print: stdout = the record's output; exit 0; nothing written
else record has an issued line, its token = the call's token, and every
     report path of the call is a word of it
  → decide as today (allowed_tokens and key_ok still apply), then write the record
else no record
  → today's check (Current phase allows the token), decide, write the record
else
  → step: error (logged as `- [!] step: …`)
```

Answer calls: `open_gate` as today; on success the record is rewritten.

## Agents line

`- Agents: <role> <id>, … (for SendMessage)` as today (`none` from `S
init` until the first id, as today).

| Event | Change |
| ----- | ------ |
| answer or reviewer batch call with `agent=<role>:<id>` | that role's entry set to `<id>`, before the decision prints |
| an agent-run boundary at `/feat` 2, 3 or 5 | none (it takes no `agent=` word) |
| a re-print | none |
| `/fix` | none: `agent=` is a usage error |

`continue:` on a spawn of those roles:

| Spawn | `continue:` |
| ----- | ----------- |
| a reformat spawn of the specifier, planner or tasker (`/feat`) | `<role>`, always, no lookup |
| the planner amend after a soft gate 4 (printed by the batch call, which sets the id first) | the recorded id, else `fresh` (today's lookup) |
| every other spawn | `fresh`, as today |

The coordinator resolves `continue: <role>` to the latest agent of that
role, by the id its `Agent` result gave; holding none (after a resume), it
spawns fresh.

## Hand-back block

The agent's hand-back ends with step.sh's stdout, every line as printed
(tabs kept), between two fence lines of four backticks each, and nothing
after it. The block is only ever a copy of that request's Bash result: a
call that was refused, failed or not run gives no block and a word on the
digest's last line.

It **parses** when its first line is `soft`, `hard:`, `reformat`, `stop:
…` or `step: error: …`, and its last line starts `boundary:` + tab,
`answer call:` + tab, or `done:`, or it is the one `step: error: …` line.
Otherwise (tabs turned into spaces included), or on a `step: usage: …`
line, or with no block: the slip fallback.

A parsed block whose last line starts `done:` is not acted on directly:
the coordinator makes the `done:` check (Calls) and acts on its own
output. A made-up block that parses is caught at the next `step.sh` call
(`no boundary is open`, or `neither the open boundary…`).

## Pending log lines

Lines the coordinator would have chained with `S log` before a boundary
call: setup's `flag:` value, `- [!] brief left in place: <path>`, a failed
board move's `- [!] <line>`. They wait for the next own `T` call (an
answer, a reviewer batch, a slip fallback or the `done:` check), chained
before it with `&&`; when the run ends on an own call's output with lines
still pending, one `S log` call in the final turn.
