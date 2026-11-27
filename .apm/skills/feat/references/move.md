# Moving onto a new main

Read this when `step.sh` prints `base: moved`, when a shipper reports `PR:
conflict`, and from `references/rebase.md`. The harness's rules hold here
too; the values in *italics* are the skill's (its `## Harness values`
block).

Runs go in parallel, one worktree each; when one merges, the others fall
behind `origin/<default>`. `step.sh` runs the base check and the repair
check, prints the rebase-mode spawn (`feat-implementer` on the *implement
row*, `action: move` or `repair`, `shipped: no`, key `move`) in place of
the phase's, and reads the move's report at its `move` or `repair`
boundary. Give that spawn the worktree, the default branch, the state
file, the *resolver context* and the fields the spawn block prints. The
last base is never stored: it is `git merge-base HEAD origin/<default>`,
and each move's old and new base are on its Log line.

## The move's report

Its `Move:` line, after `step.sh` checked the report like any other:

- `<old> → <new>`: `step.sh` logs the move and prints `move:` and the
  phase's spawn (under a new snapshot when the phase's reviewers run under
  one). The next gate, or the final message, shows `Main moved <old> →
  <new>; checks <result>`, then its `Resolved alone:` lines, one per file.
  It is not a surprise.
- `undone (<old> → <new>)`: the move gate (below), before the phase.
- `nothing to do`: nothing is logged or shown.
- `repaired`: a move that died part way was put back; `step.sh` logs it
  and goes on.

## Move gate

A hard gate: the worktree is back on `<old>`, its tracked content and
index as before. Show each `Needs decision:` item as file, the run's side,
main's side and the recommendation.

```
## Main moved before phase <N> <name> — needs your call
**What I did:** feat-implementer, rebase mode (<model · effort>): <old7> → <new7>, then undone; the worktree is on <old7>, its tracked content and index as before
**What you should know:** resolved alone: <n> files (listed); checks with my recommendations: <result>
**Your call:**
1. <file> — run: <one line> — main: <one line> — I recommend <rec>
**Next:** the move with your answers ("ok": my recommendations), then phase <N> <name>
```

At ship, the heading says `before <the ship phase>` and **Next:** "the
move with your answers, then the ship again".

Answers:

- `approved` ("ok") or `changed` (the user's words for some items):
  `step.sh` prints a fresh rebase-mode spawn. Give it `Decisions:`, one
  line per item, `<file> — <the accepted rec | the user's words>` ("ok"
  copies each item's rec as is). Its report is read the same way.
- `stay`: `step.sh` logs `- [x] move — stayed on <old>, refused <new>
  (user: "<words>")` and runs the phase on `<old>`; that base is not
  offered again.
- `stop`: as at any gate.

## At ship

A shipper report `PR: conflict` pushed nothing; its `Conflicts:` lists the
files, or reads `none` when main moved after the shipper's rebase (its
publish found a new main before pushing). Both go the same way. `step.sh`
prints `read:` (this file) and the rebase-mode spawn (`shipped: no`); its
`boundary:` line carries the ship report with its
`sum=` and the move's report. Follow it: a move that needs the user's call
stops at the move gate first; a kept one logs the move (`at ship`) and
prints the ship spawn again, as the first time. When the shipper numbered
the artifact dir, `step.sh` prints the state file's new path on its
`state:` line and writes there. List the move in the final message.

## Log

One entry per move, kept or decided. `step.sh` writes it at its
boundaries; `rebase` writes its own `PR #<n>` moves with `S log`.
`<where>` is `before <N> <name>`, `at ship`, or `PR #<n>`:

    - [x] move — <old> → <new> (<where>): checks <result>; not verified: <none | items>
        - resolved: <file> — <how>
        - asked: <file> — <decision> (user: "<words>" | as recommended)

`<result>` is `pass` or `fail: <the first failing check>`. The move's not
verified items stay on that line and at the next gate; they are not passed
on (the ship's full checks run after any move).
