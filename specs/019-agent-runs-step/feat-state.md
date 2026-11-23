# /feat state: Agents run step.sh last so the coordinator spawns straight from the hand-back

- Branch: agent-runs-step Worktree: /home/pierre/Projects/logistics/.claude/worktrees/brief-agent-runs-step
- Size: medium
- Agents: specifier af534610d508f3604, planner af2fba9f475aa83b0, tasker a69b65b1b3c227151 (for SendMessage)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, no Co-authored-by trailer; git as /usr/bin/git, one plain command per call; rm/cp/mv are -i aliases (use command rm -f); zsh, quote variables; mise run lint and mise run test:apm before committing, plus the offline tests (test:step, test:ship, test:preflight, test:trail, ...); step.sh and other scripts: Bash 3.2, no jq, no Python, shellcheck clean, tests in tests/step; an agent report format change goes with step.sh, tests/step and the skills together; /feat and /fix stay thin; keep /feat-only words out of harness.md, rebase.md, move.md; sizes.json is the source (mise run diagrams), never edit between sizes-start/sizes-end markers, CHANGELOG or versions by hand; never name private projects from outside this repo; PR body says Closes #88, never a commit message
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #88

## Brief

- Size: medium — ~40 tasks expected: step.sh (re-print, late agent ids, fail-closed check, continue by role) with its tests, six agent files, harness.md and both coordinators, docs
- Short name: agent-runs-step
- Kind: feat
- Issue: #88

## Why
Each coordinator model call re-reads its whole context (120–160k tokens
by mid-run). Since #28, `step.sh` prints what the next spawn needs (verdict,
report path, model, effort, inputs), so at every boundary the coordinator
must run `step.sh` and wait for its output before spawning: one call that
does nothing but carry the output across. In the 5 `/feat` runs since #28
that is 18–25 `step.sh` calls per run. Before #27 the boundary chore rode
in the same call as the spawn (766 of 985 spawn calls carried the
state-file edit), which is why #28's target (`/feat` ≤ 45 coordinator
calls) was missed. The people paying are every `/feat` and `/fix` user,
per run. Part of epic #31.

## Today
A sequential boundary costs the coordinator a `step.sh` call, then an
`Agent` call (plus the waiting and notification turns that #87 targets).
The agent that just reported has the state file path, its report path
and a small context (30–60k): it could run the boundary call itself at a
fraction of the cost, but nothing lets it, and `step.sh` needs words the
agent can't give (`agent=<id>`) and chores the coordinator chains before
the call (`S log` lines).

## Behaviour
- At every boundary closed by one agent, that agent runs the `boundary:`
  line of its own spawn block (`step.sh` with the skill and state file) as
  its last step, and its hand-back ends with `step.sh`'s output verbatim,
  in one fenced block. These boundaries move:
  - `/feat`: specifier, planner, tasker (first runs and amends continued
    with `SendMessage`), each implementer story and its check retries,
    the review-fixes implementer, the shipper;
  - `/fix`: assessor (assess and test), bug-mode implementer, review-fixes
    implementer, shipper.
- The coordinator reads the verdict and spawn blocks from the hand-back
  and acts on them as it does on its own `step.sh` output today: on
  `soft`, the one-line summary and the printed spawn(s) in the same turn,
  with no `step.sh` call of its own; on `hard:`, the gate; on `done:`, the
  final message; on `base: moved`, `read:`; on `step: error`, the error
  gate.
- On `reformat`, the agent itself writes the corrected report to the path
  the reformat spawn block names and runs that block's `boundary:` line,
  once; it hands back the second output, whatever it says (a second miss
  is today's hard gate). The agent acts on no other verdict: it never
  changes its work or its writes to turn a gate soft. An implementer's
  failed-checks verdict is handed back as is, and the coordinator makes
  the retry spawn `step.sh` printed, as today.
- **What the agent needs**: `step.sh` prints `step script:` and the
  `boundary:` words as keys inside the spawn block, so the coordinator's
  rule "every key of its spawn block goes into the prompt" carries them
  with no new rule. The six agent files get one fixed last-step section:
  run `boundary:`, act on `reformat` only, end with the verbatim block.
- **Slip fallback**: when a hand-back has no `step.sh` block, or the block
  doesn't parse (truncated, paraphrased), the coordinator runs that
  boundary's `boundary:` call itself, as today. `step.sh`, given the last
  boundary it decided with the same report, prints that decision again
  (verdict, spawns, `boundary:` and `answer call:` lines) without deciding
  or logging twice.
- **Fail closed**: `step.sh` accepts a boundary call only when its token
  is the open one (the next spawn the Log issued), or when it is the last
  decided boundary and its report path and sum match that Log entry (a
  re-print). Anything else, such as a stale token with a different report,
  is a `step: error`, not a decision.
- **Latest hand-back only**: the coordinator spawns only from the
  hand-back of the agent it is waiting on; a re-print always returns that
  boundary's logged decision, never an older one.
- **Agent ids arrive late**: an agent-run boundary takes no `agent=<id>`
  word; where `step.sh` prints a continuation today it prints
  `continue: <role>` (specifier, planner, tasker) until it has the id.
  The coordinator passes `agent=<role>:<id>` words, from the `Agent`
  results, on its next own `step.sh` call (an answer call at a hard gate,
  or a fan-out boundary), and `step.sh` records them in `Agents:` then.
  Every `/feat` continuation follows such a call. `/fix` makes no
  continuations (its `Agents:` is "every spawn is fresh"), so it needs no
  ids.
- **Chores ride on the coordinator's next own call**: log lines the
  coordinator chains before a boundary call today (`[!] brief left in
  place`, a preflight `flag:`) go with its next own `step.sh` call; other
  chores at a moved boundary (deleting the brief after phase 2, the review
  move before phase 7) are extra tool calls in the same response as the
  next spawn, so they cost no model call of their own. Both are
  coordinator chores today (`/feat` phase 2 step 2, phase 7): only their
  timing changes, not who does them.
- Reviewer fan-outs (`/feat` phases 4, 7 and 7e, `/fix` phase 4) and
  `rebase` keep the coordinator's `step.sh` call: their merge needs every
  report.

## Out of scope
- Foreground spawns and the waiting/notification turns: #87, built
  separately; this change does not depend on its answer.
- Fan-out boundaries run by an agent or a Workflow script (#56's
  candidate for medium and large fan-outs).
- Guarding against a malicious agent: the guard is against slips only.
  `model` and `effort` copied wrongly from a hand-back are not detectable
  by `step.sh` and are accepted as a risk, no likelier than a coordinator
  slip today.
- Changes to `measure.py`: its existing coordinator "chores" column is the
  measure.
- The implementer's own call count (#55).

## Alternatives rejected
- Wait for #87's "is it possible?" answer first — the gains stack and
  neither needs the other: with #87 a sequential boundary goes from 3
  coordinator calls to 1, without it from 3 to 2, and the `step.sh` turn
  costs a full context re-read either way.
- Sign `step.sh`'s output (a hash the coordinator checks) — checking it
  costs the coordinator the call this change removes; slips are the
  threat, and the slip fallback plus the fail-closed check cover them.
- Keep specifier, planner and tasker boundaries coordinator-run because
  they need `agent=<id>` — gives up about 4–6 calls per `/feat` run; the id
  can ride on the coordinator's next own call, since every continuation
  follows one.
- The agent acts on every verdict (fixes its `Wrote:` list, retries
  checks) — a refused write or a hard gate is the user's call; letting the
  agent chase a soft verdict widens what it does unseen. Only `reformat`,
  a format slip, is the agent's.
- Leave the shipper's boundary with the coordinator (it only prints
  `done: PR #N`) — one rule for every single-agent boundary keeps the
  agent files and coordinators free of exceptions.
- A lint check that the six agent files carry the last-step wording —
  `tests/step` and the code review cover the contract; a wording grep
  adds upkeep for little.
- Give the coordinator's chained log lines a new home in the agent's
  `step.sh` call (passed through the spawn prompt) — more prompt text and
  a new argument for a line that can wait for the coordinator's next own
  call.

## Acceptance
- `tests/step` cases: an agent-run boundary (soft, hard, `done:`) with no
  `agent=` word; the same boundary called again with the same report
  re-prints the decision and leaves the Log and header unchanged (the
  slip fallback: block missing, then the coordinator's own call); a
  boundary token or report path not issued by the Log, and a stale token
  with a different report, are a `step: error`; an implementer's
  failed-checks verdict from an agent-run boundary prints today's retry
  spawn;
  `agent=<role>:<id>` on an answer call and on a fan-out boundary fills
  `Agents:`, and a later continuation prints the id; `continue: <role>`
  before the id is known; a reformat run by the agent ends in the second
  boundary's decision, and a second miss in today's hard gate; a chained
  log line carried by the next own call lands in the Log.
- The six agent files (specifier, planner, tasker, implementer, shipper,
  bug assessor) end with running `boundary:` and the verbatim block, and
  say that only `reformat` is theirs to act on; reviewers are unchanged.
- `harness.md`, `/feat` and `/fix` say the coordinator spawns from the
  hand-back, the slip fallback, where ids and chores go; a walk-through of
  a small `/feat` run in `docs/workflow.md` shows one coordinator `step.sh`
  call per fan-out, gate and answer, and none per sequential spawn.
- `mise run lint` and every offline test pass; `step.sh` stays Bash 3.2,
  no jq, no Python; `harness.md` stays free of `/feat`-only words.
- After merge, not blocking the PR (the issue's "Done when"): on at least
  five runs of each skill, `mise run measure --compare-since <merge date>`
  shows coordinator `step.sh` calls only at fan-outs, gates and answers,
  and subagent calls per spawn rising by at most about 2.

## Constraints / decisions already made
- Agent prompts, their report format, `step.sh`, `tests/step` and both
  skills change together (CLAUDE.md). `/feat` and `/fix` stay thin: no
  new coordinator work besides reading the block.
- The shared rules live once in `harness.md` with named values; nothing
  `/feat`-only there (`mise run lint` greps it).
- `step.sh` stays the only decider and, with `state.sh`, the only writer
  of the state file; every line it prints is data. An agent running it
  changes who calls it, not what it decides.
- The report-file and `Wrote:` rules are unchanged: the agent writes its
  report before running `boundary:`.
- The agent gets what the call needs from its spawn block's keys: the
  step script path, the skill, the state file and the `boundary:` words
  as printed (tab-separated, each single-quoted). Agents keep Bash (their
  `disallowedTools` don't remove it).
- A change to `/feat`'s phases or gates updates `gates.d2` and `chain.d2`
  and their renders in `docs/img/`.

## Log

- [x] 0 Setup — brief specs/briefs/agent-runs-step.md, size medium, issue #88, no hooks gated; board building move ok (#88 In progress); reused the brief worktree, HEAD = origin/main 48b9de2
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 A sequential boundary costs the coordinator no step.sh call (P1); US2 A format slip is repaired by the agent, once (P1); US3 A missing or broken block never costs a decision (P1); US4 Agent ids arrive late, on the coordinator's next own call (P2); US5 Coordinator chores move to the coordinator's next own call (P2); US6 The documents tell the same story (P3)
    - Requirements: 21; FR-001 agent runs boundary: last with verbatim block; FR-009 fail-closed token check; FR-008 re-print without a second decision; FR-011/012 late agent ids and continue: <role>; FR-013/014 chores timing; FR-015 fan-outs and rebase keep the coordinator call
    - Spec assumptions: 1. Agents keep Bash and get the step script, skill, state file and boundary: words from the spawn block (recommended: keep as written); 2. Wrong model or effort copied from a hand-back is an accepted risk (recommended: keep as written); 3. The shipper boundary joins the rule with no exception (recommended: keep as written)
    - Unchecked checklist items: none
- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [hard] — D2, D3, D7, D12 need you
    - D1 contracts/prompts.md: Agents (Last step text) — A well-formed block the agent wrote itself, without running the call (from memory, from an earlier call, after a refused Bash), passes the coordinator's parse check (first line a verdict, last line `boundary:`/`answer call:`/`done:`). step.sh only catches it at the next boundary call, after the next agent has already run and written files; a made-up `soft` in place of a real `hard:` skips the user's gate until then. The Last step wording forbids nothing of the kind: it only covers "a command that printed nothing"
    - D2 spec.md: Assumptions (slips are the threat… the fail-closed check and the slip fallback cover them); data-model.md: Hand-back block — `done:` is the one verdict that no later step.sh call ever checks: a made-up `done: PR #N` from the shipper ends the run with the final message and no PR, and the fail-closed check never runs. The brief's claim that "the slip fallback plus the fail-closed check cover" slips does not hold for this verdict
    - D3 research.md: R8 (Alternatives considered: a lock); contracts/prompts.md: Chores — Two writers of the state file (the agent's step.sh call and any coordinator `S`/`T` call) are kept apart only by a prompt rule ("make no `S` or `T` call while an agent runs"). The brief's own threat model is coordinator slips. A slip here, such as a `size` or `S log` mid-spawn, or a `/feat resume` in a second session while a background agent still runs, is a lost update: the Log or `Current phase` loses the agent's decision while `last-step.md` says it was decided, and nothing reports it
    - D4 contracts/step-cli.md: The decision record (`record_write`); research.md: R2 — `record_write` runs its own reports/ checks (a dir, no symlink) and dies when reports/ is missing. It does not use state.sh's shared `reports_dir`/`reports_make` guard, which also refuses unsafe dir names and makes sure `reports/.gitignore` holds `*`. The record copies step.sh's whole output, `base: fetch-failed: <git message>` included, so the one guard that keeps it out of commits would be skipped. A run whose reports/ was never created turns setup or resume into a `step: error`
    - D5 plan.md: Design "Block keys"; contracts/step-cli.md: "Spawn block keys" (`bline` prints both) — Each agent-run spawn prints the same call twice (`boundary:` key in the block, then the `boundary:` call line after the blocks), and the agent then copies the whole output verbatim into its hand-back; the duplicate line is paid in agent output tokens and re-read by the coordinator on every later call — rec: skip (a line or two per spawn; the trailing line keeps the one parse rule and the slip fallback uniform; dropping it adds an exception to harness.md)
    - D6 spec.md: Acceptance last bullet — Post-merge measurement asks for at least five real runs of each skill (ten runs) before the issue's "Done when" can be judged; each full run is the expensive thing this feature is meant to cut — rec: skip (already non-blocking; no extra runs are required by the plan)
    - D7 data-model.md "Acceptance of a boundary call"; contracts/step-cli.md "Acceptance"; spec.md US3 — Slip fallback after an agent-run reformat ends in `step: error`, not a re-print: the agent's second call (new report path, e.g. `2-specify-2.md`) is the only one the record holds, but the coordinator only knows the `boundary:` words of the original spawn (first path), so the words differ and the issued line (token 3) is not token 2; the promise of US3/SC-002 (a slip falls back to today's behaviour) fails exactly where a format slip already happened — rec: user (widens which calls re-print, FR-009's rule)
    - D8 research.md R2; contracts/step-cli.md "The decision record" (`main` runs `commit`, then `render`, then `record_write`) — "A failure between the commit and the record leaves the previous record ... the retry decides as the first try" (R2) is not backed by the code: `commit` clears `CM_SET` at its end, so a `record_write` that dies after it never reaches `undo_sets`; `Current phase` and `Size` stay advanced, only the Log repeat check protects the retry, and a retry reads a state its own decision already changed — rec: apply
    - D9 contracts/step-cli.md "record_write"; data-model.md "Decision record" — `record_write` dies when `reports/` does not exist, but `reports/` is gitignored and untracked: a `resume` on another clone or machine, at a hard gate or on a `done` run that prints no spawn, never calls `report-path`, so the directory is absent and `resume` would fail. Creating it from step.sh would also skip the `.gitignore` `*` that `state.sh reports_make` writes, so the record could be committed by the shipper — rec: apply
    - D10 data-model.md "Hand-back block"; research.md R6; contracts/prompts.md harness "Slip fallback" — The block's tabs are load-bearing but the parse rule does not check them: the coordinator takes later call words (`answer call:`, a reviewer batch's `boundary:`, and the slip fallback's own words) from lines whose tabs the agent had to copy; a model that turns tabs into spaces still passes "last line starts `boundary:`", and the next call then fails as `step: usage` or splits a path with a space, with no recoverable source of the original words — rec: apply
    - D11 spec.md Key Entities "Log entry", FR-008, FR-009, US3 — The spec says the open boundary and the re-print come from "the Log" and defines Key Entity "Log entry" as "the state file's record of a decided boundary", but the plan keeps them in a separate runtime file, `reports/last-step.md`, which is not in the state file, not committed, and per worktree (R1 states it is the spec's "Log entry"). A reader of the spec alone would build Log sub-lines and change every `.log` golden — rec: apply
    - D12 contracts/step-cli.md "Agents"; research.md R5; spec.md FR-011/FR-012 — `drop_agent`, the `none` rendering of an empty Agents line and test 11 exist to stop a stale id from printing on a reformat spawn of boundary 2, 3 or 5, but an agent-run boundary's reformat is made by the agent, and a coordinator-made one continues the agent whose Agent result it just read; the only other lookup, the planner amend after gate 4, runs on a call that sets the id first — rec: user (changes FR-012's "a later continuation prints the id")
    - D13 contracts/prompts.md "docs"; plan.md Source code — plan.md and prompts.md update workflow.md's /feat Roles paragraph, but the `/fix` section has the same claims ("As in `/feat`, it holds the gates `step.sh` decides ... the first `step.sh` call", around line 654 and 666) and is not listed — rec: apply
    - answer: approved (user: "ok")
    - answer: fix D2 (user: "ok")
    - answer: fix D3 (user: "ok")
    - answer: fix D7 (user: "ok")
    - answer: fix D12 (user: "ok")
    - outcome: picked D1, D2, D3, D4, D7, D8, D9, D10, D11, D12, D13; rejected D5 (as recommended), D6 (as recommended)
- [x] 3 Plan — amended (D1, D2, D3, D4, D7, D8, D9, D10, D11, D12, D13); assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [hard] — analyze not run
    - answer: changed (user: "ok")
- [x] 5 Tasks [soft] — 44 tasks; story.sh: match; analyze ran
- [x] move — 48b9de2 → fa01276 (before 6 Implement): checks pass; not verified: none
    - resolved: specs/019-agent-runs-step/ — the auto-mode classifier refused the WIP commit (step 4); the run's work is untracked files only, which main's 3 commits don't touch, so the files stayed untracked, the pre-move ref was set and the rebase was a plain fast-forward with no conflict; the tree after the move is the same untracked specs/019-agent-runs-step/
- [x] 6 US1 — not verified: none
    - wrote: specs/019-agent-runs-step/tasks.md
    - wrote: tests/step/expected/agent-run-soft.out
    - wrote: tests/step/expected/agent-run-soft.log
    - wrote: tests/step/expected/agent-run-hard.out
    - wrote: tests/step/expected/agent-run-hard.log
    - wrote: tests/step/expected/agent-run-retry.out
    - wrote: tests/step/expected/agent-run-retry.log
    - wrote: tests/step/expected/agent-run-retry.in
    - wrote: tests/step/expected/agent-run-done.out
    - wrote: tests/step/expected/agent-run-done.log
- [x] 6 US1 [soft] — checks failed (retry 1 of 1): mise run test:step
    - override: hard — the failing test:step case (agent-run done: re-print) needs T023 in US3; a US1 retry cannot fix it
    - answer: approved (user: "ok")
- [x] 6 US1 — not verified: none
    - wrote: specs/019-agent-runs-step/tasks.md
    - wrote: tests/step/expected/agent-run-not-issued-token.out
    - wrote: tests/step/expected/agent-run-not-issued-token.log
    - wrote: tests/step/expected/agent-run-not-issued-path.out
    - wrote: tests/step/expected/agent-run-not-issued-path.log
    - wrote: tests/step/expected/agent-run-stale-edited.out
    - wrote: tests/step/expected/agent-run-stale-edited.log
    - wrote: tests/step/expected/agent-run-stale-older.out
    - wrote: tests/step/expected/agent-run-stale-older.log
    - wrote: tests/step/expected/agent-run-record-failed.out
    - wrote: tests/step/expected/agent-run-record-failed.log
    - wrote: tests/step/expected/agent-run-record-retried.out
    - wrote: tests/step/expected/agent-run-record-retried.log
    - wrote: tests/step/expected/agent-run-changed.out
    - wrote: tests/step/expected/agent-run-changed.log
    - wrote: tests/step/expected/agent-run-no-reports.out
    - wrote: tests/step/expected/agent-run-no-reports.log
- [x] 6 US3 — not verified: none
    - wrote: specs/019-agent-runs-step/tasks.md
- [x] 6 US2 — not verified: none
    - wrote: tests/step/expected/agent-run-reformat.out
    - wrote: tests/step/expected/agent-run-reformat.log
    - wrote: tests/step/expected/agent-run-reformat-soft.out
    - wrote: tests/step/expected/agent-run-reformat-soft.log
    - wrote: tests/step/expected/agent-run-reformat-hard.out
    - wrote: tests/step/expected/agent-run-reformat-hard.log
    - wrote: specs/019-agent-runs-step/tasks.md
- [x] 6 US4 — not verified: none
    - wrote: tests/step/fixtures/agents/design-reviewer/4a-apply.md
    - wrote: tests/step/fixtures/agents/design-reviewer/4b-zero.md
    - wrote: tests/step/fixtures/agents/design-reviewer/4c-matches.md
    - wrote: specs/019-agent-runs-step/tasks.md
- [x] 6 US5 — not verified: none
    - wrote: tests/step/expected/chores-log-answer.out
    - wrote: tests/step/expected/chores-log-answer.log
    - wrote: specs/019-agent-runs-step/tasks.md
- [x] 6 US6 — not verified: none
    - wrote: specs/019-agent-runs-step/tasks.md
- [x] 6 Implement [soft] — tasks done: 44 (0 not verified); checks pass
- [x] 7 Code review [hard] — C1 need you; criterion not met: US1-4 done: block: the coordinator's own call, the re-print gives the final message
    - B1 .apm/skills/feat/scripts/step.sh:405-458 — The `done:` check fails after the shipper renumbered the artifact dir: the shipper's block carries `state: <new path>`, and harness.md:88 makes that the state file of every later call, so the coordinator's check passes the new state file with the old report path from the spawn's `boundary:` words. main only runs `renumbered` when the state file argument is missing (step.sh:4323-4331), so RENUM stays empty, record_sums hashes the gone old path to "" (step.sh:405-420), the sums do not match the record, the done: output has no `boundary:` line, and accept dies `no boundary is open (soft)` (step.sh:448-458) instead of re-printing `done: PR #N`. Same for /fix's `fix:5`. — rec: apply
    - B2 docs/workflow.md:421-422 — wrong: docs/workflow.md still says the coordinator first moves the issue to In review and `step.sh` then prepares the review diff; now the last story's own call prepares the diff and prints the reviewers' spawns, and the review move is a tool call in the response that spawns them (as /feat's phase 7 now says) — rec: apply
    - B3 tests/step/run.sh:2446-2453 — missing: `continue: <role>` on a reformat spawn is only tested for the specifier; the planner and tasker go through the same `spawn_row ... "$ROLE"` line, but FR-020 asks for "those roles" — rec: skip (one shared line, role_of feeds all three; the specifier case covers it)
    - C1 .apm/agents/feat-bug-assessor.agent.md:173-187, .apm/agents/feat-implementer.agent.md, .apm/agents/feat-planner.agent.md, .apm/agents/feat-shipper.agent.md, .apm/agents/feat-specifier.agent.md, .apm/agents/feat-tasker.agent.md — reuse: the 17-line "Last step" paragraph is copied word for word into six agent files (only the first sentence's role differs); a change to it must be made six times — rec: user (cutting means a shared file the agents must read, a trade-off against self-contained prompts)
    - C2 .apm/skills/feat/scripts/step.sh:4215-4220 — shrink: do_boundary reuses `ok` as a scratch flag for the agent= check and resets it to 0 straight after — rec: skip (a line saved, clarity gain only)
    - R1 .apm/skills/feat/scripts/step.sh:449,451,462 — Name the error text: `w` holds the refusal message in accept() but is also the loop variable of the CALL_W loop just above — rec: apply
    - R2 .apm/skills/feat/scripts/step.sh:385,391,395 — Magic slice offsets in record_read (`${line:6}`, `${line:10}`) tie the code to the length of `call:<tab>`, `sums:<tab>`, `boundary:<tab>` — rec: apply
    - R3 .apm/skills/feat/scripts/step.sh:433,451 — The "join the call's words with tabs" loop is written twice (record_write, accept), and its result `c` is compared against the stored call — rec: apply
    - R4 .apm/skills/feat/scripts/step.sh:4215-4220 — do_boundary reuses `ok` for the agent= check, resets it to 0, then uses it for the token check — rec: apply
    - [std]1 .apm/skills/feat/scripts/step.sh:433,451 — judgement: the loop that joins a call's cleaned words with tabs is written twice, in record_write and accept — rec: apply
    - [std]2 .apm/skills/feat/scripts/step.sh:4214-4220 — judgement: do_boundary reuses its `ok` local (the token-allowed flag) as the "batch token" flag for the agent= check, then resets it with `ok=0` so the later token loop still works — rec: apply
    - [std]3 .apm/agents/feat-specifier.agent.md:72-86 — judgement: the "Last step" paragraph is copied word for word into six agent files — rec: skip (agent prompts are standalone, and the repo already repeats its Report file paragraph per agent; a reference read adds a tool call per spawn)
    - answer: approved (user: "ok")
    - answer: fix C1 (user: "ok")
    - outcome: picked B1, B2, C1, R1, R2, R3, R4, [std]1, [std]2; rejected B3 (as recommended), C2 (as recommended), [std]3 (as recommended)
- [x] 7 review fixes — B1 → applied; B2 → applied; R3/[std]1 → applied (one fix); R4/[std]2 → applied (one fix, local `batch`); C1 → applied (lint check, copies kept); R1 → applied; R2 → applied; performance: none; checks: mise run lint → pass, mise run test:step → pass, mise run test:state → pass, mise run test:ship → pass, mise run test:preflight → pass, mise run test:trail → pass, mise run test:tracker → pass, mise run test:spec-number → pass, mise run test:story → pass, mise run test:sizes → pass, mise run test:measure → pass, mise run test:secret-scan → pass, mise run test:apm → pass; not verified: none
- [x] 8 Ship
