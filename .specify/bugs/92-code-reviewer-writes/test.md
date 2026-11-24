# Bug Verification: Code reviewer writes sections of lenses it was not given; parser and reformat name the wrong line

- **Slug**: 92-code-reviewer-writes
- **Tested**: 2026-11-24
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The original symptom no longer reproduces. A `7a+7b` code-reviewer report holding `Performance (7c): none`, `Cuts (7d): none`, `net: lean already` and `Readability (7e): none` now fails with `line 7 (Performance (7c)) — a section of a lens not given (7c)` instead of blaming `Accepted design findings built (7b)`. The same input against the unfixed main checkout's step.sh still gives the old reason (`line 7 (Accepted design findings built (7b)) — not a "- " item at column 0`). A stray `net:` line names lens 7d, a stray section with items is named the same way, and a clean `7a+7b` report still parses. `mise run test:step` and `mise run lint` pass, and shellcheck is clean on step.sh and tests/step/run.sh. The agent prompt now says to omit other lenses' sections and shows a `7a+7b` example, and reformat mode says to remove every section outside `lenses:`.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | scratch script under the system temp dir sources the worktree's step.sh and calls `parse <report> code-reviewer 7a+7b; validate; unparsable_reason` on the issue's report | pass | `line 7 (Performance (7c)) — a section of a lens not given (7c)` |
| Reproduction (pre-fix control) | same scratch script against the main checkout's step.sh (no `pstray`) | fail, as expected | `line 7 (Accepted design findings built (7b)) — not a "- " item at column 0`: the symptom is real and the fix removes it |
| Stray `net:` | `7a+7b` report with only a `net: lean already` line | pass | `line 7 (net) — a section of a lens not given (7d)` |
| Stray section with items | `7a+7b` report with `Performance (7c):` and one `- ` item | pass | named the same way, on the header line |
| Other direction | `7c+7d+7e` report with a `Bugs (7a): none` line | pass | `line 5 (Bugs (7a)) — a section of a lens not given (7a)` |
| Wider mode | the issue's report parsed as `7a+7b+7c` | pass | failure moves to `Cuts (7d)`, lens 7d, line 8 |
| Clean group | well-formed `7a+7b` report with no stray lines | pass | `P_BAD=0` |
| New tests | `mise run test:step` (cases `format: code reviewer bad-stray-7c`, `bad-stray-net`, their `-hard` goldens) | pass | `step: all cases pass`; goldens reviewed: reformat spawn carries `lenses: 7a+7b`, `from:`, and the new `unparsable:` reason, and `unparsable line:` shows the stray line |
| Regression suite | `mise run test:step` | pass | existing code-reviewer cases (`7a+7b+7c-plain`, `bad-7c-slip`, `7c+7d+7e-*`, `/fix` 4's `4-7a+7b`) stay green |
| Lint / shellcheck | `mise run lint`; `shellcheck` on step.sh and tests/step/run.sh | pass | exit 0 |
| Agent prompt | read the diff of `.apm/agents/feat-code-reviewer.agent.md` | pass | omit rule (net: included), `7a+7b` example, reformat-mode rule; `/tiny` does not quote the report rule |

## Output Excerpts

```
post-fix:  7a+7b issue.md: line 7 (Performance (7c)) — a section of a lens not given (7c)
pre-fix:   7a+7b issue.md: line 7 (Accepted design findings built (7b)) — not a "- " item at column 0
net:       line 7 (net) — a section of a lens not given (7d)
[test:step] $ bash tests/step/run.sh
step: all cases pass
```

## Residual Risks

- The agent prompt wording (omit rule, example, reformat rule) cannot be exercised without spawning the reviewer; only its text was read, not its behaviour.
- A line inside a field that begins with another lens's key (`Cuts (7d): ...`) now fails the report whatever its position; this is the intended fail-closed behaviour.
- My scratch `net:` line in a `7c+7d+7e` report used a free-text value and was rejected as `a value outside its format`; that is the existing `net` format rule, unrelated to this fix.
- No source file was edited; scratch files live under the system temp dir.

## Recommendation

Close the bug: verified. The reproduction fails without the fix and passes with it, and the project's checks pass.
