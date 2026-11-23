# Bug Assessment: the scan misses keys
- **Slug**: `29-key-scan`
The scan flags a line holding @private-key@ as a key.
- **Verdict**: valid
- **Severity**: low
## Symptom
A key with its headers and no end line, prose right after it:
@private-key@
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-128-CBC,0A1B2C3D4E5F
MIIEowIBAAKCAQEA0Zq81mXv0Lw3NcR7tYp2Ue5Ha
kept: the line after the body
## Reproduction
Mention @private-key@ in a list:
- @private-key@
## Suspected Code Paths
## Root Cause Hypothesis
## Proposed Remediation
## Open Questions
None.
