# Quickstart: validating configurable gates

Run from the repo root (the worktree), offline.

## 1. The suites

```sh
mise run lint
mise run test:apm
mise run test:tracker
mise run test:preflight
mise run test:state
mise run test:step
mise run test:ship
mise run test:trail
mise run test:measure
```

Expected: all pass. `git diff tests/step/expected` shows only new goldens
(the forms listed in [contracts/gates.md](contracts/gates.md#tests-teststep))
and the `/fix` 1 `issue to create` fixture's `.logistics.yml` (now a
`tracker:` line); no existing golden changes (SC-001). `git diff
tests/preflight/expected` shows only a new `gates: none` line, right
after `board:`, in the goldens of brief, issue and symptom runs that get
past the fetch.

## 2. Scenarios and where they are covered

| Scenario (spec) | Covered by (`tests/step` case numbers from [contracts/gates.md](contracts/gates.md#tests-teststep)) |
| --------------- | ---------- |
| US1.1, FR-008: `feat.6` soft on large, mark on the last story only | case 9 |
| US1.2–1.4, SC-003, SC-004: soft on large equals medium (at gate 4, minus the plan rows when gate 3 stopped); safety reasons stay | cases 3, 9 (`same_verdict`, `plan3` for gate 4 after a stopped gate 3) |
| US1.5, FR-005: `feat.3` soft on large merges gate 3, its reasons at gate 4 | case 7 |
| US1.6: `fix.1` soft on a medium bug; `Confidence: medium` stops | case 11 |
| US1.7, FR-009: soft at `feat.2`, `fix.2`, `fix.3` equals `auto` | case 2 (`same_run`) |
| US1.8, US2.8, FR-023, SC-009: a cell for one size leaves the others as `auto` | case 2 (`same_run`) |
| US2.1–2.4, FR-007: the small gate 3, its answers, resume, gate 4 skipping the plan rows | case 5 |
| US2.5–2.7, FR-006: `hard` elsewhere; `large; gates: hard` | cases 4, 6, 8–14 |
| US3, SC-006: field read once, mid-run edit ignored, old state = `auto` | `tests/state` init cases; `tests/step` cases 1, 15, 16; `tests/preflight` gates cases |
| US4, SC-005: malformed section stops with its line; a pair key with spaces echoes nothing | `tests/tracker` error rows and the `{ ignore this: soft }` case; `tests/preflight` stop line |
| US5, SC-007: gates-only file leaves tracking off (resume included) | `tests/tracker` off cases; `tests/preflight` board and flag; `tests/step` case 17; the skills' resume clause (contracts/prompts.md), read in review |
| US6, SC-008: the matrix | `docs/workflow.md` `## Configuring the gates` has ten settable rows (each with its per-size behaviour) and two ship rows; `/fix`'s `### Gates` links it; `docs/install.md` section 7 shows both forms |

## 3. A manual run (optional)

In a scratch repo, push a `.logistics.yml`:

```yaml
gates:
  feat:
    3: { small: hard }
```

1. `/feat <a small brief>`: setup shows `Gates in force (from
   origin/main:.logistics.yml): feat.3.small=hard`, board tracking is off
   (no `tracker:`), the state file has `- Gates: feat.3.small=hard`.
2. After the plan: `Phase 3: Plan — needs your call` with the reason
   `gates: hard`; "ok" → the design review runs as today, without asking
   again about the plan's assumptions.
3. Edit `.logistics.yml` (`3: soft`), push, `/feat resume`: the run still
   reads `Gates: feat.3.small=hard` (the file is not read again).
4. Push `gates:\n  feat:\n    8: soft` and start another run: setup stops
   with `origin/main:.logistics.yml line 3: feat.8 is not settable (feat
   2-7, fix 1-4)`.
