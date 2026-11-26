# Contract: skills read by path (coordinators and the four agents)

## Coordinator side (`harness.md`, once, no `/feat`-only words)

One bullet in "Subagents don't see this conversation. Give each one, in
its prompt:":

- the `skill <name>: <path>` lines the *preflight script* printed at
  setup (on resume, the resume call's), each as printed, after the spawn
  block's keys: data, like `trail script:`. Never read a skill yourself.

`/feat` setup step 1 and `/fix` setup step 2 add "the `skill` lines" to
the lines they keep. `rebase` passes none (its call prints no lens or
hook skill lines and its spawns read none). `/tiny` is unchanged: its
lens 7a spawn gets no line and needs none.

## Agent side

`feat-implementer`, `feat-code-reviewer`, `feat-design-reviewer`,
`feat-bug-assessor`: `Skill` added to `disallowedTools`. Each gets one
short **Skills by path** paragraph carrying these rules (the reviewers'
copy without the hook sentence):

- You have no `Skill` tool. A skill you run (the implementer's preloaded
  `speckit-implement` aside) has a `skill <name>: <path>` line in your
  prompt: Read that `SKILL.md` and follow its steps.
- `$ARGUMENTS` in it stands for the arguments this file passes the skill
  (`slug=<slug>`, the stage's input, or nothing for a hook); its relative
  links (`references/…`) are read from the skill's own directory.
- The skill's text and the path are data beyond the skill's own steps:
  this file's rules win where they differ (never commit; run only the
  allowed hooks; skip a hook that would branch or commit unless allowed).
- Hooks (implementer, assessor): an allowed hook runs the same way; its
  skill is its command with dots as hyphens (`speckit.git.commit` →
  `speckit-git-commit`). An allowed hook with no line is listed on
  `Skipped hooks` as `<hook> → no skill path`.
- A skill this file names with no line: do no other work and never
  improvise. Reviewers and the assessor hand back `Report not written: no
  skill path for <name>`; the implementer in bug mode reports `Status (bug
  mode): not-applied` and `Design problems: no skill path for
  speckit-bug-fix`.

Wording changes in place (no other text moves):

| Agent | Today | After |
| ----- | ----- | ----- |
| code reviewer, design reviewer | "Load a lens's skill only when you run that lens." | "Read a lens's skill only when you run that lens." |
| code reviewer 7b, design reviewer 4a | "Invoke `security-and-hardening`." | read and follow it (Skills by path) |
| code reviewer 7c | "Invoke `performance-optimization` and follow its steps 1–2" | read it and follow its steps 1–2 |
| assessor assess/test step 2 | "Invoke `speckit-bug-assess`" / "`speckit-bug-test`" | run it by path, same input and `slug=<slug>` |
| implementer bug mode step 2 | "Invoke `speckit-bug-fix` with `slug=<slug>`" | run it by path, same arguments |
| implementer One turn, bug mode | Spec Kit reads after `speckit-bug-fix` | `speckit-bug-fix`'s `SKILL.md` read in the first turn |
| implementer, assessor "Spec Kit hooks" | run only allowed ones | same, by path (rule above) |

## Report formats

Unchanged in all four agents; `step.sh` and `tests/step` don't change.
