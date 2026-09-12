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

**Phase-4 forward note — home-screen update delivery for distributed users (2026-07-17, do not act now).** Across **every** Phase-2 on-device test, a shipped fix was live on the server but the **home-screen PWA kept serving the old shell until a full app-kill** (close-reopen), not just a resume from the app switcher. This is *correct* no-`skipWaiting` behavior (Amendment C already recorded that "all clients gone" may not happen for days), but Amendment C justified it as **"acceptable for a personal app"** — and **v4 is now a distributed app** (D17), so that premise is weaker: ordinary users won't know to force-quit, so a fix can take days to reach installed apps. Open questions for Phase 4 (not this phase): does the "Update ready" bar actually **surface and apply reliably in `display: standalone` context** (a resumed-from-switcher PWA may not re-run the SW update check, so the bar may never fire until the full relaunch that *also* activates the new SW anyway — possibly making the bar moot in exactly the case that matters)? Candidate mitigations to weigh with effort estimates: an explicit periodic `reg.update()` on `visibilitychange`, a more assertive (but still non-yanking) update prompt, or a bounded opt-in `skipWaiting` for shell-only patches. Recorded so it is a **ranked Phase-4 candidate**, not a bug rediscovered on every deploy.

**Amendment — force-and-notify: automatic updates + post-update changelog (Phase-4 Slice G, 2026-07-17). Supersedes BOTH the original no-`skipWaiting` rule AND the (rejected) gesture-scoped-`skipWaiting` amendment.** A gesture-bar design (visibilitychange resume-check + "Update now" + `SKIP_WAITING` message + reload-once) was drafted and **rejected**: it depended on the iOS resume-from-app-switcher path, which does not reliably fire, so it failed on device. **Ruled instead: force the update automatically on load, then notify after the fact.**

- **What "force across the platform" means here (pinned).** A no-backend app cannot push to installed devices — there is no server, by design. So this does **not** mean "change every phone from our end instantly." It means: **the next time any device loads the app, it is forced onto the current version — no waiting, no gesture, no stale copy can persist.** Every device becomes current on its next load; no lingering-old-version state is possible. That is as platform-wide as a privacy-preserving, backend-free app can be, and it is the correct amount.
- **Force on load — drop no-`skipWaiting`.** The SW calls `self.skipWaiting()` on `install` (automatically) and `self.clients.claim()` on `activate`, so a normal load / reopen / reload gets the current version. No bar, no button, no user action. This **deliberately reverses** D6's no-`skipWaiting` rule. On a page that already had a controller (an update, not a first install), `controllerchange` triggers **one** guarded `location.reload()` to the new shell; a first-ever install does **not** reload (guarded on a prior controller existing).
- **Post-update notice (informational, after the fact — NOT a permission prompt).** `APP_VERSION` is stored under `healthtracker-version`; on load `versionNotice(stored)` compares it to the running `APP_VERSION` and, if changed, shows a **dismissible** notice, then updates the stored value. A genuine first install (`isFirstRun`, no stored version) shows **no** spurious "updated" notice.
- **Multi-version jumps.** A returning user may open after several releases. `versionNotesBetween(from, to)` returns the **accumulated** changelog for every version in `(from, to]` (numeric `cmpVersion`, so `0.2.0 < 0.10.0`), not just the latest — the notice reads e.g. "Updated from v0.2 to v0.5" with each skipped version's line.
- **Changelog: in.** `VERSION_LOG` is a single in-code `version → note` list (one line per release, like `AI_TEMPLATE_VERSION` lives in one place). Turns a bare bump into something a user values and makes updates feel intentional and cared-for.
- **`APP_VERSION` is load-bearing** — it bumps **every release** (also the OFF UA version, D14). `tests/check-version.sh` gates it: `APP_VERSION` must have a `VERSION_LOG` entry and be the newest, and a **shell change without an `APP_VERSION` bump fails** (committed `(SHELL_HASH, APP_VERSION)` baseline drift check, same spirit as `check-sw-hash`). So a shipped update can't silently show no notice, and a bump can't ship without a changelog line.
- **Accepted tradeoff (eyes open).** Forcing on load means a reload **can swap the app version mid-use** — e.g. part-way through logging a meal. **Deliberately accepted:** the app auto-saves and logging is quick, so a mid-use refresh is cheap, whereas "updates never arrive on installed PWAs" (the problem the gesture design left unsolved) is a genuinely worse failure. Still safe from version skew by D6's **atomic shell** (new HTML+JS from one generation).
- **Gate.** `tests/update-gate.ps1` (CDP) asserts: a shell change → the new SW **activates automatically on load** (not waiting for all clients, not a gesture) and the new shell is served. Notice logic (from→to, multi-version accumulation) is committed as `VN` harness cases; the `APP_VERSION`-vs-shell drift is `check-version.sh`. **On-device attestation (signed after deploy by simply reopening the app):** reopen → "Updated to vX" with the changelog appears, no force-quit — reliable because it applies on **load**, which a plain reopen triggers (unlike the rejected resume-from-switcher path). SW/shell only; `localStorage` untouched.

**Refinement — resume counts as a load (2026-07-19, v0.5.1).** On-device gap: force-and-notify applies on **load**, but an iOS home-screen PWA **resumed from the app switcher never navigates**, so the check can't fire and a resident old version lingers until a real launch — the force-quit ritual creeping back for the primary surface, the exact thing the amendment set out to kill. Fix: a **throttled `visibilitychange` resume-check** — on becoming visible (throttled ~5 min via a `lastCheck` stamp), call `reg.update()`. **This is NOT the rejected gesture-bar design** (line above): it adds **no** bar, button, or `SKIP_WAITING` message — it only asks the browser to re-check `sw.js`, and any resulting new SW force-applies + notices through the **same** `controllerchange`→reload→changelog path a load already uses. "Resumes count as loads" is the intended force-and-notify behavior the load-only trigger under-delivers on iOS. **Safe by construction:** the amendment already accepted the mid-use swap deliberately, so applying on resume adds no new tradeoff — it only widens *when* the already-accepted swap can occur; the throttle bounds redundant checks. `swnow=1` zeroes the throttle as a test seam (like `prod=1`). **Bootstrap caveat:** the resume-check ships *in* v0.5.1, so v0.5.1 itself is first obtained via a real launch; every release *after* it can arrive on a resume. **Gate:** `update-gate.ps1` extended with a **resume path** — a controlled page + a shell change + a dispatched `visibilitychange` (no navigation) must auto-apply the new shell.

**Amendment — the converse arm: a bump REQUIRES a shell change (2026-09-06).** D6 has always ruled one direction — *a shell change without an `APP_VERSION` bump fails*, so a shipped update can't silently show **no** notice. **The converse was never ruled and was never enforced: a bump with no shell change ships a notice that announces an update that did not happen.** Both halves are now binding: **`APP_VERSION` moves when the shell changes, and only when the shell changes.**

- **Why this is not pedantry.** Force-and-notify means the bump *is* the user-facing event: every device that loads is forced current and then shown the `VERSION_LOG` line. A hollow bump therefore doesn't ship "nothing" — it ships a **changelog entry describing work the user cannot see, on other people's devices**, and every existing `VERSION_LOG` note is a real, observable change ("Tap the unit to switch it", "Fix: the quick-log chips now wrap to rows"). There is no honest sentence to write for a release that changed no shipped byte. Same family as D50/D52/D53/D56: the surface must not claim more than the substance.
- **Occasion (recorded, not hypothetical).** 2026-09-06, after v0.21.0: a release was requested when `git diff v0.21.0..HEAD -- index.html app.js manifest.json icons` was **empty**. Every commit since the release touched only `DECISIONS.md`, `tests/README.md`, `tests/run-all-gates.sh` — infrastructure that never reaches a device. Caught before shipping, by inspection rather than by a gate; hence the gate.
- **Infrastructure work is not a release.** Gates, harness, decision log and docs are committed and pushed like anything else, and they change **no** version. A user's device is not the audience for a test runner. Holding the version is the correct outcome, not a deferral.
- **The gate — why it can't be a plain diff.** Bumping `APP_VERSION` *itself edits `app.js`*, which is a shell file, so "the shell changed" is trivially true on **every** bump and a naive check would never fire. `tests/check-version.sh` therefore compares a **version-metadata-stripped fingerprint**: the shell text with the `APP_VERSION` assignment and the `VERSION_LOG` entry lines removed, hashed and compared against `HEAD` (line-ending-normalized, binaries compared via git — same conventions as `check-sw-hash`). Identical fingerprint + a moved `APP_VERSION` = the version is the only thing that changed = **FAIL**.
- **Deliberately still allowed.** Editing a `VERSION_LOG` note's wording, or any other version metadata, **without** moving `APP_VERSION`: the arm keys on `APP_VERSION` actually changing, so fixing a typo in a shipped changelog line is friction-free — consistent with the gate's existing "iterating within a release is friction-free" stance.

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

## D13 — Product cache: capped localStorage key, disposable mirror (2026-07-16)

Phase 2 Slice 1. The OFF product cache (barcode → product + nutriments + fetched-at) was deferred from Phase 0 to be decided with Phase 2's needs in view. **Ruled: a capped localStorage key, not IndexedDB.**

- **Storage:** a single dedicated key `healthtracker-products`, a JSON map `{ <barcode>: <record> }`, read/written through the **existing D1 `Store` adapter** (localStorage → memory tier, same probe). No second storage subsystem, no async — the cache stays **synchronously testable** by the committed harness. IndexedDB is the **Phase-4 escalation only**, if product volume ever outgrows the localStorage budget.
- **Nature: a disposable, rebuildable mirror — not user data.** Losing it costs a re-fetch, never data. Three consequences follow:
  1. **Excluded from export/import.** Export serializes the log only (D5); the product cache is machinery like `-prerestore`/`-premigration` — never exported, never restored, never merged by ingest. A round-trip neither reads nor writes it.
  2. **A cache write failure is a benign no-op, NOT a badge event.** The truthful badge (D1) speaks for *your log*; a failed cache put (memory mode / quota) just means the next lookup re-fetches. The lookup still returns the freshly-mapped record from the in-flight fetch. Cache failure never flips the storage badge to a warning (distinct from a log-write failure, which does).
  3. **In memory tier the cache simply doesn't persist** — every lookup is a fetch. Correct, not a bug (mirror, not truth).
- **Entry shape: the *mapped* record, not raw OFF (ruled).** Each entry is the normalized per-100g product record `{ barcode, name, brands, quantity, serving_g, per100:{macros}, micros:{present canonical keys only}, fetchedAt, cacheVersion }` — the trust boundary (escape-safe strings, coerced+clamped numbers, absence≠zero micros) is crossed **once, at fetch time** (D14), so every rescan reads already-clean data. The rejected alternative (cache raw OFF, map on read) re-runs the boundary each read and can serve wrongly-shaped data after a mapper change.
- **`cacheVersion` stamp:** each entry carries the mapper's schema version. On read, an entry whose `cacheVersion` ≠ current is treated as a **miss** (ignored, re-fetched, overwritten) — a mapper change can never serve stale-shaped cached data. Bump `cacheVersion` whenever `mapOffProduct`'s output shape changes.
- **Eviction — LRU, cache yields first.** Count cap **500** products and a serialized byte ceiling **~512 KB** (well under the ~5 MB localStorage budget, leaving ample room for the log). Each entry records `lastAccess`; a `put` that would breach either cap evicts oldest-access first until it fits. The cache never grows unbounded and always yields storage to the log.
- **Refresh — pure cache-first, no auto-TTL (ruled).** A cached product resolves without a network call (OFF's 15 req/min/IP courtesy, D14; nutriments rarely change). Staleness is handled by an **explicit, manual** "refresh from OpenFoodFacts" affordance — **never automatic**, never a background revalidate.
- **Cache taxonomy — three distinct caches, do not conflate:** (1) `healthtracker-shell-<hash>` — SW Cache Storage, app shell (D6); (2) `healthtracker-runtime` — SW Cache Storage, ZXing UMD (later camera slice, D6 forward note); (3) `healthtracker-products` — **localStorage**, this cache. #3 is **not** a Cache Storage cache; the SW never touches it (D6: data lives in localStorage, which the SW never caches), so D6-Amendment-A shell cleanup can never evict it.

**Amendment — a FOURTH store, and the escalation clause exercised (2026-09-07, D59).** The taxonomy above said *"three distinct caches, do not conflate"* and enumerated three. **That enumeration is now incomplete**, and it is amended here rather than left to go stale — a governance claim that quietly becomes false is believed by the next session that reads it (D54).

**(4) `healthtracker-corpus` — IndexedDB, the micronutrient composition corpus (D59).** Not a cache and not user data: an **accreting asset** that is never evicted, excluded from export, and re-acquired rather than restored. It is the first exercise of this entry's *"IndexedDB is the Phase-4 escalation only"* clause.

**Nothing above changes for the product cache.** D13 is not superseded: its localStorage ruling, its 500/512 KB caps, its LRU eviction, its cache-first refresh and its export exclusion all stand exactly as ruled. D59 rules a different artifact class, and records that this entry's reasoning — *no second storage subsystem, no async, synchronously testable* — was **weighed and traded** there, not sidestepped.

**One clause of this entry does NOT generalise, and D59 turns on why.** *"LRU, cache yields first"* is safe here **because the cache is disposable** — evicting costs a re-fetch and never data. Applied to an accreted corpus the same policy destroys resolution work that a source refresh cannot re-derive. The mechanism that bounds the product cache safely is, for that artifact class, a mechanism for silently deleting it.

## D14 — OpenFoodFacts integration: lookup, micros mapping, identifier transport (2026-07-16)

Phase 2 Slice 1, the data-layer half of the scan path — **no camera** (getUserMedia is a later, on-device-attested slice). The pipeline is a DOM-free, synchronously-testable core (`mapOffProduct`, `scalePortion`, `buildScanItem`, `finishLookup`, `ProductCache`) behind a thin async fetch edge (`fetchOff`/`lookupBarcode`), triggered in this slice by the **manual barcode field** (the camera-free trigger from the scanner spec); the camera later wires into the same `lookupBarcode`.

**Endpoint.** `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,quantity,serving_size,serving_quantity,nutriments`. Barcode hygiene 8–14 digits before any request. Missing product / offline: keep the barcode, offer manual entry — **never lose the code**.

**Identifier transport — the Forbidden-Header resolution (ruled).** `APP_VERSION = '0.2.0'`; identifier string `OFF_UA = 'HealthTracker/0.2.0 (https://github.com/Githor404/healthtracker)'` — repo URL as contact, **no personal email** (the UA reaches a third party on every request from every distributed user; per v4's privacy stance it names the app, never a person). A browser **cannot** set `User-Agent` (WHATWG Forbidden Header — `fetch()` silently drops it), which collides with the brief's "custom User-Agent on every request." Resolution: (i) pass OFF's own documented app-identification **query params** `&app_name=HealthTracker&app_version=0.2.0` on every request (browser-safe identification); (ii) set the `User-Agent` header **defensively** too (a no-op in browsers, correct if ever proxied/native). **Live verification 2026-07-16:** the product endpoint returns **HTTP 200** with those query params attached — confirmed. (OFF documents `app_name`/`app_version`/`app_uuid` for *write* ops; on reads they are benign and are the best identification a browser can send. `app_uuid` is deliberately omitted — a per-install UUID is a tracking identifier, contrary to the privacy stance.)

**Rate limit — the real courtesy.** OFF read limit is **15 req/min/IP** for `GET /api/v*/product` (the `/search` endpoint is stricter — observed 503s under light use, so Slice 1 never uses search). Cache-first (D13) is how we honor it; there is no server to absorb bursts.

**Micros mapping — units + absence≠zero (verified 2026-07-16 on live products).** OFF normalizes every nutriment `_100g` value to the **SI base unit (grams)**, reported in `<key>_unit`. The mapper is **unit-aware**: it converts from the reported `_unit` (g/mg/mcg/µg/kg → target), defaulting to grams when `_unit` is absent — so a factor is *derived*, never hardcoded, and a product that ever deviates still maps correctly. Verified factors:

| Schema key | OFF nutriment | target | verified on real data |
|---|---|---|---|
| kcal | `energy-kcal_100g` (kcal); else `energy_100g` kJ ÷ 4.184 | kcal | Nutella 539, Coca-Cola 42 |
| protein_g / fat_g / carb_g / fiber_g | `proteins_/fat_/carbohydrates_/fiber_100g` (g) | g ×1 | Nutella, Coca-Cola |
| soluble_fiber_g | `soluble-fiber_100g` if present, else **0** | g ×1 | contract: always present |
| **sodium_mg** | **prefer `sodium_100g`; else `salt_100g` ÷ 2.5** | mg | **Nutella: sodium 0.0428 g & salt 0.107 g (ratio 2.5) → both paths 42.8 mg, no double-count** |
| potassium/calcium/iron/magnesium/zinc/cholesterol_mg | `*_100g` (g) | mg (×1000 from g) | calcium 0.267→267, iron 3e-5→0.03, K/Mg/Zn (mineral waters) |
| vitamin_a_ug / vitamin_d_ug / vitamin_b12_ug / folate_ug | `vitamin-a_/vitamin-d_/vitamin-b12_/vitamin-b9_100g` (g) | µg (×1e6 from g) | **vitamin-a 0.0002 g → 200 µg (Ovomaltine)**; b9=folate |
| vitamin_c_mg | `vitamin-c_100g` (g) | mg (×1000 from g) | **0.0264 g → 26.4 mg (Ovomaltine)** |
| saturated_fat_g / sugars_g | `saturated-fat_/sugars_100g` (g) | g ×1 | Nutella 10.6 / 56.3 |

- **Absence ≠ zero:** a micro enters the record **only** when OFF returns its key; a missing nutrient is **omitted**, never zero-filled. A product with zero mapped micros carries **no** `micros` key (not `{}`-of-zeros). Numbers are coerced + clamped ≥ 0; strings kept raw for escaped render (day-view escaping proven, G5/P1).
- **The scanned item** is `source: scan`, `confidence: measured`, retains `barcode`, `soluble_fiber_g` always present, and only the present micros — logged via the honesty rule's labeled-source path. `buildScanItem` runs through `normalizeItem`, so it is contract-clean by construction.

**Portion picker.** OFF per-100g is the base. Modes: **per 100 g** (×1), **per serving** (× `serving_quantity`/100; unavailable/omitted when `serving_quantity` is absent or ≤ 0 — no divide-by-zero), **custom grams** (× g/100). Macros **and** micros scale by the one factor together; an absent micro stays absent at every portion. Full precision stored; rounding is display-only (`rDisp`).

**Cross-origin + SW.** OFF is cross-origin, so the D6 fetch handler passes it through untouched (no shell/runtime cache involvement). Slice 1 changes no SW logic; only `SHELL_HASH` re-stamps because `index.html`/`app.js` content changed.

**Deferred to later Slice 2/3 (recorded so the split is explicit):** camera/getUserMedia + the `err.name` message matrix + BarcodeDetector/ZXing (Slice 2, on-device attested like the update bar); optional price+store capture and the personal comparison view (Slice 3). Open Prices / nearby prices stay Phase 3 under the deferred-verification rule.

**Amendment — OFF returns HTTP 404 for unknown barcodes (2026-07-16, surfaced on-device).** OFF's product endpoint returns **404** (not `200` + `status:0`) for a barcode absent from its database. The original `fetchOff` threw on *any* non-2xx, so a 404 was caught as a network failure and shown as "offline" — a **not-found product mislabeled as a connectivity error** (found scanning a product not in OFF, while a product that *is* in OFF worked on the same phone/network). Fix: a pure `offStatusKind(status)` (`404 → missing`, `2xx → ok`, else `error`); `fetchOff` returns `{status:0}` for a 404 (→ the `finishLookup` not-found branch) and throws only on genuine failures. The two now read distinctly — not-found: *"Not in OpenFoodFacts — enter the details manually."*; offline: *"Can't reach OpenFoodFacts (are you online?) — retry…"*. **Test-gap lesson:** `OF16` fed `finishLookup` a synthetic `{ok:true, json:{status:0}}` — a shape the live fetch never produces (OFF 404s) — so the unit test passed a branch the real path couldn't reach. `offStatusKind` is now committed-tested so the status→outcome mapping is guarded, not assumed. (This class of gap is exactly what the on-device attestations exist to catch.)

## D15 — Camera scanner: two-tier detection, ZXing sourcing/integrity/caching (2026-07-16)

Phase 2 Slice 2, wiring a camera scanner into the Slice-1 `lookupBarcode` pipeline. Fundamentally an **attested** slice: getUserMedia, permission prompts, live detection, vibrate, and real teardown need a device — so the pure decision logic is committed harness (`CAM` cases) and the live flow is on-device attested (A1–A7, like the update bar / offline-manual fallback).

**Two-tier detection.** Native **`BarcodeDetector`** (format-intersected, readyState-gated rAF loop) when present; else the **ZXing UMD fallback** (100 ms poll / ~6 s timeout). **Verified live 2026-07-16:** `BarcodeDetector` is **Chromium/Android-only — no Safari (iOS/macOS), no Firefox** ([caniuse](https://caniuse.com/mdn-api_barcodedetector)). So **iOS Safari + Firefox have ZXing as their ONLY scanner** — this is why runtime-caching ZXing (below) is mandatory, not optional: without it, offline scanning is broken for every iPhone user.

**ZXing sourcing — single source of truth (verified 2026-07-16).** One constant `ZXING = { version:'0.23.0', url:'https://cdn.jsdelivr.net/npm/@zxing/library@0.23.0/umd/index.min.js', integrity:'sha384-0ASr5PEWAMtTnWsn0PzKmioHVDA4+QqFiJr94io/0DCrGP6E1gRAmbO6O8y5WZW9', global:'ZXing' }` is the **only** place version/url/hash live; the `<script>` tag and `loadZXing()` both read it. Global `ZXing` exposes `BrowserMultiFormatReader` / `DecodeHintType` / `BarcodeFormat` (confirmed). The SRI+CORS `<script>` load succeeded headless (integrity matched the file, `onload` fired).

**Integrity — SRI + CORS, a deliberate D6 amendment.** D6's forward note assumed an **opaque no-cors** ZXing response; **this supersedes that.** We ship third-party *executable* JS to every user, so we integrity-pin it: `crossorigin="anonymous"` + `integrity="sha384-…"`. Rationale ruled: SRI is what keeps the "data never leaves your device" promise honest against a **compromised/substituted CDN file** — a tampered script that could exfiltrate the local store is rejected by the browser before it runs. SRI **requires** CORS; a CORS response is also **non-opaque**, so (unlike D6's opaque plan) the SW caches a **verifiable** response and SRI **re-validates the cached bytes** on every offline load. Opaque caching + SRI are mutually exclusive; CORS gives us both integrity and cacheability.

**Runtime caching — `healthtracker-runtime`, now (D6 extension point).** The SW `fetch` handler gains one branch: a cross-origin GET to the **ZXing CDN host** → cache-first into `healthtracker-runtime` (D6 Amendment A already shields this cache from shell cleanup). Matched by **host** (`cdn.jsdelivr.net`), **not** the exact pinned URL — so a version bump needs **no** SW edit. The **offline gate is extended**: online → `loadZXing()` caches the script → cut network → reload → `loadZXing()` resolves from `healthtracker-runtime` (ZXing global appears offline).

**Drift gate — `tests/check-zxing.sh` (the anti-stale-hash guard).** SRI-pinned + SW-cached means a version bump that forgets the hash is a **silent "scanner won't load"** no headless test catches — the same failure class as the SW-version integer that went stale for six slices (D6 amendment). So, mirroring `check-sw-hash`: `check-zxing.sh` (a) **consistency, offline:** `ZXING.url` contains `ZXING.version`, and `sw.js`'s runtime-cache branch references the CDN host; (b) **hash-vs-file, network:** fetches `ZXING.url`, computes `sha384` base64, **fails loudly** on mismatch with `ZXING.integrity`; `--fix` stamps the correct hash. Wired into `run-data-layer.sh` (consistency always; the network hash-check runs when online and is the authoritative bump-time gate). A stale hash cannot ship silently.

**Preconditions + the literal escape hatch.** `cameraPrecondition` = secure context (https/localhost) **and** `getUserMedia`; the **Scan** button renders **only** when `ok` (insecure/unsupported → the manual barcode field is the whole card). **Error matrix** (`cameraErrorMessage(err.name)`): `NotAllowed/PermissionDenied` → permission-denied; `NotFound/DevicesNotFound/Overconstrained/ConstraintNotSatisfied` → no-camera; `NotReadable/TrackStart` → camera-in-use; `Security` → insecure-page; `TypeError` → browser-can't; default (incl. `Abort`) → generic. **Every message ends "— enter the barcode by hand below," and the manual field is VISIBLE in the same card view (ruled)** — the escape hatch is literal, never one navigation away.

**Capture + detection.** getUserMedia constraints `{ video:{ facingMode:{ ideal:'environment' }, width:{ ideal:1280 } } }` (`ideal`, so no hard-fail without a rear cam). Formats: retail 1D only — `ean_13, ean_8, upc_a, upc_e, code_128, itf` (no 2D/QR); native intersects with `getSupportedFormats()`, ZXing sets the equivalent `POSSIBLE_FORMATS` hints. **Debounce** time-based ~1.5 s (`scanGate`, injected clock). First valid detect → `vibrate` → **auto-stop the camera** (`stopScanner`, idempotent: tracks stopped, rAF/timers cancelled, reader reset) → `guardBarcode` (8–14 digits, reused from Slice 1) → `lookupBarcode` (Slice-1 result UI takes over).

**Committed vs attested.** Committed `CAM` cases: `cameraErrorMessage` matrix, `cameraPrecondition`, `detectorTier`, `intersectFormats`, `scanGate`, `stopScanner` idempotency, detect→guard→lookup handoff. Attested on-device (A1–A7): permission grant → live scan → log; **denied**; **no-camera**; **`NotReadableError` / camera-in-use** (ruled addition — the most likely real error, least likely hit by grant/deny); ZXing fallback **on a real iOS device** (ruled — the genuine ZXing-only path, not a DevTools override); teardown (camera indicator off); vibrate; and ZXing-from-cache offline (also machine-checked by the extended offline gate).

## D16 — Third-party-browser stance: feature-detect + storage.persist(), never fingerprint (2026-07-16)

Prompted by a real on-device event: **DuckDuckGo on iOS granted the camera then errored "permanently" and dropped cached site data** (DDG clears storage / SW aggressively). Third-party iOS browsers (DuckDuckGo, Chrome-iOS, Firefox-iOS) all wrap **WKWebView** with their own permission + data-clearing layers. Two distinct problems, one stance.

**Camera symptom → already handled.** DDG's "granted-then-permanent-error" is just another `getUserMedia` rejection, so the D15 error matrix already **graceful-degrades to the manual field** (A2). No new code. **Ruled: graceful-degrade-to-manual, feature-detection only — never brand/UA-sniffing.** UA-sniffing for `CriOS`/`FxiOS`/`DuckDuckGo` tokens is exactly the **browser fingerprinting the app exists to avoid**, and the token lists drift every release. No browser is ever blocked or feature-gated; every browser gets the app + manual entry + export.

**The scarier problem → data clearing.** "Dropped the cached version" means DDG wiped the SW shell cache **and potentially `localStorage`** — i.e. real logged days/presets/`priceLog` gone. For a **local-only** app this is the worst-case property, so it gets the real mitigation:
- **`navigator.storage.persist()` requested once on boot** — asks the browser to make storage **persistent** (resist eviction). **SILENT and non-blocking by contract:** feature-detected (`navigator.storage && .persist`), fire-and-forget (never `await`ed in the boot path), wrapped so it **never throws**, and **a declined permission prompt never blocks boot** — the app boots and works identically whether persistence is granted, denied, or unsupported. It only *reduces the odds* of eviction; it is not a guarantee.
- **Export is the actual durability guarantee (D5), reinforced.** Against a browser that deliberately clears data, the honest guarantee is not persistence (which a Fire-Button-style clear overrides anyway) but the always-available export. The about line now states plainly: *your export is your backup; some privacy browsers clear site data, so export regularly.* Same truthful-badge philosophy (D1) — never assert durability we don't have.
- **Capability guidance, not a blocklist.** One about/README line: *on iOS, use Safari or Add to Home Screen for reliable offline use and camera scanning.* Guidance the user acts on — not detection, not a gate.

Committed evidence: `requestPersistentStorage()` **never throws** even where `navigator.storage` is absent (the boot-safety contract), asserted in the harness. Its own single-purpose commit (boot + about-line), separate from Slice 3.

## D17 — Strategic positioning: free public good, optionality preserved (2026-07-16)

A governance decision, not an implementation contract — it **binds future rulings** (Phase 4 especially), so it lives here with the rest.

**HealthTracker is a free, MIT, local-only public good.** It is positioned as a **consulting-credibility and lead-generation asset** — a portfolio-grade reference implementation that demonstrates the author's engineering judgment (the honesty rules, truthful badges, gated evidence, local-first sovereignty) — **not a product business.** The architecture already reflects this: no backend, no accounts, no telemetry, export-is-yours, forkable core. Those choices strip the conventional monetization levers and moats *by design*, and that is accepted, because the trust story **is** the asset.

**Monetization is NOT pursued now, but optionality is deliberately preserved.** Preserving the option — and never spending it prematurely — means three standing rules:

- **(a) Copyright ownership stays clear.** Solo-authored, or a **CLA/DCO in place before accepting any outside contribution.** A future dual-license or commercial path is only possible if provenance is unambiguous; a single un-tracked outside patch can foreclose it. This is the cheapest option to keep open and the most expensive to recover, so it is kept open from the start.
- **(b) No server / accounts / telemetry scaffolding is added speculatively.** The trust story is the *current* asset; it must never be compromised for a *hypothetical* future. Building backend hooks "in case we monetize later" spends the asset now for a maybe — forbidden. If a commercial layer is ever built, it is built then, deliberately, not scaffolded ahead.
- **(c) Any future commercial path is drawn LATER, against the finished clean core.** Open-core (a paid optional server tier — sync / backup / hosted vision), B2B white-label customization, or dual-licensing are all **still available later** and lose nothing by the app staying local now. The clean local core is the best possible substrate to draw that line against; drawing it early only constrains the core.

**Phase 4 consequence (binding):** the Phase-4 candidates build **local / bring-your-own** — BYOK in-app AI vision uses the user's own key/compute (no hosted inference), nearby prices read the community Open Prices API (no proprietary aggregation server). The open-core line is **deferred, not pre-drawn.** Any proposal to add a server, an account, telemetry, or a hosted paid service is out of scope for the current roadmap and would require re-opening this decision explicitly.

## D18 — Personal price capture + comparison (2026-07-16)

Phase 2 Slice 3. **Personal price history only** — capture at scan/lookup time + a per-product comparison. **Nearby/community prices (Open Prices) + location stay Phase 3** (deferred-verification rule); Slice 3 is fully offline, no network, no location — entirely committed (no camera/attestation). Closes the Phase-1 deferred gate item "store names escaped."

**`priceLog` is independent of the food log.** A product can be price-checked without being eaten (contract). Price capture triggers on a successful **lookup** (scan or manual barcode), and **recording a price never creates or touches a day/item** — it writes only `priceLog`.

**Inline field, zero-tap skip (ruled).** The optional price field is **inline in the scan result** (price + currency + store), not a post-add modal — log the food and simply never fill it, so *skipping literally costs zero taps, nothing to dismiss*. Shown for a found product **and** for a not-found result whose barcode is valid (you scanned it; `name` defaults to the barcode) — `addPriceEntry` accepts any 8–14-digit barcode regardless of OFF result.

**`addPriceEntry(barcode, name, {price, currency, store, date})`:** barcode validated 8–14 digits; **price required** (non-empty) and coerced + clamped ≥ 0; `store`/`currency` trimmed, kept raw (escaped at render); `date` validated `YYYY-MM-DD`, defaults today. Creates the `priceLog[barcode]` bucket + `name` on first entry. **Duplicates append** (accept, like the food-log D8/3 — a re-recorded price is history). The entry's `currency` is remembered as `settings.currency` (last-used default) — no locale/geo sniffing; empty until the user types one.

**`settings.currency`** — additive settings field, default `''`, coerced by `normalizeSettings`; read with an `|| ''` fallback so pre-D18 blobs need no migration. Added to `defaultSettings` **and** `normalizeSettings` so a fresh state and a restored state agree (v2 round-trip stays exact).

**`priceComparison(priceLog, barcode)` — grouped, currency-safe (ruled, confirmed).** Grouped by **(store, currency)** so a **trend is NEVER computed across mismatched currencies** — £2 vs €3 is meaningless. Each group: latest price (newest `date`), entry count, and a simple trend — latest vs the previous entry **within that same store+currency group** (`up`/`down`/`flat`, or `none` for a single entry). A store shopped in two currencies yields **two segmented rows**, each with its own within-currency trend; there is no cross-currency arrow.

**`storeHistory(priceLog)`** — distinct sorted store names, the `<datalist>` autocomplete source (the user's own history only).

**Restore hardening — `normalizePriceLog` (was passthrough; the audit D12 flagged for its own map).** `priceLog` was previously kept **as-is** in `normalizeState` — an untrusted-paste surface that never got the coerce+escape audit every other boundary has. Now hardened at the restore boundary: **barcode keys validated 8–14 digits** (non-conforming keys dropped — a crafted key is never a real product and is markup waiting to render); per-entry `price` clamped ≥ 0, `store`/`currency`/`name` kept raw (escaped at render), a bad `date` blanked but the **entry kept** (less lossy than dropping the price); unknown-shaped buckets skipped. **A hostile store name survives to storage raw and is escaped only at render** — the gate proves a `<script>`-style store name renders inert in the comparison view (`PR6`), the same audit `normalizeSupplement` got in D12. **Data-loss statement:** a clean v2 export→import round-trips `priceLog` exactly (well-formed values are coercion-identity); only hostile/malformed input is sanitized. **Export includes `priceLog`** (D5 v2 round-trip); **ingest never touches `priceLog`** (D8/6 — that is restore's job).

**Escaping.** Every rendered store / currency / product name / price routes through `esc()` — closing the Phase-1 "store names" item (N/A until price capture existed). Committed `PR` cases; light UX-only attestation (the inline field is ignorable).

## D19 — Governance: correlation-engine destination, timeline substrate, device-integration gate (2026-07-17)

A governance note (binds near-term Phase-4 design), like D17. Recorded before the slices per the working rules.

**Destination.** HealthTracker's endpoint is a personal **correlation engine**: inputs — food, and discrete **interventions** (sauna / cold plunge / yoga / …) — tracked against **biometric outcomes** (HRV, resting HR, glucose, sleep, weight), so a user sees how what they do affects how their body responds. Food is one input class; interventions a second; biometrics the outcome signal. The Phase-4 slate is reframed around this destination.

**Consequence 1 — one generic substrate, many adapters.** Weight readings, logged sauna sessions, and (later) device-fed HRV/glucose are the **same shape**: a *typed, timestamped, dated record* the food log is correlated against. Build the substrate generic enough to hold any of them — **not** a bespoke weight widget plus a separate events feature. One abstraction, many adapters; the source-agnostic ingestion seam is designed now (near-free) rather than retrofitted after adapters harden (expensive).

**Consequence 2 — device biometric integrations are NOT authorized here.** Oura / Apple Health / CGM etc. either cross D17's "nothing leaves your device" line (cloud-OAuth sources) or need a native/hybrid app the current PWA stack can't produce (Apple Health, native-BLE CGM). That is a **separate strategic decision, ruled with D17-level rigor before any integration code** (the standalone device-integration gate, below). The near-term slices stay entirely local and cross no wall.

**Ruled near-term sequence (gated, pre-registered as usual):**
- **Slice G — home-screen update delivery (FIRST).** Gates the *deliverability* of everything built after it — no point shipping features installed users can't receive.
- **Slice T — timeline substrate + its first two local adapters** (manual biometric entry; event logging). Fully local.
- **Slice X — fasting candidates (local, three-state).** Pure logic over meal data.
- **Then STOP** for the device-integration strategic gate before any device work.
- Parked (still valid, lower priority): **A** nearby prices, **D** week analytics, **E** shopping lists. Behind their own stance rulings: **B** BYOK vision, **F** contribute-back.

**Pinned design rulings (bind Slices T and X; T/X are pre-registered only after G is ruled).**

*Timeline substrate (T):*
- **Additive schema** — a new top-level store (like `priceLog`), **not** shoved into the day/items structure. Keyed by date; records carry a **type**, a **timestamp**, a **value** (where applicable), a **`source`** tag, and optional **notes**.
- **Source-agnostic adapter contract** — ingestion defined abstractly: a source produces typed timestamped signals conforming to **one** contract; **manual entry is the zeroth adapter.** A later cloud adapter (Oura) or native layer (Apple Health) must feed the **same** store via the **same** contract with no substrate rebuild. Designing the seam now is near-free; retrofitting after adapters are hardwired is expensive.
- **Events are timeline records, NOT food items** — a sauna/cold-plunge/yoga entry has no macros, barcode, or portion and must **not** be stored as a zero-calorie item in the food log (that repeats the water double-count error already ruled against). Events share only **timestamp + day** with meals — which is exactly what lets them overlay on one timeline.
- **Overlay view** — the substrate earns its keep by being **visible against the food/fasting timeline**: a day (later a week) shows food, events, and biometric readings on one aligned timeline. Manual data alone is useful ("cold plunge 7am" + "weight 82.1 kg" → patterns); device feeds are later upgrades, not prerequisites.
- **Boundary discipline** — every value coerced/clamped at entry **and** at the restore boundary (new store → a new `normalize…` function, like `normalizePriceLog`); every rendered field escaped; export includes the store with **exact round-trip**; **ingest never touches it** (restore's job).

*Event types (T) — FORK ruled:* **fixed core enum + generic `other` with a free-text label.** Clean, comparable categories for the interventions people actually correlate (so "does yoga help" is answerable, not scattered across `yoga`/`Yoga`/`vinyasa`), with an escape hatch; a popular `other` can be promoted into the enum later. Mirrors meals (fixed enum) vs notes (free text). Core set (confirm/adjust at T pre-registration): **`sauna, cold_plunge, yoga, workout, walk, meditation, other`**.

*Fasting candidates (X) — THREE-STATE ruled:* a logging gap generates a fasting **candidate**, never an asserted fact; the user resolves each to **fasted** (confirmed), **ate-but-didn't-log** (denied — the gap was missing data), or **pending** (unresolved). **Only confirmed fasts enter any analysis or correlation.** Pending **never** silently counts as fasted (would fill the fasting data with forgot-to-log noise and poison every downstream correlation) or as eaten (would lose real fasts) — the **"absence ≠ zero" principle at the behavioral level** (a logging gap is not evidence of fasting, as a missing micro is not evidence of zero intake). **Design for later corroboration:** structure the candidate/resolution model so a future biometric signal (a real fast's glucose/HRV signature) can act as a **fourth, automatic resolver** of pending candidates — don't build that now, but don't build a two-state model that would have to be torn up to add it.

**Separate — device-integration strategic gate (referenced; ruled before any integration code).** The cloud-OAuth-vs-on-device-only architecture fork (cloud sources like Oura keep the app a PWA; on-device sources like Apple Health force native/hybrid), a per-source stance + architecture matrix, and a conscious re-confirmation of whether D17's free/public-good posture survives a materially more valuable correlation-engine product. Kept standalone (same reason monetization became D17 rather than tangling into a feature slice), **not** part of the near-term slate.

## D20 — Timeline substrate + its first two local adapters (Phase-4 Slice T, 2026-07-18)

The load-bearing generic store from D19 (Consequence 1): a **source-agnostic timeline** the food log is correlated against. Slice T builds the substrate + its **manual biometric** and **event** adapters + a **day-level overlay** — fully local, entirely committed. No fasting (Slice X), no week overlay (later), no device adapters (behind the strategic gate).

**Schema v3 (firmly ruled; additive-no-bump rejected).** Without the bump, an older app (still v2) importing a v3 export would keep `version:2`, not recognize `timeline`, and **silently drop it on re-export** — cross-version biometric/event data loss with no warning, the worst bug possible with real distributed users on mismatched versions. The bump makes the older app **reject** the v3 blob (forward-guard) instead of eating the data. Mechanics: blob carries `version:3`; an add-only in-place **v2→v3 migration** adds empty `timeline` (days/settings/priceLog/current byte-preserved), **chained after v1→v2** (`migrateToLatest`: v1→v2→v3; v2→v3; v3 as-is); the retained **pre-migration snapshot (D7)** captures the original blob before any step; **forward-guard now rejects `version > 3`** (boot protects a `>3` blob read-only, restore/ingest reject it). Round-trip: **v3 export→import is exact** (incl. `timeline`); a v2 import is a one-way **upgrade** to v3 (gains empty `timeline`), not identity.

**The store + the one contract every adapter satisfies.**
- `timeline: { "YYYY-MM-DD": [ record, … ] }` — a **new top-level store**, keyed by date, NOT inside `days`/`items`.
- `record = { time:"HH:MM", kind, type, value?, unit, source, notes? }`.
- **`kind` ∈ `biometric` | `event` (ruled) — the input/outcome distinction the correlation engine is built on.** Structurally: `event` = a discrete timed intervention (value = optional duration); `biometric` = a numeric reading. The two align with input/outcome for the canonical cases (sauna=input event, HRV=outcome reading); a reading that is behaviorally an *input* (e.g. `steps`) is still stored as `biometric` (a reading) — the **correlation layer, not the `kind` tag, assigns the final input/outcome role**. `kind` is not collapsed into `type`: folding them would lose the distinction.
- **`type`** — canonical, from the `SIGNAL_SPEC` registry (below), 1:1 `type → label → unit`, no cross-wiring (like `MICRO_SPEC`). Unknown types are **tolerated + preserved** on restore (shown raw), like unknown micros.
- **`value`** coerced + clamped ≥ 0 (biometric reading or event duration; optional for an event with no duration). **`source`** is a **string**, `manual` forced by the manual adapter, **extensible + tolerated** (future `oura`/`apple_health`) — that is what makes the store source-agnostic. **`notes`** optional free text; for the `event` type **`other`**, `notes` carries its **free-text label** (D19's "generic `other` with a free-text label"). `date` is the map key, not stored in the record.

**The adapter seam (designed now, near-free; retrofitting later is expensive — D19).** `normalizeSignal(raw)` → a canonical record; `addSignal(raw)` files it under `timeline[date]` (date validated `YYYY-MM-DD`, default today). **Manual entry is the zeroth adapter.** A future cloud/native adapter produces the **same raw signal shape** → the **same** `addSignal` → the **same** store, with **no substrate rebuild**.

**Events are timeline records, NOT food items (D19).** An event/biometric writes **only** `timeline` — never a `day.item` — so `dayTotals` (food, `items`-only) is untouched: **no zero-calorie double-count** (the water error stays dead), by construction.

**`SIGNAL_SPEC` registry (ruled set + the two zero-hardware additions).** One table drives the forms, labels, units, and sane-range warnings (like `MICRO_SPEC`); generation and read-back key off the same `type`, so no cross-wiring.
- **biometrics (readings):** `weight` (kg), `resting_hr` (bpm), `hrv` (ms), `glucose` (mg/dL), `bp_systolic` (mmHg), `bp_diastolic` (mmHg), `sleep_hours` (h), **`steps` (count — most universally available, no device)**, **`mood` (/5 — the one outcome loggable with zero hardware)**.
- **events (duration in min):** `sauna, cold_plunge, yoga, workout, walk, meditation, other`.
- Sane-range **soft, non-blocking** warnings per entry (e.g. mood > 5, sleep > 24 h, weight > 500) — catch unit/typo errors, never reject (D9 discipline).

**Units — per-record + remembered default (ruled; same as `settings.currency`).** Each record stores its own `unit`; the entry form defaults to the last-used unit per type (`settings.signalUnits[type]`, remembered on add) or the `SIGNAL_SPEC` default. Fixed canonical units were rejected — kg/lb and mg/dL vs mmol/L are hard i18n splits that would kill daily logging for half the users; no locale sniffing. **Forward pin (ruled):** any future **trend or correlation must normalize a type's records to a canonical unit before comparing** — a half-kg/half-lb series cannot be trended raw (the same catch as the price slice's cross-currency trend). Slice T has no trend yet; this binds when one is built.

**Overlay (day-level; week later).** A day renders food (`items`) + events + biometrics **merged and time-sorted** on one aligned timeline (`timelineForDay(date)`) — even manual-only data ("cold plunge 07:00" + "weight 82.1 kg") shows patterns. Week overlay parks with week-analytics; device feeds are later upgrades, not prerequisites.

**Boundary discipline.** `normalizeTimeline(o)` at the restore boundary (like `normalizePriceLog`): date keys validated (bad dropped), `value` clamped ≥ 0, `type`/`notes`/`source`/`unit` kept raw (escaped at render), unknown keys tolerated. Export includes `timeline` (exact round-trip); **ingest never touches `timeline`** (D8/6 — restore's job). Every rendered field through `esc()`. `APP_VERSION → 0.4.0` with a `VERSION_LOG` line (gated by `check-version`). Committed `TL` cases; no attestation (fully local).

### D20 addendum — the full v0.4.0 substrate (2026-07-18, ruled before build)

All of the below ships in **one** Slice-T build as **v0.4.0** (not dribbled across point releases — adding a signal type after the forms and gates exist is more churn than up front). Extends the rulings above.

**`kind` becomes three: `biometric | event | medication`.** Medication is neither a reading nor a discrete intervention — it is a **named substance with a dose**, and forcing it into either contract would bury the structured detail correlation needs ("does my morning metformin move my glucose" requires the drug as a real field, not notes). So it is a **first-class third kind** with its own extended record.

**Added `SIGNAL_SPEC` biometrics (in now):**
- **`breath_ketones`** — per-record unit (`ppm` for breath-acetone meters like Biosense, or `mmol/L`); the per-record unit model is exactly why this ambiguity is fine. **Forward flag (fasting, Slice X):** breath ketones directly confirm a fast, so this signal is one of the **future auto-resolvers of a pending fasting candidate** — in the registry now means the fasting slice references it with no retrofit.
- **`steps`** (`count`) — most universally available signal, real correlation input/outcome, zero hardware.
- **`mood`** and **`energy`** (`/5` each) — the outcomes loggable with no device at all; both ship (one spec entry apiece).

**Added `SIGNAL_SPEC` events (in now) — all plain events (timestamp + optional value + notes, no new fields):**
- **`alcohol`** — a correlation **input** ("does drinking move my sleep HRV / next-day glucose / weight"), so it belongs with events, **not** the food-macro system; optional count (e.g. "3 drinks", unit `drinks`) + notes; never routed through food macros.
- **`red_light`** (RLT) and **`hbot`** (hyperbaric oxygen) — plain events with optional duration (min) + notes; **any parameters (RLT wavelength, HBOT pressure) go in `notes` for now**, promotable to structured fields later only if correlation needs them.

**Blood pressure — paired entry (ruled).** `bp_systolic` and `bp_diastolic` stay two records, but the **entry is one grouped action** at one timestamp — a single "120 / 80" field group, never two disconnected logs the user can mismatch. `logBP(sys, dia, time)` writes both records at the same `time`, correctly separated, no cross-wiring (gated).

**Medication record (maximum detail; quick path stays quick).** A `medication`-kind record extends the base with a structured field set — most **optional**, so name + optional dose is enough to log, but the schema supports full clinical detail:
- **`name`** (required, free text, escaped).
- **`dose`** (number, optional, clamped ≥ 0) + **`dose_unit`** (per-record with remembered default; closed enum: `mg, mcg, g, mL, IU, tablet, capsule, drop, puff, unit`).
- **`form`** (optional closed enum: `tablet, capsule, liquid, injection, topical, inhaler, patch, drops, other`).
- **`route`** (optional closed enum: `oral, sublingual, topical, inhaled, injected, nasal, other`).
- **`scheduled`** (optional bool — standing/recurring vs one-off; **full scheduling/reminders/recurrence is a LATER feature — this flag only records intent, do not build scheduling now**).
- **`prescriber`** / **`reason`** (optional free text, escaped — for later clinical export); **`notes`** (optional, escaped); `time` from the base record.

Medication design: **no `MEDICATION_SPEC` registry** (names are open-ended, unlike the closed biometric/event type sets) — `name` is free text; but `dose_unit`/`form`/`route` **are** closed enums driving their form controls, so the same **no-cross-wiring** discipline (MICRO_SPEC/M1) applies to those three (validated, tolerant fallback to unset). Free text (`name`/`prescriber`/`reason`/`notes`) escaped at render, coerced at entry **and** restore; `dose` clamped ≥ 0. Because `name`+`dose` are structured fields (not notes), a future correlation view can group by medication and align doses against outcomes — the reason for the first-class kind.

**Deferred intent — contraindication / interaction capability (recorded, intentionally undetermined).** The reason medication captures *maximum structured detail now* (name/dose/dose_unit/form/route as real fields, not notes) is to be the **foundation** for a future capability that could surface **drug–drug / drug–supplement contraindications or interactions** — but **its exact form is deliberately undecided**, and building it is **not** in this slice or the near-term slate. If it is ever pursued it is a **separate strategic decision** (D17-level), because it crosses into **medical-advice territory** and would require explicit guardrails (not a diagnosis; "consult a professional"; sourcing/liability posture; almost certainly a third-party interaction dataset, which touches the device/data-egress and D17 postures). Recorded here so the structured schema's *purpose* is not lost and so the feature is understood as **deferred and intentionally undetermined**, never an implied commitment.

**Deploy posture.** Weight + full biometric set (incl. breath ketones, steps, mood/energy, BP-paired), events (incl. alcohol, red_light, hbot), and the medication kind ship as **one v0.4.0** — one deploy, one "Updated to v0.4.0" changelog. Also the **first clean force-and-notify test:** a device already on 0.3.0 auto-updates on reopen with zero taps + the notice.

**Explicitly NOT in this slice (deferred, do not build):** medication scheduling/reminders/recurrence (the `scheduled` flag marks intent only); correlation/analysis views across kinds (Slice X+); week-level overlay (with week-analytics); any device adapter (behind the strategic gate).

**Gate additions (extend `TL`).** Medication normalize (name required; dose clamped; `dose_unit`/`form`/`route` enum-validated with fallback; free text escaped; quick path name-only valid; full-detail round-trip exact) + the three medication enums no-cross-wiring (like M1). BP pairing (one action → both records, one timestamp, separated, no cross-wiring). Alcohol event (optional count + notes; no food item; day totals unmoved). `breath_ketones`/`steps`/`mood`/`energy`/`red_light`/`hbot` 1:1 `type→unit` (extend TL4). Restore/round-trip/escaping (TL7/TL9) exercise a **medication record with hostile `name`/`prescriber`/`notes`**.

## D21 — Governance: the four-layer product model — TRACK → MIRROR → NUDGE → ADVISE (2026-07-18)

A **governance entry, binding on future rulings** — the **third pillar** alongside **D17** (positioning: free public good, optionality preserved) and the **guidance/contraindication gate** (the D20-addendum deferred-intent note + the D19 device-integration gate). **This is NOT a build authorization.** It is the product philosophy that **sequences the roadmap** and tells every future slice **which layer it serves**, so the layers stay in their safety order and the app earns its way toward helping.

**Guiding principle.** The app exists to help the builder's friends and family (and users like them) improve their health, resting on ~10 years of longevity research: **nothing changes without tracking and feedback.** The core value — the honest tracking-and-feedback loop — is already delivered by the built foundation; everything beyond amplifies that loop and **none of it is a prerequisite** for the app to work. Intended arc: **start as a food tracker → gather the person's real diet and habits → then gradually introduce better habits.** You cannot prescribe a change before you know the baseline, and a person accepts a change they partly arrived at themselves. The tracking period **earns the right to suggest** — statistically (a baseline to compare against) and psychologically (having seen their own patterns, a suggestion feels like their own insight surfacing, not nagging).

**The four layers — increasing value AND increasing risk; build in order:**

- **Layer 1 — TRACK (built).** The honest log: food, biometrics, events, medications on one timeline; goals; fasting candidates. Delivers the *tracking* half immediately. **Design imperative: adherence.** The intervention that works is the one people actually do; an abandoned tracker changes nothing. **Ease-of-logging is the mechanism of action, not polish** — a first-class, ongoing concern; every point of logging friction is a point where a user quietly stops and gets zero benefit. **Ruthless ease-of-logging outranks almost everything.**
- **Layer 2 — MIRROR (safe; build next).** Clear presentation of the person's OWN trends (weight over 90 days, avg HRV on cold-plunge days vs not, fasting streaks, glucose patterns) — the *feedback* half, at **zero guidance risk**: a mirror with a memory, not advice. No "you should." For the longevity-literate user, a clear mirror is often all the feedback needed. It is also the **precondition for Layer 3** (the person must SEE their baseline before a nudge lands). This is the **week-analytics work, reframed as the feedback layer** (D19's parked item **D**).
- **Layer 3 — NUDGE (safe; the "gradually introduce better habits" layer).** Progressive, paced introduction of **established, uncontroversial** good habits, **gated on the person having tracked enough to have a baseline** (e.g. after weeks of logging: "want to try adding a vegetable at lunch?" / "a short walk after dinner?"). This is where the builder's longevity knowledge **encodes most safely** — a curated, graduated **curriculum** of already-trusted practices, released as the person shows readiness. Same low-risk profile as sourced facts, gentler delivery. **Distinct from Layer 4:** a nudge toward established good practice is **not** a personalized claim about this person's data — the moment a "nudge" is derived from the person's own correlations it **has become Layer 4** and inherits Layer 4's risk and guardrails. Paced and progressive, never a firehose; at moments of demonstrated readiness, not day one.
- **Layer 4 — ADVISE (deferred, guarded).** Personalized correlation guidance (Feature B) + sourced interaction/contraindication flagging (Feature A). Highest value, highest risk. Governed **entirely by the separate guidance/contraindication gate**: two-feature split, sourced-not-guessed interactions, observational-not-prescriptive correlations, consent-gated, built only when real data and guardrails exist. **NOT required** for the app to fulfill its purpose.

**What the model buys.** **Layers 1–3 fully deliver the stated goal without ever crossing the guidance/consent line** — Track + Mirror + Nudge = start as a food tracker, gather habits, gradually introduce better ones, all honest and low-risk, none needing AI, a pharmacological database, or a consent tier. Layer 4 is **optional amplification, not a prerequisite.** The builder can genuinely help friends and family — actually change habits — with the three safe layers alone.

**Roadmap consequence (sequencing, not authorization):**
- **Now:** finish **Layer-1 adherence** (easy logging — the health-focus chips / quick-log). Everything downstream depends on the person actually logging.
- **Next:** **Layer 2** (mirror / clear self-trends) — delivers feedback safely and creates the baseline visibility Layer 3 needs.
- **Then:** **Layer 3** (nudge) — paced introduction of established good habits, unlocked by a tracked baseline; the heart of the "better habits" intent.
- **Deferred/guarded:** **Layer 4** (advise), per the guidance/contraindication gate.

*(Sequencing note: the near-term D19 slices still stand — Slice X fasting is Layer-1/2 substrate; the device-integration gate is unchanged. This model overlays D19, telling each future slice which layer it serves; it does not reorder committed slices.)*

**Audience note.** Built for a specific, known, motivated audience: people who track the way the builder does (fasting, cold plunge, sauna, HBOT, red light, breath ketones, HRV, glucose — the aggressive-optimization end of longevity). Building for a specific, motivated user is a **strength** — it licenses sharp, opinionated choices over generic ones. Design deliberately for that user; **do not dilute** the tool trying to also serve someone who'd find a breath-ketone field baffling. The public/open posture (**D17**) still holds — but the primary users are friends, family, and their kind, and their benefit comes from **the loop working well and feeling good to use**, not from the trust posture alone.

## D22 — Fasting candidates: three-state, derived detection / persisted resolution (Phase-4 Slice X, 2026-07-19)

Realizes D19's fasting pin under D21 (a Layer-1 substrate; the *feedback* it enables is Layer 2). Slice X builds detection + three-state resolution + passive surfacing + round-trip, plus a universal **undo** logging affordance (below). **Deferred:** fasting analytics/streaks/trends (Layer 2 Mirror); the biometric auto-resolver (seam only); any fasting nudge (Layer 3); fast↔biometric correlation (Layer 4).

**Model — derived candidates, persisted resolutions (ruled).** Candidates are **derived** from food-item timestamps on every render (no stored candidate list); only human **resolutions** persist. This shape was chosen because: no migration for candidates, the detector can improve freely without rewriting data, candidates and data cannot desynchronize, and **only human judgment is stored**.

**Three-state — absence ≠ zero at the behavioral level (Pin 1, non-negotiable).** A gap ≥ threshold is a **candidate**, resolved to `fasted` (confirmed) | `ate_didnt_log` (denied) | `pending` (unresolved). **Pending never counts** — in this model **pending = the ABSENCE of a resolution record**, so it cannot silently enter any count by construction. `confirmedFasts()` (the sole surface any future average/analysis/correlation reads) returns **only `fasted`**; denied and pending are excluded. A logging gap is a question, not a conclusion.

**Gap definition (Forks 1a–1c).** A candidate is the span between two consecutive **fast-breaking food events**, computed **across days** (fasting is cross-day: dinner → next-day lunch spans two date keys), when the span ≥ `settings.fasting.minHours` (default **16h**, configurable). Overnight needs no special rule — the threshold handles it (11h < 16h → nothing; 18h ≥ 16h → candidate).
- **`kcal > 0` breaks a fast (Fork 1b) — a deliberate PROTOCOL STANCE, not a neutral fact.** 0-kcal black coffee / electrolytes do **not** break a fast; strict water-fasters would disagree. This is our audience's default (D21's audience note licenses the opinionated choice), recorded here as a *stance* so it reads as a modeling decision, not physiology.
- **Auto-supplement exemption (Fork 1b-ii).** The standing daily supplement (`_auto` item, ~5 kcal) must **not** break a fast, or supplement-enabled users could never register one. Mechanism: a food item breaks a fast iff **`kcal > 0` AND not `_auto`** — exempt the flagged auto item specifically (precise and self-documenting, chosen over a magic `kcal > 5` threshold). Gated (an auto-supplement mid-gap doesn't break the candidate).

**Bounded, day-status-independent (Fork 2).** A candidate needs food on **both ends** (a closed gap); the trailing open gap (last meal → now) is a *current fast in progress* — quiet info, **not** a resolvable candidate. Detection is **independent of day-close** (fasting is about food timestamps, not the complete-days discipline).

**Derived over all history, surfaced passively (Fork 3, Pin 3 — mirror never nag).** Candidates being derived, all history is covered with no migration; they surface on the day the fast **ended** (where eating resumed), in the **timeline overlay**, as quiet inline rows with inline resolve — never a badge, count, notification, or guilt mechanic. Day-nav exposes older candidates; today's are the default view.

**No upper cap (Fork 4).** Gaps are **not** capped: the three-state discipline is already the noise defense (a false candidate costs one glance + one tap and never touched analysis while pending), whereas a cap would systematically **delete the most significant events** — the audience's real 48–72h extended fasts. Very-long gaps (> 48h) are **visually marked**, not dropped.

**Representation + interactions (Fork 5).** New top-level store **`fastLog`** (parallels `priceLog`/`timeline`): `{ "<start-ISO>": { start, end, hours, state, resolved_by, resolved_at, notes? } }`, keyed by the gap-start datetime (`YYYY-MM-DDTHH:MM`, local). **Only resolved states are stored** (`fasted` | `ate_didnt_log`); **pending = absence** (resolve-to-pending / undo deletes the record). **Identity is tolerance-matched** (±15 min on start **and** end) so a minor boundary-meal edit doesn't orphan a resolution; an **orphaned resolution is kept INERT** (retained in state, round-trips, but not shown or counted) rather than deleted — an accidental edit must not destroy a human confirmation. Confirmed fasts feed a **separate** fasting metric (deferred to Layer 2), **never** the macro averages (which stay complete-days-only, **untouched** — gated byte-identical with vs. without fasting data). Orthogonal to day-close.

**Fourth-resolver seam (Pin 2).** `resolved_by ∈ user` now; a future biometric auto-resolver (breath_ketones already in `SIGNAL_SPEC`, D20) writes `resolved_by: 'biometric'` to the **same** store; the retained `start`/`end` span is exactly what lets a future signal **overlap-match** a pending candidate. `'biometric'` is **tolerated on restore now**; the resolver is not built.

**Config + off-switch (Forks 1a, 7).** `settings.fasting = { enabled: true, minHours: 16 }`. **Always-on-but-silent** (only appears on real ≥ threshold gaps, so a non-faster never sees it); `minHours` is the volume knob; an explicit **off-switch** is included (nearly free).

### D22 amendment — universal undo on logging (the protection is UNDO, not confirmation)

The failure mode is mis-entry (wrong chip, fat-fingered value, an ingest that ended a fast the user was mid-way through). The protection is **undo, not confirmation**.

1. **Logging stays instant** — zero intermediate steps on the happy path (unchanged).
2. **Every log action** (chip/signal, medication, preset, manual, scan, ingest item) surfaces a brief **passive toast with an Undo affordance** for a short window (~6–8s): *"Logged Weight 82.1 · Undo"*. Undo **deletes the just-created record — nothing else.**
3. **Fast context.** When a food log **ends an open fast**, the same toast carries it: *"Logged — this ended a 15h fast · Undo"*. Because candidates are **derived**, undo simply removes the record and the gap **recomputes** to its pre-log state — **no special-case repair logic** (the whole reason the derived model earns its keep here).
4. **No confirmation dialogs on logging, ever (prohibition extended).** A confirm step habituates into reflexive-yes within days, then taxes every honest log forever while protecting nothing. Undo protects **exactly where the failure is, at zero cost to the happy path.** After the undo window, the record is still removable the normal way (items/records were always deletable).

**Scope:** a **universal** logging affordance, not fasting-specific — mis-entry corrupts totals/averages/fasts equally, so undo covers **every log path**. It ships with Slice X because the fast-context note motivated it. Implementation seam: each log handler, after its instant add, registers `offerUndo(label, undoFn)` where `undoFn` removes the created record **by reference** (BP's paired entry removes both); the pure data-layer add functions stay untouched and testable — undo wiring lives in the UI handlers.

**Schema v4 (same cross-version-safety reasoning as v3/D20).** Adding top-level `fastLog` means an older app (v3) importing a v4 export would not recognize `fastLog` and would **silently drop it on re-export** — losing persisted human resolutions, the one thing the model treats as precious. So blob carries `version: 4`; an add-only **v3→v4 migration** adds empty `fastLog` (days/settings/priceLog/timeline byte-preserved), chained after v1→v2→v3 (`migrateToLatest`: …→v4; v4 as-is); the **forward-guard now rejects `> 4`** (boot protects a `>4` blob read-only; restore/ingest reject); pre-migration snapshot (D7) retained; **v4 export→import exact incl. `fastLog`**; `ingest` never touches `fastLog` (restore's job). `settings.fasting` rides along in v4 (config; defaults reapply if absent). `APP_VERSION → 0.5.0` (a new capability, not polish).

**Explicitly NOT in this slice:** fasting analytics/streaks/trends (Layer 2 Mirror); the biometric auto-resolver (seam only); any fasting nudge (Layer 3); fast↔biometric correlation (Layer 4).

## D23 — Mirror (Layer 2): descriptive self-trends, the feedback half (Phase-4, 2026-07-19)

Realizes **D21 Layer 2 (MIRROR)**: the *feedback* half of "nothing changes without tracking and feedback," making the person's **baseline visible** — the precondition for Layer 3. **Read-only** over existing local stores (food, timeline, fastLog): **no schema change, no migration.** `APP_VERSION → 0.6.0`.

**The Mirror/Advise line — WHO INITIATES THE PAIRING (governing distinction; binds all of Layer 2).** A mirror shows the person their own data; it never asserts a relationship or prescribes. The line between Mirror (L2) and Advise (L4) runs through **who initiates a pairing of two variables**:
- **User-selected juxtaposition of the person's own series = still a mirror** — they are looking in the mirror from an angle they chose.
- **App-initiated pairing = a hypothesis = Layer 4.** The moment the app pairs variables on its own ("we noticed X relates to Y"), it has formed a hypothesis about the person — Advise (Feature B), guarded + consent-gated.
Same principle as D22's absence-≠-zero and the honesty rule: **the app presents; the person concludes.**

**No-evaluative-language rule (ratified).** The Mirror renders **factual summaries only** — latest, min–max, average, delta, count, over an explicit window. **No** evaluative/prescriptive vocabulary ("should," "improving," "good/bad," "on track," "recommend," "try…"). Arithmetic on the person's data is not interpretation; a value-judgment is. **Grep-able safety invariant (gated):** the rendered Mirror contains **none** of the banned evaluative/prescriptive terms and (v1) **no asserted cross-variable relationship** — a structural assertion, like the other honesty gates.

**v1 = single-variable trends (Tier 1).** Biometric trends (one inline-SVG sparkline per *logged* signal type + a factual summary), fasting history (streak / count / avg / longest), macro trend (daily kcal, complete-days-only). **Tier 2 — user-selected juxtaposition of two of the person's own series — is a fast-follow**, and per the line above is **user-selected only, never annotated, never app-suggested**: the app draws the two series the user picked and says nothing about their relationship.

**Unit normalization (the D20/D22 pin, realized).** A trend cannot mix units. Each type's series is normalized to its current display unit (`settings.signalUnits[type]` or the `SIGNAL_SPEC` default) via a **finite per-type conversion table** (weight kg↔lb, glucose mg/dL↔mmol/L). Units that are **not** inter-convertible (breath-ketones **ppm vs mmol/L measure different things**) are **not** force-converted — records in the non-matching unit are **excluded** from that series with an honest coverage note (absence ≠ fabrication). This is the pin's "normalize a type's records to a canonical unit before comparing."

**Completeness asymmetry, labeled (Fork E).** Two data classes, two deliberately different rules: **macro trends are complete-days-only** (D10 — a half-logged day isn't a real daily total); **biometric trends show every reading** (point-in-time, not day-totals). The macro trend is **labeled "complete days only"** so the asymmetry reads as design, not inconsistency.

**Fasting streak (new pin).** The streak is **consecutive days with a CONFIRMED fast** (a fast ending that day; confirmed-only per D22 — pending never counts). Where **pending** candidates fall in the streak window, the view says **"N unresolved — resolve to update"** rather than silently showing a possibly-broken streak — an honest stat that also **teaches the resolution loop** (a pending resolved to fasted may extend the streak; the app won't inflate it, but won't hide that it could change).

**Charting / windows / min-data / placement.** Hand-rolled **inline SVG** sparklines (theme-aware via CSS vars, no deps — honors the no-build constraint). Window **30 / 90 / all** (calendar-window discipline, D10; non-persisted UI state in v1). A trend needs **≥ a few points**; below that an honest "keep logging" empty state, never a 2-point "trend." Placement: a **Trends group below the day/timeline** — reflection is not the primary daily act; Layer-1 adherence keeps the fold.

**Deferred (flagged):** Tier-2 juxtaposition (fast-follow, user-selected only); **signal-type goals + the dormant chip-float awakening** (its own slice — goal-vs-trend display has distinct latest-reading/direction semantics); week-over-week deltas; chart export.

**Sequencing (for the record).** The **device-integration strategic gate (D19) is DEFERRED, not skipped** — still owed before any integration work. Mirror needs **no** ruling from it: read-only, fully local, no data egress.

## D24 — Signal goals: biometric targets + the chip-float awakened (Phase-4, 2026-07-20)

Makes biometric goals settable (weight ≤ 80 kg, HRV ≥ 60, glucose ≤ 100), **waking the wired-but-dormant chip-float** (D21): a signal type with a goal floats to the unscrolled front of the quick-log strip. Extends the goals + Mirror machinery; **no schema change.** `APP_VERSION → 0.6.1`.

**`settings.goals` is now a MIXED NAMESPACE — mandatory-filter contract (binds every consumer).** The map holds two semantically different goal kinds, discriminated by key:
- **nutrient goals** — `{value, direction}`, keyed by a food nutrient (`kcal, protein_g, fat_g, carb_g, fiber_g`); evaluated against a **daily SUM** (`dayTotals`); shown on the food ring/strip.
- **signal goals** — `{value, direction, unit}`, keyed by a **signal type** (`weight, hrv, glucose, bp_systolic, …`); evaluated against the **LATEST reading**; shown on the Mirror trend + the chip-float. **Never on the food ring.**

The two key namespaces are **closed and disjoint** (no nutrient/signal-type collision). **Contract (mandatory — written for the next consumer's author, six months out): any code reading `settings.goals` MUST filter to the kind it means.** The food ring/strip (`renderGoalsHTML`) filters to nutrient keys; a signal goal rendered there would be `dayTotals[weight]` = 0 → food-summed nonsense (the D21 "wrong-schema" trap). Gated **byte-identically** (SG1): the food ring's rendered output is **identical with vs. without a signal goal present** — the filter proven by output equality, not merely asserted (the FX3 pattern). Chosen over a separate `settings.signalGoals` store because it **cashes in D21's forward-ready float** (already reads `settings.goals`) at **zero churn** — no new store, no float rewire, no existing-fixture edits — but the mixed namespace is a real hazard, recorded here so it isn't rediscovered as a bug.

**Fully neutral goal display (ruled — an M7 refinement, not a loophole).** The Mirror shows a signal goal as **factual text only** — "target ≤ 80 kg · latest 78" — plus a **neutral dashed reference line**. **No met/unmet color, ever.** A green "under your ceiling" line is the evaluative word "good" **re-encoded past the text grep** — an honesty invariant satisfiable by changing the encoding is not an invariant. It is also **more correct**: the direction-of-good is **personal** for several signals (mood, weight mid-cut, HRV) — the user declared the target, the user judges the gap. If lived use later argues for a cue, that is a **deliberate, recorded M7 amendment**, never a default.

**Latest-reading basis (deliberately simple).** A signal goal is evaluated against the most recent reading, direction-aware (floor short-when-under, ceiling over-when-above) — reusing `goalProgress` arithmetic but rendering **no** evaluative status word. A **rolling-average basis** for noisy signals (mood, HRV) is **deferred, not rejected**.

**Unit (the pin, again).** A signal goal stores its unit (the signal's current display unit at set-time); the Mirror **normalizes the goal to the series unit** before drawing the line (kg goal ↔ lb series). A goal whose unit is **not inter-convertible** with the series (a ppm ketone goal against an mmol/L series) **surfaces the mismatch honestly and is not drawn** — the same never-force-convert rule as the trend (D23).

**Set UX + scope.** Set via the existing Goals form (a "Biometrics" optgroup; `setGoalFromForm` routes signal types, storing the unit). **Biometrics only** — weight, resting HR, HRV, glucose, breath ketones, BP systolic + diastolic (separately), sleep, steps, mood, energy. **Events excluded** (a "sauna goal" is a frequency target — different shape, deferred).

## D25 — Nudge (Layer 3): paced, established good habits; curriculum-as-content (Phase-4, 2026-07-20)

Realizes **D21 Layer 3 (NUDGE)** — the "gradually introduce better habits" layer, unlocked once the tracking period has earned the right. Delivery machinery is code; the **curriculum is the builder's content**. `APP_VERSION → 0.7.0`; **no schema change** (state lives in `settings.nudges`).

**Established-practice-only, engagement-gated (Pin 1, load-bearing).** A nudge suggests a **generally-accepted** habit ("many people find a short walk after dinner an easy add"). It **never** derives from the person's data *content* — the instant it does ("your sodium looks high, cut salt"), it is **Layer 4** and inherits its guardrails, prohibited here. **Readiness gates on ENGAGEMENT milestones** (distinct days logged), **never on what the readings say.** Readiness = food/timeline logged on **≥ 7 distinct calendar days** AND **≥ 7 days elapsed since the first log** (auto-supplement items don't count — that's not the user tracking). Both are counts, never content.

**Mirror-never-nag delivery (Pin 2/3).** A quiet card near the reflective area (Trends), **offered not pushed** — no notifications, badges, guilt, or repeat-pestering. **One habit at a time**, offered in curriculum order, with a **real interval between offers** (5 days after a resolution; snooze re-eligible after 7). Decline is **one tap, permanent, never argued**. A **global off switch** (`settings.nudges.enabled`) and, per Fork E, a **"browse all habits" view (v1)** so the user has their **own path back** — decline-permanent is only honest if the user can revisit the full list themselves; the app never re-pushes.

**Accept = current focus WITH a factual adherence line (Fork B, OVERRIDDEN — the wear-indicator, never the scold).**
- **Derived-only from voluntary timeline logging.** A curriculum entry may carry an optional **`linkedType`** (`walk_after_dinner → walk`); the focus line counts that type's timeline records **since acceptance**. **No check-in prompts, no separate compliance capture, ever.** An **unlinked** habit stays a **pure self-assessed focus** — no line. **No content inference** (detecting "veg at lunch" from food names is data-content reading = Layer-4 creep, **prohibited**).
- **Language: "logged," never "done."** "walk logged 4 times in the last 7 days · last: Tue." **Counts and dates only** — no percentages, no streaks, no color (Fork-G neutrality). **Absence of a log is never rendered as a lapse** (0 → a neutral "no walks logged in the last 7 days," never a failure framing).

**NG-safety invariant SPLIT, not weakened (the Pin-1 proof).**
- The **OFFER** path is **engagement-only** and **byte-identical under a wholesale swap of all reading values** (holding the day count constant) — the offered habit + readiness can't depend on what the data says.
- The **FOCUS adherence line** may read the linked type's **occurrence TIMESTAMPS only, never values** — gated by its **own** byte-identical-under-value-swap case (swap walk durations, the count/dates are unchanged).

**Markers, not analysis (rationale for the record).** Acceptance date + linked events + the biometric series together form the **intervention / dose / outcome** structure a future *impact analysis* needs. That analysis is **Layer 4 / Tier-2, gated as ruled** — **this slice only lays the markers**; it computes no effect, asserts no relationship.

**State + persistence (Fork C — settings, no v5 — with a load-bearing-markers caveat).** `settings.nudges = { enabled, habits: { <id>: { state: accepted|declined|snoozed|retired, at } } }`. Config-adjacent, consistent with the established split (fasting *config* in settings, no bump; precious tracked *records* top-level + bump). **Because acceptance `at` timestamps are now load-bearing markers**, the settings normalizers must **PRESERVE them exactly** on export/restore — gated (round-trip byte-exact, `at` survives). The one residual risk (an older *same-schema* app's `normalizeSettings` dropping the unknown `nudges` key) is the accepted C tradeoff: it re-offers a declined habit / loses markers-not-yet-used, not health data; a v5 store was judged disproportionate.

**Curriculum is content (Pin 4), the builder's.** `NUDGE_CURRICULUM = [{ id, title, rationale, howTo?, category, linkedType? }]` in code (like `SIGNAL_SPEC`), sequenced by the builder = the offer order. v1 baseline **approved** (walk-after-dinner `linkedType: walk`; veg/water/protein/daylight/wind-down/stand); the builder personalizes entries in later passes — it's cheap-to-evolve code content, shipping on the builder's sign-off.

**Language/safety (Pin 5).** Nudge copy is invitational + hedged ("many people find…", "worth trying?") — note "try" is the mechanism here, *allowed* on the nudge surface (unlike the Mirror). The grep-able safety invariant extends to the nudge surface: **no evaluative-about-the-user vocabulary, no user-data reference**; every rendered curriculum string escaped; the byte-identical-under-value-swap gates are the structural teeth.

## D26 — Scope policy: primary-user-first; generality is not a goal (governance, 2026-07-20)

Per the builder's explicit ruling — sharpening **D21's audience note into operative scope policy**: the app is built around the **primary user's actual usage and needs. Generality is not a goal.** When a fork offers "general / flexible / serve-a-hypothetical-user" vs **"what the primary user actually does," default to the primary user's real protocol** unless generality is nearly free. **Features nobody present uses don't ship.**

This is a **strength, not a limitation** (D21): a sharp, opinionated tool shaped by a real user beats a diluted generic one. The public/open posture (**D17**) still holds — the public gets the opinionated tool; scope decisions are anchored to real use, not imagined users.

**Bound:** scope policy governs **which** features/forks ship, **not** the safety layers. A primary-user desire for personalized advice is still **Layer 4** (D21/D25), gated — primary-user-first never licenses crossing a governance boundary.

## D27 — Regimen: a named timeline template for a repeating day (Phase-4, 2026-07-20)

Layer-1 adherence (D21 day-40 test), scoped to the primary user's real protocol (**D26**). A **regimen** is a **named timeline template** — composition over existing machinery (presets / the medication kind / event types), **never a fourth record system**. `APP_VERSION → 0.8.0`; **schema v5**.

**Never auto-log (Pin 1).** A regimen **never writes a record by itself** — instantiation is always user-confirmed. The template pre-fills; the human confirms. Gated: rendering the checklist, day-switch, day-boundary, and boot write **zero** records.

**Byte-identical instantiation (Pin 2).** Food = a **preset reference** → `buildPresetItem(preset, time)` (the same builder the manual `logPreset` uses); medication = `addSignal({kind:'medication',…})`; event = `addSignal({type,…})`. Instantiated records carry **no regimen tag** — byte-identical to the equivalent manual log at the same time (gated). A regimen is composition, not a record system.

**Scheduled-time default + surfaced-lateness (Fork B, tap-time leaning reversed).** The record's time **pre-fills to the entry's scheduled time** (for a *followed* regimen that is the truthful time; tap-time would systematically falsify it to whenever the app was opened); confirm attests, adjust deviates. **Refinement (ruled):** when the tap is **grossly late (> ~2 h from scheduled)**, the confirm **surfaces the time** ("Log at 04:30 (scheduled) · adjust?") rather than silently backfilling — a deviant day must not launder itself to protocol-time by reflex. Gated (`isGrosslyLate`; a late log needs confirmation).

**Storage — top-level `regimens` store, schema v5 (Fork A).** User-authored content with **real recreation cost** sits on the **`fastLog` side** of the D20/D22 line, not the nudges side — an older app silently dropping authored protocols on re-export is genuine data loss. The **fulfillment log rides in the same store** (attestation history must also survive cross-version). `regimens = { active, list:[ {id,name,window?,entries:[…]} ], log:{ "<date>":{ "<entryId>": "template"|"substituted" } } }`. Add-only **v4→v5 migration**; forward-guard rejects `>5`; snapshot retained; `normalizeRegimens` hardens; export exact; ingest never touches it.

**Weekday-mapped rotation (Fork D/5).** Each entry has an optional `days:[0..6]` (Sun=0); absent = every day. "Today's regimen" = entries matching today's weekday, time-sorted — subsumes A/B alternation with no separate variant concept.

**Window = metadata, decoupled from fasting (Pin 4).** The declared eating window is **display-only** on the checklist; it **never** feeds `detectFastCandidates` — candidates stay derived from actual food timestamps (D22). Gated (candidates identical with/without a window).

**Substitution — fulfillment by acknowledgment (Fork G, the addendum).** A checklist row has **three affordances**: **Log** (instantiate → record + a `template` fulfillment flag), **Logged elsewhere** (attest a substitution → a `substituted` flag, **no record** — the real intake exists via ingest/scan/manual), **Skip** (neutral, no state). **No auto-match** — ingest/scan/manual logging sets **no** flag (inferring fulfillment from timing/content is content-guessing, prohibited); the user attests, same grammar as fasting resolution. Never-auto-log holds (acknowledge writes a **flag, not intake**). **No double-log** — tapping a fulfilled row **asks**, never silently adds; **undo-removes-both** (the Log undo toast removes the record **and** its flag); un-acknowledging a substitution same-day clears the flag. The `template`/`substituted`/unfulfilled kinds are recorded as **markers** for a future adherence surface (not built now — like the nudge markers).

**Authoring — JSON paste (Fork C, D26).** v1 authors by pasting JSON (a form builder is a fast-follow for a second author). `parseRegimen` runs `cleanJSON` + validation with **specific per-entry rejection messages** (which entry, why). An **in-app copyable authoring template + sample** ships (the `AI_PROMPT_TEMPLATE` pattern), **self-consistency-gated** the same way: the shipped `REGIMEN_SAMPLE` must `parseRegimen`-clean — so author-via-AI works out of the box.

**Edits never touch history (Fork E).** Instantiated records are independent copies; editing/deleting a regimen or entry never touches logged records (the preset-deletion precedent). **Multiple regimens, one active (Fork F).**

**Cadence items are OUT (Fork D).** The 72–96 h fast every 14–21 days needs **no representation** — `detectFastCandidates` already catches it (D22's no-cap ruling was made for exactly these). Weekday-fixed recurrence fits via `days`; genuine interval/quota cadence is deferred. **User-authored only (Pin 6)** — no suggested/recommended regimens (app-recommended-from-goals is Layer 4, prohibited).

## D28 — Governance: the device-integration gate is RULED (closes D19's deferral) + FairCart addendum (2026-08-30)

Closes the **standalone device-integration strategic gate** that **D19** referenced and deferred ("ruled with D17-level rigor before any integration code"). Governance-only, like D17/D19/D21/D26: it binds architecture, it builds nothing.

**Option letters are local to this entry** — D19's parked-feature letters (A nearby prices, B BYOK vision, D week analytics, E shopping lists, F contribute-back) are a **different set** and are not affected. Here: **A** = stay PWA, manual entry only; **B** = native shell; **C** = cloud OAuth adapters; **D** = a server we run.

### The ruling: B, then C-if-demanded; A is the floor, not the plan.

**Architecture fork — ruled directionally, not calendared.** HealthKit-class device data will come via a **native shell** (Expo/React-Native WebView wrapping the existing web app, native bridge for HealthKit) feeding the **existing Slice-T adapter contract** (D19/D20: "a later cloud adapter or native layer must feed the same store via the same contract with no substrate rebuild") — **never via a server we run**. The web app remains **canonical**; the shell is a **consumer**.

**The shell's start is gated on a real trigger, not a date:** when the WebView pattern's viability is confirmed on this exact stack, or when a HealthKit need (steps, sleep/HRV, CGM-via-HealthKit) becomes an actual build decision — whichever comes first. Ruled **directionally so the fork is never re-litigated**.

**Verified facts the ruling rests on** (recorded because the ruling is only as good as these):
- **HealthKit is native-only**; no browser API exists or is coming. This is the fact that **forces** the fork — no amount of PWA work reaches it.
- **HealthKit ingestion via a native bridge involves ZERO egress** — device → bridge → `normalizeSignal`; no cloud, no token, no server. **B adds device data without crossing D17's "nothing leaves your device" line**; the only thing spent is the "just a website" simplicity.
- **Dexcom lands in HealthKit** (3-hour delay, the same as their own API) — **CGM comes free with B**, no API work.
- **Costed path** (report dated 2026-08-29): no Mac needed (EAS cloud builds from Windows); `@kingstinct/react-native-healthkit` with **anchored queries + per-type staleness badges** (background delivery throttles silently — **surface it, never trust it**); ~US$99/yr developer program; ~three build days to TestFlight after enrolment.

**Cloud OAuth adapters (C — Oura-first) are DEFERRED behind B's evidence.** Revisit only when a real user actually needs the cloud route (e.g. an Oura owner who won't or can't install the shell). C is the **genuine D17 egress crossing** (user token + biometric data transiting the vendor's cloud) and ships only behind the **informed-consent tier**. **Do not build consent infrastructure for a constituency that may not exist** — the D26 discipline applied to governance plumbing.

**Option D (any server we run — sync, hosted pulls, accounts) is REJECTED** per D17(b). A future commercial tier revisits under **D17's own optionality rules**, never through this gate.

### D17 posture — re-confirmed, with one extension.

The **free / public-good positioning HOLDS** for an app holding device biometrics: the shell ships free, no accounts, data on-device, export-is-yours; **an App Store listing is distribution, not monetization**. **Extension line for D17:** the native shell's existence creates **no server, no account system, no telemetry**; the bridge has **no network path** (cross-device transfer, if ever wanted, follows the **export-via-share-sheet** pattern). The privacy README extends to the shell: **HealthKit data never leaves the device**.

### Roadmap consequence (recorded, not built).

B unlocks, in order: **steps → sleep/HRV → CGM via HealthKit → the fasting resolver's fourth state** (biometric auto-resolution of pending candidates — the **Slice-X seam D22 was built to leave open**) **→ Layer 4's data threshold actually filling** (D21).

### FairCart addendum.

The **FairCart lineage** — scan, personal price history, and nearby-price comparison via **Open Prices (read-only, user-initiated)**, with device location as a **TRANSIENT query parameter: never stored, never continuous, one-shot lookups only; a location history/trail is PROHIBITED** — is confirmed **in-scope and privacy-clean** under the existing rulings (D14/D18 + the brief's Phase 3).

**Product COMPARISON on explicit factual metrics is Mirror-grammar (D23) and PERMITTED:** same-barcode price deltas across stores ("$4.99 here · $3.49 at X, 800 m") and cross-product **price-per-unit** or **price-per-gram-protein** with the **metric STATED**. **Comparative-factual language only; never "better for you."**

**Product RECOMMENDATION that reads the user's health data** (goals, regimen, intake history) **to steer purchases is Layer-4 personalized guidance** (D21/D25) — gated behind the guidance/contraindication governance note and the consent tier; built only when that gate opens.

**Standing rule regardless of tier: NO recommendation or comparison surface ever carries commercial placement** — no affiliate links, no sponsored results, no paid ranking (D17). **The trust story is the asset; a paid "better product" would spend it permanently.**

## D29 — Timezone-offset capture: additive, capture-only, no schema bump (Phase-4, 2026-08-30)

**Motivation.** Timestamps store **local wall-clock only** (`item.time` = `"HH:MM"`, `fastLog` start/end = `"YYYY-MM-DDTHH:MM"`) and days are keyed on **local date**. Fine at home; **logging while travelling silently shifts day boundaries** and poisons future correlation against sleep/fasting windows. The offset costs ~nothing at write time and **can never be retrofitted** — every day logged without it is information destroyed. This slice takes the **minimal honest version**: capture only.

**`tzo` = the device's UTC offset in whole minutes, east-positive** (UTC−4 → `-240`). JS `getTimezoneOffset()` is west-positive, so `nowTZO()` negates it. `APP_VERSION → 0.8.1`.

**Pin 1 — ADDITIVE ONLY; this slice CAPTURES, nothing CONSUMES.** Every record-creation path stamps `tzo` alongside the existing timestamp. **Zero behavior change**: day keying, display, averages, fasting detection, trends, Mirror all untouched. No reader is built.

**Pin 2 — absence is a first-class state, never backfilled, never guessed.** All existing history is **pre-capture**; records without the field are honest, not broken. A garbage or out-of-range value is **dropped to absent, never clamped** — clamping would launder noise into a real-looking zone, the "absence ≠ zero" principle (D19/D22) applied to zone data.

**Pin 3 — never stamp the ingesting device's zone onto data authored elsewhere.** The AI-paste / full-days / restore boundaries **preserve** a valid incoming `tzo` and **never invent one**; the paste author's zone is unknowable. The AI prompt template is unchanged for now.

**Pin 4 — boundaries.** `normalizeTzo` coerces to an integer and validates **±840** (UTC−14…UTC+14) at entry **and** at restore; every normalizer **preserves** the field; export/restore round-trips **exact**.

### Fork 1 — version: NO BUMP (ruled). Optional-additive; schema stays v5.

**The asymmetry is decisive.** D27 bumped v4→v5 because an older app silently dropping **regimens** destroys **user-authored content with real recreation cost**. `tzo` is not that: losing it **degrades precision on records that remain fully valid**, and **absence is already a first-class state** (Pin 2) — a stripped offset lands the record in a state the schema already defines as honest. Weighed against a bump's cost — the forward-guard makes an older app **reject the export outright**, so a user hits a wall instead of losing a field no feature yet reads — no-bump is correct.

**Recorded consequence, eyes open:** an older app that restores a v5-with-`tzo` export **silently strips** every offset. Accepted, because the loss is precision on still-valid records, not content.

**Implementation note that the ruling's phrasing must not obscure:** this codebase's record normalizers (`normalizeItem`, `normalizeSignal`, `normalizePriceLog`, `normalizeFastLog`) are **allowlist rebuilds, not passthroughs** — only `normalizeMicros` genuinely preserves unknown keys. "Preserve-unknown-keys posture" is therefore implemented as an **explicit allowlist addition** in each normalizer, **not** by opening a passthrough (which would let arbitrary keys cross the untrusted paste boundary). The `normalizeTimeline` comment claiming "tolerate unknown keys" was misleading and is corrected.

### Fork 2 — regimen instantiation: STAMP the instantiation device's offset (ruled).

Verbatim, as the ruling framed it: **the timestamp answers "when"** — the schedule supplies it, per D27's Fork-B scheduled-time-default — **and the offset answers "where was the device when this was recorded"** — the device supplies it. **Different questions, different sources, each field its own truth.**

Byte-identity (D27 Pin 2) is preserved **by construction**: the offset is stamped inside the **shared** `buildPresetItem` / `addSignal`, the same builders a manual log uses, so an instantiated record stays byte-identical to the equivalent manual log at the same time.

### The creation-path sweep — stamp-or-deliberately-exempt, enforced

The sweep enumerates **every write site**, not just the obvious record creators, and asserts each is **stamped** or **deliberately exempt with a stated reason** — so **a future write site cannot silently join unstamped**. Enforced statically by `tests/check-writesites.sh` (the `check-sw-hash` / strip-check idiom): a write site not in the manifest **fails the gate**.

**STAMPED (8):** `photoSave` (R6, added 2026-09-02 — the census flagged it as unregistered on its first run, which is the mechanism working) · `addManualEntry` · `buildPresetItem` (manual `logPreset` **and** regimen food instantiation) · `buildScanItem` · `buildSupplementItem` (day-rollover injection **and** enable-time injection) · `addSignal` (chips, signal form, medication form, `logBP`, regimen med/event instantiation) · `addPriceEntry` · `resolveFast`.

**DELIBERATELY EXEMPT, with reason:**
- `toAiPasteItem` / `ingestItems` / `ingestFullDays` / `restore` / all `migrateV*` — **Pin 3**: foreign or historical data; preserve, never invent.
- **Pre-restore backup (D3)** — a **verbatim snapshot** of existing state; stamping would rewrite history with today's offset, violating Pin 2. Must preserve `tzo` exactly and add none.
- **Regimen fulfillment flag** (`setFulfillment`) — the flag is a **bare enum string** (`'template'` / `'substituted'`) keyed by date and **carries no timestamp**; there is nothing to stamp. Giving it one would be a record-shape change, out of scope for an additive-capture slice. The **record** a `template` log creates **is** stamped, via the shared builders.
- `saveManualPreset`, `setGoal`, `setSupplement`, `setNudge`, `setFastingFromForm`, `addRegimenFromJSON` — **templates and settings, not records**: they describe intent, not an event that happened. Their instantiations are stamped.
- `addWater` — `day.water_l` is a **day-level scalar**, not a timestamped record.
- `deleteItem` / `cycleMeal` / `toggleDayStatus` / `clearDay` — mutate or remove; create nothing.
- `ProductCache` — a **disposable mirror** of OFF data (D13), not a user record.
- `priceComparison`'s internal grouping and `focusAdherence`'s date collection — **display-side** structures, never persisted. (Both are read-side false positives of the census pattern; they are classified rather than pattern-matched away, so the pattern stays deliberately over-broad and a real write cannot slip past it.)

## D30 — Single entry point: the main surface becomes display + attestation; authoring moves to settings (Phase-4, 2026-08-30)

**Presentation only. No schema change (v5), no data written, no migration.** The app presents ~19 panels on one surface and most are **authoring** surfaces, so a first use must configure something before the app returns anything. The two paths that return value immediately (scan, quick-log) are not privileged over the rest, and the AI photo round trip is split across two panels sited apart. **This is an ordering problem, not a capability gap** — nothing is removed and nothing changes behavior.

**Main surface** keeps: today's day (ring + strip), timeline (food · events · biometrics), trends, averages, all days. **One persistent `+`** opens a sheet with four food modes — **Scan (default)** · **Quick** (presets as chips) · **Photo / AI paste** · **Manual** — plus two secondary entries at its foot: *log event or biometric*, *log medication or supplement*. **Scan is default** because it is the only path returning micronutrients in one tap, and micronutrient capture is the app's differentiating claim. **Photo is third, not second**, because AI-paste items are macros-only at `eyeballed` confidence — the ordering reflects **data quality, not convenience** (the honesty rule, applied to menu order).

### The five open rulings, closed

**(1) Cold-start kit — the gate protocol is now specified.** Fresh install, **one real barcode-bearing item**, the instruction *"log what you'd eat today,"* success = an **honest logged item unaided within minutes**. Pre-registering the kit is what makes the criterion falsifiable: without it a failure cannot distinguish *wrong ordering* from *nothing in the room to scan*.

**(2) The main-surface rule is AUTHORING vs ATTESTATION** — not "display vs interactive". **Authoring and configuration go to settings; today's state and its one-tap responses stay.** So the **regimen checklist**, the **nudge offer**, and **fast-candidate resolution** REMAIN on the main surface: each is today's state plus a one-tap response, and each is load-bearing for a ruled invariant (D27 substitution grammar, D25 one-tap-to-pass, D22 three-state resolution). Moving them would have silently regressed those rulings while passing a naive "display-only" reading. Their **configuration** (regimen authoring, habit enable, fasting config) moves.

**(3) Photo mode is "Photo / AI paste", with the paste field directly reachable** — copy-prompt and paste-return are one flow in sequence, ending the split-across-two-panels problem. The paste field is the existing four-shape `ingest` boundary, so the **full-export merge shape stays reachable** there. **Destructive Import / Restore stays in settings and never shares a surface with merge-ingest** — a non-destructive merge and a replace-everything restore must never sit one mis-tap apart.

**(4) The tap-count promise is DROPPED.** "At most two taps from settings" was unfalsifiable (settings did not exist; `<details>` panels make the count arguable). Replaced by a stronger, checkable property: **settings is a flat, single-level list and every relocated capability is a named top-level entry**, gated **by enumeration** — the gate names each capability and asserts its entry exists, which cannot be satisfied by burying something one level deeper.

**(5) The tester is the primary user; distribution is deferred by the builder's decision.** The gate is the **re-verification sweep** plus the builder's **attestation that the reorganization costs the daily flow zero**. The **cold-start criterion is DEFERRED, not dropped** — it fires **if and when distribution happens**, with the kit from (1) already pre-registered so it cannot be retrofitted favorably.

**Reconciliation with D26 (required, recorded).** My earlier review named a conflict: the change is D26-clean (it removes and adds no features) but its original **gate** — three unfamiliar cold-start testers — was a **generality instrument**, and D26 rules that generality is not a goal and that work is not done for a constituency that may not exist. Ruling (5) **resolves it in D26's favour without discarding the evidence**: the slice is judged by **primary-user cost** now, and the generality instrument is **held in reserve, pre-registered**, firing only once distribution makes that constituency real. This is the same discipline D28 applied to consent infrastructure — **design the seam, don't build for a hypothetical population** — and it preserves registered-before-observed, since the cold-start kit is fixed in advance rather than written after a disappointing result.

### Moved to settings (flat, single-level, unchanged in function)

Regimen authoring · Goals · Daily supplement · Presets (management) · Fasting configuration · Habits configuration · AI prompt template (also surfaced inside Photo mode) · Export · Import / restore.

### Invariants that must not regress (each testable)

Events/biometrics never enter food totals · averages complete-days-only · pending fast candidates count toward nothing · AI-paste is macros-only, micros stripped, eyeballed · ingest never overwrites a day with items · restore backs up first and surfaces the backup · daily supplement off by default, flagged and non-deletable when enabled, past days keep their record · habits one at a time, never a notification, one tap to pass, permanent on decline · the data-layer suite stays green at its current count.

**Post-attestation addendum (2026-08-30, v0.9.1).** Ruling (5)'s attestation is **signed**: the reorganization costs the primary user's daily flow nothing. The pass surfaced two presentation defects, both fixed without behaviour change — **"All days" collapses to one counted line**, and the **two entry points take permanent labels** ("+ Log", "Settings") rather than icons.

The labels point at something the record should hold: on a display-only surface those two controls are the **only doors**, so an unlabelled one does not read as an unlabelled button — it reads as *"where did everything go."* This is **the closest available proxy for the deferred cold-start criterion**, and **it points the same way**: the barrier this slice diagnosed was ordering and legibility, not capability. It is a proxy, not a substitute — one experienced user meeting his own reorganized app is not three strangers meeting it cold — so the deferred criterion stands unchanged, with its kit still pre-registered.

**Failure means the diagnosis was wrong** — that the barrier is not configuration burden but something else (day model, form length, performance). That is a useful result and is to be **recorded as such rather than patched around**.

## D31 — Governance: monetization direction (2026-08-30; reconciled verbatim 2026-08-30)

Direction only, like D17/D19/D21/D26/D28: it binds **preconditions and refusals**, and authorizes **no** build work. **Nothing here requires action now.** This entry's only job is to make sure the future conversation with an affiliate network, an analytics vendor, or an eager advisor **finds the refusal already written**.

*(Reconciled against the authoritative draft. An earlier reconstruction of this entry, written from a four-point summary, thinned it badly — it omitted the wall placement, the billing rail, paid-computes-locally, the upsell rules and the sequencing. The full text is restored below.)*

### The wall placement (the price list is already built)

- **Layers 1–3 — Track, Mirror, Nudge — are free forever, on the PWA, never degraded.** D21's public-good commitment restated commercially: **the free tier is a complete product by the project's own declaration.**
- **The advisory tier is the paid product:** the Layer-4 correlation engine, the two-feature guidance split (sourced interaction flags; personal correlation observations), the trusted-supplier directory, and any future curated protocol library. **One subscription, not SKUs.**
- **The consent wall and the paywall are THE SAME WALL.** Layer 4 was always going to be opt-in, walled, and deliberately activated for safety reasons; **charging at that gate adds no architecture and moves no boundary.**

### Capture free, interpretation paid

- **Device-data ingestion (HealthKit via the native shell, per D28) is FREE.** Charging users to receive **their own data into their own device** would spend the ethos for trivial revenue; free capture also feeds the free Mirror.
- What is paid is what we **ADD** to their data: analysis, sourced flags, curation, templates. The commercial ethic in one sentence: **"Your data, free. Our judgment, paid."**

### The billing rail (no accounts, ever)

- The **ONLY** payment rail is **platform in-app purchase** (Apple IAP via the native shell). The platform holds identity and payment; **the app validates entitlement locally.** We hold **no name, no email, no card, no account system** — **D17(b) intact**.
- **Consequence accepted:** the free tier lives everywhere (PWA); the paid tier lives in the shell. **The constituency that would pay is the constituency that installs.**

### Paid computes locally

- The subscription unlocks **CODE PATHS, not a cloud service.** The correlation engine runs **on-device over on-device data**. The supplier directory ships as **versioned, signed content inside app releases — no phone-home**.
- **Paying creates zero telemetry, zero sync, zero egress.** A paying user's data is **exactly as sovereign as a free user's**.

### The upsell surface (mirror-never-nag applies to commerce)

- **No locked-panel teasers, no interstitials, no upgrade badges in the free experience.** **ONE** named entry in settings, plus **at most one quiet, dismissible card that appears only when TRUE**: data-earned eligibility ("you have N days of data — enough for the advisory tier to say something meaningful"). **The offer arrives exactly when the product can deliver.**

### Standing bans (permanent)

- **No commercial placement, ever:** no affiliate links, sponsored results, paid rankings, or supplier-paid listings — **on any surface, any tier** (per the D28 FairCart addendum). **Suppliers in the directory never pay and are never notified in advance of evaluation. Money flows only FROM users, never from the things being recommended.**
- **No ads, no telemetry, no data sale, no accounts — under any tier, any revenue pressure, any future.**

### The agency clause ("paid infers agency")

**Payment for advice creates reliance; reliance creates duty.** The paid tier inherits the guidance-gate guardrails as **OBLIGATIONS, not design preferences**:

- **Sourced-not-guessed** is what makes the product defensible at all; the **minimum-data thresholds** are the refusal-to-opine a professional owes when evidence is thin; **observational-vs-prescriptive grammar** is the line between information a user acts on and advice we are accountable for; **Feature-A's flag-for-your-professional framing** is the referral made at the edge of competence.
- **A wrong paid recommendation is worse than a wrong free one. Charging RAISES the accuracy bar.**
- The purchase flow includes a **real scoping document, plainly written**: what the analysis **is** (pattern-surfacing over the user's own logged data), what it **is not** (diagnosis, treatment, a substitute for clinical judgment), what it **will refuse to do** (opine under-threshold, guess interactions, override the sourced database), and what the user **retains** (all agency over action — **the app informs, the user decides**).

### Named preconditions of the first charge

1. **A new corporation.** Commercial operation ships under a **NewCo formed for the purpose** — **never under ENVIROMINDsource Inc.**, whose consulting practice, professional reputation, and liability profile stay **untangled** from a consumer health product. **NewCo owns the product IP, the developer account, the insurance, and the revenue.**
2. **IP assignment.** Copyright currently rests with the **builder personally** (MIT, solo-authored). On NewCo formation, **assign or license to NewCo** — trivial while solo-authored, **which is why D17(a)'s solo-authorship / CLA-before-merging rule is a COMMERCIAL precondition, not only a governance nicety.**
3. **Legal review** of the scoping document and consent language **before the first dollar.** Insurance/liability structure decided at NewCo formation.
4. **The guidance gate's own conditions** (sufficient real data; deliberate ruling) **remain independently binding — monetization never accelerates the gate.**

### Sequencing

Nothing here requires action now. **Triggers, in order:** the **D28 shell trigger fires** → the shell exists → **IAP becomes possible** → **Layer 4's data threshold fills and its gate is ruled** → **NewCo forms** → **legal review** → **the first charge.** **Each step waits for the one before it.**

## D32 — Safety amendment: jurisdictional reference ranges, shown against the user's own readings (2026-08-30)

Amends the **Mirror (D23)** and the **four-layer model (D21/D25)**. Reference ranges are the first content the app shows that is **about health rather than about the user's behavior**, so the amendment is written as constraints first.

**Declared in settings, never detected.** The user **declares** their jurisdiction in settings. The app **never infers it** — not from locale, timezone, IP, or the D28/FairCart location lookup (which stays a transient one-shot query parameter, never stored, per D28). Detecting jurisdiction would build a location signal the privacy stance forbids, to save one setting.

**Sourced, cited, versioned. Canada first, US second.** Every range ships with its **source, a citation, and a version**, so a range can be audited and updated without guessing what the app was showing last year. **Canada first, United States second**; further jurisdictions follow the same sourcing bar or do not ship.

**Shown against the user's readings.** Ranges are displayed **against the user's own values** — the Mirror grammar (D23): the user's data, the cited band, and the relationship between them. **Factual trend commentary only.**

**Persistence-gated trend row.** When a **sustained multi-week trend crosses a band**, a trend row surfaces. **Persistence is the gate** — a single crossing reading is noise, and surfacing it would manufacture alarm from measurement variance. This is the "absence ≠ zero" discipline (D19/D22) applied to the other tail: **one reading is not a trend**.

**"Worth discussing with your doctor" is standing context, never a per-flag verdict.** It appears as **standing context** for the feature, not as a per-reading or per-flag pronouncement. A verdict attached to individual values is Layer-4 guidance wearing a disclaimer.

**Acute sourced statements ONLY on hand-entered readings, never device streams.** A hand-entered reading is an act of attention — the user is present, looking at a number. A **device stream is not**: acute statements on a stream would fire unattended, at arbitrary hours, on data the user has not looked at, with no one in the loop. This bound holds regardless of how good the stream gets, and it binds the D28 shell in advance.

**Free and default-on regardless of tier.** This is **safety content, not a feature**: it is **free and on by default at every tier**, including any future paid tier (D31). Placing a safety surface behind payment would make D31's paid-infers-agency clause self-contradicting.

**Mirror-never-nag is scoped to BEHAVIOR, not DANGER.** D23/D25's never-nag discipline governs **behavioral** commentary — it was never a rule against telling a user something that matters. **A danger signal is not a nudge**, and never-nag must not be read as a reason to stay silent about one. The two are separated here explicitly so the discipline cannot be misapplied as suppression.

## D33 — Reserved: biometric-triggered logging candidates (a future class; NOT authorized) (2026-08-30)

**Reserved, not authorized.** No build work follows from this entry. It is recorded now so the class has a **named shape and its bounds before anything is built against it** — the same reason D19 designed the adapter seam before any adapter existed, and D22 built a three-state resolver rather than a two-state one that would have to be torn up.

**The class.** A **physiological signal** (from the D28 shell — steps, sleep/HRV, CGM-via-HealthKit) suggests that **something happened worth logging**, and the app offers a **candidate** the user resolves. It is a *prompt to record*, never a record: the same grammar as a fasting candidate (D22), sourced from physiology instead of from a gap in the log.

**Bounds, all of which bind if it is ever authorized:**
- **Opt-in.** Off until the user turns it on. Never on by default, at any tier.
- **Frequency-capped.** A hard cap, so the class cannot degrade into a stream of interruptions.
- **Observational grammar.** It reports **what the signal did**, never what the user should do — Mirror language (D23), never Layer-4 guidance (D21/D25).
- **Three-state resolution.** Confirmed / denied / pending, per **D22**: **pending counts toward nothing**, and a candidate is never silently promoted to a fact. A physiological hint is **not** evidence that something happened, exactly as a logging gap is not evidence of fasting.
- **A narrow, named exception to the notification ban.** D25 rules that a nudge is **never a notification**. This class is the **single** exception, and it is **scoped to physiology-triggered logging prompts only** — it does **not** loosen the ban for nudges, habits, adherence, streaks, or anything else. The exception exists because the trigger is time-sensitive in a way a habit suggestion never is; it is written narrowly so it cannot be widened by analogy later.
- **Depends on D28's shell.** The class is unreachable without device streams, so it cannot start before the native shell exists — and the shell's own start is trigger-gated, not calendared (D28).

**Interaction with D32, stated so it is not resolved by accident:** D32 bounds **acute sourced statements** to **hand-entered readings, never device streams**. That bound is **not** loosened here. A logging *candidate* asks the user to record something; an **acute statement tells them something is wrong**. This class may do the first from a stream; it may **never** do the second. Anything that would blur that line needs its own ruling, not this reservation.

## D34 — Lab-panel ingestion: per-value records, a lab sub-registry, and measurement-class-aware persistence (Phase-4, 2026-08-30)

A **dated lab panel** enters as **biometric records with `source: 'lab'`** — the **outcome layer** the correlation engine (D19) was aimed at. Curated starter set of 14: ApoB, LDL-C, HDL-C, triglycerides, HbA1c, fasting glucose, fasting insulin, hs-CRP, 25-OH-D, ferritin, ALT, AST, eGFR, TSH. `APP_VERSION → 0.10.0`; **schema unchanged at v5**.

**Fork A — PER-VALUE records + an optional `panelId` (ruled).** Each analyte is an ordinary timeline record; the **panel is a derived grouping**, exact when `panelId` is present. This keeps D19's "one abstraction, many adapters" and avoids the **fourth record system D27 warned against**. A blank row is *not measured* — not an error, and not a zero.

**Fork B — a `LAB_SPEC` SUB-REGISTRY merged into `SIGNAL_BY_TYPE` at load (ruled).** Two authoring surfaces, **one runtime lookup**: `normalizeSignal`, `signalSeries` and `chipLabel` needed **no change**. It is deliberately **not** merged into `SIGNAL_SPEC`, which drives the biometric/event picker and the chip strip — **ApoB does not belong beside Sauna**, and lab rows carry reference-range metadata no other signal has.

**Fork C — NO schema bump (ruled).** `source: 'lab'` rides D20's open `source` string. `panelId` is a **grouping key**: losing it degrades grouping but loses no value, so on D29's asymmetry test it is **precision, not content**. Gated for the older-app case: an app that does not know an analyte **still preserves the record** (unknown `type` tolerated), and `panelId` / `ref_low` / `ref_high` / `ref_src` are **explicit allowlist additions** in `normalizeSignal` — the `tzo` pattern, because that normalizer is a rebuild, not a passthrough.

**Fork D — measurement-class-aware persistence, restating D32 for lab cadence (ruled; "in the same band" = PERSISTENT BAND MEMBERSHIP across consecutive panels, confirmed on review).** D32's "sustained multi-week trend" cannot fire on quarterly data, so it is restated in **panels**:
- **1 point** → the band is displayed **factually**, with **no trend claim**;
- **≥ 2 consecutive panels in the same band** → a **trend row**;
- **≥ 3 points** → **directional commentary**.

**Gated explicitly: a single out-of-band lab value is never silently un-displayed.** That is the failure mode this restatement exists to prevent — a persistence gate written for daily data would have made the first abnormal result invisible.

**Fork E — per-analyte conversion, and a CHANGED `convertUnit` contract (ruled).** Conversions ship for the convertible set: **glucose and lipids with per-analyte factors** (LDL/HDL 38.67, triglycerides 88.57, glucose 18.0182 — *not* one shared factor), **25-OH-D ×2.496**, **insulin ×6.945**, and **HbA1c by the NGSP/IFCC FORMULA**, which cannot ride a multiply table. Everything else is **store-as-entered**.

**The contract change:** `convertUnit` returning `null` now means **display as entered, unconverted and labelled — NEVER dropped**. It previously meant *excluded from the series*, which is how an analyte vanishes from its own history. **Gated: no analyte ever vanishes from a series.**

**A previously-gated behaviour changed, recorded rather than quietly updated:** case **M1** asserted the old exclusion (`points.length===1 && excluded===1`). It now asserts the new contract — the reading is **kept, flagged `converted:false`, and labelled with its own unit**. *Statistics* (avg/min/max/Δ) are still computed over converted points only, and the sparkline plots only those: **averaging ppm with mmol/L would be a worse dishonesty than the drop this replaced** (confirmed on review). The unconverted readings are **stated explicitly** rather than hidden, using **the micronutrient coverage idiom**: *"avg over N of M readings (K unconverted, shown as entered)."* Same grammar as the micro rollup's "from N of M items" — partial coverage is visible, never implied-complete.

**Content bar — SPLIT (ruled). Five cited analytes, not fourteen — and the lipids are OVERLAYS, not bands.**
- **Guideline-BANDED (3), Canada first per D32:** HbA1c and fasting glucose (**Diabetes Canada**), 25-OH-D (**Osteoporosis Canada**). Each band carries **org, citation, version and jurisdiction**.
- **Risk-stratified OVERLAYS (2) — ApoB and LDL-C (Canadian Cardiovascular Society).** **The CCS lipid targets are risk-stratified** (statin-indicated vs primary prevention by risk tier), so **a single band would silently assume a risk category the app must never infer**. Ruled fix: **lipids band from the lab's printed interval like any other lab-report analyte, and the CCS figure rides as a LABELLED OVERLAY with its applicability stated** — displayed alongside the value, never as the user's band, and always carrying the line that **the app does not know the user's risk category and does not assume one**. Gated (`LB-risk`): an overlay analyte carries **no** guideline bands, so an overlay **can never become a band**; with no printed interval entered a lipid claims **no band at all**.
- **Lab-report interval (9):** for ferritin, ALT, AST, TSH, eGFR, hs-CRP, HDL-C, triglycerides and fasting insulin there is **no single honest universal range**, so the honest range is **the reporting laboratory's printed interval**, entered by the user beside the value (`ref_src: 'lab-report'`). **With no interval entered, no band is claimed** — absence, never a guess.
This is why the slice **ships usable on day one** instead of waiting on fourteen citations.

**Content attestation — SIGNED 2026-08-30, with three required edits (folded in above and below).**
1. **CCS lipid overlays:** numbers confirmed; applicability extended to name the **stricter very-high-risk secondary-prevention tier** (LDL-C ≥ 1.8 / ApoB ≥ 0.7 / non-HDL-C ≥ 2.4) and the **non-HDL-C-or-ApoB preference when triglycerides exceed 1.5 mmol/L**; cited to **Pearson et al., Can J Cardiol 2021**.
2. **25-OH-D:** cited to **Hanley et al., CMAJ 2010**, version **"2010 (reaffirmed 2024)"**. **Required disclosure on the band:** Health Canada/IOM and many Canadian labs define sufficiency at **50 nmol/L**, and the user's lab interval may differ. The lab's printed interval is now storable and shown **alongside a guideline band on every analyte**, not only where it is the band. **Nothing on the surface implies the app recommends testing** — Osteoporosis Canada does not recommend routine population screening, and this is a record of panels the user already has.
3. **Boundary semantics: half-open `[min, max)`.** The comparison **already behaved this way** — verified before editing — so 6.5 % and 7.0 mmol/L always banded as the diabetes range. The defect was in the **wording**, which read inclusive. Labels now state the range explicitly, the comparison carries a *never change `<` to `<=`* note, and **six boundary values are gated** so the semantics cannot drift.

**D32 compliance, and what is still outstanding.** The "worth discussing with your doctor" line is **standing context for the section, exactly once — never a per-flag verdict** (gated). Commentary is factual throughout. The numeric thresholds were an **attestation, not a gate** — the harness can enforce that org/citation/version are present, never that the numbers are right. That attestation is now **signed** (GATES.md), in the same shape as the Phase-0 real-export attestation and D30's ruling (5).

**Form density (v0.10.1, on-device follow-up).** The panel form put four controls on one line; at 360 px that left the **value field — the one a human types into — at 64 px**, because three fixed-width neighbours held their space while the single flexible one absorbed every shortfall. Relaid out as **two lines per analyte** (name + hint / value + unit / optional printed interval). **A structural assertion could not see this**, exactly as "14 chips rendered" could not see that ten were unreachable (v0.4.1), so it takes the same remedy: **`tests/lab-form-gate.ps1` measures usable density on the real page, and was proven against the unfixed form before the fix landed.**

**Adapter seam.** `addSignal` now accepts a **declared source from an allowlist** (`SIGNAL_ADAPTERS = ['manual','lab']`) rather than forcing `'manual'` — D19's "one contract, many adapters", with the D28 device adapter joining that list later. It is an allowlist so a source can never be self-asserted by data we did not create; ingest and restore never reach this path.


## D35 — Rhythm ring: a derived 24-hour circle as the day's centerpiece (Phase-4 Layer 2, 2026-08-31)

The day view's centre becomes a **24-hour circle for the selected day**, with arcs for **eating, sleep, exercise and the gaps between** — **every arc derived from a logged record, nothing inferred**. `APP_VERSION → 0.11.0`; **schema unchanged at v5**.

**Ruled and built:** the ring is the centerpiece with a **"now" hand on today only**; tapping a goal cell **swaps** the centre to that goal's progress ring for **12 s** then reverts; the ring follows the existing day navigation; **week and month grids** of tappable mini-rings.

**No zones, no metabolic bands, no achievements, no evaluative colour** — categorical only (eat / sleep / exercise / fast), and the **M7 vocabulary invariant now extends over every ring and mini-ring label** (gated, including an explicit no-zones/no-anabolic/no-catabolic check).

### Forks, as ruled

**A — ownership and drawing are two questions.** A sleep interval is **owned by the wake day**, but **drawn split by the clock**: each day's ring shows only the portion that actually elapsed within that day, and the crossing end is flagged **open** so it reads as continuing rather than as a second sleep. Painting a whole night onto the wake day would put a 23:30 segment on a day when nothing happened at 23:30 — **an inferred arc, which the honesty rule forbids**. (The D29 Fork-2 shape: different questions, different answers.)

**B — no bump, and no new shape.** The existing event record **already is an interval** (`time` = start, `value` = duration), so bed→wake needs no new shape. The real problem was a **discriminator**, and **the type itself is it**: a new `sleep` type for intervals, legacy `sleep_hours` untouched and **arc-less**. This needed **no normalizer change at all** — unknown types are already tolerated and preserved (gated by `LB-C`) — so "existing readings stay valid and draw no arc" is **automatic rather than conditional**. `sleep_hours` remains the analysis series and an interval **contributes a derived point** to it (`SERIES_ALIAS`), so Trends and Mirror keep reading one key.

**C — one clock seam, used twice.** `nowMs()` with a test override drives **both** the swap timer and the **now hand**; without it the ring is untestable at a fixed time. **Day navigation cancels** a swap (it changes the ring's subject); **an incidental `refresh()` does not** (a background re-render must not revert it mid-look). Both gated.

**D — its own Rhythm card**, directly below the day view. **Trends stays numeric**: the mini-rings are **navigational**, which is day-view behaviour, not trend behaviour.

**E — NOT the first consumer of the D29 offset.** The ring draws **wall-clock**. D29 was ruled capture-only; making the ring its first consumer would silently change what a travel day looks like without a ruling of its own. **Recorded so it is not assumed later.**

**F — the empty ring renders.** Hiding it would make the centerpiece appear and disappear and would teach a first-run user nothing. A zero-record day draws an honest empty circle with a plain caption, and **implies nothing about intake**. At every density, **no arc without a record** — nothing is interpolated.

### Conflicts, as ruled

**(i) Signal goals get their own cell.** There was **no "signal goal chip" to tap** — signal goals had no goal-strip cell (D24's nutrient-only filter contract) and surfaced only as floated **quick-log chips whose tap logs**. Wiring the swap onto those would have **regressed D21's fastest logging path**. Instead the goal strip gains a **separately-filtered signal-goal group**; cells swap, **quick-log chips are untouched**, and **D24's filter contract is unchanged** — the new cells never feed the ring math.

**(ii) `.primsel` retired; `primaryNutrient` is now a declared setting.** This made the slice **not presentation-only**: an explicit `normalizeSettings` allowlist addition (the `tzo` / `panelId` trap), **validated against `RING_NUTRIENTS` and never the mixed-namespace goals map**, so a signal key can never become the "primary nutrient". **No schema bump** (settings-side precedent: `currency` D18, `signalUnits` D20, `fasting` D22, `nudges` D25). **Absent stays absent and derives** — protein if a protein goal exists, else kcal — because storing a default at first boot would fabricate a choice the user never made. It lives inside the existing **Goals** settings entry, so the flat list and `SE-enum` are unchanged. *Recorded eyes-open: an older app restoring the export silently drops the declaration and the next slice falls back to the derived key.*

**(iii) Fast-candidate resolution did not move — it gained a surface.** The ring is now the primary resolution surface, and `#fastCandidates` **remains**, so `SE-attest` is unchanged rather than amended.

**(iv) One sleep chip, one mapping.** The chip targets the interval type; `CHIP_GOAL_ALIAS` makes a legacy `sleep_hours` goal float it. Not two sleep chips.

**(v) `"fasting"` is gated separately.** M7's banned list does not contain that word, so D22's trailing-gap prohibition is its own case (`RR-trailing`), asserted on the label directly rather than assumed to fall out of the vocabulary invariant.

### Centerpiece scale (addendum, v0.11.1)

The ring is the centerpiece, so it renders at **centerpiece scale**: `min(80vw, 360px)` — **80% of viewport width on a phone**, capped so desktop stays sane. Both ring SVGs carry a `viewBox`, so **arcs, labels and the now-hand scale proportionally** with no separate work; **mini-rings are unchanged**.

**The ruled constraint was that the regimen checklist and the `+ Log` pill stay reachable without scrolling, with the constraint winning over the number. Neither can bind, and the record should say why rather than let a gate look stronger than it is:**
- **`#regimenChecklist` renders ABOVE `#dayView`** in the day card, so ring growth pushes it **up the document, never down** — it cannot be displaced by a larger ring.
- **The `+ Log` pill is `position:fixed`**, so it is in the viewport **by construction**, at any ring size.

Both are asserted anyway (they are the ruled wording), but the assertions that **actually bind** are the surfaces a larger ring *can* push off screen, and which the ring itself depends on: **the goal cells** (the swap affordance — the ring's own interaction) and **the ring caption** (which carries the pending-fast one-tap resolve, a ruled D22 attestation affordance). Both are gated above the fold at 390×844.

**Measured, so no size-down was needed:** at 390×844 the ring is **312 px (80% of vw)** with checklist, `+ Log`, goal cells and caption all above the fold; at 360×780 it is **288 px (80%)**; at 1200 px it caps at **360 px** with no overflow. The full 80% target holds, so the fallback ("size down to the largest ring that doesn't break reach") never fired.

### Day-status label and date display (addendum, v0.11.2 — presentation only)

**Day status.** The "in progress" badge is a **pre-ring leftover on today** — the now-hand already communicates it — so today carries **no badge**, a **complete past day carries no mark**, and the one state that keeps a visible label is a **past day left unclosed**. That is the only status that **prompts an action**, and it **silently excludes the day from averages** (D10), so the label says so: *"not closed · excluded from averages."* **The underlying binary is untouched** — `in_progress | complete`, averages complete-days-only — and the close/reopen control was already its own button, so removing the badge orphaned nothing.

**Dates.** The day header reads **"Tue Aug 31"** — weekday, month, day, **no year**. The year appears **only where it disambiguates**: the grid range label when it **spans a year boundary or sits outside the current year**, and the all-days list for **prior-year entries**. **Date keys, storage, `tzo` handling and exports are untouched — data stays full ISO, always** (gated).

*Edge RULED (v0.11.3):* a **prior-year day opened in the header SHOWS its year** — *"Wed Jul 8, 2025"*. **The ambiguity rule governs, and the header is not exempt from it.** The two statements of this ruling reconcile cleanly: "the header renders without a year" describes the ordinary current-year case, and the ambiguity rule settles the edge it did not address. Gated (`DT-prioryear`).

### Assertion-count discipline (standing rule, from v0.11.3)

Ruled after the masked-exception defect below. **Every gate report states the authored-assertion count against the executed count, and any discrepancy is explained.** Made structural rather than left to diligence:

- **`EXPECTED_ASSERTIONS` is pinned in `tests/run-data-layer.sh`.** The executed total must match it, so a **silent drop fails the gate** instead of passing quietly. The pin is bumped **deliberately, in the commit that adds or removes cases**, with the delta stated.
- The report prints **`executed · pinned · authored-lines`**. The authored count is a **static lower bound only** — it counts source lines containing a `res(` call, so multi-line calls and helper reuse make it an approximation. **The pin is the enforcing mechanism; the static count is a cross-check.**
- **Proven against the real fault**: re-injecting the v0.11.0 defect fires **both** defences independently — the harness records the uncaught throw *and* the pin reports the count delta (−11). A layout gate that cannot reproduce its defect is worthless; so is a count check that cannot.

**`DS-drift`** closes the second half of that failure: `normalizeSettings(defaultSettings())` must be **byte-identical** to `defaultSettings()`, plus an idempotency case — so the divergence that left a fresh state's `primaryNutrient` `undefined` cannot return.

### A previously-gated contract changed, recorded rather than quietly updated

**`SG1`** asserted that `renderGoalsHTML` output was **byte-identical** with vs without a signal goal. Conflict (i) deliberately breaks that — a signal goal now renders a cell. The invariant D24 actually protects is that **a signal key never reaches the ring math**, and that is now asserted **more precisely than whole-output equality ever did**: the centerpiece ring and the swapped nutrient ring are each byte-identical with vs without a signal goal, the nutrient cells are byte-identical and unmoved, and the signal goal appears **exactly once**, appended as its own group.


## D36 — Ring fullness: trailing-24h live ring, ghost plan-arcs, centre tenant (R8; Phase-4 Layer 2, 2026-09-01)

Bundles and **supersedes R1**; **R3's rationing note is recorded here**. Extends **D35**. `APP_VERSION → 0.12.0`; **schema unchanged at v5**.

**1 — Trailing-24h live ring (the primary emptiness fix).** The **live** centerpiece shows the **last 24 h on a fixed clock face**, labelled **"last 24 h"**. Last night's dinner, the sleep that followed and the open gap render **contiguous**; the hand **ages content out** behind it. **Archival rings stay calendar days.** Within any 24-hour window each clock position occurs exactly once, so a trailing window needs no extra disambiguation — the face stays a clock, and a record keeps its clock position.

**Fork A still holds for archival rings** (an interval is owned by the wake day but **drawn split by the clock**). On the live ring the same night is **one arc**, because the window itself spans the midnight it crosses — that is the point, not an exception. Both are gated against the same record set.

**2 — Arc weight.** Stroke is **12 of the 180 viewBox = 6.7% of ring diameter**, so a 312 px ring draws **~21 px bands**. Lane spacing is `0.16·R ≈ 13` units, so a 12-unit stroke nearly fills each lane with a hairline gap — **bands, not hairlines**. Gated in `ring-size` both **absolutely (≥ 14 px)** and **as a proportion (≥ 5% of the ring)**, so a future resize cannot quietly thin them back out.

**3 — Centre tenant (R3's rationing note).** The centre disc carries the **open-gap counter** — *"14.1h since last logged food"* — **today-state, factual, D22 grammar exactly**. It **never says "fasting" about an unconfirmed gap**, and a gate asserts the word is absent from the open-gap label in any form.

*Distinction worth keeping visible:* the **open** gap shown is **not** a candidate — candidates are **closed** gaps awaiting attestation. So tapping the centre **reveals** the most recent pending candidate's resolve rather than asserting anything about the gap on display. Two different objects, one surface, and the tap is a reveal, not a claim.

**4 — Ghost plan-arcs (D27 generalized).** The regimen's **declared** items with clock positions draw **faint, under the actual**: the eating window (existing), a **new optional `sleep` field (bed → wake)**, and **scheduled entries as rim ticks**. **Plan ghost, actual solid**, visually distinct, no evaluative rendering, **no auto-anything** (gated: plan arcs write zero records). Rendered **only from declared fields** — with no regimen there are no plan arcs and no plan ticks.

*Schema:* `sleep` is an **allowlist addition** to `normalizeRegimen` (a rebuild, like every other normalizer here) with a matching check at the `parseRegimen` authoring boundary. **No bump** — the `regimens` store already exists (D27's v4→v5 covered introducing it), and losing this field costs **two re-typed times, not a protocol**. Both boundaries gated.

**5 — GUIDELINE TARGETS DO NOT DRAW ON THE DAY RING (standing prohibition).** Durations and weekly sums **have no clock position**, so placing them on a 24-hour face **fabricates a schedule the user never declared** — the same failure as an inferred arc, arriving by a different route. They belong in **Trends and the week view under D32** (sourced, cited, versioned, jurisdiction-aware): a sleep-duration guideline beside the sleep trend, a weekly-activity guideline in the week header. **A separate slice if wanted — not this one, and nothing here builds it.** This is recorded as a prohibition rather than a preference so a later slice cannot reach for the ring as the convenient surface.


### Ring display rules (R11 addendum to D36, v0.12.1 — presentation only)

**Graduated gap counter.** Under **48 h** (`GAP_DATE_AFTER_MIN`) the centre is a stopwatch; at or past it, a **date with no decimal**. A tenth of an hour on a 46-day gap is **fabricated precision**, which is the inferred-arc failure arriving by another route — so the counter stops offering precision it does not have. The pending-resolve tap line survives either form.

**First-contact surface.** Zero records and no declared regimen draws an **instructional ghost**: complete, faint lane circles labelled *meals · sleep · exercise*, plus one quiet hint line. **Complete circles, never arcs** — a full circle cannot be misread as logged time. **Grammar, not content**: no fake data, no example numbers, gated as zero digits in caption and SVG. It yields the moment a record **or** a declared regimen exists, and with a regimen the ghost plan-arcs carry the window instead. **The bare circle is never the answer.**

**Now-hand clears the centre tenant** — it runs rim-inward and terminates at the counter's bounding circle, measured against the text block rather than assumed.

**De-duplication.** The legend never restates the centre: the open-gap line lives in the centre, the legend carries the pending-candidate resolve, and the open-gap arc still draws.


## D37 — The ring as a concentric-lane instrument, allocated by conflict (R13 + R13.1; Phase-4 Layer 2, 2026-09-02)

Replaces the single-ring rendering. `APP_VERSION → 0.13.0`; **schema unchanged at v5**. **R14 (radial response layer) and R15 (audit view) are named and RESERVED, not authorized** — this slice builds their seams only.

### Lanes are allocated by OVERLAP, not by category (R13.1)

**Sleep and eat keep dedicated anchor lanes** at fixed innermost positions — the face's stable identity. **Every practice shares one fat lane**, and a second **spawns only on genuine overlap** (greedy interval packing). Humans are sequential: five dedicated practice lanes would sit empty almost always, spending radius to encode a category that **colour already carries**. **`cat` is identity; `lane` is position** — positional identity is deliberately traded for radius.

**FLIP-STABILITY PIN.** Lane assignment is computed from the **union of plan + actual** intervals and shared by both views, so **an arc can never change lanes between "my day" and "the plan"**. A blink comparator whose geometry moves under it is worthless. Gated by comparing `planeBySrc` across views.

**Packing is deterministic** — sorted by `(start, end, src)`, so the same records pack to the same lanes in **any input order**, and overlap is measured in **absolute** minutes so it is correct across midnight rather than accidentally correct within a day. Gated.

### Geometry, measured rather than assumed

**Fork D was real and it bound.** The reach gate assumed 844 px; Safari's usable height is **~745**. At that height an 85 vw ring pushed the goal cells and caption **below the fold**, and the largest reach-preserving ring measured **256 px (66% of vw)** — far short of the ruled size.

**The cause was ordering, not size.** The goal cells — an *interactive affordance* — rendered **after** the read-only caption. Moving the affordance above the detail list took the reach-preserving maximum from **256 px (66%) to 328 px (84%)**, essentially the ruled figure. That is a design correction, not a relaxed gate: an affordance belongs above a detail list at any ring size.

**Shipped: `--ringw: min(84vw, 380px)`** — the measured maximum. Anchor strokes **12 px**, practice **14 px**, gaps **4.8 px**, centre **0.46 of rim**, reserved annulus **12%**, all computed from constants and gated against collision.

**`MAX_PRACTICE_LANES = 2`, and the trade is recorded.** The ruled stroke widths (12/14 px) with legible gaps fit two practice lanes, not three. A **third simultaneous overlap clamps** into the overflow lane rather than spawning past the cap — rare, gated explicitly, and surfaced here rather than silently muddied.

### The other forks

**Fork B — eleven event types, seven categories.** `cold_plunge`, `workout`, `walk`, `hbot` and `other` have no named category and **all draw today**; dropping them would be a silent regression. They fall into **`exercise` as a bucket**, each arc keeping its **own truthful label**. `alcohol` carries no duration and still draws nothing.

**Fork C — records have no identity.** Every mark carries a **synthesized positional reference** (`item:<date>:<index>`, `sig:<date>:<index>`) as `data-src`. **No schema change.** Recorded plainly: it is stable **within a render, not across edits** — if R15 needs cross-session identity, that becomes a **deliberate schema question then**, not something smuggled in now.

**Fork E — R11's three-circle instructional ghost is RETIRED.** The always-present lane tracks are the teaching layer and do it better. Its cases are **repointed, not weakened**: same invariants (no arc without a record, no digits, one quiet line) asserted against the replacement surface.

**Fork G holds.** Seven categorical hues, **no green at all**, so no green/red pair can read as an evaluation. Plan view renders the **same hues at reduced opacity** — the day dimmed to intention, not a grayscale copy.

**Centre stays display-only, always.** The resolve UI is **evicted below the ring** and gated never to render inside it.

### Reserved seams for R14/R15 (built as seams, not features)

- **Per-category CHANNELS** on the model — a named channel with typed content (`span` | `tick`). **The same contract a radial response series will use** (`kind: 'trace'`, angle-mapped). Channels are keyed by **category** rather than lane, because lanes are now dynamic and categories are the stable thing.
- **`data-src` on every rendered mark** — the audit tap-path needs "what did I tap" to resolve to a record.
- **`AUDIT_WINDOWS` (R15, named, NOT built):** stimulus × response → default window, **sourced/cited/versioned on the D32 machinery**, user-adjustable, **uncited pairs labelled uncited**.
- **Recorded destination:** **stimulus-aligned ensemble averaging over the user's own history** is the named future analysis this structure feeds — the **first consent-tier analysis candidate**, with **shows-never-attributes** governing its framing, and the audit **displaying the crowd of causes, never a single-cause fiction**.


### 0.13.1 addendum to D37 — two defects the synthetic smoke could not see

**Both hid behind the same blind spot: every gate and smoke seeded records INSIDE the window.** A real phone's ordinary state — food logged days ago, nothing recent — was never exercised, so a `BUG1-aged` case now covers it.

**The full-ring meals artifact did not violate the lane-channel gate.** The arc traced to a real record (the last food); what was wrong is that **a gap filling the whole window renders as "meals everywhere"**, the inverse of its meaning. Such a gap is now **recorded but not drawn** — the centre tenant already states it, and an arc with no edge to read against carries nothing. Dashed arcs take **butt caps**; round caps on a 359.99° dashed arc overlap into a blob and scallop, which is what read as "off-centre" (measurement showed every circle sharing one centre). **Concentricity is now gated from the rendered SVG.**

**A sleep interval without a start is not an interval.** `signalTimeLabel` existed but was never wired, and the time field had no default, so the chip path stored `time: ''` records that could never draw. The field is labelled **Bedtime**, and such a record is now **rejected rather than silently stored**. Records already created this way remain, drawing nothing — honest absence, and the user's to delete.


## D38 — Sleep as toggled segments + badge-summoned centre controls (R16; Phase-4, 2026-09-02)

Real nights are fragmented. A single bed→wake interval forces a fiction; a live toggle captures the night as **segments**, and the **mid-night wake gap is itself signal**. `APP_VERSION → 0.14.0`; **schema unchanged at v5**.

**Toggle-on opens a pending segment; toggle-off closes it into an ordinary interval record** — byte-identical to the manual bed→wake path (gated). `sleep_hours` derives as the **sum** of a day's segments, one point per day rather than one per segment. The ring draws each segment on the sleep anchor with the **wake gap between them visible**. The **morning manual path remains**, and existing hours-only scalars stay valid and draw nothing.

**FORGOTTEN-OFF is the honesty core.** An open segment past **`SLEEP_OPEN_MAX_MIN` (11 h, surfaced)** becomes a **pending candidate** — *"sleep ended when?"* — resolved by the user with an end time, or discarded. **Never auto-closed, never auto-trusted.** Three-state grammar per D22, and while pending it **counts in nothing** (gated: `sleep_hours` sees zero points).

### Forks, as ruled

**A — the open segment lives in `settings.sleepOpen`.** It **must survive a mid-night reload**, and the check that settled it: **every piece of ring view state is module-level** (`RING_VIEW`, `LANE_FOCUS`, `RESOLVE_FOCUS`, `SWAP`) and the **D6 force-and-notify reload wipes all of it**. So the segment cannot live there. It is **live state, not a record**, so it sits beside the other persisted live state rather than as a half-record in the timeline (the shape D19 warned against). **Allowlist addition, no bump**; on D29's asymmetry test, losing it costs one re-entered bedtime. Gated against a simulated reload.

**B — a second toggle-on while open is a no-op.** Silently closing and reopening would **fabricate a segment boundary the user never marked**.

**C — a trivially short segment is KEPT, not discarded.** **Deciding a user's record is not real is a judgment this app has consistently refused to make**, and undo already answers the mis-tap. The undo is a **true inverse**: the record goes *and the open segment comes back* (gated).

**D — day ownership is the wake-day rule (D35 Fork A), unchanged, per segment.** A midnight-crossing segment still splits by clock onto the previous day's ring; both segments of a fragmented night belong to the wake day. **Recorded consequence:** a 14:00 nap therefore sums into the same day's `sleep_hours` as the previous night — correct as *total sleep that day*, and a deliberate choice rather than a side effect.

**E — the summoned-centre contract.** A lane may offer **one primary action**, summoned by tapping its legend badge; **only sleep builds one** in this slice. It **reverts on action, on idle (`GOAL_SWAP_MS`), or on tap-away — the centre never sticks in control mode**. A summon **cancels a goal swap** (one tenant at a time) and **returns the ring to "my day"**, because you are about to record actual data. **Highlight rides the summon** — one tap does both, a second clears both; **no long-press**, which is undiscoverable and fights mobile text-selection. A lane with no action highlights only. The control sits in the **centre**, never in R14's reserved annulus (gated).

**F — the live counter is deliberately stale.** An open segment shows *"sleeping · Xh"* in the resting centre and a pending arc on the ring, but **nothing re-renders on a timer**: at 0.1 h resolution the figure moves every six minutes, and a ticking timer is real battery cost for a number nobody watches. It updates on the next interaction.

### One shared helper changed, and it was a latent defect

**`nowTime()` was still on the real clock** while `nowMinutes()` was on the injected seam — so a toggle recorded a wall-clock start whose duration was then measured on a different clock. **In production both are the same clock, which is exactly why it could sit unnoticed**; it only surfaced under an injected clock. `nowTime()` now uses the seam, so D35 Fork C's "one clock indirection" is finally true of every path, and all logging paths become clock-injectable for future gates.


### 0.14.1 addendum (R17) — deletion, mini digests, and light mode

**A timeline record had no way out.** Deletion now goes through the same undo grammar as every other destructive action, restoring byte-identical at its original position.

**The minis never received the R13 redesign** — they inherited main-ring geometry, and `overflow:visible` let the now-hand and plan ticks draw outside the viewBox, which is why they overlapped. They are now **digests with their own geometry**: fixed pixel size, **two anchors only** (sleep span, eating window), no hand, no tracks, no centre text, and **every coordinate inside the box**, so spilling onto a neighbour is structurally impossible rather than merely unobserved.

**Light mode went unspecced because the palette was inline hex**, which can serve exactly one theme. Lane colour is now a **CSS custom property per category, defined for both themes** — light darker and more saturated against a white panel, the track themed alongside so an arc always has something to read against, and still no green in either set (Fork G). **Contrast is gated in both themes** rather than assumed from one.

**The grid density gate, unattested since 0.11.0, is closed.** It immediately caught a real 1 px `border-box` spill — and, before that, two flaws in my own measurements: a per-row metric that divided instead of counting, and an over-escaped regex that left contrast unmeasurable while still reporting a value. **A gate that cannot measure is worse than none, because it reads as a pass.**


## D39 — The summoned-centre contract, filled in across four practices (R18; Phase-4, 2026-09-02)

R16 built the contract generically but wired **only sleep**. R18 fills it in. `APP_VERSION → 0.15.0`; **schema unchanged at v5**.

**Why toggles rather than stamps, recorded as the load-bearing reason:** a live session yields a **true start time**, and **R14/R15's audit quality depends on t=0 being real**. A stamp records when you remembered, not when it began.

**Sauna, meditation and red light** gain toggles in sleep's grammar; **meals** summons the existing three-state fast resolve; **exercise and yoga get none**.

### Forks, as ruled

**A — `settings.sleepOpen` generalised to `settings.laneOpen`, keyed by lane**, with the old field folded in inside `normalizeSettings`. No bump. **Gated**: a 0.14.x blob with an open night emerges as `laneOpen.sleep`.

**B — several lanes may be open at once**, which is the point of keying by lane. R13.1 already stacks genuinely overlapping practice arcs, so red light *while* meditating renders honestly rather than being refused.

**C — midnight crossing** uses the wake-day rule per lane, unchanged.

**D — thresholds are per practice**: **sauna 3 h, red light 3 h, meditation 4 h, sleep 11 h**. One number could not plausibly bound both a sauna and a night's sleep. Each fires at its own constant and not before (gated), and a pending segment counts in nothing.

**E — meals offers an action only while a candidate is pending**; otherwise the badge highlights only. It is the **existing resolve relocated — no new semantics**.

**F — exercise and yoga get NO summoned action, as a ruling rather than an omission.** Their logging **carries a value** (a workout has a duration, often a distance) or **an attestation** (a regimen checklist row). A bare toggle would be **a second, thinner path to the same record** — the shape D19 warned against when it refused to store events as zero-calorie food items. **One record, one path.**

### A latent defect this slice exposed, and it predates it

**`boot()` took a same-version blob AS-IS and never ran `normalizeSettings`** — it patched settings with **ad-hoc per-key guards** for `fasting` (D22) and `nudges` (D25) only. So **every settings-side allowlist addition since D18 applied on RESTORE but never on BOOT**: `currency`, `signalUnits`, `primaryNutrient`, `sleepOpen`. It went unnoticed because each is read defensively with a fallback — **until one needed a real migration**, and the `sleepOpen → laneOpen` fold silently did not happen for the ordinary boot path.

**Boot now normalizes settings exactly as restore does**, and the two ad-hoc guards are subsumed and removed. Gated directly: after boot, the settings key set equals the default shape's. The general lesson is the one the assertion-count pin taught in another form — **a defensive read hides a missing normalization until something needs it to have run.**


## D40 — The photo-meal slice (R6; Phase-4, 2026-09-02)

Photo → **the user's own assistant** (copy template / paste JSON, the D11 flow; **no BYOK, no in-app calls, consulted exactly once per meal**) → a local **draft** → anchor by slider → save. **All recalibration is client-side arithmetic; there is never a second round trip.** `APP_VERSION → 0.16.0`; **schema unchanged at v5**.

**Cost declaration, recorded with the slice:** this build defers the lab-panel entry and curriculum voice pass (~1 week of queue), and assumes capture accuracy matters pre-distribution at a user base of one — justified because the correction-loop data it accumulates (`ai_grams` vs accepted) **only compounds with time**, so starting earlier is structurally better regardless of distribution timing.

### Template v3

`AI_TEMPLATE_VERSION` **2 → 3**, because the item contract changes. Per item: `name`, `grams`, **per-100 g macros only**, `scale_linked` (default **true**), and `dominance` ranked by the user's **declared** `primaryNutrient` — which D35's conflict-(ii) addendum made declarable **precisely so this slice could read it**. The template ships that nutrient inline, so the model ranks by what this user actually tracks.

**D8 holds absolutely: no micros from the photo path**, ever. Micros arrive later from the knowledge-layer corpus, keyed off identification. And **saved items stay `source: 'ai-paste'` at `eyeballed` confidence** — anchoring improves an estimate; **it does not make it weighed**. Both gated.

### The two rails

**SCALE.** Correcting an item's grams **pins** it. `r_i = user_grams / ai_grams`; the shared correction is **`R = exp(mean(ln r_i))`, the geometric mean recomputed from the FULL pinned set on every change** — so **order-independence is a property of the construction, not of luck** (gated: pin A then B is bit-identical to pin B then A). Unpinned `scale_linked` items display `ai_grams × R`; **non-`scale_linked` items never move**.

**Divergence.** If `max(r_i)/min(r_i) > DIVERGE_MAX` (1.5, surfaced), **propagation stops** and unpinned items read *"estimates don't share a scale — adjust individually."* **Fabricating a mean across disagreeing pins is prohibited** — the same refusal as inferring an arc, applied to arithmetic.

**IDENTITY.** A name re-pick swaps the **per-100 g profile**, **keeps the anchored grams**, and **recomputes that item only**. **Identity corrections never propagate** — shared-scale is a **geometry hypothesis, not an identity one** (gated). A pinned item **stays pinned**, and its ratio still holds because it is measured against the **original** `ai_grams`.

### Storage and staging, as ruled

**Four additive optional item fields** — `ai_grams`, `ai_identity`, `pinned`, `mealId` — as explicit `normalizeItem` allowlist entries (the `tzo` / `panelId` pattern). **No bump**: on D29's asymmetry test, losing them degrades a **future calibration input**, not authored content. All four round-trip export→restore, and a saved photo-meal item is **byte-identical to a manual item plus exactly those fields** (gated).

**A dedicated staging path.** `ingest()`'s four shapes are untouched; the paste produces a **draft** and **records are written only on Save**. A draft **deliberately does not persist** — unlike R16's open segment, it is one paste away from being recreated, and persisting it would put a non-record in the store for no gain.

**Saving with nothing pinned is allowed** — every item rides the raw estimate. **Reopen by `mealId`** restores the same widget; re-saving **replaces that meal's items only**, never another meal, and undo covers it.

**The correction loop is RETENTION ONLY.** `(ai_grams vs accepted)` and `(ai_identity vs accepted)` persist; **nothing computes from them in this slice**. Personal calibration is a named future slice.

### Residuals — named as the immediate follow-up, with the reason

Post-slider quick-add for oils, butter and sauces is **deferred rather than built**, and not for cost: shipping per-100 g constants for them would **introduce unsourced nutrition data into the one path D8 keeps most tightly bounded**. The honest source is the knowledge-layer corpus, which is explicitly out of scope here. Sourcing it from the user's own presets would be honest but dead on arrival, since presets ship empty. **It is the immediate follow-up, once there is a sourced place for the numbers to come from.**

**Out of scope, as ruled:** micros (knowledge layer), BYOK, the fast-food declared tier, and regimen auto-matching (suggest-then-confirm per D27, deferrable).


## D41 — Confirm-first (R6.1; presentation refinement of D40, 2026-09-03)

Presentation-only refinement of the shipped photo-meal draft. **D40's arithmetic is byte-unchanged** — no propagation rule, no schema touch, no new item field. What changes is what the draft **asks first**. `APP_VERSION → 0.16.1`; **schema unchanged at v5**.

### The contract

**The draft leads with a question on the dominant item:** *"AI estimated: Grilled chicken breast, 150 g (~5.5 oz) — confirm or correct."* One tap confirms (pins at the estimate); typing or sliding corrects (pins at the truth). The remaining items rescale by the shipped math and render beneath as the adjustable list. **Confirm first, sliders second — the interaction is a question, not a form.** The lead is `items[0]` after the shipped dominance ordering (a stable sort, so ties fall back to paste order): deterministic, no new selection rule.

**A confirmation is DATA, not a skip.** It pins at `r = 1.0` and records the correction-loop pair with `accepted == ai_grams`. **The existing storage already carried this**: a confirmed item has `pinned: true` with `grams === ai_grams`, while an item never touched has **no `pinned` field at all** (`normalizeItem` writes it only from a real `true`). *Confirmed correct* and *never looked at* do not collapse. No schema work was needed.

### Fork rulings

**A — ships standalone as 0.16.1.** Presentation-only and self-contained. R19 (capture flow) exists only as an unsent draft and arrives later as its own pre-registration; there was nothing to fold into, so nothing was guessed.

**B — storage stays GRAMS, end to end.** No oz input affordance, no unit setting. The **confirm line alone** shows dual units for **weight-shaped** items; the slider, the exact field and the record are grams. **Display-only, the D34 display/stored separation.** Rationale, as ruled: *people know steaks in ounces — the confirm question should speak the unit the user's knowledge is stored in, while the record speaks the app's.*

*Weight-shaped* is read from the shipped `scale_linked` flag: an item that scales with the plate gets the ounce hint; a fixed-size packaged item (a canned drink, a sealed side) is known by its package, not in ounces, and gets grams only. Below `OZ_MIN_G` (25 g) there is **no hint rather than one rounded to noise**. Decided here rather than escalated, since it follows from the shipped data.

**The R6 addendum's "grams/oz slider" phrasing is corrected to grams-only input** — no oz input was ever the intent. Recorded because grams-only shipped in D40 with no oz affordance built and none gated; the gap is now closed by ruling rather than left as a silent divergence.

**C — divergence reaching sooner is the FEATURE, and is gated.** Confirm-first pins the dominant item before anything else is touched, so a confirmation at `r = 1.0` plus a later correction past `DIVERGE_MAX` trips divergence and stops propagation — a state the shipped draft rarely reached. **If the steak is confirmed right and the potatoes are 60% off, the scene genuinely does not share a scale, and saying so is the whole point.**

**D — the lead renders only while the dominant item is unpinned.** A reopened meal whose lead is already pinned is **not asked again**; one saved unanchored still leads with the question. Read from existing state, no new flag.

### Reference-object guidance — RETIRED, as a prohibition

**The design's scale reference is the USER'S KNOWLEDGE, delivered through the confirm question — not props in frame.** User-facing photo help reduces to exactly *one plate, all items visible*.

**Audit finding: no such guidance existed in any shipped surface.** `index.html`, `app.js` and `README.md` carried no prop, framing or angle advice. That advice had been given **in conversation by the assistant, not by the app**. So the ruling lands as a **recorded prohibition plus a static gate** (`tests/check-guidance.sh`) rather than a deletion: it corrects the assistant, and fences the guidance out of the code before it can creep in. As ruled: *advice that only ever lived in conversation still deserves a fence if it contradicts the design.*


## D42 — Per-practice forgot-off thresholds, and the meals-lane full-ring defect (R18.1, 2026-09-03)

`APP_VERSION → 0.16.2`; **schema unchanged at v5**. Two changes ship together: a threshold table, and a render fix for a defect reported from the device.

### The meals-lane full-ring defect — diagnosed, not guessed

**Reported:** the meals lane drew as a full 360° dashed green ring on a day with an 0.8 h eating window and nothing logged yet.

**Reproduced headlessly before any code was touched**, by seeding the described shape against a pinned clock. The mechanism is **not** the eating-window span and **not** an empty-state gap — both of those hypotheses were tested and cleared:

| seeded shape | eat-lane arcs | lane covered |
|---|---|---|
| two meals 0.8 h apart yesterday, none today | eat 12°, open gap 86° | 27% |
| last meal 30 h ago (gap fills the window) | none — the 0.13.1 rule already suppresses it | 0% |
| **the device shape:** the same two meals **plus an older meal leaving an unresolved gap** | eat 12°, **fast/pending 263°**, open gap 86° | **100%** |

**The cause is the UNION.** The 0.13.1 fix guarded a *single* arc filling the window. Here a **pending fast candidate** and the **trailing open gap** are each legal, each well under the window, and **together they tile the lane** — and both are dashed (`.rpending` 5-4, `.ra-open` 4-4), so the result reads as one segmented ring meaning *meals everywhere*, the exact opposite of what it says. `arcPath` then clamps the span to 359.99°, closing the circle visually.

**The fix measures coverage, because coverage is the property that matters** — per arc **and** as a union (`EAT_FULL_FRAC = 0.97`; at 97% the remaining wedge is ~11 minutes of arc, which no one reads as a gap). When the lane is full, the **negative-space arcs** (`open`, `fast`) are withheld.

**Suppression withholds the DRAWING, never the record.** Suppressed arcs stay in the model, so the legend keeps the pending candidate **with its resolve buttons** and the centre still states the gap in words. **Ticks always survive** — meal dots at meal times are the honest render of a sparse day, and they are what the ruling asks for. A declared ghost is not counted or withheld: it is the plan's claim, not the lane's claim about what happened.

**Render-only, and gated as such:** no write path was touched and every meal record is asserted untouched in the same case. Coverage on the device shape goes **100% → 3%**.

### Per-practice forgot-off thresholds

Per-practice thresholds already existed as `LANE_ACTIONS[lane].maxOpenMin`; **the values were wrong** — three hours of red light is not a forgotten switch, it is a forgotten *day*. They now live in one surfaced table:

`FORGOT_OFF_MIN = { sleep: 11 h (unchanged), sauna: 45 min, meditation: 60 min, red_light: 40 min }`

Each is set just past a long-but-real session of that practice. `LANE_ACTIONS` and the retained `SLEEP_OPEN_MAX_MIN` both read the table, so a threshold lives in exactly one place.

**Past the threshold is a QUESTION, never an auto-close** — this was already the behaviour and is now explicitly gated at each practice's own number: the segment stays open, keeps its **true** start, writes nothing, and the centre asks *"&lt;practice&gt; ended when?"* with a time field. Closing at the threshold would write a duration nobody lived; **an invented end time is the same fabrication as an inferred arc (D19)**, and it would be indelible in a way the question is not. Gated six hours past the threshold too: still open, still unwritten.

**Yoga and exercise get no threshold** — D39 (R18 Fork F) gave them no toggle, so they cannot be left on. A lane that cannot be left on cannot be left on too long. If yoga ever gains a toggle, its threshold arrives with it.

### The 152-minute red-light record

**Deletable, with undo, and the undo restores it byte-identical** — verified end to end (record → rendered row with its delete affordance → delete → undo). **There is no edit-in-place for a timeline record:** the correction path is delete and re-log. Stated rather than implied, because "editable" and "deletable" are different promises.


## D43 — The meals-lane gap is bounded by FIGURE AND GROUND, not by closeness to 360° (R18.2, 2026-09-03)

`APP_VERSION → 0.16.3`; **schema unchanged at v5**. This corrects D42's fix, which was right about the mechanism it found and wrong about the boundary — the defect was still on the device after 0.16.2 shipped.

### What D42 missed

D42 measured **union coverage** at `EAT_FULL_FRAC = 0.97` and proved it against the union case it had reproduced. But **the common shape is a single trailing gap**, and a sweep of hours-since-last-meal shows what that draws:

| hours since last meal | drawn under D42 |
|---|---|
| 6 h | gap 90° |
| 14 h | gap 210° |
| 18 h | gap 270° |
| **20–22 h** | **gap 300–330° — a ring with a notch** |
| ≥ 23 h | suppressed |

Ate yesterday evening, look at it this evening: **20–22 hours, and the lane is a ring**. The union rule never fired because a lone gap plus a 12° eating window is 91.7%, comfortably under 0.97. **0.97 was a number chosen to describe the one case in hand, not the property being protected.**

### The rule

**`EAT_GAP_MAX_FRAC = 0.5`.** A negative-space arc (`open`, `fast`) draws only while it is **under half the lane**. The boundary is **figure and ground**: past half, the eye stops reading the arc as the gap and starts reading the **remainder** as the mark — so an oversized gap arc says the opposite of what it means. Under half it reads as a gap and is genuinely useful, which is why it is kept rather than removed outright.

**The information never depended on the arc.** `rhythmCenterHTML` states the gap in words unconditionally — *"22h since last logged food"*, or a date past 48 h — whether or not anything is drawn. Gated at every point in the sweep.

**Positive arcs are exempt, deliberately.** An eating window that really did span 14 h is two real meal times with **ticks at both ends**; shortening it would be the lie. A gap has no such endpoints — its far edge is just *now*. The full-lane rule (`EAT_FULL_FRAC`) still applies to any arc of any kind, and the union rule still guards arcs that are each under their own limit yet together tile the lane.

### The lesson, recorded

**A threshold set from the single case in hand is a threshold that fits that case.** D42's reproduction was real and its mechanism was real, and that made the number feel earned when it was not. The check that would have caught it — and now exists — is to **sweep the parameter rather than assert at one point**: `R182-gapsweep` gates eight positions from 6 h to 22 h, so the boundary itself is under test, not just one side of it.

The rendered gate had the same flaw: `ring-size-gate`'s sparse case asserted `< 97%` and **passed the reported defect at 91.7%**. It now asserts the rule the fix implements — no single arc past **half** the lane, total draw under 60% — and its seed was narrowed to the reported shape, because the wider seed included an older meal whose fast candidate pushed the union to 100% and let D42's rule handle it. **A gate seeded so that the old rule already passes cannot prove the new one.**


## D44 — "Clear this day" joins the undo grammar, and stops sharing the thumb path (R20, 2026-09-03)

`APP_VERSION → 0.17.0`; **schema unchanged at v5**. Two answers to a pre-distribution review of the day-wipe.

### 1. It was NOT undoable — and that was the wrong exception to make

`clearDay()` ran `window.confirm('… This cannot be undone.')`, emptied `items` and `water_l`, saved and toasted. **No `offerUndo`.** ~~Every other deletion in the app — an item, a timeline record, a photo-meal re-save — goes through the undo grammar (D22). **The whole-day wipe was the single exception**~~, and it is the largest destructive action there is, which makes it the worst place to hold one. The confirm text also *promised* the exception: it told the user the loss was permanent, which it did not have to be.

> **CORRECTION (2026-09-06, D54).** The struck sentence was **false when it was written**, and it stood in the governance log for three days. `deleteItem()` — the `×` on a food row, the most-used deletion in the app — spliced and saved with **no `offerUndo`**. The day-wipe was **not** the single exception; it was one of **two**, and the other one was the smaller, commoner gesture nobody thought to check.
>
> The claim was not merely incomplete, it was **load-bearing**: it was the argument for fixing the day-wipe ("every other deletion goes through the grammar, so this one must too"). An argument from a false premise reached a correct conclusion, which is the kind of luck that hides the next defect rather than exposing it — and it did: a food row stayed unrecoverable for three more days because the log said it was already safe.
>
> Recorded rather than quietly patched, because **a governance claim that was false deserves the same treatment as a false gate.** This log is read as evidence by future sessions; a sentence in it that is wrong will be believed. Fixed in D54, with the pre-fix behaviour reproduced against the new cases.

It now snapshots `items` and `water_l`, wipes, and offers the same undo toast as an item delete, restoring **byte-identical**. **The confirm stays** — a day is bigger than a row, and the two mechanisms answer different questions ("did you mean it?" versus "can you take it back?"). The text no longer claims permanence.

**The undo restores BY DATE KEY, never by object reference.** The toast lives seven seconds and a day is one tap away, so the user can page elsewhere inside that window; the restore has to land on the day that was cleared, not the day now on screen. Gated explicitly, including that the day it lands on is not touched.

### 2. The demotion — done now, not post-launch

The control was `width:100%`, `font-weight:700`, `color:var(--bad)`, **8 px below** the primary "End & complete this day" button: **a full-width red bar directly in the thumb path of the frequent affirmative action, at the same width and heavier weight.** That is the shape of a mis-tap, and first contact is exactly when someone reaches for "complete" without reading.

Judged **this slice** rather than post-launch: it is a CSS-and-one-wrapper change with a measurable gate, the review is pre-distribution, and the two fixes are the same concern — one lowers the cost of the mistake, the other lowers its likelihood. Shipping the undo alone would have left the trap in place.

**Kept on the day surface rather than moved to settings.** Clearing a day is a legitimate rare action, most likely during first-contact experimentation ("I typed nonsense in, wipe it"); burying it would make a reasonable act hard while barely reducing the mis-tap, whose cause is proximity and size, not presence. It is now centred, auto-width, 12 px, unbolded, muted at rest, separated by 26 px, and carries the destructive colour only on press — where the intent is already deliberate.

**Measured, not asserted.** `R19-demote` reads the **shipped shell, laid out** in the harness iframe: narrower than 60% of the affirmative control, ≥ 16 px of separation, smaller font and lighter weight, and a different rest colour. *"It has a different class"* is not the property that stops a mis-tap. **Proven against the defect:** restoring the previous CSS fails three of the four.


## D45 — BYOK vision calls: a bounded exception to D11's "no in-app AI calls" (R21, 2026-09-04)

**Controlled single-user prototype**: one user, their own xAI key, their own device. **Not a cohort feature.** Everything runs client-side or against that key; **no server of ours exists or is created**. Distribution to testers is deferred, so this is a full build, not a fenced one.

### The exception, and its bounds

The app **MAY** call a user-supplied vision endpoint, **only**: (a) with a key the user entered themselves, (b) on an explicit capture-send, (c) sending only the meal photo and the perception template — nothing else. **The share-sheet/paste path (D11) remains** as the no-key fallback. **BYOK is an addition, never a replacement**, and every failure lands back on it.

### Key hygiene — by construction, not by rule (Fork F, ruled)

**The key never enters `APP_STATE`.** It lives in its own localStorage key, `healthtracker-byok`, alongside its own per-day counter. This is the whole rule, and it is structural: **export, the D3 pre-restore backup, and restore cannot carry the key because it is not in the object they serialize.** An exclusion filter would have been a rule a future normalizer change could quietly break — and `normalizeSettings` is an allowlist rebuild that has surprised this project once already. A structural fact needs no vigilance.

The remaining hygiene rules, each gated: never in code, never committed; **never written to any log, console, toast or error string** — including the failure paths, which is where keys usually leak; **egress only on an explicit capture-send**, never in the background.

**Photo hygiene:** the image is held in memory for the call only. **Never persisted to any store, never in any export.** The downscale touches only the bytes that are sent.

**The service worker explicitly bypasses the call** (Fork G, ruled). A cross-origin POST is not cacheable *by default*, and "by default" is not "never".

### Provider-agnostic, with a verified contract

A provider table `{ label, base, model }` keyed by name; the call is OpenAI-compatible so a second provider slots in **without a code change** (gated). Ships with xAI/Grok configured.

**Verified live 2026-09-04, and the verification changed the answer.** xAI's image-understanding guide documents `{"type":"input_image","image_url":"…"}` with `input_text` — the **Responses API** shape. Sent to `/v1/chat/completions` that is **rejected** (`data did not match any variant of untagged enum Content`), while the **OpenAI-classic** `{"type":"image_url","image_url":{"url":"data:…"}}` parses. **Following the documentation alone would have shipped a payload the endpoint refuses.**

**Pre-registered contract:** `POST https://api.x.ai/v1/chat/completions`, `Authorization: Bearer <key>`, OpenAI-classic content parts, model `grok-4.6`, image as `data:image/jpeg;base64,…`. Limits per the guide: 20 MiB, jpg/png. **CORS is open** (`access-control-allow-origin: *` on both preflight and POST), which is what makes a browser-only call possible at all.

**Model-string validity and rate-limit behaviour cannot be verified without a key** — they are checked after authentication. **"Test connection" is the verification mechanism**, and it surfaces the provider's own error text, never the key.

### D8 holds absolutely — actively refused, not passively dropped (Fork H, ruled)

The model returns **identification and macros only**. Micros are **never requested and never accepted**. The v3 parser has no micros field, so they would be dropped as a side effect — **dropped as a side effect is not the same as refused**. The parser now **detects and strips them explicitly and says so**, the same "stripped and reported" contract the ingest path has, on **both** paths. Gated with a micros-bearing response.

**Micros are out of scope, seam only:** identification strings are retained (`ai_identity`, already shipped) so a future knowledge-layer corpus can populate micros with coverage masks. **This slice ships macros. A macros-only anchored meal is the honest deliverable**, and fabricating micros to "complete" it is prohibited.

### One downstream, not two

A valid response routes **straight into the shipped confirm-first draft** (R6/R6.1) — no paste step. Everything after it — anchor, pin, divergence, identity re-pick, save, correction-loop retention — is **unchanged and already built**. The load-bearing gate is **R21-parity**: identical item JSON produces a **byte-identical draft whether it arrived by call or by paste**.


## D46 — "Test connection" could finish without saying anything (R21.1, 2026-09-04)

`APP_VERSION → 0.18.1`; **schema unchanged at v5**. Reported from the device against 0.18.0: key saved, Test connection tapped, **nothing rendered — no success, no error, no spinner.**

### What the live page actually does

Driven with CDP against the **live 0.18.0 build**, with a deliberately fake key (a rejection proves the round trip happened):

| question | answer |
|---|---|
| a request to `api.x.ai`? | **yes, two** — the preflight and the POST |
| status | preflight **200**, POST **400** — **no `loadingFailed`, no CORS error** |
| console | no CORS, no `Access-Control`, no `Failed to fetch` |
| status line | rendered at t0 and t12 |

**So the network path is sound and the code is not silent on desktop.** The silence is presentational, and it is legible in the old markup: the outcome rendered as `<div class="note bad">`, and **`.bad` was only ever defined for `.ireport`** — so a failure painted in the *same 12 px muted grey* as the help paragraph directly beneath it, with no spinner and no colour. To an eye scanning a phone, a new grey line above an existing grey paragraph is not an answer. **The harness could not have caught this: the harness reads strings, and a person reads a page.**

### Three real defects on that path, any one of which produces exactly "nothing happened"

1. **No `.catch`.** A throw anywhere in the `.then` — `renderByok()` included — became an unhandled rejection, and unhandled rejections are invisible.
2. **A disabled button.** `byokSave` reported `configured` from the key's **length**, not from whether the write **landed**; a failed write was masked by the in-memory fallback until the next reload, after which the key was gone, the button rendered `disabled`, and tapping it did nothing at all.
3. **No distinct timeout.** The call's own 45 s bound is far longer than anyone waits before deciding a button is broken.

**The fix is one rule, not three patches: every exit from `byokTest` paints.** Pending (with a spinner) the moment it is tapped; success naming the model that answered; failure in the provider's own words; timeout at **15 s**; a throw; and "no key saved" — because **the button is never disabled again: a disabled button is the silence.**

### xAI answers a bad key with 400, not 401

Verified in the same run: the live response is `400` with *"Incorrect API key provided. You can obtain an API key from https://console.x.ai."* Classifying on the status code alone filed **the single most likely failure** under a generic HTTP error. The classifier now reads the provider's message as well, and surfaces it verbatim. Gated both ways — a key-shaped 400 is `auth`, a `Messages cannot be empty` 400 stays `http`.

### R21.1 — key shape check and persisted status

A **shape** check, not a validity check: only the provider can say whether a key *works*, which is what testing is for. Blocking rules are the ones certainly wrong for any provider — empty, embedded whitespace, implausibly short. **A prefix that does not match the provider's usual one warns and saves anyway**: key formats change, and refusing on a guess is a worse failure than the one it prevents.

Status — `unverified` / `verified` / `failed`, with a timestamp and the failure message — is **persisted beside the key**, so it stays out of the log and out of the export, and it shows in settings and on the capture surface. **Replacing the key resets it to unverified**, because a new key has not been verified.


## D47 — Capture could do nothing at all, and the decode is where it stopped (R21.2, 2026-09-04)

`APP_VERSION → 0.18.2`; **schema unchanged at v5**. Reported from the device against 0.18.1: **Capture meal never fires** — "used today" stays 0/20, the provider console shows no call, nothing renders.

### The tell was in the report

**`used today: 0`.** The counter increments *after* the decode and *before* the send, so a stuck counter says the chain stopped **inside the decode** — upstream of the POST, exactly as reported. Test connection working confirms key, auth and endpoint are fine.

Driven through the shipped shell's own input and handler, the chain **does** complete on desktop: change → handler → decode → POST → draft. So the decode is failing on the device specifically, and the original `byokDownscale` had three ways to fail there **quietly**:

1. **Neither `onload` nor `onerror` fires.** An unsettled promise is an invisible one, and the whole capture simply stops. **The decode is now bounded by a timeout.**
2. **A 12 MP photo exceeds iOS Safari's canvas limit** and `drawImage` yields a **blank canvas with no exception**. `createImageBitmap` now resizes without ever allocating the full-size bitmap, and **the output is sanity-checked** — a blank canvas encodes to almost nothing, so an encode under `BYOK_MIN_DATAURL` throws instead of being sent as a meal.
3. **An HEIC frame from the photo library decodes nowhere** in a browser. That is now **named** — *"Set the camera to Most Compatible, or use Copy prompt"* — rather than surfacing as a mystery.

### The decoder is on a short leash, because the first fix hung the harness

`createImageBitmap` is preferred (it is what survives a large photo on a phone) but it gets **5 seconds** before the `Image` path takes over. That bound is not hypothetical: the first version of this function, without it, **hung the test suite exactly the way the button hung the device** — and the runner caught it as *"no SUMMARY line (the suite did not finish)"*.

**Harness limitation, recorded rather than hidden:** `createImageBitmap` **never settles** under `--virtual-time-budget` — neither resolve nor reject, while timers around it fire normally (measured directly). **The suite therefore cannot exercise the preferred decoder at all.** What it proves is the leash, the fallback, and that every outcome is visible. The preferred path's first real exercise is on the device.

### Capture can no longer end in silence

The old handler could **return in silence** — no file, no message, indistinguishable from a broken button — and it cleared `input.value` **before** the read, which on iOS can invalidate the very File it was handed. It also returned nothing, so no caller could await it.

Now: **something is on screen the instant a photo comes back**, the stage is named as it changes (*reading* → *sending*), and the input is cleared only **after** the read completes. Every terminal outcome is visible, and the state paints **on the capture surface** as well as in the draft — the draft sits below two textareas, which on a phone is off-screen, and off-screen is its own kind of silence.

**Gated as an invariant, not as a list:** for no-file, a non-image, an empty file and an HEIC frame, each capture must end in **a fired request or a visible message**. Never neither.


## D48 — Two clocks: a model reading a photograph is not a one-word ping (R21.3, 2026-09-04)

`APP_VERSION → 0.18.3`; **schema unchanged at v5**. From the device: capture now fires — decode, encode and send all work — and the counter moves 0 → 1/20. **The failure is a timeout on the vision response**, and it was **ours**: the app aborted a call that was still working, having already paid for it.

### The budget was one number for two different calls

`BYOK_TIMEOUT_MS = 45000` covered both a one-word text ping and a model reading a plate of food. **One number cannot be right for both.** They are now separate:

| call | budget | why |
|---|---|---|
| connection test | **15 s** (unchanged) | a one-token ping; longer just delays a verdict |
| capture | **120 s** | the model reads a photograph and returns structured JSON |

**120 s rather than the ~60 s proposed.** 45 s had *already* failed, so 60 s is a thin margin over a bound known to be too low, and a second timeout costs another call. The cost of waiting is now bounded by what the user can **see** — the wait is counted on screen and can be cancelled — while the cost of giving up early is a call already charged for and thrown away. **The asymmetry favours waiting.**

The ping's own abort is bounded by the **test** budget, not the capture one: otherwise it would sit behind the 15 s race and never be the thing that fires.

### A long wait must look alive

The pending line now **counts the elapsed seconds** — *"Sending to your provider… 23s"* — beside the spinner, and it renders on the capture surface. A slow answer therefore looks slow, which is the truth, rather than dead. **And a two-minute budget must never trap anyone: there is a `cancel`**, which abandons the wait and says the photo is still in hand.

### A timeout is not proof the call did not happen

The message now says so: *"The provider did not answer within 120 seconds. If it answered afterwards, that call still counted — check your provider console."* **An aborted request is not an unmade one**, and a user deciding whether to retry deserves to know which they are looking at.

### What I could not check

**The provider console is the user's, not mine.** Whether the earlier call completed with a 200 after the app gave up is answerable only from that console — and the raised budget answers it in practice: if a capture now succeeds at, say, 55 s, the call was always completing and the bound was the whole defect.

## D49 — One persisted fact, and the writer that ate it (R21.4, 2026-09-04)

`APP_VERSION → 0.18.4`; **schema unchanged at v5**. Reported from the device against 0.18.3: Test connection went green — *"Connected — grok-4.6 responded"* — and Capture meal then read **"key not tested yet."** A genuinely tested key treated as untested.

### The reader was never the problem

Both surfaces already read the same field. `byokTest` persisted `status` beside the key, and `renderCaptureBtn` read `byokSettings().status`. The suspicion in the report — *"capture checks a different flag than the test sets"* — was the natural one and was wrong.

**`byokCount()` erased it.** It rebuilt the whole stored blob from its own four-field list:

```js
byokWrite({ provider: s.provider, key: s.key, cap: s.cap, used: {...} });
```

No `status`. The counter increments **inside the capture**, between the decode and the send, so the verified state was destroyed **while the user watched the capture run** — which is exactly why the two looked causally linked, and why the report reads as *"capture blocks."*

**This is the pattern D45 warned about, one function below the warning.** D45 kept the key out of `APP_STATE` structurally rather than by an exclusion filter, on the grounds that *"`normalizeSettings` is an allowlist rebuild that has surprised this project once already."* The BYOK store then grew its own allowlist rebuild, and it surprised us the same way inside a single slice.

### The fix is a merge, because a rule is what failed

Every writer now goes through **`byokPatch(patch)`** — read, assign the named fields, write. `byokSetStatus`, `byokSave` and `byokCount` all use it, and nothing else writes the store. The old contract was *"remember to carry the other fields"*, which is a rule; **a merge cannot forget**, including fields no writer has been taught about yet. Gated with a field no writer knows.

**Replacing the key still resets the status to `unverified`** — merging must not preserve a verdict about a *different* key. That is the one place the rebuild was doing real work, and it is kept explicitly.

### A capture is a verdict on the key too (the other half of "one source of truth")

The status meant *"what the Test connection button last saw."* It now means **"what the provider last said about this key"**, whichever call asked:

| capture outcome | status |
|---|---|
| a reply | **verified** — the provider answering is the proof, and no button has a monopoly on it |
| `auth` rejection | **failed**, in the provider's words |
| timeout, network, rate limit, unparseable body | **unchanged** — none of them is a verdict on the key |

That last row is the load-bearing one. A 120-second timeout (D48) says nothing about whether the key works, and demoting on it would manufacture a failure out of a slow model.

### Capture was never gated on the status — and the line still read as a gate

Worth stating plainly, because it was the reported symptom and the code disagrees with it: **`byokCapture` has never checked the status.** Its only guards are "a key is saved" and the daily cap. Nothing blocked.

But a bare status line sitting directly under **Capture meal** reads as a **precondition**, and after a capture that had *also* failed on the old 45-second budget, "key not tested yet" was the nearest available explanation. The presentation was making a claim the code did not.

So, per the interim-safety instruction: **an unverified or failed key is never stated without an offer to settle it.** The line now carries an inline **verify now** that runs the test on the capture surface itself, with the pending state and the verdict painted there — no trip to Settings. A verified key is offered nothing, because it is settled and an offer would be noise. **Never a status without a path forward**, and still never a gate.

### R21.1 verification, as asked

Its two halves were **both shipped and one was being overwritten**. The shape check on save (empty / embedded whitespace / implausibly short block; an unexpected prefix warns and saves) is complete and gated. The persisted `unverified` / `verified` / `failed` with timestamp and failure message is complete and gated. What R21.1 lacked was a gate on the **invariant** — it gated the status against the writers that existed when it was written, and R21.2/R21.3 then added one that ate it. A per-writer gate would have rotted the same way; **the invariant is now what is gated: no write to this store may cost the status.**

### Two gates had rotted at midnight, and that is a separate finding

The suite was **red before this fix was written** — 837 of a pinned 1149, two aborts — and `ring-size-gate.ps1` measured an empty meals lane. Neither was a product regression. `ensureToday()` calls **`localDate()` with no argument**, which reads the real `Date`, **not the `setClock` seam**; so a date-pinned case can fix the clock but its booted `current` is always the real today. Both gates were authored on 2026-09-03 and stopped describing their own scene at midnight.

Patched at the call sites (the harness and the ring gate now pin `current` explicitly, and say why). **The root fix — `ensureToday` reading `todayKey()` so one clock governs — is NOT taken here**: it is a product change outside the reported defect, and it is the user's to rule. In production `_clockFn` is null and the two are identical, so it is a no-op at runtime and a real repair to the seam. ~~**Open ruling.**~~ **RULED 2026-09-04: take it — see D50, which also corrects the count: it is 21 call sites, not one.**

## D50 — One clock, and it was 21 call sites rather than one (R21.4 addendum, ruled 2026-09-04)

`APP_VERSION → 0.18.5`; **schema unchanged at v5**. Closes the open ruling at the end of D49.

### The fix moved, because the diagnosis was too small

D49 named `ensureCurrentDay()` and described the repair as one word at one site. **That was under-counted.** `localDate()` takes an optional date and defaults it with `new Date()` — and there are **21 bare `localDate()` calls** in `app.js`. Every one of them consulted the real wall clock while the rest of the app ran on `setClock`. `ensureCurrentDay` was simply the one whose damage was visible.

So the default argument is what changed, once, at the definition:

```js
function localDate(d) { d = d || nowDate(); ... }
```

`nowDate()` is `new Date(nowMs())`, and `nowMs()` is `_clockFn ? _clockFn() : Date.now()`. **`setClock` is a test seam and is never called by shipped code**, so in production `_clockFn` is null and this is `new Date()` exactly — a runtime no-op. `localDate()` and `todayKey()` are now literally the same expression, which is **pinned by a gate** so they cannot drift apart again.

**Fixing the definition rather than the caller is the point.** Patching `ensureCurrentDay` would have left twenty sites reading a second clock and a third gate free to rot the same way later.

### What it repairs, and the evidence

Both gates in D49's finding stopped describing their own scene at midnight because they could fix the clock and still boot onto the real today.

- `ring-size-gate.ps1` **no longer pins `current` at all.** Its seed sets the clock before boot, and the day on screen follows — so the gate is now this fix's evidence in a real browser against the shipped app. Reverting D50 empties its meals lane back to `paths=0 dots=0`.
- The data-layer harness **still pins explicitly** in the R181-eatring block, because that block boots first and fixes the clock afterwards. That is the block's own ordering, not a seam problem.

**Verified against the defect:** reverting the default fails the three `D50-seam` assertions and the ring gate's real-browser measurement simultaneously.

### Why this ships with a version bump and a changelog line that says "nothing to see"

D6 makes `APP_VERSION` bump whenever the shell changes, and the shell **did** change: `app.js` bytes differ, the SW cache name is re-derived, and users take an update. A no-op change that still ships an update deserves an honest note rather than a silent one or an invented feature. **The changelog says there is nothing to observe, because there is nothing to observe.**

### Scope, stated plainly

This is a **test-seam repair**, not a product fix — nothing a user can see behaves differently. It is logged as a decision because it changes shipped code, and because the class of failure it removes is one this project has been bitten by before: a gate that stops testing what it claims to, while still printing green.
## D51 — The capture outcome owns the screen: one modal, three states (R21.5, 2026-09-05)

`APP_VERSION → 0.19.0`; **schema unchanged at v5**. A presentation ruling, no data contract touched.

### What was wrong was never the logic

Every capture already ended in a definite result. It ended it **in the wrong place**: the draft rendered inline in the entry sheet, beneath the prompt textarea and the ingest textarea, which on a phone is off the bottom of the screen. D47 named that exactly — *"the draft sits below two textareas, which on a phone is off-screen, and off-screen is its own kind of silence"* — and worked around it by painting the state on the **capture surface as well**.

**That workaround was the wrong shape, and this slice retires it.** Two surfaces telling the same story is not the fix for one of them being invisible; a surface that *cannot* be invisible is. And once the modal exists, the second copy is worse than redundant: it is a second outcome state, which is precisely what the gate forbids.

### The three states are exclusive by construction, not by agreement

One modal, one state, resolved in one place:

| state | when | body | actions |
|---|---|---|---|
| **success** | a draft exists | the confirm-first lead, sliders, live totals | **Save meal** · **Discard** |
| **pending** | `BYOK_BUSY.phase === 'sending'` | spinner + the counted seconds (D48) | **Cancel** |
| **failure** | `BYOK_BUSY.phase === 'error'` | the message, in the provider's words | **Try again** · **Paste the response manually** |

A draft **outranks** a stale pending line: the answer arrived, whatever the last message said. Because the state is a property of one function rather than a negotiation between three surfaces, *"exactly one outcome is shown"* needs no vigilance to stay true.

### The footer does not scroll, and that is the whole point

Save and Discard moved **out of the draft markup** and into a fixed footer. At the end of a list they were reachable only by scrolling past however many items the model returned — and a primary action you must hunt for is one an anxious user does not find. Gated at three widths with a nine-item list: the body scrolls, the footer does not.

### A success cannot be dismissed; a failure can

The scrim and the close button dismiss a **failure** — nothing is lost by closing it. They do **not** dismiss a **success**: a draft closed by a stray tap is a meal silently thrown away, which is the exact class of silence this slice exists to remove. Save or Discard, and no third exit. Pending is not dismissable either; it has a cancel, which says what it does.

### Both paths keep one downstream (R21-parity, preserved by construction)

`#photoDraft` **moved**; the draft markup did not change. The paste path and the call path still come through `openPhotoDraft` into the same element, so a pasted reply opens the same modal with the same actions. Giving the call path a modal and leaving paste inline would have split the one downstream D45 made load-bearing — the parity gate is unchanged and still green.

### "Try again" re-opens the picker, and that is deliberate

D45 holds the image in memory **for the call only**. Keeping it alive across a failure so a retry could replay it silently would stretch a ruled hygiene bound for convenience, so it does not: **Try again re-opens the picker**, and the modal says so. Re-picking costs one tap; the bound stays intact. **Open option, not taken:** keeping the decoded data URL in memory for the lifetime of the failure modal only would make retry a true replay. That is a hygiene amendment and is the user's to rule.

### What the gates learned, twice

Two of my own assertions were placed where they could not fail, and both were caught by reproduction rather than by review:

1. The `capture-outcome-gate` fixture hand-rolled a reply with **flat macros instead of `per100`**. The parser rejected it, the capture fell to the failure state, and the gate measured **the failure state while reporting on success** — passing footer assertions for the wrong buttons. A fixture the parser refuses is not a fixture.
2. The harness assertion that the capture surface carries no duplicate ran **only during success**, when `BYOK_BUSY` is null and a duplicate could not render anyway. Restoring the old second paint left the suite **fully green** while the visual gate failed on all three viewports. The assertions now run in the pending and failure states, where the defect actually lives, and they fail against the reverted code.

Both are the 0.13.0 lesson again — *the gates that missed the first meals-lane defect all seeded records inside the window* — this time in the test code rather than the product.
## D52 — Ordinal scales: a general contract, first used by Bristol (R20, 2026-09-05)

`APP_VERSION → 0.20.0`; **schema unchanged at v5** (Fork I). Ten forks ruled as argued. **Three of the rulings corrected the brief**, and are recorded as corrections rather than as choices.

### The two general rules

These are the deliverable. Bristol is the first instrument to use them; the next ordinal — a symptom scale, RPE, a mood scale — inherits them without a new ruling.

**Rule 1 — SNAP, NEVER INTERPOLATE.** An ordinal's points are **ranks, not quantities**. Bristol defines seven forms and says nothing about the distance between them, so a 3.5 is not a value the instrument can issue. The entry control offers only the defined stops; every ingest boundary either lands on a stop or **drops the value to absent**.

**Dropping, not rounding** — and the precedent is already in the log. Rounding a pasted 3.5 to 4 would "launder noise into a real-looking zone", which is exactly what **D29 Pin 2** forbids for out-of-range `tzo`. The same reasoning applies to ranks: a rounded 3.5 is an observation nobody made. The slider clamps (a drag between stops carries no data to launder); the *boundary* rejects.

**Rule 2 — ORDINAL STATISTICS ONLY: median, mode, min–max, n. Never a mean, never a delta.** The mean of ranks fabricates a quantity the scale never defined, and "Δ +2" asserts that type 5 minus type 3 is two units of something Bristol does not name.

**With a trap inside the rule:** the median of an even count, computed naively, averages the two central ranks — and reintroduces exactly the 3.5 the contract forbids. This is the **lower median**: always an actually-observed rank. A tie in the mode reports **both** modes rather than picking one.

### The correction that produced Rule 2 — and a third general rule

**DISPLAY-TIME COMPUTATION IS A GATE SURFACE.** The brief's gate — *"no non-integer type is ever stored"* — was airtight at entry and blind to everything downstream. Registered as an ordinary biometric, a `bm` series would have inherited `seriesSummary` and rendered **"avg 3.5"** in the trend row: the exact forbidden number, computed at render time **from perfectly integer stored values**.

**Entry-gating a value does not protect a derived display of it.** A gate on a value's honesty must read **stored *or* rendered**.

This is now demonstrated rather than asserted. Deleting the ordinal branch from `renderTrends` fails the four `R20-snap-render` cases **while every storage case stays green** — the storage gates report success with the forbidden number on screen. That is the shape of the hole, reproduced.

Its third instance, in pixels rather than numbers: a **polyline** between type 3 and type 5 draws a continuous path through 3.5 and 4.5. The line states in geometry what the summary may not state in text, so an ordinal plots as **dots**. Same rule, different encoding — the same argument D24 made when it refused a met/unmet colour as "good" re-encoded past the M7 grep.

### Corrections to the brief, recorded as corrections

**(1) The gate-scope hole** — above. The brief's gate would have passed while the app printed 3.5.

**(2) Fork C — the brief contradicted itself.** It specced the slider poles as *"hard / constipated"* ↔ *"loose / diarrhea"*, and four points later forbade "constipated" as a verdict. The poles are now **the scale's own end descriptors** — *"separate hard lumps"* ↔ *"watery, no solid pieces"*. Better sourced, and it removes the clinical word from the surface entirely rather than carving an exception into M7 — an invariant whose whole value is that it has none. Gated with a planted control on the clinical word itself.

**(3) Fork H — the citation did not say what the brief claimed.** Lewis & Heaton 1997 (*Scand J Gastroenterol* 32:920–4) validated the scale as a proxy for **whole-gut transit time** — types 1–2 slower, 6–7 faster. **It does not assert a target form.** The 1–2 / 6–7 boundaries are **Rome IV's** bowel-habit subtyping. Both are cited, each for the claim it actually supports, in the D32 manner.

**And following that ruling to its conclusion changed the number.** The brief named 3–4 as the reference band. Rome IV subtypes at 1–2 and 6–7, so **the range those boundaries leave is 3–5**, three forms wide. "3–4" is a common convention with no source here asserting it, so it is not what the app draws. The app states the boundaries and says plainly that the middle is *"not a target either source asserts"*.

Per **D24** the band renders on fully neutral footing: factual text and citations, **no met/unmet cue, ever**. The standing *"worth discussing with your doctor"* line is **context that renders regardless of any reading** — never a per-entry verdict.

### The remaining rulings, as argued

**Fork E — `type: 'bm'`, `kind: 'biometric'`, and it is a data-integrity question.** `kind` is a closed enum and `normalizeSignal` coerces anything outside it: a `kind:'bm'` record is silently reclassified to `event` by any app that does not know the value, permanently and without error. As an unknown *type* on a known *kind* it round-trips intact and renders nowhere. **This is the D35 sleep precedent exactly.** Gated on `future_scale` — a type this app genuinely does not know — because asserting it with `bm` would prove nothing now that a `bm` spec exists here to recover the kind from.

**Fork A — the chip sits in the first six**, and *placement is the whole question*: the touch strip is one scrolling row, so a chip appended at the end is off-screen until you scroll, for the one signal logged with the phone barely in hand. `chip-layout-gate` re-pinned **14 → 15** deliberately — and, having just learned this twice, it now **measures reachability** rather than trusting an array index: the bm chip's rect must sit inside the strip's visible box at `scrollLeft === 0`. Measured at `idx=1`, reachable.

**Fork B2 — no ring tick this slice.** The lane budget is at its ruled maximum and `laneGeometry` spends the remainder as whitespace: a fifth lane cuts inter-lane gaps from **4.84 px to 2.03 px** (or 3.12 px for a thin track), and `ring-size-gate` measures **strokes, never gaps**, so it would have stayed green through it. With R14's claim on the reserved annulus still unsettled, spending the last whitespace on the newest signal is the expensive order. **Nothing is lost:** the record carries `time`, so the tick is addable later from data already stored.

**Fork D — the note is present but secondary.** `notes` already exists on every signal record, so this cost no schema change; the two-tap path never touches it.

**Fork G — the band is `bm`-local**, reusing the `{org, cite, version, applicability}` shape rather than wiring a signal into `LAB_SPEC`. D34's fence holds — *"ApoB does not belong beside Sauna"*.

**Fork I — no bump**, on an argument stronger than D29's: an older app does not even strip these records, it preserves them unrendered.

**Fork J — `AUDIT_WINDOWS` is a decision-log reservation, not a constant.** It does not exist in `app.js`; no code lands. The two candidate pairs, recorded here for R15:

| stimulus → response | window | status |
|---|---|---|
| psyllium → bm form | ~24–48 h | **uncited** — plausible from transit physiology; no source registered |
| fast ≥ 72 h → transit disruption / recovery | to be set at R15 | **uncited** |

Both are **named candidates, not built and not asserted**. Per D37 an uncited pair must be *labelled* uncited wherever it eventually surfaces.

### One contract, one path

Entry writes the snapped integer into the existing `#sigValue` and submits through `addSignalFromForm → addSignal`. **No new record-write site**: the D29 census stays at 14, unchanged.
## D53 — Provenance collapses, safety does not; and a touch target is a zone, not a handle (R20.1, 2026-09-06)

`APP_VERSION → 0.20.1`; **schema unchanged at v5**. Presentation and accessibility; no data contract touched.

### The general rule: PROGRESSIVE DISCLOSURE OF PROVENANCE

**Citation and provenance text is AUDITABLE, NOT CONTENT.** D32 requires a claim to be **sourced and the source reachable**; it never required the source to be **permanently on screen**. Fine print that always shows costs attention on every glance and earns it only on the glances where someone is actually auditing.

**The boundary is the whole rule, and it is not "small text folds":**

| folds | stays visible |
|---|---|
| who said it, which paper, which version | anything constraining how a number may be **read** |
| how two sources differ methodologically | applicability and scope ("statin-indicated patients") |
| | "this app does not know your risk category" |
| | "figures only, no interpretation" |
| | "worth discussing with your doctor", and every warning |

**A qualifier that stops a figure being misread is not provenance — it is the safety statement wearing small type.**

Implemented as `citeBlock()` over a native `<details>`: every word stays **in the DOM at all times**, opens in **one tap**, and is keyboard- and screen-reader-navigable for free. Closed by default, because the default is the non-auditing glance.

**Gated by deletion, which is the sharp form of the test.** The cases strip every `<details class="cited">` block from a surface and assert on what remains — that is what a reader sees before touching anything, and every safety phrase must be in it. With a planted control: a safety line deliberately folded **does** trip the check, so it is not vacuous.

**One boundary call worth stating, because it went the other way from the brief's list.** The CCS overlay's **applicability text does not fold.** D32 made it load-bearing precisely so a risk-stratified figure can never read as a universal cutoff — three tiers stated in full. That is scope, not provenance. Only the paper reference folds. The brief said "guideline citations", and the applicability is not a citation, so this is the ruling applied rather than departed from.

**Applied to:** the bm sources (the claim and the doctor line stay); lab band citations; the lab overlay's paper reference; the vitamin-D Health Canada/IOM methodology note; the BYOK key-and-photo handling paragraph (the live "used today" counter stays — it is state, not provenance).

**Surveyed and proposed, NOT applied** — the brief asked for a proposal:

| candidate | verdict |
|---|---|
| scanner note: *"Nutrition is community data — verify it against the package label"* | **split**: the provenance half folds, the *verify* instruction stays. Worth doing. |
| lab-entry note: *"Values with a cited Canadian target show it; every value can also carry your lab's own printed interval"* | **fold** — methodology explanation. Worth doing. |
| labs footer: *"Reference ranges differ by laboratory and by person; these are worth discussing with your doctor"* | **do not fold.** The methodology half is fused into the safety sentence; splitting risks weakening a safety line for a small gain. |
| trends footer: *"figures only, no interpretation"* | **do not fold** — scope. |
| ingest note: *"AI-paste items are macros-only (micros stripped) at eyeballed confidence"* | **do not fold** — it states what the record means, which prevents misreading it. |
| the entry sheet's explanatory notes (how each feature works) | **out of scope.** These are *help*, not provenance. Folding them is a different slice; propose separately if wanted. |

**Amendment (2026-09-06, v0.20.2): both "worth doing" candidates taken.** The cut in each case is where the sentence changes job, not where the paragraph ends:

- **Scanner note.** Folded: *"Looks up OpenFoodFacts, cache-first. Nutrition there is community data, contributed by other people — it can be wrong or out of date."* Kept visible and promoted to bold: **"Verify nutrition against the package label."** The fold took the **why**, never the **do this** — the reason lives one tap away, the instruction does not move.
- **Lab-entry note.** Folded: *"Values with a cited Canadian target show it. Each value is stored as its own dated reading, so it trends like any other biometric"* — sourcing and storage methodology. Kept visible: the transcription instruction, the instruction for entering your lab's own printed interval (that is help, not provenance), and — bolded — **"the app does not suggest which tests to get"**, which is the sentence keeping this surface out of clinical advice.

**And the invariant grew a surface it did not previously reach.** Every earlier disclosure case asserted on strings `app.js` builds; these two notes are **static markup in the shell**, which no disclosure gate had ever looked at. `SE-disclose` now strips every `<details class="cited">` from the shipped shell's own body and asserts on what remains, over a named list of shell safety statements. **Proven against the wrong cut:** folding the instruction and the disclaimer while leaving the provenance visible fails four cases, and the invariant names both leaked phrases in its own failure message.

### The touch target is the STOP'S ZONE, not the handle

The brief asked to measure the rendered **thumb** box and assert ≥ 44×44. **The thumb is not measurable, and both routes were tried and recorded:**

- `getComputedStyle(el, '::-webkit-slider-thumb')` returns the **host box** — 332×36 — not the thumb. A ≥44 check on it would have **passed for the wrong reason** while the real handle was ~16 px.
- CDP `DOM.describeNode` with `pierce` reports **no pseudoElements** for it.

**A gate that measured the host box and called it the thumb would be a gate that lies**, so it was not written. What is gated instead is what WCAG 2.5.5 is actually about — **the area a finger must hit to select a stop** — and on a range input a tap anywhere on the track jumps to that position, so that area is `(trackWidth / 7) × control height`. Measurable, and a **stronger** claim than the handle's size.

**And the premise is proven behaviourally rather than assumed:** the gate dispatches real taps at stops 1, 3, 5 and 7 and asserts the selected value comes back as that stop, at both widths. If tapping the track ever stopped jumping, the gate fails rather than quietly measuring a target nobody can use.

**The measurement found a real failure in what 0.20.0 shipped:** the control was **36 px tall — below the 44 px floor**. It is now **48 px**, so the per-stop target is **47.4 × 48** at 360 px and **51.7 × 48** at 390 px.

**The brief's two requirements collided, and the arithmetic decides it.** "+10 %" over the 44 floor is 48.4 px of handle; but a handle must not span two stops, and at 360 px the stop pitch is only **47.4 px**. A 48.4 px handle straddles its neighbours. The window at 360 px is `44 ≤ handle ≤ 47.4` **if the handle itself had to meet the floor** — but it does not, because the *zone* is the target. So the handle is **28 px**: visibly larger than the ~16 px default, comfortably clear of the 47.4 px pitch, and the touch target is met by the control's height instead. Gated both ways.

### The readout moved above the track

**A finger occludes what is under and beside a slider exactly while sliding — which is when the readout is being read.** A mouse never shows this defect, which is why it survived the R20 gates: every one of them drove the control programmatically. The readout now sits **above** the track with 6 px clearance, gated on `readout.bottom ≤ track.top`.

Reverting both — 36 px control, readout below — fails the gate at both widths (`target ... -> False`, `readout above-track=False gap=-76.6px`).

## D54 — The food row joins the undo grammar, and D44's claim is corrected (2026-09-06)

`APP_VERSION → 0.20.3`; **schema unchanged at v5**. Shipped **alone and first**, ahead of the R22 slice that surfaced it, because it is losing data today.

### The defect

`deleteItem(idx)` spliced the item out of `day.items`, saved, and refreshed. **No `offerUndo`.** The `×` on a food row — the most-used deletion in the app — was one tap away from losing a meal, with nothing offering it back. `deleteSignal` has had undo since it shipped; `clearDay` gained it in D44; a photo-meal re-save snapshots its prior state. The food row had none.

It now captures a deep copy, offers the standard undo toast, and restores **byte-exact at the original index**.

**The date is captured, not read at undo time.** The toast lives seven seconds and a day is one tap away, so a user can navigate before undoing; restoring into "whatever day is current now" would move a meal between days — an undo that is itself a second, quieter mutation. This is D44's own by-date-key rule, applied to the row it forgot. **Gated with a day-nav in the middle of the undo.**

The flagged supplement stays non-deletable, and now **returns a refusal** rather than `undefined`, so a caller can tell "refused" from "done".

### The governance correction

D44 asserted the day-wipe was *"the single exception"* to the undo grammar. **That was false when written** — see the correction inserted at D44 itself, where the sentence is struck rather than removed.

Two things follow, and both are the point of recording it this way:

1. **The false claim was the argument.** D44 reasoned *"every other deletion goes through the grammar, so this one must too."* A correct conclusion from a false premise is worse than a wrong one, because nothing about the outcome invites re-checking the premise.
2. **It cost three days.** The log said food deletion was already safe, so nobody looked. A governance claim is read as evidence by future sessions; one that is wrong will be believed and acted on. **A false claim in the log gets the same treatment as a false gate** — reproduced, corrected in place, and struck rather than deleted, per the never-delete-log-entries rule.

### Flagged, not fixed: `cycleMeal` is the second silent rewriter — and it is NOT the same severity

`cycleMeal(idx)` rewrites a saved record's `meal` with no undo and no trace. Surfaced here rather than left to be discovered.

**But it is not data loss, and the difference is worth stating precisely.** It advances through `MEALS` **cyclically** — `MEALS[(indexOf + 1) % length]` over six values — so six taps return the original. Nothing is destroyed; the user is inconvenienced, not robbed. That is why it is **not** in this emergency fix.

It is, however, an **edit of an editable field** under R22's Fork D ruling (value / time / notes / meal), and Fork C rules that editing `meal` demotes nothing. **So `cycleMeal` is already an R22 edit that predates R22**, and the right resolution is to route it through the edit path R22 builds — one contract, one path, with undo — rather than bolting a separate undo onto it now. **Recorded as R22 scope.**
## D55 — Editing a record: the correction is kept beside the original, never in place (R22, 2026-09-06)

`APP_VERSION → 0.21.0`; **schema unchanged at v5**. Eight forks ruled; D54 shipped ahead of this as its own commit because it was losing data.

### Fork B — the correction-loop shape, and why in-place was never available

An edited record keeps **`orig`** (the fields **as first written**) and **`edited_at`**. This is the shape the photo path already uses: `ai_grams` sits beside the accepted grams — what was estimated, and what it was corrected to, both retained.

**`orig` is WRITE-ONCE PER FIELD.** A second edit of the same field must not overwrite what the first preserved: `orig` means *as first written*, not *as it was a moment ago*. A field edited three times still shows its original; a field touched later records its own original then. Gated both ways.

Editing in place was not merely simpler-but-worse — it would have **silently retired a commitment already in the log**. R15's audit view is *reserved* on the promise that provenance survives, and every honesty feature here (`confidence`, `source`, micros-only-from-labels, `ai_identity`) rests on knowing where a number came from. An in-place edit makes a hand-typed value indistinguishable from a scanned one **forever**.

The original is also **shown** in the editor — *"originally value 82"*. Provenance the user cannot see is provenance they cannot check.

### Fork C — provenance is a fact, reliability is a claim

Editing a **measurement** field demotes `confidence` to `eyeballed`; `source` and `barcode` **stand**. The record really did come from a scan, and a log that erased that while keeping the barcode would contradict itself. Editing **time, notes or meal** demotes nothing — none of them is a claim about how the number was obtained. Demotion never *invents* a field: a record with no reliability claim gains none.

**Stated plainly, because it limits this slice:** timeline signal records carry **no `confidence`** — that field lives on food items, and Fork D deferred items to second. So `demoteForEdit` ships **correct and gated as a pure function, with no live caller yet**. Its first live caller arrives with the item-edit slice. That is a consequence of the ruling, not a gap in it, and it is recorded rather than left for someone to discover.

### Fork D — the editable set, and what is deliberately not in it

`value` / `time` / `notes` (`dose` for medications). **`type` and `kind` are refused** — changing a weight into a glucose is a delete plus a create, and letting one record change species breaks every series that has already read it. A medication's `name` is its identity, out for the same reason.

**Refused, not silently ignored:** a caller that asks to change `type` gets `{ok:false, refused:['type']}`. A caller told nothing believes it worked.

An edit that changes **nothing** does not stamp `edited_at` — it must not claim an edit happened.

### Fork E — recompute, never patch; and a resolved fast is a decision

Every consumer already derives from the records on each render, so an edit needs no invalidation logic: the ring recomputes and the gate asserts the drawn SVG actually changes. **`fastLog` is untouched** — a resolved fast is a decision the user made, not a derivation to be rewritten under them.

### Fork F — `tzo` preserved, never re-stamped

D29 Pin 3. Editing a Tuesday breakfast from another timezone must not claim you ate it there. Gated across an edit and a full export→restore.

### Fork G — CORRECTED: the D29 census is a CREATION census, and an edit is not a creation

My own fork said the edit function "is a new write site and must join the D29 manifest." **That was wrong.** `check-writesites.sh` matches `.items.push(`, `.entries.push(`, `timeline[..].push(` — it enumerates **record creation**, because its purpose is that every *new* record is tz-stamped. `editRecord` pushes nothing; it mutates in place. Adding it to the manifest would have made the manifest and the detector disagree, failing the census as "lists a site that no longer exists."

So the census correctly stays at **14**, and the `tzo` invariant is gated **behaviourally** instead. **Recorded limitation:** the census does not see mutations at all — `cycleMeal`, `toggleDayStatus`, `photoSetGrams` and now `editRecord` are all invisible to it. That is the right scope for a *creation*-path census, but it should not be mistaken for a write census.

### Fork H — the row body opens the editor; the `×` keeps its own target

Two separate elements, gated as such: the body carries `openRecordEdit` and no delete, the `×` carries `deleteSignal` and no editor. D44's instinct — a destructive action must not share a thumb path with a routine one — and it costs the dense row no new chrome.

An **ordinal** offers its seven stops as a `<select>`, never a number box: the D52 snap stays *structural* on this surface too. And at the API boundary an ordinal edit to 3.5 is **refused rather than snapped-to-absent** — at ingest a stray value becomes absence because there is no one to ask; an edit has a user in front of it, and silently dropping what they just typed would be the worse answer.

### The allowlist trap, treated as a hard requirement

`orig` and `edited_at` are declared in **`normalizeSignal` and `normalizeItem`, in this commit**, though the item edit UI is a later slice. A half-declaration is the trap itself: a record edited by any future path would round-trip as **edited-value-without-edit-history** the first time it was exported — a record that looks corrected but has lost that it *is* a correction.

Third occurrence of this pattern (D45 warned; D49's `byokCount` did it; both normalizers here), so it is **round-tripped rather than reasoned about**. Proven three ways: undeclared in both → both gates fail; declared in the signal normalizer only → the item gate fails **alone**. `orig` is itself key-allowlisted, because at restore it is untrusted input.

### Found while building

`timeToMinutes` parses **"25:00" to 1500 without complaint** — it is an arithmetic helper, not a validator, and every other entry point is a native `<input type="time">` that constrains the value for it. `editRecord` takes a patch object from a caller, so it **range-checks at its own boundary**. Left global behaviour alone; recorded so the next boundary that accepts a raw time knows not to trust that helper.

### `cycleMeal`, as flagged in D54

Still the second silent rewriter. It is an edit of an editable field under Fork D, and Fork C rules it demotes nothing — so it should route through `editRecord`. **Not done here:** `editRecord` operates on `timeline[date]`, and `cycleMeal` mutates `day.items`. Wiring it means extending the contract to food items, which is the item-edit slice. **Recorded as the first task of that slice**, so it does not survive as a silent rewriter by default.
## D56 — Presence was not enough: every gate must produce a verdict (2026-09-06)

Doc-and-harness only; no shell change, no version bump.

### The fourth instance of one failure shape

This project keeps finding the same defect wearing different clothes: **a check that silently stops checking while everything still reports green.**

| # | instance | closed by |
|---|---|---|
| 1 | date-pinned gates rotting at midnight | **D50** — one clock governs |
| 2 | the storage gate green while the row printed `avg 3.5` | **D52** — display-time computation is a gate surface |
| 3 | a gate script **quarantined** by antivirus | **D53** — the gate-script presence census |
| 4 | a gate script **present but denied execution** | **this** — presence + verdict |

Instance 4 walked straight past the fix for instance 3. `bm-slider-gate.ps1` sat **byte-identical to its commit** and simply would not launch — *"Access is denied"*, one second, `rc=126` — because it is the only gate that injects synthetic input and the AV's proactive-defence module fires on that behaviour rather than on the file. **The census checked existence, and the file existed.**

**Presence was necessary and not sufficient.** The bar is now **presence *and* a verdict**: every gate must print a `GATE: PASS` / `GATE: FAIL` line, and one that prints neither **fails the suite by name**, exactly as a missing file does. There is no third outcome called *silence*.

### The silent skip was not in any committed script

It lived in **how the gates were invoked** — one at a time, by hand, through a `grep 'GATE:'` that printed nothing for the unrunnable one and moved on to the next. Nothing in the repository was wrong; the repository simply had **no runner**, and the gap was in the operator.

`tests/run-all-gates.sh` is that missing runner. It classifies every outcome, and the classification is the point:

| outcome | verdict |
|---|---|
| hung past the timeout (`rc=124`) | **FAIL — no verdict will ever arrive** |
| exited but printed no `GATE:` line | **FAIL — present but speechless** (instance 4) |
| printed `GATE: FAIL` | FAIL, with the failing measurements echoed |
| printed `GATE: PASS` but exited non-zero | **FAIL — the two disagree, so neither is trusted** |
| printed `GATE: PASS` and exited 0 | PASS |

**Every gate runs on a leash.** A hung gate never exits and would hang the runner forever — the silent skip with the volume turned all the way down — so a timeout is a *failure*, not a pause. That is not hypothetical: this exact gate hung two batch runs to the ten-minute mark before it began being denied outright.

**The no-verdict branch names the likely cause**, because the diagnosis cost real time twice: it prints the tail of the output and says that *"Access is denied"* with the file intact means the antivirus's proactive-defence module, not the script.

### Fork G, corrected in the log rather than quietly

The R22 ruling said the edit function must join the D29 write-site census. **It must not.** The census matches `.push(` — it enumerates **record creation**, because its purpose is that every *new* record is tz-stamped. `editRecord` mutates and creates nothing; adding it would have made the manifest and the detector disagree, failing as *"lists a site that no longer exists."*

**The recorded limitation is the valuable half, and it is now standing policy:** the D29 census is a **CREATION census, not a write census**. `cycleMeal`, `toggleDayStatus`, `photoSetGrams` and `editRecord` are all invisible to it, correctly. **It must never be cited as proof that all writes are covered** — only that every creation path is stamped.

### First full run, and it FAILS — which is the runner working

```
gate-script census: 8 of 8 present, manifest matches
  data-layer                 PASS
  bm-slider-gate.ps1         FAIL - PRODUCED NO VERDICT (rc=126)
      timeout: failed to run command 'powershell.exe': Permission denied
  capture-outcome-gate.ps1   PASS
  chip-layout-gate.ps1       PASS
  lab-form-gate.ps1          PASS
  offline-gate.ps1           PASS
  photo-lead-gate.ps1        PASS
  ring-size-gate.ps1         PASS
  update-gate.ps1            PASS
passed: 8   failed: 1
FAILED: bm-slider-gate.ps1(no-verdict)
SUITE: FAIL
```

**Eight of nine verdicts, and the suite exits non-zero anyway.** That is the whole point: under the old hand-run loop this was a green afternoon. The blocked gate now has a name, a return code, and a stated likely cause.

**No exemption mechanism is provided, deliberately.** A way to mark a gate "known-blocked" would reintroduce exactly the silence this closes — the suite would go green while a gate did not run, which is instance 4 again with a config file in front of it. The suite stays red until the gate can speak, and the fix is the environment (the proactive-defence exclusion), not the bar.

### Standing environment note

The gate suite depends on antivirus exclusions for `tests/` covering **both** on-access file scanning **and** the proactive-defence module. The first prevents instance 3; only the second prevents instance 4. A suite run on a machine without both is not evidence of anything, and the runner now says so out loud instead of leaving a gap where a gate should have spoken.

## D57 — The item class of the edit contract, and the portion that was never stored (R23, 2026-09-07)

`APP_VERSION → 0.23.0`; **schema v6** — the first item-field bump, and the bump is the ruling. Seven forks ruled (A1, B1, C1, D1, E1, F1, G1). The survey ran before any code was touched and **contradicted the brief three times**; all three corrections were accepted, and they are recorded here as corrections rather than folded silently into the result.

### The three corrections, because a brief believed is a brief acted on

**1. `meal` was in no editable set.** The slice was framed as *"route `cycleMeal` through `editRecord`"* on the basis that meal is editable under R22's Fork D. The **pre-registered** Fork D1 said *"value, time, notes, and meal-category only"*; the **ruled** D55 Fork D narrowed to `value`/`time`/`notes` precisely because items were deferred. `meal` sat in `ORIG_KEYS` — forward-declared for this slice — while being in no `EDITABLE_FIELDS` class at all. **So `cycleMeal` was editing a field the contract did not admit**, and this was an extension of a ruled contract, not a re-pointed caller. Ruled explicitly (B1) rather than assumed.

**2. The allowlist alone would have done nothing — silently.** `editRecord` computes `changed` over `Object.keys(next)` — the patch loop's **output**, not the caller's keys. A field the allowlist admits and no branch builds yields an empty `next`, an empty `changed`, and the return `{ok:false, error:'No change.'}`. Adding `meal` to `EDITABLE_FIELDS` without adding its branch would have made `cycleMeal` **a silent no-op reporting "No change"**.

**This is the fifth instance of the family D56 tabulated** — a check or a path that stops working while everything still reports success-shaped. It gets the same treatment: a guard that **names the failure**. A field that is editable-but-unbuilt now returns `{ok:false, drift:[...]}` saying *"Editable but unhandled (contract drift)"*. The general rule, stated so the next allowlist inherits it: **an allowlist and the loop that serves it must move together, or the allowlist lies.** Gated by planting `name` in the allowlist with no branch behind it.

**3. There was no accepted portion to edit, and that absence was the root cause of a live defect.** The brief required that editing an AI-derived item's grams update the accepted value while preserving `ai_grams`. **No food item stored an accepted grams.** `normalizeItem` had no such key; the scan path wrote the portion into **prose** (`notes: 'scanned 150 g'`); the photo path stored only the estimate and the scaled macros.

### The reopen defect — found by the survey, fixed by the same field

Because the accepted portion was never stored, `photoReopen` **reconstructed** the per-100 g profile by dividing the stored macros by `ai_grams` — correct only when the user had accepted the estimate unchanged. Transcribed the shipped `photoShared` / `photoGrams` / `photoItemMacros` / `photoSave` / `photoReopen` and ran them headless before writing a line of the fix:

```
anchor a 100 g AI estimate to 150 g
  SAVED               {"kcal":247.5,"ai_grams":100,"pinned":true}   no accepted grams anywhere
  REOPENED grams      100      <- the user set 150
  REOPENED per100     247.5    <- truth 165
  REOPENED total      247.5    (preserved -- which is why nothing looked wrong)
  REOPENED anchor R   1        <- the user's anchor was 1.5
  then nudge to 200g  495 kcal <- truth 330
```

**A photo meal reopened after anchoring lost its anchor.** `pinned: true` survived while the ratio it recorded did not. The total was preserved at reopen, so the defect was invisible — until the next grams edit compounded from the wrong base, and **the next grams edit is exactly what this slice adds**. Ruled D1: it rides along, because `grams` *is* the fix and splitting the slices would have meant writing the reconstruction twice.

**Recorded limitation:** pre-v6 items have no accepted portion and fall back to the old reconstruction. That is not a fix for them — it is the best available reading of a record that never stored what was accepted, and it is exactly as good as the app was before.

### Why this one bumps the schema (Fork C, ruled C1 + bump)

Every additive item field so far — `ai_grams`, `ai_identity`, `pinned`, `mealId` — shipped **without** a bump, justified on D29's asymmetry test: *losing them degrades a future calibration input, not content the user authored.* **`grams` is on the other side of that line.** The user typed 150. An older app silently stripping it at the restore boundary is data loss, not a degraded analysis. **So the schema bumps to 6**, `migrateV5toV6` is add-only, and the forward guard moves with it (`> 6` refused).

**The migration invents no portion, and this is the load-bearing half.** It would be easy to mine `notes` for `"scanned <n> g"` and backfill every historical scan item. That is exactly the editorializing **D4's surviving principle** forbids: `notes` is user-editable free text, so parsing it is an **inference about what a number meant**, not a transport of it. A migrated item has **no** `grams`, which is the honest state — we do not know the portion, and absence says so. Gated: the migrator carries `kcal` through and leaves both the prose and the absence alone.

**Absence is preserved, never zero-filled.** An item with no known portion has no `grams`; 0 would claim a weightless meal. Same rule micros have had since D8.

**The scan prose is retired** on new writes. Keeping both would be two copies of one fact with only one of them editable — edit the grams and the sentence *"scanned 150 g"* goes stale and starts lying, which is the surface-claiming-more-than-the-substance shape D50/D52/D53/D56 keep closing. Old items keep their sentence; migration does not rewrite history.

### Ruled inside C1, and flagged rather than buried: editing the portion RESCALES

The forks did not ask what editing `grams` does to the macros, and it has only one honest answer. A record reading 200 g while its kcal still holds the 150 g figure is **internally false**, and the app would go on totalling the stale number. So a grams edit rescales the macros by `new/old`, `orig` keeps **both** the first-written portion and the first-written macros, and an explicitly-patched macro wins over the factor (the user said what they meant).

**Labelled micros rescale with it.** They are not editable — D8 rules a hand-typed micro is exactly the dishonesty that rule exists to prevent — but a 150 g row rescaled to 200 g whose sodium stayed put would understate by precisely the ratio the macros just moved. They are rescaled in place and deliberately **not** recorded in `orig`: `normalizeOrig` takes primitives only, and the originals are recoverable exactly, since write-once `orig.grams` pins the total factor as current/original.

**With no prior portion there is nothing to scale from**, so setting one records the portion and leaves the macros alone — an annotation of what was already logged. Inventing a factor there would be fabricating a measurement.

### The allowlist trap, fourth occurrence — and where the ruling's letter was not followed

The ruling said the accepted grams *"joins BOTH normalizers in the same commit."* **It joins `normalizeItem` and `ORIG_KEYS`, and deliberately not `normalizeSignal`** — a signal has no portion, and declaring a field a class can never legitimately carry is noise pretending to be safety. The both-normalizers half is satisfied where it actually bites: **`ORIG_KEYS` is the allowlist inside the allowlist and is shared by both normalizers**, so `orig.grams` round-trips in either class and no edit history is lost at either boundary. Gated four ways: `grams` survives export→restore on an item, `orig.grams` survives with it, a signal's `orig.grams` survives, and a signal itself never grows a `grams`.

### The silent-rewriter census, corrected in both directions

| site | verdict |
|---|---|
| `cycleMeal` | **the target.** Now a caller of the contract; it gained undo and provenance without a line of undo code of its own |
| `addWater` | **the unnamed third.** The brief did not name it; it had no undo at all |
| `toggleDayStatus` | **stays out** (G1). A day-level *attestation*, not a record edit — self-inverse, and it already speaks |
| `photoSetGrams` | **NOT a rewriter.** It mutates `PHOTO_DRAFT`, which is never persisted; `photoSave` is the write and already carried a full-snapshot undo. The brief's census note was withdrawn |

`addWater` looks self-inverse and is not: `Math.max(0, …)` **clamps**, so 0.1 L take 0.25 lands on 0 and the answering +0.25 gives 0.25, not 0.1. Non-multiples of 0.25 arrive by ingest and restore. It is the one mutation in the app where the inverse gesture does not return the value, and the undo now restores **the exact prior value**, not the inverse gesture. Gated on that case specifically.

### Fork F — the shipped inconsistency, closed on both sides

Every **creation** path already reopened a completed day; **`deleteItem` did not**. So removing a row from a closed day changed its totals while the day went on counting in the D10 averages as attested. Ruled F1: an edit reopens, **and `deleteItem` gains the same**. D10's discipline is a *manual attestation*, and changing a day's contents after the attestation means it was made about different data.

**The reopen is part of the mutation, so undo undoes it too** — otherwise an undone edit leaves the day quietly reopened and out of the averages, which is a second, silent mutation of the kind D44 closed for dates.

The arithmetic needed nothing: `averageOver` derives from `day.items` on every render, so an edit recomputes for free. That is D55's Fork E rule holding without extension.

### Fork E — three targets, and the one that had to stop being a button

The timeline row was *body + ×*, and D55's Fork H put the editor on the body. The food row already carried **three** targets — body, meal chip, `×` — so putting the editor on the body would have nested a button inside the tap target. E1: **the chip stops cycling and becomes the way in**, landing the editor on meal; the body opens the same editor; `×` keeps its own target, and D44's rule that a destructive action does not share a thumb path survives intact. The affordance users know is preserved, and meal becomes a **choice from the enum** rather than six taps through it.

The supplement row offers neither, and `openItemEdit` refuses it at the API too, so the guard is not merely cosmetic.

**Confirmed rather than built:** the requirement that a meal cycled six times back to its original still shows its `orig` **falls out of the shipped write-once logic** — tap 1 pins `orig.meal`, taps 2–6 leave it, and the record ends reading *edited, and back where it started*. That is the honest reading, and it is gated as such.

### Repointed, not weakened

Fifteen existing assertions moved: the migration chain now ends at v6, the forward-guard fixtures moved to v7, and the round-trip fixture `S1` was **re-pinned to the live schema version**. That last one matters beyond bookkeeping — pinned one version behind, it would have quietly stopped being a round-trip test and become a migration test, asserting round-trip equality no longer. The comment now says so.

Six assertions that read *"schema version UNCHANGED at 5 (no bump)"* now read *"this slice bumped nothing; v6 is D57's"*. The claim each was making is preserved; only the number moved, and the reason it moved is named in the assertion text.

`R6-save`'s additive set grew from four fields to five.

## D58 — Capture from camera *or* library, and the three D47 failure modes re-proven on the second path (R24, 2026-09-07)

`APP_VERSION → 0.24.0`; **schema unchanged at v6**. Only the SOURCE of the image changes: same downscale, same base64, same call, same confirm-first modal (D51). The slice is small; what it needed was evidence that the failure modes D47 closed are closed on the *other* path too, where all three are markedly more likely.

### Two inputs, and the source is derived from the attribute

`capture="environment"` is what forces the camera, so the library input is simply the same input **without it**. Two elements rather than one input whose attribute is toggled: the source is read back at runtime by `captureSourceOf(input)`, and a mutated attribute would make that derivation race the click that set it.

**The source is derived from the `capture` attribute, never passed alongside it.** One source of truth that cannot drift from the element's actual behaviour — a second argument in the markup could disagree with the attribute, and then the messages would describe a path the file did not take. Both inputs call the **same** `onCaptureFile`, so there is one downstream, not two.

### Two buttons, ruled rather than relying on the native picker

The brief's hypothesis was that dropping `capture` is enough, because iOS then offers *Take Photo / Choose from Library* in its own picker — and asked that this be checked rather than assumed. **It cannot be checked from here**: this machine has Chrome and no iOS or Android. So the design was chosen to not depend on the unverifiable.

Two explicit buttons — **Take photo** and **Choose photo** — behave identically on every platform: each opens its own input, and the camera path is byte-for-byte the one that shipped. Relying on a single no-`capture` input would have been smaller, but its failure mode is losing the camera entirely on any platform whose picker does not offer it; the two-button failure mode is a redundant button on desktop. **Recorded as the open question for the on-device pass:** if iOS's native chooser does offer both from the library input, this could collapse to one button — that is a simplification available later, on evidence, not a guess taken now.

**Desktop is fixed as a side effect**, which was the second half of the ask: `Choose photo` opens an ordinary file dialog on a machine with no camera, where Capture previously had no working path at all.

### EXIF orientation — measured, then pinned anyway, and the gate's limits stated

`createImageBitmap(file)` was called with **no options**, so orientation depended entirely on the default — and that default has moved twice: the original spec said `"none"`, the current one says `"from-image"`, and `"none"` has since been removed and folded into from-image. Measured on this Chrome with a real JPEG carrying an injected EXIF `Orientation=6` tag:

```
source: 4x2 landscape, EXIF Orientation=6
  createImageBitmap(blob)                      -> 2x4    (as shipped)
  createImageBitmap(blob,{from-image})         -> 2x4
  createImageBitmap(blob,{none})               -> 2x4    ("none" no longer honoured)
  <img>.naturalWidth/Height (fallback path)    -> 2x4
```

So the shipped code was **already correct on this browser**, on both decoders. It is pinned anyway: the answer above is a browser-version fact rather than a contract, and a library photo carries EXIF far more often than a fresh camera frame does. A browser too old for the options argument still degrades correctly — any bitmap failure already falls through to `byokDecodeImage`, which honours EXIF via the `<img>` path.

**Stated plainly, because it bounds what the evidence proves:** the *behavioural* EXIF gate **cannot fail on this browser**. Removing the pin leaves it green, because Chrome's default is already right. It would catch the regression on a browser whose default is the old one — which is precisely the browser not running this suite. So the pin is asserted **structurally as well**, where it can fail, and the two gates are honest about proving different things.

### The structural gate matched its own comment — sixth instance of the family

The first version of that structural assertion grepped `String(byokDecodeBitmap)` for `imageOrientation` and **passed with the pin removed**, because the explanatory comment sitting inside the function body contains the word. A gate that matches its own comment asserts nothing.

This is the same family D56 tabulated — a check that stops checking while reporting green — and it was found *in a gate written to close that family*, which is the part worth recording. The rule that follows: **a structural gate must match a shape that cannot occur in prose.** It now matches the call shape (`createImageBitmap(file, { imageOrientation: 'from-image'`), which appears in no comment, and it fails against the unpinned build.

### The HEIC advice was wrong for half the photos it addressed

One message served both paths: *"Set the camera to Most Compatible."* That fixes the **next** photo you take. It does nothing for a HEIC already sitting in the library, and telling someone to change a camera setting to fix a photo they took last Tuesday is advice that cannot work. **A dead end stated confidently is worse than one stated plainly.**

`byokHeicMessage(source)` now says *"Share or re-save it as a JPEG first"* for a library photo and keeps the camera setting where it can help. Both keep the path that always works (Copy prompt). Gated on the strings **and** driven through the shipped shell.

Same reasoning for the empty pick: **a cancelled library picker is the ordinary way to change your mind**, and it must not read as a camera fault. The camera path still names the camera, so the two are told apart rather than blurred — gated with a control.

### The hard requirement now runs over both sources

D47's never-silent bar — *every adversarial input ends in a fired request or a visible message, never in nothing* — was only ever proven on the camera input. It now runs as a **cross-product of the four adversarial files against both inputs**, driven through the shipped shell in the iframe. That is not a formality: with the library input removed, four of those eight cases fail.

Size needed no new bound — `BYOK_MAX_EDGE` already binds both paths — but a 2400×1800 library photo is now put through the real decoder and **measured** to come out at the bound, rather than assumed to inherit it.

### Repointed, not weakened

`R21.4-path` asserted that an untested key still gets a `Capture meal` button. The one button became two, so the assertion now covers **both** — a status that gated only one of them would be the same block wearing half a costume.

## D59 — The micros corpus: a fourth store, and the first exercise of D13's escalation clause (2026-09-07)

Governance only. **No code, no schema change, no `APP_VERSION` bump** — nothing in the shell moves, and under the D6 converse a bump here would announce work that did not happen.

This entry rules the **substrate** for the micronutrient composition corpus and deliberately does **not** rule its schema. Six forks ruled (A1, B1, C1, D1, E1, F1) plus one pin that was not offered as optional.

### The misattribution, corrected before anything rests on it

The session that produced this entry twice cited **"D12"** as the ruling against IndexedDB. **It is D13.** D12 is the supplement config UI and has nothing to do with storage. The error was in conversation only and reached no committed file — but half a governance argument was conducted against the wrong entry number before it was caught, and the correction is recorded rather than quietly absorbed, on D54's rule: a false claim in the governance record gets the same treatment as a false gate, because a future session reading only the outcome cannot tell that the argument had to be re-grounded.

### What D13 ruled, and what it did not

> **Ruled: a capped localStorage key, not IndexedDB.** […] No second storage subsystem, no async — the cache stays **synchronously testable** by the committed harness. IndexedDB is the **Phase-4 escalation only**, if product volume ever outgrows the localStorage budget.

**D13 stands unchanged and is not superseded.** Every clause of it is about the OFF product cache: a *disposable, rebuildable mirror of a remote API* — capped at 500 entries and ~512 KB, LRU-evicted, excluded from export, benign on failure, always yielding storage to the log. The corpus is none of those things, so D13 does not govern it. Superseding a correct entry to license an unrelated one would corrupt the log; the ruling below is a **new artifact class**, not a reversal.

**Its escalation clause is also narrower than the case brought against it.** It names a **volume** trigger for **that cache**. The volume half fits as written. The growth half — see Ground 2 — is a condition D13 never contemplated, and is the stronger argument.

### D13's reasoning was WEIGHED AND TRADED, not sidestepped

This must be stated plainly or the scope argument above becomes a dodge. D13 chose localStorage in part for *"no second storage subsystem, no async — the cache stays synchronously testable by the committed harness."* That is a real architectural commitment, it is still a good one, and **this entry trades it away for the corpus.**

What makes the trade payable is a seam, not a hope: the ruling that **past meals never revise** means an item freezes its computed values at save time and the corpus is never consulted for a past meal again. **No log operation ever awaits the corpus.** The synchronous, synchronously-testable core stays exactly that; async is confined to a subsystem nothing in the log blocks on. The suite already drives async chains through the shipped shell (R21.2, R24), so the capability exists — what is new is async *in the data layer*, and it is new only outside the log.

### The escalation is met on two independent grounds

**Ground 1 — the arithmetic, which is not close.** localStorage stores strings, so a `Float32Array` must be base64'd (+33%), and browsers charge quota per UTF-16 code unit (×2):

| | raw | base64 | localStorage quota |
|---|---|---|---|
| dense 64×f32 × 10k foods | 2.56 MB | 3.41 MB | **~6.8 MB** |
| sparse (~25 populated of 64) | 1.0 MB | 1.33 MB | **~2.7 MB** |
| index, 10k plain JSON objects | — | ~1.0 MB | **~2.0 MB** |

The dense form **exceeds the whole budget on its own**, before the log and before `healthtracker-products`' 512 KB. Even sparse-plus-index consumes ~4.7 MB of a ~5 MB budget that D13 requires to *"always yield storage to the log."*

**Ground 2 — write amplification, and it is the stronger of the two.** localStorage has **no partial update**: every accretion of a single resolved food rewrites the entire corpus blob, synchronously, on the main thread. **This is not a quota problem, so no amount of subsetting fixes it.** It is a structural mismatch between a monolithic-blob store and an accreting asset, and it holds at 3,000 rows exactly as firmly as at 10,000. Ground 1 could in principle be argued down; Ground 2 cannot.

### The LRU finding — the policy that made localStorage safe is the one that is destructive here

D13's eviction rule is *"LRU, cache yields first."* **That policy is safe precisely because the cache is disposable** — evicting an entry costs a re-fetch and never data (D13's own "Nature" clause).

Evicting an accreted corpus destroys **resolution work that a source refresh cannot re-derive**. A CNF or FDC release brings back the published rows; it does not bring back the matches, the resolved misses, or the barcode-derived accretions that made this corpus better than the sources it came from. So the one mechanism that bounded the product cache safely is, applied here, a mechanism for silently deleting the moat.

This is the sharpest form of the argument: it is not that localStorage is too small for the corpus, it is that **localStorage's only safety mechanism is destructive to this artifact class.**

### Why no useful corpus is localStorage-shaped

The strongest conservative case — sparse-encode, cap at ~3,000 foods, LRU as D13 does — fails on its own terms, and not narrowly. Approximate row counts: CNF ~5,700; SR Legacy ~7,800; FNDDS ~5,600; FDC Foundation ~300 (Branded ~1.9M, excluded). A 3,000-row budget forces dropping most of one source, and dropping FNDDS costs the ~5,400 recipe-calculated mixed dishes — **the restaurant-and-cooked-meal case, which is the case the micros layer exists to serve.** A subset of single ingredients answers the questions a package label already answers.

**There is no corpus size that is both useful and localStorage-shaped.**

### The ruling

**Fork A1 — D13 stands; the corpus is a new artifact class.** Its taxonomy is extended to a **fourth store in the same commit as this entry** (see the D13 amendment). D13's *"three distinct caches, do not conflate"* sentence becomes false the moment this lands, and a stale governance claim is believed by the next session that reads it — the D54 shape, closed here by construction rather than left to be discovered.

**Fork B1 — the escalation is met**, on both grounds above, with write amplification recorded as the stronger.

**Fork C1 — one store, two object stores, one transaction; index hydrated to RAM at boot.** The index's "hotness" is served by **RAM, not by which disk store it came from** — localStorage is not faster than IndexedDB once loaded, only synchronous, and 10k masks as two `Int32Array`s is ~80 KB. Splitting therefore buys no speed and costs atomicity: **a localStorage index plus an IDB composition can crash between writes and leave a mask asserting a nutrient whose values are not there — a mask that LIES, which is worse than a mask that is absent, and is precisely what the mask/value split exists to prevent.** IndexedDB gives a transaction across object stores; a split across two subsystems gives nothing.

**Fork D1 — everything in IndexedDB for v1.** D2 — an immutable base as a versioned static asset (fetched, SW-cached, shielded as D6-Amendment-A shields the runtime cache) with accretions in IDB, overlaid at read — is **named as the escalation and not built.** It is genuinely attractive and would also solve initial acquisition, but it buys shadowing and two-sources-of-truth-per-row, and that price is not paid before base-refresh pain is real.

**Fork E1 — corpus absence is a CAPABILITY statement, not a storage-badge event.** D13's consequence-2 reasoning carries: the truthful badge (D1) speaks for *your log*, and a missing corpus is not a log-integrity fact. The micros layer says it is unavailable on this device; logging, scanning and manual entry are untouched. **Never a silent absence** — an unavailable capability that says nothing is the D56 family.

**Fork F1 — rule the substrate, defer the schema.** The substrate is cheap and robust to a 3× swing in row count; the schema is not. The **dish-vs-decompose fork is upstream of the storage sizing, not parallel to it**: decomposing makes the corpus ingredients-plus-recipe-logic, keeping dishes whole makes FNDDS's mixed dishes first-class rows, and that changes row count, mask density and average sparsity — every input to the table above. Pinning the schema now pins an estimate the next fork can invalidate.

### The pin — `resolvePath` and `maskAtResolve` are FORENSIC ONLY

Audit and explanation. **Never inputs to re-resolution.** They look exactly like re-resolution inputs, and the freeze rule dies quietly the first time someone treats them as such. Pinned here so that a future slice proposing "re-resolve past meals from stored provenance" is recognised as repealing D59, not as implementing it.

### Accepted deliberately, rather than discovered later

**Corpus version skew across devices.** Two devices at different corpus versions can resolve the same food to different numbers going forward. Under the freeze rule this produces no contradiction in the log — just two records with different provenance. Accepted.

**Store sparse, hydrate dense.** The mask exists to record which nutrients are present; dense 64-slot storage then spends bytes on exactly the absences the mask already encodes. Storing sparse and expanding on load decouples the storage question from the compute question, and the mask makes the expansion free. This holds wherever the corpus lands and is not contingent on the substrate ruling.

**Export/restore is unchanged, and the freeze rule makes it simpler rather than harder.** The corpus is an asset, not user data, so it is excluded from export for D13's consequence-1 reasoning extended to the fourth store. A restore on a device with **no** corpus is *complete* — items carry their frozen values and nothing is missing from history; future resolution degrades until re-acquisition. A **stale** or **differently-versioned** corpus is irrelevant to history by construction, since past meals never consult it.

### What this entry does not rule, and where the attention goes next

The schema, the mask's word-1 slot list, the dish-vs-decompose fork, and the matcher.

**The next slice is the MATCHER and the dish fork, prototyped in RAM over a few thousand rows with no persistence at all.** Nothing about name matching across CNF's and FDC's different conventions needs a durable store in order to be *learned*, which means the knowledge layer was less blocked behind this ruling than it appeared.

Recorded because it is the reason this entry is deliberately short on schema: **a corpus that resolves the wrong food quickly is worse than one that resolves the right food slowly.** Representation optimises retrieval; the matcher determines correctness. The representation work was the tractable half, and tractability is not the same as priority.

### Amendment — the store name, ruled rather than assumed (2026-09-07)

`healthtracker-corpus` appeared in the D13 taxonomy row above because that row needed a label, **not because it was ruled**. Flagged immediately after this entry was committed, and settled here rather than left to harden under code.

**Ruled: `healthtracker-corpus`, and the name is a SUBSTRATE decision, not a schema one.** D1 is the reason. That entry rules a *version-stable key* — the predecessor baked the version into the key (`uha-log-v1`), *"which is precisely why a future v2 would orphan v1 data"* — and the same trap is available here: `healthtracker-corpus-v1` would orphan the accreted corpus on the first schema change, which for an artifact whose whole value is accretion is the worst possible place to repeat it.

**The name therefore carries no version, and IndexedDB's own mechanism carries it instead.** `indexedDB.open(name, version)` has a native versioned-upgrade path, so the database name stays stable forever and schema migration runs through `onupgradeneeded` — D1's principle expressed in the substrate's own idiom rather than bolted on beside it.

**Object store names remain deferred to the schema slice.** The database name is D1-class — stable, never versioned, never orphaned — and belongs with the substrate. What the stores inside it are called is schema, and F1 defers schema.

## D60 — A gate is not evidence until it has been seen to fail (2026-09-07)

Governance only. No code, no schema change, no `APP_VERSION` bump.

### The finding that forces this

D56 tabulated four instances of one failure shape: **a check that silently stops checking while everything still reports green.** Two more have since been found, and sorting the six by *where they lived* is the uncomfortable part:

| # | instance | site |
|---|---|---|
| 1 | date-pinned gates rotting at midnight (D50) | **gate layer** |
| 2 | storage gate green while the row printed `avg 3.5` (D52) | app |
| 3 | a gate script quarantined by antivirus (D53) | **gate layer** |
| 4 | a gate script present but denied execution (D56) | **gate layer** |
| 5 | allowlist/loop drift in `editRecord` (D57) | app |
| 6 | a structural gate matching its own comment (D58) | **gate layer** |

**Four of six live in the gate layer.** The gates are now the most frequent site of the failure they exist to detect. That is not an argument for fewer gates — instance 5 was a live shipped defect and instance 6 was found inside the slice that shipped the fix for it — but it means the gate layer has earned the same adversarial treatment the app gets, and it has been getting that treatment by habit rather than by rule.

Instance 6 is the proof that the existing bar is insufficient. `CLAUDE.md`'s working rule asks for *"pre-registered, re-runnable gate evidence."* That gate was pre-registered, re-runnable, and green — and asserted **nothing**, because it matched the word `imageOrientation` in its own explanatory comment. Every stated requirement was met by a gate that could not fail.

### The rule

**A new or materially changed gate is not evidence until it has been RUN AGAINST THE DEFECT IT CLOSES AND SEEN TO FAIL.** The failing run is part of the gate's evidence and is recorded in `GATES.md` alongside the passing one.

Three clauses, each earned by a specific instance — **and three more added by amendment below** (Clause 4, 2026-09-08; Clauses 5 and 6, 2026-09-11):

**1. Exhibited, not asserted.** It is not enough to reason that a gate would fail; the defect is planted — the pre-slice behaviour restored, or the property mutated false — the suite is run, and the named cases are observed failing. Instance 6 survived every amount of reasoning and died in the first minute of being run against the unpinned build.

**2. A gate that CANNOT fail on the machine running it must say so, and must be paired.** Some properties are unfalsifiable locally: R24's behavioural EXIF gate stays green with the pin removed, because this browser's default is already correct, and it guards the browser that is not running the suite. Such a gate is still worth having — but it is **not** evidence of the thing it appears to prove, it must state that limitation in its own text, and it must be accompanied by an assertion that *can* fail. Silence about a gate's blind spot is the same defect one level up.

**3. It applies to CHANGED gates, not only new ones.** A repointed assertion can be weakened without anyone intending it. This session moved sixteen; each kept its claim only because the claim was re-checked, and "repointed, not weakened" is a statement that has to be *earned* per assertion rather than asserted per commit.

### What this costs, stated honestly

A defect run is a full suite run per planted defect. R23 cost eight; R24 cost four. That is minutes, not hours, and it is the cheapest evidence in the project — it found a shipped photo-reopen bug and a vacuous gate that no amount of review had caught.

### No exemption, and no pretence that writing it down is enough

**No mechanism is provided for marking a gate "unfalsifiable, skip the proof."** D56 refused the same thing for a blocked gate script and the reasoning carries: an exemption marker would let the suite go green while a gate proved nothing, which is instance 6 with a config file in front of it. Clause 2 is the honest path — state the blind spot, pair it with something that can fail.

**And this rule is NOT machine-enforced, which is its own weakness and is recorded rather than glossed.** It depends on the author remembering, and a check that depends on remembering is precisely the category this project has watched decay four times in the gate layer alone. The rule is therefore written where it binds, but it should not be mistaken for a solution: **the enforcing mechanism would be a mutation pass** — a runner that flips a known set of properties false and asserts that a named gate fails for each — and until that exists, D60 is a discipline, not a guarantee. **That runner is now a named candidate slice — R32 in `GATES.md` — rather than a standing caveat.** Naming that gap is the point; a governance claim that oversells its own enforcement is the D54 shape.


### Amendment — Clause 4: THE FIXTURE IS AS FALSIFIABLE AS THE ASSERTION (2026-09-08)

The three clauses above catch a gate that **asserts nothing**. They do not catch a gate whose **starting state makes the assertion true regardless of the code under test** — and that has now happened three times, in two consecutive slices, always found by the defect pass and never by review.

| slice | assertion | why the fixture could not exhibit the failure |
|---|---|---|
| R25 (D61) | excluding a row takes it out of the shared correction | the case excluded an **unpinned** row, which was never in the pin set |
| R25 (D61) | an excluded row is not written | the case **un-excluded everything before saving** |
| R26 (D63) | Copy fills the box, so "select it and copy" is followable | **both boxes are already full at boot**, so the assertion held whatever `copyPrompt` did |

In every case the assertion was correct, well-named, and would have caught the defect **given a fixture that could reach it**. The gap is one level below the assertion, which is exactly where nobody looks.

**Clause 4, binding:** *proving against the defect means the FIXTURE must be capable of exhibiting the failure, not merely the assertion capable of naming it.* The starting state is part of the gate and is adversarial in the same way the assertion is — set it so the property is **false before the code under test runs**, then assert the code makes it true.

**The practical diagnostic, since this is what actually catches it:** when a planted defect leaves the suite green, suspect the fixture first. An assertion that names the right property and still passes against its own defect is almost always measuring a state that some *other* code established.

**And the positive pattern, from the fourth defect of R26.** Removing the ancestor walk in `promptBoxFor` broke no gate — legitimately, because the visible-box fallback independently satisfies the property whenever only one surface is open. The temptation is a caveat: *"this mutation is safe for an unrelated reason."* The better answer is to **construct the case where the mechanism is not optional** — both surfaces open at once, two boxes visible, only the tapped card's may be written. That makes the walk load-bearing and the mutation falsifiable, and it replaces a note nobody would re-read with a gate that fails. **Prefer constructing the discriminating case over recording why the gate could not fail.**

### Amendment — the Clause 4 register, extended (2026-09-11)

The table above closed at three instances on 2026-09-08 and was never extended, so **instance 4 was recorded in D67 and not carried back here.** The register is the thing future sessions count from, so it is completed rather than left to be reassembled from three separate entries.

| # | slice | assertion | why the fixture could not exhibit the failure |
|---|---|---|---|
| 4 | R31 (D67) | *"the day-total row says so"* | asserted against the **whole day view**, where the **meal group head** carries the same sentence for the same items and satisfied it once the day-total note was deleted |
| 5 | R30 (D68) | the candidate list renders in the model's order | the fixture was `Alpha / Bravo / Charlie` — **already alphabetical**, so a planted alphabetical sort was a no-op and the gate passed with the defect in |

**Instance 4 was the first where the flaw was the assertion's SCOPE rather than the fixture's reach** — two surfaces make the same claim, and asserting on their union lets either go missing behind the other. The repair is the same shape as Clause 4's positive pattern: assert each claim **where it lives**.

**Instance 5 is the plainest statement of the clause there has been.** The assertion named exactly the right property, the defect was exactly the one it guards against, and the two never met because the test data could not tell them apart. **Fixture data must be chosen so that the wrong answers are DIFFERENT from the right one** — the names now disagree with alphabetical, reverse and by-length ordering, so only the model's own order satisfies the case.

### Amendment — Clause 5: A GATE MUST BE ABLE TO FAIL BY NAME (2026-09-11)

**Found in R30's defect pass.** With `ai_alts` dropped from the `normalizeItem` allowlist, `R30-record` read `recItem.ai_alts.length` on a field that was no longer there, raised a `TypeError`, and **aborted the synchronous suite**. What the run reported was:

```
FAIL  HARNESS: uncaught exception aborted the synchronous suite -- cases after it did NOT run
```

The suite went red. The harness did exactly what it was built to do — D56's handler exists for this, and without it the run would have printed a green-looking summary over a silently reduced count. **Nothing in the machinery misbehaved.**

**And the gate still did not report.** It crashed. The verdict named the harness, not the property: *something threw*, not *the offered list is no longer stored*. A reader of that run learns the suite is broken and nothing about which contract was violated — and the defect pass, which matches failures against the case it planted them for, scored it as **passing with the defect in**, because no line carrying `R30-record` was ever printed.

**Clause 5, binding:** *a gate is evidence only if it can fail AS ITSELF.* A case that signals its defect by taking the suite down is not evidence, **for the same reason as one that cannot fail at all: the verdict does not identify what broke.** Clauses 1–4 ask whether a gate *can* fail; this one asks whether the failure *arrives with the gate's name on it*.

**It is worse than an ordinary miss, in a way worth stating.** An abort stops every case after it, so one planted defect yields an unknown number of **unmeasured** properties — the run cannot distinguish "these still hold" from "these were never reached". That is D56's silent-skip shape, produced by a gate rather than suffered by one.

**The practical rule, since this is what prevents it:** an assertion that dereferences something a defect could remove must **guard the dereference** — `!!x && x.length === 3` rather than `x.length === 3`. The guard costs nothing when the property holds and is the whole difference between a named failure and a crash. The same applies to any case that indexes an array, walks a chain of optional fields, or calls a method on a value the code under test is responsible for creating.

**The diagnostic:** when a planted defect produces `HARNESS: uncaught exception`, the suite has told you the truth and the gate has not. Find the case that threw and guard it, then re-run — the defect is not proven closed until the failure prints the gate's own name.

**And the honest limit, as with the rest of D60:** this is still discipline, not enforcement. A mutation runner that asserted *"gate X, and only gate X, fails for defect Y"* would catch Clauses 1, 4 and 5 mechanically. Until it exists, the defect pass catches these only because its output is read case by case rather than as a pass/fail total — which is the same reason the three earlier instances were caught, and worth preserving as a habit. **It is now named: R32, with its registry, its "and only" assertion and its patch-drift ruling recorded in `GATES.md`. Not scheduled — but a task rather than a caveat.**

### Amendment — Clause 6: A DEFECT THAT BREAKS EVERYTHING PROVES NOTHING ABOUT ONE GATE (2026-09-11)

**R33's defect pass planted thirteen and withdrew or re-aimed three. Each failed for a different reason, and the three together make one rule.**

**1 — The outer defence fired first.** The plate-leak defect was planted in `photoSave`, and `check-writesites.sh` — the D29 record-write census — caught it and aborted the run **before the data-layer harness started**. The defect was detected loudly, by name, by a check that had nothing to do with the gate under test, and the gate never executed. From the pass's point of view that is indistinguishable from a gate that cannot fail.

**2 — The property had no possible mutation.** *"A plate does not break a fast"* could not be falsified by any change to `fastEvents`, because a plate is not an item — which is the entire point of putting plates in their own store. That is **Clause 2**, and it was handled as Clause 4's positive pattern requires: the defect was **withdrawn and paired** with one that can break the property (`plate-written-into-day-items`), rather than kept as a caveat explaining why the gate could not fail.

**3 — Two defects were simply too blunt.** *"Write no consumption event at all"* and *"push every plate row into the day"* break the photo path wholesale. An earlier block died, the named gate never ran, and the run reported a dozen unrelated failures. Guarding the early dereferences helped, but guarding was not the answer: **the defects were re-aimed** — *"ate all of it" silently logs half*, and *the plate reaches `dayTotals` and nothing else* — and both then failed their own gate immediately.

**Clause 6, binding:** *a gate is proven by a defect that touches ONLY its property.* A defect broad enough to break the app is always caught by something, and being caught by something is not evidence about **this** gate. When a planted defect fails a dozen unrelated cases, that is not a strong result — it is a sign the defect is too blunt to say anything about the gate it was written for.

**The diagnostic:** read the defect's blast radius, not just its verdict. One planted defect should ideally fail **one named gate and its own controls**. Many failures mean *re-aim*; zero means Clause 1 or 4; a `HARNESS` line means Clause 5; and a failure raised by a different subsystem entirely means the defect never reached the gate at all.

### Relationship to `CLAUDE.md`

The brief's working rule — *"pre-registered, re-runnable gate evidence"* — is the weaker statement and is now incomplete, as instance 6 demonstrated by satisfying it completely. **D60 is the binding form.** Per the project's own rule that ruled contracts live in `DECISIONS.md` and bind equally with the brief, no edit to `CLAUDE.md` is required for this to hold; the brief is left alone rather than partially updated, since it is already behind the code in other respects and a half-refreshed brief is worse than one known to be historical.

## D61 — The third rail: adding what the photo could not show, and the denominator nobody was writing (R25, 2026-09-07)

`APP_VERSION → 0.25.0`; **schema unchanged at v6** — `added` is an additive optional item field, and the v6 bump for `grams` (D57) already covered the authored-content case. Seven forks ruled (A1, B1, C1, D1, E1, F1 + F-fix1, G).

The motivating meal: a bowl of crab and chicken in one sauce. The model resolved the crab and did not separately report the chicken. **That is correct behaviour for what a photo permits, not a defect** — a bowl of two interleaved proteins under one browning is one thing to a camera. The gap was that the human, who knows what is in the bowl, had no way to say so: the draft's two rails (scale, identity) both correct what was *reported*, and neither can add what was not.

### F-fix1 — the identity rail computed the wrong number, and had done since it shipped

`photoSetIdentity` converts a preset's macros into a per-100 g density with `const base = num(p.portion_g) > 0 ? num(p.portion_g) : 100`. **`portion_g` was read on that one line and written nowhere.** `saveManualPreset` writes `portion` — a descriptive *label* ("1 mug") — and `normalizeSettings` passes presets through unnormalized, so no boundary could ever supply it. **The fallback was therefore the only path**, and a preset's whole-portion macros were treated as its density: a 150 g / 248 kcal preset re-picked onto a 200 g item returned **496 kcal against a truth of ~330**, silently. The comment on that line documented an intent the preset writer never implemented.

**Ruled: presets record `portion_g`, and where it is absent the re-pick is REFUSED, never assumed.** Assuming a denominator is the same fabrication as assuming a missing micronutrient is zero, and it is refused the same way — by name, with a message saying what would fix it. The denominator comes from a new optional **Portion (g)** field on the manual form, which also fills the item's own `grams`: R23 gave items that field and only the scan and photo paths ever filled it, so a hand-logged portion had nowhere to go. Absent stays absent, in both places.

**It rode along rather than shipping separately** — same reasoning as D57's reopen defect: the defect and the feature share a root, and R25's merge case *depends on this rail working*. Shipping add-item onto a broken rail would have left the crab-and-chicken case still uncorrectable, which is the thing that prompted the slice.

**And the existing gate was asserting the defect.** `R6-identity` used a preset with no portion and passed, because it expected the fallback's arithmetic. It is repointed by **stating** the portion as 100 g, so the same numbers now hold by declaration rather than by a silent default.

### Fork B — absent, never zero and never equal

An added item is pinned by construction: the user stated its grams, so nothing was estimated. **"It therefore takes no part in the shared-scale correction" does NOT fall out for free.** `photoShared` selects pins as `it.pinned && it.aiGrams > 0` and takes the geometric mean of `grams / aiGrams`. An added item is pinned, so what keeps it out is entirely the state of `aiGrams`:

- **equal to `grams`** — the obvious "symmetric" choice — enters it at ratio **exactly 1.0**, dragging the shared correction toward 1 and rescaling every unpinned estimate in the draft, with nothing on screen saying so;
- **zero** would claim the model estimated nothing, when it made no estimate at all;
- **absent** keeps it out of the pin set *by construction* rather than by a guard someone can later delete.

**Ruled absent.** The general statement, because it keeps recurring: *an added item has no AI estimate, so there is nothing for the shared-scale correction to be a correction OF.* Zero and equal both lie, in different directions.

Absence costs three render guards, each a real defect if missed: the slider `max` computes `Math.max(600, Math.round(aiGrams * 4))`, and `Math.max(600, NaN)` is **NaN** — a broken control; the row prints `est. N g`, which must be **omitted** rather than printed as 0; and the `fixed size` label describes an *estimate* that does not ride the shared scale, which an added row is not, so it says **added by you** instead.

### Fork C — the marker, and how it bites R23

`photoReopen` rebuilds a draft with `g = num(r.ai_grams) > 0 ? num(r.ai_grams) : 100`. An added item has no `ai_grams`, so without a marker it reopens with `aiGrams = 100` and, since `pinned` survives the round-trip, **re-enters the pin set at `grams / 100`** — rescaling every AI estimate in the meal. The reopened totals are right, so nothing looks wrong until the next scale correction: **the same failure shape R23 closed on this path, arriving from the other side.**

`added: true` is persisted and **declared in `normalizeItem` in this commit**, round-trip gated. **Fifth occurrence of the allowlist trap** (D45 warned; D49's `byokCount`; D55's `orig`/`edited_at`; D57's `grams`). It is now reflex rather than reasoning, which is the point of counting them.

C2 — inferring "added" from absent `ai_grams` within a `mealId` — was sound today and rejected anyway: it is an inference where a fact costs one allowlist entry, and it breaks the first time any other path writes a photo-meal item without `ai_grams`.

### Fork A — the macro source

**Typed for the portion eaten**, converted once into the per-100 g density the draft works in. *"The chicken was about 120 g and about 200 kcal"* is a sentence people can say; per-100 g density is a unit nobody holds a plate in. A preset fills the form rather than adding directly — the preset knows its own portion, not the one on this plate.

**The added item carries its own claim: `source: manual` (or `preset`), `confidence: eyeballed`.** Inheriting the draft's `ai-paste` would state that a model reported a food no model ever saw — D8's honesty rule pointed at its own draft.

**A4 — logging grams with no macros — was rejected on the log, not on taste.** D10 states: *"Macros … every complete day has them (0 for a fasting day), so the mean is Σ(day totals) / M — full coverage."* A macro-absent item does not make the log *honestly incomplete*; it **breaks an invariant** every totals consumer rests on. The honest repair is macro coverage annotation on the daily total, the ring and the averages — the *"from N of M"* shape D10 already uses for micros — which is a larger slice. **Recorded as the escalation**, not smuggled in under an add button.

**A3 — copying macros from another row — was rejected as a source** for the motivating case's own reason: crab and chicken are different foods, and copying crab's density onto chicken is fabrication wearing a decimal.

### Fork D — soft exclude, because the row cost money

A draft is not saved state, so the D44/D54 undo grammar does not reach it. But **an AI row cost a paid API call and cannot be regenerated without another one**, so destroying it on one tap is the expensive kind of irreversible. The row is therefore *excluded*, not removed: struck through, still visible, put-back-able right up to the save. A flag buys the reversibility a toast would have had to build.

Confirmed as the brief supposed: **zero grams is not a workaround** — `photoSetGrams` refuses `!(g > 0)`. Excluding the **last** item is refused, pointing at Discard: a modal offering to save nothing is the shape R21.5 exists to forbid.

`photoKeptItems` is the single definition of *"in this meal"*, and the pin set, the totals and the save all read through it — so an excluded row cannot steer a number it is not going to be part of.

### Fork E — inline, because the footer belongs to the outcome

D51 made the modal footer the **outcome commitment** surface: Save and Discard, fixed, never scrolling. Adding an item is draft *editing*, like every slider and identity picker above it, all of which are inline. In the footer it would compete for the thumb with Save — the one control D51 was written to protect.

### Fork G — micro coverage falls out

An added item carries no micros (no label was read; D8 forbids inventing them), and D10 counts only days *carrying* K. It is therefore **honestly absent from micro coverage rather than assumed complete**, with no new code. Gated as a confirmation rather than argued.

### D29 census — a new site, classified exempt, and a limit of the detector recorded

`photoAddItem` pushes into `PHOTO_DRAFT.items`, which the census's `\.items\.push\(` pattern matches. It is registered and **exempt**: the draft is held in memory and never persisted, so it creates no record and there is nothing to stamp; `photoSave` is the creation site for that path and is already registered and stamped. Census re-pinned **14 → 15**.

**The recorded limitation is the useful half:** the detector matches the *shape* `.items.push(`, not the *store*, so any array named `items` reads as a record store. That over-match is the **safe direction** — it asks rather than assumes — and the manifest is where the answer belongs. This complements D56's standing note that the census is a **creation** census and sees no mutations at all.

### Found by D60, in the session D60 was written

The defect pass planted eight defects. **Six failed their gates; two did not** — and the two that passed were properties this slice claims to have gated:

- `photoShared` reading excluded rows changed nothing, because the test excluded an **unpinned** row;
- `photoSave` writing excluded rows changed nothing, because the test **un-excluded everything before saving**.

Both gates were green, pre-registered, re-runnable — and unfalsifiable. That is instance 6's shape exactly, caught this time by the rule written a few hours earlier rather than by luck. The cases now exclude a **pinned** row and save **with a row still excluded**, and both fail against their defect.

**Recorded because it is the first evidence D60 pays for itself**, and because it says something about the rule's scope: the danger is not only a gate that asserts nothing, it is a gate whose *fixture* does not reach the property it names. A gate is not evidence until it has been seen to fail — including when the reason it cannot fail is the test data rather than the assertion.

### An environment note, since it produced a scary-looking result twice

Two harness runs during this slice reported `executed 0 · no SUMMARY line`, with three clean 1489/1489 runs on either side and no code change between them — Chrome contention from concurrent headless invocations, not a defect. **The runner behaved correctly**: it failed loudly with *"the suite did not finish"* rather than reporting a pass, which is D56's bar working. Recorded so the next session recognises the shape instead of hunting it.

## D62 — The dish fork: a stored answer beats a better guess (2026-09-08)

Governance only. **No code, no schema change, no `APP_VERSION` bump.** Five forks ruled. This is the fork D59's F1 named as upstream of the matcher, and it is upstream in the way F1 predicted: it changes what a corpus row *is*, and therefore row count, mask density and sparsity — every input to D59's sizing table.

### What changed since F1 named it

A real bowl: crab and chicken with onions, cooked together under one sauce. **Neither branch of the binary handles it**, and the reasons are different in kind.

**Decompose** returns components with guessed proportions, starts from a list that may be incomplete (occluded or visually similar components are simply not reported), and **loses the sauce and the cooking fat entirely** — because those belong to the dish and to no component in it.

**Whole-dish lookup** returns a real recipe's composition, but a **generic** one. FNDDS has ~5,400 recipe-calculated dishes built for "as consumed"; CNF's composite coverage is thinner. And no row exists at all for a dish invented in one person's kitchen.

### The reframe: the third branch is not a third strategy

Decompose and whole-dish are both **resolution strategies** — ways of turning a photograph into numbers. A user-defined composite is not a third one. It is **a stored answer**, authored once, that stops the question arising again.

That distinction does most of the work below, and it makes the branch far cheaper than it looks: **a composite is a preset with a component list.** Presets are already user-authored food objects, already carried in `settings` and therefore already exported, and already wired into the identity rail — `photoIdentityOptions` re-picks a draft item to a preset, and R25's add form fills from one. So a composite needs **no new matching mechanism**: *"this bowl is my crab-chicken thing"* is a user gesture at a rail that already exists, not a recognition problem.

**And it is the only branch that can represent what actually motivated the question.** Sauce and cooking fat are expressible in neither binary branch — decompose loses them because they belong to no component, whole-dish gets someone else's version of them. In a composite they are simply components ("2 tbsp oil") that were never visible in the photograph at all. **That is a stronger argument for the branch than reusability**, which is the argument it is usually given.

Which means a user-defined composite **is a recipe**, and the structural precedent is already ruled. **D27's regimen is a named timeline template** — user-authored, stored in state, instantiated only on explicit confirmation, never auto-applied, and built by *composition over existing machinery rather than a fourth record system*. Recipe : food :: regimen : timeline. Every pin in D27 transfers.

### Fork 1 — order: composite → whole-dish → decompose, and the last one is not a "fallback"

**Ruled as instinct had it, with one correction that decides the UI.**

The falsifiability frame is the right one, and it is sharper than the Warnsdorff gesture it replaced: **N components with N free proportions will fit almost any plate, so a decomposition's success is weak evidence.** A dish row has two free parameters — which row, how many grams — so a fit is much less likely to be accidental. Prefer the constrained hypothesis because it is the falsifiable one.

**But the counter cuts the other way at the moment of acceptance, and that is what the ruling turns on.** A bad decomposition is **visible**: "rice, 120 g" in a bowl with no rice. A bad dish match is **invisible**: one authoritative-looking row with nothing to inspect. The more constrained branch is also the one whose failures the user cannot see.

**So a whole-dish match is a HYPOTHESIS TO CONFIRM, never a result handed over.** Same confirm-first grammar D51 imposes on the capture outcome and R6's lead question imposes on the dominant item. The ordering is not softened; the acceptance is.

**And decompose is not a fallback — it is a different KIND of claim.** A lookup and an estimate-with-invented-proportions are different assertions about where a number came from, and **they must never produce indistinguishable records.** Which branch resolved a meal is therefore a **provenance fact that reaches the record**, alongside `source` and `confidence` — D57's rule that provenance is a fact and reliability is a claim, applied to resolution strategy.

*Rejected: decompose-first with whole-dish as refinement.* It inverts falsifiability — it starts from the hypothesis that cannot fail and only sometimes replaces it with one that can.

### Fork 2 — cross-source dish resolution: yes

**Ruled: a dish resolves against FNDDS regardless of locale, with provenance on the row.**

The argument brought to this fork was that refusing would mean *"silently producing worse data to preserve a locale purity I never asked for."* **The correction is that the purity does not exist.** Every barcode lookup already goes to `world.openfoodfacts.org` — the global endpoint — and takes whatever the crowd entered, from any country. There is no locale invariant to protect here; there would only be a new one, invented specifically to make dish resolution worse than it needs to be.

**Two consequences accepted deliberately rather than discovered later:**

**FNDDS dishes are recipe-calculated from US ingredients** — US enriched pasta, US fortification baselines, US dairy. The mixing is therefore **not neutral across nutrients: macros travel well, fortification-sensitive micros travel badly** (folate in flour, vitamin D in milk, iodine in salt). A cross-locale dish row is weakest exactly where D8 is most careful. **Recorded now, acted on when the micros layer exists** — not before, and not never.

**No badge.** D53 already ruled *progressive disclosure of provenance*: provenance collapses behind a one-tap line, safety never does. A per-meal source badge would be **a second provenance surface competing with the first**. The source rides **on the row**, disclosed the way D53 disclosed everything else, so a meal carrying `cnf:` components and an `fdc:` dish row is legible without new chrome.

### Fork 3 — a composite is a preset with a component list

**Both proposed structures are rejected, and cleanly.**

**Not a corpus block.** D59 drew the line: the corpus is an **asset, not user data** — excluded from export, re-acquired rather than restored. A composite is *authored by the user* and fails that test in every clause. Storing it in the corpus would mean **a person's own recipes vanish on restore** and return only if a source refresh happened to contain them, which it never will. That is the worst available outcome for this artifact.

**Not a re-resolving draft.** It violates the freeze principle in spirit, and it is **worse than log drift**: a saved object whose numbers silently change between two uses means **the same gesture produces two different meals**, with no way to see which one was got.

**Ruled: composition computed once and FROZEN, with the component list retained as provenance** — the `orig` / `ai_grams` correction-loop shape this app uses everywhere: what it was built from, kept beside what it resolved to.

**With an explicit, user-invoked recompute — never automatic.** That is D13's ruled refresh pattern verbatim (*"explicit, manual… never automatic, never a background revalidate"*), and it buys corpus improvement without the drift.

**Export follows for free and needs no new rule:** presets live in `settings`, `settings` is in the exported blob, so composites are exported while the corpus is not — the asset/data boundary D59 drew, landing exactly where it should.

**And a property worth naming:** because the composition is frozen, **a composite still works on a device with no corpus at all** (D59 Fork E1). Only *recompute* is unavailable. It degrades in the right place.

### Fork 4 — the classification is a user gesture, not a model output

**Dish-vs-components is not a property of the photograph.** The same bowl is one dish if a good row exists, separate components if it does not, and a composite if one has been defined. The answer depends on **corpus contents the model cannot see** and on how the person thinks about the meal. Asking the model to classify is asking the wrong entity a question that is not about the image.

The model also **already classifies implicitly** — returning one item for a mixed bowl *is* the "one dish" answer. So the real choice is not whether classification happens; it is whether to add a field the model can newly get wrong to a **versioned, shipped template** (D11), where every added field is a new failure mode.

**Ruled: no template change.** The corrections stay where they are: **split** is identity-correct-plus-add, which R25 shipped; **group** is the one gesture this fork implies, and it is small.

### Fork 5 — confidence is the MINIMUM; coverage is the INTERSECTION

Two different operations, for two different reasons, and the split is the substance of this fork.

**Confidence: the minimum.** It is ordinal (`eyeballed < weighed < measured`) and a composite is no better than its weakest component. The minimum runs over the components **and over the proportion claim itself** — proportions are a claim, so all-`measured` components with hand-stated proportions yield an `eyeballed` composite. That is D57's demotion rule (hand-correcting a measurement makes `measured` false) applied one level up.

**Coverage: the intersection — and this is the half that would otherwise have shipped a silent lie.** Summing micronutrient values across components where one component lacks potassium produces a potassium figure that is **understated but looks complete**. That is worse than absence: **absence is honest, and an understated figure is a wrong answer wearing decimals** — precisely what D8 exists to prevent.

**So a composite carries micronutrient K only if EVERY component carries K.** Otherwise K is absent from the composite. **Union for values, intersection for presence** — and with D59's mask this is literally an `AND` of the component masks, which is the first place that representation earns its keep.

### Scope

**Minimum viable is: define once from a draft already corrected, reuse by name through the existing identity rail.** Nothing else. A composite that accretes becomes a recipe book — CRUD, editing, scaling, search — and that is a Phase-4 candidate, not this. D27's *"composition over a fourth record system"* is the discipline that keeps it from becoming one.

### Sequencing, recorded as stated rather than softened

**This is the third session running on governance and representation rather than the matcher F1 named as next.** This one was legitimately upstream and genuinely changed the corpus shape — it is why a composite is user data rather than a corpus row, and why coverage is an intersection.

**But after this ruling the matcher has no remaining upstream blocker.** If a fourth governance question surfaces before a line of matcher code exists, **that pattern gets examined rather than answered.** The evaluation set is the first thing to build — a few hundred hand-labelled `(query → correct row)` pairs drawn from meals actually eaten — and it needs no persistence, no corpus substrate and no further rulings.

Recorded here because a governance log is read by future sessions as evidence, and a project that keeps finding tractable questions upstream of a hard one has found a way to look busy. **Tractability is not priority** (D59), and this is the entry that says so about its own sequence.

### What this entry does not rule

The matcher. The mask's word-1 slot list. The grouping gesture's surface. ~~Whether a composite's components may themselves be composites — deferred deliberately, because the answer is obvious in the small (yes) and dangerous in the large (unbounded recursion in a nutrition calculation), and nothing needs it yet.~~ **Nesting was deferred here and ruled within the hour — see the amendment below.** The sentence is struck rather than removed, because a deferral that was closed immediately is a different fact from one that still stands, and the next session should be able to see which.

### Amendment — nesting, ruled rather than left open (2026-09-08)

**Ruled: NO NESTING. A composite's components are foods, not composites. Flat, one level.**

The appeal is real in the small case — a sauce defined once and used in three dishes is exactly the thing a composite is for, and refusing it looks like a small, arbitrary limit.

**It is refused because of what arrives with it, not because the small case is wrong.** Nesting brings a **dependency graph**:

- **cycle detection** — nothing prevents a composite referencing an ancestor, and a nutrition calculation that does not terminate is a worse failure than one that is merely limited;
- **recompute propagation** — D13's explicit manual recompute is a single, comprehensible action on a flat composite; on a tree it becomes a cascade, and the question *"what else just changed?"* has no answer the user can see;
- **confidence and coverage over a tree rather than a list** — Fork 5's minimum and intersection are stated over components. Over a tree they still work, but the *weakest leaf anywhere in the tree* now silently sets the whole composite's claim, several levels from where anyone is looking.

**None of that is needed by anything on the board, and all of it becomes load-bearing the moment one nested composite exists.** That asymmetry is the ruling: the cost is not paid gradually as nesting gets used, it is paid in full by the first instance.

**If the sauce case becomes real it gets ruled deliberately** — as its own fork, with cycle detection and recompute propagation argued rather than inherited. What is refused here is nesting **arriving as an implementation detail**, which is how a dependency graph normally enters a codebase: not decided, just permitted.

## D63 — The no-key floor was dead, and the gate that named it asserted presence (R26, 2026-09-08)

`APP_VERSION → 0.25.1`; **schema unchanged at v6**. A fix, not a feature.

**The floor:** without an API key, copy-the-prompt → paste-the-reply is the *only* route from a photo to a meal. Every capture decision since R21 rests on that route existing. It did not work.

### Not the regression it looked like

The report suspected R21, R24 or R25 — all three touched the Photo tab this week. `git log -S 'id="promptTemplate"'` puts the cause at **v0.9.0 (D30)**, weeks earlier. Recorded because the instinct was reasonable and wrong, and because the defect pass, not the blame guess, is what located it.

### Two defects; the second is what made it dead rather than merely ugly

**1. Two elements shared `id="promptTemplate"`** (and `promptVersion`) — one on the photo surface, one in Settings. `renderPromptCard` used `getElementById`, which returns only the first. **The Settings prompt box has been empty on every build since v0.9.0.**

**2. `copyPrompt` always reached for that same first box, whichever card was tapped.** From Settings, that box sits inside the **hidden** photo pane, and a hidden textarea cannot be focused or selected — so `execCommand('copy')` fails. The Clipboard API fallback carried `.catch(function () {})`, so **a rejection was swallowed**, and the toast then said *"Select-all + copy the prompt"* while pointing at a box containing nothing.

**The stated recovery was impossible.** That is the difference between a rough edge and a dead path: the app told the user to do something that could not be done, and reported no failure while doing it.

### The fix

- **Distinct ids, and every box filled.** `renderPromptCard` writes to `[data-prompt-box]` — all of them, selected by attribute so a third card would be filled rather than silently joining the dead one.
- **`copyPrompt(from)` copies from the box the finger was on**, found by walking up from the tapped element until an ancestor holds a prompt box. Deliberately **not** keyed to a wrapper class: the two cards do not share one — Settings' is a `.card`, the photo pane is not — and the first version of this fix keyed to `.card` and broke for exactly that reason, which is the same mistake one layer along.
- **The box is filled unconditionally, before any copy is attempted.** Whatever the clipboard does, the manual route must be followable; *"select it and copy"* is only honest advice when the text is there.
- **The rejection is reported, not swallowed.** A failed `writeText` now says so and points at the box, rather than leaving a toast that claims nothing happened while implying something did.

### How it passed the suite — presence, not content

The nearest existing case asserted `#promptTemplate` **exists** inside `#pane-photo`. It existed throughout. Everything else exercised `AI_PROMPT_TEMPLATE` and `AI_PROMPT_SAMPLE` as **constants**, through `ingest()` and `parsePhotoMeal` — the R6 template↔ingest self-consistency gate is a gate on the *constant*, and it was green and correct the entire time the surface was broken.

**Nothing asserted that the constant reaches the box, or that the copy action yields text.** That is D53's and D56's *presence was necessary and not sufficient*, one layer up: the element was present, the constant was consistent, and the user had nothing to paste.

The new cases assert **content and outcome, on the shipped surface, from both cards** — every box holds the template after boot; the shell contains **no duplicate id at all**; Copy puts the real prompt on the clipboard from the photo surface and from Settings; and the tapped card's box is the one that gets filled.

### The defect pass, and what it caught in the gate

Four defects planted. Two failed immediately. **Two passed — and neither was an assertion problem:**

- *the box is filled* held whatever `copyPrompt` did, because **both boxes are already full at boot**. The fixture now blanks every box first, so the case measures the function rather than the boot.
- *the tapped card's box is used* held with the ancestor walk removed, because the visible-box fallback independently satisfies the property whenever only one surface is open — **a legitimate pass, not a gap**. Rather than record a caveat, the case now opens **both surfaces at once**, where two boxes are visible and only the tapped one may be written. That makes the walk load-bearing and the mutation falsifiable.

Both findings are generalised into **D60's Clause 4** in the same commit: *the fixture is as falsifiable as the assertion.*

### The instruction copy, revisited

Both notes described only the manual route, which was written before BYOK capture existed and never revisited. They now describe **both**: the photo surface names Take photo / Choose photo as the with-a-key route and the prompt as the without-one route; the Settings copy points at where capture lives. The D8 honesty line — *macros only, never micronutrients from a photo* — is kept verbatim on both.

**Count delta: 1489 → 1498** (+9), re-pinned deliberately in the same commit.

## D64 — A parse failure wearing a timeout's message, and the reply it threw away (R27, 2026-09-08)

`APP_VERSION → 0.26.0`; **schema unchanged at v6**; **`AI_TEMPLATE_VERSION` deliberately unchanged at 3** (see below). A fix, not a feature.

**Reported as:** capture timed out on a photo Grok answers directly in about ten seconds.

### Diagnosed in the order the report set, because the order was right

**1 — The counter is unambiguous, and it is the diagnostic to reach for first.** `byokCount()` fires immediately before each `byokCall`, and the retry fires **only** when `r1.ok === true` and the parse failed. So a count of **+2 is proof the reply arrived and failed validation**; +1 is proof it did not arrive. Nothing else has to be inferred.

**2 — Confirmed, and the mechanism is worse than "both attempts burned the budget."** Every call gets its **own full 120 s timeout** — the timer is per-call. A slow first attempt followed by a full second one kept the user waiting **up to 240 seconds** and then aborted, reporting a **timeout**. The parse failure had already happened; the message named the wrong cause. **A symptom that names the wrong cause is worse than a silent failure**, because it sends the next session to the network layer.

**3 — Cleared: the template IS reaching the model.** `byokCall` sends `AI_DIRECT_PREFIX + aiPromptText()` through `byokBody` into the message content beside the image. No duplicate-id-class defect on this path. Recorded because the suspicion was reasonable — D63 had just found exactly that shape one day earlier — and because clearing a hypothesis is evidence too.

**4 — The fallback did not get the raw reply, and this is the defect that cost data.**

```js
return byokFallback('', r2.error);   // r1.text discarded
```

When the **retry** failed for any reason, the **first reply was thrown away**. It had arrived. It had been paid for. It was the only thing the user could act on. The paste box — the surface the whole no-key design rests on — was handed an empty string.

Compounding it: `byokLog` writes only to `console.info`, which is unreachable on a phone. So the response existed, was discarded, and left no trace the user could read.

**5 — The template was being sent and the model returned prose anyway**, so hardening is warranted — but the two paths do not share a lever, and that distinction is the substance of this entry.

### The API path gets a constraint; the copy-prompt path only ever gets words

**`response_format: {type:'json_object'}` and a `max_tokens` bound are now sent on the capture call.** The template has said *"Reply with JSON ONLY"* since D11 and the model answered with tables, per-100 g reference values, micronutrients and dietary commentary regardless. **An instruction is a request; `response_format` is a constraint.**

The token bound matters on its own, and not for parsing: **an essay is not merely unparseable, it is slow.** A model writing commentary emits many times the tokens of a 200-token object, which is a direct cause of the wall-clock failure. Bounding the answer bounds the wait.

**This could not be verified against the live API from here** (no key on this machine), so it degrades rather than gambles: `jsonMode` is **declared per provider** rather than assumed, and a provider that rejects the field with a 400 is **retried once without it**. The retry cannot loop — it sets `noJsonMode`, and the branch requires that flag unset.

**The copy-prompt path has no equivalent**, and it is the path the evidence came from. There the words are the only mechanism, so the template now refuses **by name** what the model actually did: no tables, no reference values for foods absent from `items`, no commentary, reply starts with `{` and ends with `}`, and the JSON-only instruction repeated **last as well as first**.

**`AI_TEMPLATE_VERSION` stays at 3.** D11 ties that number to the **schema**, and the item contract is unchanged — same `grams`, `per100`, `scale_linked`, `dominance`. Bumping it would tell a user their saved copy is incompatible when it still produces valid output. The version tracks the contract; wording hardens without it.

### The fixes, and what each one closes

- **Whatever arrived reaches the paste box.** `byokFallback(r1.text, …)` — the first reply survives a failed retry, with a message saying it did not match the template but is what the model sent.
- **A retry is not started without the budget to finish it.** Below `BYOK_RETRY_MIN_MS` of the call budget the second attempt is declined and the first reply is handed over instead. This is what stops a parse failure from being reported as a timeout.
- **The retry that does run is bounded by what is left**, not given a fresh full budget.
- **The decode/parse outcome is logged with its size and elapsed time**, so the next occurrence says how far it got.

### The defect pass

Six defects planted, six failed their gates — including **the reported bug itself**, reproduced by restoring `byokFallback('', …)` and watching `R27-keep` fail. The two structural gates (`response_format`, `max_tokens`) and the provider-declaration gate fail against their own removal; the template gate fails against removing the closing restatement; the retry-floor gate fails against `if (false)`.

**Count delta: 1498 → 1512** (+14), re-pinned deliberately in the same commit.

### Recorded because it will recur

**The escape-sequence trap, three times in one session.** Writing JS string literals through a Python heredoc, `\n` was expanded into a real newline three separate times — twice breaking a string literal outright and once producing a gate that could not parse. Each time the suite said so immediately (`executed 0`, *"the suite did not finish"*), which is the runner behaving exactly as D56 requires. **The tooling lesson: build JS source through raw strings, or avoid the escape entirely by choosing test data without newlines in it.** Cheap to avoid, and it cost three round trips here.

## D65 — Instrument before tuning: where the capture time actually goes (R28, 2026-09-08)

`APP_VERSION → 0.26.1`; **schema unchanged at v6**. **Instrumentation only — nothing about how capture works was changed.**

Slowness had been reported three times, and neither side could see why. `byokLog` writes to `console.info`, which is unreachable on a phone. **A number nobody can read is not instrumentation**, and three rounds of hypothesis without measurement is where this had got to. So the ruling for this slice was: measure first, tune nothing.

### The correction that invalidated the earlier benchmark

The fast Grok responses the report had been comparing against were **web-search-augmented** — the chat identified the restaurant, the specific menu item and nearby locations, and quoted published calorie figures. That is a tool-using pipeline, not a constrained vision call. **The 20 s-versus-100 s comparison proves only that the chat's tool path is fast**, and it is withdrawn as a benchmark. Recorded because it had been steering the diagnosis, and because a benchmark that measures a different pipeline is worse than none.

### What is now measured, and the split that matters

Every capture reports, on the **outcome modal** — the surface D51 already owns, rather than a second one — and on **success as well as failure**:

- the **payload actually sent**, in bytes and pixels (base64 inflates the JPEG by 4/3, and that is what crosses the wire; the target it was aimed at is not evidence of what left the device);
- **encode time**, separately from call time;
- per attempt: **time to first byte**, **total**, **HTTP status**, **reply length**, and **whether `response_format` was sent**;
- whether the 400-retry fired, named as `response_format REFUSED, retried without`;
- the **attempt count** — a second call can no longer hide behind one spinner;
- **total elapsed**.

**The load-bearing distinction is TTFB versus body.** `fetch` resolves its `Response` when the *headers* arrive and `res.text()` when the body completes. A long time-to-first-byte means the model is **thinking before it writes**; a short TTFB with a long body means it is **writing a great deal**. **Those have opposite fixes**, and without the split every report reduces to "slow" — which is exactly where three reports had left it.

The line is monospace and deliberately **selectable**: it exists to be read off a phone and pasted back verbatim.

### Verified against the live docs, not assumed

**grok-4.6 accepts image input** — *"Text and image input; text output"*. One models-index table said otherwise; the model's own page contradicts it and captures demonstrably work, so the index summary is the unreliable source. Recorded because "the model may not be vision-capable" would have been a serious hypothesis had it been true.

**`reasoning_effort` defaults to `"high"`, and this app has never set it.** Accepted values are `low | medium | high | xhigh`; **reasoning cannot be disabled**; `"low"` is documented as *"some reasoning tokens, but still fast"*, explicitly for latency-sensitive applications. So a reasoning model runs **high-effort deliberation** to look at a photograph and emit fifteen lines of JSON.

**This is the strongest candidate and it is deliberately NOT changed here.** The instruction for this slice was to instrument before tuning, and the reason is sound: with three unmeasured reports already on the record, a fix applied now would be a fourth guess, and if it appeared to work nobody would know which of the changes did it. The trace will confirm or refute it in one capture — a long TTFB with a short body is the signature.

**`response_format: {type:'json_object'}` is supported** on grok-4.6, alongside `json_schema`. So R27's change should be valid and each capture should be a single call — but the trace now proves that per attempt rather than leaving it inferred.

**Also available and unused:** `image_url` accepts a `detail` parameter controlling image quality, a second latency lever. Noted, not pulled.

### Gated, because instrumentation that stops reporting is the worst kind

Four defects planted, four fail: TTFB not recorded; payload size not recorded; a second call not recorded; and **the trace recorded but never reaching the surface** — which is precisely the failure that made this invisible for three reports. The surface cases needed the outcome-modal elements added to the harness page: without them `renderCaptureOutcome` returns early and the cases would have **passed by never running**, which is D60 Clause 4 exactly, caught by the clause written yesterday.

**Count delta: 1512 → 1521** (+9), re-pinned deliberately in the same commit.

## D66 — The 41 seconds were deliberation, not transfer (R29, 2026-09-08)

`APP_VERSION → 0.26.2`; **schema unchanged at v6**. **One change**, deliberately, so the next measurement is attributable.

### The measurement that ended three rounds of guessing

From a real capture on the device, with D65's instrumentation:

```
249 kB · 960×1280 · encode 0.1s | call 1 · first byte 41.2s · done 41.2s
· HTTP 200 · reply 477 chars · json_object sent | total 41.3s
```

**`first byte 41.2s`, `done 41.2s`.** The body arrived in no measurable time after the headers. **Every one of those 41 seconds was spent before the first token was written**, which is the signature of deliberation, not of transfer, generation or upload.

And every competing hypothesis died in the same line:

| suspected | measured |
|---|---|
| payload too large / upload time | **249 kB**, 960×1280 — the downscale is working |
| encode cost | **0.1 s** |
| `response_format` refused, two calls each time | **one call**, `json_object sent`, HTTP 200 |
| model returning prose again | **477 chars**, honouring the template |

Three reports of "slow" had produced three plausible theories and no facts. One trace settled it in a single line. **That is the entire argument for D65 having been its own slice.**

### The change, and only it

`reasoning_effort: 'low'` on the capture call. xAI documents the parameter as `low | medium | high | xhigh`, **defaulting to `"high"`**, with reasoning **not disableable** — `"low"` is the floor, described as *"some reasoning tokens, but still fast"*, for latency-sensitive work. The app had never set it, so every capture ran **high-effort deliberation** to look at one photograph and emit fifteen lines of JSON.

**Declared per provider**, exactly as `jsonMode` is — never assumed of a provider that has not stated it.

**Nothing else was touched**, and that was the instruction. The next trace differs from this one in the first-byte number and in nothing else, so an improvement is attributable to this change rather than to the weather.

### The one thing that had to change to keep it attributable

The trace line now also reports **which effort was sent** (`effort low`, or `effort default(high)` when none is). Without it a changed first-byte time proves nothing — the parameter might simply not have arrived. Instrumentation that cannot confirm the intervention was applied cannot attribute the result to it.

### Two independent degrade flags, not one

A provider that rejects an optional field must not cost the capture, so a `400` naming a field is retried once without **that** field. The two flags are **independent**: refusing `reasoning_effort` must not silently also drop `response_format`, or a provider that dislikes one would quietly cost the other and the trace would report a state nobody chose.

A **generic** refusal — `unknown` / `unsupported` with no field named — strips **both at once** rather than degrading twice, so the worst case is two calls and never three.

### Gated

Four defects planted; the fourth needed its fixture repaired first. *"A provider that has not declared it is never sent it"* passed against hardcoding `'low'` inside `byokCaps`, because the case asserted through `byokBody(..., null)` — a null never reaches the code that decides. It now asserts through `byokCaps` with an **undeclared provider**, and fails. **D60 Clause 4, one day old, catching its third instance.**

**Count delta: 1521 → 1530** (+9), re-pinned deliberately in the same commit.

### Closed by measurement (2026-09-11)

The next capture on the device:

```
656 kB · 960x1280 · encode 0.1s | call 1 · first byte 10.7s · done 10.7s
· HTTP 200 · reply 640 chars · json_object sent · effort low | total 10.8s
```

**41.2s -> 10.7s.** One call, `effort low` accepted and applied.

The signature is unchanged — first byte and done are still identical — so the time is still **all deliberation before the first token**. There is simply far less of it.

**And the cause is isolated, because both competing explanations moved the wrong way.** The payload was **2.6x larger** (656 kB against 249 kB) and the reply **longer** (640 chars against 477, now carrying three identity candidates), and it was still four times faster. Neither upload size nor output length can account for a speed-up that happened while both increased.

D65 named `reasoning_effort` as the strongest candidate and refused to change it in the same slice that measured it. That refusal is what makes this one line conclusive rather than suggestive. **The question is closed.**

### Flagged, not touched

The capture identified a single item in frame as *"chicken nugget"* — the identity-first case discussed under the dish fork (D62). **Deliberately not addressed here**: touching the template in this commit would have made the next first-byte measurement unattributable, which is the whole point of the slice. Recorded so it is picked up as its own question rather than lost.

## D67 — Macro coverage: the invariant D10 asserted, and the item that breaks it (R31, 2026-09-09)

`APP_VERSION → 0.27.0`; **schema v6 → v7**. Built as R30's Fork F1: the prerequisite ruled out of the identity slice so it could fail its own gates separately.

**Registered after R30 and landing before it.** R-numbers record when a slice was written down, not when it ships. Recorded so the out-of-order pair reads as the ruling it is.

### What it is for

R30's off-ramp must be able to end in *"none of these"*, which produces an item with **grams and no composition**. D10 rules macros as **full coverage** — `Σ(day totals) / M`, no annotation, no per-nutrient count — and every macro consumer in the app rests on that sentence.

**R25 hit this from the other side and refused it**, as its Fork A4: *"Macro-absent items break that invariant and every consumer resting on it… Recorded as the escalation if macro coverage is ever built; not smuggled in under an add button."* This is that escalation, built — and not smuggled in under an off-ramp either.

### The failure being prevented, stated exactly

`normalizeItem` coerced every macro through `num()`, so an item with no `kcal` was stored as `kcal: 0`. A day containing it summed to a total that was **understated and indistinguishable from complete**. That is D8's absence-is-not-zero rule arriving at the **daily ring** instead of at a micronutrient, and it is worse there, because the ring is the surface read first.

The fix is the rule the codebase already applies one field along, in `normalizeItem`'s own comment for `grams`: *"ABSENCE IS MEANINGFUL AND PRESERVED. An item with no known portion has no `grams` — never 0, which would claim a weightless meal."* An item with no composition has no `kcal`, for the same reason and by the same mechanism.

### Seven forks, all resolved from the log rather than referred up

**1 — Explicit flag, absent macros.** `unresolved: true`, and the six macro keys omitted. Not inferred from the missing keys: R25's Fork C1 ruled the same question for `added` — *a read of a fact rather than an inference* — because an inference breaks the first time another path writes an item without them. `soluble_fiber_g` is *"always present, even at 0"* on every other path and deliberately absent here: **0 g of soluble fibre is a measurement, and none was taken.**

**2 — v6 → v7, and the bump is the point.** D29's asymmetry test: an older app strips `unresolved` and then coerces the absent macros to `0`. That is not a degraded future analysis, it is **a wrong number presented as a fact** — the side of the line D57 put `grams` on. The forward guard is what protects that older app; **the bump is what arms it.**

**3 — Averages exclude, and say so.** D10's micro rule applied to macros without amendment — *"A day without K data is excluded from K's mean, never counted as 0."* The macro mean now has a denominator of its own, `nMacro`, and the block reads *"from N of M days"* only when it differs from M.

**4 — Trends exclude too.** Plotting a partial day states in geometry the understatement the summary refuses to state in text — the encoding dodge **D24** refused for colour and **D53** for a met/unmet cue. The omission is **counted and captioned**; a silently shorter series looks like days that were never logged.

**5 — The coverage line never collapses.** D53 ruled *provenance collapses behind a one-tap line, safety never does*. Coverage is not provenance — it is a statement that the number on screen is incomplete.

**6 — No producer, and no resolver.** Nothing in R31 creates an unresolved item; R30's off-ramp does. Building one here would be R30 arriving early. The item **editor** was the near-miss: its macro fields render through `rDisp`, which turns `undefined` into the string `"0"`, so an unresolved item would have opened with six zeros in editable fields. They are now **empty and disabled**, with the reason on the surface. Accepting numbers there without clearing the flag would have been the worst option available — `normalizeItem` strips macro keys while the flag is set, so the numbers would survive in memory, be ignored by every total, and vanish on the next export/restore. **Refusing to take them is honest; taking and losing them is not.**

**7 — A sequencing consequence for R30.** H1 ruled the calibration fields at v6 → v7. R31 takes v7, so **R30 becomes v7 → v8**. The ruling is unchanged; only its number moved.

### Data-loss implications, ruled before the storage change

`migrateV6toV7` is a **structural passthrough** — no existing item is unresolved, so `days` comes through byte-identical and only `version` moves. In place under the stable key (D1), pre-migration snapshot first (D7). Nothing is dropped, coerced or reordered, and the key order of a **resolved** item is byte-for-byte what it was before v7, so an export fixture written against v6 still matches.

### The defect pass, and the gate it caught

**Ten defects planted, and one gate was not evidence.**

`R31-total` asserted *"the day-total row says so"* against the **whole day view** — and passed with the day-total note deleted, because the **meal group head** carries the same sentence for the same three items and satisfied it instead. Two surfaces make the same claim, and asserting on their union let one go missing behind the other. Each is now asserted where it lives, and **both fail against their own removal** — which is why the pass runs ten defects rather than the seven first written.

**D60 Clause 4's fourth instance**, and the first where the flaw was in the assertion's *scope* rather than in the fixture's reach.

The other seven behaved: restoring the `num()` coercion fails `R31-absent`; including partial days fails `R31-avg-exclude` (on a fixture chosen so excluding gives 200 and including gives 300 — a fixture where they coincide would have passed either way); dropping the allowlist entry fails `R31-flag`, the **seventh** occurrence of that trap; plotting partial days fails `R31-trend`; removing the goal-block line fails `R31-ring`; enabling the editor's zeroed fields fails `R31-edit`.

### Re-pinned, deliberately, in the same commit

**Count delta: 1530 → 1579** (+49). **Eleven existing version assertions moved with the schema**, each one a case that deliberately pinned "my slice bumped nothing" — they now name v7 and R31 as the reason. Two fixtures had to move with it: the "future blob" (v7 → v8, or it stops being ahead of `SCHEMA_VERSION` and stops testing the guard) and R23's forward-guard case, which asserted v7 was refused.

**One of those re-pins was over-applied and put back:** a blanket replace also rewrote `migrateV5toV6`'s own stamp from 6 to 7. That function is one step of the chain, not the chain, and asserting 7 there would have asserted the wrong function's job.

### Two consumers the ruling did not enumerate, and one of them was wrong rather than short

F1's scope read *"daily total, ring, averages, export"*. That was the ruling's **list**; it was never the **rule**, which is that no consumer treats absence as zero. Two more rest on the invariant, and the build found them by looking rather than by assuming the list was complete.

**The history row** prints the same understated kcal the day view does, so it now carries the same sentence. Short, not wrong.

**The fasting detector was wrong.** `fastEvents` selects a fast-breaking food event with `num(it.kcal) > 0`, so an unresolved item scored **0 and did not count as eating**. Every other consumer of this absence understates a total; this one **invents a fast that did not happen** — a longer streak, a confirmed candidate, a figure the user might act on, assembled out of a meal they ate. Unknown calories are not no calories, so the item now counts as a food event on the strength of having been eaten at a time, which is all the detector ever needed from it.

Recorded because the enumeration was mine and it was incomplete, and because the difference between *understating a number* and *asserting an event that never occurred* is the difference this slice exists to police.

### An environment note, and the same shape as D61's, one cause deeper

The full suite failed once during this slice with **three** gates down — `bm-slider` and `capture-outcome` producing **no verdict** (*"an internal WebSocket error occurred"*), and `lab-form` reporting **`rows=0`**, meaning it measured a page that had not rendered. All three passed on individual re-run, `lab-form` at `rows=14`. None of the three touches anything R31 changed.

**The next full-suite run was killed by the OS for low memory**, which names the cause the earlier flake only hinted at: the machine was at **84% of 15.7 GB with 2.5 GB free**, the user's own Chrome holding 3.9 GB across 34 processes. A CDP gate launches another Chrome and drives a real page; under that headroom the socket dies or the page has not painted when it is measured.

**The runner behaved correctly in both directions** — it failed loudly and by name rather than reporting a pass, which is failure shape #4 working as built. Recorded because *three* simultaneous gate failures with no related change is exactly the shape that sends a session hunting a regression, and because D61's note covered `executed 0` from Chrome contention without naming memory pressure as what produces it.

**Not a reason to re-run until green.** Individual passes are not the evidence; the runner's header says why. The verdict this slice rests on is a clean full-suite run.

**Second occurrence, R33 (2026-09-11), which turns it from an anecdote into a pattern.** A full-suite run was again killed by the OS for low memory, at **85% of 15.7 GB with 2.34 GB free** and the user's own Chrome holding **6.4 GB across 51 processes**. No orphaned CDP instances were left by the killed runs — checked, zero — so the pressure is the working environment rather than anything the suite leaks.

**What this means practically:** a killed run is not a failed run and must not be recorded as one, and a run that dies this way tells you nothing about the code. Re-running is legitimate here in a way that re-running a FAILED suite is not, and the distinction is worth keeping sharp: a kill is the absence of a verdict, a failure is a verdict. D56's runner refuses to let silence count as a pass; this note refuses to let a kill count as a fail.

### Flagged, not touched

R30 is now unblocked. Its off-ramp has somewhere honest to land, and the identity-first question can be built against a totals layer that no longer has to pretend an unresolved item ate nothing.

## D68 — Identity before portion, and the off-ramp that does not pretend (R30, 2026-09-11)

`APP_VERSION → 0.28.0`; **schema v7 → v8**; **`AI_TEMPLATE_VERSION` 3 → 4**. All nine forks ruled as recommended; R31 shipped first as F1 required, so the off-ramp has somewhere honest to land.

### What was wrong

A glass of wine was identified as apple juice, and the confirm modal then asked for the **grams**. The question presupposed the identity and moved attention to the number, so a volume was corrected for a drink that was not being had. Alcohol versus sugar: not close, invisible in the photo, material in the record. A single item resolved as "chicken nugget" the same way.

**The framing, ruled 2026-09-09 and built to:** the threshold is the **weaker** defence. It catches a hesitant answer, not a confidently wrong one, and the wine was almost certainly returned confidently. *Identity is asked first* is the load-bearing gate; below-threshold suppression is the narrower second. **A confidently-wrong next capture is not evidence the threshold is misset.**

### The forks, as built

**A1 — the template asks for three.** Each item now carries `alts: [{name, p}]`, best first, with `alts[0]` required to equal `name`. The primary contract is untouched, so a degraded reply still parses. The key is **`p`, not `confidence`**: `confidence` already means the item ordinal `eyeballed | weighed | measured`, and shipping the model's number under that name would have met the item contract at ingest.

**The top1 rule is enforced by detection, not repair.** A reply whose list contradicts its own `name` keeps `name` authoritative — `per100` describes it — and drops to `unsure`. Reordering the list to match would hide exactly the degradation the rule exists to detect; discarding the meal would throw away a paid call over a self-inconsistency the user can simply answer.

**`AI_TEMPLATE_VERSION` 3 → 4**, on the distinction that separates this from D64's counter-precedent: a v3 copy still produces a valid **meal** but cannot produce an **off-ramp**, so it is degraded rather than merely older.

**B1 — `single` is decided once**, at draft construction, and frozen. The named price: excluding a plate down to one row does not summon the identity question, and adding a row does not dissolve it. Gated as `R30-frozen` rather than left to be discovered.

**C1 — the plate keeps its design**, and the low-confidence dominant item carries the off-ramp *beside* its estimate. Suppressing it would strand the shared-scale correction, which needs an estimate to anchor from.

**D1 — one renderer, two mounts**, and a third that the build found: the grams lead block **replaces** the lead item's row, so on a plate the dominant item — the very item C1 is about — had nowhere to show its alternatives. Both `R30-plate-unchanged` and `R30-none-of-these` failed on it. The lead block now carries the off-ramp and the composition-absent note.

**E1 — a candidate is a name, not a nutrition profile.** Picking one that is not a preset routes to R31's unresolved path with the name recorded. Keeping the top-1 macros under a different name would be apple-juice numbers labelled "wine": **the original error wearing a correction**, which is D8 pointed at its own off-ramp.

**G1 — `IDENTITY_CONFIDENCE_MIN = 0.75`**, top candidate only, no margin rule. `p` absent on a present list counts as below. **Absent `alts` is not below-threshold** — the model did not answer the question, and an empty off-ramp is worse than none.

**H1 — recorded, not consumed.** `ai_alts` in offered order with each `p`, plus `identity_pick`. D57's correction-loop shape one field along. Confirming a lone answer records `asis`; confirming one of three records `confirm` at rank 0 — collapsing them would over-report agreement.

**I1 — a lookup, not a matcher.** A candidate matching a preset name case-insensitively resolves through the existing rail and comes back with real macros. No scoring, no ranking, no evaluation set.

### A conflict between two ruled items, named rather than resolved quietly

`R30-degrade` was pre-registered as *"a reply with no `alts` produces today's draft **exactly**"*. That cannot hold beside the headline rule: a single-item reply gets an identity-shaped question whether or not a list came with it.

**Resolved from the log, not referred up.** G1's stated reason — *"an empty off-ramp is worse than none"* — is about not showing an empty **list**, and *"resolve, rail visible"* is about **resolution state**. Neither is about question shape, which the headline rule governs unconditionally. So a no-`alts` reply resolves, shows no candidate buttons, and is still asked about. The gate keeps its purpose — **paste-path parity: same items, same `per100`, same propagation** — and its wording was re-pointed rather than quietly reinterpreted. **The wording was mine, not the ruling's**, which is why this is recorded rather than merely done.

### The defect pass, and two gates that were not evidence

**Twelve planted, and two did not fail.**

**`R30-order` passed against a planted alphabetical sort** — because the fixture was `Alpha / Bravo / Charlie`, already in alphabetical order. The assertion was right and the data made it unfalsifiable. The names now disagree with alphabetical, reverse and by-length ordering, so only the model's own order satisfies it. **D60 Clause 4's fifth instance.**

**`R30-record` detected its defect by throwing.** With `ai_alts` dropped from the allowlist, `recItem.ai_alts.length` raised a TypeError and took the synchronous suite down — so the failure arrived as `HARNESS: uncaught exception` rather than as the named case. The harness behaved correctly and the suite went red, but **a gate that can only report through the crash handler is not reporting**: the run says "something broke", not "this property is violated", and every case after it silently did not run. Guarded so it fails as itself. That is a **new shape** for the D56/D60 family — not an assertion that could not fail, but one that could not fail *by name*. **It is now D60 Clause 5**, and `R30-order` joined the Clause 4 register as its fifth instance.

The other ten behaved: resolving below the floor fails `R30-below-none`; rendering `p` fails `R30-no-numbers`; never opening the identity question fails `R30-identity-first`; an alt pick keeping the top-1 macros fails `R30-alt`; keeping the rejected name fails `R30-none-of-these`; suppressing `altsMismatch` fails `R30-top1`; re-deriving `single` from live items fails `R30-frozen`; removing the preset lookup fails `R30-preset`; stripping the lead block's off-ramp fails `R30-plate-unchanged`; and treating absent `alts` as unsure fails `R30-degrade`.

### Re-pinned, deliberately, in the same commit

**Count delta: 1579 → 1637** (+58). **Twenty-eight existing assertions moved with the schema and the template version** — each a case that deliberately pinned "my slice bumped nothing", now naming v8 and R30. Two fixtures moved with them (the forward-version blob and R23's guard case), and `R6-save`'s additive-field list went from five to seven, its claim unchanged: the photo path writes an ordinary item plus declared extras, never a different kind of record.

### Not built, and deliberately

The third depth of the off-ramp — search over a corpus — stays deferred (I1). Naming an unidentified item later is not built either: `photoPickNone` records the model's guesses as provenance and leaves the food called *"Unidentified item"*, because a name the user explicitly rejected must not be what the log calls it. **The matcher and its evaluation set are what D62 named as next, and nothing is upstream of them now.**

## D69 — The plate is a fact, the consumption is an event (R33, 2026-09-11)

`APP_VERSION → 0.29.0`; **schema v8 → v9**; new top-level store `plates`. All nine forks ruled as recommended, Fork D taking the stated alternative.

**Motivation, twice in real use:** a sushi bowl eaten half at one sitting and half later; and a takeout tray the model estimated at ~450 g, corrected to ~790 g for the **plate**, with no way to say roughly half of it was eaten. The app asked what was on the plate and then went quiet, so a takeout container saved as if the container had been eaten — an overstatement, or else a fabricated number for what was actually consumed.

### Fork A — safety by construction, not by enumeration

A plate could have been a flagged row in `day.items`. It is a separate store because **twelve analysis and display consumers read `day.items`** — `dayTotals`, `averageOver`, `macroCoverage`, `microRollup`, `macroSeries`, `fastEvents`, `renderDay`, `renderHistory`, `timelineForDay`, `isEmptyDay`, `isFirstRun`, the days-logged rollup — and under a flag every one needs a guard it could be missing.

**R31 is the evidence that enumerating them is unreliable:** its ruling named four surfaces and the build found two more, one of which produced a *wrong* answer rather than a short one. And the signs are not symmetric — **an absent macro that leaks reads as 0 and understates; a plate row that leaks reads as a whole takeout tray and overstates.**

`fastEvents` decides it alone: a plate confirmed at 19:00 and eaten at 20:00 and 23:00 would break the fast at the moment the food was **served**. R31 had just widened that selector to include unresolved items. In a store of its own the question cannot arise, which the defect pass then demonstrated in an unexpected way (below).

### Fork B — the finding that made the slice additive

**A consumption event is already exactly what an item IS.** Every field it needs, a saved item has. So an event is an ordinary item carrying `plateId`, `plateIdx` and the statement that produced it — and `dayTotals`, `averageOver`, `macroCoverage`, `microRollup`, `macroSeries`, `fastEvents`, `renderHistory`, the undo grammar and R23's editor all keep working untouched.

### What the pre-registration got wrong, and it is worth stating plainly

The survey concluded the slice was **additive**. It is additive for the twelve *consumers* — and it was not additive at all for four slices' worth of **correction-loop provenance**, which had to move.

`ai_grams` beside `grams` means **estimated beside accepted** (D57). On a consumption event `grams` is what was **eaten**, so an event carrying `ai_grams: 450` and `grams: 395` — half of a plate corrected to 790 g — would tell a calibration analysis the model **over-estimated by 12%**, when the user had in fact corrected it **up by 75%**. Carrying the fields on both the plate and the event would not have fixed that; it would have produced the wrong answer N times per plate instead of once.

**So the correction loop and the identity calibration moved to the plate**, where the identification and the portion correction actually happened (generalised as **D70**: provenance belongs where the estimate was made): `ai_grams`, `ai_identity`, `ai_alts`, `identity_pick`, `pinned`, `added`. The event carries what it ate. **Nine assertions across R6, R21, R23, R25, R30 and R61 were re-addressed**, each with its claim intact and each saying so in its own text. R30's calibration record moved one day after shipping, for the reason that the address was wrong rather than the ruling.

`photoReopen` moved with them: reopening a photo meal now reopens its **plate**, because rebuilding a draft from the day's items would reconstruct a half-eaten plate as a plate half its real size, and every later correction would compound from the wrong base. Pre-v9 meals have no plate and fall back to the old reconstruction — not a fix for them, and exactly as good as the app was before.

### Fork C — the common case does not pay

The draft's primary action is **"Ate all of it"**: one tap, writing the plate *and* a single 100 % consumption event. **The button changed its words, not its price.** "Ate some of it" is the secondary control, and the anticipation trigger opens the question for you.

A plate is created for **every** meal, including one eaten whole. One code path rather than two, and it is what makes *"actually, I had more later"* possible without re-photographing. The recall badge keys on **remainder**, so a finished plate never asks.

### Fork D — counts, taking the alternative

**The user declares countability at the plate step; no template change.** The ruling took the stated cost seriously: `AI_TEMPLATE_VERSION` went 3 → 4 one release ago, and a second bump in consecutive slices churns the one artefact the no-key path depends on — with D63 as the reminder of what happens when that path breaks. **The template field is the named follow-up.**

`count` is a **denominator**, not a second unit system: with it present, consumption may be stated as *"6 of 10"* and grams follow from the ratio. Counts contribute **no ratio** to the shared scale correction, as ruled — that mechanism is a geometry hypothesis over mass.

### Fork E — the trigger keys on a fact the user supplied

Not on a judgement about a photograph. **The user's own upward correction of the plate**: 450 g → 790 g is a 1.75× statement, in the app's own units, that this is bigger than one serving. No new field, language-independent, and it fires at the exact moment the misunderstanding happens. Absolute size is the floor for the case where the estimate was right first time; name keywords were rejected as brittle and a model's job rather than a regular expression's.

The ask is **non-blocking**: a section of the draft with every row preselected at "all", so the one-tap path survives the question being open.

### Fork I — the remainder is derived

Plate total minus the sum of its events, computed on every read and stored nowhere. Deleting an event returns the remainder for free; editing one re-derives it. **D62 Fork 3's question with the opposite answer**, and the reason is the distinction the slice is built on: a composite's composition is an **answer** that must hold still, while a remainder is **arithmetic over the user's own events** and must not.

### The defect pass, and three things it taught

**Thirteen planted in all — eleven, then two re-aimed. Three did not behave first time, and each failure was a different shape.**

**1. The write-site census fires before the gate.** The first version of *plate-written-into-day-items* planted the extra write in `photoSave` — and `check-writesites.sh` caught it, aborting the run before the data-layer harness started. The defect was detected loudly by the **outer** defence and never reached the gate it was meant to prove. Re-aimed through `consumeFromPlate`, which is already on the manifest. **Layered defences mean a planted defect can be stopped short of the gate under test**, and that reads identically to a gate that cannot fail.

**2. D60 Clause 5, one layer out — and the deeper lesson underneath it.** Two defects crashed the suite in an **earlier** block, so the named gate never executed. The crash was not in the gate; it was in a pre-existing case dereferencing `items[0]` on a day the defect had emptied. Five early dereferences are now guarded so a defect's real gate survives to name itself.

**But guarding was not the whole answer, and the rest of it generalises.** Both defects were *too broad*: "write no consumption event at all" and "push every plate row into the day" break the photo path wholesale, and **a defect that breaks everything is always caught by something.** What a gate must be shown to catch is a defect touching **only its property**. Re-aimed surgically — *"ate all of it" silently logs half*, and *the plate reaches `dayTotals` and nothing else* — both fail their own gate by name, immediately.

**The rule worth carrying:** when a planted defect fails a dozen unrelated cases, that is not proof the gate works; it is a sign the defect is too blunt to prove anything about the gate. A sharp defect and a named failure are the same requirement seen from two ends.

**3. A property true by construction has no mutation.** *fast-detector-sees-the-plate* passed with the defect in, because no mutation of `fastEvents` can make a plate break a fast — a plate is not an item. That is Fork A's whole point, and it is **D60 Clause 2**: the property is unfalsifiable *by that mutation*, and the honest response is to pair it with the defect that **can** break it — `plate-written-into-day-items` — rather than invent one that does not reach it. The defect was dropped rather than recorded as a caveat, per Clause 4's positive pattern.

**Also worth noting: the census caught `photoSave` LEAVING the manifest.** It no longer writes items at all — it confirms a plate and delegates. A census that had merely gained a name would have said less than one that also lost the one it replaced.

### The CDP gate caught two things the data layer could not

**D51's footer now holds three outcome actions, not two.** `capture-outcome-gate.ps1` pins `nActions -eq 2`, and it failed at all three widths. This is a **deliberate change to D51**, not a regression: "Ate all of it" and "Ate some of it" are both outcome *commitments*, which is exactly what that footer was ruled to hold — neither is a draft edit that wandered in. The gate is re-pointed to three, and its claim is unchanged and now asserted over all of them: in view, at or above the 44 px touch floor, footer fixed while the body scrolls, at 360 px, 390 px and 1200 px.

**And it caught the common case paying for the rare one.** The first implementation put a *"pieces (optional)"* input on **every draft row** — a control that does nothing for most foods, because most foods are not countable — and a two-item draft began scrolling on a 360 px phone. The count is now declared **inside the consumption question**, the only place it changes anything. Fork D is unaffected: the count is still a plate fact the user declares.

**The frequency rule was ruled at the GESTURE level and broke at the CONTROL level.** Fork C asked whether confirming a plate and stating consumption cost two ceremonies, and that was built correctly — one tap, one button, renamed rather than added to. Then the same rule was violated one layer down, by a control rather than a step, and nothing in the gesture-level reasoning had any purchase on it.

**Only a pixel gate saw it.** The data layer was at 1679/1679 throughout, and rightly: no assertion is false because a draft is taller. The failure existed only as geometry, at one width, in a measurement nobody would think to write as a claim about counts.

Worth carrying: **a frequency ruling binds at every level it can be violated at, and the levels below the gesture are not reachable by argument.** A control added *while we are here* costs the common case as much as a ceremony does and is harder to notice, because it never reads as a step.

### Re-pinned, deliberately, in the same commit

**Count delta: 1637 → 1679** (+42). **Twenty-seven version assertions** moved v8 → v9; **nine** were re-addressed from the item to the plate; **five** early dereferences guarded; and the D29 write-site manifest gained `consumeFromPlate` and lost `photoSave`.

**Defect pass: thirteen planted, ten in the final set, all ten failing their own gate by name.**

### Not built, and named

**Manual entry and the scan path have the identical problem** — a typed 790 g container, a scanned 500 g tub — and are Fork H's recorded escalation. **The template's `count`/`unit` field is Fork D's named follow-up.** Neither is smuggled in here.

## D70 — Provenance belongs where the estimate was made (2026-09-11)

Governance only. No code, no schema change, no `APP_VERSION` bump.

**The rule.** A provenance field records a claim made at a particular moment. Store it with that moment, not with whatever record uses the number later.

**What goes wrong, concretely.** `ai_grams` beside `grams` means *estimated* beside *accepted*. R33 made `grams` mean *eaten*. An event carrying `ai_grams: 450` and `grams: 395` then reads as *the model over-estimated by 12%*, when the truth is *the user corrected it upward by 75%* — the opposite sign, from two fields that are each individually correct. Carrying the pair in both places is worse rather than safer: the inversion then happens once per consumption event instead of once per plate.

**What moved and what did not.** To the plate: `ai_grams`, `ai_identity`, `ai_alts`, `identity_pick`, `pinned`, `added`. Staying on the event: `confidence` and `source`, which describe *that record's* own reliability and origin.

**The part to remember.** When a slice splits one object into two, **every assertion touching the original is suspect even if it still passes** — passing may only mean the two halves have not diverged in that case. Nine assertions across six slices were asserting the right claim at the wrong address and stayed green until R33 separated the plate from the event. A fully-eaten plate would have kept `grams == plate grams` and hidden the error entirely.

## D71 — How these entries are written (2026-09-11)

Ruled after D70 came back unreadable.

**Lead with the plain statement, then the rule someone can act on.** An entry has to be usable by a reader who is not holding the rest of the corpus.

**Taxonomy goes last, or not at all.** Placing a finding against its siblings — *"this is Clause 5's shape, not Clause 4's"* — is legible only to someone who already knows both. It reads as precision and carries nothing.

**Cross-references are pointers, not arguments.** Name the entry; do not re-derive it.

**The test:** would this sentence tell a reader what to DO if they had never read another entry? If not, cut it, or move it to the end.
