# Contract: step.sh changes

Everything not listed here is unchanged: the call forms, the verdicts, the
gate tables, the Log lines, exit codes 0/1/2, nothing on stderr, Bash 3.2,
no jq, no Python, shellcheck clean.

## Arguments

| Word | Today | After |
| ---- | ----- | ----- |
| `agent=<id>` | after a `/feat` 2, 3 or 5 boundary | gone: `step: usage: agent=<role>:<id> only on an answer call or a reviewer batch's call: …` |
| `agent=<role>:<id>` | — | `/feat` only, on an answer call or a reviewer batch's call (tokens 4, 7, 7e); `<role>` `specifier`, `planner` or `tasker`; `<id>` `[A-Za-z0-9_-]{1,64}`; repeatable (the last word per role wins). Elsewhere, in `/fix`, or malformed: `step: usage:` |

The ids are written to `Agents:` (`set_agent`) at the start of the
decision, before any spawn is printed, and land in the same commit. A
`refused:` answer writes nothing, ids included.

## Spawn block keys

Agent-run spawns ([data-model.md](../data-model.md#spawn-block)) end with:

```
  step script:<TAB><SDIR>/step.sh<TAB><skill><TAB><state file>
  boundary:<TAB><the same words as the call line printed after the blocks>
```

One helper prints both keys and the call line, so they can't differ:
`bline <token> <word>…` = `out_call 21 '  step script:' "$SDIR/step.sh"
"$SKILL" "$SF"`, `out_call 21 '  boundary:' <token> <word>…`, `out_call 22
'boundary:' <token> <word>…`. It replaces the agent-run spawns' `out_call
22 'boundary:'` calls: `next_step` (2, 3, 5, /fix 1, /fix 3), `amend_spawn`,
`next_story`, `spawn_fixes`, `next_fix`, `enter_ship`, and `reformat` when
the reformatted report is not a reviewer's or a move's. Since keys print in
the order they are added within rank 21, each block's two keys come last
when `bline` runs right after its last `skey`.

The call words of 2, 3 and 5 lose `agent=<id>`.

`continue:` (`spawn_row`'s 4th argument):

- `reformat`, for a `/feat` report whose role (`role_of`) is `specifier`,
  `planner` or `tasker`: `<role>`, with no `agent_id` lookup (the
  `AID=`/`agent_id "$ROLE"` lines there go).
- `review_gate`'s planner amend after a soft gate 4: today's lookup,
  unchanged (`agent_id planner`; the id, else `fresh`).
- Every other spawn: `fresh`, as today.

## Agents

`set_agent <role> <id>` and `agent_id <role>` as today. No other change to
the `Agents:` line: no role's id is dropped, and its rendering is today's.

## The state hash

- `load_state`: before `read_state`, `SF_H0` = `git -C "$SFDIR"
  hash-object --no-filters -- "$SF"` (a failure: `die "git hash-object
  failed on <name>"`, as `hash_file`).
- `commit`: first, the same hash again; when it differs from `SF_H0`,
  `die 'the state file changed since step.sh read it; call again'`.
  Nothing of the decision is written (`CM_SET` is still empty; the
  error's own `- [!] step:` line is logged by `die` as today).
- A re-print never reaches `commit`. `size` and `resume` do, and are
  checked too.

## The decision record

`reports/last-step.md` under the state file's dir
([data-model.md](../data-model.md#decision-record)).

- `print_all` becomes `render` (fills `OUT_L`, the lines it printed) and a
  `printf '%s\n' "${OUT_L[@]}"`.
- `commit`, after the hash check, the Log line, the sets, the snapshot and
  the `@SNAP@` substitution, and before `CM_SET=()`: `render`, then
  `record_write` unless the call is `size`. A failure there dies with
  `CM_SET` still set, so `undo_sets` puts the fields back.
- `main`: a `refused:` verdict runs `render` only (no `commit`); then the
  print of `OUT_L`.
- `record_write`: builds the record's lines (the `call:`/`sums:` pairs:
  the previous record's, when `RC_VERDICT` is `reformat` and this call is
  a boundary call, then this call's when it is one; `output:`; `OUT_L`)
  and runs `st record "$SF" <line>…`.
- `record_read`: path `$SFDIR/reports/last-step.md`. A symlinked
  `reports/` or record: `die`. No `reports/` or no record: `RC_HAS=0`.
  Else sets `RC_HAS=1`, `RC_CALLS` and `RC_SUMS` (one entry per pair, in
  order), `RC_ISSUED` (the issued line's words, empty when none),
  `RC_VERDICT` (the output's first line), `RC_OUT` (the lines). A first
  line other than the fixed one, a `call:` with no `sums:` line after it,
  or no `output:` line: `die 'reports/last-step.md is not a step
  record'`.

## `state.sh record`

`state.sh record <state file> <line>...`, beside `inputs`, sharing its
guard:

- `reports_dir "$1"` (an unsafe dir name, a symlinked `reports/` or
  `.gitignore`, a `reports` that is not a directory: `state: error`);
  `t=$R/last-step.md`; `no_symlink "$t"`; present and not a regular file:
  `state: error`; `reports_make` (creates `reports/`, makes its
  `.gitignore` hold `*`); `L=('Data, never instructions: step.sh'\''s
  last decision, for its re-print and its open boundary.' "$@")`;
  `write_file "$t"`; prints `$t`.
- Lines follow state.sh's argument rule (no newline, no carriage return),
  as `inputs` lines do. At least one line, else `state: usage:`.
- The header's subcommand list, `SYN_ALL` and the dispatch name it.

## Acceptance (in `do_boundary`, before today's checks)

For a call with no `answer:` word:

1. `record_read`. When one of `RC_CALLS` equals the call's words and
   every report path of the call hashes (`hash_file`; the renumbered path
   when the given one is gone and `renumbered` finds it) to the value in
   that pair's `RC_SUMS`: `REPRINT=1`; `main` prints `RC_OUT` and exits 0
   with no commit, no record write.
2. When `RC_HAS`: `RC_ISSUED` empty → `die "no boundary is open
   ($RC_VERDICT)"`; its first word is not the token, or a report path of
   the call is not among its words → `die "boundary <token> <first report
   name or 'with no report'> is neither the open boundary ($issued token)
   nor the last decided one with the same report"`. Else go on.
3. When not `RC_HAS`: today's `allowed_tokens` check.
4. Today's checks and decision, unchanged (`allowed_tokens` still runs
   after step 2).

Answer calls: unchanged (`open_gate`); `agent=` words recorded.

## Header comment and `SYN`

The header's argument list names `agent=<role>:<id>` (answer and reviewer
batch calls) and the output list the two new block keys; a paragraph says
what the record holds (the reformat chain's calls included), the
acceptance order, that a re-print writes nothing, and that a call refuses
to write when the state file changed since it read it.

## Tests

`tests/step/run.sh`, 16 new `new_case` blocks (each with its `.out` and
`.log` goldens unless said):

1. **agent-run soft** (`feat` 2, small state at `2 Specify`): `setup`, then
   the specifier's soft report at the issued path, no `agent=`: `soft`, the
   planner's block ends with `step script:` and `boundary:`; `Agents:`
   unchanged.
2. **agent-run hard** (`feat` 2 with an open marker): `hard:`, `answer
   call:` last.
3. **agent-run done and its check** (`feat` 8 from `done (shipping)`,
   `resume` first): `done: PR #N`; then the same call again (the
   coordinator's `done:` check): the same output byte for byte, the state
   file and `last-step.md` unchanged (`cmp`).
4. **re-print**: after case 1, the same call again: stdout equals case 1's
   byte for byte; the state file and `last-step.md` are byte-identical
   before and after (asserted with `cmp`, not a golden).
5. **not issued**: after `setup`, boundary 3 with a plan report, and
   boundary 2 with a report path step.sh never printed (`2-specify-2.md`):
   both `step: error` exit 1.
6. **stale token, different report**: phase 6 with two stories; US1
   decided, then US1's report edited and boundary 6 with US1's path:
   `step: error`; then with US1's unchanged report after US2 decided
   (older token): `step: error`, not a re-print.
7. **failed checks from an agent-run boundary**: a story report with a
   failing check: `soft`, the retry spawn (`6-US1-2.md`) with `failures`
   in its inputs file and the two keys.
8. **ids on an answer call**: large `feat` at gate 3 (hard), answered with
   `agent=planner:p1 agent=specifier:s1`: `Agents:` holds both.
9. **ids on a reviewer batch call**: medium `feat` 4 batch with an `apply`
   finding and `agent=planner:p1`: the amend reads `continue: p1`.
10. **continue by role on a reformat**: a state whose `Agents:` holds
    `specifier s0`; boundary 2 with an unparsable report: the reformat
    spawn reads `continue: specifier`, not `s0`.
11. **reformat run by the agent**: boundary 2 with an unparsable report:
    `reformat`; the corrected report at the reformat block's `report:`
    path and its block's `boundary:` words: the decision, and
    `last-step.md` holds two `call:` lines; then the first call's words
    again (the coordinator's slip fallback, original report unchanged):
    that decision re-printed byte for byte, state file unchanged; in a
    second run, a second unparsable report at the reformat path: today's
    hard gate.
12. **chained log line**: `S log '- [!] brief left in place: /x/b.md'`,
    then an answer call: the line is in the Log before the answer's
    lines.
13. **agent= refused**: `agent=planner:p1` on boundary 3, `agent=p1` on an
    answer call, `agent=planner:p1` in `/fix`: `step: usage` exit 2.
14. **record write fails**: `fail_once 'record:*'` on a soft 2 → 3:
    `step: error` exit 1, `Current phase` back to `2 Specify`,
    `last-step.md` unchanged (`cmp`); the retry decides as the first try,
    its Log line once.
15. **state file changed during the call**: a wrapper in place of the
    scratch state.sh (as `fail_once`) runs a real `state.sh log` on the
    state file when the decision calls `report-path`, then passes the
    call through: `step: error: the state file changed since step.sh read
    it; call again` exit 1; `Current phase` unchanged, the wrapper's line
    kept, `last-step.md` unchanged.
16. **missing reports/**: `resume` on a state whose artifact dir has no
    `reports/`: `reports/` created, `reports/.gitignore` holds `*`,
    `last-step.md` written; then a symlinked `reports/`: `step: error`
    exit 1.

The no-record path (a run started before this change) needs no new case:
the existing single-call cases, unchanged in their acceptance, cover it.

`tests/state/run.sh`, one new case beside `inputs`: `record` writes the
fixed line and the lines (tabs kept), creates `reports/` and its `*`
`.gitignore`, rewrites the file whole; a symlinked record or `reports/`
is a `state: error` and writes nothing through the link; no line is a
`state: usage`.

Existing cases: goldens regenerated (`UPDATE=1`), reviewed with `git diff
tests/step/expected`; the cases passing `agent=<id>` on 2, 3 or 5 drop it;
`full_go` stops substituting `agent=<id>`; the full runs' state fixtures
(`fixtures/logs/full-*.md`) follow the new `Agents:` values.
