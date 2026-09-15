# Matcher evaluation set

Built from a real export. **Read D72 before quoting any number from it.**

## What is here

| file | what it is | committable |
|---|---|---|
| `build.py` | regenerates the inputs from an export | yes |
| `score.py` | scores a matcher's predictions | yes |
| `set.json` | 7 rows with **barcode truth**, 1 name-only | **no** — real eating history |
| `tolabel.json` | 26 distinct queries awaiting human labels | **no** — same |

```
python eval/build.py export.json eval/
python eval/score.py eval/set.json predictions.json eval/tolabel.json
```

## The two populations, and why they are not interchangeable

**`set.json` — scanned rows, 7 of them.** A barcode determines the product independently of the app, the model and the user. This is the **only externally verified ground truth in the export**, and the per-100 g profile is rebuilt from the logged portion. One product was scanned twice, at 100 g and at 40 g, and both derivations give the same profile — the only internal check available, and it passes.

**`tolabel.json` — 26 distinct queries, 0 labelled.** These are the dish cases the matcher exists for. They carry **no truth** until a person assigns a corpus row. Five are marked `human_judged`: the plates where a candidate was actually chosen between. **That is a seed, not a set** — it is the only place a human expressed a judgement about identity, and five judgements do not measure anything.

`asked_by` says whether the string came from the model (`ai_identity`, 21) or is the name the user accepted (5). The accepted names are worth labelling first. The split exists because an R33 consumption event carries no `ai_identity` — D70 moved it to the plate — so those rows contribute their accepted name instead.

## What this cannot measure

Four limits — the first three ruled in **D72**, the fourth in **D74** — repeated here because this is where someone would compute a number.

1. **`ai_grams` / `grams` cannot measure the model's portion bias.** Estimates were corrected only when a real weight was available, plausibly *because* the estimate looked wrong. Identical pairs mean the estimate was accepted — which could mean it was right, or that there was no way to check, and those cannot be separated after the fact. Any ratio over them measures the user's correcting behaviour.

2. **`fastLog` cannot measure fasting.** Days are not closed and fasts are not resolved; gaps are logging artifacts. Any streak or mean describes logging habits.

3. **One labeller, who is also the user.** See below — the set measures agreement with a single person's judgement.

4. **The barcoded rows are selected against the matcher's job.** A barcode means the app already resolved the food *without* a matcher. The cases the matcher exists for have no barcode and therefore no external truth here. This set can measure whether a matcher returns a composition consistent with a known product; **it cannot measure the thing the matcher is for.**

## The directional rule

`score.py` prints no accuracy figure without its denominator, and below **30 rows** every figure is prefixed `DIRECTIONAL`. The label travels with the number rather than sitting in a footnote, because a percentage over seven rows reads exactly like a percentage over seven hundred once it has been copied into a sentence.

## Labelling

More **scans** will not fix limit 4 — they are the wrong population. What closes it is labelling `tolabel.json`: naming the correct corpus row for dishes actually eaten.

### `undecidable` is a finished label, not a skipped row

If no corpus row is correct for a query, set `undecidable: true` and leave `corpus_row` null. **That is a finding about the corpus**, and it is as complete an answer as naming a row.

The tooling counts it that way — `build.py` and `score.py` report *labelled*, *undecidable* and *not yet looked at* as three separate states, and the first two both count as resolved. This is deliberate: **a workflow that reports "no row fits" as unfinished work applies pressure to invent an answer**, and an invented row is noise in the truth column, which is worse than a smaller set.

### Limit 4: one labeller, and it is the same person the matcher serves

The set is labelled by the app's author, who is also the person whose meals it contains and whose matcher it will score. **It therefore measures agreement with one person's judgement, not correctness.**

Nothing here fixes that, and it is not a reason to stop — a matcher that agrees with its only user is doing most of its job. But no figure from this set may be described as accuracy without that qualification, and a disagreement between the matcher and a label is not automatically the matcher being wrong.
