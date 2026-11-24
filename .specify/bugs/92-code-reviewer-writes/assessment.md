# Bug Assessment: Code reviewer writes sections of lenses it was not given; parser and reformat name the wrong line

- **Slug**: 92-code-reviewer-writes
- **Created**: 2026-11-24
- **Source**: pasted text (pdemagny/logistics#92, https://github.com/pdemagny/logistics/issues/92; host github.com, allowlisted; fetched with `gh issue view`)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

Issue #92, "Code reviewer writes sections for lenses it was not given, and step.sh/reformat cannot say why" (author: OWNER).

In a `/feat` run a phase 7 code reviewer given lenses `7a+7b` also wrote `Performance (7c): none`, `Cuts (7d): none`, `net: lean already` and `Readability (7e): none`. `step.sh` rejected it with `unparsable: 7-7a+7b.md: line 26 (Accepted design findings built (7b)) — not a "- " item at column 0`. The reformat turn rewrote the same content and failed the same way, so the run reached the gate with the report still unparsable.

Expected: the reviewer writes only its lenses' sections; failing that, the parser and the reformat turn name the real rule so one reformat fixes it.

Suggested fix in the report: (1) say "omit the sections of lenses you were not given" in the agent and show a `7a+7b` example; (2) in `parse()`, report `section of a lens not given (7c)` on the stray line; (3) put the lens list and "remove sections outside these lenses" into the reformat prompt. Related, closed: #82, #73.

## Symptom

A code reviewer writing `<Key>: none` sections for lenses outside its group gets an unparsable report whose reason names the previous, well-formed field (`Accepted design findings built (7b)`) as "not a "- " item at column 0"; the reformat turn, told only to fix that line, copies the stray sections back and the report stays unparsable. Expected: the stray section is named as such and one reformat removes it.

## Reproduction

1. Write a code-reviewer report for lenses `7a+7b` holding every 7a/7b section as `<Key>: none`, followed by `Performance (7c): none`, `Cuts (7d): none`, `net: lean already`, `Readability (7e): none`, `Dismissed: none`, `Wrote:` and one item.
2. Source `.apm/skills/feat/scripts/step.sh` (it runs `main` only when executed) and call `parse <report> code-reviewer 7a+7b; validate code-reviewer 7a+7b; unparsable_reason`.
3. Observed (run in this assessment): `UR=7-7a+7b.md: line 7 (Accepted design findings built (7b)) — not a "- " item at column 0` (line 7 is the `Performance (7c): none` line, the key named is the 7b field above it). With mode `7a+7b+7c` the failure moves to line 8 and names `Performance (7c)`. The same report without the 7c/7d/7e/net lines parses clean (`P_BAD=0`).

## Suspected Code Paths

- `.apm/agents/feat-code-reviewer.agent.md:209-211` — "Only the sections of your lenses, each present" is the only rule; nothing says to omit the others.
- `.apm/agents/feat-code-reviewer.agent.md:222-245` — the format block lists every lens's section with no example of a group that leaves sections out, so a reviewer fills them all with `none`.
- `.apm/agents/feat-code-reviewer.agent.md:182-188` — reformat mode says to fix the named line and "change nothing else"; it never says to drop sections outside the spawn's `lenses:`, so with a reason naming a well-formed field the agent keeps the stray lines.
- `.apm/skills/feat/scripts/step.sh:926-936` (`schema()`, code-reviewer) — only the keys of the report's lenses enter `SCH_K`.
- `.apm/skills/feat/scripts/step.sh:979-986` (`pkey()`) and `1026-1075` (`parse()`) — a line is a header only if `pkey` finds it in `SCH_K`; a known key of another lens falls through to the continuation branch and `pbad "$n" "${PK[CUR]}" "$line" 'not a "- " item at column 0'` (line 1073) names the open field instead of the stray section.
- `.apm/skills/feat/scripts/step.sh:1501-1540` (`reformat()`) and `1553-1574` (`spawn_group`) — the reformat spawn already carries `lenses:`, `from:` and `unparsable:`; the only lens-related guidance it lacks is the rule, which lives in the agent file.
- `tests/step/run.sh` (code-reviewer cases ~1188, 1335-1444) and `tests/step/fixtures/agents/code-reviewer/` — no fixture covers a section of a lens outside the group.

## Root Cause Hypothesis

Two faults compound. The agent prompt shows one format block with every lens section and only a terse "Only the sections of your lenses" rule, so a reviewer of `7a+7b` writes `none` sections for 7c/7d/7e too. `parse()` then has no notion of "a known key of another lens": `pkey()` searches only the current group's schema, so the stray header is treated as a continuation line of the open field and reported against that field with a generic reason. The reformat turn, guided by a reason that points at a well-formed field and told to change nothing else, reproduces the stray lines. Confidence: high (reproduced with `parse()` directly; the code paths match).

## Proposed Remediation

**Preferred**: Fix all three layers together.

1. `parse()`: when `pkey()` finds no key, test the line against the code-reviewer keys of every lens (a small table of `<Key> → lens`, or `schema code-reviewer 7a+7b+7c+7d+7e` kept in a second array); if it matches a key of a lens not in the mode, `pbad` on that line with that key and the fixed reason `a section of a lens not given (<lens>)`. This gives `7-7a+7b.md: line 7 (Performance (7c)) — a section of a lens not given (7c)`. `net` maps to 7d. Only the code-reviewer agent needs this; other agents keep their current path.
2. `feat-code-reviewer.agent.md` report section: say plainly to omit the sections of lenses you were not given (never write them as `none`), and show a short `7a+7b` example after the full block. In reformat mode, add: remove every section outside the spawn's `lenses:`.
3. The reformat prompt already carries `lenses:` (spawn_group); with (1) and (2) no new step.sh key is needed. If the coordinator's reformat message is built from those keys, nothing in the skills changes.

**Alternatives**:
- Have `parse()` skip (ignore) sections of other lenses written as `none`: fixes the run with no reformat, but loosens the fail-closed parser and hides the prompt slip; a stray section with items would still need a rule.
- Add a new `drop:` key to the reformat spawn block listing the lenses to remove: explicit, but changes the spawn format the coordinators and tests read, for what the existing `lenses:` key and a sharper reason already give.

**Files likely to change**:
- `.apm/agents/feat-code-reviewer.agent.md`
- `.apm/skills/feat/scripts/step.sh`
- `tests/step/run.sh`
- `tests/step/fixtures/agents/code-reviewer/bad-7a+7b-stray-7c.md` (new)
- `tests/step/expected/…` (the expected output for the new case, if the case uses a golden file)

**Tests to add or update**:
- A `tests/step` case: a `7a+7b` report with `Performance (7c): none` etc. gives `reformat` with `unparsable: 7-7a+7b.md: line <n> (Performance (7c)) — a section of a lens not given (7c)` and `unparsable line:` showing that line.
- A case for a stray `net:` line in a group without 7d naming lens 7d.
- Existing code-reviewer cases (`7a+7b+7c-plain`, `bad-7c-slip`, the 7c+7d+7e ones) stay green.

## Risks & Considerations

- `step.sh` must stay Bash 3.2, no jq or Python, shellcheck clean; `mise run lint` and `mise run test:step` gate it.
- `/fix` phase 4 also spawns `feat-code-reviewer`, with rows `4a…` mapped from lenses `7a…` by `lens_rows`; the lens keys in the report are the same, so the new check applies there too. Verify a `/fix` reviewer case.
- `/tiny` spawns the same agent with lens 7a; its prompt text may quote the report rule and should be checked when the agent text changes (CLAUDE.md).
- The new reason is fixed words, never quoting the line (the `P_WHY` contract).
- No security, data or concurrency exposure: report parsing in a local harness.

## Open Questions

- Should a stray section be accepted silently when it is `<Key>: none` (no reformat) rather than reported? Recommended: no, report it; the parser stays fail-closed and the sharper reason makes one reformat enough.
