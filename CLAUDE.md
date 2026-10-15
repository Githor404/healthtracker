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
2b. **Photo → named food, with the user's own key (BYOK).** The user supplies a provider key; a photographed meal or label is sent to **their** provider, which **names** the food. The numbers then come from the corpus or from remembered items, never from the model ([[D128]]: *the AI names things; numbers come from sources*). At capture only memory proposes, the matcher's top pick is never pre-selected, and every item is confirmed one at a time. Gated by `capture-gate` and `capture-outcome-gate`.
2c. **Search → cited numbers, offline.** A food typed into Search is matched against the cited composition corpus as it is typed: plural and singular find each other, as do the Canadian and US spellings (yogourt/yogurt and eight more, each measured in the shipped files); a generic row comes before a branded one; rows *headed* by the typed word come before compounds, and a word answered in the first part of a name before one answered later; a row the user has logged before leads and says so. A food found this way takes the corpus macros as its **own** numbers at `source: corpus`, cited (namespace, id, name, hash, attribution), at `eyeballed` confidence because the portion is typed; its micros stay at `reference` provenance per the honesty rule. **The corpus lives on the device** after the first download and is fetched again only when the build expects a different one — search, pick and log work with no network, including a cold start. Gated by `onedoor-gate`, `rank-gate`, `corpus-cache-gate` and `cold-start-gate`. *Known limits, stated:* on the Canadian corpus "coffee" leads with instant, brewed second, until brewed has been logged once; "sardines" leads with fish oil on both (no row is headed Sardine); a brand is recognised only by the capitals both files print trade names in.
2e. **Manual entry looks the food up (R215/4).** Typing a name in Manual brings the same cited rows as Search, calories beside each; a pick fills in calories, macros and every micronutrient the row carries for the typed grams, each still editable. Taken unchanged the item is exactly a search's (`source: corpus`, micros at `reference`); a number the user types over makes it theirs — `source: manual`, the citation kept, `adjusted` naming the changed fields, and a typed-over micronutrient becomes a **label** value removed from the reference figures, so no nutrient of one item is counted twice. Nothing matches → the from-label form (3d). Gated by `lookup-gate`.
2f. **A drink is food (R215/3).** `meal: drink`, logged like any food: **Your drinks** in + Log (read from the log, one tap = the last one again at its last size), **Log a drink** (Search, tagged), photo or manual. Calories count in the day; alcohol rides in the cited ref where the row has it. The one-tap Drink badge is retired; its old events are shown "amount not recorded". In Log a drink, rows each source files as a **beverage** (CNF group 14, SR Legacy "Beverages"; shipped in the corpus index as `groups`, with their own hash) come first **within each tier of words answered**, so "wine" leads with a wine on both databases and "red wine vinegar" still finds the vinegar (R221/3). *Known limit:* juices are filed under Fruits and fruit juices and are not promoted. Gated by `lookup-gate` and `entry-gate`.
2d. **Combos.** A named set of parts made, edited and deleted through one builder (`+ Log → + New combo`; "Edit" beside *My combos*). Logging a combo writes ordinary items, each a copy of its part at that moment, so editing or deleting a combo never changes a past log. Gated by `onedoor-gate` and `forms-gate`.

3. **Daily log vs goals.** Daily totals of every tracked nutrient, displayed against user-configured goals (floors for things like protein and fiber, ceilings for things like sodium and kcal if the user wants them).
3b. **Served vs eaten.** A plate holds what was **served**; the day's items are what was **eaten**, and every total uses eaten. The two are shown together whenever they differ ("200 g served · ate ½ · 100 g"). The share is the user's statement — "Ate: all · ¾ · ½ · ⅓ · ¼" on the photo draft, on the Manual and Scan forms at save, and on a logged row afterwards — default *all*, never a prompt. The inedible part comes from the Canadian Nutrient File's refuse figure, cited with the row it matched: automatic only for bone on a row that is itself bone-in (or a wing, drumstick, rib or neck); peel, shell, pit and fat are one tap, off by default; the user's "boneless" / "with bone" answer is remembered per food and wins. No correction on the US corpus (no refuse source). Gated by `served-gate` and `forms-gate`.
3c. **Daily stack — a plan, logged by one tap.** Settings holds the list. Each item is a **Supplement** (the default), a **Medication** or a **Food**: the first two go on the timeline with name, amount, unit and a note, and which of the two it is is stored on the dose record (`stackKind`) so a medicine can be told from a supplement later; a Food counts in the day with its calories and is a food-database row, or one of the user's own foods, at typed grams. A logged entry leads with its kind's word; entries logged before the kind was recorded are relabelled "Supplement" at render only. "+ Log → Took my daily stack · N items" lists it ticked; the user unticks what they skipped and one confirm writes the rest at one time, with one Undo. Editing the stack logs nothing. An amount said to count toward a nutrient is converted at entry by a cited factor or refused; the editor *suggests* the nutrient when the name holds one and never sets it. **A dose that counts toward a nutrient adds to that nutrient's day total** as its own "from your stack" line, with no calories (ruled R208 — this reverses R168's "a dose never reaches totals"; a dose mapped to nothing stays on the timeline only). **A cited upper intake level carries its scope as a field**: vitamin D's is about *total* intake, so the day's food + stack is compared to it; magnesium's (Health Canada) is about *supplemental* intake only, so food is not counted toward it. A limit with no scope or no citation produces no flag. A flag states the amount, the source and the scope, and never an instruction. **Every intake flag is a collapsed note** — an icon and "Intake note — tap to read", amber and never red, a 44-point target, closed again on every render (ruled R213: *flags, not nudges*); the day-level flag lives in the Micronutrients panel and on the stack row, and nowhere on the day view. On the day, supplements have a group of their own and are never filed under a meal by the clock; sittings more than three hours apart are separate groups, each with its own time. Gated by `noauto-gate`, `stacktotals-gate` and `myfood-gate`.
3d. **My foods — a food that is in neither database.** Wherever a food-database food was required (a stack Food, a combo part) the user can add their own: name, grams per serving, macros per 100 g or per serving, and whether the numbers are **from label** or **generic values** — a field (`basis`), shown on the logged row where another item says how it was entered. Stored per 100 g in `settings.foods`, ships empty, found again by name above the database's rows. **Macros only**: a label's micronutrients keep their own entry path, and a "generic" micronutrient would be the uncited number the honesty rule forbids. Not yet offered in the Search pane. Gated by `myfood-gate`.
3e. **Backup as a file.** "Export backup" makes `healthtracker-backup-YYYY-MM-DD-vNN.json` (NN = schema number) and hands it to the share sheet, or downloads it where a file cannot be shared; closing the sheet records nothing. Settings shows "Last backup: <date>" and nothing that urges. Restore accepts the file through a file input, which only loads it — replacing data is still the user's tap, with D3's confirmation and pre-restore backup. Gated by `backup-gate` (byte-identical round trip).

4. **Glucose, as a stream.** Imported from an Apple Health export or a Shortcut-produced file, merged by timestamp, held as a re-acquirable **cache** outside the export. A collapsed day row opens into a zoomable, scrollable chart with a time axis, a tap readout, and gaps drawn as gaps. This is leg 1 of the roadmap, and the first stream.
4b. **Sensor change, with a countdown.** One tap in + Log records a new sensor (the day shows the countdown, read-only) with its **device** and **site**; the status line reads "Dexcom G7 · Day 3 of 10 · left arm", then the grace period when it is due. Wear time and grace are the manufacturer's, stored with citation and retrieval date. A second tap within ten minutes is not a second change; an existing entry's device is set only by the user's own edit, never back-filled. Gated by `sensor-gate`.
4c. **Glucose rises with no food logged before them (E-lite).** A rise of the ruled size with no eaten food in the response window is marked on the chart, passively: no prompt, no count, no badge. Opened, it offers what could account for it in a ruled order — a sensor artifact first when the rise starts from a sudden drop or falls within a day of a sensor change, then asleep or waking, then food that was not logged, then stress or other — and stores the answer as a label on the timeline. Steps (Apple Health `StepCount`, glucose's days only) are the moving covariate. **Nothing is inferred**: no stress probability, no cause in the app's voice, and "explained" is binary — magnitude matching is deferred to the full model. Serves *track* now and is the labelled set *evaluate* will need. Gated by `elite-gate`.

5. **Medication label information, sourced.** On request, the US prescribing information for a medication, selected from the FDA label and stored with its citation and retrieval date. The app never says what a drug is for in its own voice.
6. **Price — data layer only.** A per-product, per-store price history is part of the stored contract, migrated and exported with everything else. **There is no capture screen and no Open Prices lookup**, and per the v5 ruling there is no plan to add them. See *Price — kept, not roadmapped* below.

**Honesty rule (ruled; refined by D120):** micronutrients enter the log from *labeled* sources — the OFF scan path or explicit manual entry from a package label — **and from the cited composition corpus, at a distinct `reference` provenance**. The rule's purpose was to keep **fiction wearing decimals** out of daily totals, and a cited corpus value is not fiction. It is, however, **not your food**: generic cheddar is not your cheddar. So a reference value is **never summed into the same figure as a labelled one without the panel saying so**, the two live in separate maps rather than behind a flag, and the coverage line distinguishes them. The rule is refined, not abandoned: what it forbids is an *uncited* number, not a *sourced* one. The AI photo path produces macro estimates at `eyeballed` confidence and never micros; the in-app prompt template must not request micros. A vision model cannot see the iron in a stew, and daily micro totals must never be fiction wearing decimals. Days whose items lack micro data show micro totals as "from N of M items" so partial coverage is visible, not implied-complete.

## Multi-user rules (all new in v4)

- **Nothing is logged without a tap, and nothing logged is non-deletable (ruled R202/R203, 2026-10-12, v0.94.0).** This **replaces** the v4 rule that an enabled auto-supplement "persists into each new day as a flagged, non-deletable item": that setting wrote an entry whenever a day record was created — at app start or a resume after midnight — stamped with that clock. It is retired. A day record is created **empty** at every creation site. A schedule or a plan may *propose*; only a tap writes. Entries the old setting added are ordinary entries marked `autoLegacy`, with their time cleared and shown as "time unknown (auto-added at app open)"; they count on their day and are excluded from every timing analysis.
- **Every entry goes through + Log (ruled R215/R216, 2026-10-14, v0.97.0).** No control outside + Log (and Settings) writes an entry, except three **answers** to something the page shows: Fasted / Ate, didn't log (a fasting gap), the answer to a glucose rise, and the side slept on (a flagged night). Restore from the trash brings back an entry rather than making one. A side entry point is removed or becomes a link that opens + Log at the right spot (the leftovers line, today's regimen). The day **shows** — the ring, water, the sensor countdown — and does not write. Starting or ending a sleep always **asks the time** (Now, the user's usual wake time from their own nights, or any time); an open sleep is **never closed by the app** (D113's auto-close retired). Gated by `entry-gate`, a census that clicks every control on the page.
- **No personal calibrations in code.** The daily **stack** (`settings.stack`) is the user's own list and ships **empty**; it is never seeded from code, and nothing from a user's stack is written in this repo — records refer to "the user's stack" only (ruled R204). Quick-add presets ship **empty**; users create their own (name + nutrient amounts + default portion). Seed data is zero days, zero presets.
- **First-run experience.** An empty state that teaches the two input paths, prompts goal setup (skippable), and exposes the copyable AI prompt template. No feature assumes the user knows the JSON contract — the app teaches it.
- **Privacy is a stated feature.** README + in-app about line: all data local, no accounts, no telemetry, export-is-yours. Device location is used only when the user invokes nearby-price comparison, is sent only as an Open Prices query parameter, and is never stored.
- **License:** add one before distribution (default MIT unless the user rules otherwise — open ruling).
- **OFF etiquette:** every OpenFoodFacts / Open Prices request carries a custom User-Agent identifying the app (`HealthTracker/<version> (<repo URL>)`). Cache-first lookups are the rate-limit courtesy.
- Repo stays history-free and now fixture-synthetic forever; it is public-facing.

## Data contract (schema v2)

Item fields: `name, meal, time, kcal, protein_g, fat_g, carb_g, fiber_g, soluble_fiber_g, confidence, notes`, plus optional `barcode`, optional `micros`, and `source`.
- `meal` ∈ breakfast | lunch | dinner | snack | drink | supplement
- `confidence` ∈ eyeballed | weighed | measured
- `source` ∈ scan | ai-paste | manual | preset | supplement | corpus
  - `corpus` (ruled 2026-10-11, v0.85.0): an item found purely by search, whose OWN macros are the cited composition corpus's at the typed grams. Written in one place (`corpusOwnNumbers`); its `ref` carries the citation; its micros stay in `ref.v` and are never copied into `micros`. Additive, no schema bump — a build that does not know the value falls back to `manual` at its restore boundary. Items logged by search under v0.84.0 keep `manual` and are not back-filled.
- `micros` is an optional flat map of canonical keys → numbers: `sodium_mg, potassium_mg, calcium_mg, iron_mg, magnesium_mg, zinc_mg, vitamin_a_ug, vitamin_c_mg, vitamin_d_ug, vitamin_b12_ug, folate_ug, saturated_fat_g, sugars_g, cholesterol_mg` (extensible; unknown keys tolerated on ingest, preserved, not displayed until recognized). Only scan/manual items may carry micros per the honesty rule; ingest strips `micros` from `ai-paste` items and says so in the ingest report.
- `soluble_fiber_g` always present (0 when unknown) on every creation path.
- Items may carry `adjusted` (v0.97.0, additive, no schema bump): the field keys a database lookup filled in and the user then changed.

Day shape unchanged: `{ status, items[], water_l }` keyed by `YYYY-MM-DD` (keys validated at every paste boundary). Water: the day's figure is `day.water_l` **plus** its `water` timeline entries (R221/2, v0.98.0): each tap is an entry, listed and deletable with × + Undo; `water_l` holds what was logged before and what an import brings, untouched.

New top-level state:
- `settings`: `{ goals: { <nutrientKey>: {value, direction: "min"|"max"} }, stack: [], foods: [], combos: [], presets: [] }`
  - `foods` (v0.96.0, additive): `{ id, name, basis: "label"|"generic", serving_g?, per100: {<macro>: n} }`. Items and combo parts made from one carry `basis`.
  - Items and dose records may carry `stackKind` (`supplement`|`medication`|`food`; v0.96.0, additive). A stack item's stored `kind: "dose"` reads as `supplement`.
  - `settings.supplement` is **retired** (schema v15): its migration carries the name and any nutrients into one `stack` item and removes the setting. Stack item: `{ id, name, kind: "dose"|"food", enabled, dose?, dose_unit?, note?, nutrients?, part?, bioactive? }` — a `dose` goes to the timeline, a `food` is a food-database row at typed grams (`part`, a combo part) and goes to the day at `meal: supplement`.
  - Items gain optional `autoLegacy: true` (v15), set only by that migration and by the item boundary converting an old `_auto` item. `_auto` no longer exists in the store.
  - A timeline **dose** record gains optional `micros` (v0.95.0, additive, no schema bump): the nutrient key(s) and amount it counts toward, copied from the stack item at the tap. Summed per day in its own provenance ("from your stack"), beside labelled and reference figures and never inside either.
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

**Phase 4 — superseded by the v5 roadmap above.** Of its old candidate list: **BYOK in-app AI vision SHIPPED** (`byokCapture`, `BYOK_PROVIDERS`, gated by `capture-gate` and `capture-outcome-gate`) and is a capability, not a candidate — see 2b above. **Open Prices contribute-back and shareable shopping lists are withdrawn**: they predate the goal. The work after the logging core is the four legs — streams, event signatures, the evidence layer, prediction — in that dependency order, each slice naming which of *track / evaluate / predict* it serves.

> **Correction (2026-10-04).** The first draft of this section called the whole candidate list *withdrawn*, which would have told every future reader that a shipped, gated capability had been abandoned. The cause: the price entry below was audited against the code because the ruling demanded it, and the rest of this document was reasoned about instead of checked. *A claim about the code made without consulting the code is the same defect as a search pattern typed from memory.*

## Working rules (unchanged)

Small single-purpose commits; data-loss implications stated and ruled before touching storage/ingest/export/migration; pre-registered, re-runnable gate evidence; ruled contracts live in DECISIONS.md and bind equally; ask before adding scope; name conflicts between patterns rather than silently resolving them.
