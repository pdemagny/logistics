#!/usr/bin/env bash
# Setup checks for /feat and /fix, before and after EnterWorktree (contract:
# setup-trail-scripts).
#
#   preflight.sh <feat|fix> [<argument>] [slug=<words>]   mode 1, before EnterWorktree
#   preflight.sh feat worktree <short-name> <on|off>        after EnterWorktree
#   preflight.sh fix worktree <slug> <on|off>
#
# <argument> is $ARGUMENTS as one word (lines joined with spaces); none, or
# an empty one, is kind `empty`. slug=<words> gives a /fix symptom's slug
# words (without it: the symptom's first four words); /fix ignores it for
# any other kind, /feat refuses it. A first word `worktree` selects the
# worktree mode (a brief named `worktree` is given by its path).
#
# Mode 1 classifies the argument (kind: brief, issue, symptom, resume,
# rebase, empty, or a refused one), then runs the steps that kind needs:
# brief lookup and fields, install, board check, default branch and fetch,
# hooks, issue title and author, slug. Worktree mode checks its arguments,
# the bug dir (/fix), renames the branch and checks .logistics.yml; it makes
# no network call.
#
# Output: `key: value` lines on stdout in a fixed order, whatever order the
# steps run in: kind, usage, rebase target, brief, candidate, brief in
# checkout, title, size, size note, short name, map, issue, behaviour,
# acceptance, github, author, install, bug extension, board, default, fetch,
# hook won't run, hook would branch or commit, hooks allowed, slug, pointer,
# searched, stop; worktree mode: worktree, branch, flag. Text read from the
# argument, a brief, an issue or git comes only after its key, on one line,
# control characters replaced by spaces; nothing read is evaluated or
# executed. Nothing on stderr.
#
# Exit 0 go on; 1 stop (the last line is `stop: <why>`); 2 could not run
# (the last line is `preflight: usage: ...` or `preflight: error: <why>`).
set -euo pipefail
export LC_ALL=C

USAGE='preflight.sh <feat|fix> [<argument>] [slug=<words>] | <feat|fix> worktree <short-name|slug> <on|off>'
RE_NAME='^[a-z0-9][a-z0-9-]*$'
RE_OWNER='[A-Za-z0-9][A-Za-z0-9-]*'
RE_REPO='[A-Za-z0-9._-]+'
RE_NUM='[1-9][0-9]*'
RE_VERSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
TAB=$'\t'

# The script's dir as called (logical) and resolved: the agents dir sits
# beside the skills dir, three levels above it, in every install layout
# (APM and install.sh: <base>/.claude/{skills,agents}; the plugin:
# <plugin>/.apm/{skills,agents}).
SDIR_L="$(cd -L -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -L)"
SDIR_P="$(cd -P -- "$SDIR_L" && pwd -P)"

# --- output ----------------------------------------------------------------------

# OUT is indexed by <key's slot> * 1000 + <sequence>, so its lines come out in
# the contract's key order, and in emit order within a key.
OUT=()
SEQ=0

slot() {
  case "$1" in
    kind) S=1 ;; usage) S=2 ;; 'rebase target') S=3 ;; brief) S=4 ;; candidate) S=5 ;;
    'brief in checkout') S=6 ;; title) S=7 ;; size) S=8 ;; 'size note') S=9 ;;
    'short name') S=10 ;; map) S=11 ;; issue) S=12 ;; behaviour) S=13 ;; acceptance) S=14 ;;
    github) S=15 ;; author) S=16 ;; install) S=17 ;; 'bug extension') S=18 ;; board) S=19 ;;
    default) S=20 ;; fetch) S=21 ;; "hook won't run") S=22 ;; 'hook would branch or commit') S=23 ;;
    'hooks allowed') S=24 ;; slug) S=25 ;; pointer) S=26 ;; searched) S=27 ;; stop) S=99 ;;
    worktree) S=29 ;; branch) S=30 ;; flag) S=31 ;;
    *) S=98 ;;
  esac
}

# emit <key> <value>: one output line, control characters in the value
# replaced by spaces
emit() {
  slot "$1"
  SEQ=$((SEQ + 1))
  OUT[S * 1000 + SEQ]="$1: ${2//[[:cntrl:]]/ }"
}

flush() {
  local l
  for l in ${OUT[@]+"${OUT[@]}"}; do printf '%s\n' "$l"; done
  OUT=()
}

# stop <why>: what was found, then `stop: <why>`; exit 1
stop() {
  emit stop "$1"
  flush
  exit 1
}

# die_usage [<why>]: exit 2 with one usage line and nothing else
die_usage() {
  printf 'preflight: usage: %s\n' "${1:-$USAGE}"
  exit 2
}

# die_error <why>: what was found, then `preflight: error: <why>`; exit 2
die_error() {
  flush
  printf 'preflight: error: %s\n' "${1//[[:cntrl:]]/ }"
  exit 2
}

tmp=""
cleanup() { if [ -n "$tmp" ]; then command rm -rf -- "$tmp"; fi; }
trap cleanup EXIT
mktmp() { [ -n "$tmp" ] || tmp="$(mktemp -d)" || die_error "mktemp failed"; }

# trim <text>: T = the text without leading and trailing whitespace
trim() {
  T="${1#"${1%%[![:space:]]*}"}"
  T="${T%"${T##*[![:space:]]}"}"
}

# first_line <text>: L = its first non-empty line
first_line() {
  local l
  L=""
  while IFS= read -r l; do
    if [ -n "$l" ]; then L="$l"; return 0; fi
  done <<<"$1"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# join <item>...: the items separated by `, `
join() {
  local out="$1"
  shift
  while [ "$#" -gt 0 ]; do out="$out, $1"; shift; done
  printf '%s' "$out"
}

# abs_file <path>: P = the file's absolute path, its dir resolved
abs_file() {
  local d
  d="$(cd -P -- "$(dirname -- "$1")" && pwd -P)"
  P="$d/$(basename -- "$1")"
}

# --- classification --------------------------------------------------------------

# issue_ref <text>: 0 when it is a GitHub issue reference whose parts pass
# the checks; IO, IR (empty for #N) and IN set
issue_ref() {
  IO="" IR="" IN=""
  if [[ $1 =~ ^#($RE_NUM)$ ]]; then
    IN="${BASH_REMATCH[1]}"
  elif [[ $1 =~ ^($RE_OWNER)/($RE_REPO)#($RE_NUM)$ ]]; then
    IO="${BASH_REMATCH[1]}" IR="${BASH_REMATCH[2]}" IN="${BASH_REMATCH[3]}"
  elif [[ $1 =~ ^https://github\.com/($RE_OWNER)/($RE_REPO)/issues/($RE_NUM)(/|[#?][^[:space:]]*)?$ ]]; then
    IO="${BASH_REMATCH[1]}" IR="${BASH_REMATCH[2]}" IN="${BASH_REMATCH[3]}"
  else
    return 1
  fi
  [ "$IR" != . ] && [ "$IR" != .. ]
}

# a /fix argument that is a brief: a ...specs/briefs/<x>.md path, or a file
# whose first line starts `# Brief:`
is_brief_for_fix() {
  local l=""
  [[ $1 =~ (^|/)specs/briefs/[^/]+\.md$ ]] && return 0
  [ -f "$1" ] || return 1
  IFS= read -r l <"$1" || true
  [[ $l == '# Brief:'* ]]
}

# --- brief -----------------------------------------------------------------------

# brief_lookup <argument>: BRIEF = the one matching brief's absolute path;
# several print `brief: several` and exit 0, none stops
brief_lookup() {
  local name w p found=() searched=() i dup
  if [ -f "$1" ]; then
    abs_file "$1"
    BRIEF="$P"
    return 0
  fi
  name="${1#specs/briefs/}"
  name="${name%.md}"
  searched+=("$top/specs/briefs/$name.md")
  while IFS= read -r w; do
    case "$w" in 'worktree '?*) ;; *) continue ;; esac
    w="${w#worktree }"
    [ "$w" != "$top" ] || continue
    searched+=("$w/specs/briefs/$name.md")
  done < <(git -C "$top" worktree list --porcelain 2>/dev/null || true)
  for p in "${searched[@]}"; do
    [ -f "$p" ] || continue
    abs_file "$p"
    dup=0
    for i in ${found[@]+"${found[@]}"}; do [ "$i" != "$P" ] || dup=1; done
    [ "$dup" = 1 ] || found+=("$P")
  done
  case "${#found[@]}" in
    1) BRIEF="${found[0]}" ;;
    0)
      for p in "${searched[@]}"; do emit searched "$p"; done
      emit pointer "/brief"
      stop "no brief named $name in this checkout or its worktrees"
      ;;
    *)
      emit brief several
      for p in "${found[@]}"; do emit candidate "$p"; done
      flush
      exit 0
      ;;
  esac
}

# brief_fields: the header's fields and the sections' line counts of BRIEF
brief_fields() {
  local line sec="" header=1 title="" sizel="" sname="" map="" iss="" nb=0 na=0 hb=0 ha=0
  local word note lacks=() topp
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ $line == '## '* ]]; then
      header=0 sec=""
      if [[ $line =~ ^'## Behaviour'[[:space:]]*$ ]]; then sec=b hb=1; fi
      if [[ $line =~ ^'## Acceptance'[[:space:]]*$ ]]; then sec=a ha=1; fi
      continue
    fi
    if [ "$header" = 1 ]; then
      case "$line" in
        '# Brief:'*) [ -n "$title" ] || { trim "${line#'# Brief:'}"; title="$T"; } ;;
        '- Size:'*) trim "${line#'- Size:'}"; sizel="$T" ;;
        '- Short name:'*) trim "${line#'- Short name:'}"; sname="$T" ;;
        '- Map:'*) trim "${line#'- Map:'}"; map="$T" ;;
        '- Issue:'*) trim "${line#'- Issue:'}"; iss="$T" ;;
      esac
    elif [[ $line =~ [^[:space:]] ]]; then
      case "$sec" in b) nb=$((nb + 1)) ;; a) na=$((na + 1)) ;; esac
    fi
  done <"$BRIEF"

  word="${sizel%%[[:space:]]*}"
  word="$(lower "$word")"
  note="${sizel#"${sizel%%[[:space:]]*}"}"
  trim "$note"
  note="$T"
  case "$note" in '—'* | '–'* | '-'* | ':'*) note="${note#—}" note="${note#–}" note="${note#-}" note="${note#:}" ;; esac
  trim "$note"
  note="$T"

  emit brief "$BRIEF"
  topp="$(cd -P -- "$top" && pwd -P)"
  if [[ $sname =~ $RE_NAME ]] && [ "$BRIEF" = "$topp/specs/briefs/$sname.md" ]; then
    emit 'brief in checkout' yes
  else
    emit 'brief in checkout' no
  fi
  [ -z "$title" ] || emit title "$title"
  case "$word" in
    tiny)
      emit pointer "/tiny $BRIEF"
      emit pointer "/brief $BRIEF"
      stop "the brief is tiny: /tiny makes it, or /brief grows it into a full brief"
      ;;
    huge)
      emit pointer "/brief $BRIEF"
      stop "the brief is huge: /brief splits it into a capability map"
      ;;
    small | medium | large) ;;
    normal) word=medium ;;
    big) word=large ;;
    *) word="" ;;
  esac
  if [ -n "$word" ]; then
    emit size "$word"
    emit 'size note' "${note:-none}"
  else
    lacks+=(size)
  fi
  if [[ $sname =~ $RE_NAME ]]; then emit 'short name' "$sname"; else lacks+=('short name'); fi
  emit map "${map:-none}"
  emit issue "${iss:-none}"
  if [ "$hb" = 1 ]; then emit behaviour "$nb lines"; fi
  if [ "$ha" = 1 ]; then emit acceptance "$na lines"; fi
  [ "$nb" -gt 0 ] || lacks+=(behaviour)
  [ "$na" -gt 0 ] || lacks+=(acceptance)
  if [ "${#lacks[@]}" -gt 0 ]; then stop "brief lacks $(join "${lacks[@]}")"; fi
}

# --- install ---------------------------------------------------------------------

step_install() {
  local agents a d f ok miss=() dirs
  [ -d "$top/.specify" ] || stop ".specify/ is missing: run specify init --here --integration claude"
  if [ "$skill" = feat ]; then
    agents="specifier planner design-reviewer tasker implementer code-reviewer shipper"
  else
    agents="bug-assessor implementer code-reviewer shipper"
  fi
  # three levels up by name: `..` through a symlinked dir would resolve it
  dirs=("${SDIR_L%/*/*/*}/agents" "${SDIR_P%/*/*/*}/agents" "$top/.claude/agents")
  if [ -n "${HOME:-}" ]; then dirs+=("$HOME/.claude/agents"); fi
  for a in $agents; do
    ok=0
    for d in "${dirs[@]}"; do
      for f in "$d/feat-$a.md" "$d/feat-$a.agent.md"; do
        if [ -f "$f" ]; then ok=1; fi
      done
    done
    [ "$ok" = 1 ] || miss+=("feat-$a")
  done
  if [ "${#miss[@]}" -gt 0 ]; then stop "agents not installed: $(join "${miss[@]}") (install or update logistics)"; fi
  if [ "$skill" = fix ]; then
    ok=0
    if [ -d "$top/.specify/extensions/bug" ]; then ok=1; fi
    dirs=("$top/.claude/skills")
    if [ -n "${HOME:-}" ]; then dirs+=("$HOME/.claude/skills"); fi
    for d in "${dirs[@]}"; do
      for a in assess fix test; do
        if [ -d "$d/speckit-bug-$a" ]; then ok=1; fi
      done
    done
    [ "$ok" = 1 ] || stop "the bug extension is missing: run specify extension add bug in this project"
  fi
  emit install ok
  if [ "$skill" = fix ]; then emit 'bug extension' "$(bug_version)"; fi
}

# bug_version: the first two-space `version:` of the column-0 `extension:`
# mapping of the bug extension's extension.yml, else `unknown`
bug_version() {
  local f="$top/.specify/extensions/bug/extension.yml" line in=0 v=""
  if [ -f "$f" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      if [[ $line =~ ^[^[:space:]#] ]]; then
        [ "$in" = 0 ] || break
        if [[ $line =~ ^extension:[[:space:]]*(#.*)?$ ]]; then in=1; fi
        continue
      fi
      if [ "$in" = 1 ] && [[ $line =~ ^'  version:'(.*)$ ]]; then
        v="${BASH_REMATCH[1]}"
        break
      fi
    done <"$f"
  fi
  trim "$v"
  v="$T"
  if [[ $v =~ ^\"([^\"]*)\"([[:space:]]+#.*)?$ ]] || [[ $v =~ ^\'([^\']*)\'([[:space:]]+#.*)?$ ]]; then
    v="${BASH_REMATCH[1]}"
  elif [[ $v =~ ^([^[:space:]#]+)[[:space:]]+# ]]; then
    v="${BASH_REMATCH[1]}"
  fi
  if [[ $v =~ $RE_VERSION ]]; then printf '%s' "$v"; else printf 'unknown'; fi
}

# --- board, base -----------------------------------------------------------------

# step_board: the skill's `tracker.sh check` when .logistics.yml exists; a
# failure stops (the board moves of the run would fail)
step_board() {
  local o rc=0
  if [ ! -e "$top/.logistics.yml" ]; then
    emit board off
    return 0
  fi
  o="$(cd "$top" && bash "$SDIR_L/tracker.sh" check 2>&1)" || rc=$?
  first_line "$o"
  [ "$rc" = 0 ] || stop "board check failed: ${L:-tracker.sh check exited $rc}"
  emit board "${L:-tracker: ok}"
}

# default_branch: DEF = origin's default branch. A copy of step.sh's
# default_branch (.apm/skills/feat/scripts/step.sh, which can't be sourced):
# the name comes from the remote and reaches git, so it must come back
# unchanged from check-ref-format and not start with `-`.
default_branch() {
  local n l c
  n="$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" || n=""
  if [[ $n == origin/?* ]]; then n="${n#origin/}"; else n=""; fi
  if [ -z "$n" ]; then
    l="$(GIT_TERMINAL_PROMPT=0 git -C "$top" ls-remote --symref origin HEAD 2>/dev/null)" || l=""
    while IFS= read -r c; do
      if [[ $c == 'ref: refs/heads/'?*"${TAB}HEAD" ]]; then
        n="${c#'ref: refs/heads/'}"
        n="${n%"${TAB}HEAD"}"
        break
      fi
    done <<<"$l"
  fi
  [[ -n $n && $n != -* ]] || die_error "no default branch found"
  # --branch expands @{-n}: the name must come back unchanged
  c="$(git -C "$top" check-ref-format --branch "$n" 2>/dev/null)" || c=""
  [[ $c == "$n" ]] || die_error "no default branch found"
  DEF="$n"
}

# step_base: the default branch, fetched (a stale base is what the fetch
# prevents, so a failure stops). The refspec is explicit so origin/<default>
# moves whatever the clone's fetch refspec says.
step_base() {
  local err
  default_branch
  emit default "$DEF"
  if ! err="$(GIT_TERMINAL_PROMPT=0 git -C "$top" fetch -q origin "+refs/heads/$DEF:refs/remotes/origin/$DEF" 2>&1)"; then
    first_line "$err"
    stop "git fetch origin $DEF failed: ${L:-git failed}"
  fi
  emit fetch ok
}

# --- hooks -----------------------------------------------------------------------

# Spec Kit's .specify/extensions.yml, read as data: a line reader for the
# subset Spec Kit writes (research R2). Under the column-0 `hooks:` key, event
# keys at one indent, each `{}`, `[]`, `null`, `~`, nothing, or a block
# sequence (indented or at the key's own indent) of mappings; only `extension`,
# `command` and `enabled` are read, other keys and their continuation lines
# are skipped. Other top-level sections are skipped whole. Anything else
# stops: a file it can't read may hide a hook that commits.
RE_KEY='^([A-Za-z_][A-Za-z0-9_-]*):([[:space:]].*)?$'
RE_EVENT='^[a-z][a-z0-9_]*$'
RE_HOOK='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_SQ="^'([^']*)'([[:space:]]+#.*)?\$"
RE_DQ='^"([^"\\]*)"([[:space:]]+#.*)?$'
H_KEY=()
H_EXT=()
H_CMD=()

# scalar <text after the colon>: V = its value, quotes stripped and a trailing
# comment dropped; Q=1 when quoted. Not a scalar the reader takes: 1.
scalar() {
  trim "$1"
  V="$T" Q=0
  if [[ $V =~ $RE_SQ ]] || [[ $V =~ $RE_DQ ]]; then
    V="${BASH_REMATCH[1]}" Q=1
    return 0
  fi
  case "$V" in \'* | \"*) return 1 ;; '#'*) V="" ;; esac
  V="${V%%[[:space:]]#*}"
  trim "$V"
  V="$T"
}

# hooks_bad <line>: stop, naming the source and the line
hooks_bad() {
  stop "$HSRC can't be read as data (line $1); it may hide a hook that commits"
}

# item_close: the open item becomes a hook when enabled
item_close() {
  [ "$ITEM" = 1 ] || return 0
  ITEM=0
  [ -n "$IEXT" ] || hooks_bad "$ILINE"
  [ "$IEN" = 1 ] || return 0
  H_KEY+=("$CUR")
  H_EXT+=("$IEXT")
  H_CMD+=("$ICMD")
}

# item_key <line number> <content>: one `key: value` line of the open item
item_key() {
  local k v
  [[ $2 =~ $RE_KEY ]] || hooks_bad "$1"
  k="${BASH_REMATCH[1]}"
  v="${BASH_REMATCH[2]:-}"
  case "$k" in
    extension | command | enabled) INKEY=1 ;;
    *)
      INKEY=0
      return 0
      ;;
  esac
  scalar "$v" || hooks_bad "$1"
  if [ "$k" = enabled ]; then
    [ "$Q" = 0 ] || hooks_bad "$1"
    case "$(lower "$V")" in
      true | yes | on) IEN=1 ;;
      false | no | off) IEN=0 ;;
      *) hooks_bad "$1" ;;
    esac
    return 0
  fi
  if [ "$Q" = 0 ]; then
    case "$V" in null | Null | NULL | '~') V="" ;; esac
  fi
  [ -z "$V" ] || [[ $V =~ $RE_HOOK ]] || hooks_bad "$1"
  if [ "$k" = extension ]; then IEXT="$V"; else ICMD="$V"; fi
}

# read_hooks <source name>: the hooks on stdin into H_KEY, H_EXT, H_CMD
# (enabled ones only); never evaluates anything it reads
read_hooks() {
  local line content ind n=0 inh=0 hempty=0 E=-1 I=-1 K=-1 seq=0 rest sp
  HSRC="$1" CUR="" ITEM=0 INKEY=0 IEXT="" ICMD="" IEN=1 ILINE=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    content="${line#"${line%%[! ]*}"}"
    ind=$((${#line} - ${#content}))
    if [[ $content =~ ^[[:space:]]*(#.*)?$ ]]; then continue; fi
    # a column-0 key: a top-level section (a column-0 `-` is an indentless
    # sequence of the section above)
    if [ "$ind" = 0 ] && [[ $content != '-' && $content != '- '* ]]; then
      item_close
      [[ $content =~ $RE_KEY ]] || hooks_bad "$n"
      inh=0
      if [ "${BASH_REMATCH[1]}" = hooks ]; then
        scalar "${BASH_REMATCH[2]:-}" || hooks_bad "$n"
        [ "$Q" = 0 ] || hooks_bad "$n"
        case "$V" in
          '') hempty=0 ;;
          '{}' | null | '~') hempty=1 ;;
          *) hooks_bad "$n" ;;
        esac
        inh=1 E=-1 CUR=""
      fi
      continue
    fi
    [ "$inh" = 1 ] || continue
    [ "$hempty" = 0 ] || hooks_bad "$n"
    # deeper than the open item's keys: a continuation of the last key
    if [ "$ITEM" = 1 ] && [ "$K" -ge 0 ] && [ "$ind" -gt "$K" ]; then
      [ "$INKEY" = 0 ] || hooks_bad "$n"
      continue
    fi
    [[ $content != $'\t'* ]] || hooks_bad "$n"
    if [[ $content == '-' || $content == '- '* ]]; then
      [ -n "$CUR" ] && [ "$seq" = 1 ] || hooks_bad "$n"
      if [ "$I" -lt 0 ]; then
        [ "$ind" -ge "$E" ] || hooks_bad "$n"
        I="$ind"
      fi
      [ "$ind" = "$I" ] || hooks_bad "$n"
      item_close
      ITEM=1 ILINE="$n" IEXT="" ICMD="" IEN=1 INKEY=0 K=-1
      rest="${content#-}"
      [ -n "$rest" ] || continue
      sp="${rest%%[! ]*}"
      rest="${rest#"$sp"}"
      [[ $rest != $'\t'* ]] || hooks_bad "$n"
      K=$((ind + 1 + ${#sp}))
      item_key "$n" "$rest"
      continue
    fi
    if [ "$ITEM" = 1 ] && { [ "$ind" = "$K" ] || { [ "$K" -lt 0 ] && [ "$ind" -gt "$I" ]; }; }; then
      K="$ind"
      item_key "$n" "$content"
      continue
    fi
    if [ "$E" -lt 0 ] || [ "$ind" = "$E" ]; then
      E="$ind"
      item_close
      [[ $content =~ $RE_KEY ]] || hooks_bad "$n"
      CUR="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]:-}"
      [[ $CUR =~ $RE_EVENT ]] || hooks_bad "$n"
      scalar "$rest" || hooks_bad "$n"
      [ "$Q" = 0 ] || hooks_bad "$n"
      case "$V" in
        '') seq=1 ;;
        '[]' | '{}' | null | '~') seq=0 ;;
        *) hooks_bad "$n" ;;
      esac
      I=-1 K=-1
      continue
    fi
    hooks_bad "$n"
  done
  item_close
}

# would_commit <extension> <command>: 0 when the names say the hook would
# branch or commit (research R3; names only, the description is not read)
would_commit() {
  local e c w
  e="$(lower "$1")"
  c="$(lower "$2")"
  [ "$e" != git ] || return 0
  # a word starting with `git` (`gitflow`), or `pr`, `pull`, `tag`, `worktree`
  for w in ${e//[._-]/ } ${c//[._-]/ }; do
    case "$w" in git* | pr | pull | tag | worktree) return 0 ;; esac
  done
  case "$e $c" in
    *commit* | *branch* | *push* | *merge* | *rebase* | *checkout* | *switch* | *release* | *publish* | \
      *pullrequest* | *amend* | *squash* | *cherry*) return 0 ;;
  esac
  return 1
}

# step_hooks: the hooks from origin/<default> (a brief, an issue, a symptom:
# the tree the run's worktree gets) or from the checkout (resume, rebase),
# sorted for the gate: won't run (/feat), would branch or commit, allowed
step_hooks() {
  local f ref text i k e c label manual allowed=() flagged
  H_KEY=() H_EXT=() H_CMD=()
  if [ "$kind" = resume ] || [ "$kind" = rebase ]; then
    f="$top/.specify/extensions.yml"
    if [ -f "$f" ]; then read_hooks .specify/extensions.yml <"$f"; fi
  else
    ref="refs/remotes/origin/$DEF:.specify/extensions.yml"
    if git -C "$top" cat-file -e "$ref" 2>/dev/null; then
      text="$(git -C "$top" show "$ref" 2>/dev/null)" || stop "can't read origin/$DEF:.specify/extensions.yml"
      read_hooks "origin/$DEF:.specify/extensions.yml" <<<"$text"
    fi
  fi
  i=0
  while [ "$i" -lt "${#H_KEY[@]}" ]; do
    k="${H_KEY[i]}" e="${H_EXT[i]}" c="${H_CMD[i]}"
    i=$((i + 1))
    label="$k: $e"
    manual="$label"
    if [ -n "$c" ]; then
      label="$label.$c"
      manual="$label → run it by hand: /${c//./-}"
    fi
    flagged=0
    if would_commit "$e" "$c"; then flagged=1; fi
    if [ "$skill" = feat ]; then
      case "$k" in
        before_specify | after_specify | before_plan | after_plan | before_tasks | after_tasks | before_analyze | after_analyze)
          # the specifier, planner and tasker can't run hooks
          [ "$kind" = rebase ] || emit "hook won't run" "$manual"
          continue
          ;;
        before_implement | after_implement) ;;
        *) continue ;;
      esac
    fi
    if [ "$flagged" = 1 ]; then
      emit 'hook would branch or commit' "$manual"
    else
      allowed+=("$label")
    fi
  done
  if [ "${#allowed[@]}" -gt 0 ]; then
    emit 'hooks allowed' "$(join "${allowed[@]}")"
  else
    emit 'hooks allowed' none
  fi
}

# --- slug ------------------------------------------------------------------------

# norm <text>: N = lowercase, every run of [^a-z0-9] a `-`, `-` trimmed at
# both ends
norm() {
  N="$(lower "$1")"
  N="${N//[^a-z0-9]/-}"
  while [[ $N == *--* ]]; do N="${N//--/-}"; done
  N="${N#-}"
  N="${N%-}"
}

# cut40 <slug>: N = the slug cut to 40 characters at a `-` (a single word
# longer than that is cut where it reaches 40)
cut40() {
  local t
  N="$1"
  [ "${#N}" -gt 40 ] || return 0
  t="${N:0:41}"
  if [[ $t == *- ]]; then
    N="${t%-}"
    return 0
  fi
  t="${N:0:40}"
  if [[ $t == *-* ]]; then N="${t%-*}"; else N="$t"; fi
}

# slug_base: B = the slug before the clash check (research R1, R13): issue
# `<N>-<first three title words>` (two when over 40; <N> alone when the title
# has no word), symptom the slug= words, another URL its last path segment;
# a symptom or URL base that normalises to nothing is `bug`
slug_base() {
  local w1 w2 w3 rest
  if [ "$kind" = issue ] && [ "$github" = yes ]; then
    norm "$ITITLE"
    if [ -z "$N" ]; then
      B="$IN"
      return 0
    fi
    w1="${N%%-*}" rest="${N#"$w1"}" rest="${rest#-}"
    w2="${rest%%-*}" rest="${rest#"$w2"}" rest="${rest#-}"
    w3="${rest%%-*}"
    B="$IN-$w1${w2:+-$w2}${w3:+-$w3}"
    if [ "${#B}" -gt 40 ]; then B="$IN-$w1${w2:+-$w2}"; fi
    cut40 "$B"
    B="$N"
    return 0
  fi
  if [ "$kind" = symptom ]; then norm "$words"; else norm "$ITITLE"; fi
  cut40 "$N"
  B="${N:-bug}"
}

# slug_taken <slug>: 0 when the bug dir is in origin/<default> or HEAD, the
# local branch fix-<slug> exists, or the remote list holds it
slug_taken() {
  local r
  git -C "$top" cat-file -e "refs/remotes/origin/$DEF:.specify/bugs/$1" 2>/dev/null && return 0
  git -C "$top" cat-file -e "HEAD:.specify/bugs/$1" 2>/dev/null && return 0
  git -C "$top" show-ref -q --verify "refs/heads/fix-$1" 2>/dev/null && return 0
  for r in ${REMOTE_FIX[@]+"${REMOTE_FIX[@]}"}; do
    [ "$r" != "refs/heads/fix-$1" ] || return 0
  done
  return 1
}

# step_slug: the first free slug of <base>, <base>-2, <base>-3, ... (the base
# trimmed so the whole stays within 40 characters). One ls-remote, whatever
# the clashes; the pattern is fix-*, as a trimmed candidate need not start
# with the whole base.
step_slug() {
  local l r i s b
  REMOTE_FIX=()
  slug_base
  if ! l="$(GIT_TERMINAL_PROMPT=0 git -C "$top" ls-remote --heads origin 'fix-*' 2>&1)"; then
    first_line "$l"
    die_error "git ls-remote origin failed: ${L:-git failed}"
  fi
  while IFS= read -r r; do
    [[ $r == *"${TAB}refs/heads/"* ]] || continue
    REMOTE_FIX+=("${r#*"$TAB"}")
  done <<<"$l"
  s="$B" i=1
  while slug_taken "$s"; do
    i=$((i + 1))
    b="${B:0:$((40 - 1 - ${#i}))}"
    while [[ $b == *- ]]; do b="${b%-}"; done
    s="$b-$i"
  done
  emit slug "$s"
}

# --- issue -----------------------------------------------------------------------

# gh_out <args>...: G = gh's output; a failure stops with gh's first line
gh_out() {
  mktmp
  if ! G="$(gh "$@" 2>"$tmp/gh-err")"; then
    first_line "$(cat "$tmp/gh-err")"
    [ -n "$L" ] || first_line "$G"
    stop "gh failed: ${L:-no output}"
  fi
}

# step_issue: title, author and the issue line of a /fix issue or symptom
step_issue() {
  local cur o r assoc title u
  if [ "$kind" = symptom ]; then
    emit title "$(first_words "$a" 10)"
    emit author user
    emit issue none
    return 0
  fi
  if [ "$github" = no ]; then
    u="${a%%[?#]*}"
    u="${u%/}"
    ITITLE="${u##*/}"
    emit github no
    emit title "$ITITLE"
    emit author unknown
    emit issue none
    return 0
  fi
  gh_out repo view --json nameWithOwner --jq .nameWithOwner
  trim "$G"
  cur="$T"
  if [ -n "$IO" ]; then
    o="$IO" r="$IR"
  elif [[ $cur =~ ^($RE_OWNER)/($RE_REPO)$ ]]; then
    o="${BASH_REMATCH[1]}" r="${BASH_REMATCH[2]}"
  else
    stop "gh names no repository for this checkout: $cur"
  fi
  gh_out api "repos/$o/$r/issues/$IN" --jq '[.author_association, .title] | @tsv'
  G="${G%$'\n'}"
  assoc="${G%%"$TAB"*}"
  if [[ $G == *"$TAB"* ]]; then title="${G#*"$TAB"}"; else title=""; fi
  ITITLE="$title"
  [[ $assoc =~ ^[A-Z_]+$ ]] || assoc=unknown
  if [ "$(lower "$o/$r")" != "$(lower "$cur")" ]; then assoc=unknown; fi
  emit github yes
  emit title "$title"
  emit author "$assoc"
  if [ -n "$IO" ]; then emit issue "$IO/$IR#$IN"; else emit issue "#$IN"; fi
}

# first_words <text> <n>: its first <n> whitespace-separated words
first_words() {
  local ws=() out="" i=0
  read -r -a ws <<<"$1" || true
  while [ "$i" -lt "${#ws[@]}" ] && [ "$i" -lt "$2" ]; do
    out="${out:+$out }${ws[i]}"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# --- worktree mode ---------------------------------------------------------------

worktree_mode() {
  local name onoff target cur err
  [ "$#" -eq 3 ] || die_usage
  name="$2" onoff="$3"
  if [ "$skill" = feat ]; then
    [[ $name =~ $RE_NAME ]] || die_usage "the short name must match [a-z0-9][a-z0-9-]*"
    target="$name"
  else
    [[ $name =~ $RE_NAME ]] && [ "${#name}" -le 40 ] ||
      die_usage "the slug must match [a-z0-9][a-z0-9-]* and be at most 40 characters"
    target="fix-$name"
  fi
  case "$onoff" in on | off) ;; *) die_usage "the last argument is on or off" ;; esac
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || die_error "not a git repository"
  emit worktree "$top"
  if [ "$skill" = fix ] && { [ -e "$top/.specify/bugs/$name" ] || [ -L "$top/.specify/bugs/$name" ]; }; then
    stop "slug $name is taken (bug dir); run setup again"
  fi
  cur="$(git -C "$top" branch --show-current 2>/dev/null)" || cur=""
  if [ "$cur" != "$target" ]; then
    if ! err="$(git -C "$top" branch -m "$target" 2>&1)"; then
      first_line "$err"
      stop "can't rename the branch to $target: ${L:-git failed}"
    fi
  fi
  emit branch "$target"
  if [ "$onoff" = on ] && [ ! -e "$top/.logistics.yml" ]; then
    emit flag "- [!] tracker: .logistics.yml is not in the worktree; commit and push it (board moves skipped)"
  fi
  flush
  exit 0
}

# --- main ------------------------------------------------------------------------

skill="${1:-}"
case "$skill" in feat | fix) ;; *) die_usage ;; esac
shift
if [ "${1:-}" = worktree ]; then worktree_mode "$@"; fi
[ "$#" -le 2 ] || die_usage
words=""
has_words=0
if [ "$#" -eq 2 ]; then
  case "$2" in
    slug=*) words="${2#slug=}" has_words=1 ;;
    *) die_usage ;;
  esac
fi
trim "${1:-}"
a="$T"
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die_error "not a git repository"

kind="" github="" target="" DEF="" ITITLE=""
if [ -z "$a" ]; then
  kind=empty
elif [ "$a" = resume ]; then
  kind=resume
elif [[ $a =~ ^rebase([[:space:]]+([^[:space:]]+))?$ ]]; then
  kind=rebase target="${BASH_REMATCH[2]:-none}"
elif issue_ref "$a"; then
  kind=issue github=yes
elif [[ $a =~ ^https?://[^[:space:]]+$ ]]; then
  kind=issue github=no
elif [ "$skill" = feat ]; then
  n="${a#specs/briefs/}"
  n="${n%.md}"
  if [ -f "$a" ] || [[ $n =~ $RE_NAME ]]; then kind=brief; else kind=idea; fi
elif is_brief_for_fix "$a"; then
  kind=brief
else
  kind=symptom
fi

# the coordinator's guess of the kind is never load-bearing: /fix ignores
# slug= for a kind other than a symptom, and a symptom without it takes its
# first four words; /feat refuses it
if [ "$skill" = feat ] && [ "$has_words" = 1 ]; then
  die_usage "slug=<words> is only for /fix"
elif [ "$kind" = symptom ] && [ "$has_words" = 0 ]; then
  words="$(first_words "$a" 4)"
fi

emit kind "$kind"
case "$skill:$kind" in
  *:empty)
    if [ "$skill" = feat ]; then
      emit usage '/feat <brief path or short name> | resume | rebase [PR]'
    else
      emit usage '/fix #N | <issue URL> | "<symptom>" | resume | rebase [PR]'
    fi
    flush
    exit 0
    ;;
  feat:issue)
    emit pointer "/brief $a"
    stop "/feat builds from a brief, not an issue: write the brief first"
    ;;
  feat:idea)
    emit pointer "/brief \"$a\""
    emit pointer "/fix \"$a\" (if it describes a bug)"
    stop "/feat builds from a brief, not an idea: write the brief first"
    ;;
  fix:brief)
    emit pointer "/feat $a"
    stop "a brief is built by /feat, not /fix"
    ;;
esac

case "$kind" in
  resume)
    step_install
    step_hooks
    ;;
  rebase)
    emit 'rebase target' "$target"
    step_install
    step_hooks
    ;;
  brief)
    brief_lookup "$a"
    brief_fields
    step_install
    step_board
    step_base
    step_hooks
    ;;
  issue | symptom)
    step_install
    step_board
    step_base
    step_hooks
    step_issue
    step_slug
    ;;
esac
flush
