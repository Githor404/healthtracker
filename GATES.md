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

### Slice 2 — camera scanner: two-tier detection + ZXing sourcing/caching (D15)

The pure decision logic is committed (`CAM` cases); the live camera flow is on-device attested (A1–A7). Gate clause closed here: *"camera-denied / no-camera messages correct"* = `CAM1`/`CAM2` (committed) + `A2`/`A3`/`A-NR` (attested).

**Committed machinery (`CAM`-prefixed, synthetic/injected — no camera):**

| Case | Asserts |
|---|---|
| CAM1 | `cameraErrorMessage` for each `err.name` (NotAllowed, NotFound, Overconstrained, NotReadable, Security, TypeError, Abort, unknown) → correct message, **each ending in the literal manual escape hatch** |
| CAM2 | `cameraPrecondition(env)` → ok / insecure / unsupported (injected env); gates the Scan button |
| CAM3 | `intersectFormats(desired, supported)` = desired ∩ supported; empty supported → empty |
| CAM4 | `scanGate(state, code, nowMs)` injected clock: first accept, second within 1.5 s reject, after 1.5 s accept |
| CAM5 | detected code → `guardBarcode` → lookup handoff (valid fires stubbed lookup; 7-digit/non-numeric rejected) |
| CAM6 | `stopScanner(session)` idempotent — called twice, no throw, tracks `.stop()`'d, state cleared |
| CAM7 | `detectorTier(env)` → native / zxing by injected `BarcodeDetector` presence |
| CAMZ | ZXING single-SoT: `ZXING.url` contains `ZXING.version`; `loadZXing` reads the constant; `check-zxing.sh` present |

**Machine-checked gates (network / SW):**
- `tests/check-zxing.sh` — consistency (offline) + **SRI hash-vs-file (network): fetches the pinned URL, sha384 must match `ZXING.integrity`**, else fails; `--fix` stamps. Wired into `run-data-layer.sh`.
- `tests/offline-gate.ps1` **extended** — online `loadZXing()` caches the script → network cut → reload → `loadZXing()` resolves from `healthtracker-runtime` (ZXing global appears offline).

**Attested on-device (uncommitted; user signs, like Phase 0 Part 2):**

| Ref | Procedure |
|---|---|
| A1 | permission granted → live-scan a real product barcode → `lookupBarcode` → portion picker → logged `measured` |
| A2 | permission **denied** → exact denied message + manual field usable in the same view (no dead end) |
| A3 | **no camera** (device without one / DevTools override) → no-camera message + manual field |
| A-NR | **`NotReadableError` / camera-in-use** (ruled addition) → camera-in-use message + manual field |
| A4 | ZXing fallback **on a real iOS device** (ruled — the genuine BarcodeDetector-absent path) → lazy-loads, detects within timeout |
| A5 | teardown → closing/navigating away turns the camera indicator off; no lingering stream |
| A6 | `vibrate` fires on detection (device-dependent) |
| A7 | ZXing-from-cache: after one online scan, go offline → ZXing still loads (also machine-checked by the extended offline gate) |

Live sourcing verification dated in **D15 (2026-07-16)**: `@zxing/library@0.23.0` UMD, global `ZXing`, SRI `sha384-0ASr…WZW9`, SRI+CORS `<script>` load succeeded headless; `BarcodeDetector` Chromium/Android-only.

**Status: Slice 2 PRE-REGISTERED — building.**

### Slice 3 — personal price capture + comparison (D18)

Personal price history only (Open Prices/nearby = Phase 3). Fully offline — entirely committed, light UX attestation only. Closes the Phase-1 deferred "store names escaped" item. Gate clause: *"price entries recorded, grouped by store, skippable at zero cost."*

| Case | Asserts |
|---|---|
| PR1 | `addPriceEntry` → bucket + `name` created; price coerced/clamped ≥0; store/currency raw+trimmed; date validated (default today) |
| PR2 | price capture is **independent of the food log** — no day/item created or modified |
| PR3 | **skippable at zero cost** — logging a scan item without the price field leaves `priceLog` untouched (no phantom entry); empty price → not saved |
| PR4 | `priceComparison` groups by **(store, currency)**, latest-per-group by date, trend within-group; **cross-currency pair → segmented rows, no shared trend** (£ vs € never compared) |
| PR5 | `storeHistory` → distinct sorted store names (autocomplete source) |
| PR6 | **hostile store name escaped** in the comparison render (closes Phase-1 store-names item; same audit as D12 `normalizeSupplement`) |
| PR7 | restore `normalizePriceLog` coerces (neg price clamped, hostile store kept-raw, bad date blanked/entry-kept, non-8–14 barcode key dropped, unknown keys tolerated); **v2 round-trip exact** |
| PR8 | **ingest leaves `priceLog` untouched** (full-days merge — D8/6) |
| PR9 | export includes `priceLog`; `settings.currency` round-trips |
| PR10 | currency default applied + per-entry stored + **last-used remembered** in `settings.currency` |

| SR1–SR4 | **scan-render coverage** (new): the unified `renderScan` (found + not-found) had no prior committed test — attested-only, so the D18 render refactor re-ran green without exercising it. `applyLookup` drives it now: SR1 found → name + portion + price field; SR2 not-found (valid barcode) → message + kept + manual link + price capture; SR3 invalid barcode → no price capture; SR4 hostile barcode escaped |

`bash tests/run-data-layer.sh` → **234/234**; offline + precache + sw-hash + check-zxing green. Real-browser smoke: found product → portion picker + inline price field + comparison render.

**Status: Slice 3 machinery CERTIFIED (234/234; render path now committed-tested). Light UX attestation only — the inline field is ignorable.**

### Phase 2 gate claim

Walking the v4 Phase 2 gate against committed, re-runnable evidence plus signed on-device attestations — same discipline as the Phase 0 claim (machinery certified + real-world attested; the history-free-repo rule keeps real data out, so only the attestation is recorded). `bash tests/run-data-layer.sh` → **234/234**; `check-precache`, `check-sw-hash`, `check-zxing`, `offline-gate.ps1` all green.

| v4 Phase 2 criterion | Committed evidence | On-device | Status |
|---|---|---|---|
| Scanned real product logs correct macros+micros at a **custom gram amount** | **OF1** map · **OF7** portion scale (macros+micros, one factor) · **OF10** scan item (`scan`/`measured`/barcode); live-edge smoke on real OFF (Nutella 539 kcal, **sodium 42.8 mg**) | **A1** — real product scanned → OFF → correct data → logged (iOS) | **MET** |
| **Absence ≠ zero** (no labeled iron → no iron, not 0) | **OF2** missing micro omitted; zero micros → no `micros` key · **OF8** absent stays absent under scaling | property proven by machinery; A1 real product | **MET** |
| Rescan **offline** resolves from cache | **OF11** cache-first (`finishLookup` offline→cache); `offline-gate.ps1` (shell + ZXing offline) | **A7** — offline scan on device | **MET** |
| **Unknown barcode** degrades without losing the code | **OF16/OF17/OF19** (OFF 404 = not-found, not offline; barcode kept); live not-found smoke (`070074679259` → `missing`) | not-found re-check — reads **"Not in OpenFoodFacts"** | **MET** |
| **Camera-denied / no-camera** messages correct | **CAM1** `err.name` matrix (every message ends in the literal manual escape hatch) · **CAM2** precondition gates the Scan button | **A2** denied — signed; **A3** no-camera — **N/A** (below); **A-NR** camera-in-use — **N/A** (below) | **Message logic MET (committed); A3/A-NR conditions N/A on iOS** |
| **Price entries** recorded, grouped by store, **skippable at zero cost** | **PR1–PR10** (independent of food log; zero-cost skip; (store,currency) grouping, currency-safe trend; escaped; round-trip) · **SR1–SR4** render · real-browser smoke (price field + comparison) | light UX — the inline field is ignorable; covered by committed + smoke | **MET** |

Also attested on device: **A4** (ZXing on real iOS — the genuine BarcodeDetector-absent path), **A5** (teardown — camera indicator off), and the **auto-advance** scan→lookup handoff re-check (no manual tap). The SW content-hash / no-`skipWaiting` update lifecycle is validated in production (D6); its home-screen delivery latency for distributed users is a recorded **Phase-4** candidate (D6 forward note), not a Phase-2 gap.

**Three attestations recorded N/A — honestly, not as MET, not as fails.** Each is an iOS/hardware constraint, not a defect; the underlying logic is committed-tested where one exists:
- **A6 (vibrate) — N/A.** iOS does not implement the Vibration API. The call is feature-detected (`if (navigator.vibrate)`) inside a try/catch, so it no-ops silently; **detection is unaffected**. Confirmed in code.
- **A-NR (camera-in-use / `NotReadableError`) — N/A.** iOS hands the camera to the foreground app rather than refusing, so `NotReadableError` does not surface (opening the Camera app then scanning in HealthTracker still scanned fine). The message *logic* is committed (**CAM1**); the *condition* can't be forced on iOS.
- **A3 (no-camera device) — N/A.** Awkward to force on the attesting hardware; skipped and noted. The precondition/message logic is committed (**CAM2/CAM1**).

**Attestation**
- Attester: Thomas Seiler (repo author)
- Date: 2026-07-17
- Device: iOS home-screen PWA (WKWebView → ZXing-only detection path)
- Passed: A1, A2, A4, A5, A7 + scan-flow re-checks (not-found message; auto-advance handoff)
- N/A (with reasons): A3 (no-camera hardware), A-NR (iOS foreground camera hand-off), A6 (no iOS Vibration API)

**Phase 2 gate: MET** — machinery CERTIFIED (234/234 + offline/precache/sw-hash/check-zxing) and on-device attested. Three attestations are N/A by iOS/hardware constraint (flagged above, not counted as MET); every gate criterion's logic is committed-tested, and the reachable-on-iOS attestations all passed.

---

## Phase 4 — Expansion (correlation-engine destination, D19)

### Slice G — force-and-notify updates (D6 amendment) — MET (machinery); on-device attestation pending

Replaced the rejected gesture-bar design. `tests/update-gate.ps1` (CDP): a shell change → the new SW **auto-activates on load** (skipWaiting+claim), the new shell goes live with **no gesture**, and the client stayed open. `tests/check-version.sh`: `APP_VERSION` carries a `VERSION_LOG` line and a shell change since the last commit without a bump fails. Notice logic (from→to, multi-version accumulation, downgrade-safe, fresh-install suppression) + render committed as **VN1–VN6**. Harness → 245/245; offline + precache green; real-browser notice smoke verified. **On-device (signed after deploy by reopening):** "Updated to vX" with the changelog, no force-quit — one-time transition may show the old bar once.

### Slice T — timeline substrate + manual biometric / event adapters (D20) — PRE-REGISTERED

Fully local — entirely committed, no attestation. Schema v3 (the data-safety bump). Gate clause: the generic source-agnostic store, its zeroth (manual) adapter, and the day overlay, with cross-version safety and no food-log double-count.

| Case | Asserts |
|---|---|
| TL1 | `addSignal` → normalized record in `timeline[date]`; `value` clamped ≥0; `source:manual` forced; time/type/kind coerced |
| TL2 | **events ≠ food items** — a signal creates no `day.item` and doesn't change `dayTotals` (no double-count) |
| TL3 | `normalizeSignal` contract: raw→canonical; unknown `type` tolerated+preserved; `source` tolerated as string |
| TL4 | `SIGNAL_SPEC` 1:1 `type→unit`, no cross-wiring (incl. `breath_ketones`/`steps`/`mood`/`energy`/`red_light`/`hbot`); `kind` biometric/event/**medication**; `other` uses `notes` for its label |
| TL5 | `timelineForDay` merges food + events + biometrics + medication **time-sorted** |
| TL6 | **schema v3**: v2→v3 adds empty `timeline`; **v1→v2→v3 chain**; forward-guard rejects `>3` (boot protects, restore rejects); pre-migration snapshot retained |
| TL7 | restore `normalizeTimeline` hardens (bad date key dropped, `value`/`dose` clamped, hostile `notes`/`type`/**medication `name`/`prescriber`** kept-raw, unknown keys tolerated); **v3 round-trip exact incl. a full-detail medication record** |
| TL8 | export includes `timeline`; **ingest leaves `timeline` untouched** (D8/6) |
| TL9 | hostile `notes`/`type` **and medication `name`/`prescriber`** escaped in the overlay render |
| TL10 | units **per-record** + last-used default remembered in `settings.signalUnits`; sane-range soft warning fires non-blocking |
| TL11 | **medication kind**: `name` required; `dose` clamped ≥0; `dose_unit`/`form`/`route` closed-enum validated with tolerant fallback (no cross-wiring, M1-style); quick path (name only) valid; full-detail round-trips exact |
| TL12 | **BP paired entry**: `logBP(120,80,t)` → two records (`bp_systolic`=120, `bp_diastolic`=80) at the same `time`, correctly separated, no cross-wiring |
| TL13 | **alcohol** event: optional count + notes; creates no `day.item`; `dayTotals` unmoved |

`bash tests/run-data-layer.sh` → **target: all PASS**; `APP_VERSION → 0.4.0` (check-version); offline + precache + sw-hash + check-zxing green.

**Status: Slice T MET — 273/273 (TL1–TL13); committed + deployed as v0.4.0.**

### Quick-log chips — Layer-1 adherence (D21) — MET

Layer-1 adherence per D21 (**ease-of-logging is the mechanism of action**): a curated, horizontal-scroll chip strip at the top of the signal card — now moved **directly under the day view**. One tap sets the type + unit, reveals the BP pair when relevant, and **focuses the value box** → tap, type, Log. Fully local — committed, no attestation.

Forks ruled: **fixed-curated order now** (adaptive → Layer 2); **event chips included**; **horizontal-scroll, no cap**; card **directly under the day view**. Goals-derived precedence — a signal type with a goal floats to the unscrolled front (curated order among floated, then the rest), recomputed **only on goal add/remove**, never a live reshuffle from readings.

> **Wired-but-dormant (ruled (A), forward-ready):** the goals-float mechanism reads `settings.goals`, but goals are **nutrient-only in the UI today**, so signal-type goals aren't settable and the float **cannot fire yet** — every user gets the pure curated order. It lights up when Layer-2 makes signal goals settable. Deliberately **not** forced into the food ring/strip to fire early: signal targets are a **different shape** (latest-reading / trend, not summed intake) that belongs to Layer-2 mirror work; wiring them into `goalProgress`/`dayTotals` would be the force-into-the-wrong-schema mistake the project refuses. The dormant mechanism costs nothing and Layer 2 inherits it working.

| Case | Asserts |
|---|---|
| TL14 | chip order = curated default with no goals; a goal-set type (hrv, bp) floats first in curated order (no dupes/drops); a non-goal type stays after; strip renders one `<button>` per curated signal; **`pickSignal` sets the type and creates NO record (prefill only)**; **chip-logged record `JSON.stringify`-IDENTICAL to dropdown-logged** — one `normalizeSignal`/`addSignal` contract, never a second code path |
| TL15 | **unit picker** (v0.4.2): the unit field is a native `<select>` offering the type's `SIGNAL_SPEC` alternatives (breath_ketones → ppm + mmol/L; weight → kg + lb); single-unit types show one; BP forced to mmHg; last-used unit pre-selected next time |

Unit-picker note (v0.4.2): the free-text unit input became a per-type `<select>` — tap it to switch kg/lb, mg/dL·mmol/L, ppm·mmol/L. A native select is the only reliably-tappable picker on iOS (datalist is not); this drops free-typing a custom unit, which the sanctioned per-type set makes unnecessary and which helps the Layer-2 trend-normalization pin (a remembered non-spec unit is still preserved as an option, so nothing logged is lost).

**Desktop-scroll fix (v0.4.3).** Bug (desktop-only): the horizontal strip scrolled by touch but a mouse wheel scrolled the page, no visible scrollbar — ~10 of 14 chips unreachable (worse than the rejected ~8 cap: the cutoff was arbitrary window width, not a chosen ranking). Root cause the `.wrap` column is **480px-capped on every viewport**, so "wide viewport" never widens the strip — the real "can't swipe" signal is **pointer type**. Fix: on `@media (hover:hover) and (pointer:fine)` the strip **wraps to rows** (`overflow-x:visible`) — pointer-based, so a *narrow desktop window* wraps too (a width-only breakpoint would strand the mouse there); plus a `min-width:600px` wrap, a visible scrollbar on hover devices, and JS **wheel→horizontal** translation (guarded: only while the strip overflows and isn't at an edge) as belt-and-suspenders. Touch keeps the compact one-row scroll strip.

Reachability gate — **`tests/chip-layout-gate.ps1`** (CDP, real `index.html`). The prior "14 chips rendered" assertion was on the **wrong property** — it passed while 10 were unreachable. This asserts reachability by emulating devices: **A** mouse/narrow 380px → wrapped, >1 row, **0 clipped**; **B** touch/phone 380px → one-row scroll strip (overflow present, reachable by swipe); **C** mouse/wide 1100px → wrapped, 0 clipped. Discriminating: B's own numbers (overflow, 1 row) are what the pre-fix strip did everywhere, and A demands the opposite.

**Process note (routine):** the app now has **two real surfaces** — every release gets a phone-first on-device pass *and* a **desktop mouse-and-window pass** (resize narrow↔wide, wheel/scroll, hover affordances). Touch-only-affordance bugs are exactly the class only a desktop human finds; `chip-layout-gate.ps1` automates the chip case, but the manual desktop pass stays in the checklist.

`bash tests/run-data-layer.sh` → **284/284 ALL PASS**; `pwsh tests/chip-layout-gate.ps1` → PASS (A mouse/narrow wrapped 0-clipped, B touch scroll, C mouse/wide wrapped); real-browser smoke (14 chips, Weight first, chip→focus on the value box, BP chip reveals the diastolic pair; unit select renders kg/lb); `APP_VERSION → 0.4.3` (check-version); offline + precache + sw-hash + check-zxing green.

**Status: MET — v0.4.1/0.4.2 committed + deployed; desktop-scroll fix follows as v0.4.3 (each also a force-and-notify test).**

### Slice X — fasting candidates + universal undo (D22) — PRE-REGISTERED

Three-state fasting per D19/D22: derived candidates, persisted resolutions (only human judgment stored), pending = absence, mirror-never-nag. Plus a universal **undo** on every log path (protection is undo, not confirmation). New capability → **`APP_VERSION → 0.5.0`**; new top-level store `fastLog` → **schema v4** (same cross-version-safety reasoning as v3/D20).

**Flagged fixture edits (legitimate schema evolution, not silent):** the v3 data-layer fixtures move to **v4** — version `3 → 4`, blob gains `fastLog`, forward-guard `>3 → >4` (future-blob cases become `version 5`), `settings` gains `fasting`, `migrateV3toV4` chained. All pre-existing assertions keep their meaning; only the version number and the added store change.

| Case | Asserts |
|---|---|
| FX1 | gap boundaries: 15h59 → 0; **16h → 1** `{start,end,hours}`; 11h overnight → 0; **18h cross-midnight → 1** correct span; 40h multi-day → 1; two qualifying gaps → 2; a trailing/lone item (no food after) → **0** (bounded-gap, no in-progress candidate) |
| FX2 | **`kcal>0` breaks a fast**; a 0-kcal drink mid-gap does **not**; the **`_auto` supplement mid-gap does not** (candidate persists); a real `kcal>0` item mid-gap **does** (splits the gap) |
| FX3 | **three-state discipline**: a pending candidate (no `fastLog`) and an `ate_didnt_log` are both excluded from `confirmedFasts()`; only `fasted` counts; **macro averages (`averageOver`) byte-identical** with vs. without `fastLog` data (fasting never touches food totals) |
| FX4 | **resolution round-trip**: resolve → `exportJSON` → `parseImport`/`restore` → `fastLog` entry `{state, resolved_by, start, end, hours}` exact; `normalizeFastLog` drops non-resolved / bad-key entries (pending = absence), clamps `hours≥0`; **`resolved_by:'biometric'` tolerated** (Pin-2 seam) |
| FX5 | **`ingest` never touches `fastLog`** (restore's job, D8/D20) |
| FX6 | **schema v4**: `migrateV3toV4` adds empty `fastLog`, version 4; `migrateToLatest` chains v1→…→v4; forward-guard rejects `>4` (v5); a v3 blob migrates → gains `fastLog` + version 4 |
| FX7 | **tolerance-matched identity + inert orphan**: a resolution survives a ±<15 min boundary-meal shift (still matched); an orphaned resolution (no matching candidate) is retained in state (round-trips) but **not** in `confirmedFasts()` (inert, not deleted) |
| FX8 | **config + off-switch**: default `{enabled:true, minHours:16}`; `enabled:false` → `detectFastCandidates()` returns `[]`; a `minHours` change alters detection |
| UN1 | **undo seam**: `doUndo()` within the window removes the just-created record **by reference** (food item from `day.items`; a signal from `timeline[date]`; **BP removes both**); state saved; nothing else changed |
| UN2 | **fast-context undo**: a food log ending a ≥minHours gap creates a candidate ending at that item; undo removes the item → `detectFastCandidates()` recomputes to the pre-log state (candidate gone), **no repair logic** |
| UN3 | happy path: instant add, **no confirmation dialog** on any log path; after the undo window the record persists and stays removable the normal way |

`bash tests/run-data-layer.sh` → **315/315 ALL PASS** (FX1–FX8, UN1–UN3; v3→v4 fixtures updated — tests 1/2/4/7/8/9/14/I8/TL6); real-browser smoke (candidate row + 2 resolve buttons on the end day; resolve → `fasted` → row shows done; `confirmedFasts()`=1; fasting settings form; toast renders a working Undo button); `APP_VERSION → 0.5.0` (check-version); offline + precache + sw-hash + check-zxing + chip-layout green.

**Ingest-undo scope (flagged):** undo covers the five single-record log paths in full; ingest gets a **batch undo on the AI-paste item channel** (removes the pushed item refs). The **full-days merge channel** (wholesale day replace) has **no toast-undo** (it's a restore-like bulk merge with its own report), and undo removes only the records — not ingest's day-create/reopen side-effects. Deliberate: ingest is a non-reflexive deliberate paste; the amendment's reflexive-mis-entry target is the single-record paths.

**Status: MET — committed + deployed as v0.5.0.**

### Resume-check — "resumes count as loads" (D6 amendment refinement) — MET

On-device gap (v0.5.0): the force-and-notify apply check runs on **load**, but an iOS home-screen PWA resumed from the app switcher never navigates, so an old version lingers until a real launch. Fix (v0.5.1): a **throttled `visibilitychange` resume-check** — on becoming visible (~5 min throttle), `reg.update()`; a new SW then force-applies + notices through the **same** `controllerchange`→reload path a load uses. Not the rejected gesture-bar (no bar/button/message); `swnow=1` zeroes the throttle as a test seam. Bootstrap caveat: the check ships *in* v0.5.1, so v0.5.1 arrives on a real launch; releases after it can arrive on a resume.

`tests/update-gate.ps1` extended: a two-level shell bump proves auto-apply on **LOAD** (token) **and on RESUME** (token2 via a dispatched `visibilitychange`, **no navigation**, page controlled). Gate PASS (v1 active · load-applies · controlled · resume-applies); `APP_VERSION → 0.5.1` (check-version); data-layer 315/315 + offline + precache + sw-hash + check-zxing + chip-layout green.

**Status: MET — committed + deployed as v0.5.1.**

### Layer 2 — Mirror slice (D23) — PRE-REGISTERED

The *feedback* half (D21): descriptive self-trends that make the baseline visible. **Read-only** over food/timeline/fastLog → **no schema change, no migration.** `APP_VERSION → 0.6.0`. v1 = single-variable trends (Tier 1); the Mirror/Advise line runs through **who initiates the pairing** (user-selected juxtaposition = mirror; app-initiated = a Layer-4 hypothesis). Factual summaries only — **no evaluative/prescriptive language.**

| Case | Asserts |
|---|---|
| M1 | **unit normalization (the pin):** a weight series mixing kg + lb collapses to ONE unit (converted, not mixed); glucose mg/dL↔mmol/L converts; **non-convertible** units (breath-ketones ppm vs mmol/L) are **excluded** from the off-unit series with a coverage note, never force-converted |
| M2 | **trend assembly:** time-ordered series per type over a window (30/90/all); factual summary latest/min/max/avg/delta/n correct |
| M3 | **fasting stats:** count/avg/longest from `confirmedFasts()` **only** — a pending or `ate_didnt_log` candidate never moves a stat |
| M4 | **fasting streak (pin):** consecutive **confirmed**-fast days; a pending day in the window surfaces **"N unresolved — resolve to update"**, never silently inflating (pending≠fasted) or hiding that resolving could change it |
| M5 | **macro trend:** complete-days-only (agrees with `averageOver` semantics; in-progress days excluded); labeled **"complete days only"** |
| M6 | **min-data/empty:** below the point threshold → honest empty state, no fabricated trend |
| M7 | **safety invariant (grep-able):** the rendered Mirror contains **no** evaluative/prescriptive vocabulary and (v1) **no** asserted cross-variable relationship — structural, like the honesty gates |
| M8 | **escaping:** every rendered label/value through `esc()` |

`bash tests/run-data-layer.sh` → **328/328 ALL PASS** (M1–M8); real-browser smoke (2 sparklines weight+energy; window 90d→30d switch; fasting streak; "complete days only" label; transparency note); `APP_VERSION → 0.6.0` (check-version); offline + precache + sw-hash + check-zxing + chip-layout green.

**Status: MET — committed + deployed as v0.6.0.**

### Signal goals — biometric targets + chip-float awakened (D24) — PRE-REGISTERED

Biometric goals settable → the D21 wired-but-dormant chip-float wakes at zero churn (it already reads `settings.goals`). **No schema change.** `APP_VERSION → 0.6.1`. `settings.goals` becomes a **mixed namespace** (nutrient keys = daily-sum goals on the food ring; signal-type keys = latest-reading goals on the Mirror + float) under a **mandatory-filter contract** (D24). Mirror goal display is **fully neutral** — factual text + neutral dashed reference line, **no met/unmet color** (a color cue is "good" re-encoded past the M7 grep).

| Case | Asserts |
|---|---|
| SG1 | `setGoalFromForm` routes a signal type → `settings.goals[type]` `{value,direction,unit}`; a nutrient → `{value,direction}`; **food ring/strip renders ONLY nutrient goals** — and its rendered output is **BYTE-IDENTICAL with vs. without a signal goal present** (the filter proven by output equality, FX3 pattern — not merely "filtered") |
| SG2 | **chip-float wakes** — a signal type with a goal floats to the unscrolled front; no goal → curated default (extends TL14) |
| SG3 | Mirror renders the goal **reference line + factual "target ≤/≥ V unit · latest L"**, **unit-normalized** (kg goal ↔ lb series); a **non-convertible** goal unit (ppm goal vs mmol/L series) surfaces the mismatch, **not force-converted / not drawn** |
| SG4 | **latest-reading, direction-aware** basis (floor short-when-under, ceiling over-when-above) correct; **no evaluative status word** rendered |
| SG5 | round-trip — a signal goal (incl. `unit`) survives export/restore exact |
| SG6 | escaping — a hostile goal unit escaped in the Mirror render |
| SG7 | **safety invariant holds with goals present** — Mirror with a signal goal contains no banned/evaluative vocabulary (extends M7) |

`bash tests/run-data-layer.sh` → **341/341 ALL PASS** (SG1–SG7; **zero existing-fixture edits**); real-browser smoke (2 reference lines weight+HRV, factual targets, HRV chip floated, unit hint, no evaluative text; real index.html has the Biometrics optgroup); `APP_VERSION → 0.6.1` (check-version); offline + precache + sw-hash + check-zxing + chip-layout green.

**Status: MET — committed + deployed as v0.6.1.**

### Layer 3 — Nudge slice (D25) — PRE-REGISTERED

Paced, **established-practice-only** good-habit nudges, unlocked by an **engagement** milestone (never by reading content — that's Layer 4). Delivery machinery is code; the **curriculum is content** (`NUDGE_CURRICULUM`, builder-authored). State in `settings.nudges` → **no schema change**. `APP_VERSION → 0.7.0`. Accept = a **current focus with a factual adherence line** (occurrence counts/dates of an optional `linkedType`, never values; absence never a lapse) — the wear-indicator, not the scold (Fork B override).

| Case | Asserts |
|---|---|
| **NG-safety-offer** | the **offered** nudge + readiness are **BYTE-IDENTICAL under a wholesale swap of all reading values** (day count held constant) — the offer keys on engagement, never on what the data says (Pin 1, FX3-style) |
| **NG-safety-focus** | the **focus adherence line** reads the linked type's occurrence **timestamps only** — **byte-identical when the linked records' values are swapped** (counts/dates unchanged) |
| NG1 | **readiness (engagement-only):** silent before 7 distinct logged days + 7 days elapsed; the auto-supplement doesn't count; first eligible habit offered at threshold |
| NG2 | **pacing:** one at a time, curriculum order; after a resolution the next is silent until the interval elapses |
| NG3 | **accept = focus + factual adherence:** counts/dates only, no %/streak/color, **no compliance capture**; unlinked habit → no line; 0 occurrences → neutral (never a lapse); no new offer while a focus is active |
| NG4 | **decline permanent:** never re-offered by the engine; snooze re-eligible only after the window; **browse view lets the user re-activate any habit themselves** |
| NG5 | **off switch:** `enabled:false` → fully silent |
| NG6 | **round-trip preserves markers:** `settings.nudges` (states + **`at` timestamps**) survives export/restore **exact**; `normalizeNudges` hardens bad input; a decline survives (never resurfaces) |
| NG7 | **language safety (extends M7/SG7 to the nudge surface):** no evaluative-about-the-user vocabulary, no user-data reference, absence-never-a-lapse; all curriculum text escaped |

`bash tests/run-data-layer.sh` → **363/363 ALL PASS** (NG1–NG7 + both split byte-identical safety invariants); real-browser smoke (ready → offer "A short walk after dinner" → accept → focus with "walk logged 2 times in the last 7 days · last: Sun" → browse shows all 7); `APP_VERSION → 0.7.0` (check-version); offline + precache + sw-hash + check-zxing + chip-layout green. **No schema change; only the flagged `settings.nudges` addition to the S1/S2 fixtures.**

**Status: MET — committed + deployed as v0.7.0.**

### Regimen slice (D27) — PRE-REGISTERED

A named **timeline template** for a repeating day — composition over presets/medication/events, **never auto-logged, never a fourth record system**. Top-level `regimens` store → **schema v5**. `APP_VERSION → 0.8.0`. JSON paste-authoring (D26); weekday-mapped daily checklist on the day view; scheduled-time-default instantiation with surfaced-lateness; window = metadata; substitution by acknowledgment.

| Case | Asserts |
|---|---|
| RG-identity | an instantiated entry is **byte-identical** to the equivalent manual log at the same time (food via the shared `buildPresetItem`; med/event via `addSignal`) — **no regimen tag** on the record |
| RG-never-auto | **no record without a confirm** — render/day-switch/boot write **zero** records; only the explicit Log action writes |
| RG-late | **surfaced-lateness:** `isGrosslyLate` (>~2 h) correct; a grossly-late Log **needs confirmation** (surfaces the scheduled time), never silently backfills |
| RG-weekday | today's checklist = entries matching today's weekday (`days` absent = every day); a Tue entry never shows on Wed |
| RG-window-decoupled | the declared window is **never** read by `detectFastCandidates` — candidates byte-identical with vs. without a regimen window |
| RG-history | editing/deleting a regimen leaves already-logged records untouched |
| RG-substitute | "logged elsewhere" writes a **fulfillment flag, ZERO** timeline/day records |
| RG-no-automatch | ingest/scan/manual logging sets **no** fulfillment flag |
| RG-no-double | tapping a **fulfilled** row **needs confirmation** (never silent double-log); same-day un-acknowledge clears a substitution flag |
| RG-distinguish | fulfillment records `template` vs `substituted` (the future-adherence marker) |
| RG-roundtrip | `regimens` (templates + fulfillment log) survives export/restore **exact**; `normalizeRegimens` hardens; v4→v5 migration adds it; forward-guard rejects `>5` |
| RG-authoring | `parseRegimen` rejects with **specific per-entry messages**; **`REGIMEN_SAMPLE` parses clean** (self-consistency, like `AI_PROMPT_SAMPLE`) |
| RG-escaping | all rendered template text (names, notes, med names) escaped |
| RG-empty | no active regimen → the checklist renders **silently empty** |

`bash tests/run-data-layer.sh` → **388/388 ALL PASS** (RG-identity … RG-empty; v4→v5 fixtures updated); real-browser smoke (paste → 3-row checklist + window; Log at 12:00 scheduled time, row marks done; substitute writes a flag with 1 record; template renders on load); `APP_VERSION → 0.8.0` (check-version); offline + precache + sw-hash + check-zxing + chip-layout green. **Flagged v4→v5 fixture updates** (version, +`regimens`, forward-blob 5→6, `migrateV4toV5`, S1/S2 +`regimens`).

**Status: MET — built, all gates green; awaiting review before commit/deploy as v0.8.0.**

### Timezone-offset capture slice (D29) — PRE-REGISTERED

Additive, **capture-only** `tzo` (device UTC offset, whole minutes, east-positive) on every record-creation path. **No schema bump** (stays v5, Fork 1); nothing consumes the field yet. `APP_VERSION → 0.8.1`.

| Case | Asserts |
|---|---|
| TZ-sweep-stamp | **every stamped creation path** writes a valid `tzo` equal to the device offset: manual add · preset log · **regimen food instantiation** · scan · supplement injection (rollover **and** enable-time) · signal chip/form · medication form · `logBP` (both records) · **regimen med/event instantiation** · price entry · fasting resolution |
| TZ-sweep-exempt | **every exempt write site** adds **no** `tzo`: AI-paste ingest · full-days merge · restore · `migrateV*` · pre-restore backup · fulfillment flag · preset save · goals/supplement/nudge/fasting/regimen config · `addWater` |
| TZ-census | **`tests/check-writesites.sh`**: the set of record-write sites in `app.js` matches the pinned manifest — **a new write site fails the gate** until it is registered stamped or exempt |
| TZ-identity | **D27 Pin 2 holds:** an instantiated regimen food record stays **byte-identical** (`tzo` included) to the equivalent manual preset log at the same time |
| TZ-foreign | **Pin 3:** a paste carrying **no** offset stays offset-**absent** (never stamped with the ingesting device's zone); a paste carrying a **valid** offset **keeps that value**, not the local one |
| TZ-hostile | **Pin 4:** `999999`, `-999999`, `"abc"`, `NaN`, `null`, `{}`, `[]`, `true` → **dropped to absent, never clamped**; `"-240"` coerced to `-240`; `240.4` rounded; boundary `±840` accepted, `±841` dropped — at **paste and restore** boundaries |
| TZ-preserve | `tzo` survives **export → restore exact** on **all four record kinds** (day items, timeline signals, price entries, fastLog) and through **v1→v5 migration** of a blob that carries it |
| TZ-inert | **Pin 1 — zero behavior change:** day totals, averages, `detectFastCandidates`, `confirmedFasts`, trends, micro rollup and the rendered day view are **byte-identical** with vs. without `tzo` present on every record |
| TZ-absent-flows | **Pin 2:** pre-capture records (no `tzo`) flow through day view / averages / Mirror / fasting / export **unchanged from today's behavior** |

`bash tests/run-data-layer.sh` → baseline before the slice was **388/388 ALL PASS**; must stay green and grow only by the TZ cases. **No schema change** (v5, no fixture version edits, no new migration).

#### Evidence (run 2026-08-30)

- `bash tests/run-data-layer.sh` → **427/427 ALL PASS** (388 baseline + 39 TZ cases; **no pre-existing case altered**, no fixture version edits).
- **`tests/check-writesites.sh` → OK (13 sites, manifest matches)**, wired into the runner ahead of the browser pass. It **earned its keep during the build**: it flagged `focusAdherence` as an unregistered write site. That one is a read-side false positive (it pushes dates into a display array), and it was **classified exempt in D29 rather than pattern-matched away** — the pattern stays deliberately over-broad so a real write cannot slip past it.
- Other gates green at the same tree: `check-precache` PASS · `check-sw-hash` OK (re-fixed for the app.js change) · `check-zxing` OK · `check-version` OK (0.8.0 → **0.8.1**, changelog line present) · `offline-gate.ps1` PASS · `chip-layout-gate.ps1` PASS · `update-gate.ps1` PASS.
- **Real-browser smoke on the actual `index.html`:** `{"schema":5,"app":"0.8.1","deviceTzo":-240,"itemTzo":-240,"signalTzo":-240,"exportTzo":-240,"uiLeaksTzo":false,"uiShowsKcal":true}` — stamped on a manual item and a signal, present in the export, **absent from the rendered UI**, day view otherwise normal, no page errors.

**Status: MET — built, all gates green; awaiting review before commit/deploy as v0.8.1.**

### Single entry point (D30) — PRE-REGISTERED

Presentation only. Main surface = **display + attestation**; **authoring/config → a flat settings list**; one persistent `+` sheet with Scan (default) / Quick / Photo · AI paste / Manual + two secondary entries. **No schema change (v5), no data written, no migration.** `APP_VERSION → 0.9.0`.

| Case | Asserts |
|---|---|
| SE-enum | **ruling (4):** settings is **flat single-level** and **every** relocated capability is a **named top-level entry** — regimen authoring, goals, daily supplement, presets, fasting, habits, AI prompt, export, import/restore — enumerated by name, so burying one a level deeper fails |
| SE-attest | **ruling (2):** the **regimen checklist**, **nudge offer** and **fast-candidate resolution** are on the **main surface** (today's state + one-tap response), while their **configuration** is not |
| SE-modes | the `+` sheet opens with **Scan default**, and Quick / Photo · AI paste / Manual are reachable; the two secondary entries (event-or-biometric, medication-or-supplement) are present at its foot |
| SE-quick | Quick renders **one chip per saved preset**, logging via the same `logPreset` path (byte-identical record); **preset names escaped**; empty preset list → a silent, honest empty state |
| SE-paste | **ruling (3):** Photo mode reaches the **paste field directly** and it is the **four-shape ingest** boundary (full-export merge still reachable); **destructive Import/Restore is NOT on that surface** |
| SE-separation | Import/Restore lives **only** in settings and **never** shares a surface with merge-ingest |
| SE-invariants | the nine ruled invariants hold unchanged: events/biometrics out of food totals · averages complete-days-only · pending fasts count nothing · AI-paste macros-only+stripped+eyeballed · ingest never overwrites a day with items · restore backs up first and surfaces it · supplement off-by-default/flagged/non-deletable · habits one-at-a-time/never-notification/one-tap-pass/permanent-decline · **data-layer suite green at its current count** |
| SE-escaping | every rendered field on the new surfaces escaped (preset/goal/store/regimen names) |
| SE-noschema | schema version **unchanged at 5**; **zero** records written by opening/closing the sheet or settings, or by switching modes |

**Gate (ruling 5):** the re-verification sweep above **plus the builder's attestation that the reorganization costs the daily flow zero**. The **cold-start criterion is DEFERRED, not dropped** — kit pre-registered in D30 (fresh install, one real barcode-bearing item, *"log what you'd eat today,"* honest logged item unaided within minutes), firing **if and when distribution happens**.

#### Evidence (run 2026-08-30)

- `bash tests/run-data-layer.sh` → **461/461 ALL PASS** (427 baseline + 34 SE cases). The DOM cases load the **shipped `index.html` into an iframe**, so they assert the real markup rather than a fixture of it.
- **No IDs and no handlers were lost in the restructure** — diffed the shipped page against `HEAD:index.html`: `lost ids: []`, `lost handlers: []`. The move was done by a script that extracts each card verbatim and re-emits it, so no panel content was retyped.
- Other gates green: `check-precache` PASS · `check-sw-hash` OK · `check-zxing` OK · `check-version` OK (0.8.1 → **0.9.0**) · `check-writesites` OK (13 sites) · `offline-gate.ps1` PASS · `update-gate.ps1` PASS · `chip-layout-gate.ps1` PASS.
- **Real-page smoke:** `{"sheetClosed":"hidden","settingsClosed":"hidden","fab":"visible","sheetOpen":"visible","defaultModeScan":true,"scanPane":"visible","quickPane":"visible","scanPaneHiddenAfterSwitch":"hidden","sheetClosedAgain":"hidden","settingsOpen":"visible","settingsEntries":9,"mainDayVisible":"visible","schema":5,"app":"0.9.0"}`.

**One gate mechanic changed, and it is not a weakening.** `chip-layout-gate.ps1` measured `#sigChips` on the main surface; the quick-log chips now live inside the `+` sheet's *log event or biometric* entry, so the strip is hidden until opened and the gate measured a collapsed element. The script now **opens the sheet before measuring**; **every assertion is unchanged** — chips still must wrap to all-reachable rows on mouse and keep the one-row scroll strip on touch. Re-run confirms 4 rows / 2 rows / 1 scrolling row, 0 clipped.

#### Ruling (5) attestation — SIGNED

- Attester: Thomas Seiler (repo author, primary user)
- Date: 2026-08-30
- **The reorganization costs the daily flow nothing.** Checklist, chips and resolutions are where expected.
- Signed against v0.9.0 as deployed.

**Status: MET — machinery gated (461/461) and the builder attestation SIGNED.** The cold-start criterion stays **DEFERRED, not dropped**, kit pre-registered in D30; it fires if and when distribution happens.

#### Follow-up from the attestation pass — v0.9.1 (presentation only, no behaviour change)

The attestation pass surfaced two presentation defects. Both are **display-layer only**; no data, no schema, no behaviour.

| Case | Asserts |
|---|---|
| SE-labels | the **two entry points carry permanent labels**, not icons: the `+` reads **"+ Log"**, the settings control reads **"Settings"** |
| SE-history | **"All days" is collapsed to one line by default**, expandable in one tap, and the collapsed state **resets on reload** (the `<details>` lives in the shell with no `open` attribute, so re-rendering never collapses it mid-use either) |
| SE-history-counts | the collapsed line **carries counts that match the expanded list** — `logged` equals the rendered row count and `in progress` equals the flagged rows, both computed from the same key set, so the line can never disagree with what it hides |

**Why the labels matter more than they look.** On a display-only surface these are the **only two doors**, so ambiguity there does not read as "an unlabelled button" — it reads as **"where did everything go."** Fixed with permanent labels rather than a one-time hint, because a hint is spent on first launch and the ambiguity returns for every later encounter.

`bash tests/run-data-layer.sh` → **469/469 ALL PASS** (461 + 8: SE-labels ×2, SE-history ×3, SE-history-counts ×3). **SE-attest unchanged and still green.** `APP_VERSION → 0.9.1`.

**Status: MET.**

### Lab-panel ingestion — PRE-REGISTERED, FORKS OPEN (awaiting ruling; NOT built)

A **dated lab panel** enters as **biometric records with `source: 'lab'`** — the outcome layer the correlation engine (D19) was aimed at. Curated starter set (14): **ApoB, LDL-C, HDL-C, triglycerides, HbA1c, fasting glucose, fasting insulin, hs-CRP, 25-OH-D, ferritin, ALT, AST, eGFR, TSH**. Per-record units; manual entry transcribed from a lab report; **D32 jurisdiction ranges displayed against the values**; visible on the timeline and in Mirror.

**D-number to be assigned on ruling.** No code written. The forks below are surfaced, not resolved.

#### What is already free (verified against the substrate, not assumed)

- **`source: 'lab'` needs no schema change.** `normalizeSignal` already tolerates `source` as an arbitrary string ("extensible", D20) — the adapter seam D19 designed is doing its job.
- **Trends and Mirror need no change per analyte.** `signalSeries(type, days)` is type-generic.
- **Lab types would not flood the quick-log chips.** `CHIP_DEFAULT` is a curated 14-entry subset, and the goal dropdown in `index.html` is a hand-written optgroup — neither auto-enumerates `SIGNAL_SPEC`.

#### Fork A — panel as ONE record vs PER-VALUE records

**Per-value** (each analyte its own timeline record sharing a date): rides the existing substrate exactly, trends/Mirror/units work with no new machinery, and it honors D19's "one abstraction, many adapters" plus D27's "**never a fourth record system**". Cost: the *panel* becomes an implicit grouping (date + `source:'lab'`) rather than an entity, so "delete this panel" is an N-record operation.
**Panel-as-one-record**: makes the panel an entity, but is a second record shape — new normalizer, `signalSeries` blind to it, and the thing D27 explicitly warned against.
*Sub-fork if per-value wins:* an optional **`panelId`** on the record makes grouping **exact** instead of inferred (and survives two panels from two labs on one day). Additive optional field, `tzo`-shaped.
**Leaning: per-value, with `panelId`.** Not ruled.

#### Fork B — extend `SIGNAL_SPEC` vs a lab SUB-REGISTRY

**Extend**: 14 rows added to `SIGNAL_SPEC`; zero new machinery. Cost: it puts ApoB in the same picker as *Sauna*, and D32 requires **range metadata (source, citation, version, per-jurisdiction bands)** that **no other signal has** — a field 14 of 35 rows would use.
**Sub-registry** (`LAB_SPEC`, its own shape carrying D32's cited/versioned ranges) **merged into `SIGNAL_BY_TYPE` at load**: one lookup table at runtime, so `normalizeSignal`, `signalSeries` and `chipLabel` need **no change**, while authoring and versioning stay separate. Cost: two registries to keep consistent — the merge is the seam, and would need its own gate case.
**Leaning: sub-registry merged at load.** Not ruled.

#### Fork C — schema implications

On the D29 asymmetry test: the **values** are ordinary signal records (already covered); **`panelId`** is a *grouping key* — losing it degrades grouping but loses no data, so it reads as **precision, not content** → **no bump**, explicit allowlist addition in `normalizeSignal` (the `tzo` pattern). D32's jurisdiction **declaration** is a `settings` field; the **ranges themselves** are shipped, versioned constants, **not user data**. **Net: likely no schema bump at all** — flagged as a fork rather than assumed, because "additive, therefore free" is exactly the reasoning D29 had to correct.

#### Fork D — quarterly cadence

Labs arrive ~quarterly; the trend machinery is day-windowed (`TREND_WINDOW`, `windowCutoff(days)`), so a 4-points-a-year analyte renders as an **empty sparkline** in a 30-day window. Options: (i) lab analytes default to an **all-time / last-N-panels** window; (ii) a distinct **panels view** — dated panels with per-analyte delta vs the previous panel; (iii) both.
**This collides with D32 and the collision must be ruled, not absorbed:** D32 gates a trend row on a **"sustained multi-week trend"**. With quarterly data there is no multi-week series — the gate has to be restated in **consecutive panels** ("two successive panels outside the band"), or D32's persistence rule silently never fires for labs, which would be the wrong kind of quiet.

#### Fork E — units and conversion

Lab units are jurisdiction-split (mg/dL vs mmol/L lipids/glucose; ng/mL vs nmol/L for 25-OH-D; ferritin, insulin and TSH each with their own conventions). `UNIT_CONVERT` currently covers **only `weight` and `glucose`**, and `convertUnit` returns `null` for anything unmapped — which **silently excludes** that reading from a series. So: ship **per-analyte conversion factors**, or **store as entered and never convert** (honest, but a user who switches labs gets two incomparable series). Unmapped-and-silently-dropped is the one option that must not be chosen by default.

#### Dependency, stated plainly

Displaying ranges against readings **is D32's mechanism**, so this slice is **D32's first consumer**: the **sourced/cited/versioned bar must be met for all 14 analytes, Canada first**, before anything displays. That is **content work, not code**, and it is the long pole — a range shipped without its citation would breach D32 on the slice that introduces it.

**Forks A–E RULED (2026-08-30) → built as D34.**

| Case | Asserts |
|---|---|
| LB-A | a panel writes **one record per value** sharing a `panelId`; a blank row is *not measured*, not an error; the panel is a **derived grouping**, never a record of its own |
| LB-B | `LAB_SPEC` merges into the runtime `SIGNAL_BY_TYPE` at load, so `signalSeries`/`chipLabel` need no change — and **no lab analyte reaches `SIGNAL_SPEC`, the picker, or the chip strip** |
| LB-C | **older-app preserve:** an app that does not know the analyte still keeps the record (unknown `type` tolerated); `panelId` + the lab-report interval round-trip **exact**; **schema unchanged at 5** |
| LB-D | **1 point → band stated factually, no trend claim; ≥2 consecutive panels in the same band → trend row; ≥3 points → direction.** GATE: **a single out-of-band value is never silently un-displayed** |
| LB-E | per-analyte factors (LDL/HDL 38.67, TG 88.57, glucose 18.0182), 25-OH-D ×2.496, insulin ×6.945, **HbA1c by the NGSP/IFCC formula** (round-trips). GATE: **no analyte ever vanishes from a series** |
| LB-content | **three** guideline-banded analytes (each with org + citation + version + `CA`), **two** risk-stratified CCS overlays, **eleven** banding from the lab report's printed interval; **no interval entered → no band claimed** |
| LB-risk | **CCS lipid targets are risk-stratified, so they may never be this user's band.** With no printed interval entered a lipid claims **no band**; the CCS figure rides as a **labelled overlay** carrying its applicability and the statement that **the app does not know the user's risk category**; **no overlay analyte carries guideline bands**, so an overlay can never become a band |
| LB-safety | an unknown analyte writes nothing; lab values never enter food totals |
| M1 *(changed)* | **contract change, recorded not quietly updated:** M1 asserted the OLD exclusion behaviour. It now asserts the new one — the unconvertible reading is **kept, flagged `converted:false`, labelled with its own unit** — while statistics and the sparkline still use converted points only |

#### Evidence (run 2026-08-30)

- `bash tests/run-data-layer.sh` → **528/528 ALL PASS** (469 baseline + 59 lab cases: M1 rewritten to the ruled contract, `LB-risk` for the CCS adjustment, `LB-boundary` and `LB-attest` for the signed content).
- The statistics line now carries the **micronutrient coverage idiom** — *"avg over N of M readings (K unconverted, shown as entered)"* — gated on a mixed-unit biometric series.
- Other gates green: `check-precache` PASS · `check-sw-hash` OK · `check-zxing` OK · `check-version` OK (0.9.1 → **0.10.0**) · `check-writesites` OK (13 sites) · `offline-gate.ps1` PASS · `chip-layout-gate.ps1` PASS · `update-gate.ps1` PASS.
- **Real-page smoke** (shipped `index.html`, 14-row panel form, one panel saved): `{"fabLabel":"+ Log","settingsLabel":"Settings","historyCollapsed":true,"historyLine":"All days · 1 logged · 1 in progress","labPane":"visible","labRows":14,"written":3,"panelIdShared":true,"showsApoB":true,"showsBand":true,"showsCite":true,"showsLabInterval":true,"doctorLineOnce":1,"schema":5,"app":"0.10.0"}`.

#### Content attestation — SIGNED

- Attester: Thomas Seiler (repo author, primary user)
- Date: 2026-08-30
- **Verified against the guideline documents**, with three required edits applied before signing.

| Analyte | Shipped | Source | Version | Kind |
|---|---|---|---|---|
| HbA1c | `< 6.0 %` below diabetes range · `[6.0, 6.5)` prediabetes · `≥ 6.5 %` diabetes range | Diabetes Canada Clinical Practice Guidelines | 2018 | band |
| Fasting glucose | `< 6.1` below IFG · `[6.1, 7.0)` impaired fasting glucose · `≥ 7.0 mmol/L` diabetes range | Diabetes Canada Clinical Practice Guidelines | 2018 | band |
| 25-OH vitamin D | `< 75 nmol/L` below sufficiency · `≥ 75` at/above sufficiency | Osteoporosis Canada — **Hanley et al., CMAJ 2010** | 2010 (reaffirmed 2024) | band + disclosure |
| ApoB | target `≤ 0.80 g/L` | CCS — **Pearson et al., Can J Cardiol 2021** | 2021 | overlay (risk-stratified) |
| LDL-C | target `≤ 2.0 mmol/L` | CCS — **Pearson et al., Can J Cardiol 2021** | 2021 | overlay (risk-stratified) |

**Edit 1 — CCS lipid overlays.** Numbers confirmed correct (2021 general intensification threshold for statin-indicated patients). The applicability line now also states the **stricter very-high-risk secondary-prevention tier** (LDL-C ≥ 1.8 mmol/L / ApoB ≥ 0.7 g/L / non-HDL-C ≥ 2.4 mmol/L) and that **CCS prefers non-HDL-C or ApoB over LDL-C when triglycerides exceed 1.5 mmol/L**. Citation corrected to **Pearson et al., Can J Cardiol 2021**.

**Edit 2 — 25-OH-D.** Number and 2010 origin confirmed; citation corrected to **Hanley et al., CMAJ 2010**, version recorded as **"2010 (reaffirmed 2024)"** per Osteoporosis Canada's Dec-2024 position statement, so the entry cannot read as though a 15-year-old document were the latest word. **Required disclosure added to the band:** *"Health Canada/IOM and many Canadian labs define sufficiency at 50 nmol/L; your lab's printed interval may differ from this target."* The lab's printed interval is now storable and **displayed alongside a guideline band on every analyte**, not only where it *is* the band. The in-app note was reworded so nothing implies the app recommends testing — **Osteoporosis Canada does not recommend routine population screening**, and the surface is a record of panels the user already has.

**Edition check — Diabetes Canada 2018 confirmed CURRENT (2026-08-30).** Flagged at sign-off as the one version string carrying residual uncertainty, since the numbers had been verified but the edition had not. Confirmed current by the attester; **no version change needed**, and `LAB_GUIDELINE.dc` stays at `2018`. All three cited sources now have both their numbers **and** their editions attested: Diabetes Canada 2018, Osteoporosis Canada 2010 (reaffirmed 2024), CCS 2021.

**Edit 3 — boundary semantics.** The comparison was **already half-open `[min, max)`** — verified before editing, so 6.5 % and 7.0 mmol/L always banded as the diabetes range. What was wrong was the **label and documentation wording**, which read as inclusive. Labels now state the range explicitly ("6.0 to under 6.5%"), the comparison carries a *never change `<` to `<=`* note at the line, and **six boundary cases are gated** (`LB-boundary`): 5.9 / 6.0 / 6.4 / 6.5 for HbA1c and 6.0 / 6.1 / 6.9 / 7.0 for fasting glucose.

| Case | Asserts |
|---|---|
| LB-boundary | **half-open `[min, max)` at every threshold** — a reading exactly at 6.5 % or 7.0 mmol/L bands as the **diabetes range**, never below it |
| LB-attest | the CCS overlay states the **stricter secondary-prevention tier** and the **TG > 1.5 non-HDL-C/ApoB preference**, cited to Pearson 2021; 25-OH-D cited to Hanley 2010 with the 2024 reaffirmation and the **required 50 nmol/L disclosure**; a guideline band and the lab's printed interval **render together**; **nothing implies the app recommends testing** |

**Status: MET — machinery gated (528/528) and the content attestation SIGNED with its three required edits applied.**

#### On-device pass follow-up — v0.10.1 (presentation only, no behaviour change)

On-device pass of v0.10.0: **update notice showed both changelog lines** (0.9.1 + 0.10.0 — correct, since both shipped in one push and the device jumped 0.9.0 → 0.10.0). **Defect found: the lab-panel form was cramped at phone width.**

**Same class of miss as the v0.4.1 chip smoke.** The harness asserted *14 analyte rows rendered* — structurally true, and unusable: four controls on one line at 360 px squeezed the value field, **the one a human types into**, to **64 px**, while three fixed-width neighbours (unit select, two reference inputs) held their space. A structural assertion cannot see density, so it gets the same answer the chip strip got — **measure the property that actually matters**.

**New gate: `tests/lab-form-gate.ps1`.** CDP measures the real `index.html` at 360 / 390 / 900 px and asserts **usable density**: value input ≥ 88 px, each reference input ≥ 56 px, unit select ≥ 74 px, **zero truncated analyte names**, no horizontal overflow. It was **written first and run against the unfixed form, where it FAILED** (value 64 px at 360 px) — a layout gate that cannot reproduce the reported defect is worthless.

**Fix (presentation only):** two lines per analyte — name + hint, then value + unit, then the optional printed interval on its own line. The sheet body also takes the app's 480 px column on desktop instead of running full-bleed.

| Width | Before | After |
|---|---|---|
| 360 px | value **64 px** → FAIL | value **216 px** → PASS |
| 390 px | value 94 px | value **246 px** |
| 900 px | value 574 px (full-bleed) | value **321 px** (480 px column) |

`bash tests/run-data-layer.sh` → **528/528 ALL PASS** (unchanged — the element ids the cases drive are the same). `lab-form-gate` PASS · precache · sw-hash · zxing · version (0.10.0 → **0.10.1**) · writesites · offline · chip-layout · update all green.

**Status: MET.**


### Rhythm ring (Layer 2 Mirror) — PRE-REGISTERED, FORKS OPEN (awaiting ruling; NOT built)

A **24-hour circle for the selected day** as the day view's centerpiece, with arcs for **eating, sleep, exercise and the fasting gaps between** — every arc **derived from logged records, nothing inferred**. Target `APP_VERSION → 0.11.0`. **D-number assigned on ruling.** No code written.

**Not presentation-only.** The conflict-(ii) addendum makes `primaryNutrient` a **persisted setting**, so this slice touches storage and carries the storage discipline: an explicit normalizer allowlist addition, validation, and an export/restore round-trip gate. Everything else in the slice remains display-layer.

#### Ruled (building to these, not re-opening them)

1. **Centerpiece.** The rhythm ring replaces the goal ring in the day view's centre position. A **"now" hand on today only**.
2. **Goal swap.** Tapping a goal chip swaps the centerpiece to that goal's existing **neutral** progress ring for **~12 s** (a constant, no setting), then reverts. Tapping a different goal restarts the timer; tapping the ring reverts immediately. **Display only — no data, no persisted state.**
3. **Ring per day**, following the existing prev/next navigation; past days show their full rhythm.
4. **Week and month views** as grids of small tappable rings (7 / calendar month), same derived arcs at reduced detail.

**Arc definitions are honesty-bound** as ruled: eating from food timestamps with the actual window = first→last logged food and the regimen's **declared** window only as a faint reference beneath (D27: template is the plan, log is the reality); fasting drawn factually, today's open gap labelled *"Nh since last logged food"* — **never "fasting," never a zone** (D22); confirmed fasts as full arcs, **pending candidates as gaps labelled pending** with one-tap resolve from the ring; exercise from event time + duration; sleep as a **bedtime→wake interval** with `sleep_hours` **derived**, and existing hours-only readings drawing **no arc** (honest absence). **No zones, no metabolic bands, no achievements, no evaluative colour** — categorical only, and the **M7 vocabulary invariant extends to every ring label**.

#### Verified against the substrate before arguing (not assumed)

- **Exercise is arc-ready today.** Events carry `time` + `value` in minutes (`sauna`, `walk`, `workout`, …) — a start and a duration, which is exactly an arc.
- **Fasting is arc-ready today.** `detectFastCandidates()` already returns `{start, end, hours, state}` with `start`/`end` as `YYYY-MM-DDTHH:MM`.
- **Sleep is NOT.** `sleep_hours` is a scalar: `time` is when it was *logged*, `value` is hours. There is no bedtime.
- **`renderGoalsHTML` filters `isNutrientGoal`** — the goal strip is **nutrient-only by D24's explicit "mixed-namespace filter contract."**

#### Conflicts surfaced — these need rulings too, not just Forks A–F

**(i) There is no "signal goal chip" to tap.** Ruling 2 says *"tapping any goal chip (nutrient or signal goal)"*, but only **nutrient** goals have a goal-strip cell. A **signal** goal has no cell — per D24 it surfaces as a **floated quick-log chip**, and tapping that chip **logs** (`pickSignal` → jump to the value box). Wiring the swap onto those chips would **regress D21's fastest logging path**, the thing that slice existed to create.
*Proposal:* add a **separately-filtered signal-goal cell group** to the goal strip; **tapping a cell swaps**, quick-log chips keep logging untouched. **D24's nutrient-only filter contract for the ring math is unchanged** — the new cells are a second group, never fed into the ring's numbers.

**(ii) The primary-nutrient selector's fate — RULED (addendum).** `.primsel` is retired from the day view; the goal cells become the selector. **But `PRIMARY_NUTRIENT` stays USER-SETTABLE and moves to settings** — the upcoming photo-meal slice ranks items by contribution to the user's primary goal nutrient, so the user needs somewhere to declare it. **A UI removal in this slice must not orphan a setting the next slice depends on.**

**This ruling changes the slice's character, and the record must say so.** `PRIMARY_NUTRIENT` is today a module-level `let … = 'kcal'` that is **never persisted** (`setPrimary` mutates it and re-renders; it does not touch state). Making it a declared setting turns a display variable into **stored user data**, so the rhythm-ring slice is **no longer presentation-only** and picks up the storage discipline the working rules attach to that:

- **`normalizeSettings` is an allowlist rebuild** (the same trap as `tzo` and `panelId`): `primaryNutrient` must be **explicitly listed** there or it is silently dropped at every restore.
- **Validate against `RING_NUTRIENTS`, not against the goals map.** D24 warns that goal keys are a **mixed namespace** — nutrient and signal keys share it. An unvalidated setting would let a *signal* key (`weight`, `hrv`) become the "primary nutrient" and reach the ring math that D24's filter contract exists to keep nutrient-only.
- **Schema: no bump.** Settings-side additions have precedent without one — `currency` (D18), `signalUnits` (D20), `fasting` (D22), `nudges` (D25). On D29's asymmetry test a dropped `primaryNutrient` costs a **one-tap re-declaration**, not authored content, so it is precision rather than content. Recorded eyes-open: an older app restoring the export **silently drops the declaration** and the next slice falls back to its default.
- **Default: absent, and derived — not stored as `'kcal'` at first boot.** Unset → **protein if a protein goal exists, else kcal**, which is exactly the rule the photo-meal slice describes. Storing a default the user never chose would fabricate a declaration, and absence stays a first-class state as everywhere else in this codebase.
- **Home: inside the existing `Goals` settings entry**, not a new one — it *is* a goal-display choice, and this keeps the flat settings list and **`SE-enum` unchanged** (a new top-level entry would require amending that gate).

**Still flagged for ruling:** retiring `.primsel` is a **user-facing removal** inside a slice otherwise framed as additive.

**(iii) Fast-candidate resolution must not silently move.** `SE-attest` (D30) gates that **fast-candidate resolution is on the main surface** via `#fastCandidates`. Making the ring "the primary resolution surface" is fine; **deleting the list is not**, and would either break that gate or quietly narrow a ruled attestation affordance.
*Proposal:* **keep both** — the ring is the primary surface, the list remains the enumerable one. If the list is to go, that is a deliberate `SE-attest` amendment, ruled, not a side effect.

**(iv) The sleep chip retarget interacts with D24's chip-float.** If bed→wake becomes a new type, `CHIP_DEFAULT` still lists `sleep_hours`, and `chipHasGoal` floats a chip when a goal exists **on that type**. A user with a `sleep_hours` goal would float the **scalar** chip while the entry path moved to the interval.
*Proposal:* the chip targets the interval type for entry, and `chipHasGoal` treats a `sleep_hours` goal as satisfying it — one mapping rule, stated, rather than two sleep chips.

**(v) M7's list is a substring grep.** Extending it to ring labels is right, but note it does **not** currently ban `"fasting"` — D22's prohibition on labelling a trailing gap *"fasting"* is a **separate, ring-specific assertion** and must be gated as its own case, not assumed to fall out of M7.

#### Forks — argued, not resolved

**A. Sleep across midnight.** Two questions are being asked as one, and conflating them is what makes the ring lie. **Ownership** (which day's record it is, what `sleep_hours` attributes to) → the **wake day**, as leaned. **Drawing** → **split by clock**: each day's ring draws only the portion that actually elapsed within that day. Whole-arc-on-wake-day would render a 23:30 segment on a day when nothing happened at 23:30 — an inferred arc, which the honesty rule forbids. *Different questions, different answers, each its own truth* (the D29 Fork-2 shape). Mitigation for "two arcs could read as two sleeps": the crossing end draws **uncapped/open** so it reads as continuing.

**B. Schema for the sleep interval — no bump, and no new shape.** The existing event record already **is** an interval: `time` = start, `value` = duration. Bedtime→wake fits it exactly, as workouts already do. The real problem is a **discriminator**: an old `sleep_hours` record (`time` = when logged, `value` = hours) is byte-identical in shape to an interval and would draw a bogus arc. *Proposal:* use **the type as the discriminator** — a new `sleep` type for intervals, legacy `sleep_hours` untouched and arc-less. This needs **no normalizer change at all**: `normalizeSignal` already tolerates unknown types and an older app preserves the record (gated by `LB-C`), so "existing readings remain valid and draw no arc" becomes automatic rather than conditional. **Strictly better than a bump**, which would make an older app reject the export outright. Per D29's asymmetry test this is not even an additive field — it is a new **value** in an already-open enum.

**C. Clock seam — and it is needed twice, not once.** The 12 s timer needs an injected clock, and so does the **"now" hand**, or the ring is untestable at a fixed time. *Proposal:* one `nowMs()` indirection with a test override (the `opts.now` shape already used by `logRegimenEntry`), driving both. **Day navigation cancels the swap** as leaned — navigation changes the ring's subject, so an overlay from the previous day must not survive it. One more rule needed: an **incidental `refresh()` must NOT cancel** the swap, or a background re-render would revert it mid-look.

**D. Week/month placement — a dedicated Rhythm card below the day view**, as leaned. Trends is numeric and the mini-rings are **navigational** (tap → go to that day), which is day-view behaviour, not trend behaviour; mixing them muddies both. Placing it directly under the day card keeps ring→ring adjacent.

**E. `tzo` — NO, and stated in the record.** The ring draws **wall-clock**. D29 was ruled capture-only; making the ring its first consumer would silently change what a travel day looks like without a ruling of its own. **The rhythm ring is not the first consumer of the D29 offset.**

**F. Empty and sparse days — render the ring, empty.** Hiding it would make the centerpiece appear and disappear, which is worse for a first-run user and inconsistent with the day view being a display surface (D30). An empty 24-hour circle also **teaches the shape**. On sparse days arcs draw only where records exist and **nothing is interpolated** — "no arc without a record" holds at every density. The empty ring must not imply zero intake; day totals already carry that.

#### Gate (to be finalised with the rulings)

| Case | Asserts |
|---|---|
| RR-derived | the ring model is derived from the **same records as the timeline**: **no arc without a record**, and **every record of an arc-bearing kind produces its arc** (set equality, both directions) |
| RR-swap | the goal swap **alters no data** (export byte-identical across a full swap cycle) and **reverts deterministically** via the injected clock; a second goal restarts the timer; a ring tap reverts immediately; **day navigation cancels**; an incidental refresh does not |
| RR-sleep | `sleep_hours` **derived** = interval duration; a legacy hours-only reading stays valid and draws **no arc**; the midnight-crossing case draws per the Fork-A ruling |
| RR-pending | **pending gaps never draw as confirmed**; a pending arc is labelled pending and its one-tap resolve is reachable from the ring |
| RR-trailing | today's open gap reads **"Nh since last logged food"** — never "fasting", never a zone (D22); asserted as its own case, since **M7 does not ban that word** |
| RR-window | the regimen's **declared** window draws only as a faint reference, **visually distinct** from the eating arc derived from logs (D27) |
| RR-vocab | the **M7 invariant extends over every ring and mini-ring label**; no evaluative colour, categorical only |
| RR-mini | week/month mini-rings **match their day rings** (same derived model at reduced detail); each navigates to its day |
| RR-empty | a zero-record day renders an **honest empty ring**, not a hidden one, and implies nothing about intake |
| RR-primary | `settings.primaryNutrient` **round-trips export → restore exact**; it is an **explicit `normalizeSettings` allowlist addition**; a **signal-goal key is rejected** (validated against `RING_NUTRIENTS`, never the mixed-namespace goals map); **unset stays unset** and derives protein-if-protein-goal-else-kcal rather than being written at boot; **schema stays at 5** |
| RR-unchanged | **`SE-attest` and every existing gate unchanged**, including fast-candidate resolution remaining on the main surface, and **`SE-enum` unchanged** because the control lands inside the existing Goals entry |

#### Evidence (built to the ruled leanings, 2026-08-31)

- `bash tests/run-data-layer.sh` → **559/559 ALL PASS** (528 baseline + 31 rhythm cases, `SG1` rewritten to the ruled contract).
- Other gates green: `check-precache` · `check-sw-hash` · `check-zxing` · `check-version` (0.10.1 → **0.11.0**) · `check-writesites` · `lab-form-gate` · `chip-layout-gate` · `offline-gate` · `update-gate`.
- **Real-page smoke:** `{"ringRendered":true,"hasEatArc":true,"hasSleepArc":true,"hasExerciseArc":true,"nowHand":true,"primselGone":true,"nutrientCell":true,"signalCell":true,"swappedToGoalRing":true,"revertedToRhythm":true,"miniRings":7,"primaryNutrientControl":true,"app":"0.11.0","schema":5}`.

**Two flagged fixture/contract updates, neither silent:**
1. **`goalState` fixture** gained `primaryNutrient: ''` — cases 7 and 8 deep-compare settings, so the ruled addendum required it (the D27 "flagged fixture updates" precedent).
2. **`SG1` rewritten**, because conflict (i) changed the contract it encoded. The replacement asserts D24's real invariant *more* tightly — see the D35 entry.

#### Centerpiece scale — v0.11.1 (presentation only)

The ring renders at `min(80vw, 360px)`. **New gate: `tests/ring-size-gate.ps1`** measures the real page at 390×844, 360×780 and 1200 px with a seeded regimen, day items and goals.

| Case | Asserts |
|---|---|
| RS-scale | the ring is **≥ 70% of viewport width** on a phone (built at the 80% target), and **capped on desktop** with no horizontal overflow |
| RS-reach | the ruled wording — **checklist above the fold, `+ Log` visible** — plus the assertions that actually bind: the **goal cells** (the ring's own swap affordance) and the **ring caption** (carrying the pending-fast resolve) are **both above the fold** at 390×844 |

**Why the two originally-named measurables cannot bind, recorded so the gate is not read as stronger than it is:** `#regimenChecklist` renders **above** `#dayView`, so ring growth moves it up rather than down; and the `+ Log` pill is `position:fixed`, so it is in the viewport by construction. They are asserted, but they could not have failed.

Measured: **390×844 → ring 312 px (80%)**, all four surfaces above the fold; **360×780 → 288 px (80%)**; **1200 px → 360 px, capped**. The 80% target held, so the ruled fallback (size down until reach is preserved) never fired.

`bash tests/run-data-layer.sh` → **559/559 ALL PASS** (unchanged — this is CSS only). `ring-size` · `chip-layout` · `lab-form` · `offline` · `update` · `precache` · `sw-hash` · `zxing` · `version` (0.11.0 → **0.11.1**) · `writesites` all green.

#### Day-status label + date display — v0.11.2 (presentation only)

| Case | Asserts |
|---|---|
| DS-badge | **today carries no badge**; a **complete past day carries no mark**; a **past unclosed day** keeps the one visible label, and that label **surfaces the silent consequence** (excluded from averages); closing the day removes it |
| DS-logic | the status **binary is unchanged** (`in_progress \| complete`), averages stay **complete-days-only**, and rendering the day view changes **no average** |
| DT-header | the header renders **without a year**, as weekday + month + day, still marking today |
| DT-year | a current-year date shows no year; a **prior-year** date does; a grid range **spanning a year boundary carries both years**; a same-year range carries none |
| DT-history | the all-days list follows the same rule — prior-year entries show the year |
| DT-export | day **keys stay full ISO** and status values export unchanged — display formatting never reaches storage |

#### A gate-integrity defect found while adding these — and it invalidated part of the D35 claim

Adding the cases surfaced that **`finish()` is invoked from the iframe callback**, so a **synchronous throw** in the suite body still printed a **green-looking SUMMARY with a silently reduced count**. It was masking a real fault: **`HT.stepDay` was never exported**, so the RR-swap block threw partway and **every case after it never ran** — `RR-swap` (last two), `RR-empty`, `RR-mini`, `RR-vocab` and **all of `RR-primary`**. The v0.11.0 claim of *559/559* was therefore true only of the cases that executed; **roughly forty D35 assertions never did.**

Fixed three ways: an `error` listener now **records any uncaught synchronous exception as a hard failure**; the missing exports (`stepDay`, `toggleDayStatus`, `renderDay`) were added; and re-running revealed **two genuine failures** in the previously-dead `RR-primary` cases — `defaultSettings()` had **diverged from `normalizeSettings()`**, leaving a fresh state's `primaryNutrient` `undefined` instead of `''`. That divergence is the same drift that produced the earlier fixture mismatch, and is now fixed at the source.

**True count after the fix: 600/600 ALL PASS** (was silently 559 of ~600).

One gate mechanic moved, and it is not a weakening: **`offline-gate.ps1`** probed for the literal ISO string `2026-07-08` in the rendered page, which the new date display replaced with *"Wed Jul 8"*. The probe now accepts either; **the assertion — the seeded day is present and rendered with the network cut — is unchanged.**

`ring-size` · `chip-layout` · `lab-form` · `offline` · `update` · `precache` · `sw-hash` · `zxing` · `version` (0.11.1 → **0.11.2**) · `writesites` all green. Real-page smoke: `{"todayHeader":"Mon Aug 31 · today","todayHasYear":false,"todayHasBadge":false,"pastUnclosedHeader":"Fri Aug 28 not closed · excluded from averages","pastClosedHasBadge":false,"gridLabel":"Aug 22 – Aug 28","exportKeysISO":true}`.

#### Structural fixes + prior-year header — v0.11.3

| Case | Asserts |
|---|---|
| DS-drift | **`normalizeSettings(defaultSettings())` is byte-identical to `defaultSettings()`**, and the normalizer is **idempotent** over the default shape — the divergence that left a fresh state's `primaryNutrient` `undefined` cannot return |
| DT-prioryear | a day from an **earlier year SHOWS its year** in the header — *"Wed Jul 8, 2025"*; **the ambiguity rule governs and the header is not exempt** |

**Assertion-count discipline (standing, enforced).** `EXPECTED_ASSERTIONS` is now pinned in the runner; the executed total must match it, so a silent drop **fails the gate**. Reports print **`executed · pinned · authored-lines`**, the last being a static lower bound (it counts lines containing `res(`, so helper reuse and multi-line calls make it approximate — the pin is what enforces).

**Proven against the real fault, not just written:** re-injecting the v0.11.0 defect (an undefined `HT.*` call mid-suite) fires **both** defences independently — the harness records the uncaught throw, *and* the pin reports `executed 593, pinned 604 (delta -11)`. The pin also caught a mistake while being introduced: it was first set to 605 when the true count was 604, and failed until corrected.

**Count delta for this release: 600 → 604** (+4: `DS-drift` ×2, `DT-prioryear` ×2). `bash tests/run-data-layer.sh` → **604/604 ALL PASS**, `assertions: executed 604 · pinned 604 · authored-lines 601`.

All gates green: `precache` · `sw-hash` · `zxing` · `version` (0.11.2 → **0.11.3**) · `writesites` · `offline` · `ring-size` · `chip-layout` · `lab-form` · `update`.

#### Goal-swap timeout retuned — v0.11.4 (R7)

`GOAL_SWAP_MS` **12000 → 8000**; 12 s read as too long in use. **Constant only** — ring-tap early-revert, restart-on-second-goal, day-nav cancel and refresh-does-not-cancel are all unchanged.

The clock-seam gate **re-runs at the new value automatically**, because the cases read `HT.GOAL_SWAP_MS` rather than a literal. The restart case previously used hardcoded 6000/7000 ms, which sat close to the new boundary; it now **derives its offsets from the constant**, so it stays discriminating at any future value — the second swap must still be live at a point where the first would already have expired. All ten `RR-swap` cases green.

**Assertion count unchanged at 604** (no cases added or removed).

**Gate scope, stated rather than implied:** the data-layer suite and `precache` were re-run. The six CDP layout/lifecycle gates were verified green at 0.11.3 and are **not** re-run here — this change is a single numeric constant with no DOM, layout, network or lifecycle effect.

**Status: MET — built to the ruled leanings, all gates green.**

### Ring fullness (D36 / R8) — v0.12.0

| Case | Asserts |
|---|---|
| R8-trailing | **content equality** — the live window holds exactly the records timestamped in the last 24 h; older content has **aged out**, nothing after the hand is drawn, a record keeps its **clock position**, and the **archival model still holds exactly the calendar day's records** |
| R8-sleep-contiguous | the same night is **one arc on the live ring** (23:00 → 07:00) and **still split by clock on archival rings** — Fork A holds where it applies |
| R8-ghost | plan arcs render **only from declared regimen fields**; with no regimen there are **none**; declared eating + sleep windows are flagged `ref`; scheduled entries draw as rim ticks; a declared sleep window creates **no actual sleep arc**; plan arcs **write zero records**; the field **round-trips**, is **rejected when malformed at authoring** and **dropped when malformed at restore**; **schema stays 5** |
| R8-centre | the centre counts hours since the last logged food, **matches the open gap derived from the same records**, **never says "fasting"**, and surfaces the pending candidate's resolve on tap |
| R8-vocab | **M7 + D22** over every new label — trailing range, ghost, centre, caption; no zones, no metabolic bands; the **open-gap label contains no form of "fast"** |
| ring-size (extended) | arc bands measure **≥ 14 px and ≥ 5% of the ring** at phone widths |

**Six pre-existing cases were repointed, not weakened.** `RR-derived`, `RR-window` and `RR-sleep` asserted **calendar-day** semantics on *today*. R8.1 moves today to a trailing window, so those same invariants now belong to the **archival** model and the cases pass `{live:false}`. **The assertions themselves are unchanged**, and the new behaviour is gated separately rather than by relaxing the old cases.

**Count delta: 604 → 635** (+31). `bash tests/run-data-layer.sh` → **635/635 ALL PASS**, `assertions: executed 635 · pinned 635`. The pin did its job on the way through — it **failed the gate at +31 until re-pinned deliberately**.

`ring-size` (band 20.8 px = 6.7% of ring at 390 px) · `chip-layout` · `lab-form` · `offline` · `update` · `precache` · `sw-hash` · `zxing` · `version` (0.11.4 → **0.12.0**) · `writesites` all green.

**Real-page smoke:** `{"rangeLabel":"last 24 h","centre":"14.1h since last logged food","hasSleepPlanGhost":true,"hasPlanTick":true,"hasSolidSleep":true,"noFastingWord":true,"live":true,"miniIsArchival":true,"schema":5}` — and the smoke showed **no eating arc**, correctly: at the real wall-clock time yesterday's dinner had already aged past the hand, leaving one food in the window.

**Status: MET.**

### Ring display rules (R11) — v0.12.1, presentation only

**1 — Graduated gap counter.** Under **48 h** the centre is a stopwatch (*"47h since last logged food"*); at or past it, a **date** (*"no food logged since Aug 30"*) with **no decimal**. **48 h is the constant** (`GAP_DATE_AFTER_MIN`), chosen because two full days is past any fast this app models and is where "hours since" stops being a number anyone uses. A tenth of an hour on a 46-day gap is **fabricated precision** — the inferred-arc failure arriving by a different route. The pending-resolve tap line survives either form.

**2 + addendum — First-contact surface, not an edge case.** With zero records and no declared regimen the ring draws an **instructional ghost**: three **complete, faint lane circles** labelled *meals · sleep · exercise*, plus the line *"log food or sleep to draw your day."* **Complete circles, never arcs** — a full circle cannot be misread as a stretch of logged time, so it names the lane without inventing a position, a duration or an example number. **Grammar, not content: no fake data, no example numbers** (gated: zero digits in both caption and SVG). It **yields the moment either a record or a declared regimen exists** — with a regimen, the **ghost plan-arcs** carry the empty window instead.

**3 — The now-hand clears the centre.** It runs from the rim **inward** and terminates at `RING_CENTER_R` (0.46·R = 37.7 units), just outside the centre block's 36-unit half-width — measured, not assumed. **No line through text.**

**4 — De-duplicated.** The open-gap row is **dropped from the legend** (the centre carries it); the legend carries the **pending-candidate line with its resolve** instead. The open-gap **arc still draws** — only its legend row went.

| Case | Asserts |
|---|---|
| R11-counter | 47 h → stopwatch, 49 h → date naming the last-logged day; **no decimal past the threshold**; the boundary is exact at 2879/2880 min; the threshold is a surfaced constant |
| R11-first | the instructional ghost renders **only** at zero records **and** no declared regimen: three lane circles, **no `<path>` at all**, labelled, **zero digits anywhere**; **disappears the moment either a record or a regimen exists** |
| R11-hand | the hand no longer starts at the centre point, **terminates at the counter bounding circle**, and still reaches the rim |
| R11-dedupe | the centre carries the open-gap line and the **legend does not restate it**; the open-gap **arc survives**; the legend carries the pending line |
| R11-vocab | **M7 + D22** over every new string; no "fasting" on any gap surface |

**One copy choice, surfaced:** the ruling's example label was *"exercise draw here"*. Rendered, the three keyed labels read as one run-on and the trailing phrase attached only to the third lane, while the hint line already says *"to draw your day"*. The labels are therefore **meals · sleep · exercise**, each with its colour key, and the "draw here" meaning is carried by the hint line.

**Count delta: 635 → 663** (+28). `bash tests/run-data-layer.sh` → **663/663 ALL PASS**, `executed 663 · pinned 663`. The pin again failed the gate at +28 until re-pinned deliberately.

`ring-size` (band 20.8 px = 6.7% of ring) · `chip-layout` · `lab-form` · `offline` · `update` · `precache` · `sw-hash` · `zxing` · `version` (0.12.0 → **0.12.1**) · `writesites` all green.

**Real-page smoke** — first contact, then after one log: `{"firstContact_hintCircles":3,"firstContact_noArcs":true,"firstContact_noDigits":true,"afterLog_hintGone":true,"afterLog_centre":"13.5h since last logged food","afterLog_captionRestates":false,"handInner":37.7,"handOuter":83.6}`.

**Status: MET.**


### Ring redesign — concentric-lane instrument (R13) — PRE-REGISTERED

**Replaces** the current single-ring rendering. Visual spec + architecture bones; **R14 (radial response layer) and R15 (audit view) are named and RESERVED, not authorized** — the bones reserve their geometry and data paths now. Target `APP_VERSION → 0.13.0`. **No schema change intended.**

**Seven concentric lanes**, fixed order in→out: **sleep, eat, exercise, sauna, yoga, meditation, red_light**. **Lane tracks always render** — full muted circles, every lane, every day — so the ring is never bare and every lane is findable. **Empty lane = visible track, no arc.** A clear **outer annulus (~12% of radius) stays reserved and empty** for R14; nothing draws there but the now-hand's tip. **Centre stays display-only** — the graduated gap counter — with the **resolve UI evicted below the ring**.

#### Geometry, computed before building (phone 390 pt)

| ring | rim (0.88·R) | centre | radial band | strokes | gap per lane |
|---|---|---|---|---|---|
| 85 vw = 332 px | 145.9 | **0.46·rim = 67.1** (R11's value) | 78.8 | 64 (12/12/5×8) | **2.46 px** |
| 85 vw = 332 px | 145.9 | **0.40·rim = 58.3** | 87.5 | 59 (12/12/5×7) | **4.75 px** |

**Fork A — R11's centre radius is the binding constraint, and it does not survive seven lanes.** At the ruled 85 vw with R11's `RING_CENTER_R = 0.46` and 8 px event lanes, the seven lanes are separated by **2.46 px** — with rounded caps they read as one mass, which defeats "every lane findable". *Leaning:* **centre → 0.40 of rim, event lanes → 7 px**, giving **4.75 px** gaps; the centre still spans 116 px, ample for a big numeral plus caption at this width. **R11's "hand never crosses centre text" is preserved and re-measured**, not assumed.

**Fork B — eleven event types, seven lanes.** `SIGNAL_SPEC` carries `sauna, cold_plunge, yoga, workout, walk, meditation, red_light, hbot, alcohol, other`. Four duration-carrying types (**cold_plunge, workout, walk, hbot, other**) have **no named lane**, and today they all draw. Dropping them would be a **silent regression from 0.12.x**. *Leaning:* the **`exercise` lane is a bucket** carrying every duration-event not claimed by a named lane, with **each arc keeping its own truthful label** ("Cold plunge 3 min"). The lane groups; the label never lies. `alcohol` carries no duration and still draws nothing, unchanged.

**Fork C — no record has an identity today.** The audit tap-path needs "what did I tap" to resolve to a record, but neither `day.items` nor timeline signals carry an id. *Leaning:* synthesize a **positional reference** (`item:<date>:<index>`, `sig:<date>:<index>`) as a `data-` attribute — **no schema change**, cheap now. Recorded plainly: this is stable **within a render**, not across edits. **If R15 needs cross-session stable identity, that becomes a deliberate schema question then** — not something to smuggle in now.

**Fork D — 85 vw against the REAL usable height.** The reach gate assumes 844 px; Safari's usable height is nearer **745**. The ring grows from 312 → 332 px while the centre gains a numeral and a legend row is added, so the goal cells and caption have **less room, not more**. *This will be measured at 390×745 before the ring size is fixed*, and if reach breaks, **the ruled fallback applies — the constraint wins over the number** and the ring sizes down.

**Fork E — R11's three-circle instructional ghost is RETIRED**, as ruled: the always-present lane tracks are the teaching layer, and they do it better (seven findable lanes rather than three unlabelled circles). The `R11-first` cases are **repointed, not weakened** — they will assert that the **lane tracks** carry first contact, that **no arc draws at zero records**, and that **no digit appears** — the same invariants against the replacement surface.

**Fork F — legend highlight is transient view state.** Tapping a legend key dims the other lanes. *Leaning:* it behaves like the goal-swap — **display-only, nothing persisted, cleared on day navigation** — and it must not fight the flip or the swap.

#### Architecture bones (seams, not features)

- **`rhythmModel` gains a stable per-lane CHANNEL structure**: each lane is a **named channel with typed content** (`span` | `tick`) derived from records — **the same contract a future radial response series uses** (a biometric series is a channel with `kind: 'trace'`, angle-mapped). One contract: lanes now, traces later.
- **Every rendered arc and tick carries its source record reference** as a data attribute (Fork C).
- **`AUDIT_WINDOWS` (R15, named, NOT built):** stimulus × response → default window, **sourced/cited/versioned on the D32 lab-band machinery**, user-adjustable, and **uncited pairs get a generic window LABELED as uncited**.
- **Recorded destination:** **stimulus-aligned ensemble averaging over the user's own history** is the named future analysis this structure feeds — the **first consent-tier analysis candidate**, and **shows-never-attributes governs its framing**. The audit **displays the crowd of causes, never a single-cause fiction**: every other stimulus tick inside the window is shown.

#### Gate (to be finalised with the build)

| Case | Asserts |
|---|---|
| R13-channels | per-lane derivation equality — **every record of a lane kind produces its arc/tick, and no arc exists without a record**, asserted per channel |
| R13-tracks | **all seven tracks render always**, every day including empty ones; an empty lane is a **visible track with no arc** |
| R13-flip | *my day ⇄ the plan* is **display-only, deterministic, always labeled, sticky (no timeout)**; plan view renders **only declared regimen content**; an undeclared practice is an **empty track** |
| R13-swap | goal-swap **suspends** the flip and **revert restores** it; neither writes data |
| R13-centre | the **resolve UI never renders inside the ring** — the centre is display-only, always |
| R13-reserved | **nothing draws in the reserved annulus** except the now-hand's tip |
| R13-ids | **every rendered arc and tick carries a source record reference** |
| R13-palette | the seven hues and the plan-view opacity are **gated constants**, like ring-size; **no red/green good-bad axis** (Fork G holds) |
| R13-geometry | lane radii, strokes and gaps are computed from constants and **do not collide**; the hand terminates **outside the centre text** and **at the reserved band's inner edge** |
| ring-size / density | **re-measured for seven lanes at a REAL phone viewport (390×745)**, not 844 |
| R13-vocab | **M7** over every new label, including lane and legend names |

#### R13.1 amendment — conflict-based allocation (folded in before locking)

The five dedicated practice lanes are **replaced by overlap allocation**: sleep and eat keep anchor lanes; every practice shares one fat lane and a second **spawns only on genuine overlap**. `cat` is identity, `lane` is position. The **flip-stability pin** — assignment from the **union** of plan + actual, shared by both views — is gated, as is **packing determinism**.

#### Evidence (built to the ruled leanings, 2026-09-02)

| Case | Result |
|---|---|
| R13-packing | deterministic in any input order; overlap spawns a lane; a third simultaneous overlap **clamps at the cap** (gated) |
| R13-tracks | one practice lane at rest (3 tracks); an overlap **spawns a second and its track appears**; removing it **disappears again**; stacked practices render as stacked arcs |
| R13-union | `planeBySrc` **identical across views** — an arc never changes lanes between my-day and the-plan |
| R13-flip | sticky, labeled both ways, writes no data; plan view renders **only declared** content |
| R13-swap | a goal swap **suspends** the flip without losing it; revert **restores** it |
| R13-ids | every model mark and every **rendered** mark carries `data-src` |
| R13-reserved | every lane at full stroke stays inside the rim; **no circle is drawn in the annulus**; lane radii do not collide |
| R13-palette | seven distinct explicit hues, **no good/bad tokens**; plan opacity dims rather than greys |
| R13-channels | one channel per category; **every mark belongs to exactly one channel**, and a category with no record has an empty channel |
| R13-centre | the resolve **never renders inside the ring** |

**Fork D bound, and the fix was ordering.** At the real 390×745 viewport an 85 vw ring pushed the goal cells below the fold; the largest reach-preserving ring was **256 px (66%)**. The cause was that the **goal cells rendered after the caption** — an interactive affordance below a read-only detail list. Moving the affordance up took the maximum to **328 px (84%)**. Shipped at **84 vw**, the measured maximum.

**Two gate recalibrations, both stated rather than silent:**
1. The reach assertion now binds on **goal cells + legend** (fixed-height affordances) instead of the **caption**, because the caption is a **variable-length detail list** — requiring all of it above the fold would make ring size depend on how busy the day was, which is incoherent as a size rule.
2. The band threshold was **14 px / 5%-of-ring**, derived from the single-lane design where one stroke was 6.7% of the diameter. **Four lanes cannot each be 5% of the ring.** It now asserts the **ruled sizes in pixels** (≥11 thinnest, ≥13 fattest at the 390 reference) **and their scale-invariant proportions** (≥3.5% / ≥4.1%), so a smaller phone's proportionally thinner bands pass while a genuine thinning fails.

The gate also now **reports the largest reach-preserving ring** at each viewport, so the headroom is visible rather than rediscovered each time.

`bash tests/run-data-layer.sh` → **700/700 ALL PASS**, `executed 700 · pinned 700`. Count delta **663 → 700** (+37). `ring-size` (ring 328 px = 84% of vw, bands 12–14 px, cells and legend above the fold at **390×745**) · `chip-layout` · `lab-form` · `offline` · `update` · `precache` · `sw-hash` · `zxing` · `version` (0.12.1 → **0.13.0**) · `writesites` all green.

**Real-page smoke:** `{"tracks":4,"marksWithSrc":5,"practiceLanes":2,"toggle":true,"legendKeys":7,"resolveInRing":false,"planLabeled":true,"planDim":true,"unionStable":true,"schema":5}` — two practice lanes because the seeded walk and meditation genuinely overlap.

**Status: MET — R13 + R13.1 built. R14/R15 reserved, not authorized.**

### 0.13.1 — on-device bug fixes (D37 follow-up)

Three findings from the real phone. **The synthetic smoke never exercised a window with records AGED OUT of it — which is the ordinary state of a real phone**, and that is what hid both defects.

**1 — Meals lane drew a full ring on a day with no food logged.** With the last food long outside the trailing 24 h, the **open-gap arc spanned the entire window** (1440 min) and drew as a near-complete circle on the meals lane. Two clarifications the report's framing deserves:
- **The lane-channel gate was NOT violated.** The arc *did* trace to a record — the last logged food — so "no arc without a record" held. What was wrong is that **an arc filling the whole window says "meals everywhere", the opposite of what it means.**
- **It was not actually off-centre.** Measured from the rendered SVG, every circle shared `cx=90 cy=90`. The apparent offset was the **round cap on a dashed 359.99° arc**: the two caps overlap into a blob near the closure and the dashes scallop, which reads as a lopsided beaded ring. **Zoom magnified it, and activating the meals badge dimmed everything else, leaving the artifact alone on screen** — which is why it only showed up that way.

*Fix:* a gap that **fills the whole window is recorded but not drawn** — it has no edge to read against, and the centre tenant already states it exactly ("no food logged since Jul 18"). Dashed arcs also take **butt caps** so they can never bead. A gap with an edge inside the window draws exactly as before.

**2 — Legend highlight confirmed correct.** The defect persists un-highlighted (it was the arc, not the highlight), and dimming renders correctly otherwise: with `sauna` active, other marks carry `rdim` and the sauna arc does not.

**3 — Sleep chip produced records that silently drew nothing.** `signalTimeLabel` was **defined and exported but never called**, and `sigTime` has no default — so a chip-logged sleep arrived with `time: ''`, `timeToMinutes` returned `null`, and the record stored without ever drawing. *Fix:* the field is labelled **"Bedtime"** for the sleep interval, and **a sleep record without a bedtime is rejected** rather than stored as an invisible one. A sleep interval is start + duration; without a start it is not an interval at all.

| Case | Asserts |
|---|---|
| BUG1-aged | with food logged but **none inside the trailing 24 h**: the gap is recorded, `suppressed`, **no arc on the meals lane, no path emitted at all**; the centre still states it; a gap **with an edge inside the window still draws** |
| BUG1-concentric | every lane **track** shares one centre constant, and **every arc is circular with both endpoints at its radius from that same centre**, measured from the rendered SVG (tick dots are excluded — they sit at clock positions by design) |
| BUG3-sleepchip | the field is labelled **Bedtime**; a sleep record **without** one is **rejected and nothing is written**; with one it stores as an interval, **draws on the sleep anchor**, and `sleep_hours` still derives from it |

**Count delta: 700 → 713** (+13). `bash tests/run-data-layer.sh` → **713/713 ALL PASS**, `executed 713 · pinned 713`. Verified at **2.4× zoom with the meals badge active**: zero paths, zero full circles.

**Status: MET.**


### R16 — Sleep as toggled segments + badge-summoned centre controls — PRE-REGISTERED, FORKS OPEN

Real nights are fragmented. A single bed→wake interval forces a fiction; a live on/off toggle captures the night as **segments**, and the **mid-night wake gap is itself signal** (fragmentation) — matching the shape device sleep data (HealthKit/Oura, per D28) will eventually deliver into the same channel. Target `APP_VERSION → 0.14.0`. **Nothing built; stopped for ruling.**

**Ruled pins, to be built once the forks are settled:** segments open pending on toggle-on and close into the **existing event record shape** on toggle-off; `sleep_hours` derives as their **sum**; the ring draws each segment on the sleep anchor with **wake gaps visible**; an open segment past a **surfaced ~11 h threshold** becomes a **pending candidate** resolved by the user — **never auto-closed, never auto-trusted**, three-state grammar per D22, counting in nothing while pending; the **morning manual path remains** and a toggle-produced record must be **byte-identical** to a manually entered one; existing hours-only scalars stay valid and draw nothing.

#### Verified before arguing, not assumed

- **`GOAL_SWAP_MS` is already 8000**, so "reuse the swap constant" for the summoned control's idle revert is exact rather than approximate.
- **Every piece of ring view state is module-level** — `RING_VIEW`, `LANE_FOCUS`, `RESOLVE_FOCUS`, `SWAP` — and the **D6 force-and-notify reload** (`index.html:664`) wipes all of it. **An open segment therefore cannot live where view state lives.** That settles the shape of Fork A before the argument starts.

#### Forks

**Fork A — where the open segment lives (the load-bearing one).** It must survive a **mid-night reload, an update, and a force-and-notify claim**. Three options: a **new top-level store** (semantically cleanest, but every prior new store cost a schema bump — timeline v3, fastLog v4, regimens v5); an **incomplete timeline record** flagged open (no bump, free export/restore, but puts a non-record in the record store — the shape D19 warned against when it kept events out of `day.items`); or **`settings.sleepOpen`** (allowlist addition, **no bump**, precedent `currency` / `signalUnits` / `fasting` / `nudges` / `primaryNutrient`).

*Leaning:* **`settings.sleepOpen`** — `{ start: "<date>T<HH:MM>", startedAt: "<iso>" }`. It is **live state, not a record**, so it belongs beside the other persisted live state rather than in the timeline; and on D29's asymmetry test, losing it costs **one re-entered bedtime, not content**. **Gated explicitly against a simulated reload mid-segment** — the resume path must not eat an open night.

**Fork B — a second toggle-on while a segment is open.** *Leaning:* **no-op returning `{ok:false}`**. The summoned control offers only *Sleep off* while open, so this is defensive; silently closing and reopening would **fabricate a segment boundary the user never marked**.

**Fork C — toggle-off within a trivial duration (< 5 min).** *Leaning:* **keep the record and offer undo** (D22's universal-undo grammar) rather than discarding under a threshold. **Discarding is the app deciding a user's record is not real** — a judgment it has consistently refused to make — and undo already covers the accidental double-tap this would protect against. Flagged, because the opposite lean is defensible if junk segments prove to pollute fragmentation.

**Fork D — day ownership of segments.** *Leaning:* the existing **wake-day rule (D35 Fork A) governs unchanged, per segment** — a segment is owned by the day it ends, drawn split by clock on archival rings and contiguous on the live one. **Consequence to rule on explicitly:** a 14:00 nap then lands in the same day's `sleep_hours` as the previous night's segments. Arguably correct as *total sleep that day*, but it is a real semantic choice rather than a side effect.

**Fork E — the summoned-centre contract, and its collisions.**
- **Goal-swap** also occupies the centre. *Leaning:* **mutually exclusive, later summon wins and cancels the earlier**; both display-only.
- **Flip view.** Summoning a *logging* control while showing *the plan* is incoherent. *Leaning:* **summoning returns the ring to "my day" first** — you are about to record actual data.
- **Badge-tap disambiguation** (proposal requested): **highlight rides the summon** — one tap highlights the lane *and* summons its control; a second tap clears both; a lane with no control highlights only. **No long-press** — undiscoverable, and it fights mobile text-selection; a second gesture is not worth buying a distinction nobody asked for.
- The summoned control lives in the **centre**, so it never touches **R14's reserved annulus**.

**Fork F — what an open segment draws, and the live counter's staleness.** *Leaning:* a **pending open arc on the sleep anchor** from start to now (the open-food-gap grammar), plus one quiet **"sleeping · Xh"** line in the resting centre. But **nothing re-renders on a timer**, so that figure is **stale until the next interaction**. *Leaning:* **accept the staleness rather than run a ticking timer** — at 0.1 h resolution the number moves every six minutes, and a timer is real battery cost for a figure nobody is watching. Flagged, because the alternative is a one-line `setInterval` and you may want it.

#### Gate (to be finalised with the rulings)

| Case | Asserts |
|---|---|
| R16-persist | an open segment **survives a simulated reload / update claim** — the resume path never eats an open night |
| R16-segments | a night of multiple segments round-trips export→restore; `sleep_hours` derives as their **sum**; the ring draws each with **wake gaps visible** |
| R16-identical | a **toggle-produced record is byte-identical** to the manual bed→wake record for the same start and duration (the TL14 / RG-identity pattern) |
| R16-forgotten | an open segment past the threshold becomes a **pending candidate**, resolves **three-state**, is **never auto-closed**, and **counts in nothing** while pending |
| R16-summon | the summoned control **reverts deterministically** on action, on the injected-clock idle, and on tap-away; the centre **never sticks in control mode**; the resting centre is **unchanged when nothing is summoned** |
| R16-collide | summon vs goal-swap mutually exclusive; summoning from plan view returns to my-day; the **reserved annulus stays untouched** |
| R16-manual | the morning bed→wake path still works and still requires a bedtime (0.13.1) |
| R16-vocab | **M7** over every new label, including "sleeping · Xh" and the forgotten-off prompt |

#### Evidence (built to the ruled forks, 2026-09-02)

| Case | Result |
|---|---|
| R16-persist | the open segment is **persisted, survives a simulated reload**, round-trips through export, and a malformed one is dropped at the boundary |
| R16-segments | two segments round-trip; `sleep_hours` = their **sum** (one point per day); both draw on the wake day with a **30-minute wake gap visible between them**; the midnight-crossing segment still splits onto the previous day (Fork A holds per segment) |
| R16-identical | a toggle-produced record is **byte-identical** to the manual bed→wake record |
| R16-forgotten | pending fires **past the threshold and not before**; nothing is written while pending; **`sleep_hours` sees zero points**; it asks when sleep ended; resolve and discard both work; an unparseable end resolves nothing |
| R16 (Fork B) | a second toggle-on is a **no-op** |
| R16 (Fork C) | a sub-5-minute segment is **kept**, and **undo is a true inverse** — record removed *and* open segment restored |
| R16-summon | summons, **highlight rides**, control appears, **reverts on idle via the injected clock**, on tap-away; the **resting centre is byte-unchanged** when nothing is summoned; a lane with no action highlights only |
| R16-collide | a summon **cancels the goal swap**; summoning **returns to my-day**; the **reserved annulus stays untouched** |
| R16-manual / R16-vocab | the manual path still requires a bedtime (0.13.1 holds); **M7** over every new label |

**A latent defect surfaced while building.** `nowTime()` was still on the **real** clock while `nowMinutes()` was on the injected seam, so a toggle recorded a wall-clock start whose duration was measured on a different clock. In production both are the same clock — which is precisely why it could sit unnoticed. `nowTime()` now uses the seam, making D35 Fork C's "one clock indirection" true of every path.

**Flagged fixture update:** the `goalState` fixture gained `sleepOpen: null` (cases 7/8 deep-compare settings), the same shape as the `primaryNutrient` addition.

**Count delta: 713 → 762** (+49). `bash tests/run-data-layer.sh` → **762/762 ALL PASS**, `executed 762 · pinned 762`. `ring-size` · `chip-layout` · `lab-form` · `offline` · `update` · `precache` · `sw-hash` · `zxing` · `version` (0.13.1 → **0.14.0**) · `writesites` all green.

**Real-page smoke** (summon → toggle on → 90 min → reload → close): `{"summoned":true,"focusRides":"sleep","control":"Sleep on close","openArc":1,"stateLine":"sleeping · 1.5h","persisted":true,"survivedReload":true,"closedMinutes":150,"recordTime":"22:00","recordValue":2.5,"sleepHours":2.5,"schema":5}`.

**Status: MET.**

### 0.14.1 — on-device findings from 0.14.0 (R17)

**1 — Timeline rows had no delete affordance at all.** Once the undo toast expired, a biometric/event/medication record was permanent in the UI. Each row now carries a `×` that removes it through the **same undo grammar as every other destructive action** (D22), and the undo restores it **byte-identical at its original position**. Food rows already had a delete in the day view.

**2 — The mini-ring grid was broken post-R13: the redesign never reached the minis.** Cause, found rather than guessed: the minis **inherited the main ring's geometry**, and `.rring{overflow:visible}` let the **now-hand (rim × 1.04) and plan ticks (R × 1.07) draw outside the viewBox** — which is exactly why neighbours overlapped and the caption was overdrawn.

Rebuilt deliberately as **digests, not scaled instruments**: their own `miniRingSVG` with its own viewBox and **fixed pixel size**, carrying **only the two anchors** (sleep span + eating window). Seven lanes at 42 px is noise. **No now-hand, no lane tracks, no centre text, and every coordinate inside the box** — so a mini structurally cannot spill onto a neighbour. Label sits under its ring, inside the same button. Tap-to-open unchanged.

*The mini-ring alternative I considered and rejected:* adding a third mark for practice presence. It would answer "did I move that day" at a glance, but a 42 px ring with three bands is the noise the ruling was reacting to, and the anchors already carry the day's shape.

**3 — Light mode was never specced.** The R13 palette was hex constants chosen against dark; **inline hex can only ever serve one theme**, which is how it went unspecced. Lane colour is now a **CSS custom property per category, defined for both themes**, so the browser resolves it natively and a theme switch needs no re-render. Light values are **darker and more saturated** so an arc reads against a white panel; the lane track is themed too, so an arc always has something to read against. **Still no green in either set**, so no green/red pair can read as an evaluation (Fork G).

#### The long-flagged grid density gate — closed

This surface had been **unattested since 0.11.0**, and the 0.14.0 report is precisely what it would have caught. The ring gate now also measures, at the real phone viewport:

| Case | Asserts |
|---|---|
| grid density | **7 rings per row** at 42 px, **zero overlaps**, **zero spill** (every SVG inside its own button), **zero detached labels** |
| theme contrast | **arc-vs-track and arc-vs-background in BOTH themes**, via emulated `prefers-color-scheme` |
| R17-delete | delete removes **exactly one** record, undo restores it **byte-identical**, derived values (the sauna arc) **recompute both ways**; out-of-range targets remove nothing; every row renders its affordance |
| R17-mini | fixed size; **no now-hand, no tracks, no centre text**; the two anchors only, **not** the practice lanes; **every coordinate inside the viewBox**; an empty day is two quiet rings |
| R17-theme | all seven hues defined for **light and dark**, distinct within each, **light tuned rather than copied**, and the track themed too |

**Measured:** grid `7 rings at 42px, 7/row, overlaps=0 spill=0 detached=0`; contrast `light arc/track 2.71, arc/bg 4.14 | dark arc/track 5.61, arc/bg 7.02` — thresholds 1.6 and 2.2, referenced to WCAG's 3:1 non-text guidance, with the arc-vs-track pair set lower because those two are adjacent bands of the same family rather than figure-and-ground.

**Two of my own measurement bugs surfaced while building the gate**, both fixed rather than worked around: the per-row metric divided rings by row count instead of counting the topmost row, and an over-escaped regex left contrast unmeasurable (reporting a sentinel rather than failing). A gate that cannot measure is worse than no gate, because it reads as a pass.

**One real defect the new gate then caught:** `border-box` plus a 1 px border left the button's content box 2 px narrower than `MINI_PX`, so every fixed-size SVG overflowed by 1 px a side — `spill=7`. Sized to 44 px outer / 42 px content.

**Repointed, not weakened:** `R13-palette` asserted *explicit hex, no `var()`* — the exact contract item 3 had to change, since inline hex cannot respond to a theme. It now asserts seven **themed properties**, defined in **both** themes and distinct within each, which is a stronger claim than the hex check was.

**Count delta: 762 → 784** (+22). `bash tests/run-data-layer.sh` → **784/784 ALL PASS**, `executed 784 · pinned 784`. All eleven gates green; `version` 0.14.0 → **0.14.1**.

**Status: MET.**


### R18 — extending the summoned-centre contract to four practices — PRE-REGISTERED

R16 built the summoned-centre contract generically but wired **only sleep**. R18 fills it in: **sauna, meditation and red light** gain toggles in identical grammar, **meals** summons the existing fast-candidate resolve, and **exercise and yoga deliberately get none**. Target `APP_VERSION → 0.15.0`. **No schema bump** (settings-side).

**Why toggles rather than stamps, recorded because it is the load-bearing reason:** a live session yields a **true start time**, and **R14/R15's audit quality depends on t=0 being real**. A stamp records when you remembered, not when it began.

#### Forks

**A — `settings.sleepOpen` generalises to `settings.laneOpen`, keyed by lane, and the migration is the risky part.** An open segment must survive the update that performs the migration — the **mid-night reload case, now per lane**. *Leaning:* fold the old field in inside `normalizeSettings` (which runs on both boot and restore), so a 0.14.x blob carrying `sleepOpen` emerges as `laneOpen.sleep` with **no data loss and no bump**; `defaultSettings()` carries `laneOpen: {}` and no `sleepOpen`, keeping `DS-drift` byte-identical. **Gated explicitly**: a stored `sleepOpen` from the previous version must still be an open sleep segment after boot.

**B — several lanes open at once.** *Leaning:* **allowed**, and it is the point of keying by lane — R13.1 already stacks genuinely overlapping practice arcs, so red light *while* meditating renders honestly rather than being refused.

**C — a segment crossing midnight.** *Leaning:* the wake-day rule (D35 Fork A) applies **per lane, unchanged** — the day it ends owns it, drawn split by clock on archival rings.

**D — per-practice forgotten-off thresholds.** *Leaning, as proposed:* **sauna 3 h, red light 3 h, meditation 4 h, sleep 11 h** — surfaced constants, each a plausible outer bound for that practice rather than one number pretending to fit all four. Past its threshold an open segment becomes a **pending candidate**, three-state, counting in nothing.

**E — the meals summon when nothing is pending.** *Leaning:* `laneHasAction('eat')` becomes **conditional on a pending candidate existing** — with none, the badge **highlights only** and no control appears. **No new semantics**: it is the existing three-state resolve, relocated into the summon.

**F — exercise and yoga get NO summoned action, as a ruling rather than an omission.** Their logging **carries a value** (a workout has a duration and often a distance) or **an attestation** (a regimen checklist row). A bare toggle would create **a second, thinner path to the same record** — the shape D19 warned against when it refused to store events as zero-calorie food items. One record, one path.

#### Gate

| Case | Asserts |
|---|---|
| R18-migrate | a stored `sleepOpen` from 0.14.x **survives the update as `laneOpen.sleep`** — the mid-night reload case, per lane; `defaultSettings` stays drift-free |
| R18-segments | each lane's segment round-trips export→restore and draws on its own cat |
| R18-identical | a toggle-produced record is **byte-identical to the manual record** for that lane — minutes for practices, hours for sleep |
| R18-thresholds | each practice's threshold fires **at its own constant and not before**; pending counts in nothing |
| R18-meals | the meals badge summons the resolve **only when a candidate is pending**; otherwise highlight only |
| R18-noaction | exercise and yoga offer **no** summoned action |
| R18-contract | one action per lane; reverts on action / idle / tap-away; the centre never sticks; the resting centre is unchanged when nothing is summoned |
| R18-vocab | **M7** over every new label |

#### Evidence (built to the ruled leanings, 2026-09-02)

| Case | Result |
|---|---|
| R18-migrate | a 0.14.x `sleepOpen` **survives the update as `laneOpen.sleep`**; the old field stops being emitted; unknown lanes and malformed segments are dropped; **boot normalizes settings identically to restore** |
| R18-segments / R18-identical | all four lanes toggle, close at the clock, round-trip through export, and produce records **byte-identical to the manual path** — minutes for practices, hours for sleep |
| R18-thresholds | sauna 3 h, red light 3 h, meditation 4 h, sleep 11 h; each fires **at its own constant and not before**; a pending segment counts in nothing |
| R18-meals | with no candidate the badge **highlights only** and no control renders; with one, the **existing three-state resolve** appears |
| R18-noaction | exercise and yoga declare **no** action and highlight only |
| R18 (Fork B) | two lanes open at once, each drawing on **its own category**, each named in the resting centre |
| R18-contract / R18-vocab | each lane summons its own control, reverts on idle, resting centre unchanged; **M7** over every lane control |

**A latent defect this slice exposed, predating it.** `boot()` took a same-version blob **as-is** and never ran `normalizeSettings` — it patched settings with **ad-hoc per-key guards** for `fasting` and `nudges` only. So **every settings-side addition since D18 applied on restore but never on boot** (`currency`, `signalUnits`, `primaryNutrient`, `sleepOpen`). Each is read defensively, so nothing broke — **until one needed a real migration**, and the fold silently did not happen. Boot now normalizes identically to restore; the two guards are subsumed and removed; and the key-set equality is gated.

**Flagged fixture update:** `goalState` gained `laneOpen: {}` in place of `sleepOpen: null`.

**Repointed, not weakened:** R16's persist cases read `settings.sleepOpen`, the field this slice generalises. They now read `laneOpen.sleep` and assert the same invariants.

**Count delta: 784 → 836** (+52). `bash tests/run-data-layer.sh` → **836/836 ALL PASS**, `executed 836 · pinned 836`. All eleven gates green; `version` 0.14.1 → **0.15.0**.

**Status: MET.**
