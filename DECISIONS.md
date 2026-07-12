# HealthTracker — Decision Log

Ruled implementation contracts. The brief (`CLAUDE.md`) says **what** and **why**; this log says exactly **how**, as ruled. Both bind equally. Entries are append-only and dated; once ruled, supersede with a new entry rather than editing an old one, so the audit trail survives.

---

## D1 — Storage key naming (2026-07-11)

Version-stable key `healthtracker-log` with `{ version: 1, ... }` inside the blob. The predecessor baked the version into the *key* (`uha-log-v1`), which is precisely why a future "v2" would orphan v1 data. Schema bumps migrate in place under this one stable key; nothing is ever orphaned.

## D2 — Migration precedence: idempotent, one-directional (2026-07-11)

**⊘ SUPERSEDED by v4 (2026-07-11).** The v4 reframe removed legacy `uha-log-v1` support (distributable app, no legacy users), so the cross-key "new key wins" precedence is moot — there is one key. Replaced by the in-place v1→v2 migration (D7). Retained for history; do not apply.

- On boot, read `healthtracker-log`. **If present, it wins unconditionally** — the migrator does not run, does not read legacy, does not merge or "refresh," regardless of what `uha-log-v1` looks like.
- **Only when `healthtracker-log` is absent** do we read `uha-log-v1`, migrate it, and write the new blob stamped with `migratedFrom: "uha-log-v1"` and `migratedAt: <ISO timestamp>`.
- Legacy `uha-log-v1` is left **untouched** (read-only) as a rollback copy.
- **Memory-mode edge case:** if the new-key *write* keeps failing (memory mode / quota), then `healthtracker-log` stays absent and the migrator will re-read legacy on the next load. That's correct, not the resurrection this rule guards against — there were no durable new-app edits to lose, since nothing persisted. The "resurrect stale data after a week" failure mode requires successful new-key writes to have happened, and once one has, the new key exists and legacy is never consulted again.

## D3 — Pre-restore backup: durable key + visible surface (2026-07-11)

- On destructive Import/restore: **before** overwriting, write the outgoing blob to `healthtracker-log-prerestore` (single rolling slot = "undo the last restore") **and** render it into a visible, copyable `<textarea>` on the page. Confirm-gate stays.
- **No clipboard** as the backup mechanism — gesture-gated, fails silently, and the user's next paste destroys it.
- **Degraded path:** if the `-prerestore` write itself fails (memory mode / quota), we will **not** claim it's backed up. The confirm dialog degrades to "storage can't hold a backup — copy the on-screen text below first," and the visible copyable surface becomes the sole recovery path. Same truthful-badge philosophy: never assert safety we don't have.

## D4 — Migration is lossless; supplement backfill is a separate, optional Phase-1 utility (2026-07-11)

**⊘ SUPERSEDED by v4 (2026-07-11).** No legacy history exists to undercount, and the supplement is now a user setting (off by default), not a baked-in calibration — so there is nothing to backfill. Retained for history; do not apply. The transport-layer principle it states — *migration never editorializes* — survives its retirement and is carried into D7.

Migration is a **transport layer and must never editorialize**. Migrated days are byte-faithful to the export; the auto-supplement is **not** retro-injected inside the migrator — doing so would break the lossless gate (see Phase 0 gate) and blur what "migrated" means.

**Known consequence, recorded so it does not die silently:** the predecessor's export defect dropped the daily supplement, so migrated history sits ~5 kcal/day and — more materially — **~4 g/day soluble fiber below truth**, with a small step discontinuity in the fiber averages where new-app days (which persist the supplement at creation) begin. Fiber is a watched metric here, so this correction is flagged, not paved over.

**The fork in the road:** the correction, if wanted, is an **optional one-time backfill utility** — a Phase-1 candidate, built and committed *separately* from migration:
- a distinct, explicit operation, never part of boot or migration;
- injects the daily supplement into selected historical days;
- items flagged `_auto: true` **and** `backfilled: true` (identifiable, and distinguishable from natively-created supplement items);
- reversible and confirm-gated;
- whether to run it is the user's call at the time it exists.

Build the fork; do not pave over it.

## D5 — Export / import-restore semantics (2026-07-11)

**Export (copy-out)** is read-only and purely local: serialize the `healthtracker-log` **log state only** (never the `-prerestore` backup — machinery, not data, and it would needlessly double any payload pasted to Claude) to pretty JSON, offered via the dual clipboard strategy (Clipboard API → `execCommand` fallback) plus an always-populated visible copyable surface.

**Import/restore** is a **destructive full replace** of `healthtracker-log`, the highest-risk operation in the app. Order of operations, mutating nothing until a valid replacement is in hand:

1. **Validate first (no mutation, no backup on failure).** `cleanJSON` normalize → `JSON.parse` → shape check. Reject if parse fails, the blob is not a log (no `days` object), **any day key does not match `YYYY-MM-DD`** (a crafted key is markup waiting for an unescaped render — reject it at the boundary), or **`version` > the app's schema version** ("this export is from a newer version of the app"). Forward-version rejection is absolute — we migrate up, we never silently load down. Same- or lower-known-version proceeds (a lower version runs the in-place migrator when one exists; at v1 there is none).
2. **Shape routing — `version` wins.** A blob **with** an internal numeric `version` is new-schema, full stop, even if it also has `days`. Legacy routing (through the proven `migrateLegacy`) applies **only** when `version` is absent. New-schema blobs restore **as-is, no added stamp** (clean export→import round-trip); legacy blobs get `migratedFrom`/`migratedAt`.
3. **Confirm gate, then pre-restore backup (D3) — applies to every restore, legacy paste included.** Backup is attempted *before* the confirm so the prompt can tell the truth about whether one exists. Write current state to the durable `healthtracker-log-prerestore` key (**single rolling slot — exactly one level of undo**) and render it into a visible copyable surface that persists after the restore. If the backup write fails (memory/quota), do **not** claim a backup: the confirm degrades to "storage can't hold a backup — copy the on-screen text first," and the visible surface is the sole recovery path. **Decline is a true no-op for the slot:** snapshot the slot's current value *before* overwriting it; on a declined restore, restore that snapshot (or clear the slot if it was empty) and hide the surface — a cancel must never consume the one level of undo earned by a *prior* restore. On confirm, keep the new backup.
4. **Overwrite → persist**, then run the **same** boot normalization path (`normalizeStatuses` + `ensureCurrentDay`) — one normalization code path, not two. Restore never touches `uha-log-v1`, so D2 precedence still holds next boot.

**Round-trip equality (formal, for the gate):** exporting a state and importing it reproduces that state such that **every day present in the source matches exactly**, and the **only** permissible deltas are (i) one added empty `in_progress` day for today and (ii) the `current` pointer set to today. Nothing else may differ.

**Amendment — schema v2 / legacy removed (2026-07-11).** v4 retires the legacy `uha-log-v1` route, so the version routing above changes:
- version **absent** → **reject** ("unrecognized log format") — was: route through `migrateLegacy`;
- version **1** → run the in-place **v1→v2** migrator (D7), then restore — was: restore "as-is";
- version **2** → restore as-is;
- version **> 2** → reject (forward-version guard, now `> 2`).

The legacy clauses in steps 1–2 are void. Validate-first, confirm + D3 backup + degraded path, decline-no-op, escaping, and day-key validation are unchanged. Per-item coercion at the **restore boundary** now **clamps** numbers ≥ 0 (untrusted paste) and coerces/clamps `micros` while preserving unknown micro keys; `source` is validated against its enum (fallback `manual`). The in-place migrator (D7), operating on the user's own trusted blob, coerces without clamping — it preserves day/item values byte-for-byte.

**Round-trip equality, v2:** a **v2** export→import reproduces the state with the only permissible deltas being the added-today day and the `current` pointer — now including `settings` and `priceLog` preserved exactly. A **v1** import is a deliberate one-way **upgrade** to v2 (gains `settings`/`priceLog`; items gain `source`), **not** identity.

## D6 — Service worker + manifest: offline shell, update lifecycle, dev story (2026-07-11)

The SW caches the **app shell only** (HTML/CSS/JS/manifest/icons); all *data* lives in `localStorage`, which the SW never touches. Offline = shell from cache + the existing data layer reading `localStorage`.

**Cache-first atomic shell.** No build step → no content-hashed filenames → a *mixed* strategy (network-first HTML + cache-first JS) can serve fresh HTML against stale JS (version skew). Avoided structurally: the same-origin shell is served cache-first from a single versioned cache; a new SW precaches new HTML *and* JS together and swaps only on `activate`, so both always come from the same generation. Everything else is network passthrough.

**Cache name + cleanup — Amendment A.** Cache is `healthtracker-shell-<id>`. `activate` deletes only caches matching `healthtracker-shell-*` that aren't current — **not** every non-current cache. A blanket purge would nuke the Phase-2 `healthtracker-runtime` ZXing cache on every shell bump and silently re-break offline scanning until the next online session.

**Update lifecycle — no `skipWaiting`, apply next launch, passive visible hint.** A new SW installs, precaches the next generation, and waits; it activates only when all app clients are gone (next launch). No `skipWaiting` / `clients.claim` / auto-reload — someone mid-entry on an in-progress day is never yanked through a reload. Not fully silent (that would fail this app's truthful-badge philosophy): on `updatefound`→`installed` with an existing controller, show a small non-blocking "Update ready — reload" affordance (the SW equivalent of the storage badge). The user reloads between entries; it applies next launch regardless.

**Known property — Amendment C.** For a home-screen PWA that lingers in the app switcher, "all clients gone" may not happen for days, so an update can wait. Acceptable for a personal app and mitigated by the hint; recorded here so it is not later filed as a bug.

**Dev story — environment split.** On `localhost` / `127.0.0.1` the SW is network-first (fall back to cache) so active development never serves a stale shell; on the deployed origin it is cache-first. A `?prod=1` override on the SW URL forces the production cache-first path even on localhost — used by the offline gate test.

**Precache discipline.** Hand-maintained `PRECACHE` list, relative paths. A 404 in `cache.addAll` rejects the whole install silently and disables offline. `tests/check-precache.sh` verifies every precached path exists on disk and fails loudly otherwise. Real icon assets (SVG maskable + iOS PNG) are produced in this slice — referencing phantom icons is exactly the 404-kills-install trap.

**Phase 2 forward note.** The ZXing CDN fallback is the app's one future cross-origin resource. The fetch handler's "else = network passthrough" branch is the extension point: runtime-caching ZXing later is additive (one conditional → a separate `healthtracker-runtime` cache, cache-first over an opaque no-cors response). No restructuring, and Amendment A keeps that cache safe from shell cleanup.

**Offline gate evidence — Amendment B (automated is canonical).** `tests/offline-gate.ps1`: a PowerShell `HttpListener` static server on `127.0.0.1` + headless Chrome with a persistent profile, forced onto the prod path via `?prod=1` (so the run exercises production cache-first, not the localhost network-first dev branch). Seed synthetic history → load with the server **up** (SW registers + precaches) → **stop the server** → reload → the shell + history render from cache with the origin unreachable. The manual DevTools procedure (Application → Service Workers → Offline → reload) is the documented fallback. Re-runnable evidence over attested.

**Amendment — content-derived cache name, enforced (2026-07-12).** The original manual `VERSION` integer required remembering to bump it on every shell change — and it was **missed on every slice after Phase 0**, so the deployed SW never installed an update and served a frozen first-deploy shell (the "update ready" hint had nothing to fire on). Replaced with a **content-derived** `SHELL_HASH`: the hash of the precached shell (index.html, app.js, manifest.json, icons), stamped into `sw.js` by `bash tests/check-sw-hash.sh --fix` and **enforced by the gate** — `check-sw-hash.sh` runs inside the data-layer gate and **fails if the shell changed but `SHELL_HASH` didn't**, so it can't be forgotten again. Any shell change flips the hash → new `sw.js` bytes → the browser installs a new SW → new cache (and Amendment-A cleanup) → the update hint fires. No serve-time build (stamped at commit time, like the test harness); `sw.js`'s own edits are self-detecting. Text is line-ending-normalized before hashing so the hash is platform-stable; PNGs are hashed raw. **Observed on device (2026-07-12):** after this fix deployed (39fc6b1), the browser installed the new SW and the "Update ready" bar appeared on the phone's cached shell — D6 Amendment C validated in production, not just reasoned about.

## D7 — Schema v2 migration: in-place v1→v2 with a retained pre-migration snapshot (2026-07-11)

The first real exercise of the versioning machinery D1 was built for. Boot reads `healthtracker-log`; the **same** migrator serves the restore boundary for a pasted v1 blob.

- **Trigger:** blob `version === 1` (also a version-absent blob under our key, defensively). `version === 2` is used as-is; version absent *at the restore boundary* is rejected (D5 amendment); `version > 2` is rejected everywhere (forward guard).
- **Add-only transform:** add empty `settings` (`goals:{}`, `supplement:{enabled:false, name:'', nutrients:{}}`, `presets:[]`) and `priceLog:{}`; set each item's `source` (`supplement` if `_auto`, else `manual`); bump `version` to 2. Existing days, items, water, and `current` are **preserved byte-for-byte** — migration never editorializes (the D4 principle survives its retirement). This preserves the user's logged days; a genuinely clean slate is done deliberately by the user via export + clear, **never** by the migrator.
- **`known` is dropped** (v4 removes it; superseded by `settings.presets`). If a non-empty `known` is ever encountered it is dropped and its count recorded as `knownDropped: <n>` in the migration stamp — recorded truth, zero machinery.
- **Pre-migration snapshot (R1):** before writing the v2 blob, snapshot the untouched v1 blob to `healthtracker-log-premigration` — a labeled rollback key, **never auto-read**, **retained** (not cleared). Insurance against a migration *logic* bug; atomic `setItem` already covers write failure but not dropped data. Deleting insurance to save one small key is false economy. Written once (a pre-existing snapshot is never overwritten).
- **Stamp:** the v2 blob records `migratedAt` (ISO); fresh new-user v2 states carry no such stamp.
- **Idempotent:** runs once (1 → 2); subsequent boots see version 2 and skip.
- **Forward blob in storage:** if `healthtracker-log` already holds `version > 2` (a newer app wrote it), boot does **not** migrate or overwrite it — the newer data is left untouched and surfaced read-only, never clobbered with an empty state.

## D8 — Ingest: four-shape non-destructive merge, AI-paste honesty, report (2026-07-11)

Ingest is the paste channel — **two sub-channels with different trust:**
- **Item shapes** (`{items:[…]}` +optional top `date`, bare array, single item object) = the **AI-paste channel** (untrusted model text).
- **Full-days shape** (`{days:…}`) = a **non-destructive day merge of the user's own export** (attested by construction).

**Standing rules:** item `date` > top `date` > today; day keys validated `YYYY-MM-DD` at the boundary; per-item coerce + clamp ≥ 0; `cleanJSON` normalize; escape every rendered field including the report.

1. **Complete-day append (fork 1).** An item-shape paste targeting a `complete` day appends and **reopens it to `in_progress`**, reported. Post-hoc additions must not silently re-enter a closed day (averages discipline). Full-days merge never reaches a day with items.
   - **Empty/fillable, tightened:** a full-days merge fills a local day only if it is **no items AND `water_l === 0` AND status `in_progress`**. A `complete` day (even with zero items — a deliberately-closed fast) and a water-only day carry real information and are never overwritten.
2. **AI-paste honesty (forks 2, 7).** Item-shape items are forced to `source: ai-paste`, `confidence: eyeballed`, and **micros stripped** — regardless of any `source`/`confidence`/`micros` in the paste. The boundary can't verify intent, so it **never honors a self-declared source** (no loophole). Label micros enter **only** via the manual add-item UI (`source: manual`) or the scan path. Full-days items are preserved as-is (their `source`/`micros`/`confidence` kept) — the own-data channel.
   - **Recorded loophole (accepted):** the full-days channel is user-attested by construction; someone can wrap AI output in a `{days:…}` shape to smuggle micros — same trust level as restore (deliberately packaging as "my export" *is* the attestation). Two consequences pinned: (i) the in-app AI prompt template must only ever request **item shapes**; (ii) days-merged items carry whatever `source` they arrived with — the channel never launders them into `manual`.
3. **Duplicates (fork 3).** Non-destructive merge protects days, not items — the same item pasted twice double-logs, **accepted** (silent dedup guessing wrong loses real data; a visible double-add costs one delete tap). The report surfaces the count.
4. **Supplement injection is a property of day creation on this device (fork 4).** When `settings.supplement.enabled`, the flagged non-deletable supplement item is injected at **device-side day creation** — boot, day navigation, and an **item-shape ingest that creates a new day**. Enabling mid-day injects into today (if absent) and all future creations; **never** past days. Days arriving **wholesale** (full-days merge or restore) are taken as-is — no injection on top (that is where the double-supplement risk lives, and an imported day may already carry its own). Closes the under-recording hole for AI-channel-only users without double-counting imports.
5. **Ingest report = honesty surface (fork 5).** A **persistent** panel (not a toast), escaped, itemizing every effect: items **added** (per day), days **created**, **supplement injected**, days **reopened**, **micros stripped** (AI-paste count), days **skipped** (already populated), items **rejected** (no name / bad date). The app explains what it did to the user's data.
6. **One front-end, two back-ends (fork 6).** The full-days shape routes through the **same** validation + version guard as restore (absent → reject, v1 → migrate incoming days via the D7 migrator, v2 → as-is, > 2 → reject), then applies the non-destructive merge. Ingest merges **days only** — local `settings`/`priceLog` are never touched by a paste (that is restore's job). Reusing the D7 migrator prevents a second parser drifting.

## D9 — Manual add + presets: human-attested item creation, micro units (2026-07-11)

Manual add and presets are **human-attested** creation paths, distinct from the AI-paste channel (D8).

**Manual add** → a `source: manual` item on the selected day:
- **Selectable confidence** (eyeballed / weighed / measured), default **eyeballed**. Forced-eyeballed is the AI channel only (D8) — a human with a scale logs `weighed`.
- May carry **micros** (human label attestation). Numbers coerced + clamped ≥ 0; micros coerced/clamped; unknown micro keys preserved.
- Appends; never overwrites. Onto a `complete` day it **reopens** to `in_progress` (same rule as D8/1).

**Micro units — silent-corruption defense:**
- Every micro field renders its **unit hard against the field** (persistent adjacent label, never a vanishing placeholder). Field → canonical key → unit is **1:1, no cross-wiring** (gated). Form fields are generated from a single `MICRO_SPEC` table and read back by the same canonical key, so generation and reading can't drift.
- **Sane-range soft warnings** — inline and **non-blocking** everywhere (real outliers exist): sodium 10000 mg, potassium 10000 mg, calcium 5000 mg, iron 100 mg, magnesium 1000 mg, zinc 100 mg, cholesterol 5000 mg, vitamin_a 10000 µg, vitamin_c 5000 mg, vitamin_d 1250 µg, vitamin_b12 5000 µg, folate 2000 µg, saturated_fat 200 g, sugars 500 g; macros too: kcal 10000, any macro 1000 g. (µg is shown as `mcg` in the UI to keep the source ASCII-clean.)
- The 14 micros sit behind a collapsible **"micronutrients (from label)"** disclosure; collapsed-with-fields-filled, the header shows a **count** ("micronutrients (4 entered)") so hidden values can never be saved unseen (fork C).

**Presets** (`settings.presets[]`, each with a stable **id** — names may collide):
- **Fixed calibrated values, logged as-is** (fork A). "Portion" is a **descriptive label** only, never a scaling factor — a log-action multiplier is a Phase-4 candidate, deliberately not built.
- Carries name, meal, confidence, macros, soluble fiber, and **micros** (a preset is a saved manual attestation; preset-logged items inherit its micros — fork 4).
- v1 lifecycle: **create / delete / log only** (edit = delete + re-save — fork B).
- **Log-from-preset** copies values into a new `source: preset` item (current time), appends to the selected day, reopens a complete day.
- **Delete removes only the preset — already-logged items are copies, never touched** (requirement 5, gated).

**Two independent creation actions (fork D):** **"Add to day"** and **"Save as preset."** Save-as-preset writes a preset and gives visible confirmation **without clearing the form**, so save-then-add works without retyping; it does not log an item.

## D10 — Averages: complete-days-only, per-nutrient micro coverage, honest empty state (2026-07-11)

Read-only. Two windows, both **complete-days-only** (manual-close discipline — in-progress days never count):
- **7-day = calendar window**: complete days whose date key is ≥ (today − 6 days). **Not** "last 7 complete days" — logging gaps thin the sample honestly.
- **All-time**: all complete days.

**Macros** (kcal, P, F, C, fiber, soluble): every complete day has them (0 for a fasting day), so the mean is Σ(day totals) / **M** over the M complete days in the window — full coverage. The supplement, when enabled, is a *persisted* item and is therefore already in the totals; no render-time addition (the predecessor's understatement bug stays dead).

**Micros — per-nutrient coverage, absence ≠ zero:** for each micro K, a complete day "carries K" iff some item in it has K. K's mean = Σ(daily K over days carrying K) / **N_K**, annotated **"from N_K of M complete days."** A day whose only micro is iron feeds iron's mean and coverage, never sodium's. A day without K data is **excluded** from K's mean, never counted as 0. Both the daily summary and the averages micro block carry the honesty label **"Micronutrients — labeled intake only"** — micros never originate from the AI-paste channel (D8), so the label states where they *can* come from (scan / manual label).

**Empty state:** M = 0 (no complete days in the window) renders an honest empty state ("close a day to see averages"), never zeros posing as data. A micro with N_K = 0 simply does not appear.

## D11 — First-run onboarding + AI prompt template (2026-07-11)

**First-run is derived from state, never a stored flag.** `isFirstRun()` = no day has a non-`_auto` item **AND** no presets **AND** no goals — a pristine install. Computed fresh each render; nothing persisted (survives export/import; nothing to migrate or drift). No manual "dismiss" (that would need a flag) — onboarding auto-recedes on first engagement, and the prompt template stays available afterward. Enabling a supplement alone (an `_auto` item) does **not** end first-run — the user still hasn't logged food (fork A).

**Onboarding** (fork B): a dedicated teaching card at the top, rendered **only** when first-run — the two input paths (AI-photo + manual, with label micros noted), a **skippable** link to goal setup (fork D — a scroll, not a wizard), and the privacy line.

**AI prompt template:** one canonical constant `AI_PROMPT_TEMPLATE` + `AI_TEMPLATE_VERSION` (tied to the schema; **shown on the template card** so a stale copied template is visible). Its own always-available card adjacent to Ingest (fork C), copyable via the dual-clipboard strategy. It requests JSON only, straight quotes, the item schema **without micros**, `confidence: "eyeballed"`, honest portions in `notes`, `soluble_fiber_g` present, and spells out the **full meal enum** (breakfast | lunch | dinner | snack | drink | supplement) so an assistant can't invent values.

**Template↔ingest self-consistency (gated):** an adjacent `AI_PROMPT_SAMPLE` that obeys the template runs through real `ingest()` and must yield source `ai-paste`, `confidence: eyeballed`, **no micros**, `soluble_fiber_g` present. Template + sample live adjacent so they drift together or not at all. A second assertion pins the template *text* invariants: no micro request, and it mentions eyeballed / straight quotes / `soluble_fiber_g` / the full meal enum.

## D12 — Supplement config UI: unified day-scope, shared micro component (2026-07-11)

The supplement is a single user setting (`settings.supplement = {enabled, name, nutrients}`), off by default — **single supplement stack in v1** (multiple named supplements is a Phase-4 candidate). The config form sets **name + nutrients** (kcal, macros, soluble fiber, micros); the built item's `confidence: measured`, `source: supplement`, `meal: supplement`, and `_auto: true` are **fixed**. Non-deletable-in-UI is enforced by the day view hiding delete/cycle for `_auto` items — the only way to remove it is to disable the setting.

**Unified day-scope rule** (enable / disable / edit all share it): the supplement setting governs **today-while-`in_progress`** + all **future** day-creations; it **never rewrites a settled (`complete`) day** — today-once-closed or any past day. History stays recorded.
- **Enable** → inject into today if it is `in_progress` and lacks the `_auto` item; future creations inject via the existing day-creation logic (refines D9's "today if absent" with the `in_progress` qualifier).
- **Disable** → remove today's `_auto` item if today is `in_progress`; leave complete/past days. The `_auto` item is your **standing planned dose**, so disabling removes today's planned dose; a one-off you actually took is logged manually.
- **Edit** → rebuild today's `_auto` item in place from the new values if today is `in_progress`; future creations use the new values.
- **Complete-today edge:** if today is already `complete` when the setting changes, today is settled — the change takes effect on the next open day (or if you reopen today); it does **not** reopen or rewrite it. Config is not a log action.

**Micros — one component, two forms.** The supplement form is a human reading a supplement label (manual attestation, D8), so `nutrients` may carry micros (where a real stack's vitamin D / B12 live). The existing micro component is generalized — `renderMicroFields(hostId, prefix, countId)` / `readMicroFields(prefix)` — and mounted in both the manual-add form and the supplement form: same `MICRO_SPEC`, units, sane-range warnings, and no-cross-wiring guarantee. **No second micro form.**

**Restore hardening:** `normalizeSupplement` coerces + clamps the `nutrients` map (macros and micros, ≥ 0) at the restore boundary, so a hostile paste can't seed negative/huge config values; the form's displayed values are escaped. (The built item was already clamped; this protects the stored config and its display — a surface that was previously passthrough.)
