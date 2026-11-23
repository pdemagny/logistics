# Multi-line values (contract rule 2)

config:
  @pw@: |
    first hidden line
    second hidden line

    after a blank line, still the value
  next: kept

@sec@: >-  # folded
  folded hidden words
kept at column 0
@API@="first part
middle part
last part" # tail
@tok@='never closed
runs on

kept after the blank line
@pw@: |
  <redacted>
@pw@: |
kept: an empty block scalar
