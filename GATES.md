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
