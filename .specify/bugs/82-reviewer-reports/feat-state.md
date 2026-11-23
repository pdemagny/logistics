# /fix state: Reviewer reports left unwritten, and one missing report cancels the batch's reformat turn

- Branch: fix-82-reviewer-reports Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-82-reviewer-reports
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change each, no co-author; git via /usr/bin/git, one plain command per call; rm/cp/mv aliased -i (use command rm -f); agent prompts end with a fixed report format: change the agent, step.sh, tests/step and the skills together; step.sh/ship.sh Bash 3.2, no jq, no Python; shellcheck clean; checks: mise run lint, mise run test:step (and other test:* tasks), mise run test:apm; sizes.json is the source of sizes.tsv/docs tables (mise run diagrams); never edit CHANGELOG or versions
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #82

## Report

#82

## Log

- [x] 0 Setup — tracker: ok users/pdemagny/projects/2; slug 82-reviewer-reports; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 3; proposed size large; remediations: 3; public behaviour change
    - answer: approved (user: "ok, but medium")
    - answer: size medium (user: "ok, but medium")
    - passed: gate: valid, high confidence, reproduced, 3 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Ship the review_boundary per-group re-spawn in this fix, or only the agent-file rule? → both here (user: "ok, but medium")
- [x] 1 Assess — answer: Does a missing group's re-spawn use up the batch's one reformat turn, or get its own allowance? → its own one-time allowance per group, logged, a second miss hard (user: "ok, but medium")
- [x] 1 Assess — answer: Give feat-shipper and feat-brief-reviewer the rule too? → no (user: "ok, but medium")
- [x] tracker: #82 set to "In progress"
- [!] stopped before the move 314e49c → 708d407 (before 2 Fix) (user: "stop")
- [x] move — 314e49c → 708d407 (before 2 Fix): checks pass; not verified: none
    - resolved: .specify/bugs/82-reviewer-reports/ — the WIP commit was refused by the permission classifier; the branch had no commits of its own and the only change was this untracked dir, which main does not touch, so the move ran as a fast-forward with the dir left untracked (no WIP commit, nothing to undo)
    - resolved: .specify/bugs/82-reviewer-reports/assessment.md — main (708d407) changed step.sh, feat-bug-assessor, feat-implementer, feat-code-reviewer, harness.md and docs/workflow.md, but not review_boundary, check_report, reformat or the agents' report-writing paragraphs; the assessment still holds, only its quoted line numbers may have shifted
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/82-reviewer-reports/fix.md
    - wrote: tests/step/fixtures/agents/code-reviewer/bad-7c-slip.md
    - wrote: tests/step/expected/batch-missing-slip.out
    - wrote: tests/step/expected/batch-missing-slip.log
    - wrote: tests/step/expected/batch-missing-slip-7e.out
    - wrote: tests/step/expected/batch-missing-slip-7e.log
    - wrote: tests/step/expected/batch-missing.out
    - wrote: tests/step/expected/batch-missing.log
    - wrote: tests/step/expected/batch-missing-twice.out
    - wrote: tests/step/expected/batch-missing-twice.log
    - wrote: tests/step/expected/batch-missing-check.out
    - wrote: tests/step/expected/batch-missing-check.log
    - wrote: tests/step/expected/batch-missing-snapshot.out
    - wrote: tests/step/expected/batch-missing-snapshot.log
    - wrote: tests/step/expected/feat7e-missing.out
    - wrote: tests/step/expected/feat7e-missing.log
    - wrote: tests/step/expected/fix4-missing.out
    - wrote: tests/step/expected/fix4-missing.log
- [x] 2 Fix [hard] — size increase: medium → large (deviations)
    - answer: approved (user: "ok, stay medium")
- [x] 3 Test [soft] — verified
- [x] 4 Code review [soft] — auto-applied B2, [std]1; skipped B1 (reviewer: "behaviour matches the documented rule; the second slip is still hard through turn_used")
    - B1 .apm/skills/feat/scripts/step.sh:2800-2810 — A reformat spawn's own missing report (e.g. 7-7c-2.md after a 7c reformat) now also gets a fresh review-mode respawn instead of the hard gate it got before; the docs' "a group whose report is missing" covers it, but no test locks it in — rec: skip (behaviour matches the documented rule; the second slip is still hard through turn_used)
    - B2 tests/step/run.sh:1539-1554 — missing: the "report changed since checked" half of the non-missing-failure test is not written; only a bad Wrote: item and a snapshot change are combined with a missing report — rec: apply
    - [std]1 .apm/skills/feat/scripts/step.sh:1852-1856 — judgement: the merge-base DIFF_BASE fallback (default_branch, git merge-base, die) is now written a third time, in review_respawn, beside spawn_7e_block and diff_prep — rec: apply
- [x] 4 implementer — B2 → applied; [std]1 → applied; performance: none; checks: mise run lint → pass, mise run test:tracker → pass, mise run test:spec-number → pass, mise run test:story → pass, mise run test:state → pass, mise run test:sizes → pass, mise run test:step → pass, mise run test:ship → pass, mise run test:measure → pass, mise run test:apm → pass; not verified: none
    - wrote: tests/step/expected/batch-missing-changed.out
    - wrote: tests/step/expected/batch-missing-changed.log
- [x] 3 Test [soft] — verified
- [x] 5 Ship
