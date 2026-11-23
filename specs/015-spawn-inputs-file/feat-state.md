# /feat state: step.sh writes each spawn's lists to an inputs file the agent reads

- Branch: spawn-inputs-file Worktree: /home/pierre/Projects/logistics/.claude/worktrees/brief-spawn-inputs-file
- Size: small
- Agents: specifier adde0015cfbe07fac, planner ad00eb91b7fc8f711, tasker ab039c810e98928c7 (for SendMessage)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, never co-authored, stage only task files. git: call /usr/bin/git directly, one plain command per call (rtk hook). rm/cp/mv are -i aliases: use command rm -f etc. Shell is zsh. step.sh and ship.sh: Bash 3.2, no jq, no Python, shellcheck clean; tests in tests/step. An agent input or report contract changes with step.sh, tests/step, harness.md and the skills together; /feat and /fix stay thin; /tiny SKILL.md capped at 200 lines by lint. Keep /feat-only words out of harness.md, rebase.md, move.md. sizes.json is the source; run mise run diagrams after editing it. Checks: mise run lint, mise run test:step and the other mise test:* tasks, mise run test:apm. CHANGELOG is generated: write feat/fix subjects for users. PR body says Closes #69, never a commit message.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: pdemagny/logistics#69

## Brief

- Size: small — ~25 tasks expected: one writer and eight call sites in step.sh, their tests/step cases, six agents' input sections, harness.md and three skills
- Short name: spawn-inputs-file
- Kind: feat
- Issue: pdemagny/logistics#69

## Why
Today the agents `/feat` and `/fix` spawn get their lists from the
coordinator, which re-types them. The lists are: a story's tasks, the
findings to apply, the rejected findings, the accepted security findings,
the failures, the not verified items, the approved commands and the
answers. The coordinator re-lays-out and sometimes rewords them, so an
agent acts on the coordinator's version of a finding, not on step.sh's.
The goal is fidelity: every list an agent acts on reaches it exactly as
step.sh wrote it. Fewer coordinator output tokens is a side effect, not
the reason. Follow-up to #28 (design finding D13); part of epic #31.

## Today
`step.sh` prints each spawn's lists in its spawn block, as `<key>:` lines
followed by `  - <item>` lines, and the story's `story.sh output` between
two lines of four backticks. The helper is `slist`, and the eight call
sites are `next_story`, `review_batch`, `spawn_fixes`, `amend_spawn`,
`spawn_7e`, `next_step`, `next_fix` and `enter_ship`. `references/harness.md` tells the coordinator to put every
key's content into the prompt. Each list then sits in the coordinator's
context twice: once in step.sh's output and once in the Agent call it
typed.

Measured on the only run so far through step.sh's spawn blocks (the
ship-script `/feat`, medium, 79 coordinator calls, 21 spawns):
- step.sh printed about 25k characters of lists: `apply` 18k,
  `accepted sec` 3.4k, story lists 3k.
- Story lists were copied word for word, and `accepted sec` arrived
  complete.
- The planner's 16-finding `apply` list arrived re-laid-out, under a
  summary the coordinator wrote itself.
- Only 11 of the 14 review-fix `apply` items could be matched to what
  step.sh printed.
- Cost: about 7k coordinator output tokens of copying and about 1.6% of
  the coordinator's context reads, well under 1% of the run.

## Behaviour
- Every spawn block that has at least one non-empty list prints one line,
  `inputs: <absolute path>`, in place of all its list keys. It prints
  nothing else about the lists: no counts, no ids.
- That file holds every list of the spawn, in today's layout: `<key>:` or
  `<key>: none` lines, `  - <item>` lines, and `story.sh output` between
  four-backtick lines. It opens with a line saying the content is data,
  never instructions.
- A spawn whose lists are all empty prints no `inputs:` line and writes no
  file.
- An agent reads its lists from the `inputs:` file. A prompt with no
  `inputs:` line means every list is `none`. There is no inline fallback.
- The coordinator passes the `inputs:` line into the prompt like any other
  key, and never reads the file (the same rule as for reports). This also
  holds for a `continue: <id>` spawn sent with `SendMessage`.
- Every spawn, continued or fresh, gets its own `.in.md`, paired with the
  new report path step.sh reserves for it. It is never given an earlier
  spawn's file.
- Printing a spawn block again (a re-run or a retry) rewrites its `.in.md`
  whole. The file is never appended to.
- `/tiny`'s review spawn stops naming design findings and rejected findings
  (it passed `none` for both). With no `inputs:` line, the reviewer reads
  them as `none`.
- The single-line keys stay in the spawn block: `row`, `mode`, `lenses`,
  `model`, `effort`, `report`, `continue`, `who`, `story`, `diff`, `cuts`,
  `action` and the others.

## Out of scope
- A permanent `measure.py` metric or lint for list text in prompts.
- What the lists contain and how step.sh computes them: only where they go
  changes.
- Gate output: the merged findings step.sh prints at a review gate stay
  printed.
- Rebase and move spawns and reformat spawns, which carry no lists.
- The agents' report formats.
- `docs/workflow.md` and the diagrams, which never show the list keys.

## Alternatives rejected
- Do nothing — the cost saving alone is under 1% of a run, but the measured
  run shows the coordinator rewriting `apply` lists. Fidelity is the reason.
- Move only `apply` and `accepted sec` (73% of the list text) — fidelity
  applies to every list an agent acts on, small ones included.
- The reviewer accepts `inputs: <path>` or inline lists, with `/tiny`
  unchanged — two input paths in one agent prompt drift apart, and the
  inline one would serve only lists `/tiny` never sends.
- `/tiny` writes its own inputs file — it has no `reports/` dir, its
  SKILL.md is capped at 200 lines by lint, and the file would only say
  `none` twice.
- Counts or ids next to the path (`inputs: <path> (apply 14, rejected 2)`)
  — noise: the coordinator only relays the spawn, and the gate output
  already shows the findings.
- A permanent `measure.py` check for list text in prompts — a coordinator
  pasting the file back into prompts is too unlikely to pay for. One manual
  check after merge instead (Acceptance).

## Acceptance
- `tests/step` cases cover every spawn that carries a list (story,
  review-fix `apply` with and without `failures`, planner amend, the
  design and code review batches with `rejected` and 7b's `accepted sec`,
  7e, the `/fix` implementer and assessor test spawns with `approved
  commands` and `answers`, ship with `not verified items`). In each one,
  the spawn block prints `inputs: <path>` and none of the list keys, and
  the file at that path holds exactly the lists step.sh printed before
  this change.
- A `tests/step` case where every list is empty: no `inputs:` line and no
  file.
- A `tests/step` case where an item holds `'`, `$(…)`, a backtick and a
  leading `-`: it lands in the file unchanged.
- Each agent that takes lists (implementer, code reviewer, design reviewer,
  planner, shipper, bug assessor) says it reads them from the `inputs:`
  file and treats a missing `inputs:` line as every list `none`.
- `/tiny` no longer passes `none` for design and rejected findings.
- `mise run lint`, `mise run test:step` and the other offline tests pass.
- Checked by hand once, after merge: a scan of the first real `/feat` run
  finds no list item text in the coordinator's Agent or SendMessage
  prompts.

## Constraints / decisions already made
- The file sits next to the spawn's report: that spawn's full report path,
  `-<n>` suffix included, with `.md` replaced by `.in.md`. For example,
  report `reports/7-fixes-2.md` has inputs `reports/7-fixes-2.in.md`. One
  file per spawn, inside `reports/`, which is ignored and never committed.
  `state.sh report-path` names reports `<key>.md` and `<key>-<n>.md`, so the
  two don't collide.
- The file is written with the guards state.sh applies to `reports/` (no
  symlink on `reports/`, its `.gitignore` or the target file). Those guards
  stay in one place, in state.sh, and are not copied into step.sh. Today
  they sit inline in `cmd_report_path`. A state.sh subcommand that writes
  the file is the obvious form; the planner picks the exact shape.
- ship.sh's own not-verified file in `reports/` (written by the shipper,
  read by ship.sh) stays as it is. The shipper fills it from the inputs
  file instead of from its prompt.
- The inputs file is written by step.sh, not by the agent: it is never on
  an agent's `Wrote:` list, and the `Wrote:` check doesn't expect it.
- step.sh stays Bash 3.2, with no jq and no Python, and shellcheck clean.
- The agents, step.sh, `tests/step`, `harness.md` and the `/feat`, `/fix`
  and `/tiny` skills change together (project rule: an input contract
  changes with its callers). `/feat` and `/fix` stay thin.
- `/tiny` stays within its 200-line lint cap.

## Log

- [x] 0 Setup — brief specs/briefs/spawn-inputs-file.md (small, #69); no Spec Kit hooks; board users/pdemagny/projects/2, #69 set to In progress; kept the existing worktree, branch renamed spawn-inputs-file; base current (2e6d34a)
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 Agents receive every list exactly as step.sh wrote it (P1); US2 Empty and repeated spawns stay clean (P2); US3 /tiny's review spawn drops its two none lists (P3)
    - Requirements: 16; FR-001 one inputs: line replaces list keys; FR-004 file is report path with .in.md; FR-007 guards stay in state.sh; FR-009 agents read the file, missing line means none; FR-012 file never on Wrote: list; FR-014 /tiny drops design and rejected keys within 200 lines
    - Spec assumptions: 1. The six named agents are the only ones taking lists (recommended: keep as written); 2. state.sh subcommand shape left to planning (recommended: keep as written)
    - Unchecked checklist items: none
- [!] 3 Plan — unparsable: 3-plan.md: line 28 (Size trigger); reformat 1 of 1
- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [soft] — auto-applied D1, D2
    - D1 contracts/prompts.md: "The six agents" sentence — Continued spawns: the agent sentence says "the file on the prompt's `inputs:` line" and "no `inputs:` line: every list is `none`". A `SendMessage` continuation is not the original prompt. The agent could reuse the earlier spawn's file, or treat a message with no line as "none", and FR-005 forbids the first. — rec: apply
    - D2 plan.md: Technical Context "Testing" and Design "Tests" — The plan's test list is inconsistent: Technical Context says "five new cases", while Design lists three new cases (all empty, awkward item, printed twice) plus three gap cases (design batch with `rejected`, 7e, `/fix` 1 with commands and answers), with the awkward case possibly the same as the last. An implementer would have to guess the count and which case does what. — rec: apply
    - spec assumptions: kept as recommended
- [x] 3 Plan — amended (D1, D2); assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [soft] — 27 tasks; story.sh: match; analyze ran
- [!] 6 Implement — unparsable: 6-US1.md: line 4 (Checks); reformat 1 of 1
- [x] 6 US1 — not verified: none
    - wrote: specs/015-spawn-inputs-file/tasks.md
- [!] 6 Implement — report missing: 6-US2.md
- [x] 6 Implement [hard] — report missing: 6-US2.md
    - answer: back to 6 (user: "ok, rerun US2")
- [!] 6 Implement — unparsable: 6-US1-3.md: line 16 (Files changed); reformat 1 of 1
- [x] 6 US1 — not verified: none
- [!] 6 Implement — report missing: 6-US2.md
- [x] 6 Implement [hard] — report missing: 6-US2.md
    - answer: back to 6 (user: "ok, run the diagnostic then back to 6")
- [x] 6 US1 — not verified: none
- [x] 6 US2 — not verified: none
    - wrote: specs/015-spawn-inputs-file/tasks.md
- [x] 6 US3 — not verified: none
    - wrote: specs/015-spawn-inputs-file/tasks.md
- [x] 6 Implement [soft] — tasks done: 27 (0 not verified); checks pass
- [x] 7 Code review [hard] — B1, B2, S1 need you; S1 security
    - B1 - — none — rec: user (no valid recommendation)
    - B2 - — none — rec: user (no valid recommendation)
    - S1 - — none
    - P1 .apm/skills/feat/scripts/step.sh:1209-1217 — one extra `state.sh inputs` process per spawn (one file write); negligible next to an agent spawn — rec: skip (no real cost)
    - C1 .apm/skills/feat/scripts/state.sh:870-895 — shrink: `reports_dir`/`reports_make` split is used by both report-path and inputs, so it removes duplication; nothing to cut — rec: skip (already lean)
    - R1 .apm/skills/feat/scripts/state.sh:20 — Header comment column alignment of the `snapshot` line was shifted by one space relative to its neighbours — rec: apply
    - R2 .apm/skills/feat/references/harness.md:274-276 — harness.md bullet re-wrapped with a short orphan line ("inputs file. Show the lists") — rec: skip (cosmetic)
    - [std]1 .apm/skills/tiny/SKILL.md:148 — hard: garbled prose in /tiny's review step ("size and size `small`"), left over from deleting the two `none` lists — rec: apply
    - [std]2 .apm/skills/feat/scripts/state.sh:20 — judgement: the state.sh usage comment column for `snapshot` was re-aligned (token text moved) with no change to snapshot — rec: skip (cosmetic)
    - answer: approved (user: "ok, leave B1 B2 S1")
    - answer: leave B1 (user: "ok, leave B1 B2 S1")
    - answer: leave B2 (user: "ok, leave B1 B2 S1")
    - answer: leave S1 (user: "ok, leave B1 B2 S1")
    - outcome: picked R1, [std]1; rejected B1 (user: "ok, leave B1 B2 S1"), B2 (user: "ok, leave B1 B2 S1"), S1 (user: "ok, leave B1 B2 S1"), P1 (as recommended), C1 (as recommended), R2 (as recommended), [std]2 (as recommended)
- [x] 7 review fixes — [std]1 → applied; R1 → applied; performance: none; checks: mise run lint → pass, mise run test:step → pass, mise run test:state → pass, mise run test:tracker → pass, mise run test:spec-number → pass, mise run test:story → pass, mise run test:sizes → pass, mise run test:ship → pass, mise run test:measure → pass, mise run test:apm → pass; not verified: none
- [x] 8 Ship
