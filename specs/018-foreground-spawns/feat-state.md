# /feat state: Wait for sequential agents instead of spawning them in the background

- Branch: foreground-spawns Worktree: /home/pierre/Projects/logistics/.claude/worktrees/brief-foreground-spawns
- Size: small
- Agents: specifier adeb4124723fdf4e1, planner af3df4a7901504e55, tasker a5f838ec31cf3f0a0 (for SendMessage)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, never co-authored; PR body says Closes #87, never a commit message. In this worktree call /usr/bin/git directly, one plain command per call. rm/cp/mv are aliased -i: use command rm -f etc. Checks: mise run lint and mise run test:apm before committing, plus the offline tests (mise run test:preflight, test:measure, test:step, ...). Scripts stay Bash 3.2, no jq, no Python, shellcheck clean; measure.py is Python 3.11 stdlib only. CHANGELOG.md and release versions are generated, never edit by hand. New docs pages need title and weight front matter. Never name private projects from outside this repo.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #87

## Brief

- Size: small — ~15–20 tasks expected: one harness rule, a preflight note with its tests, an `install.sh check` line, one new measure.py metric with tests, docs
- Short name: foreground-spawns
- Kind: feat
- Issue: #87

## Why
`/feat` and `/fix` coordinators pay one extra model call per spawn. Every
spawn returns "Async agent launched" at once, so the coordinator spends a
text-only "spawned, waiting" turn, then another when the notification
arrives. On the 5 `/feat` runs since #28 that is about 17 text-only turns
per run right after an `Agent` result, a third of all coordinator calls,
each re-reading 120–160k tokens of context (`/fix`: about 4–5). This is for
logistics users (today: the maintainer) running `/feat` and `/fix`, as part
of epic #31's cost cuts.

## Today
Interactive Claude Code sessions run in "fork mode" by default: the Agent
tool has no `run_in_background` parameter and every subagent starts in the
background. The spike on #87 (Claude Code 2.1.330, answer posted on the
issue) found that `CLAUDE_CODE_FORK_SUBAGENT=0`, set in the user's
`settings.json` / `settings.local.json` `env`, brings the parameter back; it
still defaults to background, so a spawn must pass `run_in_background:
false`. Then the call blocks and returns the agent's report: 2 coordinator
calls instead of 3. Parallel foreground spawns in one message still run
concurrently. No logistics skill passes the parameter today, and nothing
tells the user the setting exists.

## Behaviour
- With `CLAUDE_CODE_FORK_SUBAGENT=0` in the user's settings, every `/feat`
  and `/fix` spawn (sequential agents and reviewer fan-outs alike, `rebase`
  included) blocks and returns the agent's report as its tool result; the
  coordinator's next call goes straight to `step.sh`, with no
  "spawned, waiting" turn.
- Without the setting, nothing changes: the Agent tool has no
  `run_in_background` parameter and spawns stay async as today.
- If a foreground agent is killed (Esc) and returns no report, nothing new
  happens: on the coordinator's next turn (or `/feat resume`, `/fix
  resume`) it makes its usual boundary call, and `step.sh` takes its
  existing missing-report path (reformat or fresh spawn, then a hard
  gate). The coordinator never re-spawns on its own.
- At setup, when `CLAUDE_CODE_FORK_SUBAGENT` is unset or empty,
  `preflight.sh` prints a one-line note, in its first call only (before
  `EnterWorktree`), never in worktree mode: how to opt in (the `env` line
  and where it goes), that it saves one model call per agent spawn in
  interactive sessions (no hard-coded number), and that setting it to `1`
  keeps background spawns and hides the note. The coordinator shows it;
  it never stops the run. With `0` or `1` set, no note. No Claude Code
  version detection.
- `install.sh check` reports the setting: `ok` when it is `0`, a `note`
  line (not counted as missing) otherwise, with the line to paste.
- `docs/install.md` has a short section: the setting, the gain, where to
  put it (`<repo>/.claude/settings.local.json` recommended: just you, just
  that repo, not committed; `~/.claude/settings.json`: every project, and
  plain sessions change too, the `fork` agent type goes away; not
  `.logistics.yml`: committed and shared, and this is a personal choice),
  and the trade-off: while an agent runs, a typed message waits until it
  finishes; **Esc kills the running agent**; Ctrl+B moves it to the
  background and the run continues the async way.
- `measure.py` reports, per run, the number of text-only coordinator turns
  right after an `Agent` result, so `--compare-since <date>` shows it
  directly. Definition: the first coordinator assistant turn with no
  `tool_use` block after the last tool result of a spawn batch (one or
  more spawns in one message), for every tool name in `SPAWN_TOOLS`.

## Out of scope
- `/brief`'s `feat-brief-reviewer` spawn and `/tiny`'s `feat-code-reviewer`
  spawn: one call saved each, `/tiny` is length-capped, and Esc during
  `/brief`'s interview should not kill its reviewer. They stay async.
- `SendMessage` continuations (`continue: <id>`): not tested in the spike.
  If they still return async they stay as they are; the new metric shows
  them as the remaining turns.
- #88 (agents run `step.sh` last): it removes the other extra call per
  boundary and is unaffected by this.
- Setting the env var for the user: a plugin can't (no `env` key), and
  logistics doesn't write the user's settings files.

## Alternatives rejected
- A `background: false` key in every `step.sh` spawn block — every spawn
  passes `false` (parallel foreground spawns still run concurrently), so a
  constant key carries no information, and it would rewrite ~125 golden
  files in `tests/step` and every agent's view of the block. One rule in
  `harness.md` does the same. Add the key only if measurement shows
  coordinators dropping the flag.
- `install.sh` asking "Wait for agents…? (y/N)" and writing the `env` key —
  `install.sh` is the developer install (APM and plugin users never run
  it), it has no interactive prompt today, and merging a key into an
  existing settings JSON from Bash without `jq` or Python is the riskiest
  code in the feature for one user. `check` reporting it, plus the preflight
  note and the docs, reach every install path.
- A separate switch to silence the preflight note (a `.logistics.yml` key,
  a "seen" state file) — `.logistics.yml` is committed and shared while
  this is personal; `CLAUDE_CODE_FORK_SUBAGENT=1` already states the choice
  in the same settings file.
- `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` — also makes spawns block, but
  removes background Bash and Monitor too; fork mode off is the narrower
  switch.
- Judging the gain on median calls per run only — too noisy on few runs of
  mixed sizes; a 15–17-call drop can hide behind one large run.
- Dropping the `measure.py` metric and checking the result by hand once
  (the brief review's yagni finding) — rejected by the user: the median is
  too noisy to judge on, and the metric keeps judging the rest of epic #31.
- Doing nothing — about a third of coordinator calls per `/feat` run, each
  re-reading the whole context, is the largest single waste left in epic
  #31's measurement.

## Acceptance
- `harness.md` says: when the Agent tool has a `run_in_background`
  parameter, pass `false` on every spawn; it holds no `/feat`-only words
  (`mise run lint` passes).
- In a session with `CLAUDE_CODE_FORK_SUBAGENT=0`, a `/feat` or `/fix` spawn
  returns the agent's report as its tool result, with no "Async agent
  launched".
- `preflight.sh` prints the note in its first call when the variable is
  unset or empty, and nothing when it is `0` or `1` or in worktree mode;
  its exit code never changes because of it; `tests/preflight` covers
  these cases. The new key is in the `setup-trail-scripts` preflight
  contract, and `.apm/skills/feat/SKILL.md` and `.apm/skills/fix/SKILL.md`
  say their setup shows the note.
- `install.sh check` prints `ok` for `0` and a `note` (exit unaffected)
  otherwise.
- `measure.py` prints the new per-run count; `tests/measure` covers a
  transcript with async spawns (count > 0) and one with foreground spawns
  (count 0); `docs/measure.md` describes it.
- After merge, `mise run measure --compare-since <merge date>` on runs with
  the setting shows text-only turns after an `Agent` result at about 0
  (only `SendMessage` continuations may remain), and `/feat`'s median
  calls per run falls by about 15–17.
- `mise run lint` and the offline tests pass.

## Constraints / decisions already made
- Opt-in only, through the user's own Claude Code settings; logistics adds
  no switch of its own.
- The flag lives in `harness.md` (shared by `/feat` and `/fix`), not in
  `step.sh`'s output; `step.sh` and `tests/step` don't change.
- `preflight.sh`: Bash 3.2, no jq, no Python; its output is a fixed-order
  `key: value` contract (`setup-trail-scripts`): a new key goes into that
  order, its contract and the coordinators' setup steps together.
- `measure.py`: Python 3.11+, standard library only.
- The setting is read from the environment Bash sees (the spike showed a
  `settings.json` `env` value reaches Bash).

## Log

- [x] 0 Setup — brief foreground-spawns (small, issue #87); install ok; board ok, #87 set to In progress; no Spec Kit hooks; worktree reused: brief-foreground-spawns, already on origin/main 48b9de2 (EnterWorktree refused inside a worktree session)
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 Spawns block and return the report (P1); US2 Learn the setting exists (P2); US3 Measure the gain (P3)
    - Requirements: 14; FR-001 harness rule passes run_in_background false; FR-002 step.sh unchanged; FR-003 preflight note in first call only when unset or empty; FR-008 install.sh check ok/note; FR-010 measure.py text-only turn metric
    - Spec assumptions: 1. Unexpected variable values count as chosen for the preflight note and get the note line in install.sh check (recommended: keep as written); 2. SendMessage continuations stay as they are (recommended: keep as written)
    - Unchecked checklist items: none
- [x] 3 Plan — merged with 4; assumptions needing you: 4, 5; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [hard] — assumption 4 needs you; assumption 5 needs you
    - D1 plan.md: section 1 (harness.md rule); harness.md lines 54-56 — The existing harness.md sentence "A turn ends only at a hard gate, at the final message, or while agents are running; then say which are pending and continue when they report" (lines 54-56) is not reconciled with the new rule — rec: apply
    - D2 plan.md: section 4 (`_parse_session`) — The metric algorithm in plan section 4 is hard to build exactly: `batch_mid`, `armed`, `open_ids` and `firsts` are named, but the plan doesn't say where `tool_result` records are read in `_parse_session` or how records that share one `message.id` are handled — rec: skip (research R5 already states the definition and tests pin it; the implementer can read the loop)
    - D3 spec.md: US2 intro vs FR-003 — The spec says the note tells the user "once per setup" but it prints on every first setup call until the user sets `0` or `1`, which nags the maintainer's every run while undecided — rec: apply
    - answer: approved (user: "ok")
    - outcome: picked D1, D3; rejected D2 (as recommended)
- [x] 3 Plan — amended (D1, D3); assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [soft] — 18 tasks; story.sh: match; analyze ran
- [x] 6 US1 — not verified: none
    - wrote: specs/018-foreground-spawns/tasks.md
- [x] 6 US2 — not verified: none
    - wrote: specs/018-foreground-spawns/tasks.md
    - wrote: tests/preflight/expected/feat-resume-note.out
- [x] 6 US3 — not verified: none
    - wrote: specs/018-foreground-spawns/tasks.md
- [x] 6 Implement [soft] — tasks done: 18 (0 not verified); checks pass
- [x] 7 Code review [soft] — auto-applied C1, R2; skipped P1 (reviewer: "no bottleneck"), R1 (reviewer: "output text is user-visible and tested only by wording in the contract; a judgement call, not worth a re-golden")
    - P1 .apm/skills/feat/scripts/measure.py:597-660 — none: the added per-message work in `_parse_session` is a set update and one `any()` over a message's tool uses, linear in the transcript, no new I/O; preflight adds one string test and one emit — rec: skip (no bottleneck)
    - C1 .apm/skills/feat/scripts/measure.py:73-78 — shrink: the spawn-batch block tests `as_str(b.get("name")) in WAIT_TOOLS` twice (once in `any`, once in the comprehension); compute the waiting ids once, `waits = [as_str(b.get("id")) for b in uses if as_str(b.get("name")) in WAIT_TOOLS]`, then `if waits:` and `open_ids.update(waits)` — rec: apply
    - R1 install.sh:138 — The `install.sh check` note line is one 330-character string carrying the setting, the file, the "run from a Claude Code session" caveat and the docs pointer; split it into a short note plus a second indented hint line or shorten it to the setting and the docs pointer (docs/install.md section 6 already holds the rest) — rec: skip (output text is user-visible and tested only by wording in the contract; a judgement call, not worth a re-golden)
    - R2 .apm/skills/feat/scripts/measure.py:600-603 — The armed/firsts/batch_mid/open_ids state machine has one comment per variable but no line saying how they cooperate; one comment above the four declarations, such as "a batch ends when its last result arrives; the next counted model call is recorded in firsts", would let a new reader follow the loop without opening plan.md — rec: apply
- [x] 7 review fixes — C1 → applied; R2 → applied; performance: none; checks: mise run lint → pass, mise run test:measure → pass, mise run test:preflight → pass, mise run test:step → pass, mise run test:apm → pass; not verified: none
- [x] 8 Ship
