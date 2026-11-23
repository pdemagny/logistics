# Quickstart: validate the spawn inputs file

All checks are offline, from the worktree root.

## 1. The suite

```sh
mise run lint          # shellcheck, the harness grep, /tiny's 200-line cap
mise run test:state    # state.sh inputs: write, rewrite, refusals
mise run test:step     # every spawn with a list, the all-empty case, awkward items
mise run test:tracker && mise run test:spec-number && mise run test:story \
  && mise run test:sizes && mise run test:ship && mise run test:measure
mise run test:apm
```

Expected: all pass (SC-004).

## 2. What tests/step proves

- Every golden with a spawn block (`tests/step/expected/*.out`) holds no
  list key, item or `story.sh output` line (SC-002); `check` fails
  otherwise.
- Every `inputs:` path is its block's `report:` path with `.in.md`
  (FR-004), and the files' content equals `expected/<case>.in` (SC-001).
  Review the regenerated goldens with `git diff tests/step/expected`: each
  removed list line of a `.out` reappears in the matching `.in`, unindented
  for keys, otherwise byte for byte.
- The all-empty case prints no `inputs:` line and leaves no `*.in.md` in
  `reports/` (SC-003).
- The awkward case's item (`'`, `$(…)`, a backtick, a leading `-`) is in
  the file unchanged (FR-008).
- The twice-printed case's file equals its golden, not twice its content
  (FR-006).

## 3. By hand, once

```sh
bash tests/step/run.sh            # passes
grep -c '' tests/step/expected/*.in | head
```

After the first real `/feat` run on the merged change: scan the
coordinator's Agent and SendMessage prompts in the session log for any
list item text from the run's `.in.md` files; expect none (SC-005).
