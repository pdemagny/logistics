# Brief: Configure each gate of /feat and /fix as soft, hard or auto in .logistics.yml
- Size: medium — ~38 tasks expected: a new `gates:` section in `tracker.sh`'s parser, board tracking keyed on `tracker:`, the effective gates read at setup and kept in the state file, `step.sh` applying them at ten gates, their tests, and the docs
- Short name: configurable-gates
- Kind: feat
- Issue: #34

## Why
Whether a phase stops (hard gate) or goes on with a one-line summary (soft
gate) is fixed by the gate tables `step.sh` applies, mostly by size. A user
who never wants to stop after every story on a large run, or who wants to
see every plan even on a small feature, has to say so at every gate of
every run, and the coordinator does not carry it across phases or a
`/feat resume`. The loop should adapt to the people running it, not the
other way round.

## Today
- `step.sh` decides each gate from the tables of
  `specs/013-step-command/contracts/gates.md`. Size enters them through one
  reason only: `large` at `/feat` 3, 4, 5, 6 (after every story) and 7 and
  at `/fix` 4, and `proposed size <s>` at `/fix` 1. Every other hard reason
  is a safety or judgement trigger.
- A soft gate already prints an `answer call:` so the user can override it
  at that gate; there is no way to set a gate for every run.
- `.logistics.yml` holds only `tracker:`; `tracker.sh` refuses any other
  key, and the file's presence alone means "board tracking on" (`/brief`,
  `/tiny`, `harness.md`, `preflight.sh`, and `/fix` 1's `issue to create`
  row in `step.sh`).

## Behaviour
- `.logistics.yml` takes an optional `gates:` section, keyed by skill and
  phase, each value `soft`, `hard` or `auto`:
  ```yaml
  gates:
    feat:
      3: hard      # always stop after the plan
      6: soft      # no stop between stories, even on large
    fix:
      1: soft
  ```
  A missing key, or `auto`, is today's table. Settable: `feat` 2–7, `fix`
  1–4. Ship (`feat` 8, `fix` 5) is not settable.
- `soft` removes only the size reasons (`large`; `proposed size <s>` at
  `fix` 1). Every other reason still makes the gate hard, whatever the
  config says. At a gate with no size reason (`feat` 2, `fix` 2 and 3),
  `soft` is accepted and changes nothing.
- `soft` at a large gate evaluates exactly the reason rows small and medium
  evaluate, no row added or dropped. Today `step.sh` skips those rows when
  `large` holds (e.g. `if [[ $SKILL == fix || $SC != large ]]` near
  `step.sh:2908`, and the large branches of gates 3 and 5), so this
  restructures those branches rather than removing one reason.
- `feat.3: soft` on large behaves exactly like small: no gate 3 (`- [x] 3
  Plan — merged with 4; <facts>`), and the large-only gate 3 reasons
  (assumption needs you, constitution, blocker, checklist item) are checked
  at gate 4, as on small.
- `hard` adds the reason `gates: hard`, so the gate stops even when no
  other reason holds. At `feat` 6 it stops after each story.
- `feat.3: hard` on small or medium is the large gate 3 with `gates: hard`
  in place of `large`: the same Log line form (`- [x] 3 Plan [hard] —
  gates: hard[; <other reasons>]; <facts>`), the same reasons, the same
  answers (`approved` → phase 4; `changed` → planner `amend`, then `- [x] 3
  Plan — amended; <facts>`), and resume and the done-phase logic treat it
  as they treat the large gate 3. Gate 4 keeps its small/medium rows
  unchanged (and its `note: plan amended after gate 3`).
- A gate softened by config says so on its Log line (`; gates: soft`), so
  the record shows why a large run did not stop.
- The matrix of what each value does at each gate (below) is in
  `docs/workflow.md`, in a new `## Configuring the gates` section linked
  from `/fix`'s `### Gates`:

  | Gate | Today small · medium · large | `soft` changes | `hard` changes | Always hard |
  |---|---|---|---|---|
  | `feat.2` Specify | soft · soft · soft | nothing (no size reason) | stops after the spec | open markers, blocker, size remark, no spec |
  | `feat.3` Plan | none (merged with 4) · none · **hard** `large` | large: no gate 3, merged with 4 like small; its reasons are checked at gate 4 | small/medium: the large gate 3, reason `gates: hard` | when gate 3 stops: assumption needs you, constitution, blocker, checklist item (with no gate 3, these are checked at gate 4) |
  | `feat.4` Design review | soft* · soft* · **hard** `large` | large: soft* | stops always | `rec: user`, assumption needs you, constitution, blocker, size increase, paraphrase contradicts, checklist item, fact missing |
  | `feat.5` Tasks | soft* · soft* · **hard** `large` | large: soft* | stops always | CRITICAL/HIGH, analyze not run, `story.sh` mismatch, unanswered checklist, size increase, fact missing |
  | `feat.6` Implement (per story) | soft* · soft* · **hard** `large` after each story | large: no stop between stories | stops after each story | Not verified line missing, checks fail after retry, design problem |
  | `feat.7` Code review | soft* · soft* · **hard** `large` | large: soft* (applies `apply` recommendations) | stops always | `rec: user`, `S` finding, criterion not met, empty diff |
  | `feat.8` Ship | not settable | — | — | ship blocked |
  | `fix.1` Assess | soft* small only · **hard** `proposed size` · **hard** `proposed size` | medium/large: soft* | stops always | every other row: untrusted author, needs approval, security risk area, issue to create, needs reproduction, open questions, several bugs, confidence, reproduction, remediations, public behaviour change, sections, slug |
  | `fix.2` Fix | soft* · soft* · soft* | nothing | stops after the fix | deviations (size increase), check fails, status, Not verified line missing |
  | `fix.3` Test | soft* · soft* · soft* | nothing | stops after the test | partial, failed after retry, unaccounted items |
  | `fix.4` Code review | soft* · soft* · **hard** `large` | large: soft* | stops always | security risk area, `rec: user`, `S` finding |
  | `fix.5` Ship | not settable | — | — | ship blocked |

  \* soft only when nothing in the last column applies. On every gate, a
  failed report check, an unparsable report or files changed outside the
  reports also make it hard.
- The effective gates are read once, at setup, from the worktree's
  committed `.logistics.yml`, and logged in the state file. Every later
  boundary and a resume use the logged gates; editing the file mid-run does
  not change a run already started. Setup shows them in one line when any
  is not `auto`.
- A malformed `gates:` section (unknown skill, a phase outside the
  settable ones, a value outside `soft | hard | auto`, bad indentation, a
  duplicate key) stops setup with the file's line number, like a bad
  `tracker:` section does today.
- Board tracking turns on from the `tracker:` key, not from the file
  existing: a `.logistics.yml` with only `gates:` leaves it off.
  `tracker.sh check` reports `off (no tracker: in .logistics.yml)` for it
  (today a missing `tracker` dies with `missing …`), and every other
  `tracker.sh` command (`read-issue`, `create-issue`, `set-status`, …)
  treats a missing `tracker:` as off, with no error.
- `docs/install.md` (and the README where it lists the file) says where the
  section goes and links the matrix.

## Out of scope
- A user-level or per-developer config (`~/.config/logistics/…`, a
  gitignored `.logistics.local.yml`, an env var): follow-up issue #93.
- Per-size keys (`feat.4.large: soft`).
- Softening any reason other than the size reasons.
- Setting the ship phases, or `/tiny` (it has no gates).

## Alternatives rejected
- Doing nothing (answer at the gate each time) — the user restates it at
  every gate of every run, and the coordinator does not carry it across
  phases or a resume.
- An env var in Claude Code settings (`LOGISTICS_GATES=…`), which would get
  user/project/local layering for free — the user wants the config file to
  stay the single source of truth.
- A user-level file, or a gitignored `.logistics.local.yml` over the shared
  file — deferred to a follow-up issue; shared and repo-level for now. (A
  local file would also be invisible to the worktree branched from
  `origin/<default>`.)
- A separate file (`.specify/gates.yml` or similar) — one config file.
- Per-size keys — `auto` already varies by size; no need was stated for
  "hard on medium but not small".
- Letting `soft` remove `/fix` 1's judgement rows (confidence,
  remediations, needs reproduction) — those are where a wrong assumption
  ships a wrong fix; config moves the size default, nothing else.
- A fourth value `none` (no gate line at all) — `soft` already goes on with
  one line; the only "no gate" today (`feat` 3 on small/medium) stays as
  `auto`.
- Defining `soft` at the review gates as something new — a soft review
  gate already applies the `apply` recommendations and stops on
  `rec: user`.
- Re-reading the file on resume — a resume continues the same run, with
  the gates it started with.

## Acceptance
- With no `gates:` section (and with every key `auto`), every `tests/step`
  case gives today's output unchanged.
- `feat.6: soft` on a large run: no stop between stories when checks pass
  and no other row applies; a design problem or a failing check after the
  retry still stops.
- `feat.3: hard` on a small run: a hard gate after the plan with reason
  `gates: hard`, then the design review as today.
- `soft` at a large gate with a safety reason (e.g. `feat.5` with a HIGH
  finding, `feat.7` with an `S` finding, `fix.4` with security risk area)
  is still hard, with that reason and without `large`.
- `fix.1: soft` on a medium bug that otherwise meets every soft condition
  passes soft; the same bug with `Confidence: medium` stops.
- `soft` at `feat.2`, `fix.2`, `fix.3` gives the same output as `auto`.
- `soft` on a large run gives the same verdict and reasons as the same
  fixture on medium, for `feat` 3, 4, 5 and 7 and `fix` 4 (only the size
  column and the `; gates: soft` mark differ).
- `feat.3: hard` on a small run: the gate's `approved` and `changed`
  answers, and a resume at that gate, behave as at the large gate 3.
- A softened gate's Log line carries `; gates: soft`.
- A resume after `.logistics.yml`'s `gates:` changed mid-run uses the gates
  logged at setup.
- Each malformed `gates:` case stops setup with its line number, covered in
  `tests/tracker` (or wherever the parser's tests live).
- A `.logistics.yml` with only `gates:`: board tracking off in `/brief`,
  `/feat`, `/fix`, `/tiny` and at `/fix` 1's `issue to create` row; with
  `tracker:` and `gates:`, both work.
- A run started before this feature (no gates in its state file) resumes as
  `auto`.
- `docs/workflow.md` has the matrix and the dict; `docs/install.md` says
  where it goes; `mise run lint` and the offline tests pass.

## Constraints / decisions already made
- `step.sh`, `preflight.sh` and `state.sh`: Bash 3.2, no jq, no Python
  (`.claude/CLAUDE.md`). The `gates:` parser keeps `tracker.sh`'s strict
  style: exactly the documented shape, comments and quoted values fine,
  anything else refused with a line number.
- `/feat` and `/fix` stay thin: reading the config and applying it go into
  `preflight.sh`, `state.sh` and `step.sh`, not into the coordinators.
- The rules both skills share stay in `harness.md` with no `/feat`-only
  words (`mise run lint` greps them).
- A change to the gate rules updates `docs/diagrams/gates.d2` if the
  diagram shows the size rule, re-rendered with `mise run diagrams`.
- `measure.py`'s counts read gate lines; a new hard `feat` 3 line on small
  is a real gate and counts as one.
- `/fix` 1's `issue to create` row and every "board tracking, i.e.
  `.logistics.yml` exists" sentence change to "has a `tracker:` key". The
  sites today: `preflight.sh:360` and `:825`, `step.sh:3689`,
  `tracker.sh:597–603`, `.apm/skills/brief/SKILL.md:38`,
  `.apm/skills/tiny/SKILL.md:65` and `:88`,
  `.apm/skills/feat/references/harness.md:342`, `docs/usage.md:72`,
  `docs/workflow.md:540`, and the fixtures that write a `.logistics.yml` in
  `tests/preflight/run.sh` (around 626–638, 1101–1106), `tests/step/run.sh`
  (around 699) and `tests/tracker`. The brief review said some of those
  fixtures use keys `tracker.sh` would refuse (`board:`); check them, since
  they are the only "on" paths tested.
- One parser for the file: the `gates:` section is parsed in `tracker.sh`
  next to `tracker:`. `preflight.sh` takes its result at setup and passes
  it to `state.sh init`, which writes a `Gates:` field in the state file
  (e.g. `Gates: feat.3=hard feat.6=soft`, `auto` keys left out, `none` when
  nothing is set); `step.sh` reads only that field. A state file without
  `Gates:` is read as all `auto`.
- The new feature's contract (its spec's gate rules, amending
  `specs/013-step-command/contracts/gates.md`) is the source of the gate
  rules; the `docs/workflow.md` matrix cites it, and a change to a gate row
  updates both, with a `tests/step` case per matrix row that changes
  behaviour.
