# Bug Assessment: the scan misses keys

- **Slug**: `29-key-scan`
- **Verdict**: valid

The scan flags a line holding @private-key@ as a key.

## Root Cause Hypothesis

The rule reads one line at a time.

## Proposed Remediation

Read the block.

## Open Questions

None.
