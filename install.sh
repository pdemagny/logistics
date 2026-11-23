#!/usr/bin/env bash
# Developer install of the feat skills and feat-* subagents into Claude Code:
# symlinks into this repo, so edits apply at once. Users install with APM or
# the Claude Code plugin instead (docs/install.md); `check` works for all three.
#
#   ./install.sh [install] [--copy] [--target DIR]   link (or copy) skills + agents
#   ./install.sh deps                                install the third-party skills
#   ./install.sh check [PROJECT_DIR]                 report what is missing
#   ./install.sh uninstall [--target DIR]            remove what install created
#
# --target defaults to ~/.claude (user level). Pass a project's .claude
# directory to install for that project only.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$HOME/.claude"
mode="link"
cmd=install
project=""

# Third-party skills, all from one repo. Keep in sync with apm.yml.
# Same repo and tag as apm.yml's dependencies; skills CLI pinned too.
deps_src="https://github.com/addyosmani/agent-skills/tree/0.6.13/skills"
deps=(interview-me security-and-hardening performance-optimization)
# Installed per project by `specify init --integration claude`.
speckit_skills=(speckit-specify speckit-clarify speckit-plan speckit-tasks speckit-analyze speckit-implement)
# Spec Kit's bug extension, per project by `specify extension add bug`; /fix only.
# The headings and verdict words /fix relies on, as recorded for this version
# (specs/002-fix-workflow/contracts/bug-extension.md).
bug_version="1.0.1 and 1.0.2"
bug_skills=(speckit-bug-assess speckit-bug-fix speckit-bug-test)
bug_words_assess=("# Bug Assessment:" "**Verdict**" "**Severity**" "## Symptom" "## Reproduction"
  "## Suspected Code Paths" "## Root Cause Hypothesis" "## Proposed Remediation" "## Open Questions"
  "likely valid, needs reproduction" "invalid")
bug_words_fix=("# Bug Fix:" "**Status**" "## Deviations from Assessment" "applied" "partial" "not-applied")
bug_words_test=("# Bug Verification:" "**Result**" "## Checks Performed" "verified" "partial" "failed")
tools=(claude git gh specify)

while [ $# -gt 0 ]; do
  case "$1" in
    install|deps|check|uninstall) cmd="$1" ;;
    --copy) mode=copy ;;
    --target) target="$2"; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [ "$cmd" = check ] && [ -z "$project" ]; then project="$1"
       else echo "unknown argument: $1" >&2; exit 2; fi ;;
  esac
  shift
done

# place SRC DEST: link or copy, backing up anything that isn't already ours.
place() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    echo "ok       $dest"; return
  fi
  if [ -L "$dest" ] && [[ "$(readlink "$dest")" == "$repo"/* ]]; then
    rm "$dest"   # ours, from an older layout of this repo
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    local bak
    # Outside skills/ and agents/: Claude Code would load a backup there as a skill or agent.
    bak="$HOME/.claude/logistics-backups/$(basename "$dest").$(date +%Y%m%d%H%M%S)"
    mkdir -p "$(dirname "$bak")"
    mv "$dest" "$bak"
    echo "backup   $dest -> $bak"
  fi
  if [ "$mode" = link ]; then ln -s "$src" "$dest"; else cp -R "$src" "$dest"; fi
  echo "$mode     $dest"
}

# skill_file NAME: print the path of the first SKILL.md found for NAME.
skill_file() {
  local name="$1" dir
  for dir in "$target/skills" "$HOME/.claude/skills" ${project:+"$project/.claude/skills"}; do
    [ -f "$dir/$name/SKILL.md" ] && { echo "$dir/$name/SKILL.md"; return 0; }
  done
  return 1
}

has_skill() {
  skill_file "$1" >/dev/null
}

# bug_words_found FILE WORD...: how many of the WORDs FILE contains.
bug_words_found() {
  local file="$1" args=() w; shift
  for w in "$@"; do args+=(-e "$w"); done
  { grep -oF "${args[@]}" "$file" || true; } | sort -u | wc -l
}

has_agent() {
  [ -f "$target/agents/$1" ] || [ -f "$HOME/.claude/agents/$1" ] ||
    { [ -n "$project" ] && [ -f "$project/.claude/agents/$1" ]; }
}

# Installed as a Claude Code plugin: its skills and agents live in the plugin cache.
has_plugin() {
  claude plugin list 2>/dev/null | grep -q 'logistics@'
}

case "$cmd" in
  install)
    mkdir -p "$target/skills" "$target/agents"
    for d in "$repo"/.apm/skills/*/; do
      d="${d%/}"
      place "$d" "$target/skills/$(basename "$d")"
    done
    for f in "$repo"/.apm/agents/*.agent.md; do
      place "$f" "$target/agents/$(basename "$f" .agent.md).md"
    done
    echo
    echo "Next: ./install.sh deps (third-party skills), then ./install.sh check <project>"
    ;;

  deps)
    command -v npx >/dev/null || { echo "npx not found: install Node.js first" >&2; exit 1; }
    npx -y skills@1.7.6 add "$deps_src" --skill "${deps[@]}" --agent claude-code --global --yes
    ;;

  check)
    missing=0
    # expect LABEL FIX CMD...: run CMD, report LABEL as ok or missing with FIX.
    expect() {
      local label="$1" fix="$2"; shift 2
      if "$@" >/dev/null 2>&1; then echo "ok       $label"
      else echo "MISSING  $label ($fix)"; missing=1; fi
    }
    for t in "${tools[@]}"; do expect "tool $t" "install it" command -v "$t"; done
    # Not counted as missing: only measure.py needs Python.
    if python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
      echo "ok       python3 3.11 or later (measure.py)"
    else
      echo "note     python3 3.11 or later not found (needed by measure.py only: docs/measure.md)"
    fi
    if [ "${CLAUDE_CODE_FORK_SUBAGENT:-}" = 0 ]; then
      echo "ok       CLAUDE_CODE_FORK_SUBAGENT=0 (agents run in the foreground)"
    else
      echo "note     CLAUDE_CODE_FORK_SUBAGENT is not 0 in this shell: to wait for each agent, add \"env\": {\"CLAUDE_CODE_FORK_SUBAGENT\": \"0\"} to <repo>/.claude/settings.local.json; Claude Code sets it in its own sessions, so run check from one (! ./install.sh check) to see it (docs/install.md section 6)"
    fi
    expect "gh authenticated" "gh auth login" gh auth status
    if has_plugin; then
      echo "ok       plugin logistics (skills and agents)"
    else
      for d in "$repo"/.apm/skills/*/; do
        s="$(basename "$d")"
        expect "skill $s" "see docs/install.md" has_skill "$s"
      done
      for f in "$repo"/.apm/agents/*.agent.md; do
        a="$(basename "$f" .agent.md)"
        expect "agent $a" "see docs/install.md" has_agent "$a.md"
      done
    fi
    for skill in "${deps[@]}"; do
      expect "skill $skill" "APM installs it; plugin or clone: docs/install.md section 2" has_skill "$skill"
    done
    if [ -n "$project" ]; then
      fix="specify init --here --integration claude"
      expect "spec kit in $project" "$fix" test -d "$project/.specify"
      for s in "${speckit_skills[@]}"; do expect "skill $s" "$fix" has_skill "$s"; done
      # Not counted as missing: only /fix needs the bug extension.
      for s in "${bug_skills[@]}"; do
        if ! f="$(skill_file "$s")"; then
          echo "note     skill $s (needed by /fix only: specify extension add bug)"
          continue
        fi
        echo "ok       skill $s"
        case "$s" in
          *-assess) words=("${bug_words_assess[@]}") ;;
          *-fix) words=("${bug_words_fix[@]}") ;;
          *) words=("${bug_words_test[@]}") ;;
        esac
        if [ "$(bug_words_found "$f" "${words[@]}")" -lt "${#words[@]}" ]; then
          echo "warn     $s differs from the names /fix was tested with (bug $bug_version)"
        fi
      done
    else
      echo "skipped  spec kit checks (pass a project dir)"
    fi
    exit "$missing"
    ;;

  uninstall)
    for dest in "$target"/skills/brief "$target"/skills/feat "$target"/skills/fix "$target"/skills/tiny "$target"/skills/feat-* "$target"/agents/feat-*.md; do
      [ -e "$dest" ] || [ -L "$dest" ] || continue
      if [ -L "$dest" ] && [[ "$(readlink "$dest")" == "$repo"/* ]]; then
        rm "$dest"; echo "removed  $dest"
      else
        echo "kept     $dest (not a link into $repo; remove it by hand)"
      fi
    done
    ;;
esac
