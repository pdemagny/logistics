# /fix state: ship.sh publish pushes onto a stale base when main moved during the checks

- Branch: fix-110-ship-sh-publish Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-110-ship-sh-publish
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, concise; never co-author, user is sole author; stage only task files. In worktrees call /usr/bin/git directly, one plain command per call (no heredocs/pipes/globs). rm/cp/mv aliased -i: use command rm -f etc. Shell zsh: quote vars. Checks: mise run lint and mise run test:apm before committing; ship.sh tests are tests/ship (mise run test:ship), Bash 3.2, no jq, no Python, shellcheck clean. CHANGELOG generated from commits (write feat/fix subjects for users). PR body says Closes/Fixes #N, never in a commit message. Agent report format changes go with step.sh and tests/step.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #110
- Gates: none

## Report

#110

## Log

- [x] 0 Setup — tracker: ok users/pdemagny/projects/2 (Brief, In progress, In review); slug 110-ship-sh-publish; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 2; proposed size medium; remediations: 2; public behaviour change
    - answer: approved (user: "ok")
    - passed: gate: valid, high confidence, reproduced, 2 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Reuse PR: conflict with Conflicts: none, or add a distinct main-moved outcome in step.sh? → reuse PR: conflict (no step.sh schema change)
- [x] 1 Assess — answer: Cap the ship-mode move-then-ship-again loop when main keeps moving? → no cap in this fix; a follow-up issue if it shows up
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/110-ship-sh-publish/fix.md
    - wrote: tests/ship/expected/ship-moved.out
- [x] 2 Fix [hard] — size increase: medium → large (deviations)
    - answer: approved (user: "keep medium")
- [x] 3 Test [soft] — verified
- [x] 4 Code review [soft] — auto-applied [std]1, [std]2; skipped B1 (reviewer: "same handling as rebase_onto's conflict path at line 791; the reset only fails with local edits to files that differ between HEAD and the lease")
    - B1 .apm/skills/feat/scripts/ship.sh:974 — rebase-mode base_check ignores a failed `reset --keep` to the lease, then reports `PR: conflict`, which rebase.md reads as "the shipper put the branch back on the lease"; lease_push adds "; <branch> left rebased locally" in the same case — rec: skip (same handling as rebase_onto's conflict path at line 791; the reset only fails with local edits to files that differ between HEAD and the lease)
    - [std]1 .apm/skills/feat/scripts/ship.sh:966-970 — judgement: base_check's "already pushed at HEAD" predicate (pushed ref, lease sha, compare) repeats lease_push's three lines, and publish_ship has a third copy of the pushed-ref read — rec: apply
    - [std]2 .apm/skills/feat/references/move.md:65 — judgement: the edited move.md line and the workflow.md sentence are not wrapped like the paragraphs around them (about 75 columns) — rec: apply
- [x] 4 implementer — [std]1 → applied; [std]2 → applied; performance: none; checks: mise run test:ship → pass, mise run test:step → pass, mise run lint → pass, mise run test:apm → pass; not verified: none
- [x] 3 Test [soft] — verified
- [x] 5 Ship
