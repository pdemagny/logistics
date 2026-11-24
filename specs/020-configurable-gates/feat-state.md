# /feat state: Configure each gate of /feat and /fix as soft, hard or auto in .logistics.yml

- Branch: configurable-gates Worktree: /home/pierre/Projects/logistics/.claude/worktrees/configurable-gates
- Size: medium
- Agents: specifier a47f08bf8c50bdf0a, planner a09fba90d08bdacea, tasker a3dcd1b9ffce274f1 (for SendMessage)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, never co-author (the user is the only author), stage only task files. In the worktree call /usr/bin/git directly, one plain command per call. zsh: quote variables; use command rm -f, command cp -f, command mv -f. sizes.json is the source: run mise run diagrams, never edit sizes.tsv or sizes-start/sizes-end blocks by hand. An agent report-format change updates step.sh, tests/step and the skills together; /feat and /fix stay thin. Shipped scripts: Bash 3.2, no jq, no Python, shellcheck clean. Run mise run lint, mise run test:apm and the relevant mise run test:* tasks before committing. CHANGELOG is generated; Closes #N only in the PR body. New docs pages need title and weight front matter.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #34

## Brief

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

## Log

- [x] 0 Setup — brief configurable-gates (medium, issue #34), no Spec Kit hooks, board users/pdemagny/projects/2: #34 set to In progress
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 Soften a gate that size makes hard (P1); US2 Force a gate to stop (P1); US3 Gates fixed for the run, safe to resume (P1); US4 A malformed gates section is refused (P2); US5 Board tracking follows the tracker key (P2); US6 The matrix is documented (P3)
    - Requirements: 22; soft removes only size reasons; hard adds gates: hard and feat.3 hard on small/medium is the large gate 3; Gates: field in state file read once at setup; strict parser with line numbers; board tracking keyed on tracker:; docs matrix and amended contract
    - Spec assumptions: 1. The brief's gate matrix is the intended behaviour at each gate (recommended: keep as written); 2. feat.3 hard on large keeps large as a reason beside gates: hard (recommended: keep as written); 3. fix.1 soft removes proposed size on every size (recommended: keep as written); 4. The setup gates line appears only when a gate is not auto (recommended: keep as written); 5. User-level config, per-size keys, other reasons, none value, ship and /tiny out of scope (recommended: keep as written)
    - Unchecked checklist items: none
- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] move — 27f277f → 39d9da3 (before 4 Design review): checks pass; not verified: none
- [x] 4 Design review [hard] — D1, D3, D6, D7, D8 need you
    - D1 plan.md: Design, "Applying" / contracts/config.md: `state.sh` — The new `- Gates:` header becomes the only source `step.sh` trusts for whether a gate stops, but the state file sits in the worktree where any phase agent (the implementer especially, or an agent steered by issue or brief text) can edit it, and `state.sh`'s `manifest` leaves the state file (`SX`) out of the snapshot on purpose, so an edit such as `- Gates: feat.7=soft` or removing `feat.3=hard` would soften later gates with no `files changed outside the reports` reason. `Size:` has the same exposure today, but `Gates:` is a more direct switch: one edit drops every remaining `large` stop. `state.sh set` refusing `Gates` only blocks the scripted path.
    - D2 contracts/config.md: `preflight.sh` / contracts/prompts.md: the coordinators' shown line — On a repo you didn't write, the repo's committed `.logistics.yml` can soften large-run gates (`feat.4`–`feat.7`, `fix.1`, `fix.4`) for whoever runs `/feat` or `/fix` there. The plan shows the effective gates in one setup line and adds a docs sentence, but the line as specified (`gates: <tokens>`) doesn't say where the values came from. install.md's advice for the tracker line ("check that line before going on") depends on the user seeing that the repo chose them.
    - D3 plan.md: Design, Applying (`test_rows`' soft rows with an answer flag) — `hard` at `fix` 2 and `fix` 3 needs an answer flag so `apply_answer` does not stop twice, and `soft` there is a no-op. That is extra state machinery in `test_rows` for a case the brief matrix lists but no story needs. Keep those two gates settable to `soft` or `auto` only, or make `hard` there a plain stop with the existing answer path. Refusing `hard` at `fix.2` and `fix.3` removes a settable cell, which changes FR-001 and FR-006. — rec: user (drops a settable cell of the brief's matrix)
    - D4 spec.md: FR-019, FR-020; plan.md: Contract and docs — The matrix is kept in three places: the brief, `contracts/gates.md` and `docs/workflow.md`. FR-020 makes every gate-row change a double edit. The docs copy can drift and costs lint or review attention. Let `docs/workflow.md` carry the matrix, and make `contracts/gates.md` hold only the deltas to 013 with a pointer to it. Alternatively keep both and add a `tests/step` check that the gate rows agree. — rec: skip (the user asked for both the matrix and the amended contract; the duplication is deliberate)
    - D5 plan.md: Testing; spec.md: US1 scenario 4, 7 — The plan asks for a `tests/step` case per matrix row that changes behaviour, over 16 case blocks, plus parallel soft-on-large vs medium fixtures for five gates. Several rows (`feat.2`, `fix.2`, `fix.3` soft) must equal `auto`. One shared fixture per gate run under two configs, with the output compared, covers SC-003 and FR-009 without a golden file for each. State in the plan that SC-003 and FR-009 are asserted by comparing the outputs of two runs of one fixture, not by new goldens. That keeps the ~38-task estimate from growing. — rec: apply
    - D6 spec.md: US2 acceptance scenario 4; contracts/gates.md: `### 4 Design review` row "small/medium rows" — `feat.3: hard` on small or medium asks the user twice about the same plan reasons — rec: user (changes an acceptance scenario of the spec)
    - D7 spec.md: FR-014; research.md: R1 — FR-014 says the setup script passes the result to the state initialiser; the plan and R1 do the opposite — rec: user (rewords a requirement)
    - D8 spec.md: US1 acceptance scenario 1, FR-008 — US1 scenario 1 and FR-008 promise a `; gates: soft` Log line "when a story finishes" at `feat.6: soft` on large, but data-model.md and R9 write that mark only on the last story's line; earlier stories log no gate line, as on small today — rec: user (changes an acceptance scenario)
    - D9 research.md: R10; contracts/gates.md: `/fix` `### 3 Test`; plan.md: Design "Applying" — `fix.3: hard` is the one gate whose mechanism is left to the implementer ("an answer flag so `apply_answer` does not stop again") — rec: apply
    - D10 contracts/prompts.md: Docs; contracts/gates.md header — Docs and the 013 contract that call gate 3 large-only are not on the update list — rec: apply
    - D11 contracts/prompts.md: harness.md "Board moves"; FR-017 — harness.md's board sentence needs a fact the coordinator cannot check — rec: apply
    - D12 spec.md: FR-010, US3; plan.md: Summary; research.md: R1 — Where the gates are read from is stated three ways — rec: apply
    - D13 contracts/config.md: `.logistics.yml` grammar, `state.sh` `Gates=` — Two small gaps in the new file contracts — rec: apply
    - D14 spec.md: Edge Cases, Assumptions 2 — Spec edge case 131 and assumption 2 word the `feat.3: hard` on large result as "beside `large` or in its place per the Log line form" — rec: apply
    - answer: back to 2 (user: "that'd be great to be able to configure gates by phase AND size, do we need to brief again? back to 2 with per-size keys")
- [x] 2 Specify [hard] — size remark
    - Stories: US1 Soften a gate that size makes hard (P1); US2 Force a gate to stop (P1); US3 Gates fixed for the run, safe to resume (P1); US4 A malformed gates section is refused (P2); US5 Board tracking follows the tracker key (P2); US6 The matrix is documented (P3)
    - Requirements: 23; FR-001 plain value or one-line size mapping per phase; FR-007 feat.3 hard form and gate 4 skips plan rows; FR-010 Gates field tokens feat.3=hard feat.6.large=soft, read from origin default branch; FR-013 malformed cases incl. size keys; FR-014 setup prints, coordinator passes Gates=, step reads field; FR-023 size cell applies to that size only
    - Spec assumptions: 1. Brief's gate matrix is the intended behaviour (recommended: keep as written); 2. feat.3 hard on large reads `large; gates: hard`, on small/medium `gates: hard` alone (recommended: keep as written); 3. fix.1 soft removes proposed size on every size (recommended: keep as written); 4. setup gates line only when a cell is not auto (recommended: keep as written); 5. user-level config, other reasons, none value, ship and /tiny out of scope; per-size in scope (recommended: keep as written); 6. D6: gate 4 skips plan rows when gate 3 stopped, as on large (recommended: keep as written); 7. accepted forms: plain value and one-line flow mapping, no nested block (recommended: keep as written); 8. D12: gates read from .logistics.yml as committed on origin default branch (recommended: keep as written)
    - Unchecked checklist items: none
    - answer: approved (user: "ok")
- [x] 3 Plan — merged with 4; assumptions needing you: 1; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [hard] — D2 need you; assumption 1 needs you
    - D1 contracts/config.md: Errors (rows "a pair that is not `<key>: <value>`" and "a size key other than `small`, `medium`, `large`"); research.md: R4 — The new size-mapping error `unknown size <k> in gates.<skill>.<n>` echoes a key taken from inside `{ … }`, but no character set is stated for that key: RE_KEY (`[a-z0-9]+`) constrains only line keys, and the pair split on `,` leaves `<k>` as whatever precedes the `:`. A repo's committed `.logistics.yml` (including one in a repo you didn't write) could then put free text, spaces and words included, into preflight's `stop: origin/<default>:…` line, which goes into the coordinator's context. That breaks the contract's own promise ("No value from the file is echoed but the key names the grammar already allows") and gives repo text a way into the prompt.
    - D2 spec.md: FR-004, US1 scenario 4, SC-003; research.md: R8 (4th table row) — FR-004, US1 scenario 4 and SC-003 say `soft` at a large gate evaluates exactly the rows small and medium evaluate with an identical verdict, but research R8's table (and contracts/gates.md `### 4 Design review`) drops `plan3_rows` at gate 4 whenever gate 3 stopped, which is the default on every large run; so `feat.4.large=soft` under the default `feat.3` gives a different verdict than the same fixture on medium (no `assumption <k> needs you`, `constitution`, `blocker`, `checklist item`). An implementer who reads only the spec evaluates those rows and asks the user twice; SC-003 holds only for a fixture whose gate 3 was merged, which the spec never says — rec: user (rewords a requirement and an acceptance scenario of the spec)
    - D3 contracts/prompts.md: harness.md "Board moves", `/feat` and `/fix` SKILL.md bullets; .apm/skills/feat/SKILL.md: Setup step 4; .apm/skills/fix/SKILL.md: Board-check step and Resume Board bullet — The resume path for board tracking is left undefined: harness.md's new sentence says board moves happen "only when setup's `board:` line (on resume, `check`'s line) is not `off`", but setup's `board:` value is the mapped `off` while on resume the coordinator holds `check`'s raw line `tracker: off (no tracker: in .logistics.yml)` (preflight resume prints no `board:` line, and today the coordinator tests file existence, not the line). The SKILL.md resume steps (`/feat` Setup step 4 "On resume, run `check` here: exit ≠ 0 → stop"; `/fix` "Board-check step" line 74 and Resume "Board" bullet line 217) only test the exit code, and `contracts/prompts.md` edits none of them, so a resumed run on a gates-only repo would try `set-status` and log `[!]` lines — rec: apply
    - D4 contracts/prompts.md: Docs; plan.md: Design "Contract and docs" — contracts/prompts.md lists only some of the docs sentences that tie a gate to a size, and the plan's general rule ("every size rule stated as absolute says by default") has no list to check against; others exist: workflow.md line 97 ("3 on large"), 330 ("large stops here"), 364 ("Large: always hard"), 412 ("Large: a gate after each story"), 468 ("Large always stops"), the `/fix` code-review bullet at 775 ("`Size: large` is hard"), README.md line 83 ("A large feature also stops after...") and usage.md line 301 ("gates at 3, 4, 5 and after each story"). Left as is, the docs state a rule the repository can now change — rec: apply
    - D5 contracts/prompts.md: `.apm/skills/feat/SKILL.md`, `.apm/skills/fix/SKILL.md`, harness.md "Gates in force" — The coordinator prose that renders a hard gate keys on the literal `large`, and the harness paragraph's "show the gate as the skill shows a size-made hard gate" does not say which lines that covers: `/feat` SKILL.md lines 249-254 and 309-311 ("on large too, even when none is `user`", title "Phase 4: Design review" vs "Phase 3–4"), line 285 ("for large, the per-story gate shows that story's list") and `/fix` SKILL.md line 386 (the bullet "`large`, `<ids> need you`, `S<n> security`: list every finding"). With `feat.7=hard` on a small run the only reason is `gates: hard`; an implementer would have to guess whether to list every finding — rec: apply
    - D6 plan.md: Constitution Check III, Design "phase2-mode"; contracts/config.md: `state.sh` — plan.md's Constitution III row says the gate-3 rule is "in `step.sh` only (`phase2-mode` takes its gate from it)", but `state.sh phase2-mode` keeps today's Size to gate rule as the default when no gate is passed, and `tests/step/run.sh` line 329 (`log-readers-agree`) and `queries` (line 1991) call it that way as the oracle against `step.sh`'s `phase2-mode:` line, so a second copy of the rule lives on and the oracle disagrees with `step.sh` for any state file with `feat.3` hard on small or soft on large — rec: apply
    - D7 spec.md: FR-007 — The spec uses "plan rows" and "gate 3 stopped" (FR-007, US2 scenario 4, the edge case "gate 3 stopped under") without defining them; the definitions sit only in contracts/gates.md `### 4 Design review` and research R8, so a reader of the spec alone cannot tell which rows gate 4 skips — rec: apply
    - answer: approved (user: "ok")
    - answer: fix D2 (user: "ok")
    - outcome: picked D1, D2, D3, D4, D5, D6, D7
- [x] 3 Plan — amended (D1, D2, D3, D4, D5, D6, D7); assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [soft] — 59 tasks; story.sh: match; analyze ran
- [x] 6 US1 — not verified: none
    - wrote: specs/020-configurable-gates/tasks.md
    - wrote: tests/tracker/fixtures/gates.yml
    - wrote: tests/state/fixtures/feat-gates.md
    - wrote: tests/state/fixtures/feat-gates-large.md
    - wrote: tests/step/expected/gates-feat3-soft-large.out
    - wrote: tests/step/expected/gates-feat3-soft-large.log
    - wrote: tests/step/expected/gates-feat4-after-soft-3.out
    - wrote: tests/step/expected/gates-feat4-after-soft-3.log
    - wrote: tests/step/expected/gates-feat6-soft-large-last.out
    - wrote: tests/step/expected/gates-feat6-soft-large-last.log
    - wrote: tests/step/expected/gates-fix1-soft-medium.out
    - wrote: tests/step/expected/gates-fix1-soft-medium.log
    - wrote: tests/step/expected/gates-fix1-soft-medium.in
- [x] 6 US2 — not verified: none
    - wrote: specs/020-configurable-gates/tasks.md
    - wrote: tests/step/expected/gates-feat2-hard-approved.log
    - wrote: tests/step/expected/gates-feat2-hard-approved.out
    - wrote: tests/step/expected/gates-feat2-hard.log
    - wrote: tests/step/expected/gates-feat2-hard.out
    - wrote: tests/step/expected/gates-feat3-hard-amended.log
    - wrote: tests/step/expected/gates-feat3-hard-amended.out
    - wrote: tests/step/expected/gates-feat3-hard-approved.log
    - wrote: tests/step/expected/gates-feat3-hard-approved.out
    - wrote: tests/step/expected/gates-feat3-hard-changed.log
    - wrote: tests/step/expected/gates-feat3-hard-changed.out
    - wrote: tests/step/expected/gates-feat3-hard-large.log
    - wrote: tests/step/expected/gates-feat3-hard-large.out
    - wrote: tests/step/expected/gates-feat3-hard-small.log
    - wrote: tests/step/expected/gates-feat3-hard-small.out
    - wrote: tests/step/expected/gates-feat4-after-hard-3-amended.log
    - wrote: tests/step/expected/gates-feat4-after-hard-3-amended.out
    - wrote: tests/step/expected/gates-feat4-hard-small.log
    - wrote: tests/step/expected/gates-feat4-hard-small.out
    - wrote: tests/step/expected/gates-feat5-hard-small.log
    - wrote: tests/step/expected/gates-feat5-hard-small.out
    - wrote: tests/step/expected/gates-feat6-hard-us1-approved.in
    - wrote: tests/step/expected/gates-feat6-hard-us1-approved.log
    - wrote: tests/step/expected/gates-feat6-hard-us1-approved.out
    - wrote: tests/step/expected/gates-feat6-hard-us1.log
    - wrote: tests/step/expected/gates-feat6-hard-us1.out
    - wrote: tests/step/expected/gates-feat6-hard-us2-approved.log
    - wrote: tests/step/expected/gates-feat6-hard-us2-approved.out
    - wrote: tests/step/expected/gates-feat6-hard-us2.log
    - wrote: tests/step/expected/gates-feat6-hard-us2.out
    - wrote: tests/step/expected/gates-feat7-hard-medium.log
    - wrote: tests/step/expected/gates-feat7-hard-medium.out
    - wrote: tests/step/expected/gates-fix1-hard-small.log
    - wrote: tests/step/expected/gates-fix1-hard-small.out
    - wrote: tests/step/expected/gates-fix2-hard-approved.in
    - wrote: tests/step/expected/gates-fix2-hard-approved.log
    - wrote: tests/step/expected/gates-fix2-hard-approved.out
    - wrote: tests/step/expected/gates-fix2-hard.log
    - wrote: tests/step/expected/gates-fix2-hard.out
    - wrote: tests/step/expected/gates-fix3-hard-failed-approved.log
    - wrote: tests/step/expected/gates-fix3-hard-failed-approved.out
    - wrote: tests/step/expected/gates-fix3-hard-failed.log
    - wrote: tests/step/expected/gates-fix3-hard-failed.out
    - wrote: tests/step/expected/gates-fix3-hard-partial.log
    - wrote: tests/step/expected/gates-fix3-hard-partial.out
    - wrote: tests/step/expected/gates-fix3-hard-unaccounted-approved.log
    - wrote: tests/step/expected/gates-fix3-hard-unaccounted-approved.out
    - wrote: tests/step/expected/gates-fix3-hard-unaccounted.log
    - wrote: tests/step/expected/gates-fix3-hard-unaccounted.out
    - wrote: tests/step/expected/gates-fix3-hard-verified-approved.log
    - wrote: tests/step/expected/gates-fix3-hard-verified-approved.out
    - wrote: tests/step/expected/gates-fix3-hard-verified.log
    - wrote: tests/step/expected/gates-fix3-hard-verified.out
    - wrote: tests/step/expected/gates-fix4-hard-small.log
    - wrote: tests/step/expected/gates-fix4-hard-small.out
- [x] 6 US3 — not verified: none
    - wrote: specs/020-configurable-gates/tasks.md
- [x] 6 US4 — not verified: none
    - wrote: tests/preflight/expected/gates-malformed.out
    - wrote: specs/020-configurable-gates/tasks.md
- [x] 6 US5 — not verified: none
    - wrote: specs/020-configurable-gates/tasks.md
- [x] 6 US6 — not verified: none
    - wrote: specs/020-configurable-gates/tasks.md
- [x] 6 Implement [soft] — tasks done: 59 (0 not verified); checks pass
- [x] move — 39d9da3 → db0d8ec (before 7 Code review): checks pass; not verified: none
- [x] 7 Code review [hard] — B1 need you
    - B1 docs/workflow.md:284 — The matrix's contract link and three code comments name `specs/020-configurable-gates/`, a path phase 8 renames to `specs/NNN-configurable-gates/`; ship.sh's number_dir rewrites the old path only inside the artifact dir and .specify/feature.json (ship.sh:740-751, list_outside_refs runs only on renumber), so the published docs link 404s and the comments go stale — rec: user (it needs either a post-numbering edit or a ship.sh change outside this feature's scope)
    - B2 .apm/skills/feat/scripts/step.sh:4219-4221 — After gate 3 is decided, G3 comes from the current Size (gate3_stops), not from the Log: with a size-specific feat.3 cell (e.g. `feat.3.small=hard`) and a size increase answered at gate 4, gate 3 stopped and already logged "spec assumptions: kept as recommended", but the gate 4 answer then gets G3=4, phase2-mode reads the on-disk Log where gate 4 is not yet passed, returns `soft 4 open`, and the sub-line is logged a second time (resume's phase2-mode is wrong the same way) — rec: apply
    - B3 .apm/skills/brief/SKILL.md:38 — missing: /brief and /tiny still say board tracking runs "only when `.logistics.yml` exists" (the added sentence after it handles the `tracker: off` line, so behaviour is right, but the statement itself was to change) — rec: apply
    - C1 .apm/skills/feat/scripts/step.sh:360-382 — yagni: g3_stop's fallback for a Log written before tagged gates (Size large read as stopped, latest_gate lookup) — rec: skip (resume of in-flight runs is a stated compat need; the Gates field also defaults to none for them)
    - R1 .apm/skills/feat/scripts/step.sh:498-512 (diff lines 498-512) — Doc comment of size_gate sits above the SOFTENED and TR_GATES globals, so it no longer describes the next line; TR_GATES (a /fix 3 flag) is declared among the size_gate helpers — rec: apply
    - R2 .apm/skills/feat/scripts/step.sh:review_gate, dec_feat_3, dec_feat_5, dec_feat_6 — The two-line `h=0; if [[ $SC == large ]]; then h=1; fi` after `size_col` is repeated in review_gate, dec_feat_3, dec_feat_5 and dec_feat_6, always to feed size_gate/in_force the "size reason holds" argument — rec: skip (callers also read $SC afterwards; a judgement call on churn)
    - R3 .apm/skills/feat/scripts/step.sh:3101-3103, 4210-4211, 4219-4220, 4519-4520 (diff lines) — `gate3_stops || true` followed by `st phase2-mode "$SF" "$G3"` is repeated at four sites (review_gate, apply_answer feat:3 and feat:4, do_resume); the `|| true` exists only to set G3 as a side effect — rec: apply
    - R4 .apm/skills/feat/scripts/step.sh:3949-3961 (diff lines 872-885) — test_rows tests `[[ $1 == first && $2 == no ]]` twice in a row (first with TR_GATES, then alone) — rec: apply
    - R5 .apm/skills/feat/scripts/step.sh:504-512 and its call sites — size_gate's trailing positional arguments (`size_gate 6 "$h" "$u: large" '' "$u: gates: hard"`, `size_gate 2 0 -`, `size_gate 1 0 - small`) need the reader to count arguments and know that `''` means the current size and `-` means no reason — rec: apply
    - R6 .apm/skills/feat/scripts/tracker.sh:1130-1133 (diff lines) — In parse_config, `4:feat | 4:fix)` runs two cfg_err calls in sequence (`[ "$top" != gates ] || cfg_err ... "unknown key"` then an unconditional `cfg_err ... "outside gates"`) — rec: apply
    - [std]1 .apm/skills/feat/references/harness.md:237-240 — hard: harness.md gained /feat-only wording (`<story>: gates: hard`, "a story's list"); stories exist only in /feat's phase 6 — rec: apply
    - [std]2 .apm/skills/feat/scripts/step.sh:3486-3487 — judgement: the same two-line `h=0; if [[ $SC == large ]]; then h=1; fi` precedes size_gate at five call sites — rec: skip (two lines each, and the explicit argument keeps /fix 1's call uniform)
    - answer: approved (user: "1 fix 2 ok")
    - answer: fix B1 (user: "1 fix 2 ok")
    - outcome: picked B1, B2, B3, R1, R3, R4, R5, R6, [std]1; rejected C1 (as recommended), R2 (as recommended), [std]2 (as recommended)
- [x] 7 review fixes — B1 → applied (user's second option: ship.sh number_dir rewrites the PR's own files, so docs/workflow.md, step.sh and tests/step/run.sh get specs/NNN-configurable-gates/ at ship); B2 → applied; B3 → applied; [std]1 → applied; R1 → applied; R3 → applied; R4 → applied; R5 → applied; R6 → applied; C1, R2, [std]2 → skipped (rec skip); performance: none; checks: mise run lint → pass, mise run test:apm → pass, mise run test:step → pass, mise run test:ship → pass, mise run test:tracker → pass, mise run test:spec-number → pass, mise run test:story → pass, mise run test:state → pass, mise run test:sizes → pass, mise run test:preflight → pass, mise run test:trail → pass, mise run test:measure → pass, mise run test:secret-scan → pass; not verified: none
- [x] 8 Ship
