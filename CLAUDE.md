# HealthTracker — Agent Brief (v5)

**This version reframes the product again.** v4 described a distributable nutrition and price tracker. v5 describes an **instrument**: *track inputs, evaluate them against current research, and predict my outcomes* ([[D152]]). Where v4 and v5 disagree, **v5 wins**. Where v3 and v4 disagreed, v4 still wins over v3.

**What this does NOT change.** Everything v4 ruled about the data layer and its gates, the honesty rule, the multi-user rules, the schema, the scanner spec, the OpenFoodFacts mapping and the architecture constraints **stands unchanged**. This is a change of *direction*, not of *discipline*. D1/D3/D5/D6 stand; D2 and D4 remain retired.

## The goal ([[D152]])

> **Track inputs, evaluate them against current research, and predict MY outcomes.**

**Every slice must say which of those three it serves** — *track*, *evaluate*, or *predict*. A slice that serves none of them needs a reason before it needs a gate.

### The roadmap, in dependency order

1. **STREAMS.** Glucose now (imported from the Apple Health export, merged by timestamp). HRV, resting HR and sleep when the Oura arrives. The native shell reading HealthKit is the durable route; manual export is the stopgap.
2. **EVENT SIGNATURES + OUTCOME BITS.** Each meal tagged with what it did to glucose; each night with its HRV.
3. **AN EVIDENCE LAYER.** D32's discipline extended from lab ranges to *responses*: any claim the app makes about a pathway or a response carries its **source**, the **population studied**, and the **strength of the evidence**.
4. **PREDICTION.** n=1, from the user's own paired data, **uncertainty shown**, **opt-in**. Predict **proxy responses**; never claim to measure a pathway directly. A prediction is not a measurement, so predictions live in their own store and are never summed into or displayed as a reading — D120's separation, inherited.

### Primary outcome: vagal tone

Read through **HRV and resting heart rate**.

- **A reading's MEASURE and DEVICE are part of its identity.** Oura's RMSSD and Apple Watch's SDNN never share a series. This is the glucose-unit rule and the breath-ketone rule again, and the machinery exists: a glucose day is keyed by its unit and refuses to draw one line through two.
- **Compare against the user's OWN baseline, never population norms** — between-person spread dwarfs within-person change.
- **Ranges for labs, baseline for responses.** D32 shows jurisdictional reference ranges because that is the convention for a lab panel; a vagal-tone comparison against a population range is the same number doing a different job.

### First composite: tonicity

Inputs the app holds or will: water, sodium, potassium, alcohol, caffeine, glucose. Outcomes: day-to-day weight swings, resting HR, HRV. Anchored in calculated osmolality ≈ 2·Na + glucose + urea (mmol/L), with Na and urea from lab panels — and it **says plainly that between panels the estimate leans on intake and proxies**. The figure carries **which of its inputs were measured and which estimated**: the same number computed on a panel day and three weeks later is not the same quantity.

### Practices as experiments

Sauna, cold plunge, red light, slow breathing and similar are **logged events**. Their effect on that night's HRV against the user's own baseline is an **n=1 test, not a claim**. Contested "vagal toning" claims get **tested, not asserted**.

## What the app is

A mobile-first, fully client-side personal health instrument. No backend, no accounts, no analytics; all data lives on the device; export is always available. It remains **distributable** — no personal calibrations in code, per the multi-user rules below — but its direction is set by one person's outcomes.

Capabilities, as they actually stand:

1. **Scan → nutrients.** Barcode scan → OpenFoodFacts lookup → macros *and* labeled micronutrients → portion picker → one-tap log at `measured` confidence.
2. **Photo → nutrients via AI paste.** For restaurant/cooked meals: the app provides a copyable prompt template; the user sends it with their meal photo to their AI assistant (Claude or any other), pastes the returned JSON into Ingest. Macros only — see the honesty rule below. No API keys, no in-app AI calls.
3. **Daily log vs goals.** Daily totals of every tracked nutrient, displayed against user-configured goals (floors for things like protein and fiber, ceilings for things like sodium and kcal if the user wants them).
4. **Glucose, as a stream.** Imported from an Apple Health export or a Shortcut-produced file, merged by timestamp, held as a re-acquirable **cache** outside the export. A collapsed day row opens into a zoomable, scrollable chart with a time axis, a tap readout, and gaps drawn as gaps. This is leg 1 of the roadmap, and the first stream.
5. **Medication label information, sourced.** On request, the US prescribing information for a medication, selected from the FDA label and stored with its citation and retrieval date. The app never says what a drug is for in its own voice.
6. **Price — data layer only.** A per-product, per-store price history is part of the stored contract, migrated and exported with everything else. **There is no capture screen and no Open Prices lookup**, and per the v5 ruling there is no plan to add them. See *Price — kept, not roadmapped* below.

**Honesty rule (ruled; refined by D120):** micronutrients enter the log from *labeled* sources — the OFF scan path or explicit manual entry from a package label — **and from the cited composition corpus, at a distinct `reference` provenance**. The rule's purpose was to keep **fiction wearing decimals** out of daily totals, and a cited corpus value is not fiction. It is, however, **not your food**: generic cheddar is not your cheddar. So a reference value is **never summed into the same figure as a labelled one without the panel saying so**, the two live in separate maps rather than behind a flag, and the coverage line distinguishes them. The rule is refined, not abandoned: what it forbids is an *uncited* number, not a *sourced* one. The AI photo path produces macro estimates at `eyeballed` confidence and never micros; the in-app prompt template must not request micros. A vision model cannot see the iron in a stew, and daily micro totals must never be fiction wearing decimals. Days whose items lack micro data show micro totals as "from N of M items" so partial coverage is visible, not implied-complete.

## Multi-user rules (all new in v4)

- **No personal calibrations in code.** The auto-supplement is now a user setting: **off by default**, configurable (name, kcal, per-nutrient amounts); when enabled it persists into each new day as a flagged, non-deletable item, exactly as the old behavior. Quick-add presets ship **empty**; users create their own (name + nutrient amounts + default portion). Seed data is zero days, zero presets.
- **First-run experience.** An empty state that teaches the two input paths, prompts goal setup (skippable), and exposes the copyable AI prompt template. No feature assumes the user knows the JSON contract — the app teaches it.
- **Privacy is a stated feature.** README + in-app about line: all data local, no accounts, no telemetry, export-is-yours. Device location is used only when the user invokes nearby-price comparison, is sent only as an Open Prices query parameter, and is never stored.
- **License:** add one before distribution (default MIT unless the user rules otherwise — open ruling).
- **OFF etiquette:** every OpenFoodFacts / Open Prices request carries a custom User-Agent identifying the app (`HealthTracker/<version> (<repo URL>)`). Cache-first lookups are the rate-limit courtesy.
- Repo stays history-free and now fixture-synthetic forever; it is public-facing.

## Data contract (schema v2)

Item fields: `name, meal, time, kcal, protein_g, fat_g, carb_g, fiber_g, soluble_fiber_g, confidence, notes`, plus optional `barcode`, optional `micros`, and `source`.
- `meal` ∈ breakfast | lunch | dinner | snack | drink | supplement
- `confidence` ∈ eyeballed | weighed | measured
- `source` ∈ scan | ai-paste | manual | preset | supplement
- `micros` is an optional flat map of canonical keys → numbers: `sodium_mg, potassium_mg, calcium_mg, iron_mg, magnesium_mg, zinc_mg, vitamin_a_ug, vitamin_c_mg, vitamin_d_ug, vitamin_b12_ug, folate_ug, saturated_fat_g, sugars_g, cholesterol_mg` (extensible; unknown keys tolerated on ingest, preserved, not displayed until recognized). Only scan/manual items may carry micros per the honesty rule; ingest strips `micros` from `ai-paste` items and says so in the ingest report.
- `soluble_fiber_g` always present (0 when unknown) on every creation path.

Day shape unchanged: `{ status, items[], water_l }` keyed by `YYYY-MM-DD` (keys validated at every paste boundary). Water source of truth: `day.water_l`.

New top-level state:
- `settings`: `{ goals: { <nutrientKey>: {value, direction: "min"|"max"} }, supplement: {enabled:false, name, nutrients}, presets: [] }`
- `priceLog`: `{ <barcode>: { name, entries: [{price, currency, store, date}] } }` — independent of the food log (a product can be price-checked without being eaten).

**Versioning:** blob carries `version: 2`. The existing v1→v2 migration is **in-place under the stable key** — this is the versioning machinery doing the job it was built for (first real exercise of it). v1 blobs gain empty `settings`/`priceLog`, items gain `source` (inferred: `supplement` if `_auto`, else `manual`). Forward-version guard now rejects `version > 2`.

**Legacy `uha-log-v1` support: removed.** Strip `migrateLegacy`, the legacy-paste restore route, and their harness cases (fresh start, no legacy users exist). The restore boundary accepts schema v1/v2 blobs only.

**Ingest (four shapes) and import/restore semantics carry forward** from v3/D5, with version routing amended for schema v2 (version-absent → reject; v1 → in-place migrate; v2 → as-is; > 2 → reject — see the D5 amendment): non-destructive merge never overwrites non-empty days; destructive restore is confirm-gated with the D3 pre-restore backup and degraded path; per-item coercion (numbers coerced, clamped ≥ 0) and escaping at every untrusted boundary (paste, OFF, Open Prices). Escaper covers `& < > " '`.

## The AI prompt template (shipped in-app, copyable)

A short instruction block the user pastes into any AI assistant along with their meal photo. It must request: JSON only, straight quotes, the item schema above **without micros**, `confidence: "eyeballed"`, honest portion assumptions in `notes`, `soluble_fiber_g` present (0 if unknown). The template is versioned with the schema and lives in one place in the code.

## Goals display

- The daily ring becomes progress-vs-goal for a primary nutrient (user-selectable, default kcal), with a compact goal strip for the rest: current / target, direction-aware (a ceiling at 80% is good; a floor at 80% is short).
- Daily summary rolls up all macros + all micros present, each micro annotated with its coverage ("from N of M items").
- Averages keep the calendar-window definition and complete-days-only discipline.

## Scanner spec — unchanged from v3 (follow it exactly)

Preconditions (https/localhost, getUserMedia support), the getUserMedia constraints and error-message matrix by `err.name`, two-tier detection (native BarcodeDetector with format intersection + readyState-gated rAF loop; ZXing UMD CDN fallback with 100 ms poll / ~6 s timeout), ~1.5 s debounce, vibrate, full teardown, 8–14 digit hygiene, manual barcode field alongside the camera.

## OpenFoodFacts integration (extended for micros)

`GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,quantity,serving_size,serving_quantity,nutriments`
- Map nutriments to the schema: macros from `energy-kcal_100g, proteins_100g, fat_100g, carbohydrates_100g, fiber_100g`; micros from their `_100g` keys where present (sodium, salt→sodium conversion, calcium, iron, potassium, vitamins, saturated fat, sugars). Missing micros are simply absent — never zero-filled (absence ≠ zero on a label).
- Portion picker (per serving / per 100 g / custom grams) scales macros and micros together.
- Cache every successful lookup (barcode → product + nutriments + fetched-at); cache-first on rescan; offline-capable.
- All OFF strings escaped, all numbers coerced and clamped. Custom User-Agent on every request.
- Product missing / offline: keep the barcode, offer manual entry; never lose the code.

## Price — kept, not roadmapped (ruled, v5)

**Price tracking stays as an existing feature and is no longer a roadmap capability.** Stated at its real state, because the brief should not promise what the code does not keep:

- **What exists:** the `priceLog` contract — `{ <barcode>: { name, entries: [{price, currency, store, date}] } }` — which is migrated, exported, escaped and **gated** (63 harness references), plus `storeHistory()`. It is part of the data layer and stays there.
- **What was never built:** the capture prompt, the per-product comparison view, and **any** Open Prices integration. There is a `.pricecap` CSS rule in `index.html` with nothing rendering into it.
- **So:** do not delete `priceLog` and do not plan work against it. If price capture is ever wanted it gets pre-registered then, like anything else. Nearby-prices-from-Open-Prices is **withdrawn** as a plan, not deferred: it was a v4 roadmap capability and v5 has no roadmap slot for it.
- The privacy stance about location stands regardless: device location is used only when the user invokes a nearby-price comparison, is sent only as an Open Prices query parameter, and is never stored. Since no such call exists, the app currently sends location **nowhere**.

## Architecture constraints (unchanged, restated)

Static, no build step, GitHub-Pages-deployable; vanilla HTML/CSS/JS in a handful of files; only external dependency is the lazy-loaded ZXing fallback; localStorage primary with truthful badge and memory fallback (D1); SW per D6 (cache-first atomic shell, prefix-scoped cleanup, no skipWaiting, passive update hint, localhost network-first, `?prod=1` override); mobile-first, light+dark tokens, safe-area insets, no web fonts, no `maximum-scale`.

## Phase plan (gated; evidence pre-registered and re-runnable, as established)

**Phase R — Reframe.** Strip legacy migration + its tests; retire D2/D4 in DECISIONS.md; schema v2 with in-place v1→v2 migration; settings (goals, supplement-off-default, empty presets); `priceLog` scaffold; seed emptied of personal data.
*Gate:* full harness green after the strip (no orphaned cases); a v1 blob migrates in place under the stable key with items gaining correct `source`; new-user boot yields zero days'-worth of fabricated intake (no supplement unless configured); forward-version guard rejects v3+.

**Phase 1 — Logging core, multi-user.** Day view (meal grouping, day nav, tap-to-cycle, clear-day), goals setup + progress display + daily summary with micro coverage annotation, averages, manual add (with optional label-micros entry), preset CRUD, supplement setting, four-shape Ingest incl. the ai-paste micro-strip rule, first-run flow + in-app AI prompt template, README (privacy stance) + license.
*Gate:* displayed and exported totals are the same numeric item set; all four ingest shapes per contract; ai-paste micros are stripped and reported; goal direction math correct for min and max cases; every rendered field escaped (incl. goal names, preset names, store names); first-run on a clean profile reaches a logged day via the prompt-template path without external instructions.

**Phase 2 — Scan + price capture.** Full scanner spec, OFF lookup with micros mapping, portion picker, product cache (storage ruling made here per D-log), optional price+store prompt, personal price comparison view.
*Gate:* scanned real product logs correct macros+micros at a custom gram amount; absence-≠-zero verified (a product with no labeled iron shows no iron, not 0); rescan offline resolves from cache; unknown barcode degrades without losing the code; camera-denied/no-camera messages correct; price entries recorded, grouped by store, skippable at zero cost.

**Phase 3 — Nearby prices.** Open Prices read integration per the deferred-verification rule; location permission flow; proximity ranking; caching; graceful degradation.
*Gate:* scanned product with location permission shows nearby community prices with store/date/distance; permission denied → personal-only with no error surface; offline → cached/personal; the API contract used is recorded in DECISIONS.md with a dated verification note.

**Phase 4 — superseded by the v5 roadmap above.** The old candidate list (Open Prices contribute-back, BYOK vision, shareable shopping lists) is **withdrawn**: it predates the goal. The work after the logging core is the four legs — streams, event signatures, the evidence layer, prediction — in that dependency order, each slice naming which of *track / evaluate / predict* it serves.

## Working rules (unchanged)

Small single-purpose commits; data-loss implications stated and ruled before touching storage/ingest/export/migration; pre-registered, re-runnable gate evidence; ruled contracts live in DECISIONS.md and bind equally; ask before adding scope; name conflicts between patterns rather than silently resolving them.
