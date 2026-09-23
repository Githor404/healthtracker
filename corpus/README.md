# The micronutrient corpus (D114)

This directory holds the **slot list** and the script that derives it. It does
**not** hold the source databases, and it never will: they are ~19 MB of
third-party archives, and the repo is fixture-synthetic and public-facing.

## What is committed

| file | what it is |
|---|---|
| `slots.json` | the slot list — **append-only forever** |
| `derive_slots.py` | the derivation, re-runnable against the sources |

`tests/check-slots.sh` is wired into the gate suite and asserts the artifact
describes itself honestly. The stronger check — a full re-derivation — is
`python corpus/derive_slots.py --src <dir> --check`, run when the sources are to
hand.

## The sources, as measured 2026-09-22

| source | download | unzipped | foods | nutrients |
|---|---|---|---|---|
| USDA FDC **SR Legacy** (2018, frozen) | 13,456,312 B | 211 MB | **7,793** | 148 with values |
| Health Canada **CNF 2015** | 5,226,720 B | ~26 MB CSV | **5,690** | 152 defined, 153 with values |

Get them with:

```
curl -O https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip
curl -O https://www.canada.ca/content/dam/hc-sc/migration/hc-sc/fn-an/alt_formats/zip/nutrition/fiche-nutri-data/cnf-fcen-csv.zip
```

and rename them `srlegacy.zip` and `cnf.zip` in one directory.

**Not used, and why.** FDC **Foundation Foods** is 363 usable entries and
populates vitamin A at 14.0%, D at 14.3%, B12 at 17.6% — a quality reference,
not a corpus. FDC **Branded** is 3.1 GB and OFF already covers branded goods by
barcode. FDC **FNDDS** is the whole-dish source and belongs to D62's slice.

## Licence, and what it constrains in the design

**CNF** — *"The Canadian Nutrient File may be downloaded and used without further
permission"*, on conditions. Two of them bind this code, not just the README:

- **Attribution travels with the value.** *"Health Canada be identified as the
  source (Canadian Nutrient File, Health Canada, 2015)"* — carried with any
  displayed CNF-sourced number, the same shape as the openFDA disclaimer (D78).
- **Values may be re-expressed, never adjusted.** *"You may not modify the
  nutrient value but you may express it in different serving sizes than the 100g
  provided in the CNF."* The corpus stores per-100 g values exactly as published
  and scales only at portion time.

**FDC** — US federal public domain; attribution is courtesy, not obligation.

## The slot list

`slots.json` keeps two sets **separately countable**, because a curated list
wearing a derivation's clothes is the failure this guards against:

- **derived** — every nutrient clearing **≥90%** coverage in *either* source,
  keyed by the USDA SR nutrient number (FDC exposes it as `nutrient.number`, CNF
  as `NutrientID`).
- **judged** — hand-ruled entries, each carrying a stated reason: *merges*, where
  one nutrient is filed under two different source numbers, and *additions*, for
  nutrients the app already stores that fall below the bar.

**Why the bar is evaluated on the union.** FDC's retinol activity equivalents is
SR 320 at 88.8%; CNF's is 814 at 95.4%. The two halves of one nutrient fell on
opposite sides of the threshold. Applied per-namespace, the bar would make a
nutrient exist or not **depending on locale**, with nothing on the surface to
explain why. The union plus the override table is what prevents that, and it
generalises past vitamin A — vitamin D is filed as FDC 328 and CNF 339.

**Why the SR number and not the FDC id.** Within one publisher, total sugars is
`Sugars, Total` / id **1063** in Foundation and `Total Sugars` / id **2000** in
SR Legacy. Keying slots on the FDC id would have split one nutrient in two
silently. The SR number is shared with CNF; where it is not, the override table
says so by name.
