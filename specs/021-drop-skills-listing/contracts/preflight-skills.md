# Contract: `preflight.sh` skill lines and stops

Mode 1 only (`preflight.sh <feat|fix> [<argument>]`); worktree mode is
unchanged. Everything else in its output contract stays as it is.

## New output lines

```
skill <name>: <absolute path to SKILL.md>
```

- One line per skill, each skill once (a hook whose skill is already
  listed adds no line).
- Key order: after `hooks allowed:`, before `slug:`. Within the key: the
  lens skills (`security-and-hardening`, `performance-optimization`), then
  (`/fix`) `speckit-bug-assess`, `speckit-bug-fix`, `speckit-bug-test`,
  then hook skills in `.specify/extensions.yml` order.
- `<path>` is `<top>/.claude/skills/<name>/SKILL.md` when that file exists,
  else `$HOME/.claude/skills/<name>/SKILL.md` when that one does. Nothing
  else is searched.

| Kind           | Lens skills | Bug skills (`/fix`) | Hook skills |
| -------------- | ----------- | ------------------- | ----------- |
| brief, issue, symptom, resume | yes | yes | yes |
| rebase         | no          | yes                 | no          |
| empty, refused | no (no install check) | no        | no          |

Hook skills: each hook printed on `hooks allowed:` must resolve; each
hook printed on `hook would branch or commit:` gets a line when its skill
is found and nothing otherwise; a `hook won't run:` hook gets none. A
hook's skill name: research R1.

## New stops (exit 1, last line `stop: …`)

Lens (in the install step, before the board check):

```
stop: skills not installed: <name>[, <name>] (searched <top>/.claude/skills and ~/.claude/skills; a skill only a plugin provides isn't found): npx -y skills@1.7.6 add https://github.com/addyosmani/agent-skills/tree/0.6.13/skills -s interview-me security-and-hardening performance-optimization -a claude-code -g -y
```

Bug (`/fix`, replaces today's bug-extension stop; same command):

```
stop: the bug extension is missing (<name>[, <name>] not found): run specify extension add bug in this project
```

Hooks (in the hooks step, after every hook is sorted):

```
stop: allowed hooks whose skill isn't installed: <key>: <label> (<skill name> not found | maps to no skill)[, …]: install the skill, or disable the hook in .specify/extensions.yml (enabled: false on its entry)
```

`<key>: <label>` is the hook as `hooks allowed:` prints it
(`after_implement: docs.speckit.docs.update`).

The install line in the lens stop is `docs/install.md`'s line, as it is;
adding or removing a third-party skill updates both (`.claude/CLAUDE.md`).

## Unchanged

- `install: ok` and `bug extension: <version>` lines, the hook gate's
  lines (`hook won't run:`, `hook would branch or commit:`, `hooks
  allowed:`), every other key, exit codes, nothing on stderr.
- Bash 3.2, no jq, no Python, shellcheck clean; values read from files are
  never evaluated.
