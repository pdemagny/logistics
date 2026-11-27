# Bug Assessment: ship.sh publish pushes onto a stale base when main moved during the checks

- **Slug**: 110-ship-sh-publish
- **Created**: 2026-11-27
- **Source**: pdemagny/logistics#110 (https://github.com/pdemagny/logistics/issues/110; host github.com, allowlisted; read with `gh issue view`)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

Title: "ship.sh publish pushes without re-checking main after the checks".

Summary: `ship.sh prepare` fetches `origin/<default>` and rebases onto it. The shipper then runs the full checks (several minutes). `ship.sh publish` then pushes and opens the PR without fetching again: it reuses the `Base:` that `prepare` recorded in the handoff and only re-checks the spec number. A PR merged during the checks makes the new PR conflict as soon as it opens. Seen in another repo: prepare rebased onto 727b2a5, a 3-commit PR merged at 21:02:35, publish opened the PR at 21:03:55 already conflicting in 8 files; the run's boundary base checks had all passed.

Done when (from the issue):
- `publish` fetches `origin/<default>` before pushing (ship, fix, and rebase mode for its lease push).
- If `origin/<default>` moved since prepare's `BASE`, publish pushes nothing and reports it the way a ship conflict is reported (`PR: conflict`, or a `main moved` outcome), so `step.sh` runs the rebase-mode move, reruns the checks and ships again.
- A clean replay needs no user stop, as with any kept move.
- A test covers the window: `origin/<default>` advances between prepare and publish, and publish refuses to push.

Notes from the issue: this narrows the race, it does not remove it; `/feat rebase` stays the way to handle a merge right after the push. Related: #13.

## Symptom

After `prepare`, `origin/<default>` advances (another PR merges) while the shipper runs the checks; `publish` still pushes the branch based on the old base and opens the PR, which may conflict on GitHub at once. Expected: publish notices main moved and pushes nothing, reporting a conflict-like outcome so the run moves onto the new main and ships again.

## Reproduction

Scratch test under the system temp dir (modelled on `tests/ship/run.sh`, using the stub `tests/ship/bin/gh` and the real `state.sh`, `secret-scan.sh`, `spec-number.sh`):

1. Build a bare origin with `main`, a clone on `feat-x` with a spec dir, its state file, a ship notes file and a source change.
2. Run `ship.sh prepare ship <flags>`: exit 0, handoff written with `Base:` = origin/main (a23bf23).
3. From a second clone, commit to `main` and push it to the bare origin (origin main now 8943b8d).
4. Run `ship.sh publish ship <flags>` (spec dir now `specs/001-x`).

Observed: publish exits 0 with `PR: https://github.com/o/r/pull/42`; `feat-x` is pushed to origin with merge base a23bf23 (the stale base); the stub logged `pr create`. Notably, the local `refs/remotes/origin/main` was already at 8943b8d after publish: in ship mode `number_check` runs `spec-number.sh check`, which itself fetches `origin/<default>`, yet ship.sh never compares the fresh ref with `BASE`. Reproduced.

## Suspected Code Paths

- `.apm/skills/feat/scripts/ship.sh:publish()` (~line 1217) — reads the handoff, folds check fixes, `number_check`, fixup autosquash onto `$BASE`, `pre_push`, then `publish_ship`/`publish_rebase`; there is no `fetch_default` and no comparison of `refs/remotes/origin/$V_default` with `$BASE`.
- `.apm/skills/feat/scripts/ship.sh:read_handoff()` (~line 824) — `BASE` comes only from the handoff written by prepare.
- `.apm/skills/feat/scripts/ship.sh:number_check()` (~line 958) — ship mode (and rebase mode with `--spec-number`) calls `spec-number.sh check`, which fetches (`spec-number.sh:50`); fix mode skips it, so fix mode does not even refresh the ref.
- `.apm/skills/feat/scripts/ship.sh:publish_ship()` / `push_branch()` / `publish_rebase()` / `lease_push()` — push without a base check.
- `.apm/skills/feat/scripts/ship.sh:conflict()` (~line 394) — the existing `PR: conflict` exit (`finish conflict`, exit 1), which `step.sh` already routes to the rebase-mode move at ship (`step.sh` ~line 3867, `ship_move`) and `rebase.md` step 5 routes back to 4.
- `.apm/skills/feat/references/move.md` "At ship" and `.apm/agents/feat-shipper.agent.md` — describe `PR: conflict` as a rebase conflict with files listed under `Conflicts:`.

## Root Cause Hypothesis

`publish` trusts the `Base:` recorded by `prepare` and never re-reads `origin/<default>` before pushing, so any commit merged to main during the shipper's checks goes unseen; the gap is the whole duration of the checks. Confidence: high (read in code and reproduced).

## Proposed Remediation

**Preferred**: In `publish()`, before any push (after `read_handoff`/`parse_notes` and before `pre_push`/`publish_*`), call `fetch_default` and compare `git rev-parse refs/remotes/origin/$V_default` with `$BASE`. If they differ, push nothing and exit through the existing conflict path (`PR: conflict`, exit 1) so `step.sh` and the coordinators reuse the move-then-ship-again flow already wired for a ship conflict (and, in rebase mode, `rebase.md`'s "main moved again: back to 4"). Since no file conflicts, `Conflicts:` would read `none`; consider a distinct `Command for the user` or a `Conflicts:`-free marker only if step.sh needs to tell the two apart. Do the check after the check-fix fold and fixup autosquash (local-only steps) or before them; in either case it must precede every push. Rebase mode must leave the branch at the state it would be put back to on a conflict (reset `--keep` to the lease, as `rebase_onto` does) so the move starts from the PR's head. Update the shipper agent and `move.md` text so `PR: conflict` with `Conflicts: none` reads as "main moved since prepare".

**Alternatives**:
- A new `PR: moved` (or `main moved`) outcome: clearer for readers, but needs `step.sh`'s shipper schema (`pwant PR`), its ship boundary case, `tests/step` fixtures, the shipper agent, both skills' report handling and `move.md` to change together.
- Have publish rebase onto the new main itself and continue: rejected, the checks ran on the old base and the move flow must rerun them.

**Files likely to change**:
- `.apm/skills/feat/scripts/ship.sh`
- `tests/ship/run.sh`
- `tests/ship/expected/` (a new golden for the moved-main case)
- `.apm/agents/feat-shipper.agent.md`
- `.apm/skills/feat/references/move.md`
- possibly `.apm/skills/feat/scripts/step.sh` and `tests/step` (only for the alternative, or if `Conflicts: none` with `PR: conflict` must be told apart)

**Tests to add or update**:
- tests/ship: ship mode, origin/main advanced between prepare and publish: exit 1, `PR: conflict`, `no_push`, no `pr create` call.
- Same for fix mode (no spec-number fetch, so the fetch must be publish's own).
- Rebase mode: origin/main advanced after prepare: no lease push, no `pr edit`, branch put back on the lease.
- Existing publish cases keep passing (origin unchanged: no conflict).

## Risks & Considerations

- A network fetch in publish adds a failure point: a failed fetch should block (`! git fetch: …`), nothing pushed, like prepare's.
- The race is narrowed, not removed (a merge right after the push still conflicts); `/feat rebase` remains the remedy.
- Reusing `PR: conflict` with `Conflicts: none` changes what that report means for readers of move.md and the shipper agent; documentation must follow.
- A loop is possible on a busy main (move, checks, main moves again); rebase.md already caps it at "back to 4, once" for rebase mode; the ship-mode flow has no such cap mentioned.
- No security, data or concurrency risk in the data sense; this is a workflow race between runs.

## Open Questions

- Reuse `PR: conflict` with `Conflicts: none`, or add a distinct `main moved` outcome in step.sh? [NEEDS CLARIFICATION] recommended: reuse `PR: conflict` (no step.sh schema change).
- Should the ship-mode "move then ship again" be capped when main keeps moving? [NEEDS CLARIFICATION] recommended: no cap in this fix; follow-up issue if it shows up.
