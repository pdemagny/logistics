# Data model: drop the skills listing

No stored data changes: no state-file field, no `sizes.json` change, no
report-format change. Two values move between existing parts.

## Skill path line

- Form: `skill <name>: <path>` (`contracts/preflight-skills.md`).
- `<name>`: a skill directory name, `[A-Za-z0-9-]` (lens and bug names
  are fixed in `preflight.sh`; a hook's comes from its command, research
  R1).
- `<path>`: absolute, ends `/<name>/SKILL.md`, the first of
  `<top>/.claude/skills`, `$HOME/.claude/skills` that has the file.
- Lifecycle: printed by `preflight.sh` mode 1 at setup (and on resume);
  kept by the coordinator for the run; copied into every spawn's prompt;
  read by an agent only when it runs that skill. Never written to a file.

## Needed skills

| Set | Members | Needed by | Missing → |
| --- | ------- | --------- | --------- |
| Lens | `security-and-hardening` (4a, 7b), `performance-optimization` (7c) | design and code reviewers | setup stop, install line |
| Bug (`/fix`) | `speckit-bug-assess`, `speckit-bug-test` (assessor), `speckit-bug-fix` (implementer, bug mode) | `/fix` | setup stop, `specify extension add bug` |
| Hook | one per allowed hook (`/feat`: `implement`; `/fix`: all) | implementer, assessor | setup stop, disable in `.specify/extensions.yml` |
| Flagged hook | one per would-branch-or-commit hook in scope | same, if the user allows it | no stop; line only when found |

`speckit-implement` stays preloaded (`skills:`) and is not resolved.
