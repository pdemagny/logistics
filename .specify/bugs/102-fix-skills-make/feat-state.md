# /fix state: step.sh accepts a typed "Analyze: ran" with no trace of analyze's run

- Branch: fix-102-fix-skills-make Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-102
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, never co-author; in worktrees call /usr/bin/git directly, one plain command per call; zsh, rm/cp/mv aliased -i (use command rm -f etc.); edit sizes.json then mise run diagrams, never edit sizes.tsv or between sizes-start/end markers; mise run lint and mise run test:apm before committing, plus the relevant mise run test:* tasks; step.sh/ship.sh/preflight.sh/trail.sh are Bash 3.2, no jq, no Python, shellcheck clean; keep /feat-only words out of harness.md, rebase.md, move.md; agent prompt report formats, step.sh and tests/step change together; never edit CHANGELOG or versions; PR says Closes/Fixes #N in body, never in commit message
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #102
- Gates: none

## Report

#102

## Log

- [x] 0 Setup — board tracker: ok users/pdemagny/projects/2; slug 102-fix-skills-make; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 2; proposed size medium; remediations: 3; public behaviour change
    - answer: approved (user: "ok, go with your recommendations")
    - passed: gate: valid, high confidence, reproduced, 3 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Should the metrics line shape in 5-analyze.md be fixed by the tasker prompt, or parsed loosely from analyze's template bullets? → save analyze's report verbatim and parse the six labelled bullets loosely (the number after each label)
- [x] 1 Assess — answer: Include the separate analyze spawn in this fix? → no, file it as a follow-up issue
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/102-fix-skills-make/fix.md
    - wrote: tests/step/fixtures/agents/tasker/analyze.md
    - wrote: tests/step/expected/feat5-no-analyze.out
    - wrote: tests/step/expected/feat5-no-analyze.log
    - wrote: tests/step/expected/feat5-analyze-no-block.out
    - wrote: tests/step/expected/feat5-analyze-no-block.log
    - wrote: tests/step/expected/feat5-analyze-short.out
    - wrote: tests/step/expected/feat5-analyze-short.log
    - wrote: tests/step/expected/feat5-analyze-differ.out
    - wrote: tests/step/expected/feat5-analyze-differ.log
    - wrote: tests/step/expected/feat5-soft-layout.out
    - wrote: tests/step/expected/feat5-soft-layout.log
    - wrote: tests/step/expected/feat5-soft-layout.in
- [x] 2 Fix [hard] — size increase: medium → large (deviations)
    - answer: approved (user: "ok, keep medium")
- [x] move — 245b2b8 → b0f9c82 (before 3 Test): checks pass; not verified: none
- [x] 3 Test [soft] — verified
- [x] 4 Code review [hard] — B3 need you
    - B1 .apm/skills/feat/scripts/step.sh:3658 — A bullet whose value is followed by a note holding a colon is read from the last colon, not the first: `- Total Requirements: 8 (FR: 6, SC: 2)` reads 2 (a false "metrics differ" hard gate) and `- Total Tasks: 6 (T001: setup)` reads nothing (a false "lacks one of the six metrics") — rec: apply
    - B2 .apm/skills/feat/scripts/step.sh:3654-3659 — A table row whose coverage value has no `%` reads the `1` of the label's `>=1 task`: `| Coverage % (requirements with >=1 task) | 100 |` gives 1, so a real run gates hard on "metrics differ" — rec: apply
    - B3 .apm/skills/feat/scripts/step.sh:3679 — A stale `5-analyze.md` from an earlier analyze run is still accepted: in the accepted-fixes rerun (tasker step 4), a tasker that amends tasks.md without rerunning analyze and copies the old numbers passes, though the file predates the amended artifacts — rec: user (an extra check beyond the assessment; the stated risk accepts that a written report raises the bar without proving the run)
    - [std]1 .apm/skills/feat/scripts/step.sh:3673-3681 — judgement: `dm`, `AM`, `NN`, `w`, `x` are opaque names in the new helpers (`dm` is the digest metrics, `AM` the analyze-file metrics) — rec: skip (the file's convention is short result globals; a comment above each function already names them)
    - answer: approved (user: "ok, leave B3")
    - answer: leave B3 (user: "ok, leave B3")
    - outcome: picked B1, B2; rejected B3 (user: "ok, leave B3"), [std]1 (as recommended)
- [x] 4 implementer — B1 → applied; B2 → applied; performance: none; checks: mise run test:step → pass, mise run lint → pass, mise run test:apm → pass; not verified: none
- [x] move — b0f9c82 → c49f79b (before 3 Test): checks pass; not verified: none
- [x] 3 Test [soft] — verified
- [x] 5 Ship
