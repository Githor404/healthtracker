# HealthTracker — Agent Brief (v3)

You are building a food/health logging web app in this repo, from scratch. It succeeds an existing app (**health-log**) whose proven design decisions are distilled below. This brief is the **spec of record**.

**Status:** The one-time analysis of the predecessor source has been completed and its findings are absorbed into this version. Do not fetch or consult the original again — where memory of the original and this brief disagree, the brief wins.

**Storage ruling (decided):** localStorage is the primary tier for the day log — single versioned key, memory fallback for private-mode/write-failure cases, truthful badge. The Phase 2 OFF product cache is a separate storage decision, made in Phase 2 (capped localStorage key vs small IndexedDB store); it is rebuildable data and does not need the log's durability guarantees.

## Product concept

A mobile-first daily food log with two input paths landing in the same data structure:

- **Scan path** (new, primary for packaged foods): barcode scan → OpenFoodFacts nutriments → portion picker → one-tap log at `measured` confidence. No AI round-trip.
- **Claude path** (carried forward, for cooked/plated meals): user photographs a meal, sends it to Claude in a chat, pastes the returned JSON into the app's Ingest box. Periodically the full state is copied out and pasted back to Claude for analysis.

## Data contract (stable — extend, never break)

Item fields: `name, meal, time, kcal, protein_g, fat_g, carb_g, fiber_g, soluble_fiber_g, confidence, notes`, plus optional `barcode` (scan path) and optional `water_l`.
- `meal` ∈ breakfast | lunch | dinner | snack | drink | supplement
- `confidence` ∈ eyeballed | weighed | measured
- Numbers are numbers. `soluble_fiber_g` is always present (0 when unknown) on every path that creates items — ingest normalizer, manual add, scan path, presets. No path may emit an item without it.

Day shape: `{ status: "in_progress" | "complete", items: [], water_l }`, keyed by local date `YYYY-MM-DD`.

**Water source of truth:** `day.water_l` drives all display and totals. Water-type items (e.g. a "Water 1L" preset) are timestamped log records that increment `day.water_l` when added; they are never independently summed. One truth, no double counting.

**New schema versioning:** the stored blob carries an internal `version` field. The legacy blob (`uha-log-v1` key) has no internal version — migration detects it by key/shape. Legacy shape: `{ days: {date: day}, known: [], current }`; it must import losslessly, preserving `water_l`, statuses, and every item field.

**Two import mechanisms, both present, clearly labeled:**
- **Ingest** = non-destructive merge. Accepts four shapes: `{items:[...]}` with optional top-level `date`; a bare array; a single item; a full `{days:...}` export. Full-days merge fills only days that are locally missing or empty — never overwrites a day that has items; merges `known` deduped by name. Item-level `date` overrides top-level `date` overrides today.
- **Import/restore** = destructive full replace, confirm-gated (the predecessor lacked the confirm — add it).

All ingest paths — including the full-days shape — route every item through the same per-item coercion (numbers coerced, clamped ≥ 0) and escaping. Pasted JSON is normalized before parsing: smart quotes → straight, non-breaking spaces → spaces.

## Design decisions carried forward (all mandatory)

- **Per-item confidence tag** rendered on every item.
- **Manual day-close discipline**: new days are `in_progress`; the user explicitly closes them (and can reopen); only `complete` days enter any average or statistic; in-progress days are visibly flagged wherever they appear.
- **Auto-applied daily supplement item** (kcal ≈ 5, soluble fiber ≈ 4 g, flagged, non-deletable) — persisted into the day's items at day creation, so displayed and exported totals are always identical.
- **Arbitrary-day navigation and editing**: ‹ / › navigation across all logged days; the ring, item list, totals, close/reopen, and clear-day all operate on the selected day, not just today.
- **Tap-to-cycle meal**: tapping an item's meal chip cycles through the six meal values.
- **Confirm-gated "Clear this day"**: wipes the selected day's items and water (for re-importing a clean full-day JSON).
- **7-day average = complete days within the last 7 calendar days** (not "the last 7 closed days"). This is intentional: it answers "how am I eating lately," and logging gaps should visibly thin the sample rather than reach back to stale days. All-time average = all complete days.
- Soluble/insoluble fiber split display; macro-composition ring with %-of-calories and grams modes; stacked P/F/C daily history chart with in-progress days marked; per-meal grouping with group subtotals; water quick-add (+0.25/+0.5 L); pinned quick-add presets whose values are calibrated and never re-estimated; copy-full-state-to-clipboard with graceful fallback when the Clipboard API is unavailable.
- **History-free repo**: day logs are personal data. No real history in seeds, fixtures, or commits — synthetic data only.

## Proven patterns to re-implement (patterns, not pasted code — every line here is justified by this brief, not by the predecessor)

- `cleanJSON` paste normalization (smart quotes, non-breaking spaces).
- Dual clipboard strategy: Clipboard API with a select-and-copy fallback surface.
- CSS custom-property token palette — extended with a dark scheme via `prefers-color-scheme` (the predecessor had none).

## Baseline quality rules (the predecessor's defects, inverted)

1. Auto-items persist; display and export never disagree.
2. **Every** interpolated value is escaped — including pasted JSON and OpenFoodFacts responses (community-sourced, untrusted). The escaper covers `& < > " '` (the predecessor missed `'`).
3. Offline-capable from Phase 0: service worker + web app manifest. No render-blocking third-party resources — **system font stack only, no web fonts** (the predecessor loaded Google Fonts, which breaks offline and adds a dependency).
4. Known foods are a real feature (Phase 2): seeded from presets + product cache, surfaced in manual add.
5. The storage badge always tells the truth and **reacts to write failures at write time** — a quota error after load must visibly degrade to memory mode and warn the user to export, not keep claiming "saved."
6. Viewport: keep `viewport-fit=cover` for safe areas; do **not** set `maximum-scale` (pinch-zoom stays available).

## Scanner spec (distilled from a proven on-device implementation — follow closely)

**Preconditions, checked in order before opening the camera:**
- Require `https:` (allow `localhost` / `127.0.0.1`); otherwise: camera only works on a secure page.
- Require `navigator.mediaDevices?.getUserMedia`; otherwise: browser doesn't support camera access.

**Camera:** `getUserMedia({ video: { facingMode: {ideal:'environment'}, width:{ideal:1920}, height:{ideal:1080} }, audio: false })`. Map failures by `err.name`:
- `NotAllowedError` / `PermissionDeniedError` → permission blocked; allow camera in browser settings and reload.
- `NotFoundError` / `OverconstrainedError` → no camera on this device.
- `NotReadableError` → another app is using the camera.
- anything else → surface the error message.

Video element: `playsinline`, muted, autoplay; `.play()` wrapped in try/catch.

**Detection, two tiers:**
1. If `'BarcodeDetector' in window`: `getSupportedFormats()`, intersect with `['ean_13','ean_8','upc_a','upc_e','code_128','code_39']`; if non-empty, run a `requestAnimationFrame` loop calling `detector.detect(video)` only when `video.readyState >= 2`, swallowing per-frame errors.
2. Fallback: lazy-load the ZXing UMD browser build from CDN (the only permitted external dependency), poll for `window.ZXingBrowser` every 100 ms with ~6 s timeout; on timeout, error cleanly ("check your connection") and stop. On success use `BrowserMultiFormatReader.decodeFromVideoElement`.

**On hit:** debounce ~1.5 s between accepted reads, `navigator.vibrate(50)` if available, stop the scan (stop all stream tracks, release the reader, clear the detector-active flag), then run the lookup.

**Barcode hygiene:** accept 8–14 digits after stripping non-digits; validate before lookup. A hand-typed barcode field with a Look-up button exists alongside the camera.

## OpenFoodFacts integration

`GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,quantity,serving_size,serving_quantity,nutriments`

- Use per-100 g nutriments (`energy-kcal_100g`, `proteins_100g`, `fat_100g`, `carbohydrates_100g`, `fiber_100g`) and per-serving where present.
- Portion picker: per serving / per 100 g / custom grams, live-computed macros; logging writes a complete item at `measured` confidence with `barcode` set.
- Cache every successful lookup (barcode → name, brand, nutriments, fetched-at). Repeat scans resolve from cache first and work offline.
- Missing product / network failure degrades gracefully: keep the barcode, offer manual macro entry or defer to the Claude photo flow. Never lose the scanned code.
- OFF data is untrusted: escape all strings, coerce and clamp all numbers.

## Architecture constraints

- Static app, no build step, GitHub-Pages-deployable. Vanilla HTML/CSS/JS across a handful of files (index.html, app.js, sw.js, manifest.json). No frameworks, no bundlers, no npm. Only external dependency: the lazy-loaded ZXing fallback.
- Mobile-first (~480 px column), safe-area insets, light + dark schemes via CSS tokens and `prefers-color-scheme`.
- Versioned storage schema with a migration path; full JSON export/import always available as the escape hatch regardless of storage tier.

## Phase plan (gated — a phase does not start until the previous gate passes, with evidence pre-registered)

**Phase 0 — Scaffold & data layer.** localStorage adapter with truthful badge and memory fallback, versioned schema (internal `version` field), JSON export/import, `uha-log-v1` migration, service worker + manifest, day model with status discipline.
*Gate:* a real legacy export imports losslessly (item counts, per-day totals, statuses, `water_l` all match); the app loads and displays imported history with networking disabled; the badge correctly reflects each tier including a forced write failure occurring after load.

**Phase 1 — Logging parity.** Day view grouped by meal, day navigation, totals with persisted auto-supplement, macro ring, fiber split, history chart, averages (calendar-window definition), manual add, tap-to-cycle meal, clear-day, quick-add presets, Claude JSON ingest (all four shapes, paste normalization), confirm-gated import/restore, copy-data-out.
*Gate:* displayed and exported day totals comprise the same item set with the same underlying numeric values (persisted supplement in both) — compared numerically, not as display-rounded strings; all four ingest shapes behave per the Data contract; a sweep confirms every rendered field passes through the escaper, including the full-days ingest path.

**Phase 2 — Scan-to-log.** Full scanner spec, OFF lookup, portion picker, product cache (storage decision made and ruled on here), known-foods list surfaced in manual add.
*Gate:* a scanned real product logs with correct computed macros at a custom gram amount; the same barcode rescanned offline resolves from cache; an unknown barcode degrades to manual entry without losing the code; camera-denied and no-camera paths show the correct messages.

**Phase 3 — Expansion (propose, don't assume).** Candidates: weight/biometrics tracking, targets on the ring, week-view analytics, shopping-list features. Present options with effort estimates and let the user rank them before building anything.

## Working rules

- Small, single-purpose commits. Before any change to storage, ingest, export, or migration code, state the data-loss implications explicitly and wait for approval. No bulk approvals.
- Ruled implementation contracts live in DECISIONS.md and bind equally.
- Pre-register each gate's test evidence before claiming the gate passes.
- Ask before adding any scope not listed here. When two patterns in this brief could conflict in practice, name the conflict and propose a resolution rather than silently picking one.
