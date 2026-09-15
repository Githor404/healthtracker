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

Three limits, ruled in **D72**, repeated here because this is where someone would compute a number.

1. **`ai_grams` / `grams` cannot measure the model's portion bias.** Estimates were corrected only when a real weight was available, plausibly *because* the estimate looked wrong. Identical pairs mean the estimate was accepted — which could mean it was right, or that there was no way to check, and those cannot be separated after the fact. Any ratio over them measures the user's correcting behaviour.

2. **`fastLog` cannot measure fasting.** Days are not closed and fasts are not resolved; gaps are logging artifacts. Any streak or mean describes logging habits.

3. **The barcoded rows are selected against the matcher's job.** A barcode means the app already resolved the food *without* a matcher. The cases the matcher exists for have no barcode and therefore no external truth here. This set can measure whether a matcher returns a composition consistent with a known product; **it cannot measure the thing the matcher is for.**

## The directional rule

`score.py` prints no accuracy figure without its denominator, and below **30 rows** every figure is prefixed `DIRECTIONAL`. The label travels with the number rather than sitting in a footnote, because a percentage over seven rows reads exactly like a percentage over seven hundred once it has been copied into a sentence.

## Growing the set

More **scans** will not fix limit 3 — they are the wrong population. What closes it is labelling `tolabel.json`: naming the correct corpus row for dishes actually eaten. Leave `corpus_row` null where it is undecidable. **An unlabelled entry is honest; a guessed one is noise**, and noise in the truth column is worse than a smaller set.
