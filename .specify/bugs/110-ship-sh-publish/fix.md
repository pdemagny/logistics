# Bug Fix: ship.sh publish pushes onto a stale base when main moved during the checks

- **Slug**: 110-ship-sh-publish
- **Fixed**: 2026-11-27
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`ship.sh publish` now fetches `origin/<default>` again before any push (ship, fix and rebase mode) and, when it is no longer the `Base:` that `prepare` rebased onto, pushes nothing and reports `PR: conflict` with `Conflicts: none` (exit 1), so `step.sh` runs the existing move-then-ship-again flow. Rebase mode puts the branch back on the lease first, as a rebase conflict does. No `step.sh` schema change (the user's answer at the assess gate).

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/ship.sh` | modified | new `base_check` (fetch, compare with `$BASE`, `conflict` with no files; rebase mode `reset --keep` to the lease), called in `publish()` after the check-fix fold and before `number_check`, the autosquash and every push; header comment updated |
| `tests/ship/run.sh` | added tests, updated two | three moved-main cases and a retry case; the two renumber-at-publish cases now take the number through an open PR instead of a main commit |
| `tests/ship/expected/ship-moved.out` | added | golden for the ship-mode moved-main report |
| `.apm/agents/feat-shipper.agent.md` | modified | step 5: `PR: conflict` with `Conflicts: none` means main moved during the checks; report it as it is |
| `.apm/skills/feat/references/move.md` | modified | "At ship": `Conflicts:` may read `none` (main moved after the shipper's rebase); same flow |
| `docs/workflow.md` | modified | ship section: publish's base check, the narrowed race, `/feat rebase` for a merge right after the push |

## Diff Highlights (optional)

```bash
base_check() {
  ...
  if [[ $pushed == "$head" && $head != "$lease_sha" ]]; then return 0; fi
  fetch_default
  main=$(git rev-parse -q --verify "refs/remotes/origin/$V_default^{commit}" 2>/dev/null) || main=''
  [[ $main != "$BASE" ]] || return 0
  if [[ $MODE == rebase ]]; then git reset -q --keep "$V_lease" >/dev/null 2>&1 || true; fi
  conflict
}
```

A failed fetch blocks through `gx` (`! git fetch: …`), nothing pushed, as in prepare.

## Tests Added or Updated

- `tests/ship/run.sh` "stop: main moved since prepare (ship)" — origin/main advances between prepare and publish: exit 1, `PR: conflict`, `Conflicts: none`, HEAD unchanged, origin/main fetched, nothing pushed, no `pr create`; golden `ship-moved.out`.
- "stop: main moved since prepare (fix)" — same in fix mode (no spec-number fetch): nothing pushed, no gh call at all.
- "rebase: main moved since prepare resets to the lease" — no lease push, no `pr view`/`pr edit`, HEAD back on the lease.
- "stop: main moved after the push, publish again still opens the PR" — a retry after `gh pr create` failed post-push opens the PR even though main moved.
- "ship: renumbered at publish" and "stop: a gh failure after a renumber, …" — the number is now taken by an open PR (stub `prs`/`files-7`), the path that still renumbers at publish; their assertions are unchanged.
- Confirmed the ship moved-main case fails with the call disabled (exit 0, PR opened).

## Local Verification

- Commands run: `mise run lint` → pass; `mise run test:ship` → pass (65 cases); `mise run test:step` → pass; `mise run test:apm` → pass.
- Manual checks: none.

## Deviations from Assessment

- Two existing renumber-at-publish tests moved main to take the spec number; with the fix that is a conflict, so they now take the number through an open PR (the remaining way a number is taken between the calls). Their assertions and the `ship-renumber.out` golden are unchanged.
- `base_check` is skipped when the branch is already pushed at HEAD (a retry after a post-push `gh` failure; in rebase mode, HEAD not the lease), mirroring `publish_ship`'s and `lease_push`'s retry paths: reporting a conflict there would send a move whose plain push is then refused, or reset a branch already force-pushed. Covered by the retry test.
- The check runs before `number_check` (not after the autosquash), so no renumber is done against a base that is abandoned; a fixup left by the fold is squashed by the next prepare's autosquash.

## Follow-ups

- No cap on the ship-mode move-then-ship-again loop when main keeps moving (user's answer); open an issue if it shows up.
