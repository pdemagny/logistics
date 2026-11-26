# Bug Verification: Agents say their preloaded skills run without the Skill tool

- **Slug**: 103-fix-agents-say
- **Tested**: 2026-11-26
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The static reproduction no longer holds: all three agents now say their `skills:` entries are preloaded and run without the Skill tool, the hooks sentence is scoped to hooks and other skills, and the tasker's `Analyze: not run (<why>…)` must name the real command and error. The model's behaviour was not re-run (prompt-only fix); lint and test:apm pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `grep -rn -i preload .apm/agents/` | pass | Now matches in feat-tasker, feat-specifier and feat-planner |
| Hooks sentence | read `git diff` | pass | "`Skill` is denied, so you can't run hooks or other skills… doesn't touch your preloaded skills" in all three |
| Tasker `<why>` | read `git diff` | pass | `<why>` names the command run and its error, or where you stopped, never a choice to skip |
| Lint | `mise run lint` | pass | exit 0 |
| APM tests | `mise run test:apm` | pass | exit 0 |

## Output Excerpts

lint exit 0; test:apm exit 0.

## Residual Risks

- Whether a model stops skipping the skills depends on its reading of the prompt; not exercised.
- No lint guards the preload sentence (a follow-up noted in fix.md).

## Recommendation

Close the bug: the wording fix is verified statically.
