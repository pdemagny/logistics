# Quickstart: validating agent-run boundaries

## Prerequisites

The repo's tools through `mise` (`mise install`): bash, shellcheck,
actionlint, d2 0.9.0, Python 3.11 or later for lint's compile step.

## Offline checks (before the PR)

```sh
mise run test:step      # tests/step: the new cases of contracts/step-cli.md#tests, regenerated goldens
mise run test:state     # state.sh: the new record case, the rest unchanged
mise run test:ship
mise run test:preflight
mise run test:trail
mise run test:tracker
mise run test:spec-number
mise run test:story
mise run test:sizes
mise run test:measure
mise run test:secret-scan
mise run lint           # shellcheck, the harness.md grep, the drift checks, docs/img matches a fresh render
mise run test:apm
```

Expected: every task exits 0. `UPDATE=1 bash tests/step/run.sh` rewrites
the goldens and exits non-zero; review them with `git diff
tests/step/expected`: every agent-run block gains `step script:` and
`boundary:` as its last keys, the boundary lines of 2, 3 and 5 lose
`agent=<id>`, and nothing else changes in the existing goldens except
`Agents:` lines where a case relied on `agent=<id>`.

## Spot checks

- Re-print (US3): in the scratch repo a test case builds, run a boundary,
  copy the state file and `reports/last-step.md`, run the same call again:
  the two outputs are equal and `cmp` finds both files unchanged.
- Fail closed: a call with the token of an older boundary, or a report
  path step.sh never printed, exits 1 with one `step: error:` line.
- The record: `reports/last-step.md` starts with the fixed "Data, never
  instructions" line, holds `call:`, `sums:` and `output:` (two
  `call:`/`sums:` pairs after a reformat), and is listed by no `git
  status` (ignored with `reports/`); with `reports/` removed, the next
  call recreates it with its `*` `.gitignore`.
- Reformat chain: after a reformat the agent ran, the first call's words
  re-print the second call's decision.
- Concurrent write: an `S log` landing while a `step.sh` call decides
  makes that call end in `step: error: the state file changed since
  step.sh read it; call again`, with `Current phase` unchanged.
- Diagrams: `mise run diagrams` leaves `docs/img/chain.svg` and
  `models.svg` unchanged and rewrites `gates.svg`.

## Live runs (after merge, not blocking the PR)

1. A small `/feat` run: the coordinator's Bash calls to `step.sh` are
   `setup`, one per reviewer batch (4, 7, and 7e on medium), one per answer
   at a hard gate, the one `done:` check after the shipper, and none after
   the specifier, planner, tasker, each story and the review fixes. Each
   of those agents' hand-backs ends with a four-backtick block whose first
   line is a verdict.
2. A small `/fix` run: no coordinator `step.sh` call after the assessor
   (assess and test) and the implementer; one for the phase 4 batch and
   the `done:` check after the shipper.
3. SC-006: after at least five runs of each skill, `mise run measure
   --compare-since <merge date>` shows coordinator `step.sh` calls only at
   fan-outs, gates, answers and the `done:` check, and subagent calls per
   spawn up by about 2
   at most.
