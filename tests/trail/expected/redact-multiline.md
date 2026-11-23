# Multi-line values (contract rule 2)

config:
  password: |
    <redacted>
  next: kept

secret: >-  # folded
  <redacted>
kept at column 0
API_KEY=<redacted>
<redacted> # tail
token=<redacted>
<redacted>

kept after the blank line
password: |
  <redacted>
password: |
kept: an empty block scalar
