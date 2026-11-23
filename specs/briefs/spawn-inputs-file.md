# Brief: step.sh writes each spawn's lists to an inputs file the agent reads
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
