# Contract: what the user sees in a /brief interview

The interface of `/brief` is its conversation. This contract fixes the
shape of two messages; field rules are in [data-model.md](../data-model.md).

## First interview message on an issue start

```text
Where it stands
- The ask: <paraphrase: the problem and who has it>
- Today: <what code/docs do now, file:line, what's missing>
- Already decided: <what the issue settles>        (omitted when empty)
- Open: <unchecked items, anything unclear>        (omitted when empty)

HYPOTHESIS: <one sentence>
CONFIDENCE: <n>% <— missing: … when below ~70%>

Q: <first question>
GUESS: <guess with reasoning>
```

- Exactly one message before the user's first answer.
- Comes after the `/tiny` offer when that offer applies and is declined.
- Not shown on non-issue starts: those open with HYPOTHESIS as today.

## A question that meets the table trigger

```text
Q: <question>

| Option | <criterion 1> | <criterion 2> | … |
|---|---|---|---|
| A | … | … | … |
| B (recommended) | … | … | … |
| C | … | … | … |

GUESS: <guess with reasoning>
<strongest counter-argument>
```

- One table per question, before GUESS; the recommended row is marked.
- Questions outside the trigger keep interview-me's `Q:` / `GUESS:` format
  with no table.
- Column headers are the separating criteria, never `Phase`/`Agent` or
  `Size`/`Condition` (and the skill text itself holds no table).
