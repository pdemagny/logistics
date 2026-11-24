# /fix state: step.sh accepts an unproven "Analyze: ran" from the tasker

- Branch: fix-97-tasker-reports-analyze Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-97-tasker-reports-analyze
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, concise; never co-author commits (user is sole author); feat/fix subjects feed CHANGELOG, write them for users; PR body says Closes #N, never a commit message; stage only task files. Shell is zsh: quote variables; use command rm -f / command cp -f / command mv -f; never pkill -f a pattern in your own command line. In worktrees call /usr/bin/git directly, one plain command per call (cd <worktree> && /usr/bin/git ...), no heredocs, pipes or globs; fetch and rebase before pushing. Checks: mise run lint and mise run test:apm before committing; offline tests mise run test:step, test:state, test:sizes, test:ship, test:preflight, test:trail, test:tracker, test:story, test:spec-number, test:measure. step.sh/ship.sh/preflight.sh/trail.sh: Bash 3.2, no jq, no Python; shellcheck clean. Agent report formats, step.sh, tests/step and the skills change together. sizes.json is the source: edit it then mise run diagrams; never edit sizes.tsv or between sizes-start/sizes-end markers. Never edit versions or CHANGELOG.md by hand. Never name the private project orleus anywhere.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #97

## Report

#97

## Log

- [x] 0 Setup — board users/pdemagny/projects/2 (Brief, In progress, In review); slug 97-tasker-reports-analyze; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 1; proposed size medium; remediations: 3; public behaviour change
    - answer: approved (user: "one-line field, go on with medium")
    - passed: gate: valid, high confidence, reproduced, 3 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Should the evidence be a one-line metrics field in the tasker report or a separate analyze report file checked by step.sh? → the one-line field (user: "one-line field, go on with medium")
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/97-tasker-reports-analyze/fix.md
    - wrote: tests/step/fixtures/agents/tasker/ran-no-metrics.md
    - wrote: tests/step/expected/feat5-no-metrics.out
    - wrote: tests/step/expected/feat5-no-metrics.log
    - wrote: tests/step/expected/feat5-metrics-none.out
    - wrote: tests/step/expected/feat5-metrics-none.log
    - wrote: tests/step/expected/fmt-tasker-metrics.out
    - wrote: tests/step/expected/fmt-tasker-metrics.log
- [x] 2 Fix [hard] — size increase: medium → large (deviations)
    - answer: approved (user: "ok")
- [x] 3 Test [soft] — verified
- [x] 4 Code review [soft] — auto-applied none
- [x] move — db0d8ec → a90bd9f (before 5 Ship): checks pass; not verified: none
    - resolved: tests/step/run.sh — main's many_tasks helper (configurable-gates) wrote `Analyze: ran` with no metrics line, so c3-feat5-large went hard with the fix's new reason; it now writes an `Analyze metrics:` line, as the fix did for tasker/match.md (no conflict: the rebase applied cleanly)
- [x] 5 Ship
