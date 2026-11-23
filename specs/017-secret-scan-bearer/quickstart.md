# Quickstart: validating secret-scan-bearer

Run everything from the worktree root.

## Checks

```sh
mise run lint
mise run test:secret-scan   # case 10: the three shapes and their near misses; case 7 now reports jwt
mise run test:trail         # every rule has a sample; the per-rule loop; the new redact case; the goldens
mise run test:ship
mise run test:tracker
mise run test:apm
```

All of them pass. In `tests/trail/expected/`, `git diff` shows only the
three added lines in `redact-rules.md`.

## False-positive pass (FR-012)

Tracked text files (exit 1, no output):

```sh
git grep -n -I -E -e '(^|[^A-Za-z0-9_-])[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{16,}' -e 'ey[J][A-Za-z0-9_-]{7,}[.][A-Za-z0-9_-]{10,}[.]' -e '[A-Za-z][A-Za-z0-9+.-]{0,31}://[^/:@[:space:]]+:[^/@[:space:]<{$][^/@[:space:]]{5,}@'
```

This run's own artifacts: run the same three `-e` patterns with
`grep -rnE` over `specs/017-secret-scan-bearer`, `specs/briefs/secret-scan-bearer.md`
and `.specify/bugs/83-secret-scan-bearer`. Then run them with `grep -E` over
`git log --format=%B origin/main..HEAD` for the commit messages. Expected: no
hit. Record the result (or any intended hit) in the PR body.

## Manual spot check

Source `.apm/skills/feat/scripts/secret-scan.sh` in a bash shell and call
`secret_line_rule` on an `Authorization: Bearer` line built by
concatenation. Expect a return of 0 and `SECRET_RULE=bearer-token`. Write
that line to a file under the system temp dir and run
`bash .apm/skills/feat/scripts/trail.sh redact <file>`. Expect it to print
`1` and leave `Authorization: <redacted>` in the file.
