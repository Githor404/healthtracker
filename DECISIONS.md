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

**Cache name + cleanup — Amendment A.** Cache is `healthtracker-shell-v{N}` (`N` a `VERSION` constant, bumped on shell changes). `activate` deletes only caches matching `healthtracker-shell-*` that aren't current — **not** every non-current cache. A blanket purge would nuke the Phase-2 `healthtracker-runtime` ZXing cache on every shell bump and silently re-break offline scanning until the next online session.

**Update lifecycle — no `skipWaiting`, apply next launch, passive visible hint.** A new SW installs, precaches the next generation, and waits; it activates only when all app clients are gone (next launch). No `skipWaiting` / `clients.claim` / auto-reload — someone mid-entry on an in-progress day is never yanked through a reload. Not fully silent (that would fail this app's truthful-badge philosophy): on `updatefound`→`installed` with an existing controller, show a small non-blocking "Update ready — reload" affordance (the SW equivalent of the storage badge). The user reloads between entries; it applies next launch regardless.

**Known property — Amendment C.** For a home-screen PWA that lingers in the app switcher, "all clients gone" may not happen for days, so an update can wait. Acceptable for a personal app and mitigated by the hint; recorded here so it is not later filed as a bug.

**Dev story — environment split.** On `localhost` / `127.0.0.1` the SW is network-first (fall back to cache) so active development never serves a stale shell; on the deployed origin it is cache-first. A `?prod=1` override on the SW URL forces the production cache-first path even on localhost — used by the offline gate test.

**Precache discipline.** Hand-maintained `PRECACHE` list, relative paths. A 404 in `cache.addAll` rejects the whole install silently and disables offline. `tests/check-precache.sh` verifies every precached path exists on disk and fails loudly otherwise. Real icon assets (SVG maskable + iOS PNG) are produced in this slice — referencing phantom icons is exactly the 404-kills-install trap.

**Phase 2 forward note.** The ZXing CDN fallback is the app's one future cross-origin resource. The fetch handler's "else = network passthrough" branch is the extension point: runtime-caching ZXing later is additive (one conditional → a separate `healthtracker-runtime` cache, cache-first over an opaque no-cors response). No restructuring, and Amendment A keeps that cache safe from shell cleanup.

**Offline gate evidence — Amendment B (automated is canonical).** `tests/offline-gate.ps1`: a PowerShell `HttpListener` static server on `127.0.0.1` + headless Chrome with a persistent profile, forced onto the prod path via `?prod=1` (so the run exercises production cache-first, not the localhost network-first dev branch). Seed synthetic history → load with the server **up** (SW registers + precaches) → **stop the server** → reload → the shell + history render from cache with the origin unreachable. The manual DevTools procedure (Application → Service Workers → Offline → reload) is the documented fallback. Re-runnable evidence over attested.

## D7 — Schema v2 migration: in-place v1→v2 with a retained pre-migration snapshot (2026-07-11)

The first real exercise of the versioning machinery D1 was built for. Boot reads `healthtracker-log`; the **same** migrator serves the restore boundary for a pasted v1 blob.

- **Trigger:** blob `version === 1` (also a version-absent blob under our key, defensively). `version === 2` is used as-is; version absent *at the restore boundary* is rejected (D5 amendment); `version > 2` is rejected everywhere (forward guard).
- **Add-only transform:** add empty `settings` (`goals:{}`, `supplement:{enabled:false, name:'', nutrients:{}}`, `presets:[]`) and `priceLog:{}`; set each item's `source` (`supplement` if `_auto`, else `manual`); bump `version` to 2. Existing days, items, water, and `current` are **preserved byte-for-byte** — migration never editorializes (the D4 principle survives its retirement). This preserves the user's logged days; a genuinely clean slate is done deliberately by the user via export + clear, **never** by the migrator.
- **`known` is dropped** (v4 removes it; superseded by `settings.presets`). If a non-empty `known` is ever encountered it is dropped and its count recorded as `knownDropped: <n>` in the migration stamp — recorded truth, zero machinery.
- **Pre-migration snapshot (R1):** before writing the v2 blob, snapshot the untouched v1 blob to `healthtracker-log-premigration` — a labeled rollback key, **never auto-read**, **retained** (not cleared). Insurance against a migration *logic* bug; atomic `setItem` already covers write failure but not dropped data. Deleting insurance to save one small key is false economy. Written once (a pre-existing snapshot is never overwritten).
- **Stamp:** the v2 blob records `migratedAt` (ISO); fresh new-user v2 states carry no such stamp.
- **Idempotent:** runs once (1 → 2); subsequent boots see version 2 and skip.
- **Forward blob in storage:** if `healthtracker-log` already holds `version > 2` (a newer app wrote it), boot does **not** migrate or overwrite it — the newer data is left untouched and surfaced read-only, never clobbered with an empty state.
