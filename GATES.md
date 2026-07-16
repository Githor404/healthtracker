# Phase Gates

Pre-registered evidence for each phase gate. Machinery is certified by committed,
re-runnable tests. Claims that reference *real* personal data are **attested**, not
committed — the history-free-repo rule forbids that data entering the repo, so only
the attestation is recorded here.

---

## Phase 0 — Scaffold & data layer

**Gate (from the brief):** a real legacy export imports losslessly (item counts,
per-day totals, statuses, `water_l` all match); the app loads and displays imported
history with networking disabled; the badge correctly reflects each storage tier
including a forced write failure occurring after load.

### Part 1 — Committed machinery evidence (re-runnable)

Certifies the *mechanism* on **synthetic** fixtures — not any real export.

| Gate requirement | How to re-run | Result |
|---|---|---|
| Lossless migration/import (counts, per-day totals, statuses, water) | `bash tests/run-data-layer.sh` (tests 2, 8) | **66/66 PASS** |
| Loads + displays imported history, networking disabled | `powershell -File tests/offline-gate.ps1` | **PASS** — prod path forced (`?prod=1`), network cut via CDP; shell + migrated history render offline |
| Badge reflects each tier incl. forced write failure after load | `bash tests/run-data-layer.sh` (tests 5, 6) | **66/66 PASS** |
| Precache list honest (no silent 404 disabling offline) | `bash tests/check-precache.sh` | **PASS** |

### Part 2 — Real-export attestation (one-time, uncommitted data)

The gate sentence says a *real* legacy export imports losslessly. Verified once by
the user against the live `uha-log-v1` export; only the attestation is recorded.
The data never enters the repo.

**Procedure**
1. Open the app; paste the real `uha-log-v1` export into **Import · restore**; confirm.
2. Click **Copy data out** to obtain the new-schema export.
3. Compare, per day, the old `uha-log-v1` export against the new export: item counts,
   per-day kcal / P / F / C / fiber sums, `status`, `water_l`. Compare **export-to-export**
   so the predecessor's render-time supplement is not a confound (that delta is the D4 fork).
4. Confirm the **History** card renders every migrated day with the correct status and water.

**Attestation**
- Attester: Thomas Seiler (repo author)
- Date: 2026-07-11
- Migrated day count: **34**
- Item counts / per-day totals / statuses / water all match: **YES** (export-to-export)
- Discrepancies: none

**Status: MET — machinery CERTIFIED and real export verified (34 days, full match).**

_Note: legacy `uha-log-v1` support was retired by v4 (2026-07-11) **after** this gate was met. "Gate met, then feature retired" is the historical truth; the evidence stands. Phase R strips the legacy code and moves the data-layer harness to schema v2 — see the Phase R gate below._

---

## Phase R — Reframe (schema v2)

**Gate (from the brief):** full harness green after the strip (no orphaned cases); a v1 blob migrates in place under the stable key with items gaining correct `source`; new-user boot yields zero days'-worth of fabricated intake (no supplement unless configured); forward-version guard rejects v3+.

### Committed machinery evidence (re-runnable, synthetic fixtures)

| Gate requirement | How to re-run | Result |
|---|---|---|
| Full harness green after the strip; `app.js` legacy-free (no orphaned cases) | `bash tests/run-data-layer.sh` | strip check PASS · **59/59 PASS** |
| v1 blob migrates in place; items gain correct `source`; days/water byte-preserved; `known` dropped + stamped; pre-migration snapshot retained | data-layer tests 2, 3 | PASS |
| New-user boot: zero fabricated intake (no supplement unless configured) | data-layer test 1 | PASS |
| Forward-version guard rejects v3+ (boot protects the blob; restore rejects) | data-layer tests 4, 9 | PASS |
| Restore boundary: v1→migrate, v2→as-is, absent→reject, micros/source coerced | data-layer tests 9, 10 | PASS |
| Offline load still works — now also exercising v1→v2 migration offline | `powershell -File tests/offline-gate.ps1` | PASS |
| Precache list honest | `bash tests/check-precache.sh` | PASS |

Legacy `uha-log-v1` support removed; the restore boundary accepts schema v1/v2 blobs only (D5 amendment, D7).

**Status: MET.**

---

## Phase 1 — Logging core, multi-user (IN PROGRESS)

**Gate (from the brief):** displayed and exported totals are the same numeric item set; all four ingest shapes per contract; ai-paste micros stripped and reported; goal direction math correct (min/max); every rendered field escaped (incl. goal/preset/store names); first-run on a clean profile reaches a logged day via the prompt-template path. Built slice-by-slice (ingest first, per the ruled sequencing); evidence accrues here.

### Ingest slice (D8) — MET

| Gate requirement | Evidence |
|---|---|
| All four ingest shapes per contract (`{items}`+date, array, single, full-days) | data-layer tests I1–I8 |
| ai-paste micros stripped **and reported** | I1 |
| full-days merge non-destructive; tightened fillable (complete / water-only preserved) | I6, I7 |
| full-days version-routed via the D7 front-end (v1 migrate, absent/>2 reject) | I8 |
| complete-day append reopens + reports; duplicates accepted; rejects reported | I9, I10, I11 |
| supplement injection at device-side creation; wholesale days as-is | I12, I13, I14 |
| ingest merges days only (settings/priceLog untouched); report fields escaped | I15 |

`bash tests/run-data-layer.sh` → **strip check PASS · 83/83 PASS**; offline + precache gates still green.

### Day view + goals slice — MET

| Gate requirement | Evidence |
|---|---|
| Displayed day totals == exported totals (sum persisted items, no phantom additions) | data-layer test G4 |
| Goal direction math correct (floor short/met, ceiling good/over) | G1, G2 |
| Daily summary micro coverage ("from N of M items") | G3 |
| Every rendered field escaped (hostile item name in the day view) | G5 |
| Goals persist (value + direction) | G6 |

Day view: meal grouping, per-item delete / tap-to-cycle-meal, confidence dot, source, meal subtotals, day totals, close/reopen, clear-day, water quick-add, day nav. Goals: progress-vs-goal ring (selectable primary, default kcal), direction-aware goal strip, micro-coverage summary, minimal goals setup. `bash tests/run-data-layer.sh` → **93/93**; offline + precache green.

**License:** MIT (ruled) — `LICENSE` added.

### Manual add + presets slice (D9) — MET

| Gate requirement | Evidence |
|---|---|
| Manual item `source: manual`; selectable confidence honored (weighed); micros carried + clamped ≥ 0 | data-layer test M2 |
| Micro field → canonical key → unit, **no cross-wiring**; units rendered | M1 |
| Sane-range warnings fire and are **non-blocking** (item still added) | M3 |
| Manual add onto a `complete` day reopens it | M4 |
| Save-as-preset writes a preset (micros + descriptive portion); preset-log is `source: preset` with micros | M5 |
| Preset delete never touches already-logged copies | M6 |
| Duplicate preset names allowed (id-keyed) | M7 |

`bash tests/run-data-layer.sh` → **106/106**; offline + precache green. Micros behind a labeled disclosure with a filled-count header (fork C); Add / Save-as-preset are independent (fork D).

### Averages slice (D10) — MET

| Gate requirement | Evidence |
|---|---|
| 7-day = calendar window (day-3 in, day-8 out); in-progress excluded | data-layer test A1 |
| All-time = every complete day | A2 |
| Macro mean = Σ/M; a fasting complete day counts as 0-intake | A3 |
| Micro **per-nutrient** coverage; **absence ≠ zero**; "N_K of M" | A4 |
| Honest empty state at M=0 (not zeros) | A5 |
| Persisted supplement included (no render-time addition) | A6 |

`bash tests/run-data-layer.sh` → **115/115**; offline + precache green.

### First-run + AI prompt template slice (D11) — MET

| Gate requirement | Evidence |
|---|---|
| First-run **derived from state**, no stored flag | data-layer tests F1, F2, F2b, F3 |
| Onboarding renders iff first-run, auto-recedes | F5 |
| Template↔ingest self-consistency (ai-paste, eyeballed, no micros, soluble present) | F6 |
| Template-text invariants incl **full meal enum** | F7 |
| Template version exposed + shown on the card | F8 + smoke ("template v2") |

`bash tests/run-data-layer.sh` → **129/129**; offline + precache green.

### Supplement config slice (D12) — MET

| Gate requirement | Evidence |
|---|---|
| Enable (today `in_progress`) injects `_auto` with nutrients incl micros | data-layer test S1 |
| Disable removes today's `_auto` (standing dose) | S2 |
| Edit rebuilds today's `_auto` in place | S3 |
| Complete-today never rewritten / reopened by config | S4 |
| Past complete day never touched | S5 |
| `normalizeSupplement` coerces + clamps nutrients (restore hardening) | S6 |
| Shared micro component, no cross-wiring across **both** forms | S7 (+ M1) |

`bash tests/run-data-layer.sh` → **138/138**; offline + precache green. One micro component mounted in both the manual-add and supplement forms.

### README + privacy slice — MET

`README.md` (privacy stance: all local, no accounts, no telemetry, export-is-yours, location only on request and never stored; micronutrient-honesty note) + an in-app about/privacy footer. Closing tests: preset-name escaping (P1), first-run→logged E2E (P2).

### Phase 1 gate claim

Walking the v4 Phase 1 gate criteria against committed, re-runnable evidence — same discipline as the Phase 0 claim (auditable, not asserted). `bash tests/run-data-layer.sh` → **140/140**; offline + precache green.

| v4 Phase 1 criterion | Evidence | Status |
|---|---|---|
| Displayed and exported totals are the same numeric item set | **G4** (day totals shown === exported, summing persisted items only); supplement is a persisted item — no render-time addition (**A6**) | **MET** |
| All four ingest shapes per contract | **I1** `{items}`+date · **I2** bare array · **I3** single item · **I5/I8** full-days; date precedence I4; never-overwrite-non-empty I6; tightened fillable I7; version routing I8 | **MET** |
| ai-paste micros stripped and reported | **I1** (micros gone, `report.stripped` counted) | **MET** |
| Goal direction math correct for min and max | **G1** (floor: short / met) · **G2** (ceiling: good / over) | **MET** |
| Every rendered field escaped (goal names, preset names, store names) | day keys R1 + test 15 · item names **G5** · preset names **P1** · goal "names" are a fixed nutrient enum (escaped regardless, no free-text vector) · **store names — N/A: price capture is Phase 2** | **MET for Phase-1 fields; store names deferred to Phase 2** |
| First-run reaches a logged day via the prompt-template path, no external instructions | **F5** (onboarding teaches on a clean profile) · **F6** (the template's own sample ingests to an honest ai-paste item) · **P2** (end-to-end: first-run → template ingest → logged day → onboarding recedes) | **MET** |

Also folded into Phase 1: the "Micronutrients — labeled intake only" honesty label (**H1**), and the SW content-hash fix that made deploys actually update (D6 amendment; update bar **observed on device**).

**Phase 1 gate: MET.** One criterion is only partially applicable — "store names" has nothing to escape until price capture exists (Phase 2); the escaping *discipline* (every rendered value through `esc()`) is proven on day keys, item names, and preset names, and enforced by the render-layer backstop tests.

---

## Phase 2 — Scan + price capture (IN PROGRESS)

**Gate (from the brief):** scanned real product logs correct macros+micros at a custom gram amount; absence-≠-zero verified (no labeled iron shows no iron, not 0); rescan offline resolves from cache; unknown barcode degrades without losing the code; camera-denied/no-camera messages correct; price entries recorded, grouped by store, skippable at zero cost.

Built slice-by-slice (ruled): **Slice 1** = OFF data pipeline (lookup + micros mapping + portion math + product cache) via the camera-free manual barcode trigger; **Slice 2** = camera/getUserMedia (on-device attested, like the update bar); **Slice 3** = price capture + comparison view. This section pre-registers **Slice 1**.

### Slice 1 — OFF lookup + micros + portion + cache (D13, D14) — PRE-REGISTERED

Committed, re-runnable synthetic-fixture cases in `tests/data-layer.test.html` (prefix `OF`), plus one uncommitted live attestation. Async fetch is not committed (the edge is a trivial try/await/catch around the pure `finishLookup`); its degradation branches are tested synchronously via `finishLookup`.

| Slice-1 gate clause | Pre-registered evidence |
|---|---|
| Correct macros+micros at a custom gram amount | **OF1** `mapOffProduct` maps a full product (macros from `energy-kcal_100g` etc.; per-100g base) · **OF7** `scalePortion` per-100g/per-serving/custom scales macros **and** micros by one factor · **OF10** `buildScanItem` → `source:scan`, `confidence:measured`, `barcode` kept, `soluble_fiber_g` present, only-present micros, passes `normalizeItem` unchanged |
| **Absence ≠ zero** | **OF2** a product with no iron key → no `iron_mg`; zero mapped micros → `micros` omitted (not `{}`-of-zeros) · **OF8** scaling never introduces an absent micro at any portion |
| Salt→sodium + units, no double-count | **OF3** `sodium_100g` present → used; only `salt_100g` → ÷2.5; both present → sodium wins (single source) · **OF4** unit-aware conversion g→mg (×1000) and g→µg (×1e6) off the reported `_unit`; kJ→kcal fallback |
| Boundary hardening | **OF5** hostile OFF name / negative & NaN numbers → coerced+clamped, string escaped at render · **OF6** unknown OFF nutriment keys ignored; missing `nutriments` → macros 0, `micros` omitted, valid record |
| Rescan offline resolves from cache | **OF11** `ProductCache` put→get round-trip; `finishLookup(bc,{ok:false})` with a cached entry returns it (`source:cache`) · **OF12** own key `healthtracker-products`, absent from export/import (round-trip untouched) |
| Cache hygiene | **OF13** LRU count-cap + byte-ceiling eviction (oldest `lastAccess` first) · **OF14** cache write under forced-failure is a benign no-op (no throw; storage badge unchanged) · **OF15** `cacheVersion` mismatch → treated as miss (re-fetch) |
| Unknown barcode degrades without losing the code | **OF16** missing product (`status:0`) → `found:false`, barcode retained, manual entry offered · **OF17** offline (`{ok:false}`) with no cache → graceful, barcode retained · **OF9** guard rejects non-8–14-digit input before any request |
| Identifier transport (D14) | **OF18** `offURL()` carries the exact `fields` + `app_name`/`app_version`; `OFF_UA` = the ruled string |

`bash tests/run-data-layer.sh` → **182/182 PASS** (42 new `OF` cases); `tests/check-precache.sh`, `tests/check-sw-hash.sh`, `tests/offline-gate.ps1` all green. **Live-edge smoke (real browser, real OFF):** `HT.lookupBarcode('3017620422003')` → `source=network`, Nutella, 539 kcal/100 g, **sodium 42.8 mg** (salt→sodium end-to-end), `serving_g=0`; immediate rescan → `source=cache` (cache-first confirmed). The async `lookupBarcode` wrapper is a trivial try/await/catch around the committed-tested `finishLookup`; its network path is proven by this smoke run and folded into the live attestation.

**Deferred within Phase 2 (not Slice 1):** camera-denied / no-camera messages (Slice 2, attested); price entries grouped by store, skippable at zero cost (Slice 3).

**Live attestation (uncommitted, one-time):** a real barcode fetched from live OFF maps to correct macros + micros at a custom gram amount, verified by the user against the on-package label; absence≠zero confirmed on a product lacking a given micro. Only the attestation is recorded (history-free-repo rule). Build-time API verification is dated in DECISIONS.md **D14 (2026-07-16)**: endpoint + `fields` + `app_name`/`app_version` params → HTTP 200; nutriment `_100g` g-normalization and the salt→sodium precedence confirmed on Nutella / Coca-Cola / Ovomaltine / mineral-water products.

**Status: Slice 1 machinery CERTIFIED (182/182; offline + precache + sw-hash green; live-lookup smoke verified). Awaiting user review + the one-time live attestation against a real package label.**
