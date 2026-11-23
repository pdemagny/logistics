# Contract: the review diff file and the new spawn keys (`step.sh`)

## `reports/review.diff`

- Written at each code review boundary that spawns reviewers: `/feat` 7
  (7a–7d batch, and 7e), `/fix` 4. Path: `<artifact dir>/reports/review.diff`,
  beside the batch's report paths; ignored by `reports/.gitignore` (`*`) and
  left out of `state.sh snapshot`.
- Content: `git -C <top> diff --no-color --no-ext-diff <base> --`, `<base>`
  being the merge-base `diff_prep` computes; byte-equal to the `diff: git
  diff <base>` command's output run at the top level. Written through a temp
  file and `mv -f`; a symlink at the path is a `step: error:`.
- Rewritten at every such boundary. An empty diff (the `empty diff` hard
  gate, no spawn) writes nothing.

## Spawn block keys

Every `feat-code-reviewer` block, after `diff:`:

```text
  diff: git diff <base>
  diff file: <artifact dir>/reports/review.diff
```

Not written to the `inputs:` file (a single value). The design reviewers
(`/feat` 4) get neither key.

`/fix` spawns of `feat-bug-assessor` (assess, test) and `feat-implementer`
in bug mode, after their existing keys:

```text
  trail script: <step.sh's dir>/trail.sh
```

## `feat-code-reviewer`

Takes `diff file:` or `diff:`. With a file: reads it (in parts when long),
runs no git command to find the diff. Without one (`/tiny`): runs the
command. Reads the tree in both cases to verify each finding. The report
format is unchanged.
