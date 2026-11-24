# Research: configurable gates

Each decision: what was chosen, why, what else was weighed. Nothing in the
spec was left as NEEDS CLARIFICATION. The brief's "Alternatives rejected"
listed per-size keys; the user overturned that at the spec's clarification
(2026-11-24), so they are in scope here. R17 records how this plan settles
the points the earlier design review raised (D1–D14) on the per-phase-only
plan.

## R1 Where setup reads the gates

**Decision**: `preflight.sh` mode 1 (kinds `brief`, `issue`, `symptom`),
right after `step_base`'s fetch, reads
`refs/remotes/origin/<default>:.logistics.yml` with `git cat-file -e` /
`git show`, exactly as `step_hooks` reads `.specify/extensions.yml`, pipes
it to `tracker.sh gates <skill>`, and prints one `gates: <tokens> | none`
line. The coordinator keeps it, shows it when it is not `none` (naming
where it came from, R16), and passes it to `S init` as `'Gates=<value>'`.

**Rationale**: FR-010 (origin's default branch, which the worktree is
branched from) and FR-014 (the setup script prints, the coordinator passes
`Gates=`, the step script reads only the field). The setup chain
(`preflight.sh … worktree && S init … && S log … && T … setup`) is one
Bash command whose `S init` arguments are written before it runs, so the
value must come from mode 1: worktree mode's output could not reach `S
init` without an extra coordinator turn. Reading in mode 1 also stops a
malformed section before any worktree exists.

**Alternatives**: worktree mode prints it and the coordinator makes a
second Bash call (one more model turn per run); `preflight.sh` running
`state.sh init` itself (FR-014 rules it out); the checkout's working copy
(may hold uncommitted edits the worktree never sees; Assumption 8);
`state.sh init` or `step.sh setup` reading the file (FR-014).

## R2 One parser: `tracker.sh gates <skill>`

**Decision**: `tracker.sh gates <feat|fix>` parses the config text it
reads on stdin with the same `parse_config` as every other subcommand and
prints `tracker: gates <tokens>` (that skill's non-`auto` cells, canonical
order, R6) or `tracker: gates none`, exit 0. A malformed text prints
`tracker: error: .logistics.yml line <n>: <why>`, exit 1, whichever skill
the error is under. It runs before the repo lookup and the `gh` check, and
never calls `gh`.

**Rationale**: FR-013/FR-014 (one parser, strict style). The skill
argument keeps `preflight.sh` free of a token filter. Stdin avoids a temp
file: `parse_config` reads `<"$config"`, so `config=/dev/stdin`.

**Alternatives**: a second parser in `preflight.sh` (two parsers drift);
printing both skills and filtering in `preflight.sh` (a loop for nothing);
a path argument (a temp file for the blob, and its cleanup).

## R3 `tracker.sh` on Bash 3.2

**Decision**: replace the two constructs Bash 3.2 lacks: `declare -A st`
becomes three plain variables (`st_brief`, `st_building`, `st_review`) read
through one helper, and `${name,,}` a lowering through `tr` (or a `case`
on both spellings). Audit every `"${arr[@]}"` of a possibly empty array
under `set -u` (Bash before 4.4 calls it unbound): guard it as
`${arr[@]+"${arr[@]}"}`, as `step.sh` does. `tests/tracker/run.sh` gains
the construct grep `tests/step/run.sh` runs on `step.sh`.

**Rationale**: today `tracker.sh` runs only for board users; from now on
setup runs it for every repo whose `origin/<default>` has a
`.logistics.yml`, gates-only repos included, under whatever `bash` the user
has (stock macOS: 3.2). FR-018 binds the scripts that read gates.
`declare -A` sits at the top level, so it fails before any subcommand.

**Alternatives**: leave it Bash 4 (a gates-only user on macOS stops at
setup).

## R4 The `gates:` grammar and its errors

**Decision**: top-level keys `tracker` and `gates`, each optional, in any
order (the "tracker must be the first key" rule goes; the tracker
completeness checks run only when `tracker` is present). Under `gates`, at
two spaces, `feat` or `fix` (no value); under each, at four spaces, a phase
number whose value is either a plain value (`soft`, `hard`, `auto`, bare or
quoted) or a one-line flow mapping `{ <size>: <value>, … }` of `small`,
`medium`, `large`; a trailing ` # comment` allowed after either. `RE_KEY`
takes a key of lowercase letters or digits. The error rows are in
[contracts/config.md](contracts/config.md#errors). A key met in the wrong
section keeps today's `<key> outside <section>` form (`provider outside
tracker`, `brief outside statuses`, `feat outside gates`, `3 outside
gates.feat or gates.fix`); any other key at a known indent is `unknown
key`, except a non-skill key under `gates` (`unknown skill <k> (feat or
fix)`). Inside `{ … }`, each pair's key (the text before its first `:`,
trimmed) must match `^[a-z]+$` before any message names it: a matching
key that is not a size is `unknown size <k> …`, any other key (spaces,
digits, empty, other characters) is `bad size mapping in
gates.<skill>.<n>` with nothing echoed, so a committed file cannot put
free text into preflight's `stop:` line and the coordinator's context.

A phase written twice, whatever its forms (a plain value and a mapping
included), is `duplicate gates.<skill>.<n>`: one line per phase is the
only shape, so "plain and sized" is a second line for the same phase. A
multi-line mapping shows up as a phase line with no value, or a `{`
without its `}`: both are the value error (`… must be soft, hard, auto or
{ <size>: <value>, ... } on one line`).

**Rationale**: SC-005's kinds, each with its line number; the strict style
FR-013 asks for, reusing `parse_value`, `no_value`, `cfg_err`. Assumption 7
(the block form is refused; adding it later is additive).

**Alternatives**: accept the nested block mapping (a second indentation
level of state for no stated need); dedicated messages for plain-plus-sized
(the duplicate line already names the phase and the line).

## R5 The board switch is the `tracker:` key

**Decision**: `tracker.sh`, after parsing, says `off (no tracker: in
.logistics.yml)` and exits 0, with no `gh` call, for every subcommand but
`gates` when the file has no `tracker` key; a file with no key at all is
valid (empty or comments only). `preflight.sh`'s `step_board` runs `check`
whenever the file exists and maps a first line starting `tracker: off` to
`board: off`. `step.sh` (`/fix` 1 `issue to create`) and `preflight.sh`'s
worktree flag use one line test, `has_tracker_key <file>`: a line matching
`^tracker:( |#|$)` after stripping a CR. The coordinators' rule reads
setup's `board:` line, never the file (R16).

**Rationale**: FR-015/FR-016. The line test needs no `gh` and no full parse
(setup already parsed the file strictly); `preflight.sh` already keeps a
copy of one `step.sh` helper (`default_branch`) for the same reason
(scripts can't source each other).

**Alternatives**: `step.sh` calling `tracker.sh` (a process per `/fix` 1
gate, and a parse error mid-run would break a gate); reading the setup
line's board segment from the Log (a coordinator-written line).

## R6 The `Gates:` field and its tokens

**Decision**: `state.sh init` takes `Gates=<value>`, default `none`, and
writes `- Gates: <value>` after `- Issue:`. The value is `none` or
space-separated tokens of the init's skill: `<skill>.<n>=<v>` (a plain
value: every size) or `<skill>.<n>.<size>=<v>` (one size), `<n>` settable,
`<v>` `soft` or `hard` (`auto` cells are left out). Canonical form only:
phases ascending; within a phase either one plain token, or size tokens in
`small`, `medium`, `large` order, each at most once. Anything else is
`state: error`, an out-of-order value included (one canonical form, since
only `tracker.sh gates` produces it). `state.sh set` does not take `Gates`.
`step.sh` reads the header line into `F_GATES` and applies the same check
on every call (`step: error: Gates: <value> is not a canonical <skill>
gates value`); a missing field or `none` is all `auto`.

A mapping that gives all three sizes the same value is written as three
size tokens, not folded into a plain one: the two are equivalent in effect
(spec edge case), and folding is one more rule to test.

**Rationale**: FR-010/FR-011, SC-006; one writer, one reader. Only the
run's skill's cells are kept, so the line shown at setup and the field say
what applies to this run. The check is a dozen lines in each script,
copied like `default_branch` (scripts can't source each other).

## R7 Applying a cell in `step.sh`

**Decision**: three helpers.

- `gate_cfg <n> <size>`: `GC` = the token `<skill>.<n>.<size>=<v>`, else
  `<skill>.<n>=<v>`, else `auto`.
- `in_force <n> <holds>`: true when the size reason holds (`<holds>` 1) and
  `GC` is not `soft`. Every "skip the other rows when large" branch tests
  it instead of `SC` alone, so `soft` evaluates the small/medium rows
  (FR-004) and `hard` keeps today's large path.
- `size_gate <n> <holds> <size reason>`: called where each table adds its
  size reason (`large`, `US<n>: large`, `proposed size <s>`). `auto`: the
  reason when it holds (today). `soft`: no reason; `SOFTENED=1` when it
  would have held. `hard`: the reason when it holds, then `gates: hard`
  (`US<n>: gates: hard` at `/feat` 6).

The size is the run's (`size_col`'s `SC`, after any decrease the call
applies first, as at `/feat` 5); at `/fix` 1 it is the assessment's
`Proposed size` (FR-011). A cell for another size never matches, so it
changes nothing (FR-023). At `feat` 2 and `fix` 2, which have no size
reason, `gates: hard` is added after the table's reasons (`holds` 0, so
`soft` is the `auto` output: FR-009). `fix` 3 is R10.

**Rationale**: FR-002 to FR-006, FR-023 in one place; `auto` takes exactly
today's path, so every existing case is unchanged (SC-001).

## R8 Gate 3 and the plan rows at gate 4

**Decision**: gate 3 stops when `in_force 3 <large>` or `GC` is `hard`.
Its reasons, in order: the report-check reasons (as today), `large` (in
force), `gates: hard`, then today's large reasons (`assumption <k> needs
you`, `constitution: …`, `blocker`, the checklist rows). Otherwise the
merged record, with `; gates: soft` after the facts when `soft` removed
`large`.

"Gate 3 stopped" (`G3STOP`) means: the latest tagged `3 Plan` line holds
the reason `large` or `gates: hard` (a `; `-segment match, as
`apply_answer` matches reasons). On today's runs that is exactly "Size
large": a small or medium gate 3 line is tagged only for a report-check
reason. `plan_rows` splits in two: `plan3_rows` (the gate 3 reasons:
assumptions, constitution, blocker, the two checklist rows) and the rest
(size increase, fact missing, paraphrase contradicts). At gate 4:

| Size reason at 4 | `G3STOP` | Rows |
| ---------------- | -------- | ---- |
| in force | yes | `large` only (today's large) |
| in force | no (gate 3 softened on large) | `large`, then `plan3_rows` (FR-005) |
| not in force | no | every small/medium row (today's small/medium) |
| not in force | yes (`feat.3` hard on small or medium; large with `feat.4` soft and gate 3 not softened, the default on large) | the small/medium rows without `plan3_rows` (FR-007, Assumption 6; the exception FR-004, US1 scenario 4 and SC-003 name) |

`gates: hard` (value `hard` at 4) follows the size reason's place. The
`note: plan amended after gate 3` condition moves from `SC == large` to
`G3STOP` (identical on today's runs). In the second row only `plan3_rows`
run: FR-005 moves gate 3's reasons, not the other small/medium rows,
which `large` makes moot.

**Rationale**: FR-005, FR-007; one size-blind fact (`G3STOP`) replaces the
size test, so `feat.4` soft on large with a stopped gate 3 also skips what
gate 3 approved. The spec states that exception (FR-004, US1 scenario 4,
SC-003): at gate 4, a large fixture with gate 3 merged (`feat.3.large=soft
feat.4.large=soft`) matches medium exactly; one with gate 3 stopped
(`feat.4.large=soft` alone) matches medium once `plan3_rows` are set aside
(`tests/step` case 3).

## R9 The `; gates: soft` mark

**Decision**: appended as the last segment of a soft gate line when
`SOFTENED` is set: `5 Tasks`, `4 Design review`, `7 Code review`, `4 Code
review`, `1 Assess` (after `performance bug <v>`), the `3 Plan — merged
with 4` record, and the last story's `6 Implement [soft] — tasks done…`
line on a large run with `feat.6` soft (earlier stories log no gate line,
FR-008). Never on a hard line; never where nothing was removed (FR-009,
FR-023).

**Rationale**: FR-008; every reader of those lines takes `; `-separated
segments by prefix (`seg`, `review-summary`'s `split_top`,
`assess_facts`) and skips an unknown one; `apply_answer feat:6` tests
`tasks done: ` as a prefix.

## R10 `fix.3: hard`: one stop per test report

**Decision**: a flag `TR_GATES` (0 by default). `dec_fix_3` sets it to 1
before calling `test_rows`; `apply_answer fix:3` leaves it 0. With `GC`
hard for the run's size:

- a soft row of `test_rows` (`verified`; `failed` with `cycle` `first` and
  `retry-used` `no`) becomes, when `TR_GATES` is 1, the hard gate `- [x] 3
  Test [hard] — gates: hard; verdict: <verified|failed>` (one reason
  string, as `unaccounted items: …; verdict: …` is);
- every other `3 Test` gate `dec_fix_3` makes hard (sections, slug, a
  report check, a review fixes report without its Not verified line,
  unaccounted items, `partial`, `failed` after the retry) gets `gates:
  hard` as its last reason: it stops once, as it does today.

`approved` at any of them runs `apply_answer fix:3`, which re-runs
`test_rows` with `TR_GATES` 0: the verdict's row runs once (a soft row
logs `3 Test [soft] — verified` or the retry line; a hard row is its own
new gate, as today), and never stops again for `gates: hard`. The
`changed` check keeps its prefixes (`partial: `, `unaccounted items: `),
so a `gates: hard; verdict:` gate takes `approved`, `back to`, `stop`.
`soft` at `fix` 3 is the `auto` output.

**Rationale**: FR-006 at the one gate whose answer re-runs the rows; the
flag is the only new state, named, and tested both ways.

**Alternatives**: refusing `hard` at `fix` 2 and 3 (the earlier review's
D3; the approved spec keeps them settable, FR-001); a second answer stop
(the user approves the same report twice).

## R11 `feat.6: hard`

**Decision**: `US<n>: gates: hard` where `US<n>: large` is added today
(checks pass, no design problem); the one automatic retry after a failing
check stays soft with any value (the story is not finished yet).

**Rationale**: FR-006 ("stops after each story") mirrors the large rule.

## R12 `phase2-mode` gets its gate from `step.sh`

**Decision**: `state.sh phase2-mode <state file> [<3|4>]`: when the gate
is given, it is the gate that carries a soft phase 2's summary; without
it, today's Size rule. `step.sh` always passes it, from one helper
`gate3_stops` (Size and the `feat.3` cell: `in_force 3 <large>` or `hard`).
Resume needs no other change: `next_step` (`owed_amend '3 Plan'`),
`open_gate`, `token_of`, `allowed_tokens` and `apply_answer feat:3` are
size-blind already.

**Rationale**: FR-007's resume and done-phase logic; the gate-3 rule for
a run with gates stays in `step.sh` only (constitution III), and
`state.sh` reads no gates. The no-argument default is today's Size rule,
kept only for callers and tests that pass no gate; on a state file with no
`feat.3` cell it equals `step.sh`'s rule. The `tests/step` oracles that
call `state.sh phase2-mode` with no gate (`log-readers-agree`, `queries`)
therefore keep fixtures with no `Gates:` cell, and a case whose state file
carries one passes the gate to the oracle.

**Alternatives**: `state.sh` reading `Gates:` and repeating the rule (a
second copy of the cell lookup); a new query (one more subcommand).

## R13 The contract

**Decision**: [contracts/gates.md](contracts/gates.md) amends
`specs/013-step-command/contracts/gates.md` section by section (the rows it
changes, the new rows, the matrix), and the two `step-cli.md` lines that
call gate 3 large-only (`changed` at `/feat` 3 (large); `note: plan
amended after gate 3 … /feat 4, large`). 013's files are not edited. The
`docs/workflow.md` matrix links this contract by its GitHub URL under
`specs/020-configurable-gates/`; the shipper rewrites that path to the
numbered dir in the PR's own files when it renumbers.

**Rationale**: FR-020; earlier features' contracts stay as specified.

## R14 Diagrams and `measure.py`

**Decision**: no change. `gates.d2` draws a small or medium run with every
gate at its default and shows no size rule (FR-021 applies only if it
does); `chain.d2` shows checks, not gates. `measure.py` reads session
transcripts, not the Log, so a hard gate 3 on small counts as one gate
through its usual stop detection.

## R15 Docs

**Decision**: `docs/workflow.md` gets `## Configuring the gates` before
`## Phase details`: where the section goes, the two accepted forms, the
three values, that each can be set per size, the matrix (ten settable rows
with their per-size behaviour, two ship rows marked not settable, the
footnote), the setup line, the `Gates:` field fixed for the run, a setting
taking effect once pushed, `; gates: soft` on a softened line, and the
link to the contract. The sentences that tie a gate to a size, listed
one by one in [contracts/prompts.md](contracts/prompts.md#docs)
(`docs/workflow.md`, README line 83, `docs/usage.md`'s sizes table), say
"by default" or link the section; the list is the checklist, not a
general rule. `docs/install.md` gets `## 7. Configure the gates
(optional)` after 6 (no anchor renumbered). The README does not list the
file; its one size-gate sentence gains "by default".

## R16 What the coordinators show and decide

**Decision**: harness.md holds both skills' part once: a `gates:` line
other than `none` is shown as `Gates in force (from
origin/<default>:.logistics.yml): <value>`, `<default>` being setup's
`default:` value, and passed to `S init` as `'Gates=<value>'`; a `gates:
hard` reason means the repository set this gate to stop, and the skills
render it wherever they render `large` (contracts/prompts.md). Board
moves happen "only when setup's `board:` line is not `off` (on resume:
when `check` exits 0 and its line does not start with `tracker: off`)";
`/feat`'s and `/fix`'s resume steps carry the same clause, since resume
prints no `board:` line and the coordinator holds `check`'s raw line.

**Rationale**: the earlier review's D2 (where the values came from, for a
repo you didn't write) and D11 (the coordinator never reads the file); no
script change, two values setup already prints.

## R17 The earlier design review, settled

| Point | Settled by |
| ----- | ---------- |
| D1 `Gates:` editable by an agent | an assumption for the user: trusted like `Size:` (written only through `state.sh`, not guarded against agent edits), documented in the contract and `## The state file` |
| D2 the source of the shown line | R16 |
| D3 `hard` at `fix` 2, 3 | kept (FR-001, approved spec); `fix` 2 needs nothing (its answer enters 3); `fix` 3 is R10 |
| D4 the matrix in two places | kept (FR-019, FR-020); the docs copy links the contract |
| D5 tests by comparison | [contracts/gates.md](contracts/gates.md#tests-teststep): SC-003, FR-009, FR-023 and SC-001 compare two runs of one fixture; goldens only for new forms |
| D6, D8, D12, D14 | the spec (Assumptions 2, 6, 8; FR-007, FR-008, FR-010) |
| D7 FR-014's wording | the spec (FR-014) and R1 |
| D9 `fix.3: hard`'s mechanism | R10 |
| D10 docs and 013 lines that say large-only | R13, R15 |
| D11 harness.md's board sentence | R16 |
| D13 out-of-order values, wrong-section keys | R6, R4 |

## R18 The second design review, settled

The user kept assumption 1 (the `Gates:` field trusted like `Size:`,
documented in the contracts and `## The state file`; a guard for both
fields is a follow-up issue) and accepted D1–D7.

| Point | Settled by |
| ----- | ---------- |
| D1 a size key echoed unchecked | R4; FR-013; US4 scenario 3; contracts/config.md (Errors, `tests/tracker`) |
| D2 gate 4's plan rows on large with `feat.4` soft | FR-004, US1 scenario 4, SC-003 reworded; R8; contracts/gates.md (value table, case 3) |
| D3 board moves on resume | R16; US5 scenario 3; contracts/prompts.md (harness.md, both skills' resume steps) |
| D4 the size-gate sentences in the docs | R15; contracts/prompts.md (Docs, an explicit list) |
| D5 the prose that renders a hard gate keys on `large` | R16; contracts/prompts.md (both skills, harness.md) |
| D6 `phase2-mode`'s default and the test oracles | R12; contracts/config.md (`state.sh`); plan.md (Constitution III) |
| D7 "plan rows" and "gate 3 stopped" undefined in the spec | FR-007 |
