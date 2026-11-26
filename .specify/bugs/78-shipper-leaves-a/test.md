# Bug Verification: Shipper leaves a Monitor running after its report

- **Slug**: 78-shipper-leaves-a
- **Tested**: 2026-11-26
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The live symptom (a Monitor re-waking the finished shipper) cannot be reproduced here: it needs a real ship phase with a multi-minute suite. The fix was checked statically and the project checks pass, so the result is partial.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | live ship phase with a multi-minute suite | not-run | needs a live agent run; depends on model tool choice |
| Static diff review | `git diff` of both agent files | pass | step 4 (shipper) and step 2 (implementer) give the long-check rule; `Monitor` is in both `disallowedTools` |
| Grep for Monitor | `grep -rn Monitor .apm/agents` | pass | only the deny entries and the "never with Monitor" rule |
| New / updated tests | none added (Monitor denied in two agents only) | skipped | lint loop not extended, per the user's answer |
| Regression suite | `mise run test:apm` | pass | exit 0 |
| Lint | `mise run lint` | pass | exit 0 |

## Output Excerpts

- `mise run lint` exit 0; `mise run test:apm` exit 0.

## Residual Risks

- The live behaviour (no Monitor left behind, no re-wake) is unverified.
- Claude Code's own re-wake on leftover Monitor events stays (reported upstream).
- Other agents still allow Monitor.

## Recommendation

Hold for the live check: the prompt and tool-deny changes are in place and the checks pass, but the end-to-end effect needs a real ship phase to confirm.
