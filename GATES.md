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
