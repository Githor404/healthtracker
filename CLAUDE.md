# HealthTracker — Agent Brief (v4)

**This version reframes the product.** v3 described a personal successor to an older app; v4 describes a **distributable app for other people**: fresh start, no legacy data, no personal calibrations baked in. Where v3 and v4 disagree, v4 wins. The Phase 0 data layer, its gates, and decisions D1/D3/D5/D6 all stand. D2 and D4 are **retired** (superseded — mark them so in DECISIONS.md; never delete log entries).

## Product definition

A mobile-first, fully client-side nutrition and price tracker. No backend, no accounts, no analytics; all data lives on the device; export is always available. Distribution target: ordinary users, not just the author.

Four capabilities:

1. **Scan → nutrients.** Barcode scan → OpenFoodFacts lookup → macros *and* labeled micronutrients → portion picker → one-tap log at `measured` confidence.
2. **Photo → nutrients via AI paste.** For restaurant/cooked meals: the app provides a copyable prompt template; the user sends it with their meal photo to their AI assistant (Claude or any other), pastes the returned JSON into Ingest. Macros only — see the honesty rule below. No API keys, no in-app AI calls.
3. **Daily log vs goals.** Daily totals of every tracked nutrient, displayed against user-configured goals (floors for things like protein and fiber, ceilings for things like sodium and kcal if the user wants them).
4. **Price intelligence.** Optional price + store capture at scan time builds a personal price history per product per store; the app also reads the crowdsourced Open Prices database (read-only) to show nearby prices for a scanned product. No contribution flow in v1.

**Honesty rule (ruled):** micronutrients enter the log only from *labeled* sources — the OFF scan path or explicit manual entry from a package label. The AI photo path produces macro estimates at `eyeballed` confidence and never micros; the in-app prompt template must not request micros. A vision model cannot see the iron in a stew, and daily micro totals must never be fiction wearing decimals. Days whose items lack micro data show micro totals as "from N of M items" so partial coverage is visible, not implied-complete.

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

## Price capture & Open Prices (read-only)

- After a successful scan (or manual barcode lookup), an **optional, skippable** price prompt: price + store name (store names autocomplete from the user's own history). Writes to `priceLog`. Skipping must cost zero taps beyond dismissal.
- Personal comparison view per product: entries grouped by store, latest price per store, simple trend.
- **Nearby prices:** on user request (never automatically), ask for device location, query Open Prices for the product's recent prices, rank by proximity, display store / price / date / distance, cache results briefly. Degrade gracefully: no permission → personal history only, no error; offline → cached or personal only.
- Implementation detail deferred to the phase: verify the current Open Prices API surface at https://prices.openfoodfacts.org/api/docs at build time (query-by-barcode + location filtering), and pre-register the exact endpoint/params in DECISIONS.md before coding. Read-only; no OFF account.

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

**Phase 4 — Expansion (propose, don't assume).** Candidates: Open Prices contribute-back (OFF account + proof photos), BYOK in-app AI vision, biometrics/weight, week analytics, shareable shopping lists. Options with effort estimates; user ranks.

## Working rules (unchanged)

Small single-purpose commits; data-loss implications stated and ruled before touching storage/ingest/export/migration; pre-registered, re-runnable gate evidence; ruled contracts live in DECISIONS.md and bind equally; ask before adding scope; name conflicts between patterns rather than silently resolving them.
