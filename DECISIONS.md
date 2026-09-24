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

**Macros** (kcal, P, F, C, fiber, soluble): every complete day has them (0 for a fasting day), so the mean is Σ(day totals) / **M** over the M complete days in the window — full coverage. — **AMENDED TWICE: by R31/D67** (a day holding an item with no composition is excluded, and the macro mean gets a denominator of its own) **and by D90** (a complete day with NO ITEMS has no macro data either, and the parenthesis above — *“0 for a fasting day”* — is **withdrawn**: measured against a real log, every such day sat inside a fast window the user had themselves resolved as *ate, didn’t log*). The rule that survives is the one this entry already states for micros: **a day without the data is excluded, never counted as 0.** The supplement, when enabled, is a *persisted* item and is therefore already in the totals; no render-time addition (the predecessor's understatement bug stays dead).

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

**Closed by D78 §4 (2026-09-17): no interactions, ever.** The paragraph above stays as the record of what was left open on 2026-07-18.

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

**FORGOTTEN-OFF is the honesty core.** An open segment past **`SLEEP_OPEN_MAX_MIN` (11 h, surfaced)** becomes a **pending candidate** — *"sleep ended when?"* — resolved by the user with an end time, or discarded. **Never auto-closed, never auto-trusted.** — **AMENDED BY [[D113]] for sleep alone:** past **24 h**, and only where the sleeper's own history supplies a typical wake time, the segment closes at that time and is **marked inferred**. The 11-hour question is unchanged; what changed is that silence now has an end. *Never auto-**trusted** still holds — that is what the mark is for.* Three-state grammar per D22, and while pending it **counts in nothing** (gated: `sleep_hours` sees zero points).

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

**Amended by D77 §4 (2026-09-17):** bound (c) now reads *"only the photo the user chose for this capture, and the template for its kind"*, so a medication label can be sent. Every other clause stands.

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

### Amendment — the Clause 4 register reaches six, and it is a class (2026-09-17)

| # | slice | assertion | why the fixture could not exhibit the failure |
|---|---|---|---|
| 6 | H4 (D82) | "None of these" keeps no name | the case used a reply whose candidate list contradicted its own name, and for that reply the name is **already** withheld. A defect that kept the name could not change the outcome. The case now uses a confident reply, where the name is filled in first, and the fixture asserts that before the pick |

**Instance 6 was found by reading the fixture before the defect pass ran.** It is the first instance caught that way; the earlier five were caught by a green run against a planted defect.

The same reading added a restore step to H4-absent. That test never crossed the restore boundary, where `normalizePrinted` runs. It is recorded here, next to the register rather than in it: the assertion was missing a code path, not measuring the wrong state.

**This is a recurring class, not a run of incidents.** There have been six instances in five slices over eleven days: R25 (twice), R26, R31, R30 and H4. Expect one in any slice that has a defect pass. For each planted defect, work out which starting state lets that defect change the outcome. Do this before the run, because that is when fixing the fixture costs least.

> **SEVENTH INSTANCE (2026-09-20, H7/D95): ten evenly spaced days, where the mean and the median are both 550.** The *“typical is the mean”* plant changed nothing and Fork B1's ruling went untested. It is registered here as the seventh, and it also generalises past this fixture — see [[D96]]: **a ruling that picks one statistic, one ordering or one policy over another needs a fixture where the alternatives DIFFER.** That question is asked from the ruling's side and can be answered before anything is run, which is where the register above says the cost is lowest.

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

**Amended by D76 (2026-09-17):** the corpus turned out to be upstream of the matcher, and the evaluation set is parked until the corpus exists. The paragraphs above stay as the record of what was believed on 2026-09-08.

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

## D72 — What the export cannot measure (2026-09-14)

Governance only. No code, no schema change, no `APP_VERSION` bump. Ruled when the first real export arrived, before anything was computed from it.

**The rule: a field records what the user DID, which is not the same as what it appears to measure. Before computing a statistic over the log, ask what had to happen for the row to exist.**

Three limits, ruled. The evaluation set is built from the scanned rows only, and the others are refused rather than caveated.

### 1. `ai_grams` / `grams` cannot measure the model's portion bias

The pair looks like a correction loop and is one — but only over a **selected** subset. The user corrected an estimate **only when an actual weight was available**, and plausibly corrected it *because* the estimate looked wrong. Selection is correlated with the error being measured, so any ratio computed across the log measures **the user's correcting behaviour**, not the model's accuracy.

Identical pairs (155/155, 70/70) are the sharper trap. They are not agreement. They mean the estimate was accepted, which could mean it was right **or** that there was no way to check. **Neither is evidence**, and they cannot be separated after the fact.

This does not retire the field. D57 stores it so the loop can be measured *when the two cases become distinguishable* — which needs the app to record that a weight was consulted, not just that a number was accepted. Until then the ratio is not a metric.

### 2. `fastLog` cannot measure fasting

Days are not reliably closed and fasts are not reliably resolved, so gaps are **logging artifacts**. The 1,132-hour entry is the plain case: it is the interval between two log events, not a fast. Any streak, mean or longest-fast figure over this export describes **logging habits**.

### 3. The eval set's own limit, which follows from the same reasoning

Only the **scanned** rows carry external truth: a barcode determines the product independently of the app, the model and the user. That is what makes them usable and everything else not.

**But the barcoded rows are also selected, and selected against the matcher's actual job.** A barcode means the app already resolved the food without a matcher. The cases the matcher exists for — *lotus leaf sticky rice*, *siu mai*, *bean curd skin rolls* — are precisely the ones with no barcode and therefore no external truth in this export.

**So the set can measure whether a matcher returns a composition consistent with a known product. It cannot measure the thing the matcher is for.** Stated here rather than discovered when the first accuracy number looks good.

### What the first export already demonstrates

Recorded because it is the first real-world evidence for three slices, and because a log that only records failures is not a record.

**R30's off-ramp worked on the case that motivated it.** The 2026-09-12 plate is wine-as-apple-juice caught in the act: the model answered `apple juice` at **p = 0.42**, below the 0.75 floor, so nothing was filled in; the user picked **rank 1** (`white wine`); and because a candidate is a name and not a nutrition profile, the item landed **unresolved with no macros** rather than logging apple-juice numbers under "wine". Every clause of Fork E1 doing its job on real data.

**R33 is in use.** Three plates, two partial consumptions — a third of a 205 g tofu plate on 09-13 — and the remainder derived rather than stored.

**D70's move is confirmed against real data.** All five plate items carry `ai_alts` and `identity_pick`; no consumption event does. The provenance sits where the identification happened.

### What the set is, as built

**7 rows** with barcode, query string and per-100 g composition truth; **1 name-only** row (barcode and product name from the price log, no logged portion, so no composition). One product was scanned twice, at 100 g and at 40 g, and both derivations give the same profile — the only internal check available, and it passes.

**And a labelling worklist: 26 distinct queries, none labelled.** Five are marked `human_judged` — the plates where a candidate was actually chosen between. **That is a seed, not a set.** The worklist separates the 21 strings the model proposed from the 5 names the user accepted, because the accepted ones are worth labelling first. (The split exists because an R33 consumption event carries no `ai_identity`: D70 moved it to the plate.)

**The directional rule is enforced structurally, not remembered.** `eval/score.py` prints no figure without its denominator, and below 30 rows every figure is prefixed `DIRECTIONAL`. A percentage over seven rows reads exactly like a percentage over seven hundred once it has been copied into a sentence, so the label travels with the number.

`eval/build.py` regenerates it from an export and is committable. `eval/set.json` is the user's eating history in another shape and is not.

## D73 — A document that states a rule its enforcer does not implement (2026-09-14)

Governance only. No code, no schema change, no `APP_VERSION` bump.

**What happened.** `eval/README.md` stated that `tolabel.json` was not committable. `.gitignore` covered `set.json` and not `tolabel.json`. The file — real dish names and dates — was committed to a public repo. Caught before the push, so amending removed it; had it been pushed it would have been permanent.

**The rule: when a document states a rule that something else enforces, verify it against the enforcer, in the same change.** One `git check-ignore` would have caught this. Prose asserting a guarantee is not the guarantee.

**Why it is worth an entry.** This is D3's shape — *never assert safety we don't have* — in documentation rather than in code. D3 ruled that a confirm dialog must not claim a backup exists when the write failed. A README claiming a file is protected when the ignore rule omits it is the same failure with a different surface, and it is the first instance of that shape here.

**And the narrower lesson: I ignored the instance, not the category.** The first fix covered `set.json` alone. `.gitignore` now covers the export, both generated data files, a labels file that does not exist yet, and any predictions file — because the next data artefact will be created by a future session that has not read this entry.

## D74 — Two limits on the evaluation set (2026-09-14)

Governance only. Ruled before labelling starts, because both would otherwise be discovered by their consequences.

**`undecidable` is a finished label, not a skipped row.** If no corpus row is correct for a query, that is a **finding about the corpus** and as complete an answer as naming a row. The tooling counts *labelled*, *undecidable* and *not yet looked at* as three states, with the first two both resolved — **a workflow that reports "no row fits" as unfinished work applies pressure to invent an answer**, and an invented row is noise in the truth column, which is worse than a smaller set.

**One labeller, who is also the user the matcher serves.** The set is labelled by the app's author, whose meals it contains and whose matcher it will score. **It measures agreement with one person's judgement, not correctness.** Nothing fixes that, and it is not a reason to stop — a matcher that agrees with its only user is doing most of its job. But no figure from this set may be called accuracy without the qualification, and a disagreement between matcher and label is not automatically the matcher being wrong.

## D75 — A check nothing runs is not a gate; the count says what it counts (2026-09-17)

Tests and docs only. No shell change, no `APP_VERSION` bump.

**What happened.** `tests/run-all-gates.sh` is the full-suite runner, and it never executed `check-precache.sh` or `check-guidance.sh`, even though GATES.md counted both as gates. A green `SUITE: PASS (9 of 9 …)` therefore said nothing about either. Reproduced: the old runner passes with a phantom path in `PRECACHE`, and with prop advice planted in the README. Both checks passed when run by hand, so nothing shipped wrong. The gap was in what a green run meant.

**The rule: every `tests/check-*.sh` must be wired, meaning the runner executes it, or the harness calls it and the runner can see that call. An unwired check fails the suite by name.** A new check joins a list in the same commit that adds it, as a new CDP gate joins the census.

**What changed.**

- The runner executes `check-precache.sh` and `check-guidance.sh` and judges them by the same rules as every other gate. Both now print a `GATE: PASS` / `GATE: FAIL` line, so there is no special case.
- The runner holds two lists. `STATIC_CHECKS` holds the checks it runs itself. `IN_HARNESS` holds `check-sw-hash`, `check-version`, `check-writesites` and `check-zxing`, which `run-data-layer.sh` runs as preconditions. The suite fails on any `check-*.sh` that is on neither list, and on any `IN_HARNESS` check the harness no longer calls outside a comment. The second failure matters because a precondition whose call has been removed has nothing left to fail on, so the harness still passes.

**How the count is arrived at.** The suite's number is **the number of verdict lines the runner prints**:

> 1 data-layer harness + the checks in `STATIC_CHECKS` + every `*-gate.ps1` (pinned by the census)

Today that is 1 + 2 + 8 = **11**. The four `IN_HARNESS` checks count as part of the harness's verdict, not a second time. Every run prints the sum on a `counted:` line, and the suite fails if the passes do not add up to it. **Quote the number together with that line.** A bare count cannot be told apart from one that lost a gate.

**Why the method has to be written down.** GATES.md has recorded eleven, thirteen, fourteen, fifteen and sixteen gates green, and then nine. The hand-collected counts listed the static checks one by one. The runner's nine listed none of them and never ran two of them. None of those numbers said what it counted, so a smaller number could not be told apart from a lost gate. The counts recorded before this entry stand as written. Comparing across this change needs the method above.

**Limit.** The call-site check matches text. An `IN_HARNESS` call on a line that never executes, such as inside a disabled branch, would still count as a call. The check does catch deletion and commenting-out, which is how a call normally disappears.

This is D56's failure shape, a check that silently stops checking, now found in the runner's own call list.

Evidence: GATES.md, "D75".

## D76 — The evaluation set is parked (2026-09-17)

Governance only. No code, no schema change, no `APP_VERSION` bump.

**Status: PARKED, not outstanding. Nobody is waiting on labels.** The scaffold stays: `eval/build.py`, `eval/score.py` and `eval/README.md`. The local `set.json` and `tolabel.json` stay as they are. Nothing is deleted.

**Why.**

1. **The set was sequenced against a matcher that is not coming soon.** It exists to score the matcher. The matcher needs the micros corpus (D59), because that is what it searches, and the corpus is unbuilt and not next. A set labelled now would sit for months, and by then it would be re-derived from a fuller log anyway.
2. **Labelling now would be circular.** With no corpus to search, a label would be chosen from a pick-list shortlist, and the shortlist would be produced by the same reasoning the matcher uses. A label picked from it measures agreement with that reasoning, not correctness. This tightens D74's limit: the set already measured agreement with one person, and a shortlist would make that person's choices depend on the matcher's own reasoning. The original design did not have that circularity.

**Reactivation: when the corpus exists.** At that point:

- regenerate the set from the export of that time (`python eval/build.py export.json eval/`) rather than labelling the September worklist;
- before any labelling, rule how a label is chosen without a candidate list that shares the matcher's reasoning. **That question is open and is not answered here.**

**This amends D62's sequencing.** D62 said the matcher had *"no remaining upstream blocker"*, and that the evaluation set *"needs no persistence, no corpus substrate and no further rulings"*. The first claim no longer holds, because the corpus is upstream of the matcher. The second holds for storage but not for labels: a label is a corpus row, so labelling needs corpus content to label against. D62's forks are unaffected. GATES.md's notes calling the matcher and its set *"stated next, still unblocked"* (under R30, R32 and R33) are superseded by this entry.

## D77 — Medication capture, ruled before build: a scan list answers "whose", and each refusal says why (H4, 2026-09-17)

Governance only; H4 is not built. No code yet, and no `APP_VERSION` bump. The forks and gates are in GATES.md under H4; this entry records the rulings that bind beyond that slice.

### 1. Whose medication: asked once, at capture, and answered by where the record goes

**The problem is a category, not an exposure.** The app has one profile and no concept of whose. A label scanned for someone else would land in the user's medication list, and anything computed across that list would silently mix two people.

**Ruled: a scan list.**
- **It is local and separate from the medication record.** Every scan is logged there with drug, strength, Rx number, date and whose.
  **Amended by D79:** entries also hold directions and prescriber, as printed.
- **Whose is asked at capture, with one tap: "yours or someone else's?"** Capture is the only moment the app can know; working it out later would be guessing.
- **"Mine"**: the reading is offered for saving into the medication record, as H4 describes.
- **"Someone else's"**: the reading is shown and the scan is logged, and nothing enters the medication record. Reading a label is a lookup and saving it is a record; they are different acts.
- **So the medication record is single-person by construction.** It has no whose field, and none of its consumers need one.
- **The scan list stays local and is not exported.** The copy button covers anything that needs moving.
- **The Rx number is kept.** Anyone holding the prescription already has a photo of it on the device, so the app holding the drug name and Rx number is strictly less than what is already there.

**Superseded within the same ruling:** a `for` field on the medication record, which was first named as the fix. The scan list removes the problem instead of modelling it.

**Record this as a scan list, not a privacy control.** The user framed this as privacy twice, once for the patient name on the label and once for the Rx number, and neither framing held up. A future session must not read how either field is handled as a privacy rule.

### 2. Every refusal entry carries its reason, because the reasons differ

One list that encodes two policies is how a future session adds or removes the wrong entry. So each entry states which policy it follows:

| entries | handling | reason |
|---|---|---|
| drug class, indication, mechanism, interactions, dose advice, appropriateness | refused: stripped, counted and named on the draft | **claim**: the model would be asserting this, not reading it |
| patient name, patient address, pharmacy phone | refused: stripped and counted | **tidiness**: nothing uses these. This is not a safety rule |
| directions, and every other contract field | kept verbatim | **transcription is not assertion** |

The reason is stored as data in the code, not only written here, and a gate asserts that every entry has one.

**The consequence, stated plainly.** If a label prints *"TAKE 1 TABLET DAILY FOR BLOOD PRESSURE"*, the record **contains** an indication, even though the app never states one. "The app makes no claims about indications" is true of the app's claims and false of its contents. Nothing that reads medication records may treat "the app stated no indication" as "there is no indication".

### 3. The honest limit of any refusal

The model sees the whole label, whatever it returns. Refusing a field keeps it out of the **record**, not out of the **request**. The capture surface says so before the first send.

### 4. D45's bound is amended

*"Only the meal photo and the perception template"* becomes *"only the photo the user chose for this capture, and the template for its kind"*. Every other clause of D45 stands: the key, the photo hygiene, the service-worker bypass, and the fallback to paste.

### 5. Schema v9 → v10 for the medication store

**This bump is required, not optional.** The existing medication record turns "50 mg" into a number and a unit, which is exactly what H4 forbids. So the as-printed reading needs a record that never passes through that normaliser. The scan list lives outside `APP_STATE` (§1 keeps it out of export), so it needs no schema change.

### 6. References corrected

- **The brief's "D4 two-objects rule", "R1.1" and "asking-price refusal" belong to another project's log.**
- **The rule the brief meant is D55/D69/D70:** a derived value is kept beside the observation, never in place of it. **The refusal machinery it meant is D45 Fork H.**
- **"Middle row" means one reply, two assertions:** the refused field is stripped, **and** the legitimate field survives. Both are asserted against the same response, so a refusal that removes too much fails the gate.

## D78 — Drug information comes from openFDA, by measurement; interactions are closed (H5, 2026-09-17)

Governance only; H5 is not built. The forks and gates are in GATES.md under H5.

### 1. The source, decided by measurement

**DailyMed cannot be the transport.** Checked on 2026-09-17 with the app's origin: DailyMed's API sends no `Access-Control-Allow-Origin` header, on either the GET or the preflight. A page on github.io therefore cannot read its responses, and the app has no server to read them for it.

**openFDA serves the same FDA label documents**, with `Access-Control-Allow-Origin: *`.

**Ruled:**
- openFDA is the transport.
- The label document is the citation.
- The DailyMed page for the label's set ID is linked. A link is navigation, not a fetch, so CORS does not block it.
- openFDA's two statements travel with every stored section:
  - *"Do not rely on openFDA to make decisions regarding medical care."*
  - *"The drug labeling provided in this API may not be the labeling on currently distributed products."*

### 2. The query contract, pre-registered (verified 2026-09-17)

Base URL: `https://api.fda.gov/drug/label.json`. No API key.

| step | request | measured |
|---|---|---|
| list the manufacturers | `search=openfda.generic_name.exact:"<NAME>"&count=openfda.manufacturer_name.exact&limit=100` | 3.9 KB; 48 manufacturers for METOPROLOL TARTRATE |
| fetch the chosen label | `search=openfda.generic_name.exact:"<NAME>"+AND+openfda.manufacturer_name.exact:"<MFR>"&sort=effective_time:desc&limit=1` | about 47 KB |
| fetch the exact product, when the label printed an NDC | `search=openfda.product_ndc.exact:"<NDC>"&limit=1` | about 64 KB, 1 result |

- **`.exact` is case-sensitive.** `"metoprolol tartrate"` matches nothing, while `"METOPROLOL TARTRATE"` matches 158 labels. So the query string is a **derived value**: the confirmed printed name, upper-cased, stored beside the printed name and never in place of it (D55/D70).
- **No match comes back as HTTP 404** with `"No matches found!"`. The app treats that as a no-match, not an error.
- **Never request a list of full labels.** One full label is about 50–65 KB, and five are 256 KB. The manufacturer list comes from `count`, and only the label the user picks is fetched. From that label, only `description`, `indications_and_usage`, `mechanism_of_action` and the citation fields are kept.
- **Rate limits without a key:** 240 requests per minute and 1,000 per day, per IP address.
- **Open for the build:** whether a printed **brand** name is also searched exactly, via `openfda.brand_name.exact`. "LOPRESSOR" matches, but the Canadian "TEVA-METOPROLOL" does not.
  **Ruled in D80:** yes, with exact matching after case-folding; the upper-casing above is replaced for both names.

### 3. Three findings, ruled as constraints

- **Exact matching only.** A phrase search for "metoprolol tartrate" also returns the tartrate/hydrochlorothiazide combination product, an injection and a misspelled entry. So there is no "contains" match, no dropping of the salt name, and no retry with a looser query.
- **A missing Mechanism of Action section renders as absent**, not as an error, and no other section fills its place.
- **The gap in Canadian coverage is named where it matters.** A drug with no US label, such as domperidone, gets a line naming Health Canada's Drug Product Database (DPD) as the Canadian source, which is not connected.

### 4. D20's deferred intent is closed: no interactions, ever

The D20 addendum left drug–drug and drug–supplement interaction checking open as a possible future capability. **That door is now closed.** No surface, prompt or export combines information about two medications. The app's honest position is that a pharmacist needs the consolidated medication list, and that a pharmacist's medication review (MedsCheck, in Ontario) is the service built to check interactions.

### 5. The boundary on indications

**The app never says what a drug is for this person.** A label's indications say what the product is approved for, not what it was prescribed for.

This rule governs what the **app** writes. A printed direction that names an indication is still kept verbatim, under D77 §2. So H5's vocabulary gate must skip fields that are verbatim label text, and must also assert that those fields are displayed as label text.

## D79 — The medication list is a copy action in H4, not a slice of its own (H6, 2026-09-17)

Governance only; nothing is built. All four H6 forks are ruled as recommended.

**The list is a copy action.** H4 builds the medication record, but had no way to copy it, which made the missing copy action a gap in H4 rather than a slice of its own. **H4 now includes:**
- **"Copy my medications"** on the medication record: one line per current medication, with name, strength, directions, prescriber and Rx number, all as printed.
- **Copy on the scan list**, filterable by whose and by date.

**Scan entries gain directions and prescriber, as printed.** Without them, the scan list holds only a drug name and a number, which is not what anyone reviewing medications needs. They are printed text, so they fall under "transcription is not assertion" (D77 §2). **This amends D77 §1's field list.**

**Scans for several other people: named, not built.** The fix would be a separate bucket for each person, which is the whose field arriving by another route. If it is ever needed, it gets its own deliberate ruling rather than creeping in.

**Every copied list starts with a header:** the date it was copied, and *"From HealthTracker, as printed on pharmacy labels. Not checked for interactions or completeness."* This makes D78 §4's closure visible at the moment the list leaves the app, which is exactly when someone might assume it was checked.

**A refill scanned twice appears twice, and stays that way.** De-duplicating the log would mean deciding that two scans are the same prescription, and that is a judgement. The duplicate is honest.

**What remains under the name H6** is only the case of scans for several other people.

## D80 — Brand names are searched too; nine of nine Canadian brands tested found nothing (H5, 2026-09-17)

Governance only; nothing is built. This rules D78 §2's open item.

**Ruled: a printed brand name is searched as well as the generic name, with exact matching only.**

### Exact, but not case-sensitive. Measured 2026-09-17

openFDA stores each brand name the way its labeler wrote it: "Lipitor", "Crestor", and both "LOPRESSOR" and "Lopressor". `.exact` is case-sensitive. So upper-casing the printed brand fails, even though it works for generic names: `"LIPITOR"` finds nothing, while `"Lipitor"` finds one label.

**The contract, for both brand and generic names:**
1. Run `search=openfda.<field>:"<NAME>"&count=openfda.<field>.exact&limit=100`. This cheap call lists the spellings openFDA has stored for the name.
2. Keep only the stored spellings that equal the printed name after case-folding. A longer stored name that merely contains the printed one is **not** a match. This is the same equivalence H4 Fork F uses for refills.
3. Look labels up with `openfda.<field>.exact:"<spelling>"`, combining every matching spelling with OR.

**This replaces D78 §2's upper-casing for generic names.** In the measurement, every stored generic name was upper-case, so upper-casing happened to work. The contract should not depend on how openFDA happens to case a field.

### The measured limit

Thirteen printed brand names were tested. DPD confirmed all but Lopressor as Canadian products.

| brands | kind | resolve in openFDA |
|---|---|---|
| TEVA-METOPROLOL, APO-METOPROLOL, PMS-METOPROLOL-L, SANDOZ METOPROLOL, APO-ATORVASTATIN, TEVA-ATORVASTATIN, APO-LEVOTHYROXINE | Canadian generic-company brands | **0 of 7** |
| MONOCOR, ELTROXIN | brands sold only in Canada | **0 of 2** |
| LIPITOR, CRESTOR, SYNTHROID | brands sold in both countries | 3 of 3 |
| LOPRESSOR | US brand | yes (two stored spellings, three labels) |

**Nine of nine Canadian brand names found nothing, and three of three brands sold in both countries resolved.** That split is structural, not patchy coverage: openFDA indexes US labelling, so a brand name used only in Canada has no US label to match. The claim is about the thirteen names tested and that mechanism; it is not a coverage estimate. So a label whose only printed name is a Canadian company brand (APO-, TEVA-, PMS-, SANDOZ) gives the lookup nothing that openFDA can find. This is the DPD gap (D78 §3) appearing a second time. The first time, it was a drug with no US label; here, it is a US label that the Canadian name cannot reach.

**When nothing matches, the app says so, and D78 §3's DPD line applies.** Searching the brand and the generic name is two exact lookups on two printed names. It is not a retry with a looser query.

### Why the case-sensitivity catch mattered

Upper-casing worked for generic names, and it would have returned nothing for every brand. **A lookup that finds nothing looks exactly like a drug with no label**, so the defect would have shipped as a stream of honest-looking "no US label found" answers. This is the presence-versus-value failure: the absence of a result was about to be read as a fact about the drug, when it was a fact about the query.

**The rule: when a lookup's empty result is shown to the user as an answer, the same test run must prove that the lookup finds a known-present item whose stored form differs from the query.** This is a planted control, the way `check-guidance.sh` proves its matcher can match. Without it, "not found" cannot be told apart from a broken query. The gate is the control on H5-no-match.

### Open, and it decides how often the lookup can work in Canada

H4's contract has a single `name` field. If a label prints both a brand and a generic name, the second has nowhere to go. That matters because when the brand is Canadian, the generic name is what resolves, and it may then never be captured. **Recommended:** add an optional `generic_name` field, transcribed as printed, beside `name`. **Ruled in D81: yes.**

## D81 — A label's two names are two fields (H4, 2026-09-17)

Governance only; nothing is built. This rules the open item in D80.

**Ruled: an optional `generic_name` field, transcribed as printed, alongside `name`.** A Canadian label can print both a company brand and the generic name, and in openFDA only the generic resolves (D80). With a single field, transcription would have to choose between the name that is prominent and the name that is useful. So there are two fields, both verbatim, and no judgement about which matters.

**What follows:**
- **Neither field is derived from the other.** A label that prints only one name has only that field, and the other stays absent (H4-absent). The app never fills `generic_name` from a lookup.
- **The template asks for both names as printed**, and says to leave out any name that is not printed. `LABEL_TEMPLATE_VERSION` stays at 1, because nothing is built yet.
- **H5 searches each printed name exactly** (D80's contract), and shows which name found each result.
- **Scan entries and copied lines carry both names when both are printed.** This is the same no-judgement rule; keeping only one name there would force the same choice again.
- **Fork F's refill match does not change.** It still keys on the printed `name` and strength, and on the Rx number. A generic name printed on one fill but not another must not break the match.

## D82 — H4 built: medication capture from a pharmacy label (2026-09-17)

`APP_VERSION → 0.30.0`; **schema v9 → v10**; a new top-level store, `meds`; and a local scan list (`healthtracker-scans`) kept outside `APP_STATE`. Built to D77, D79 and D81. The evidence is in GATES.md under H4.

### What was built

- **A capture kind, chosen before sending**: Meal / My label / Someone else's label, on the capture surface.
  - Choosing a label shows the honest limit above the buttons that send.
  - The meal request is byte-identical to 0.29.0, and a test asserts it.
- **A label template and its own parser** (`LABEL_TEMPLATE_VERSION = 1`). Printed values are kept verbatim; a value with no visible characters is absent.
- **One policy table** (`LABEL_REFUSED`, `LABEL_KEPT`). Every entry carries its reason: claim, tidiness, or transcription. The harness fails if an entry has no reason.
- **The label draft lives in the single outcome modal** (D51).
  - The draft asks for name and strength first, plus a generic name if one is printed separately.
  - Below the confidence floor, the name is left empty.
  - Nothing saves until the user confirms name and strength.
- **Mine**: "Save to my medications". A refill match (by Rx number, or by name and strength) is offered, never applied.
- **Someone else's**: "Done" or "Copy". The reading is logged to the scan list and never saved.
- **Settings › Medications** contains:
  - my medications, each with "Mark stopped" or "Resume", and "Copy my medications";
  - the scan list, with whose and date filters, a delete button per entry, and "Copy scan list";
  - the no-key paste path: the honest limit, the label prompt, and a whose choice with nothing preselected;
  - "Type a label by hand", which saves with source `manual`.
- **README**: a Medications feature bullet, and a privacy bullet about photos sent with the user's own key.

### Decisions made during the build, not separately ruled

1. **A scan whose name was never confirmed is logged as "Unreadable label"**, with no strength and no generic name. This is D68's "None of these" rule, applied as recommended for this open detail. Directions, prescriber and Rx number are kept as read.
2. **A scan is logged when the draft ends, however it ends**: saved, added as a fill, "Don't save" or "Done". A label typed by hand is not a scan.
3. **A different strength is never a refill, even under a matching Rx number.** The ruling puts the Rx number above a difference in *name*; it does not say the Rx number overrides strength. A strength change is the clinically meaningful case F1 exists to protect.
4. **Values keep their surrounding whitespace.** "60 " stays "60 ". The refill comparison trims and case-folds; storage does neither.
5. **A number returned for a text field keeps its digits, as a string.** Objects, arrays and empty strings are not readings; they are counted as not kept.
6. **Unknown keys are counted and named on the draft, not dropped silently** (D3). Their names are escaped.
7. **B1's `source: 'manual'` needed a way in.** "Type a label by hand" opens the same draft with no reading. It is small and falls within B1, but it was not ruled on its own.
8. **A medication is stopped, never deleted.** It can be marked stopped and resumed. A mistaken save can be undone immediately with the existing undo; one noticed later can only be marked stopped.

### D29 write-site census

- **Three new write sites.**
  - `createMedFromDraft` and `addMedFill` are stamped: every medication and every fill carries `tzo`.
  - `logScan` is exempt. The scan list is a date-only local log outside `APP_STATE`, and D77 ruled its fields.
- **The census pattern now also matches** `meds[id] =`, `.fills.push(` and `scans.push(`.
- **A gap found, not fixed.** The census comment listed "the five persisted record stores", and R33's `plates` store was never added. A plate write does not match the pattern, so a new plate write site would go unnoticed. It is named here rather than fixed inside this slice.

### Found while building

- **Two CSS tokens the shipped styles rely on do not exist.**
  - `.pmalt`, `.pmaltnone`, `.pmfrac`, `.pmcount` and `.plrow` use `var(--card)` and `var(--fg)`, and neither theme defines them.
  - So those controls fall back to a transparent background and inherited text colour. That renders acceptably, which is why nobody noticed.
  - H4's styles use the tokens that do exist. The existing ones are not fixed here.
- **Headless screenshots narrower than about 500 px are cropped, not narrow.** With a 390 px `--window-size`, Chrome still lays the page out at 504 px, so the first layout check showed an overflow that does not exist. Checked again inside a 390 px iframe: no horizontal overflow. The CDP gates avoid this by emulating the device; a one-off screenshot does not.
- **A literal closing script tag inside a harness string ends the harness.** The escape test's fixture key contained `</script>`, which closed the inline script. The whole suite then produced no results at all. The fixture now splits the tag.
- **Intermittent empty dumps.** Four defect runs, and one full-suite run earlier the same day, produced no SUMMARY line; every re-run completed. The runner reports this as a failure by name, which is correct. The likely cause is the headless dump under memory pressure, not the harness.

### Count and pins

- **Count delta: 1679 → 1802** (+123).
- **27 existing assertions moved from v9 to v10**, each claim unchanged (the same number R33 moved). That took 26 edits; one assertion followed its fixture, the forward-version blob, which moved to v11.

## D83 — The write-site census classifies every store (2026-09-17)

Tests and docs only. No shell change, no `APP_VERSION` bump.

**What was wrong.** The D29 census matched record writes with a single hand-written pattern, which covered only the stores someone had remembered to add. R33 added the `plates` store and nobody added it to the pattern. A new plate write site would therefore have gone in unstamped and still passed. It was not a defect when R33 shipped; it was a defect waiting for the next slice that writes plates.

**The rule: every top-level store must be classified, and the store list comes from the app, not from memory.**
- The census reads the store list from `emptyState()` in app.js.
- Each store must be one of two things: a record store, with the pattern (or patterns) that detect a record being created in it; or a named non-record store, with the reason it holds no records.
- A store the app gains fails the census until someone classifies it.
- A pattern for a store the app no longer has also fails.
- Stores that live outside `APP_STATE`, such as H4's scan list, are listed separately.

**The classification today.**
- **Record stores:** `days`, `priceLog`, `plates`, `meds`, `timeline`, `fastLog` and `regimens`, plus the scan list outside the state.
- **Not record stores:** `version` and `current`, which are scalars describing the blob; and `settings`, which holds configuration and templates.

**What the census now sees.** `photoSave` returns to the manifest, for the plate it creates. It is stamped: `plateFromDraft` sets `tzo`. R33's note that `photoSave` left the manifest still holds for items, because it writes none. The census now finds 19 write sites.

**Proven against the defect** (see GATES.md, D83).
- The pre-change census passes an unregistered plate write.
- The new census fails that same write by name.
- It also fails on a new unclassified store, a store removed from `emptyState()`, a dropped pattern, and a store list it cannot read.

**Limit.** Classification works at the level of top-level keys. A new *kind* of write into an existing record store, such as a new array inside `meds`, still needs its pattern added by hand. The census guarantees only that no store is invisible to it.

## D84 — The prompt card ignored the capture kind (H4.2, 2026-09-17)

`APP_VERSION → 0.30.1`; schema unchanged at v10. Reported from the device against 0.30.0: **Log → Log medication or supplement → Photo · AI paste showed the MEAL prompt.**

### What was actually wrong: four faults, one cause

The capture kind switched the template that was **sent**, and nothing else on the surface.

- The prompt card rendered `AI_PROMPT_TEMPLATE` unconditionally, so "My label" still showed the meal prompt.
- The version line read `template v4` for every kind.
- The pane's Read button was always the **meal** reader, so a label reply pasted there was refused with *"Expected {"meal":…, "items":[…]} from the photo template."* — the parse failure the report predicted.
- Found while fixing: the kind chooser rendered **only when a key was configured**, so the person who most needs the copy-prompt path — the one with no key — could not choose a label at all.

### Why every H4 gate passed

They assert the template constant, the policy table and the body of the call. All three were right. What shipped wrong was the **card on the page**, rendering the other constant.

This is D63's shape — *the template was correct and the box was empty while every assertion passed* — and it is the second time this same card has produced it.

**The rule: when one control changes what another surface means, gate the SURFACE, not only the value it is supposed to carry.** The constant the code sends and the constant the page shows are two facts. Only one of them was ever asserted.

### The fix

- One kind, one surface: the prompt text, the version line, the heading, the note and the Read button all follow `CAPTURE_KIND`, and `setCaptureKind` repaints them.
- A box opts in with `data-prompt-kind="capture"`. Settings' own meal prompt card does not follow the kind, because it is a meal card by name.
- The pane's Read button routes through `doCapturePaste`, which parses by kind and takes `whose` from it.
- The kind chooser and the honest limit render with or without a key.

### One thing deliberately simplified

The failed-capture fallback used to put a label reply in the Settings box, because that was where the label paste path lived. With the pane reading labels, that sent the user away from the box in front of them.

There is now **one paste box, on the surface the capture came from**. Two gates were re-pointed to say so, and their claim is unchanged: the reply the user paid for reaches a box they can act on.

### Gated where it broke

- **`H4.2-prompt`** drives the **shipped page** through its own `HT`, for all three kinds, and asserts the box contents, the version line and the button label. Its control shows what an unconditional renderer leaves in that box.
- **`H4.2-copy`**: Copy takes what the surface is showing.
- **`H4.2-nokey`**: the chooser exists with no key saved.
- **`H4.2-paste`**: the reader routes by kind, with a control that reproduces the reported failure — a label reply through the meal reader.

## D85 — The keyless floor is a floor, and it has now broken three times (H4.3, 2026-09-17)

Tests and docs only. No shell change, no `APP_VERSION` bump.

### The fault, at its weight

In v0.30.0 the capture-kind chooser rendered **only when an API key was saved**. The kind decides which prompt the page shows and how a pasted reply is parsed, so without a key there was no way to choose a label at all.

**The person that shut out is exactly the person the copy-prompt path exists for.** D45 ruled the key path an addition and the paste path the floor: *"BYOK is an addition, never a replacement, and every failure lands back on it."* For anyone without a key, medication capture did not degrade. It was absent.

It shipped because the person who tested it had a key.

### Three times now

| # | shipped | defect | dead for |
|---|---|---|---|
| 1 | v0.9.0 → v0.25.1 (D63) | two cards shared `id="promptTemplate"`, so Settings' prompt box was **empty on every build for weeks** | anyone copying the prompt from Settings |
| 2 | same slice (D63) | `copyPrompt` always reached for the first box, which is inside the hidden photo pane, so the copy silently failed and the stated recovery was impossible | anyone copying from Settings |
| 3 | v0.30.0 (D84) | the kind chooser rendered only with a key | **every** keyless user of medication capture |

Each was gated afterwards, one feature at a time. That is the pattern this entry is about: **the floor was being tested one plank at a time, by whoever last stepped on it.**

### What else is gated on the key: audited, 2026-09-17

There is no `visionReady()` in this repo; the gate is `byokConfigured()`, and it has four call sites.

| site | gates | verdict |
|---|---|---|
| `byokCapture` | making the provider call | **correct** — there is nothing to call without a key |
| `renderCaptureBtn` | Take photo / Choose photo, and the no-key note | **correct after D84** — the chooser and the honest limit moved out of this branch |
| `byokStatusLine` | the key's own status line | **correct** — it describes the key |
| `byokSave` | reporting whether a save configured the path | **correct** |

The daily cap (`byokCap`) and the status (`BYOK_STATE`) gate only sending and reporting. **So one branch was wrong, and D84 fixed it.** That is a reading of the code, which is what the previous two instances also passed.

### The rule: gate the floor as a floor

Reading call sites is how this was missed twice. **`H4.3-keyless` asserts the whole keyless route on the shipped page, with no key saved**, in one case: the kind question is askable; each of the three kinds shows its own prompt; copy fills the box; both readers turn a pasted reply into a draft; and the Settings label path is present with its whose question. Its control asserts the key-only controls are absent, so the case cannot pass by measuring a configured page.

**A feature that has a keyless route adds it to that case.** One more plank on a floor that is tested as a floor, rather than one more feature-shaped gate that will be complete until the next feature.

**Proven against the defect:** gating the prompt card, the reader, copy, or the Settings prompt on `byokConfigured()` each fails the floor case by name, as does the chooser gating that shipped.

## D86 — H5 built: drug information from openFDA, stored with its citation (2026-09-17)

`APP_VERSION → 0.31.0`; **schema v10 → v11**; a new top-level store, `labels`. Built to D78, D80 and D81. Evidence in GATES.md under H5.

### What was built

- **The lookup, on demand only.** From a saved medication: "Drug info" opens a panel; nothing reaches the network until the user taps.
- **The query contract of D78 §2 and D80**, verified live again at build time:
  - step one asks openFDA for the **stored spellings** of a printed name (a count);
  - only spellings equal to the printed name **after case-folding** are kept, and every one of them is queried;
  - step two lists **manufacturers** (a count);
  - step three fetches **one** label, newest first, for the manufacturer the user picks;
  - an NDC printed on the label skips straight to the exact product;
  - a 404 is a **no match**, which is an answer.
- **The generic name is searched first**, then the brand (D81): when the brand is Canadian, the generic is what resolves.
- **The document** keeps the three sections as fetched, with org, set id, version, effective date, retrieval date, the source's own disclaimer and the DailyMed link. A document missing any of that is refused at the store boundary.
- **Stored only on an explicit save**, in its own capped store (40 documents). At the cap the save asks, and the only thing it may drop is a document no medication points at.
- **A newer version is offered, never applied**: taking it keeps the old text beside the new one (D55).
- **No match** says so, names the Canadian gap (DPD), offers the copy-prompt path with a prompt that states it carries no label text, and links out to DailyMed.
- **Two copies:** the label text with its citation, and a prompt carrying that text, one question stem and fixed instructions. **Exactly one label per prompt** — that is how "no interactions, ever" holds on the copy path.
- **Standing context** on the surface (G1), never a verdict on one medication.
- **README**: a feature bullet and a privacy bullet — the confirmed name is sent to openFDA only when asked, and never in the background.

### Decisions made during the build

1. **`labels` is a top-level store, not a field on the medication.** Two medications can point at one document, and the store is capped as a whole. It bumps the schema because an older app would strip documents the user chose to keep.
2. **It is not a record store** for the D29 census (D83's classification): a label document records nothing the user did, and carries the source's dates and the retrieval date rather than a device offset.
3. **The panel lives inside the Medications card.** The capture outcome modal is for captures (D51); this is reference material attached to a record, and it belongs where the record is.
4. **Sections are `<details>`, open on demand.** The label text is long; the citation and the standing context must stay visible above it.

### What the defect pass found — five gates that could not fail

The pass is 81 plants. Five of them passed against their own gate, and each was a different hole:

| plant | why it passed | repair |
|---|---|---|
| the v9 → v10 migration step deleted | the v10 → v11 step that follows produces a compatible shape, so the **end state** could not show a missing step | **`H5-chain`**: the chain is asserted to call every migrator, one per schema version |
| a section truncated to 200 characters | the fixture's section was shorter than 200 characters (**Clause 4**, seventh instance) | the fixture section is now longer than any plausible truncation |
| the app adding *"This is what you take it for"* | the banned-phrase list did not cover that wording | the check is a set of patterns, and the control plants that exact sentence |
| a fetch on every render | it broke a scripted call-path case first, so the suite reported *"something threw"* rather than the property (**Clause 5**) | the on-demand claim is asserted in the synchronous block, where nothing can fail ahead of it |
| a 404 classified as an error | the flow reaches "no match" for several reasons, so the **end state** could not tell them apart | the classifier is asserted directly: 404 → no match, 500 → an error with its status |

Two of the five are the same shape as each other and as D83's census gap: **a gate that asserts the end state cannot see a missing step in the middle.**

### Found while building, and fixed here

**A control character has been in the shipped stylesheet since v0.20.1.** `.cited>summary::before` carried a raw `0x14` where the CSS escape for the circled i belongs, so every citation block in the app has rendered as a replacement glyph followed by "D8" — on the provenance surface D53 built, and on every lab and source block since. Repaired, and gated: **`SE-ctrl`** asserts the shipped shell contains no control characters and that the marker resolves to the character it was meant to be. Found by looking at a screenshot, which is the only way it could have been found.

### Runner notes, recorded because both cost real time

- **The defect runner has no lock.** Two diagnostic scripts ran while a pass was in flight; each snapshotted a tree with a plant in it and restored that snapshot afterwards, leaving a defect behind and producing failures that looked like the build's. **Never run anything that snapshots the tree while a pass is running**, and check the tree afterwards.
- **A planted defect must not block the browser.** The escape fixture used `onerror=alert(1)`; unescaped, the alert blocked headless Chrome, so the page never reported and the defect read as a hang rather than as a failed gate (**Clause 5** again). The payload now sets a flag, which the gate also asserts was never set.

## D87 — An end-state assertion cannot see a missing step in the middle (2026-09-17)

Governance only. No code, no schema change, no `APP_VERSION` bump.

**The rule: when a process has steps, assert the steps. An assertion about the end state cannot see a step that was deleted, because the step after it produces a compatible end state.**

Three instances, all found by defect passes inside a week:

| # | process | the end-state assertion | what it could not see |
|---|---|---|---|
| 1 | the migration chain | *"a v9 blob boots at the current schema, content intact"* | the v9 → v10 step **deleted**: the v10 → v11 step that follows produced the same shape, and every gate stayed green (D86) |
| 2 | the openFDA error route | *"a drug with no US label shows the no-match surface"* | a **404 classified as an error**: the flow reaches no-match for several reasons, so the surface could not tell them apart (D86) |
| 3 | the D29 write-site census | *"the set of write sites matches the manifest"* | a **store nobody added to the pattern**: `plates` was invisible to the census for two slices, and the totals agreed anyway (D83) |

**What it looks like from inside.** The gate names the right property, the planted defect is exactly the one it guards against, and the two never meet — because something downstream repairs the state before the assertion reads it. That is D60 Clause 4's shape one level along: Clause 4 is about the state a fixture *starts* in, and this is about everything between the defect and the assertion.

**How to apply.**

- **Name the steps.** A chain of migrators. A fetch → classify → parse → store path. An error route with more than one way in.
- **Assert each step where it happens.** `H5-chain` asserts the chain calls every migrator; `H5-404` asserts the classifier rather than where the flow lands; D83's census asserts that every store is classified rather than that the totals agree.
- **In the defect pass, plant a DELETION of each step.** If the suite stays green, the gate is an end-state gate and that step is unguarded. This is the cheapest detector there is, and it is how all three were found.

**Applied so far:** the migration chain, the openFDA classifier, the store census. **Not audited yet:** the capture path (downscale → call → parse → draft), restore (parse → normalize → save) and ingest (parse → coerce → merge). Recorded as the next places to plant a deleted step, rather than claimed as covered.

## D88 — No gate reads the page the way a person does (2026-09-17)

Governance only. No code, no schema change, no `APP_VERSION` bump.

**The instance.** `.cited>summary::before` carried a raw control character from v0.20.1 (2026-09-06) until v0.31.0 (2026-09-17). Every citation block in the app rendered as a replacement glyph followed by `D8` — the lab sources, the bowel-movement reference, and the provenance blocks D53 built precisely so that sourcing would be visible. About a month, on every surface that cites anything.

**How it survived.** The character is invisible in the source: an editor shows a one-character oddity inside a CSS string, and a diff shows a line nobody re-reads. Every gate that touches this surface asserts **strings and structure** — that the block exists, is closed by default, carries a summary and a body, and hides no safety line. All of that was true, and all of it was green, while the marker painted a box.

**It also survived the on-device pass**, which happens every release. A person reading a citation line reads past a small glyph they half-expect. That is what decoration means.

**The standing limit, stated so it is not rediscovered:** the suite reads the DOM, the CSS text and the geometry. **Nothing in it looks at the rendered page.** The CDP gates come closest, and they measure boxes — a box can be exactly the right size and paint nothing legible.

**What follows, which is deliberately narrow.**

- **The class is gated where a text gate can reach it:** no control characters in the shipped shell, and the citation marker must resolve to the character it was meant to be (`SE-ctrl`). A screenshot found it; a text gate can keep it out.
- **The limit is not closed by that**, and saying it was would be D3's shape — asserting a safety we do not have.
- **When a slice touches a visible surface, look at it.** H4 and H5 both rendered the page at 390 px, and both found defects that way: a confirm button that did nothing when the name was empty, a control labelled like a status, and this. **Screenshots are not evidence and not a gate.** They are the only step in the process that reads the page.

## D89 — H4.1 built: removing what should never have been saved (2026-09-17)

`APP_VERSION → 0.32.0`; schema unchanged at v11. Forks A1, B1, C1 and D1 ruled as recommended, with the data-loss implication ruled with them.

### What was built

- **"Remove — saved by mistake"** on a medication row. It takes the medication, its fills, and the label document saved with it if nothing else points at that document.
- **The confirmation names** the medication, its fill count, and "Mark stopped" as the alternative for one that was actually taken. It says the removal can be undone straight afterwards, **and nothing more** (D3).
- **A single fill can be removed** on its own, leaving the medication and its other fills. The fills are now **listed** on the row rather than counted, because a fill that is only counted cannot be removed.
- **Both are undoable** through the existing undo, and the undo restores exactly what was taken, the document included.
- **The scan list is untouched** by either removal. The scan happened.

### The data-loss ruling, recorded where it binds

Once the undo window has passed, a removal cannot be reversed; the only way back is an export taken beforehand. That is why the confirmation promises the undo and nothing after it, and why removal is named for a mis-scan rather than offered as general tidying. Restoring an older export brings the medication back, but that is restore's contract (D5), not a recovery path for this action.

### Why a hard delete rather than a flag

A retraction flag would have to be honoured by every consumer — the list, both copy actions, refill matching, and H5's documents. That is safety by enumeration, which R33 rejected for plates and which this project has walked into repeatedly. The evidence a retraction would keep is also unusable: D72 rules that corrections noticed only when someone happened to notice are not a metric.

### The census caught a claim this slice got wrong

The pre-registration said a removal creates nothing, so the D29 write-site census would not change. **It does change.** `removeMed`'s undo closure writes `meds[id] = snapshot`, which is the shape the detector matches, and the census failed the suite by name until the site was registered.

It is registered **exempt**, and the reason is worth keeping: the undo puts back a record that already existed. Stamping it on the way back would rewrite history — the medication would claim to have been created at the moment someone undid a mistake. This is the first site in the manifest that **writes without creating**, and the detector matches the shape of a write rather than its intent, which is why the manifest carries reasons at all.

### What the defect pass found

Thirteen plants, and four of them exposed gates that could not fail by name:

| plant | what it showed | repair |
|---|---|---|
| the fill removal also deletes the medication | two cases dereferenced the medication the defect had removed, so the suite reported *"something threw"* (**Clause 5**) | the dereferences are guarded, and each case fails as itself |
| the removal filters the scan list | the scan case asserted only that the list was **non-empty**, which stayed true | it now asserts the list is unchanged **entry for entry** |
| the fills are not listed | no case asserted the listing — only a fixture mentioned it | a case asserts every fill is listed on the shipped row with its own control |
| the removal removes the wrong fill | the plant changed which fill was **snapshotted**, not which was spliced, so undo caught it and the removal gate did not | the plant now splices the wrong index, which is the defect it was meant to be |

**And one gate was re-pointed after measurement.** `H4.1-distinct` first asserted that "Remove" is **shorter** than "Mark stopped". Measured in the shipped page, it is taller: the label wraps to two lines while being smaller type with no chrome. Height was the wrong proxy for R19's claim, which is about weight and thumb path. The case now measures type size, font weight, the absence of button chrome, and that the two controls do not overlap.
## D90 — A complete day with no items is an absence, not a zero (amends D10) — v0.32.1 (2026-09-19)

Ruled as H7 Fork C, and **shipped before H7** because H7 would have inherited it. `APP_VERSION → 0.32.1`; schema unchanged at v11. Aggregates only; no stored data changes.

### The defect

`macroCoverage(day)` returned `partial: n < m`. At `m = 0` that is `0 < 0` → **false**. A day marked complete with nothing on it was therefore **not** partial, passed every filter, and was averaged and plotted as a **genuine zero**.

**D10 licensed it in terms:** *"every complete day has them (**0 for a fasting day**)"*. That sentence is the defect, and it is now amended.

### Why the premise is false, from the log rather than from argument

Measured against the author's real export (aggregates only; the export is gitignored and never enters the repo):

- the 28-day window holds **10 complete days**, of which **3 have no items**;
- the shipped series plotted all three as `0 kcal`;
- the effect on the figures was **−33%** on energy, protein and fibre alike (energy 993 vs 1490 kcal).

And the app **already held the contradicting fact**. The fast log contains five entries and **every one is resolved `ate_didnt_log`** — the only state present in the store. All three empty days fall inside those windows: `2026-09-01` inside a 1132-hour entry, `2026-09-05` and `2026-09-06` inside a 67-hour one. **Three of three.**

So this is not an inference about what an empty day means. It is **two recorded facts in one store contradicting each other**: the day says *complete and empty*, and the user's own resolution says *I ate and did not log it*. The chart drew the wrong one.

### The ruling

**A day with no items has no macro data.** It is excluded from the macro mean and from every series, it is **counted in M** so the denominator still describes the window honestly, and the surface says how many days were left out and why. This is **R31's ruling one level up**: R31 handled an *item* with no composition, and this is a *day* with no items. Both are D8 — absence is not zero.

- `macroCoverage` gains **`absent`** (`m === 0`). `partial` is unchanged, because `n < m` was never wrong — it was **silent** at `m = 0`.
- **`dayHasMacros(day)`** is the single predicate every macro aggregate asks. One predicate rather than two checks at each call site, because the next consumer's author will copy whatever is there.
- The exclusions are **counted separately and never merged**. *"Composition not recorded"* and *"nothing logged"* are different facts about different days; one number covering both would describe neither. R31's sentence is **byte-unchanged** where it applies.

**Scope: aggregates only.** The day view and the history row are untouched. A day you are looking at shows what it holds, and that it holds nothing is visible without a sentence — *"from 0 of 0 items"* would be a coverage note describing a denominator that does not exist. Gated both ways.

**A second class of day is fixed as a side effect, and it is worth naming.** R33's plate-only day also has `m === 0` — a plate recorded, no consumption logged. It too was averaging in as a zero. The same predicate covers it, for the same reason.

### The defect was not unnoticed. It was gated as correct.

`A3`, from Phase 1, asserted it directly:

```
// A3. macro mean = sum/M; a fasting complete day counts as a real 0-intake day
res(a3.n === 2 && a3.macros.kcal === 50, 'A3: macro mean = sum/M incl fasting day (100/2 = 50)');
```

The case is re-pointed to `nMacro === 1` and a mean of `100`, and it carries the history in its own comment. **A gate that pins a premise is only as good as the premise** — which is the general point, and the reason D10's sentence is amended in the log rather than quietly worked around in code. This is the second correction to D10's macro clause; R31/D67 was the first, and that one was a re-pointing that left the premise standing. This one removes it.

### The defect pass

Five plants, **all five failing their named gates**:

| plant | gates that failed |
|---|---|
| the average counts the zero again (the exact v0.32.0 line) | `D90-avg-exclude` ×3, `D90-avg-denominator`, `A3` |
| the series draws the zero again | `D90-series` ×2, `D90-stated` ×2, `D90-two-reasons` ×2 |
| `absent` is never true | 13 gates, `D90-absent` and `D90-predicate` among them |
| one count covers both reasons | `D90-stated` ×2, `D90-two-reasons` |
| the empty day is dropped from **M** as well as N (the over-correction) | `D90-avg-exclude`, `D90-avg-denominator`, `R31-avg-exclude` ×2, `A3` |

The fourth plant is the one worth keeping: it is the *plausible* wrong fix, not an obvious breakage, and without the two-reasons gate it would have passed. The fifth is the over-correction — dropping the day from the denominator too would have made the window describe fewer days than it covers.

**One runner note, not a code finding.** The third plant first reported **no SUMMARY**, which under D60 Clause 5 reads as a hang rather than a named failure. Re-run in isolation it produced a clean verdict and failed 13 gates by name. This is the **known intermittent** — an empty headless dump under memory pressure or a CDP port collision — and it is recorded here because a defect pass that reports "no verdict" must be re-run before the plant is blamed, or a working gate gets rewritten to chase a phantom.
## D91 — D24's colour rule reaches the surface it was never applied to — v0.32.2 (2026-09-19)

Ruled alongside H7 Fork G, and built immediately rather than folded into H7: H7 was about to place a scrupulously neutral chart one screen away from a surface doing the opposite, which would have made the inconsistency the user's problem rather than the record's. `APP_VERSION → 0.32.2`; no schema change; no stored data touched.

### What shipped for eleven versions

D24 ruled, for signal goals: **"No met/unmet color, ever.** A green 'under your ceiling' line is the evaluative word 'good' **re-encoded past the text grep** — an honesty invariant satisfiable by changing the encoding is not an invariant."

The **food** goal surface did exactly that, in three places:

| site | what it encoded |
|---|---|
| `goalCellsHTML` | `class="goalcell ${gp.status}"` → `.met,.good{border-color:var(--good)}` / `.short,.over{border-color:var(--warn)}` |
| `goalRingBoxHTML` (nutrient branch) | `ringSVG(pct, gp.status)` → a ring stroke in `var(--warn)` when over or short |
| the same function | `<span class="gpct ${gp.status}">` → the percentage itself in `var(--good)` |

The DOM carried the literal class name **`good`**. M7's banned list contains the string `" good"`. The word grep would have caught this on the first run — **it was never pointed at this HTML.**

### The gap is the finding; the green border is where it surfaced

Seven vocabulary gates existed. All seven read the Mirror, the capture box, the rhythm rings, the gap surfaces, or the ring legend. **None read the food goal surface.** So the rule was enforced everywhere it had already been thought about, and nowhere it had not — which is the definition of a gate that describes its author's attention rather than the product.

The detail that makes this unambiguous: **the signal branch of `goalRingBoxHTML` carries the comment *"Signal goal: fully neutral — no met/unmet colour or word (D24)"* three lines below the nutrient branch that did the opposite.** The rule was known, written down, and applied to one branch of one function.

**That is a different failure from not knowing the rule**, and it is the one worth recording. A rule nobody has written down is a gap in the record. A rule written down, understood, and applied to the branch the author was looking at is a gap in **reach** — and no amount of restating the rule fixes it. Only pointing a gate at the other surface does.

### The ruling

**No met/unmet colour on the food goal surface either.** The numbers stay exactly as they were — what you had, the target, floor or ceiling, the percentage. Only the verdict is removed.

`goalProgress` **still returns `status`**, and that is deliberate. D24's line is between **computing** the gap and **encoding a judgement** about it; only the second was ever forbidden. The arithmetic has consumers that are not colour.

**Why this rather than the M7 amendment.** The pre-registration recommended the other option: record a deliberate amendment permitting evaluative colour for *user-declared* nutrient goals, on the argument that a floor you set for yourself is a different object from a derived typical. **That was not taken**, and the reason is worth keeping: D24 already considered and rejected the "but the user declared it" argument for signals, on the ground that **direction-of-good is personal** — and it is no less personal for food. A ceiling someone set while cutting and a ceiling someone set while recovering are the same number wearing opposite meanings, and the app cannot tell which.

### Gated where it broke

Proof by **output equality**, not by assertion — the SG1 / FX3 pattern. The same totals against a goal that is **met** and one that is **short** must emit identical classes and identical stroke colours; only the numbers may differ. Plus the word grep this surface never had, with its planted control, and a fixture check proving the two sides genuinely differ in status (D60 Clause 4).

### ADDENDUM (2026-09-20, from H7/D95) — the same fact about reach, pointing the other way

D91 found a surface **no gate read**: `class="goalcell good"` shipped for eleven versions past a banned list containing the string `" good"`, because nothing pointed that list at the food goal surface.

H7 found the **opposite**, and it is worth reading beside it. The plant that put an evaluative word on the new Typical row failed **M7** and **SG7** as well as `H7-no-evaluative` — the Mirror's own vocabulary gates already read the Trends surface, so **the new row inherited their cover the moment it was rendered there.** Nobody wrote a gate for it; it arrived already covered.

**Two facts about reach, pointing opposite ways:**

| | what happened | what it cost |
|---|---|---|
| **D91** | a surface rendered **outside** every vocabulary gate's reach | eleven versions of the encoding D24 forbade, ungated |
| **D95** | a surface rendered **inside** an already-gated one | cover for free, before its own gate existed |

**The rule they jointly make is about placement, not about diligence.** A vocabulary gate reads a *region of the DOM*, so **where a new surface is rendered decides whether it is covered before anyone decides to cover it.** Rendering inside an already-read region is the cheapest coverage available, and rendering outside one is a silent opt-out that no amount of care elsewhere compensates for.

So the question to ask of any new rendered surface is not only *"does it have a gate?"* but **"is it inside one?"** — and when the answer is no, that is a decision being made, whether or not anyone notices making it.

`H7-no-evaluative` was still written, and still earns its place: it adds **"target"** and **"goal"** to the banned list **for that row specifically**, because the entire point of the row is that it is neither. Inherited cover is cover for the general rule, not for the claim the surface makes on its own.

**The standing consequence, recorded so it is not rediscovered:** a vocabulary gate covers the surface it is pointed at and no other. There is no grep over "the app". When a slice adds a rendered surface that states anything about a user's numbers, **pointing the banned list at it is part of building it** — and the count of such gates (now eight) is a count of surfaces reviewed, not a measure of coverage.

## D92 — A gate that would fail if the code were right (2026-09-19; doc-only)

Recorded beside the vacuous-gate family, and distinct from every member of it. **D60 Clause 5, D87 and D88 all describe gates that cannot fail.** This one fails readily — **it fails when the code is correct.**

### The shape

A test that encodes a **premise** rather than a behaviour becomes the premise's defender. When the premise is wrong, the test does not merely miss the defect: it **converts the defect into a protected invariant.**

That is strictly worse than having no test, and the reason is about people rather than arithmetic. With no test, the next person to notice the behaviour investigates it. With this test, they find **an assertion telling them the behaviour is intended** — signed, named, and passing. The gate does not hide the defect. It **argues for it**, and it does so at exactly the moment someone tries to repair it, because that is when it turns red.

### The instance

`A3`, written in Phase 1 and green for every release since:

```
// A3. macro mean = sum/M; a fasting complete day counts as a real 0-intake day
res(a3.n === 2 && a3.macros.kcal === 50, 'A3: macro mean = sum/M incl fasting day (100/2 = 50)');
```

The arithmetic is correct. The premise — that a complete day with no items is a fasting day, and its zero is real — is the sentence D90 withdrew from D10 after measuring a real log where **all three such days sat inside fast windows the user had themselves resolved as *ate, didn't log***.

**The failure mode, played out.** The D90 fix was applied, the suite went red, and the red test was a Phase-1 case asserting a number that had been wrong for the app's whole life. The correct response was to re-point it. A plausible and much cheaper response — *"my change broke a passing test, so my change is wrong"* — would have reverted the fix and left a 33% understatement in place, with a green suite and a documented reason to leave it alone.

### Why the usual defences do not catch it

- **The defect pass does not.** Planting defects proves a gate fails when the code is wrong. A3 fails when the code is **right**, which no plant will ever reveal.
- **The assertion count does not.** 1916 assertions passed, and one of them asserted a wrong number. A count measures how much was checked, never whether the checks were checking the right thing.
- **Review does not, reliably.** A3 reads as correct, because it *is* correct given its premise. The error is one level up, in prose, in another file.

### Recorded as UNREACHABLE BY CURRENT MACHINERY

This is the part to keep prominent, and it is stated as a limit rather than as a problem with a solution attached. **Neither of this project's two defences reaches this failure, and no rule stated here closes it.**

- **The defect pass cannot.** Planting defects proves a gate fails when the code is **wrong**. A3 fails when the code is **right**. No plant will ever reveal it, because plants search the wrong direction.
- **The assertion pin cannot.** **1,916 assertions passed, and one of them asserted a wrong number.** The count measures how much was checked. It is structurally incapable of saying whether a check checks the right thing.

Adding a third mechanism is not proposed, because the ones that exist fail here for a reason no additional automation removes: **every gate compares the code to an expectation, and the fault is in the expectation.** A machine that could audit expectations would need the thing the expectations are supposed to encode.

**If anything reaches it, it is a review of what each assertion CLAIMS rather than whether it passes — and that is a reading task, not a gate.** Reading 1,953 assertions for their claims is real work with no green tick at the end, and pretending otherwise by writing a rule here would be the same move as a gate that cannot fail: comfort standing in for coverage.

Two practices are worth the small amount they cost, offered as habits rather than as a closure:

1. **When a premise is amended, search the harness for gates that encode it, as part of the amendment.** D90 found A3 only because the arithmetic happened to change; had the numbers coincided, nothing would have flagged it.
2. **Treat a test that goes red during a repair as evidence about the test, not only about the repair.** Ask which state the premise supports before concluding the code is at fault.

### The standing line

**A passing suite says the code does what the tests say. It never says the tests say the right thing.** Every premise stated in DECISIONS.md and pinned in the harness is load-bearing in both files at once, and amending it in one place leaves it defended in the other.

**This entry is a named blind spot, not a solved problem.** It sits beside D88 — *no gate reads the page as a person does* — as the second standing limit this project has recorded and cannot gate away. Both are answered by a person looking, and both should be re-read whenever a suite's greenness is about to be offered as evidence that something is right.
## D93 — The confidence dot stays, and the item row gets the gate it never had (2026-09-19)

Found while checking D91 for orphaned CSS: `CONF_DOT = { weighed: 'good', measured: 'accent', eyeballed: 'warn' }`, rendering `<span class="dot good">` on every item row — the same two colour tokens D91 had just removed from the goal cells, on a surface no vocabulary gate reads. Tests and gates only; no version bump.

### Ruled: it stays

**A confidence dot judges the EVIDENCE, not the user.** *"Weighed" versus "eyeballed"* is a statement about provenance quality, and making it visible is most of what this app is for — the honesty rule in the brief exists to keep estimates from wearing the clothes of measurements.

D24 bans **direction-of-good about the user's behaviour** — met versus unmet. Its reasoning was that the direction is **personal and contested**: a ceiling set while cutting and the same ceiling set while recovering mean opposite things, and the app cannot tell which. **Neither half of that applies here.** A weighed measurement being better evidence than a guess is not personal, and it is not contested. The two cases look alike only because they share a CSS token.

### The reach argument still held, and the gap was real

**Cleared by ruling and covered by a gate are different states, and this surface had only the first.** No vocabulary gate read the item row. So the token was licensed by an argument while the surface it sits on remained unexamined — which is exactly the shape D91 recorded one surface earlier, and recording the shape twice without closing it the second time would have been the reach failure repeating with a better excuse.

### The gate

It asserts **what is permitted** as well as what is not, because a gate that only forbids cannot tell a licensed token from a missing one:

- **Permitted, asserted positively:** every confidence dot carries exactly `dot` plus **one** of the four provenance tokens, and the token **follows the confidence** (weighed → good, measured → accent, eyeballed → warn). A dot that stopped tracking the confidence would be decoration, and the gate says so.
- **Forbidden, asserted negatively:** no element **other than the dot** carries a provenance token — the colour is licensed for the evidence, not for the row — and **no class anywhere on the row** names a verdict about the user (`met`, `short`, `over`, `compliant`, `ontrack`, `success`, `fail`, `bad`).
- **The visible text** carries no M7 vocabulary at all. This is what makes the dot defensible in the end: it is a coloured circle with **no words**, so the token never reaches the reader as vocabulary — while the provenance **words** (`weighed`, `eyeballed`, `manual`) are asserted to still be there.
- **Controls** on both the verdict-token check and the word grep, so neither is vacuous.
- **R31 × D93:** a row stating *"composition not recorded"* still says nothing evaluative — an absence is a fact about the record, not a mark against the user.

**Scope, stated so a later reader does not widen it by accident.** This checks **app-authored vocabulary against a controlled fixture**. An item *named* "Better Butter" is user content — escaped, never vocabulary-checked — and a gate that grepped user data would fire on somebody's groceries. The rows are read through the **DOM**, not by slicing HTML, so nesting cannot quietly change what is being asserted.

**Defect pass: six plants, six named failures** — a row carrying a verdict class, a provenance token off the dot, a dot that ignores the confidence, an evaluative word in the meta line, the provenance word dropped, and a dot carrying a verdict token alongside its provenance one.

### Three runner findings, all worth more than the gate

**1. A defect pass on a CLEAN tree is silently disabled.** All six plants first returned **no verdict at all**. The cause was not the intermittent: a plant modifies `app.js`, which changes the shell, and **`check-version` then fails the run before the harness executes** — *"shell changed since last commit but APP_VERSION did not bump"*. The D90 and D91 passes only worked because uncommitted work was already in flight and had carried a bump with it. **Every plant must now carry a version bump**, and a defect pass run straight after a commit would otherwise test nothing while looking like it ran.

**2. The D91 lesson paid for itself immediately.** That pass had scored a plant **OK** because its expected gate appeared in the failure list, even though the suite produced no SUMMARY — and a named failure does not prove the rest of the suite ran. The runner was changed to treat **no verdict as inconclusive, checked first**. One pass later that ordering is what surfaced finding (1) as six honest *inconclusive* results instead of six silent vacuous passes.

**3. The intermittent, finally characterised.** It appeared **four times** across this session's three defect passes, and the pattern is now clear enough to state instead of merely noting:

- it strikes **one run out of six**, and **a different plant each time** — `absent-never-true`, then `the-facts-are-dropped`, then `provenance-word-dropped`, then `dot-carries-a-verdict-too`;
- it always occurs inside a **long sequential series** of suite runs;
- and, crucially, **the assertions had all executed.** The saved output carries the full PASS/FAIL stream, the expected gates failing by name among it, and then stops before the summary: *"no SUMMARY line (the suite did not finish)"*.

**So what is lost is the tail of the output, not the results.** That makes an inconclusive run whose named gates failed strong evidence rather than none — but still not a complete verdict, because the assertions *after* the truncation point are genuinely unknown. Re-running remains the right response; the refinement is that the truncation is an output-capture failure under sustained load, and not a sign that the plant did something strange.

All three are recorded here rather than in a scratch file because the defect pass is the machinery the rest of this log leans on, and **a pass that cannot fail is the same hazard as a gate that cannot fail** — [[D92]]'s point arriving one level out.
## D94 — Scope check: how far back does the clean-tree abort reach? (2026-09-20; tests and docs only)

D93 found that a defect pass run from a **clean tree** tests nothing while appearing to run: a plant changes the shell, `check-version` aborts before the harness executes, and no assertion runs. **A recorded pass that could not have executed is worse than an unrun one** — it is evidence asserting something it never tested, which is [[D92]]'s shape applied to the pass rather than to a gate. So the question is not "is it fixed" but "what does it invalidate".

### The decisive test, measured rather than argued

**An aborted run produces zero assertion output.** Measured directly during D93's diagnosis: **552 bytes**, ending at `VERSION CHECK: FAIL`, with **no PASS lines, no FAIL lines and no SUMMARY**. `check-version` runs ahead of the harness, so nothing downstream of it ever speaks.

That gives a self-certifying property: **any recorded pass whose result names a gate that failed is proof the harness executed.** No reasoning about historical tree state is needed — the evidence is in what the record contains.

### Applying it to the record

Every defect-pass result statement in `GATES.md` and `DECISIONS.md` was enumerated. **All of them name failures** — *"81 plants, each failing its own named gate"*, *"13 plants, each failing its own named gate"*, *"51 plants… run on the final tree"*, *"seven new plants, each failing its own named gate"*, *"45 planted, and every one fails its own named gate"*, *"thirteen planted, ten in the final set, all ten failing their own gate by name"*, *"each fails the floor case by name"*, *"restoring the previous CSS fails three of the four"*, *"reads `paths=3 dots=2 drawn=100%` → FAIL"*.

**Not one reports zero named failures.** That is the shape an aborted pass would have, and it does not appear.

The passes that *also* report gates which could **not** fail — *"the pass found two gates that could not fail"*, *"TWO gates"*, *"five gates that could not fail"* — are the strongest cases of all, because those findings sit **inside runs where other plants failed by name**. A mixed result is only possible from a run that executed.

### The four candidates, individually

Commits touching `tests/` but not `app.js` or `index.html` are the only ones that could have run a pass from a tree carrying no bump. There are four:

| pass | how it ran | status |
|---|---|---|
| **D75** (runner) | a **throwaway copy of the repo**, with the harness and all eight CDP gates stubbed to print `GATE: PASS` — `check-version` lives inside the harness leg and never executed | **safe by construction** |
| **D83** (census) | a **throwaway copy of `app.js`**, with `check-writesites.sh` invoked **directly**, not through the runner | **safe by construction** |
| **D85** (keyless floor) | plants into `app.js` on a no-bump slice — **the one genuinely ambiguous case** | **re-run and re-verified** |
| **D93** (item row) | the actual occurrence, caught at the time | **caught, fixed** |

**D85 was not argued, it was re-run.** Its decisive plant — the kind chooser rendered only with a key, *which is what actually shipped in v0.30.0* — was replanted against today's tree with release metadata carried. Result: `SUMMARY 1951/1953 — 2 FAILED`, `H4.2-nokey GATE` and `H4.3-keyless GATE`, both by name. **D85's gates catch the defect they were written for.**

### Conclusion

**No recorded defect pass is in doubt.** And the reason this went unnoticed is a workflow fact rather than a code one: passes have always run **pre-commit**, while the slice's own version bump sat uncommitted in the working tree and satisfied `check-version` by accident. **D93 was the first pass ever run from a clean tree**, because it was the first slice whose gates were written *after* the preceding slice was committed.

**The failure mode is conspicuous, not silent.** An abort makes **every plant at once** look unable to fail. A pass reporting that would be unbelievable on its face — which is why it was caught on its first occurrence, and why the record can be cleared by inspection rather than by re-running everything.

### What the scope check found on its own account

**D85's control was coupled to its gate.** It read `kl.length === 0 && ...caprow absent` — ANDing in the gate's own condition — so it could **never pass while the gate failed**. Every plant "failed the control" too, and the control certified nothing the gate had not already said. Its job is to establish **independently** that the page under test is keyless; it now asserts only that, and the replant confirms the change: three failures became two, with the control passing while the gate fails.

**This is the vacuous-control family wearing a second hat.** D60's clauses catch a control that cannot fire. This is a control that **fires whenever the gate does**, which is the same emptiness read from the other end: it moves with the thing it is supposed to hold still against. **A control ANDed with its gate's condition is not a control.**

### The intermittent, characterised

Recorded as settled, replacing the two earlier speculative notes (*"memory pressure or a CDP port collision"*):

- **five occurrences** across this session's defect passes;
- roughly **one run in six**, and **a different plant every time** — `absent-never-true`, `the-facts-are-dropped`, `provenance-word-dropped`, `dot-carries-a-verdict-too`, and the first D85 replant;
- always inside a **long sequential series** of suite runs;
- and in **every** case the assertions had **already executed**: the output carries the full PASS/FAIL stream with the expected gates failing **by name**, then stops before the summary — *"no SUMMARY line (the suite did not finish)"*.

**What is lost is the tail of the output, not the results.** It is an **output-capture failure under sustained load** — not a plant misbehaving, and not the memory flake it was first filed as. The practical consequence: an inconclusive run whose named gates fired is **strong evidence but not a complete verdict**, because assertions after the truncation point are genuinely unknown. Re-run, then read; do not rewrite a working gate to chase it.
## D95 — H7 built: the typical band, a nutrient against the user's own recent normal — v0.33.0 (2026-09-20)

All ten forks ruled before a line was written. `APP_VERSION → 0.33.0`; **no schema change**, nothing new stored, nothing persisted by the surface.

### What was built

A **Typical** row in Trends. For one macro at a time, it draws the user's recent complete days as bars against **their own middle day** over a fixed 28, with the **middle half** of those days as a band behind them. Under it: a trail of *last 3 days · 7 days · 28 days*, each printing its own span and its own n, and a direction marker that always states **both** numbers it compares.

- **Fork B1 — median, not mean**, and the reason is recorded so it is not read as a general preference: **the distribution is skewed by single-item days.** In the log that motivated this, one day sits at 3,930 kcal among days of a few hundred, and the mean sits above four of the six values. The middle half is the Tukey-style band a median deserves. Elsewhere this app still says *avg*; here it says **median**, and the caption says so.
- **Fork D1 — a floor of eight usable days**, and the cost was ruled with it: **on a sparse log this surface shows nothing.** It says how many days it has and how many it needs. A band drawn from six days spanning 115 to 3,930 kcal would be arithmetically correct and descriptively empty.
- **Fork G1 — direction only.** Above and below the middle day are **two tints of one hue** differing in lightness. `var(--good)` and `var(--warn)` are absent by construction and by gate: those two tokens mean *good* and *bad* everywhere else here, and reusing them would be [[D91]]'s finding with a new address. **A bar above the middle day is not a better bar.**
- **Fork H1 — macros only**, and `soluble_fiber_g` is **not offered**: it is *"always present, 0 when unknown"* by contract, so most of its values mean **unknown**, and a band drawn round that is [[D90]]'s zero again, drawn prettier.
- **Fork E1 — the goal is never compared to.** A goal is declared; a typical is observed. The row renders **byte-identically** with and without nutrient goals set, which is proven by equality rather than asserted.
- **Fork F1 — the sourced-band seam is built and left empty.** No food nutrient has a D32 band: every analyte there is a blood measure, and 25-OH vitamin D is serum **status**, not dietary intake. The renderer accepts one, draws it as an **outline** so it can never be mistaken for the user's own band, and carries org, citation and version. Nothing supplies one; the path is reachable only by its gates.
- **Fork J1 — two vocabularies, kept deliberately.** The 30/90/all buttons choose how much to draw; the trail's legs are the content, fixed and independent of them. **28 = 4×7**, so every weekday appears exactly four times. The disqualifying property of 30 is **instability, not magnitude**: the drift is ~2.3%, and a reference whose value depends on which day you open the app is not a reference at any size. The same unevenness costs a trend line nothing, because no single number is claimed from it.

**One narrowing, recorded rather than left silent.** The chosen nutrient is **UI state and is not persisted**. Persisting it is a settings write, which brings the D29 census, the normalizer allowlist and a migration question with it, and none of that was ruled. Gated: choosing a nutrient writes **nothing** to storage.

### A contradiction in the pre-registration, found in the build

The pre-registration said Fork D's floor *"applies per trail leg, not only to the band"*, and Fork J's proposal repeated it. **Both cannot hold: 3 is never 8, so a floor of eight applied per leg blanks the 3-day leg permanently** — by construction, on every possible log.

Resolved the coherent way: **the floor gates anything offered as a typical** — the band, and the direction marker that compares against it. **A leg reports a span, not a typical**, so it always renders, and what it must do instead is state its own n. A leg with nothing in it says *"no complete days"* rather than reaching further back for something to show. Recorded here because the pre-registration is the record and it was wrong on this point.

### The defect pass, and the fixture that could not tell a median from a mean

Sixteen plants. **The first run scored `typical-is-the-mean` VACUOUS**, and the reason is the finding: the fixture ran ten days at 100, 200 … 1000, evenly spaced — where **the mean and the median are both 550.** The plant changed nothing, the gate passed with the defect in, and **Fork B1's entire ruling was untested.**

That is **D60 Clause 4, seventh instance**, and the sharpest one yet: the gate was not weak, and the assertion named the right property. The *fixture* was symmetric, so the two answers coincided — a fixture cannot distinguish a median from a mean unless the data is skewed, which is precisely the condition B1 exists for. **The repair mirrors the log that motivated the ruling:** one day at 4,000 among days of a few hundred. The quantiles are unchanged (550, 325, 775) and the mean moves to 850 — and the fixture now asserts that difference explicitly, plus that the outlier **does not move the band**, which is the property that makes a median the right summary.

Five further plants exposed problems in the gates or the runner rather than the code:

| plant | what it showed | repair |
|---|---|---|
| the sourced band is drawn as a fill | the check was `/class="tsrcband"[^>]*fill=/` — **order-dependent**, so a plant writing `fill=` *before* `class=` sailed past it | read through the **DOM**: the element's `fill` attribute must be absent, however the tag is written |
| the citation is dropped | `H7-band-absent` keyed on the literal string `labcite`, so a plant that merely **renamed the class** slipped past | keyed on the citation **block** and the element, not a substring |
| the denominator is not rendered | the plant reported **PLANT FAILED (anchor ×0)**: `app.js` carries the literal six characters `·`, and a non-raw anchor turned it into the character | the anchor stops short of the escape |
| the choice is persisted | the plant called `resave()`, which is not in scope — **invalid JS aborted the suite**, which under Clause 5 reads as a hang | `Store.saveState(APP_STATE)`; a plant must be valid code or it tests nothing |
| the citation is dropped | the runner **expected the wrong gate** (`H7-band-absent`) — an error in the expectation, not in the gate | expectation corrected to the gate that actually guards it |

**Final: sixteen plants, sixteen failing their own named gates.** The intermittent appeared on three runs and each was re-run to a clean verdict, per [[D94]].

### One cross-check worth keeping

The `evaluative-word-on-the-row` plant failed **M7 and SG7** as well as `H7-no-evaluative` — the Mirror's own vocabulary gates already read the Trends surface, so the new row inherited their cover the moment it was rendered there. That is the opposite of [[D91]]'s finding, and a useful one: **placing a new surface inside an already-gated one is the cheapest way to be covered.** `H7-no-evaluative` is still worth having, because it adds **"target"** and **"goal"** to the banned list for this row specifically — the entire point of the row is that it is neither.
## D96 — A fixture must be able to distinguish the thing the ruling chose between (2026-09-20; doc-only)

**The rule.** Any ruling that picks **one statistic, one ordering or one policy over another** needs a fixture in which the **alternatives give different answers**. Otherwise the gate asserts a distinction the data cannot carry: it names the right property, passes, and says nothing about the choice it was written to protect.

### The instance

Fork B1 ruled **median, not mean**, for a stated reason: the distribution is skewed by single-item days. H7's fixture was ten complete days at 100, 200 … 1000.

**Mean 550. Median 550.**

So the plant *"typical is the mean"* changed nothing, `H7-quantiles` passed with the defect in, and **B1's entire ruling was untested** — while the gate named exactly the right property and the assertion was exactly the right assertion. Nothing was wrong except the data underneath.

The repair mirrors the log that motivated the ruling: **one day at 4,000** among days of a few hundred, the way `2026-09-11` sits at 3,930 in the real export. The quantiles do not move (550, 325, 775) and the mean becomes 850 — and the fixture now asserts **that difference** explicitly, plus that the outlier **does not move the band**, which is the property that makes a median the right summary.

### How this relates to D60 Clause 4, and why it is worth its own line

It **is** a Clause 4 instance — the starting state made the assertion true regardless of the code — and it is registered as the **seventh**. But Clause 4 is stated from the **defect's** side: *can the planted defect change the outcome?* That question is asked once per plant, during the pass, and it found this one only after the fact.

This rule is stated from the **ruling's** side, and can be asked **before** anything is run:

> **For each ruling that rejected an alternative, what would the rejected alternative produce on this fixture?** If the answer is *"the same thing"*, the fixture cannot test the ruling.

That is a cheap, mechanical question with a predictable answer shape, and it belongs in the pre-registration rather than the defect pass. D60's register already noted that instance 6 was the first caught by **reading the fixture before the run**; this is the reading rule that would have caught instance 7 the same way.

### Where it bites, beyond medians

The shape recurs wherever a choice is made and a fixture is symmetric with respect to it:

- **mean vs median vs trimmed mean** — any symmetric sample makes all three agree;
- **stable vs unstable sort** — a list with no duplicate keys cannot tell them apart;
- **first-wins vs last-wins** on a merge — a fixture with no conflicting keys cannot show which;
- **inclusive vs exclusive** bounds — a fixture with no value **on** the boundary tests neither;
- **round-half-up vs round-half-even** — no value at exactly .5 and the rule is untested;
- **absence vs zero** — the D90 family: a fixture where the absent value **would have been** zero proves nothing.

Each is the same failure: a ruling that distinguishes two behaviours, tested on data where the two behaviours coincide.

### The practical form

**A pre-registration that rules between alternatives names the fixture property that separates them.** Not the fixture itself — the *property*: "skewed, so mean ≠ median", "contains duplicate keys", "contains a value exactly on the boundary". One clause, written when the ruling is made, while the alternatives are still in mind. By the time the defect pass runs, the rejected alternative has usually been forgotten, which is exactly why the gate looked right.
## D97 — Two findings about string rules, both measured against the corpus (2026-09-20; doc-only)

Both came out of H8's measurement, and both are recorded because they generalise past drug names.

### 1. Chemical-looking is not the test

**The prior, stated plainly so the inversion is visible:** the ruling claimed *form and strength* are safe to strip because they are package descriptors, not part of the ingredient name — and then extended that to **salt and ester words**, because they look chemical.

**The measurement says the opposite.** Stripping a trailing chemical word from nine real names:

| printed | labels | stripped | labels | |
|---|---|---|---|---|
| metoprolol tartrate | 157 | metoprolol | **12** | lands on a real, different term |
| metoprolol succinate | 144 | metoprolol | **12** | lands on a real, different term |
| amlodipine besylate | 127 | amlodipine | **4** | lands on a real, different term |
| hydroxyzine hydrochloride | 146 | hydroxyzine | **2** | lands on a real, different term |
| bupropion hydrochloride | 239 | bupropion | **3** | lands on a real, different term |
| diclofenac sodium | 275 | diclofenac | **15** | lands on a real, different term |
| levothyroxine sodium | 275 | levothyroxine | none | fail-safe |
| fluocinolone acetonide | 42 | fluocinolone | none | fail-safe |
| triamcinolone acetonide | 213 | triamcinolone | none | fail-safe |

**Six of nine.** `bupropion hydrochloride` has 239 labels and `bupropion` has 3 — they are **different product sets**, not the same drug named two ways. A salt word is **part of the substance's identity**, because it identifies the product that was dispensed.

**This is D80's succinate-for-tartrate hazard reached by stripping instead of by loose matching** — the same wrong label, through a different door. And the rule that survives is not about chemistry at all:

> **Chemical-looking is not the test.** What may be removed is what the *source* treats as a package descriptor, and the only way to know that is to ask the source. A token's appearance says nothing about whether the thing indexing it considers it part of the name.

**The case that was expected to decide it did not.** `fluocinolone acetonide → fluocinolone` resolves to **nothing** and falls through safely, so it would have argued *for* stripping. Picking the deciding case by intuition picked the wrong one; the corpus picked the right ones.

### 2. The comma: 143 of 144, and the worst outcome this feature can produce

Of **1000** distinct `generic_name` spellings, **144 contain a comma**:

- **143** are **combination products** — `AVOBENZONE, HOMOSALATE, OCTISALATE, OCTOCRYLENE`, `DEXTROMETHORPHAN HBR, GUAIFENESIN`, `TITANIUM DIOXIDE, ZINC OXIDE`;
- **1** is a strength suffix — `DICLOFENAC SODIUM TOPICAL GEL, 1%`.

**A "strip everything after the comma" rule would be wrong 143 times out of 144.** It would silently convert a combination product into a **different single-ingredient product** — and that is not a miss. A miss shows nothing and falls through. This shows **a plausible label for the wrong drug**, which is the worst outcome this feature can produce, and it does it quietly, with a confident-looking answer.

The rule is obvious, reads correctly, handles the motivating case, and is wrong 99.3% of the time it fires. **Keep it as the standing example of why an obvious string rule needs its corpus checked before it is written, not after it ships.**

### What the two have in common

Both are rules about **string shape** standing in for knowledge about **meaning**, and in both the intuition is not merely imperfect but **inverted**: the comma looks like a separator between a name and its strength and is almost always a separator between ingredients; a salt word looks like a descriptor and is almost always part of the identity.

**The generalisation, which is cheap and was skipped both times:** before writing a rule over strings from a source, **run it over a sample of that source and count what it changes.** One request returned 1000 spellings here, and it overturned two positions that had been argued from first principles. [[D96]] is the sibling rule for fixtures; this is the same discipline pointed at the rule itself.

## D98 — H8 built: the derived query term, beside the printed one — v0.34.0 (2026-09-20)

`APP_VERSION → 0.34.0`; **schema v11 → v12**. The printed string is never modified; a query term is derived **beside** it, shown **before** anything is sent, and **editable**. The match stays exact.

### What it does

D79 stores the generic **exactly as printed**; D80 matches **exactly**. Both are right, and they do not meet: a pharmacy label prints `Fluocinonide Topical Gel USP, 0.05%` and openFDA stores `FLUOCINONIDE`. The lookup now derives the second from the first, shows both, and lets the user correct the one that goes out.

- **The order:** printed generic → derived generic → printed brand → derived brand, each its own exact lookup, each flagged for what it is, stopping at the first that resolves. A name that derives to itself adds **no** second query.
- **The no-match message lists every string tried**, marking which the app shortened. *"No US label found"* alone is true and unhelpful — and it was the absence of that list that made a working lookup read as a bug on the device pass.
- **The panel shows what will be sent before the request**, not only after one fails. The case where you most need to see the query is the one where it **succeeded** on a term you did not choose.

### The tension, resolved by stating it rather than assuming it

**Deriving a query term IS a loosening**, and the ruling forbade loosening. The distinction that makes it legitimate:

> **The loosening lives in the DERIVATION, which is visible and editable. The MATCH stays exact.**

Every request still goes out `.exact` against one spelling, and a no-match is still never retried with a looser string. A derived term is a **second reading of the label**, not a widened match of the first. A3 — no derivation, the user types the term — stays recorded as the fallback if that distinction ever fails to hold.

### The rule, and the two refinements measurement forced

The allowlist is **closed and short**: dosage forms, routes, compendial marks, release qualifiers (`ER/XR/SR/DR`, ruled in), and a strength token. Everything else survives — which is what protects `tartrate`, `succinate`, `besylate`, `hydrochloride`, `sodium`, `acetonide` (see [[D97]]).

**A1 as ruled said "never across a comma", and the motivating case requires crossing one.** `Fluocinonide Topical Gel USP, 0.05%` only reduces to `fluocinonide` if `, 0.05%` goes; a literal comma barrier leaves `Fluocinonide Topical Gel USP`, which is still a 404. **Both cannot hold**, so it was tested rather than argued: a trailing-token scan that stops at the first non-removable token leaves **141 of 143** combinations untouched on its own — **the ingredient word after the comma was doing the protecting, not the comma.**

The two it *did* alter forced the refinements:

1. **A bare number is not a strength.** `GLYCERIN, HYPROMELLOSE, POLYETHYLENE GLYCOL 400` lost its `400` — but **PEG 400 and PEG 3350 are different substances**. A number counts as a strength **only when it carries a unit** (`% mg mcg g mL IU`).
2. **A combination is never partially reduced.** `AVOBENZONE 3%, HOMOSALATE 15%, OCTISALATE 5%, OCTOCRYLENE 10%` lost one ingredient's strength while its siblings kept theirs, producing a string that is neither the label nor a query. A comma followed by a word — the measured signature of a combination — now returns the name untouched.

**Re-measured after the refinements: 0 of 143 combinations altered, 12 of 12 intended cases correct, 26 of 1000 terms altered (2.6%), and every one of 14 sampled alterations resolves while preserving the substance** — every salt word survives (`MICONAZOLE NITRATE`, `CHLORHEXIDINE GLUCONATE`, `OLOPATADINE HYDROCHLORIDE`).

### Fork C, and the allowlist trap as the first obligation

The derived term is **stored**, so an edit survives and the export shows what was actually sent. That is a schema bump, and the trap that comes with it has been walked into **eight times**, so it was the build's first obligation rather than a note: `query` joined `normalizeMed` **in the same edit that introduced the field**, and export → restore is gated.

**The bump's reason, on D29's asymmetry test:** an older app strips `query`, and what is lost is **the term the user chose to send**. Re-deriving would then send a different string than the one they picked, silently — the side of the line that makes it a wrong action rather than a degraded one.

### The defect pass: ten plants, ten named failures — and three faults in the gates

| plant | what it showed | repair |
|---|---|---|
| rendering writes to storage | `H8-census` compared the stored **content**, and a redundant save rewrites the same bytes — so the gate could not see the write at all (**VACUOUS**) | it **counts** writes now, with a control proving the counter moves |
| an edit is not stored | two cases dereferenced `med.query` after the plant stopped it being created, so the suite reported *"something threw"* (**Clause 5**) | both dereferences guarded; each case fails as itself |
| the normalizer drops `query` | the runner expected `H8-editable`, which passes in memory — normalization happens at **restore** | expectation corrected to `H8-flag`, the gate that actually guards it |

Two further gate corrections came from the first green run rather than from a plant: `printed` is compared **canonically** rather than byte-for-byte, because the record is built in the draft's key order and rebuilt in `LABEL_FIELDS` order — key order is serialisation, not the reading; and the tried-list is asserted on the **list data**, because the derived term `Fluocinonide` is a substring of the printed name and a substring check would have passed with the derived entry missing entirely.

**Suite: 2027 assertions, all passing** (1996 → 2027).
## D99 — What a computed-size audit sees that a declaration audit cannot (2026-09-20; doc-only)

Three findings from H9's measurement pass, recorded before the build because they outlive this slice.

### 1. 7.9px, in no stylesheet

```
small@7.9  <  button.rmini@9.5  <  div.rgrid@16
```

`<small>` is `font-size: smaller` **from the user-agent sheet**. It is relative, so on a button already set to 9.5px it **compounds** to 7.9px. Seven elements, all of them the regimen mini-buttons that show an hour.

**No `font-size` declaration anywhere in this repo produces that number.** A grep of the stylesheet — the obvious audit, and the one that would have been run — cannot see it, because the value exists only after inheritance and the UA default are applied. **Only a computed-size audit on the rendered page finds it.**

**Second repo, same shape.** That makes it a class rather than an incident: **wherever a relative size meets an explicit one, the result is invisible to source review.** The rule that follows is not "check for `smaller`" but the stronger one — *no relative font sizes at all*, because a rule that cannot be grepped cannot be reviewed, and the next `<small>` will land inside a sized control without anyone noticing.

### 2. The app zooms on every field focus, today

**254 of 262 form controls compute below 16px.** Inputs, selects and the slider are all at **15px**; only `.fab` reaches 16.

iOS zooms the viewport when a focused field is under 16px. This is **behaviour, not typography** — the app cannot opt out of it, and no amount of care elsewhere compensates. It is the measurement that decided the floor at 16 rather than 14: a 14px body floor would have left this defect standing everywhere a control did not happen to clear it.

### 3. The newest surfaces are the smallest, and they are mine

| surface | built | largest size present |
|---|---|---|
| **Typical row** | H7, yesterday | **13px** |
| **query row** | H8, today | **13px** |
| scan list | H4 | 14px |
| med rows | H4 | 14px |
| drug panel | H5 | 14px |
| goal cells | older | 15px |

**The two surfaces built in the last two days are the only two with nothing at 14px or above.**

The rule — *a slice's own chrome gets sized last and smallest, because the author reads it at desk distance on a large screen* — was carried into this slice as a known constraint, written down in the brief, and **it still described my own work from the previous two days.** Knowing a bias and being subject to it are independent.

**What follows is a check, not a resolution.** Being aware of the tendency did not prevent it, so the countermeasure has to be mechanical: **the floor gate reads every surface, and the newest surfaces are asserted by name** (`H9-newest`), because those are the ones the author has most recently looked at on a large screen and least recently on a phone.

### And one non-finding, checked rather than assumed

H9's step count reported that `Settings → Medications → Read label` did not reach a draft, and flagged it as needing a check — *"either a harness artefact or a dead control, and the second would be the fifth this week."*

**It is neither.** `doLabelPaste()` requires a *whose* radio and the harness never chose one; it returned `{ok: false, error: 'whose'}` and rendered *"Choose whose label this is first."* **The control works and refuses for a stated reason.**

Done properly the route is **5 taps** — `Settings → mine → [paste] → Read label → Yes, that's what it says → Save` — which is **one fewer than the 6-tap Photo route**. So the shorter path is the buried one, and the path that looks right (`Log → Medication`) goes somewhere else entirely. That is recorded here because it strengthens the route ruling, and because **a flagged observation that turns out to be nothing is worth the same write-up as one that turns out to be something** — otherwise only the alarming half of the record survives.
## D100 — H9 built: a 16px floor, four sizes, three weights, and a route that goes where its name says — v0.35.0 (2026-09-20)

`APP_VERSION → 0.35.0`; no schema change. Both passes were **measured before anything was written**, and every number below was re-measured after.

### The size scale

**18 distinct computed sizes → 4: `16 / 20 / 24 / 32`.** A **collapse of what the app already used**, not a new design: the sizes already at or above 16 were 16/20/22/24/32, and the stray 22 (a single element) folded into 20. 160 declarations rewritten.

| | before | after |
|---|---|---|
| distinct sizes | 18 | **4** |
| elements below 16px | 719 (96%) | **0** |
| form controls below 16px | **254 of 262** | **0 of 263** |
| page height at 360px | 3233px (4.3 screens) | 3962px (5.2) |

**The floor was ruled at 16, not 14, against the recommendation and on the recommendation's own evidence:** 254 of 262 controls computed under 16px, so the app zoomed the viewport on every field focus. A 14px body floor would have left that standing everywhere a control did not happen to clear it. **16px on a control is behaviour, not typography.**

**The collision prediction held to within 5px.** It was measured beforehand as +734px and came in at **+729px**; the Typical row was predicted at 3.2 screens and landed at 3.2. Half a screen on a page that was already 4.3, which is why nothing had to shrink back to pay for it.

### The weight scale

**5 weights → 3: `400 / 600 / 700`.** Also a collapse — 400 and 700 already carried 677 of 708 elements; a stray 650 (one element) and 800 (seven) folded in. Mapped to jobs: **400** body and values, **600** labels and item names, **700** headings, active states and the number that matters.

This is load-bearing now in a way it was not before. With size compressed into 16–32, **weight carries the hierarchy size no longer can**, and colour cannot help because the palette is held to its own slice.

### `font-size: smaller` is gone, and the gate proves why it mattered

`small, sub, sup` now carry an explicit 16px. The defect pass measured the counterfactual precisely: **with the rule deleted, `<small>` computes at 13.3px** — the UA's `smaller` is ~0.83×, so even from a *16px* parent it lands below the floor. The original 7.9px came from the same multiplier applied to a 9.5px button.

**A relative size is not made safe by raising its parent.** That is the general form, and it is why the rule is *no relative font sizes* rather than *no small parents*.

### The route (Fork E3 + E1)

`Add a medication from its label` now sits at the sheet foot and opens the label reader with the kind **preset**. The manual dose form is renamed **`Log a dose I took`**, which is what it records.

Before, `Log → Manual → Log medication or supplement` led to the dose-event form while the label path was `Log → Photo → My label`. That is **worse than a step count: it is a plausible wrong destination**. Someone holding a pharmacy label lands in a different feature that looks right.

**Label path: 6 taps → 5.**

### Two conflicts the build exposed

**1. The fifth tab broke a prior ruling.** The first attempt put *Medication* in the sheet head. The sheet ruling says **four food modes plus secondary entries at the foot**, with ordering reflecting **data quality, not convenience** — and a fifth tab promotes a secondary entry on exactly the convenience argument that ruling subordinates.

It also measured badly on its own terms: **493px of buttons in a 283px bar**, with *Medication* at 394–505px — **entirely off-screen**, making the new route *less* reachable than the link it replaced. The foot entries are already always visible, so a foot entry gives **the same 5 taps with nothing broken**. The bar now **wraps rather than scrolls**, so no mode can hide off the edge again.

**2. The floor removed the size half of two distinctness gates.** `R19-demote` and `H4.1-distinct` both asserted *"smaller AND lighter"*. With 16px everywhere the conjunction is unsatisfiable — not because the controls stopped being demoted, but because **size is no longer a carrier anything can use**. Both re-pointed onto **weight, chrome and thumb path**.

That is `H4.1-distinct`'s **second** re-pointing: first from *shorter* (measured **taller** — the label wraps), now from *size*. Each time a carrier went, the claim survived unchanged: **a destructive control must not be mistakable for the affirmative one.** Size and height were always carriers of that property, never the property.

`SE-modes` was re-pointed too, for a different reason: it keyed on the **wording** *"medication or supplement"*, which E3 renamed deliberately. It now asserts the ruling's actual constraint — the entries are at the foot and **none is promoted to a food tab** — which is stronger than the string it replaced and survives the next rename.

### The defect pass: eleven plants, eleven named failures — after two vacuous ones

| plant | what it showed | repair |
|---|---|---|
| `small` set to `inherit` | **vacuous**: `inherit` from a 16px parent *is* 16px, so the plant was a safe change that tested nothing | the plant now **deletes** the rule, restoring the UA's `smaller` → 13.3px |
| a fourth weight on `.mkcal` | **vacuous**: `.mkcal` is not rendered by the shipped-page fixture, so the weight never reached the audit | re-pointed onto `.modebtn`, which always renders |

Both are [[D96]] again — **a plant must be able to reproduce the defect on the fixture that will judge it**, and neither of these could.

### The limits, recorded with the gates

- **A computed-size floor is not legibility.** It is the part of legibility that can be gated. Contrast, line length, spacing and rhythm are not measured here and no gate implies them.
- **[[D88]] still stands.** The floor gate proves no text is below a number; it cannot say the page reads well at arm's length. **If 16 reads badly on device, the fallback is 15**, and that is a phone judgement rather than a measurement.
  - **CONFIRMED ON DEVICE, 2026-09-22: 16 reads right; the 15px fallback is not needed and the question is closed.** Recorded here rather than only in the slice that asked it, because an open question answered somewhere else stays open where anyone would look for it.
- **The pre-registration's own objection survives the ruling.** *"With a 16px floor and a 24px heading there is little room left to say this matters less"* was **outweighed, not answered** — and the two re-pointed gates are the first bill for it. Whether three weights carry what four extra sizes used to is the open question this slice hands to the device pass.

**Held back deliberately:** the palette, and the density question. Fork F (the Typical row at 3.2 screens) is the one place density touches this slice, and it is **named and deferred** rather than resolved.

**Suite: 2039 assertions, all passing** (2027 → 2039).
## D101 — Total page height was the wrong proxy for an above-the-fold invariant (2026-09-20)

H9's collision measurement was careful, re-runnable, and **predicted the wrong thing correctly**.

### What was measured, and what it missed

The collision was simulated before the build by raising every computed size to a floor and measuring **page height** and the **scroll depth of each destination**. It predicted a 16px floor would cost **+734px** and move the Typical row from 2.7 to 3.2 screens.

**It was right: +729px measured, and 3.2 screens.**

Then the ring gate failed. On its seeded scene at 390×745 the **goal cells sat at 792px — 47px below the fold** — breaking a ruled invariant: *checklist, + Log, goal cells and legend above the fold*.

**The page grew exactly as predicted and the invariant broke anyway**, because the invariant is not about how long the page is. It is about **which elements fall inside the first 745 pixels**. Total height cannot distinguish a page that grew at the bottom from one that grew above the fold, and only the second breaks this rule.

### The rule

**A layout collision check must measure MEMBERSHIP of the constrained region, not the size of the page.**

This is [[D96]]'s shape from the measurement side. D96 says a *fixture* must be able to distinguish the thing a ruling chose between. This says a **measurement** must be able to distinguish the thing a ruling protects. In both, the instrument was sound and pointed at the wrong quantity — and in both, it produced a confident number that was true and irrelevant.

The general question to ask of any pre-build measurement: **what exactly does the rule constrain, and does this number change when that constraint is violated?** Page height does not change when the fold is breached; it changes when anything anywhere grows.

### The fixture detail that would have hidden it forever

The invariant fails **only when the regimen checklist has entries**. With an empty checklist the goal cells sit at 632px, comfortably above the fold, and every measurement reports success.

**A fixture without a regimen would have passed this forever** — and a regimen user is precisely who the checklist exists for. The ring gate caught it because its seed builds a *populated* scene: a regimen with two entries, a week of days, two goals. That seed was written for arc-band geometry, not for the fold, and it caught a fold defect years of empty-state checking would not have.

**Recorded as a property of fixtures rather than of this bug:** the state that stresses a layout invariant is a **populated** one, and the emptier the fixture the more invariants it silently satisfies.

### The repair, and why the scope boundary did not get to decide it

**Ruled: spacing only, and in scope for H9 rather than borrowed from the density slice.** *"Density is about how much is on the surface; this is the gaps between four elements that are all staying. Letting the scope boundary push us to shrink the ring, move a ruled layout, or weaken an invariant would be the boundary making a worse decision than the constraint would."*

Sixteen spacing rules tightened — margins, padding and flex gaps. **Nothing shrank, nothing moved, no type got smaller, the ring kept its 328px and every element kept its order.**

Several of the cuts were paying for type that no longer exists: `.rmini` carried `padding:2px 0 3px` sized around **9.5px** text and now carries 16px; `.navbtn` had 6px of vertical padding around 20px type. **A floor does not only add height — it makes the old spacing wrong**, because padding was chosen against the old type size.

**Measured margin after: the goal cells sit at 724px, 21px clear of the 745px fold** — up from 2px after the first pass, which was not headroom at all. Reported because *"48px with no headroom is a constraint that breaks again on the next element anyone adds"*, and 21px is one added row of controls, not one added pixel.
## D102 — A column can become unreadable without overflowing — v0.35.1 (2026-09-21)

Found on device, one day after H9 shipped: in Settings › Medications, a medication's directions were confined to a column about six characters wide and stacked into a tall run of fragments.

### What it was

`.medrow` is a `space-between` flex row — a text block, then buttons at `flex:0 0 auto`. Measured on the shipped page:

| | 360px | 390px |
|---|---|---|
| description width | **25px** (7% of viewport) | 55px (14%) |
| characters per line | **3** | 6 |
| lines in the row | **116** | 50 |
| worst sub-line | **10px — one character per line** | 33px |

The three buttons need **301px of a 268px row** at 16px type. Before the floor they were small enough to leave the text most of the row.

**The mechanism generalises past this row.** A flex child's default `min-width` is **`auto`**, which resolves to its **longest word**. It cannot shrink below that, so when its neighbours take the room it **starves rather than wraps**. `min-width: 0` is what permits wrapping at all. The diagnosis on the device was exactly right: *a row laid out as fixed columns at the old size now starves one of them.*

### Fixed as a class, not an instance

The same shape existed in three more `space-between` rows carrying text, each checked because the floor put the same pressure on all of them:

- **`.medfill`** — the fills list,
- **`.drughead`** — the drug panel header, where a long medication name meets a Close button,
- **`.plrow`** — the manufacturer list, where names like *Sun Pharmaceutical Industries, Inc.* would starve identically.

`.medrow` now wraps with the text block at `flex:1 1 100%; min-width:0`, so the description takes the whole row and the buttons sit beneath it. **After: 268px of a 268px row at 360px, 2 lines, ~35 characters per line**, and the same at 390.

### Why every layout gate passed

**Nothing overflowed.** The row stayed inside its box the entire time — it simply grew 116 lines tall while its text column shrank to three characters. The overflow check measured the page's horizontal extent and reported, correctly, that no element crossed the viewport edge.

**This is [[D101]] again, one day later, on a different quantity.** There, total page height could not see an above-the-fold invariant. Here, horizontal overflow could not see an unreadable column. In both the instrument was sound, re-runnable and pointed at the wrong number — and in both it returned a confident result that was true and irrelevant.

The question D101 asked of a measurement holds here unchanged: **what exactly does the rule constrain, and does this number change when that constraint is violated?** Overflow does not change when a column starves; it changes when something escapes its container, which is a different failure.

**The gate that now exists measures the thing itself:** the description's rendered width as a **share of its row**, at 360px and 390px, with characters-per-line as the readability check beside it — and a control that restores the narrow shape and watches the same measurement drop to **9%** and **18%**.

### And the pair that was renamed half-way

H9's Fork E3 renamed the *entry* to **"Log a dose I took"** and left the submit inside it saying **"Log medication"** — the same ambiguity E3 existed to remove, surviving one level below where it was fixed. Someone arriving correctly could still believe that button adds a medication to their list; it writes a timeline dose event.

Renamed to **"Log this dose"**, and **gated as a pair**: the entry and the submit must both say *dose*, and the submit must not claim to log a medication. A rename that fixes a route and not its destination is half a fix, and the pair gate is what stops the two drifting apart again.

### Recorded, not a defect: three surfaces for one outcome

There are **three** ways to add a medication — the label capture from the sheet foot, Settings › *"Type a label by hand"*, and Settings › *"Read label"* (paste). All three genuinely add a medication, so this is not the naming collision E3 fixed.

**But no gate asserts they agree.** Three entry points into one record shape, each with its own surface, and nothing checks that a medication saved through one is the same object as a medication saved through another. Recorded so it is a known shape rather than a discovery.
## D103 — The truncated salt, and the strength that was never stripped — v0.36.0 (2026-09-21)

Both found from one real pharmacy label, reported from the device:

```
BISOPROLOL FUMAR  2.5MG          (primary name)
Sandoz Bisoprolol 2.5 MG         (second name)
```

It carries four awkward things at once — a **truncated salt**, an **unspaced strength**, a **double space** before it, and a **second brand name** — so it is kept verbatim as the fixture rather than tidied into something a rule finds easy.

### 1. A spaced strength was never stripped

`QUERY_STRENGTH` wanted the number and unit in **one token**. `2.5 MG` is two: `2.5` is a bare number, which D98 protects because **PEG 400 and PEG 3350 are different substances**, and `MG` alone is not on the drop list. So the derivation was a **no-op on the conventional print form** — it defeated H8 for most labels and **failed invisibly**, producing a derived term identical to the printed one and no second query at all.

**Fixed as A1 across a token boundary:** a number and a unit come off **together**, and only when the unit is one of the already-ruled closed set. Under [[D96]] the fixture contains names the fix **alters** and names it must **not**:

| | |
|---|---|
| `Bisoprolol Fumar 2.5 MG` | → `Bisoprolol Fumar` **(altered)** |
| `POLYETHYLENE GLYCOL 400` | unchanged — a bare number is identity |
| `VITAMIN 12 COMPLEX` | unchanged — a number then a **non-unit** word |
| `SOMETHING MG` | unchanged — a lone unit with no number is not a strength |
| `metoprolol tartrate 25 mg` | → `metoprolol tartrate` — the **salt survives** |

That last row is the shape of the whole fix: **it widens what counts as a STRENGTH, never what counts as a NAME.**

### 2. The salt arrives truncated, and that is the common case

Pharmacy systems cut names to a fixed field width, so `Fumarate` prints as `Fumar`. Measured against 1000 distinct openFDA generic names:

| a label field of | truncates |
|---|---|
| 16 chars | **58%** |
| 20 chars | **43%** |
| 25 chars | **27%** |

**29.5% carry a salt word, and 129 of those exceed 25 characters** — they arrive with the salt cut in half. `DIPHENHYDRAMINE HYDROCHLORIDE` → `DIPHENHYDRAMINE HYDROCHLO`. This is not an edge case.

**No abbreviation table.** `Fumar → Fumarate` is right here and is exactly the kind of rule that is right until it is not. Instead, on a no-match the app fetches **one count request on the derived term's first token**, filters **locally** to the stored spellings that **begin with** what was printed, and offers them. The user picks; the chosen spelling is then queried **exactly**.

**The printed string is never touched.** The pick is stored beside it, so the record keeps `BISOPROLOL FUMAR  2.5MG` — double space and all — next to the `BISOPROLOL FUMARATE` that was chosen.

### Combination products get a heading, not a sort position

Measured for this exact case, `bisoprolol fumar` matches:

| spelling | labels |
|---|---|
| `BISOPROLOL FUMARATE` | 31 |
| `BISOPROLOL FUMARATE AND HYDROCHLOROTHIAZIDE` | **22** |

**Sorting orders; a heading marks.** At 31 against 22 the risk was never position — it is two rows reading as **variants of one thing**, which is precisely the plausible wrong choice [[D97]] recorded. Combinations sit under their own labelled section, after the singles, saying that they contain the drug **and another ingredient**. Never auto-selected, never first, never the easiest tap.

### The no-loosen gate had to be re-pointed, and the distinction is the whole remedy

`H5-no-loosen` asserted that **every** request carries the whole printed name. The candidate-list request deliberately sends one token, so by that gate's literal wording the ruled remedy *is* the thing D80 forbids.

Split into the distinction the remedy rests on:

- a request that can produce a **document** carries the whole printed name;
- the candidate list is a **count** — it returns no label text and **can answer nothing on its own**;
- **at most one** request ever drops words, and it is that one.

**If that distinction fails, the remedy is loosening under another name.** It is gated as three claims rather than one conjunction, because the conjunction made an honest build impossible.

### The defect pass, and the gate flaw it exposed

**Ten plants, ten failing their own named gates** — after two scored **VACUOUS** and **INCONCLUSIVE** for the same reason:

> **A source-string assertion says what the code LOOKS like, not what it DOES.**

`D103-prefix` asserted on `fdaPrefixURL` directly and `D103-printed` on `String(drugPickSpelling)`. A plant that made `drugOfferSpellings` send the **whole derived term** walked straight past the first; a plant that made `drugPickSpelling` **write to `printed`** walked past the second. Both gates named the right property and read the wrong object.

Replaced with cases that **drive the real functions through the fetch mock** and read the **outgoing URL** and the **stored record** — the same `FETCHES[0].url` shape that settled an earlier device report. Both plants now fail by name.

**One plant was withdrawn rather than repaired.** `a-bare-number-strips-too` aimed at D103's code for a property **D98 owns**: PEG 400 is protected by `QUERY_STRENGTH` requiring a unit, and the pair rule cannot strip a bare trailing number at all. **A plant that cannot express a defect is not a weak plant, it is the wrong plant** — and withdrawing it is the honest outcome, not a gap.

### Recorded on citations

The brief that opened this used an R-number. **R-numbers in briefs are the author's own relay labels, not identifiers in this repo**, and are not recorded as references. This slice is **H8/D98 → D103**.
## D104 — The pick list that never rendered, and a defect made of two faults — v0.36.1 (2026-09-21)

Reported from the device one release after D103: **every D103 gate passed and the pick list did not appear.**

### The record, kept as it came

```
Generic as printed:  SANDOZ BISOPROLOL 2.5 MG      <- the BRAND, in the generic field
Searching for:       BISOPROLOL fumar 2.5 mg       <- the user's own edit
Name as printed:     BISOPROLOL FUMAR 2.5MG        <- the GENERIC, in the name field
Searching for:       BISOPROLOL FUMAR              <- derived
```

The fields are swapped — a separate capture defect, **not repaired here** — and the fixture keeps them that way, because tidying the record would remove the condition that produced this.

### Two faults, and the question each answers

**Is the pick suppressed for a term marked "edited by you"? No.** There is no edit-awareness in that code at all. The prefix was taken **verbatim** from the last generic-field term, which was the edit — `BISOPROLOL fumar 2.5 mg`, strength and all. Nothing in the source begins with that. **The edit was not rejected; it was used underived**, while the app derives its own terms as a matter of course.

**Does it only fire on the generic index? Yes**, and that is the deeper one. `BISOPROLOL FUMAR` prefix-matches both stored spellings — but it sat on the **brand_name** side, because capture had put the generic in the name field. The one candidate that would have worked was never considered. **Which index a printed string lands in is an accident of capture, and it was silently deciding whether the user got offered a choice.**

**Fixed:** every tried term is **derived** before it is used as a prefix, and **every** tried term is a candidate regardless of field. A stored spelling is offered if it begins with **any** of them.

### The finding that matters more than the fix: the defect was a CONJUNCTION

The defect pass planted each fault separately, and **neither reproduced the failure**:

- with the prefix used verbatim, `BISOPROLOL FUMAR` is **still** a candidate, because `drugNameQueries` had already pushed the derived brand term;
- with only generic-field terms considered, the **derived** edit `BISOPROLOL fumar` still prefix-matches.

**Each fix is independently sufficient, so each fault alone is survivable.** Only both together empty the list — which is exactly the state that shipped.

**A defect pass that plants one fault at a time reports success while the shipped bug walks free.** The pass now carries a plant that restores **both**, and it fails `D104-surface` by name. The two single-fault plants are kept with the honest, weaker expectation — they reach `D104-candidates` and no further — rather than being written up as if they proved more.

This is a new shape beside [[D96]]. D96 says a fixture must distinguish what a ruling chose between. This says: **a plant must reproduce the defect that actually occurred, and when a defect required several conditions at once, so must the plant.** A one-fault-at-a-time pass silently assumes the faults are independent.

### And the gates were reading the wrong layer

Every D103 gate passed. They drove the real functions, read the **outgoing URL** and the **stored record**, and all of that was correct — the list simply never reached the DOM. D103 had itself been a repair for gates that read `String(fn)` instead of behaviour; **the repair moved one layer up and stopped one layer short.**

The new gates **render the surface** and assert `BISOPROLOL FUMARATE` is **on the page**. That is now the third layer this slice has had to be dragged through — source text, then function behaviour, then the DOM — and the rule worth keeping is that **the layer a gate reads must be the layer the user meets.**

### Two smaller repairs

- **The no-match headline named one term** — `printed.generic_name`, which on this label was the **brand**. It pointed at the wrong name while four terms had been tried. It now names **none**, and the searched list underneath carries the evidence.
- **A term the user typed was marked "(shortened)"**, because one flag meant both *app-derived* and *user-edited*. They are different facts, and the app did not shorten what the user wrote. Now: **"your edit"**.

### The fixture had a dead branch

The first candidate token's mocked response was a **404**, which takes the `!r.ok` path — so the `!best` branch, the one that tries a **second** token, was never exercised and a plant on it scored vacuous. The first token now **answers 200 with a non-matching term**, which is the case that branch exists for.

**Defect pass: eight plants, eight failing their own named gates.**

**Suite: 2086 assertions, all passing** (2074 → 2086).

### Still open, named and not touched

The capture put the **brand in the generic field and the generic in the name field**. That is a defect in the capture contract, not in the lookup, and patching it inside a lookup fix would bury it. It wants its own measurement.
## D105 — A wrong label stuck on a medication, and the three gaps that let it happen — v0.36.2 (2026-09-21)

Reported from the device: a plain bisoprolol record carried a saved document for **bisoprolol fumarate and hydrochlorothiazide** — the combination product. Two controls were involved and neither did its job.

### The question the report asked, answered from the record

> *"Does it store which candidate was picked and from which heading?"*

**No.** A pick put the chosen spelling into `query.generic_name` and nothing else — no note that it **was** a pick, and no note of which heading it came from. It was **indistinguishable from a term typed by hand.** The record already holds `identity_pick` for exactly this kind of choice (R30), so the asymmetry was the finding: one choice was recorded properly and the other was not.

**That is the third gap, and the report named it before the code was read.** A pick is now recorded as `query_pick: { term, from: 'combination' | 'single', at, of }`.

### 1. A combination label could be saved against a single-ingredient record, silently

**The guard belongs in the app, not in the user's attention.** *"After many taps on a phone, nobody knows which row they tapped."* A combination document is no longer saved against a record that prints one ingredient without a question that **names the extra ingredient** — *"It also covers HYDROCHLOROTHIAZIDE, which your medication does not print."*

**Ingredients are compared by FIRST WORD.** The label says `FUMARATE` where the bottle says `FUMAR`, so a whole-string comparison would have called **both** ingredients extra and questioned every save — the truncation [[D103]] exists for would have poisoned the guard built on top of it.

It is a **question, not a refusal**: a combination can be the right label, and accepting still saves.

### 2. "Remove this document" did the work and said nothing

**The hypothesis in the report was that H5's unattached-only rule refused it silently. That is not what happened.** `detachLabelDoc` returned `{ok: true}`, cleared `labelSetId`, and dropped the document from the store. **The work was always done.**

But `DRUG_VIEW` still held the old document, and `refresh()` does not touch the drug panel — only `drugSet` does — so the panel re-rendered the same thing, including the same button.

**A successful action that leaves the surface identical reads exactly like a dead control**, and it is worse than a refusal: the user may tap it repeatedly against an already-detached record, each tap now genuinely returning `{ok:false}` in silence. Both halves are fixed — the panel clears and says so, **and** a real refusal says so too.

**The general form:** a control's verdict lives on the surface, not in the return value. `{ok:true}` with an unchanged panel is indistinguishable from `{ok:false}` with an unchanged panel, and the user can only see the panel.

### 3. The pick recorded nothing — see above

### No schema bump, and the reason stated rather than assumed

`query_pick` is **additive provenance**. On D29's asymmetry test as [[D96]]'s sibling R31 stated it: an older app strips it and **nothing behaves differently** — the term still goes out, the lookup still works. What is lost is the record of **how** the term was chosen, which is *less information*, not a *wrong value*. R31 drew that line explicitly, and a bump is for the other side of it.

It joins `normalizeMed` in the **same edit that introduces it** — the allowlist trap, tenth occurrence — with export → restore gated.

### The defect pass, and two vacuous gates it caught

**Nine plants, nine failing their own named gates** — after two scored **VACUOUS**, both gate faults:

| plant | what it showed | repair |
|---|---|---|
| the question does not name the ingredient | the check read `indexOf('HYDROCHLOROTHIAZIDE')`, which the **document's own name already satisfies** — so it could not tell whether the extra was **named** or merely **echoed** | it **counts occurrences**: once inside the doc name, once more as the thing the label adds |
| every save is questioned | the narrowness check used a single-ingredient label that **matches the bottle**, which has no extras with or without the combination test | it now uses a label for a **different drug**, where removing the test does fire a question |

The second is [[D96]] again: **a fixture that cannot distinguish the presence of a rule from its absence cannot test the rule.**

### An adjacent case the ruling did not cover, named not built

A single-ingredient label for a **wholly different drug** — amlodipine saved against a bisoprolol record — raises **no question**, because the ruling was about combination products. That is gated as the current behaviour rather than left ambiguous. **Whether a wrong drug should also be questioned is a separate ruling**, and it is the same shape as this one: the app can see the mismatch, and today it says nothing.

**Suite: 2103 assertions, all passing** (2086 → 2103).
## D106 — A wholly different drug is the worse mismatch, not a lesser one — v0.36.3 (2026-09-21)

[[D105]] guarded **combination** labels and left a label for an entirely different drug — amlodipine saved against a bisoprolol record — going through in silence. D105 named combinations **because that was the case in front of it**, not because the class stopped there.

> *"A wholly different drug is a worse mismatch than a combination, not a lesser one."*

A combination at least contains the right drug. This does not.

### What it took

Nothing new. **The first-word comparison built for D105's truncated salts already saw it** — the label says `FUMARATE` where the bottle says `FUMAR`, so heads were already what got compared. D105 simply never asked the question for a non-combination.

Every mismatch the app **can see** is now in one place: a combination carrying an ingredient the bottle does not print, and a label sharing **no** ingredient at all. Both ask the same shape of question; neither refuses.

**The wording states two facts and no verdict:**

> This label is for **AMLODIPINE BESYLATE**.
> Your medication prints **"BISOPROLOL FUMAR 2.5MG"**.
> Save it against this medication anyway?

Gated to contain neither *wrong* nor *mistake*. **"This is the wrong drug" is a verdict; those two lines are facts the reader can check against the bottle in their hand** — and accepting still saves, because the user may have a reason the app cannot see.

**The narrowness is gated with the fixture the ruling asked for:** a label sharing the bottle's first word — `BISOPROLOL FUMARATE` against `BISOPROLOL FUMAR` — raises **no** question. That is the truncation D103 exists for, not a mismatch. Without that fixture the guard could have been "question everything" and passed.

### A D105 gate was superseded rather than left standing

D105 gated that a different-drug label raises **no** question. That was true of D105 and is now wrong, so it was **replaced**, not added beside. A gate still asserting the old behaviour is [[D92]]'s shape — **a test defending a ruling that has been overtaken** — and it would have turned red on the fix and argued for reverting it.

### Three faults in the pass, all mine

| | what happened | what it says |
|---|---|---|
| **the block ate the next fixture** | it ran while D105's combination document was still attached, and its cleanup detached it, breaking the detach case that follows | *"declining saves nothing"* had to mean **the attachment is unchanged**, not absent — asserting absence would have asserted the **previous case's cleanup**, not this case's behaviour. The block now hands the fixture back as it found it. |
| **an unguarded dereference** | the plant that stops the mismatch being detected leaves it null, and calling the wording function on null made the suite report *"something threw"* | **Clause 5**: guarded, and the case fails as itself |
| **a plant anchor that could not match** | the anchor was retyped with `\n\n` and nested quotes, and mangled twice | the anchor is now **taken verbatim from `app.js`** rather than retyped — the same escaping trap this repo has hit repeatedly, and the only reliable answer is to copy the bytes rather than reproduce them |

**Defect pass: five plants, five failing their own named gates.**

**Suite: 2108 assertions, all passing** (2103 → 2108).

### The standing rule this pair leaves behind

From [[D105]], recorded as its own line because it generalises past that control:

> **`{ok: true}` with an unchanged panel and `{ok: false}` with an unchanged panel are identical to the person holding the phone.** The verdict lives on the surface.

A return value is a fact about the code. **What the user can act on is what changed on screen** — and a function that succeeds without saying so has failed at the only layer that counts.
## D107 — Detach removed the document and left the choice that produced it — v0.36.4 (2026-09-21)

Reported from the device: after detaching the wrong combination label, **Drug info stopped offering the spelling pick** and went straight to *"12 manufacturers file a label for BISOPROLOL FUMARATE AND HYDROCHLOROTHIAZIDE"*.

**The diagnosis in the report was exactly right**, and reproduced on the shipped page:

```
after DETACH:
  labelSetId         = undefined
  labels store       = []
  query.generic_name = "BISOPROLOL FUMARATE AND HYDROCHLOROTHIAZIDE"   <= SURVIVES
  query_pick         = {... from: "combination" ...}                   <= SURVIVES
```

The next lookup queried the combination term **exactly**, matched, and produced a manufacturer list — **reusing the result the user had just rejected**, with nothing said.

### Three fixes, in the order the report gave them

**1. Detaching clears the pick.** A hand-typed term is left alone: the user wrote that one, and only the pick belonged to the document.

**2. A combination pick against a single-ingredient record is never reused silently**, however it got there. This matters more than it looks: **the save guard fires on SAVE, and a reused term reaches the manufacturer list before that** — so reuse did not weaken [[D105]]'s guard, it **skipped** it. The lookup goes back to the spelling list, with candidates built from what the **label prints** rather than from the choice being questioned.

**3. A stored pick is legible before a manufacturer list settles it.** The query row now renders **above** the list — it previously appeared only in the idle and no-match phases, so a pick became invisible at exactly the moment the surface starts to look decided. And it says **"picked by you from the suggestions — change it here if it is wrong"**, because calling a pick *"edited by you"* was the D105 wording fault surviving in a second place.

### What the defect pass found: two fixes, one scenario, and three vacuous plants

**Fix 1 and fix 2 prevent the same outcome.** The end-to-end case — pick, save, detach, look up again — only ever exercised the **first**, because once detach clears the pick, `drugPickNeedsReview` can never fire. Three plants on fix 2 scored **VACUOUS**: not because the fix was wrong, but because **nothing in the suite reached it**.

**This is [[D104]]'s conjunction finding inverted.** There, two *faults* were each necessary, and no single-fault plant reproduced the defect. Here, two *fixes* are each **sufficient**, and the first to run hides whether the second works at all. Both come from one blind spot: **assuming that a scenario exercises everything its outcome depends on.**

The repair is a second scenario for the case fix 2 actually exists for — **a combination pick that survives**: a record from before this change, or one whose document was never attached. There the lookup must return to the list rather than query the stored term.

**And one plant stayed survivable after that.** Dropping the `ignoreStored` flag leaves the outcome intact, because a *different* candidate — the name field's derived term — still matches. So the gate was re-pointed off the outcome and onto **the candidate list itself**: the term under review must not be among the candidates. *Offering a list built from the choice being questioned would be asking about it with itself.*

**Defect pass: six plants, six failing their own named gates.**

**Suite: 2124 assertions, all passing** (2108 → 2124).

### Confirmed from the device, 2026-09-22

Clearing the field and typing `BISOPROLOL FUMARATE` by hand **returns 24 manufacturers for the plain generic**. *"The stuck pick was the only thing routing me to the combination."*

**Both device-reported numbers reproduce exactly against the live API** (checked 2026-09-22):

| query | manufacturers |
|---|---|
| `openfda.generic_name.exact:"BISOPROLOL FUMARATE"` | **24** — the workaround's result |
| `openfda.generic_name.exact:"BISOPROLOL FUMARATE AND HYDROCHLOROTHIAZIDE"` | **12** — the stuck pick's result |

And the list the re-offer is built from: the prefix probe sends the **first token only**, `openfda.generic_name:"BISOPROLOL"`, which returns exactly two stored spellings — **BISOPROLOL FUMARATE (31 labels)** and **BISOPROLOL FUMARATE AND HYDROCHLOROTHIAZIDE (22)** — so the two candidates the pick list needs are both there, split by [[D103]]'s combination heading.

**What this confirms, stated narrowly: the DIAGNOSIS, not the fix.** The stored pick was the sole cause, and removing it by any route resolves it — which is what the record claimed and is now measured from the device end as well. **The automatic routes are still unconfirmed on device**: detach clearing the pick, and a surviving combination pick sending the lookup back to the spelling list. Those are gated and green, and gated-and-green is not the same as seen.

**One false alarm worth keeping, because it nearly became a defect report.** Probing the API by hand with the *whole* derived phrase — `openfda.generic_name:"BISOPROLOL FUMAR"` — returns `NOT_FOUND`, which looks exactly like a broken remedy. The app never sends that: `drugOfferSpellings` queries the **first token**. *A measurement of a shape the code does not use is not evidence about the code* — the same error as reading the wrong layer ([[D103]]), made with live data instead of a source string, which is precisely what makes it convincing.

### A note on the pick that is not deleted

Fix 2 **does not delete** the surviving pick — it declines to act on it. It is still what the user chose, still shown on the surface, and still theirs to change. **Silently deleting a choice to avoid re-asking about it would be the same fault in the other direction**: the app deciding, without saying so, what the user meant.

## D108 — Which silence was it? — v0.37.0 (2026-09-22)

Two meal captures in a row aborted at **120.0s with no first byte**, `600 kB · call 1 · json_object sent · effort low`. The request shape was unchanged, so the app was sending what it sent when the same call returned a first byte at 10.7s.

**The cause was measured, not argued.** An xAI datacenter incident on `us-east-1.api.x.ai` opened **01:02:42 UTC** on 22 September and fully resolved at **01:28:30 GMT** — **21:02 → 21:28 local**, the window the captures fell in. Five minutes after resolution, an unauthenticated probe from this machine answered in **223 ms**. Against the current docs: `grok-4.6` is live, **not** in the May-15 retirement list, still documented as *"text and image inputs"*, and `reasoning_effort` is unchanged at `low | medium | high (default) | xhigh`.

**No provider-config change was made, and that is the point.** Nothing in the config was wrong. Changing the model would have credited a fix to a change that did not make one — the provider was down, and is up. `grok-4.7` (launched the same day, same context, same modalities, same effort ladder) is parked until there is evidence to want it.

**What the slice fixes is the app's own blindness.** *"The provider isn't answering"* and *"this request didn't come back"* render identically on the phone: a 120-second abort. It was the **second** time that distinction cost a diagnosis. So on an abort with no first byte the app now runs **one unauthenticated GET** — `{provider.base}/models`, no key, no body, no photo — and says which silence it was.

### The ruling that made it honest

`navigator.onLine` is trustworthy **only when it reports FALSE**. `true` means the device has an interface, not that it reaches the internet — a dead cell signal, a captive portal and one bar in a tunnel all report online. So a failed probe with `onLine` true is **not evidence that the connection works**, and the app must not name the provider alone on it:

| condition | what the app says |
|---|---|
| probe answered | *"The provider's API is reachable — this request didn't come back."* |
| probe failed, `onLine` **false** | *"Your device is offline."* |
| probe failed, `onLine` **true** *or unknown* | *"Couldn't reach the provider. It may be down, or your connection may not be getting through."* |

The third is less satisfying and more true. **It is the same discipline as the positive verdict**: a 401 from the edge proves the API is *reachable*, not that inference is alive, so the wording says reachable and never *"up"*. Both cases are one rule — **the sentence may not outrun the measurement.**

### What the build found

**1. A gate that pinned the harness's own number.** `byokTimeouts().probe === 8000` read the **live** value, which the harness had already shrunk to 20 ms for speed. It would have passed on whatever it was set to. Repaired by reading through the reset seam (`setByokProbeTimeout(0)` → the shipped default). Generally: **a gate that reads a mutable value pins nothing if the fixture is allowed to set it first** — the assertion looks specific and measures the fixture.

**2. The probe was keyed on the failure KIND, not on the first byte.** The first condition read `!timedOut || !att || att.ttfbMs == null`, so a **mid-body drop** — headers arrived, body never did — would have been probed, spending a request to repeat what was already known. The rule is about *silence*, and a first byte means there was no silence. `!att || att.ttfbMs == null` is both simpler and the actual rule. Found by building the fixture, not by reasoning about it.

**3. A hazard found while building that fixture, named and NOT fixed.** `byokCall` **clears its budget timer the moment headers arrive**, so a response that sends headers and then stalls forever is never aborted — worse than the 120-second timeout it escapes. The first attempt at the no-probe fixture hung the whole suite on exactly this. The cancel button keeps nobody trapped ([[D60]] R21.3-alive), which is why this is a hazard rather than an outage. **Out of this slice, and written down so it is not re-discovered by accident.**

**4. Half the service-worker margin is gone.** The capture call passes the SW untouched because it is **non-GET and cross-origin** (D45 Fork G). The probe is a **GET**, so it rests on the cross-origin return **alone**. Gated, because **a probe served from a cache is a memory, not a measurement.**

**5. An empty message.** Dropping the network lead sentence left a no-probe network failure surfacing `''` — a failure with no words. Caught by the fixture and gated by name.

### The defect pass

Eight plants. **Three of them sit on the failed-probe side of the verdict** — the offline and not-reachable branches both arise from one failed probe, which is precisely [[D107]]'s trap: sibling branches where a plant on one may never reach the other. They stayed distinguishable, and the reason is worth keeping: **the wording is gated through the pure seam with explicit arguments, not only end to end.** An end-to-end fixture can only reach the branch its scenario happens to take; a seam can be asked about every branch directly. *Gating the seam is what stops sibling branches from hiding each other.*

**Defect pass: eight plants, eight failing their own named gates.** Two returned *no verdict* on the first run and both failed by name on re-run — the characterised output-capture intermittent, and exactly the reason [[D94]] rules that a no-verdict pass is re-run **before the plant is blamed**.

**Suite: 2152 assertions, all passing** (2124 → 2152).

## D109 — A gate that reads a value the fixture may set first measures the fixture — 2026-09-22

Found building [[D108]]. The gate read:

```js
res(HT.byokTimeouts().probe === 8000, 'the SHIPPED probe budget is 8s ...');
```

It names the right number. It reads the **live** variable — and the harness had already called `setByokProbeTimeout(20)` forty lines earlier, because every never-answering stub in the suite now also swallows the probe. So the assertion compared the harness's own copy of the value against the number it hoped to find, and **would have passed on whatever it was set to** had the shrink happened to be 8000.

**The general shape.** A gate that reads mutable state pins nothing if the fixture is allowed to write that state first. It is worse than no gate, because it **looks** specific: a named constant, an exact number, a sentence explaining why the number is that number. Everything about it reads like a pin except the thing it measures.

**It is [[D103]]'s fault with the layers swapped.** There, `String(drugPickSpelling)` asserted the *source* while the function wrote somewhere else — the gate read a layer that could not see the behaviour. Here the gate reads the right layer at the wrong *time*. Both are the same question unasked: **between this assertion and the thing it claims about, who else can write?**

**The repair is a seam, not a discipline.** "Remember to restore the value first" is a rule, and rules are what failed. `setByokProbeTimeout(0)` resets to the shipped default by contract, so the gate asks the code for its own number instead of trusting whatever is currently in the box:

```js
HT.setByokProbeTimeout(0);            // the reset seam yields the SHIPPED default
res(HT.byokTimeouts().probe === 8000, '...');
HT.setByokProbeTimeout(20);           // back to the harness's value
```

**Where else this applies:** every `set*Timeout` seam the harness shrinks for speed — the call budget, the test budget, the decode timeout, the bitmap lease — and any future setting a fixture adjusts. A gate on a shipped default reads it through the reset, or reads the source, and never reads the live variable.

**Caught by luck, not by process.** The gate failed on its first run only because the shrink ran before it. Had the harness set the probe budget *after* this block, it would have passed for the wrong reason and been recorded as evidence.

## D110 — The budget must survive the first byte — v0.37.1 (2026-09-22)

The hazard [[D108]] named and deliberately did not fix: `byokCall` cleared its deadline **the moment headers arrived** and then read the body unguarded. A response that sends headers and then stalls had **no ceiling at all** — worse than the 120-second timeout it escaped, because the promise the app makes simply stopped existing.

### Fixed as a class

Measured before building: three `AbortController` fetch sites, and **two had it**.

| site | before |
|---|---|
| `byokCall` | `clearTimeout(timer)` on headers, then unguarded `res.text()` |
| `drugFetch` | **identical** — a stalled openFDA body hung a lookup exactly as a stalled capture body hung a capture |
| `byokProbe` | resolves *on* headers and reads no body — the control, correct as-is |

The deadline is re-armed for **what is left of the same budget** (B1a: no body floor, so the 120-second ceiling holds), and the verdict says **when the first byte arrived** — *"The provider started answering at 119s and stopped; gave up at 120s. That call counted."* With a one-second body window the bare sentence would read as though the provider had had time.

`kind` stays `'timeout'` (C1): a new kind would have silently dropped out of the drug path's `kind === 'offline' || kind === 'timeout'` grouping at two call sites — a behaviour change there as a side effect of a fix here. A stall gets **no probe** (D1): it *has* a first byte, so [[D108]]'s single rule still covers both cases.

**G is instrumented, not reviewed.** `TIMER_DEBT` counts every re-armed deadline and every stand-down, and a gate reads zero after the stall, the success and the reject paths. *"Remember to clear the timer" is a rule, and rules are what failed the last three times.*

### What the build found

**1. The safety net was necessary, exactly as ruled.** Without it the first plant — removing the re-arm — **hangs**, and a hang is a no-verdict. With it, that plant fails by name, including *"the abort came from the app's deadline, not the fixture's safety net."*

**2. A DETERMINISTIC HANG READ AS THE INTERMITTENT, AND THE EVIDENCE AGAINST THAT WAS ALREADY ON SCREEN.** Two runs ended with no SUMMARY. Both were called the characterised output-capture flake and re-run; the third passed, which appeared to confirm it. **Both failures had stopped at the identical assertion and the identical count — 2024.** The intermittent loses the *tail* under load, at no fixed point. Two runs stopping at the same number is not a flake, and the discriminator was in the output from the first re-run onward.

> **The rule this adds to [[D94]]:** a no-verdict is not evidence *of* the intermittent. Re-running is right, and it is not enough — **compare where the runs stopped.** Two identical stopping points are evidence *against* the flake, and the only thing that tells a stall from a load artefact.

**3. The harness had the very defect this slice was fixing.** `wExifImage` awaited `c.toBlob` with **no deadline and no null check**. A 2400×1800 canvas on a machine that had been short of memory all session hands back nothing, and the suite dies silently. Repaired with the same shape ruled for the fixture — a net that makes a stall **say so** — plus a **chain-level net**, so any future hang anywhere in the harness reports itself by name instead of producing a missing SUMMARY that reads like the flake. *E1's reasoning holds wherever a hang can happen, not only where it was asked for.*

**4. A retry that covered the failure I could picture.** The first repair handled a **null blob**. The actual failure was `toBlob` **never calling back at all**, which the null check cannot see. It cost three more runs. **When a flake has two failure modes, fixing the one that is easier to imagine leaves the other exactly where it was** — and the fixture then fails in the same silent way it did before, while looking repaired.

**5. A fresh-budget defect is invisible to timing assertions at harness scale.** 80ms twice is still fast, so no threshold loose enough to avoid flaking could catch it. The arithmetic came out as a pure seam, `bodyDeadlineMs`, gated on the numbers that matter: 119s of a 120s budget leaves **1000**, a spent budget leaves **0**, and a control at 0s leaves the full **120000** so the rule is not merely returning something small.

**6. One plant was malformed JS** and aborted the suite — a bad plant, not a weak gate. Rewritten to drop **only** the clock, it then failed exactly one gate (*states WHEN the first byte arrived*) while the *started answering and stopped* gate still passed: the isolation the plant existed to prove.

**Defect pass: eight plants, eight failing their own named gates.**

**Suite: 2174 assertions, all passing** (2152 → 2174).

## D111 — A label asserted a fact the app never recorded, and the fact was about the user — v0.37.2 (2026-09-22)

Reported from the device. The generic field read **"Searching for: BISOPROLOL FUMARATE AND HYDR…"** labelled **"edited by you"** — after the combination document had been detached — and the next lookup went straight to that combination's 12 manufacturers.

### What the record actually held

Neither of the two explanations offered. There was **no provenance flag at all**:

```js
const picked = !!(med.query_pick && med.query_pick.term === term);
const edited = !picked && !!(med.query && med.query[f]);        // an INFERENCE
```

**"edited by you" was what the panel said when it saw an override and no pick record.** The term had been *picked*, on a build where `query_pick` did not yet exist — the pick list began rendering in [[D104]] (v0.36.1) and provenance arrived in [[D105]] (v0.36.2), both the same day. Nothing dropped it; it was never written. (`query_pick` **is** in the normalizer, added in D105's own commit, and `drugSave` never touches it — both checked before concluding.)

**This is the confidence dot ([[D93]]) and the goal colours ([[D91]]) again — the surface making a claim the data cannot support — except that this claim was about the person.** The app told the user they had typed something they had chosen from a list it offered them.

### And it made D107 structurally blind

[[D107]]'s clear is keyed on the pick **record**:

```js
if (med.query_pick) { ... }
```

So it could never reach **exactly the records that need it most**: every term chosen before provenance existed. The device's record is one. That is D107's own failure mode surviving inside D107's fix, and every fixture written for it had a `query_pick` in it.

### The repair

**Provenance is stored**, per field: `query_src` ∈ `typed | pick`, written by `setMedQuery` (default `typed`, because the only non-human caller is the pick and it now says so). Additive, **in the normalizer in the same edit**, no schema bump by D105's reasoning — an older app strips it and the term still goes out; what is lost is a claim about provenance, which then correctly reads as *not recorded*.

**Three states on the surface, and the third is the point.** Picked, edited, or — where nothing was recorded — **"search term (source not recorded)"**. The rule cuts both ways: the panel may not claim an edit, and may not claim a pick either.

**Detach keys on the DOCUMENT, not the pick record.** A term matching the generic name of the document being rejected is cleared when provenance is `pick` **or unknown**; a term recorded as `typed` survives, so D107's principle is intact. Clearing an unknown costs one retype and is visible; keeping it routed the user silently back to the label they had just thrown away.

### What the build found

**1. A plant scored VACUOUS because the scenario set the thing it was testing.** The sequence gate calls `setMedQuery(..., 'pick')` itself, so removing `'pick'` from `drugPickSpelling` changed nothing any gate saw. It proved the seam and proved **nothing about the call site**. Repaired by asserting provenance after a real `drugPickSpelling`. *A fixture that hands the code the value under test measures the fixture* — [[D109]] again, one layer along: there the fixture set a mutable value first, here it supplies an argument the production path is supposed to supply.

**2. The harness net shipped in [[D110]] could never fire.** It was set at 420000 ms against the 600 s gate leash, while `run-data-layer.sh` runs Chrome with `--virtual-time-budget=20000`: the DOM is dumped and the process exits at the budget, so the guarantee was **dead code that read like protection**. Set to 15000 it then fired on a **healthy** run that merely took a while, truncating the count and inventing a failure — proved by the output: **2197 assertions printed while the counter reported 2045**. A net must sit **above the slowest healthy run and below the hard deadline**; both numbers had been chosen against one bound and never measured against the other. Budget raised to 45000, net at 35000.

**3. The fixture stall was not a flake to retry but a failure mode to remove.** `c.toBlob` on the 2400×1800 canvas never called back in roughly half of all runs — not a null blob, which a retry absorbs, but a callback that never arrives. `toDataURL` is synchronous: there is no callback to miss. Three consecutive clean runs after. **The decode timeout behind the shortened bitmap lease was still 20000 — the entire virtual-time budget — in both windows**, so whenever the preferred decoder failed the fallback's own deadline consumed the run. Shortening the leash alone had only moved the wait.

**Defect pass: eight plants, eight failing their own named gates.**

**Suite: 2197 assertions, all passing** (2174 → 2197).

## D112 — A clock stamp is honest only when the record lands on today — v0.38.0 (2026-09-22)

First slice of H12, ruled to ship **alone and first**: the day record about to be built sorts by time, so a fabricated time had to stop being written before anything relied on it.

**AMENDED BY [[D113]]:** this decision forbids a **fabricated** time — one taken from something unrelated and stored as fact. It does **not** forbid an **inferred** one: derived from the person's own record, marked as inferred, and written only after they were asked and did not answer. The flag is what makes those different objects rather than the same object with a nicer name.

**Back-filling last Tuesday's lunch stamped it with tonight's clock.** Every path that writes to the **viewed** day called `nowTime()` unconditionally, and the day nav lets that day be any date. The time was not merely wrong, it was **invented** — [[D19]]'s fabrication, indelible in a way a blank is not. It stayed harmless only because nothing sorted by it.

### The census, which is the finding

Three sites were surfaced by inspection; **the census found eight**, and measuring what each one *reaches* reduced that to **seven that matter**.

| site | lands on | was |
|---|---|---|
| `addManualEntry` | `curDay()` | `nowTime()` |
| `logPreset` | `curDay()` | `nowTime()` |
| `logScanItem` | `curDay()` | `nowTime()` |
| `consumeFromPlate` | `o.date \|\| APP_STATE.current` | `nowTime()` |
| `plateFromDraft` | its `dateKey` | `nowTime()` |
| `maybeInjectSupplement` (via ingest) | any date | `nowTime()` |
| `addLabPanel` | the panel date | the constant `'09:00'` |
| `photoSave`'s record builder | **nothing** | `nowTime()` — see below |

**One helper, not eight patches** — `stampTime(dayKey)`, per [[D50]]'s lesson. The next write path inherits the rule instead of deciding it again.

**The honest half, gated so the census does not read as all-broken.** The `addSignal` family files under `localDate()` and therefore only ever writes to **today**; a past day can be on screen and a logged biometric still lands on today. And measured while writing that gate: **`addSignal` stamps no clock of its own** — the `nowTime()` fallback lives in the *form handlers*. That is precisely why the family was never a fabrication: **the clock and the day come from the same instant.**

### Three things the build found

**1. The right helper reading the wrong day.** `consumeFromPlate` takes an explicit `opts.date`, and the first build stamped from `APP_STATE.current`. It would have fabricated again **one argument along** — the fix applied, the defect intact. The rule is not "call the helper" but **"pass the day the record lands on"**, and it now has its own gate: eating onto a past day while today is the day on screen.

**2. A gate that tested the refusal instead of the lift.** The blank-time gate reached for *the last item on the day*, which by then already had a blank time — and blanking an already-blank record is a **no-op**, which [[D55]]'s edit contract correctly refuses. The assertion failed for a reason that had nothing to do with the thing under test. It now edits the record the **user gave a time to**.

**3. A plant that could never fail, twice — because the code it planted on is unreachable.** `photoSave` builds a full item record and the array is discarded: `photoSave` writes the day through `plateFromDraft` + `consumeFromPlate`, and the builder is vestigial from before [[D69]]. **The code says so itself** at `app.js:7968` — *"R33: `written` above is no longer what reaches the day."*

> **The general form, and it is [[D75]] one layer along.** A check nothing runs is not a gate; **code nothing reads is not a behaviour**, and a plant on it is guaranteed vacuous. A census of *call sites* is not a census of *effects* — the eight had to be walked to their landing places before the number meant anything. The dead builder is named here and **left in place**: deleting forty lines is its own change, not a rider on this one.

**Nothing in the suite pinned the old behaviour in either direction.** After the build, all 2197 existing assertions still passed — the fabrication was untested, not merely wrong.

**Defect pass: eleven plants, eleven failing their own named gates**, plus the twelfth site recorded as unreachable rather than gated.

**Suite: 2225 assertions, all passing** (2197 → 2225).

### What this changes for the person

A record logged onto a day that is not today carries **no time**, which is what was actually known. A time the user **types** is kept, on any day — the rule removes invention, never their own answer. An untimed item can now be **edited without inventing one**; a malformed time is still refused. And an untimed item **cannot anchor a fast boundary** — `fastEvents` already requires `HH:MM`, so a back-filled meal is excluded rather than placed at a time it did not happen.

## D113 — A forgotten night closes on the sleeper's own pattern — v0.39.0 (2026-09-22)

**Amends [[D38]]** (*"never auto-closed"*) and **[[D112]]** (*"an invented time must not be written"*), shipped one commit earlier. Neither reads as absolute now, and the line between them is the whole of this decision:

> A **fabricated** time is made up from something unrelated — the current clock, a constant — and stored as fact. An **inferred** time is derived from the person's **own record**, **marked** as inferred, and written only after they were asked and did not answer. [[D19]] forbids the first. This permits the second, **and the flag is what makes them different objects rather than the same object with a nicer name.**

### What ships

The forgotten-off question **leaves the ring centre for its own dialog** (completing H12's Fork F2, so the summoned centre is now exactly one thing — a toggle), and it **prefills the sleeper's typical wake time**: the **median** wake over observed nights in the last 28 days, with a floor of **eight**. Past **24 hours** — not the 11-hour question, a full day later — the segment closes at that time, marked **inferred**, and reads *"Sleep (woke ~06:30, inferred)"*.

**No timer.** [[D38]] Fork F rules the open counter deliberately stale, so the close happens on the next render and on nothing else. Contradicting that to buy a convenience would be reversing a ruling for comfort.

**Dormant below the floor.** With fewer than eight observed nights there is no prefill **and no auto-close** — the segment stays open exactly as D38 has it. *"From my own history, not a default"* requires it, and a default would be the fabrication this avoids.

**Sleep only.** Sauna, meditation and red light have a typical **duration**, not a typical **end**; D42's thresholds still ask and still never close.

### THE SUB-RULE, ON ITS OWN: an inferred night never feeds the pattern

Gated by name, because burying it in the median would be burying the thing that keeps the median honest. An app that learned from its own guesses would **drift toward them**, and the drift would present as **rising confidence**: more nights, tighter cluster, a more and more certain estimate of a number it had largely made up. The refusal lives in `observedWakeMins`, one line, so nothing downstream has to remember it.

### Three values, one field — [[D111]] applied before the fact

`wake_src` is `typed | accepted | inferred`. **Accepting a prefill is not the same evidence as typing one**: it is anchored by the app's own estimate, and folding it into *observed* would put the guess back through the door the flag exists to close. Three values cost no more than two, and a later analysis picks its own bar.

**The stated purpose, recorded so a future correlation carries its own caveat:** correlating glucose against sleep timing is meaningful on **observed** nights. Without the flag, such a correlation would partly be measuring the app's assumption against the CGM — and would look exactly like a finding.

**Three stored, two shown** ([[G1]]): typed and accepted read identically on the surface, because both are the person's answer; only an inferred night wears the tilde. Storing more than is shown is the safe direction. A night with **no** recorded provenance — anything from before this slice — claims none, per D111.

### Four invariants re-pointed, carrying their history ([[D92]])

D38 and D42's gates said the question lives in the centre and that a segment is *never* auto-closed. Both are amended rather than deleted, and the re-points say so. **The byte-identity invariant found a real gap while being re-pointed:** a sleep record typed into the form carried no provenance while a toggle-off did, so the two paths would have differed **by bookkeeping rather than by substance**. The form now records `typed`, and identity holds across all four lanes — with the one lane that gained a field gaining it on both sides. A record arriving any other way still carries **no** flag, because its provenance is genuinely unknown.

### What the defect pass found

**Two plants scored VACUOUS, and both were fixture faults of one kind: an assertion that *searched* for a record by shape found one the case had not created.** The typed-provenance gate matched one of the eight **seeded** nights, so it passed without ever looking at what `askResolve` wrote. The repair is general — **use the handle the call hands back**, not a search over the store. This is the third instance in one session, after the photo row and the already-blank record.

**And one plant was not a defect at all.** The lane-generic auto-close changed which lane `st` described while the close still named `'sleep'` explicitly, so an open sauna was never closed by it. **A plant that does not produce the defect cannot fail a gate**, and that is a bad plant rather than a weak gate. Its fixture also had to be strengthened to make the wrong behaviour *possible* ([[D96]]): without eight seeded nights a lane-generic close would decline for want of a pattern, and the gate would have passed on a genuine defect.

**A tooling finding:** the defect-pass runner decoded the harness with the system codepage and died on a curly quote in a gate message — ASCII-lucky until this slice wrote one. It reads UTF-8 explicitly now.

**And a fixture's clock is shared state.** This block advances the pinned clock by tens of hours; leaving it advanced made **H7's trail assertions fail three sections later**, nowhere near the cause. Every block that moves it puts it back.

**Defect pass: twelve plants, twelve failing their own named gates.**

**Suite: 2255 assertions, all passing** (2225 → 2255).

## D114 — H13 part 1: the sources measured, and the slot list frozen (2026-09-22)

No shell change, no `APP_VERSION` bump — nothing in the app moves yet. What ships is the **slot list**, which is append-only forever and therefore had to be settled before any code could depend on it, plus the derivation that produced it and a gate that keeps it honest.

[[D59]]'s substrate and [[D62]]'s dish fork stand. This rules **source, subset, slot list and acquisition**, and scopes the matcher **out**.

### What was measured (downloaded and counted, not read about)

| source | download | unzipped | foods | nutrients |
|---|---|---|---|---|
| FDC **Foundation** (04/2026) | 469,303 B | 6.7 MB | **395, of which 363 non-null** | 226 distinct |
| FDC **SR Legacy** (2018, frozen) | 13,456,312 B | 211 MB | **7,793** | 148 distinct |
| **CNF 2015** | **5,226,720 B** | ~26 MB CSV | **5,690** | 152 defined, 524,674 amount rows |

Nutrients clearing each coverage bar — the number that decides the slot list:

| bar | Foundation | SR Legacy | CNF |
|---|---|---|---|
| ≥95% | 10 | 15 | **27** |
| ≥90% | 13 | 28 | **42** |
| ≥75% | 15 | 48 | **60** |

### THE BRIEF WAS WRONG ON ITS CENTRAL POINT, AND THE MEASUREMENT CORRECTED IT

The slice was framed around *"bundling everything is not possible, the subsetting rule is the slice's central decision."* **That was an assumption.** SR Legacy and CNF together are **18.7 MB zipped**, and the payload actually kept is ~7,793 × ~50 slots × f32 ≈ **1.9 MB dense**, less sparse.

**So the subsetting question was mis-framed: the answer is COLUMNS, not ROWS.** Row subsetting would have manufactured not-found holes for the matcher to paper over — **making the hardest part of the project harder in order to buy space that was already there.** Column subsetting is bounded, append-only, and touches nothing the matcher searches.

**Two further corrections from the same measurement.** FDC **Foundation Foods is not a candidate** — 363 usable foods, vitamin A at 14.0%, D at 14.3%, B12 at 17.6%; it is a quality reference, and anyone reaching for "the modern FDC set" lands on 363 foods with no vitamins. And **CNF is the denser source, not merely the Canadian one** (42 nutrients at ≥90% against SR Legacy's 28), so the locale ruling is right on a second and independent ground.

### The sugars finding: the name problem arrives before any food name

Same publisher, two datasets, one nutrient:

| | name | id |
|---|---|---|
| Foundation | `Sugars, Total` | **1063** |
| SR Legacy | `Total Sugars` | **2000** |

**Keying slots on the FDC id would have split one nutrient in two, silently.** The shared key is the **USDA SR number** — FDC exposes it as `nutrient.number`, CNF uses it as `NutrientID` — which aligns for protein 203, calcium 301, iron 303, sodium 307, B12 418, folate 417.

This is the evidence for the matcher being **its own slice**. If nutrient names — a closed, curated, ~150-entry vocabulary maintained by one publisher — are this unstable, food names across publishers will be worse. It cost twenty minutes to learn and it came from the data rather than from reasoning about the data.

### THE VITAMIN A CASE, AND THE RULE IT GENERALISES TO

FDC's retinol activity equivalents is **SR 320 at 88.8%** — below the bar. CNF's is **814 at 95.4%** — above it. **The two halves of one nutrient fell on opposite sides of a threshold.**

> **A coverage threshold applied per-namespace can split one nutrient across the bar.** Without an override, a nutrient would **exist or not depending on locale**, and no user could diagnose why: the panel would simply have a row in Canada and no row elsewhere, with nothing on the surface to explain it. **So the bar is evaluated on the UNION, and the override table is what makes that true.**

It generalises immediately: **vitamin D is FDC 328 and CNF 339** — entirely different numbers for the same quantity in the same unit. Both are named merges in `slots.json`.

### The slot list: 46 = 44 derived + 2 judged, with 2 merges

Kept **separately countable on purpose**. *A curated list wearing a derivation's clothes would be the failure this guards against*, and it only survives scrutiny because both sets are visible and countable.

**The judged additions, named one at a time:** **vitamin D** (clears the bar in neither — 66.5% FDC, 87.9% CNF) and **sugars** (77.1% FDC, 81.6% CNF). Both are in `MICRO_SPEC` and arrive from OFF labels **today**. A corpus that cannot hold them would be **a schema that cannot hold a nutrient the app already stores** — exactly the cost the generosity ruling was written against: *an unused slot is 4 bytes; a missing one is a schema that cannot hold the value.*

**A reporting fault caught before freezing.** The generator read each slot's CNF coverage off the canonical number, so **vitamin D reported CNF 0.0%** when CNF holds it at 87.9% under 339. The artifact would have understated the very evidence its own ruling rests on. Coverage is now read **through** the merge.

### Acquisition — ruled here, because it is a property of the corpus

**Bundled in-repo, in its own content-addressed cache, outside the atomic shell, fetched AFTER install and never inside `PRECACHE`.**

- Same origin: no CORS, no third-party availability risk, no rate limit.
- Its own cache prefix: [[D6]] Amendment A already deletes *only* `SHELL_PREFIX` caches and *"never other app caches"*, so a corpus cache survives shell generations by existing design — an app update that does not change the corpus does not re-download it.
- **Not in `PRECACHE`**, and this is the load-bearing half: `install` does `cache.addAll(PRECACHE)`, so a failed corpus fetch inside it would fail the install and **take the offline shell down with it**. The corpus is worth having; it is not worth the shell.

A device offline before the first corpus fetch has macros and no micros, and says so — which is the honesty pin, not a workaround for it.

### Licence, carried into the design rather than the README

CNF is usable *"without further permission"* on conditions, two of which bind code:

- **Attribution travels with the value** — *"Health Canada be identified as the source (Canadian Nutrient File, Health Canada, 2015)"*, the same shape as [[D78]]'s openFDA disclaimer.
- **Values may be re-expressed, never adjusted** — *"You may not modify the nutrient value but you may express it in different serving sizes than the 100g provided."* The corpus stores per-100 g exactly as published and scales only at portion time. This also constrains the override table: it may remap a slot's **identity**, never a **value**.

FDC is US federal public domain; attribution is courtesy.

### Encoding: DENSE, and the measurement confirmed the prior rather than overruling it

Measured on the real 46 slots and the real values, because the acquisition path pays the **compressed** cost and a dense array of mostly-absent cells might have compressed hard enough to invert the answer.

| | SR Legacy (7,793) | CNF (5,690) |
|---|---|---|
| occupied cells | **78.7%** | **93.2%** |
| mean slots per food | 36.2 of 46 | 42.9 of 46 |
| dense raw / gzip | 1,433,912 B / **532,155 B** | 1,046,960 B / **428,181 B** |
| sparse raw / gzip | 1,419,283 B / 601,831 B | 1,224,955 B / 498,806 B |

**Sparse is larger both raw and compressed** — 1.15× dense over the wire, and for CNF it is 1.17× larger even uncompressed. The reason is occupancy: at 79–93% populated, sparse's one-byte slot index per stored value costs more than dense pays to NaN-fill the 7–21% that are absent, and a run of NaNs is a constant four-byte pattern that gzip eats.

So **dense**, and the safety argument now costs nothing: *a wrong slot index produces a plausible number for the WRONG nutrient*, which is the worst failure this corpus can have, and the encoding that cannot have that failure is also the smaller one.

**Absence is NaN, never zero.** Zero is a legitimate value for most of these nutrients ([[D8]], [[D90]]), so the sentinel must be distinguishable from it. That choice is what makes the dense form honest, and it is also what makes it compress.

**What a device actually pays: ~0.5 MB, not 2.4 MB.** Locale selects the namespace, so a device fetches **one** — 532 KB for the default namespace or 428 KB for Canada, gzipped. The 0.92 MB figure is both namespaces and no device needs both.

### What is NOT built yet, stated plainly

The encoder, the IndexedDB runtime, the acquisition path in code, and the panel. **The matcher is out of scope by ruling** ([[D76]] parked the evaluation set precisely for it), and the panel is deferred until Cronometer's per-food completeness marking has actually been looked at rather than recalled.

**Gate suite: 12 verdicts** (was 11) — `tests/check-slots.sh` joins the static checks.

## D115 — An instrument measuring the thing it is about to freeze gets checked against a known value first (2026-09-22; doc-only)

Found in [[D114]]. The slot-list generator read each slot's CNF coverage off the **canonical** slot number, so a merged slot reported the coverage of a number CNF does not use. **Vitamin D printed CNF 0.0%** when CNF holds it at **87.9%** under id 339.

Nothing downstream was wrong — the merge itself was correct, and the slot was included on other grounds. What would have been wrong is **the record**: the artifact would have carried, permanently and in its own file, a figure understating the evidence its own ruling rests on. A future session reading *"vitamin D: CNF 0.0%"* would have concluded CNF does not carry vitamin D at all, and that is a conclusion the data does not support.

> **The rule.** When an instrument's output is about to be **frozen** — append-only, committed, or otherwise expensive to revise — check it against a value already known by other means **before** freezing. Here the known value was one line away: CNF's vitamin D coverage had been measured minutes earlier, at 87.9%, while deciding whether vitamin D cleared the bar. The generator disagreed with a number already on screen and nothing compared them.

**Why this is not [[D109]].** D109 is a gate that reads mutable state the fixture may have written — an assertion measuring the fixture. This is narrower and in some ways worse: the instrument was **correct about the thing it was asked** (which slots exist) and **wrong in the evidence it recorded alongside** (how well populated they are). The primary output was right, so nothing failed, and only a reader comparing two numbers from different runs would ever have noticed.

**What it costs to apply:** one assertion per instrument, against one value known independently. `corpus/derive_slots.py --check` now re-derives and compares byte-for-byte, which catches drift; this rule is about the run **before** there is anything to drift from.

## D116 — H13 part 2: the encoder, the corpus runtime, and the acquisition path — v0.40.0 (2026-09-23)

The corpus can now live on a device. Nothing reads it yet — the matcher is out of scope by ruling — but the substrate [[D59]] specified exists, holds the real data, and is gated against it.

**Encoder** (`corpus/encode.py`): dense little-endian `Float32Array`, row-major, **NaN where the source has no value**, one file per namespace plus an index carrying the slot list and the licence attribution. Output matches the [[D115]] measurement to the byte — `fdc.bin` gzips to 532,155 B, the same figure the measurement script produced independently, which is the cross-check that the encoder encodes what was measured.

| namespace | rows | raw | gzip |
|---|---|---|---|
| `fdc` | 7,793 | 1,433,912 B | 532,155 B |
| `cnf` | 5,690 | 1,046,960 B | 426,899 B |

**Runtime** per D59: IndexedDB, **two object stores written in ONE transaction**, index hydrated to RAM at boot, values left on disk and read a row at a time. A half-written corpus — an index with no values, or values with no index — would answer lookups with numbers it cannot attribute, so the two stores commit together or not at all, and a payload whose byte length is not `rows × cols × 4` is refused before either is touched. **The corpus is dense, which makes its size a checkable claim about its shape.**

**Acquisition** as ruled: bundled in-repo, own cache prefix, fetched **after** install and never inside `PRECACHE`. `tests/check-precache.sh` now asserts that by name, along with the shell cleanup staying prefix-scoped — without which a shell generation would evict the corpus with it.

**Licence in the design.** The attribution travels **inside the stored meta**, so it is present wherever a value is, and the encoder stores per-100 g values exactly as published; `corpusScale` re-expresses at the point of use. Re-expressing is permitted, modifying is not.

### The gate had to move, and the reason is the point

**IndexedDB on a `file://` origin neither succeeds nor fails — `open()` simply never calls back.** The committed harness runs from `file://`, so the round trip cannot be tested there. A harness case would **hang**, and a hang is a no-verdict, which reads exactly like the characterised output-capture intermittent ([[D110]]).

So the slice is gated on **two surfaces**: the pure seams (slot → column, NaN → null, per-100 g scaling, namespace selection) in the harness where they can run, and the **round trip in a ninth CDP gate**, `corpus-gate.ps1`, served over http where IndexedDB works — and asserted against the **real committed asset**, not a fixture: 7,793 rows × 46 cols, matching what the encoder declared.

I first wrote the round trip as a harness case with a 6-second net, watched it report *"IndexedDB on this origin neither succeeded nor failed"*, and removed it. **A green assertion over untested code would have been worse than no assertion**; the net is what turned a hang into that sentence.

### What the defect pass found

**A page exception was being classified as an environment error.** The gate exited 2 — *"could not run at all"* — when the page threw, so the plant that split the one transaction into two returned **no verdict**: the one outcome a defect pass cannot read. Exit 2 is now reserved for no browser, no CDP, no asset; **a throw inside the page is the code failing and fails the gate.** The plant then failed with seventeen named failures.

**And a guard was found unreachable.** `corpusValueAt` bounds-checked `i < 0 || i >= row.length` before reading. On a `Float32Array` both cases yield `undefined`, which the `typeof` test already rejects — so a plant on the bounds half was **vacuous by construction**. It is removed rather than kept as defence that cannot be shown to defend anything, and the plant re-pointed at the `typeof` test, which is what actually does the work. This is [[D114]]'s dead-builder finding again: **code nothing can reach is not a behaviour, and a plant on it can only ever be vacuous.**

**Defect pass: nine plants, nine failing their own named gates**, across both surfaces.

**Suite: 13 verdicts** (was 12) — `corpus-gate.ps1` joins the CDP gates, census 8 → 9. Harness 2,269 assertions.

### Still not built

The panel, and the matcher. The repo now carries **3.3 MB** of corpus assets, which is a real and deliberate addition to a repo otherwise measured in kilobytes — noted here so it is a decision on the record rather than a surprise later.

## D117 — The Canadian path was the one not being tested, and a harness limit stated where it will be met (2026-09-23)

Gate and documentation only. No shell change, no `APP_VERSION` bump.

### The primary path was the unexercised one

[[D116]]'s corpus gate ran under the default locale, so it proved **`fdc`** — and the user of this app is in Canada, where **`cnf`** is the path that will actually run. *Default-locale coverage proved the path I won't use.* The gate now drives **both**, and the Canadian case is driven under a real `en-CA` locale rather than assumed to work because the default one did.

**The load-bearing assertion is that the override took effect**, and writing it was not ceremony:

> `Emulation.setLocaleOverride` moves `Intl` but **not** `navigator.language`, which is what `corpusNamespace()` reads. Measured: with it, **both cases ran `fdc` and reported identical row counts**. Without the assertion the gate would have printed PASS while testing the default twice and calling one of them Canadian.

`Network.setUserAgentOverride`'s `acceptLanguage` is the one that moves `navigator.language`. Both namespaces now verify against their own encoder output:

| locale | `navigator.language` | namespace | rows × cols |
|---|---|---|---|
| default | `en-US` | `fdc` | 7,793 × 46 |
| override | **`en-CA`** | **`cnf`** | **5,690 × 46** |

And a third assertion guards the pair: **the two namespaces must report different row counts**, or the switch selected the same corpus twice and both cases were one test run twice. That is the failure the first version actually had, so it is gated rather than trusted.

### A limit of the harness, stated where the next author will hit it

**IndexedDB on a `file://` origin neither succeeds nor fails: `indexedDB.open()` never calls back.** No handler fires, nothing throws, nothing times out. A harness case touching it does not test it — it **hangs**, and a hang produces no SUMMARY, which is indistinguishable from the characterised output-capture intermittent ([[D110]]).

This is now written **in `tests/data-layer.test.html` itself**, beside the gate-integrity note, because that is where someone about to write such a case will be looking — not in a decision entry they have no reason to open. Anything needing IndexedDB, a service worker, a real origin or CORS belongs in a `*-gate.ps1` CDP gate.

### Two conditions recorded against [[D116]]'s open flags

**The corpus assets in the repo (3.3 MB) are accepted** as static data that changes only on a source refresh. **To revisit if refreshes accumulate versions in history** — the cost is not the file, it is the number of copies git ends up keeping.

**`corpusAcquire` stays dormant, and the trigger ships in the same slice as the first reader.** Stated as a rule because both halves fail on their own: *a trigger with no reader is dead code; a reader with no trigger is a feature silently holding no data.* Neither is visible in a passing suite, which is why it is written down rather than remembered.

## D118 — The micronutrient panel: what Cronometer does, what we take, and where the 46 slots do not fit (2026-09-23; doc-only)

Prior-art study for the panel slice, which stays deferred. No code. Recorded now because the study was the condition on deferring it, and because the slot mapping turned up a problem the panel will have to solve rather than inherit.

### Borrowed

**Grouped sections with real nesting** — General / Carbohydrates / Lipids / Protein / Vitamins / Minerals, and parts under their whole: Fat → Polyunsaturated → Omega-3 → ALA/DHA/EPA. A flat list of 46 rows is a spreadsheet; the nesting is what makes it readable.

**THREE states per nutrient, not two.** This is the one genuinely new idea and it fits our data exactly:

| shown | means | in the corpus |
|---|---|---|
| `–` | not measured, and **excluded from any percentage** | `NaN` |
| `0.00` | measured, and it is zero | `0.0` |
| `<0.01` | present, below display precision | `0 < v < 0.005` |

**Too small to show is not none**, and the first two are already distinguishable in the corpus because absence is NaN and zero is zero ([[D8]], [[D90]], [[D115]]). **The third is a display rule, not a storage one** — no schema change, which is the rare case of prior art costing nothing to adopt.

**Source on every food, in search results as well as in detail** — not only on the opened row. Ours must anyway: the CNF licence requires attribution to travel with the value ([[D114]]).

**Any percentage states its basis once on the page** — "based on…" — rather than leaving the reader to infer what 100% meant.

### Refused, and on which ruling

**% of target on every row.** Each target is a claim, and [[D32]] requires a citation for one. Where no sourced target exists the honest alternatives are **"typical" from the user's own history** ([[D95]]) or **nothing at all** — never a number that looks like a recommendation because it is printed beside a percentage.

**The Nutrition Scores composite.** One number standing for a day's nutrition is the shape this project already refused in Oura's "78": a score is a judgement wearing arithmetic.

**Highlighted %-rings as the first thing seen.** The panel is **opt-in** — depth on demand, not by default.

### Where we are already ahead, and should stay

Cronometer has **no food-level or day-level completeness count**: gaps are found by scanning for dashes. Our **"from N of M items"** is a summary it never gives. Keep it, and consider a per-food **"41 of 46 slots measured"** beside the source — which the corpus can compute for free, since a row's populated count is the non-NaN count.

### The 46 slots mapped, and the nine that do not fit

| group | slots |
|---|---|
| General | 7 |
| Carbohydrates | 3 |
| Lipids | 12 |
| **Protein** | **1** |
| Vitamins | 15 |
| Minerals | 8 |

**Nine of forty-six do not fit cleanly, in four kinds:**

1. **Not a nutrient at all** — `Ash [207]`, an analytical residue nobody eats toward.
2. **The same quantity in another unit** — `Energy kJ [268]` beside `kcal [208]`; `Vitamin A IU [318]` beside `RAE [320]`. These are alternate expressions, not second nutrients, and nesting one under the other implies a part-whole relation that is not there.
3. **Computed equivalents, whose children are inputs rather than parts** — `Vitamin A RAE [320]` (retinol plus carotenoid conversion), `Total niacin equivalent [409]` (includes tryptophan conversion), `Dietary folate equivalents [815]`. Each is *derived from* its siblings, so drawing it as their parent inverts the relationship.
4. **Neither macro nor micro** — `Alcohol [221]`, `Caffeine [262]`, `Theobromine [263]`. Cronometer files them under General; that works, but it is a bucket, not a category.

### Two findings the panel must answer rather than inherit

**A nested group can be complete-looking and incomplete.** Omega-3 in our slot list is `DHA [621]`, `DPA [631]` and `20:3 n-3 [861]` — and **not ALA or EPA**, neither of which cleared the ≥90% bar. A nested "Omega-3" heading would show three members and silently omit the two a reader actually looks for. **That is [[D8]]'s rule at group level**: an understated total that looks complete is worse than an absence, and the group heading is what does the understating. So a group needs the same completeness treatment as a day — *"3 of 5 omega-3 fatty acids carried"* — or it must not be drawn as a group.

**A section with one row is a heading pretending to be a section.** **Protein has exactly one slot** (`[203]`); no amino acid cleared the bar. Rendering a "Protein" section containing protein is worse than folding it into General, and the panel has to decide which — on the evidence, not on symmetry with Cronometer, whose protein section is full because its corpus carries amino acids and ours does not.

**Neither is a defect in the corpus.** Both follow from the ≥90% bar working as ruled. They are facts about what the sources populate, and the panel's job is to show them honestly rather than to hide them behind a tidy heading.

## D119 — The matcher: the index proposes, composition disposes, nothing resolves silently — v0.41.0 (2026-09-23)

### The measurement that decided the shape

**Names do not separate.** Across CNF and SR Legacy — two databases naming the same foods with no shared identifier — only **11.7%** of names match exactly, 14.8% normalised, 20.2% by token set. And **53% of pairs land in the 0.40–0.79 token-Jaccard band**, where same and different interleave:

```
0.75  Pie, fried, cherry             /  Pie, fried pies, cherry            SAME
0.67  Turkey, giblets, simmered      /  Turkey, gizzard, cooked, simmered  DIFFERENT
0.60  Potato, skin, microwaved       /  Potatoes, microwaved, skin         SAME
0.43  Energy drink, with fruit juice /  Beverages, citrus juice drink      DIFFERENT
```

**So no similarity threshold on names can work**, and the token index is a **candidate generator and nothing else**. This is the sugars finding ([[D114]]) one layer out and worse: that was one publisher's closed nutrient vocabulary; this is food names across publishers.

**Composition separates what names cannot.** Random corpus pairs sit at a median distance of **0.69**; at a 0.20 line only **0.6%** of them fall below.

### Two modes, because the evidence differs

**The distance signal exists exactly where it is least needed and is absent where it is most needed.** A **scanned** item already has composition from its label, so its corpus match can be *verified*: the corpus is not being asked what the food contains, but **which row it is**, so the micros the label omits can be borrowed. *Verify on what you know, borrow what you do not.* A **photo** item has no composition at all — the model identifies and never supplies numbers ([[D8]]) — so there is no distance to compute and nothing for a threshold to do. It returns candidates and no verdict.

### The metric is pinned BEFORE anything scores against it

Seven axes: `[203, 204, 205, 208, 301, 303, 307]`, mean relative difference over those present on **both** sides, minimum four. **Fibre is deliberately excluded**: it would make a better metric, and adding it would invalidate the only calibration there is. *A metric chosen after seeing scores is fitted to them*, and the gate asserts the axis list exactly so that changing it is a decision rather than a drift.

### What 0.20 is, and what it is not

**It only ever declines.** Above the line the matcher routes to the off-ramp and the user picks. Below it, a match is **proposed** — still a hypothesis to confirm ([[D62]]), never a result handed over. **Nothing resolves silently at any distance**, and that is the load-bearing gate: even a perfect match returns `decided: false`.

**The caveat, at full weight.** 0.6% is specificity against **random** pairs, and the matcher never proposes a random pair — it proposes **name-similar** ones, which is precisely the population where compositions are also close. *So 0.6% is a floor on the false-accept rate, not an estimate of it*: it is the error rate against easy negatives, and the matcher only ever sees hard ones.

**And the awkward part, recorded rather than smoothed.** Specificity is what was measured; sensitivity was not, because the same-food sample is contaminated — 343 of 1,149 name-matched pairs have distance **exactly** 0.00, CNF having incorporated USDA values, so those rows are one measurement appearing twice rather than two laboratories agreeing. **The measured half would therefore support auto-accepting below 0.20, and it is ruled against anyway**, on asymmetry of harm: *a wrong auto-accept writes a false number into the record silently; a wrong decline costs one tap.*

### The direction was inverted in the ruling, and caught before it shipped

The threshold was first ruled as *"the line below which the matcher declines"*. It is a **distance**: low means a good match, so that would have declined on near-perfect matches and resolved on random ones. The intent was right and the direction was not — corrected to *decline **above*** before any code existed. Recorded because the confusion is natural and will recur: **a distance and a confidence read the same way in a sentence and opposite ways in code.**

### A consequence of the dense float32 encoding, found by a gate

**Distances are never exactly zero.** A value round-tripped through the corpus is not bit-identical to the double it came from — 0.6 × 2 lands at 1.2000000476837158 — so an "identical composition" assertion written as `=== 0` fails. The gates compare against a tolerance, because *asserting exactness would be asserting something the encoding cannot deliver.* Small, but it would have read as a matcher bug rather than a float32 fact.

### Scope, and D76's open question

**The eval set is a directional regression guard, not a design-comparison instrument.** The honest core is the scanned items — label composition is ground truth, so they are distance-scored rather than identity-labelled — and the export currently holds **7 distinct scanned products**. `eval/score.py` already labels every figure `DIRECTIONAL` below 30 rows, structurally, so this needs no new discipline.

**[[D76]]'s open question is half answered.** *"How is a label chosen without a candidate list that shares the matcher's reasoning?"* For **scanned** items it dissolves entirely: the label's composition is the ground truth, so there is no human label and no candidate list. For **photo** items it stands open, and [[D74]]'s `undecidable` remains a finished answer.

**Defect pass: ten plants, ten failing their own named gates**, first pass, no repairs.

**Suite: 2,292 assertions** (2,269 → 2,292).

## D120 — The micronutrient panel, the resolve step, and a refinement to the honesty rule — v0.42.0 (2026-09-23)

### The amendment, and why it is a refinement rather than a retreat

CLAUDE.md read: *"micronutrients enter the log only from **labeled** sources."* A corpus value is neither a label nor a model, so the panel could not have been built without either breaking the rule or working around it. **It is amended in the brief itself**, with the reasoning attached:

> The rule's purpose was to keep **fiction wearing decimals** out of daily totals, and **a cited corpus value is not fiction**. It is, however, **not your food** — generic cheddar is not your cheddar. So a reference value is never summed into the same figure as a labelled one without the panel saying so. **What the rule forbids is an uncited number, not a sourced one.**

**Provenance is structural, not a flag.** Labelled micros stay in `it.micros`; reference micros live in `it.ref.v`, keyed by corpus slot. Two maps, so the existing `microRollup` keeps counting exactly what it always counted, and **nothing can merge them by forgetting to check a field.**

### Resolve is the first reader, so the trigger ships here ([[D117]])

The panel reads **frozen values off items** and never touches the corpus — D59's rule is that *no log operation ever awaits the corpus*, and a panel that queried it would break the freeze that makes the whole substrate payable. So the first reader is **resolve**, and `corpusEnsure()` ships with it.

`resolveItemFreeze` scales the corpus row to **the grams the item actually was**, stores the attribution alongside, and keeps the match distance as **forensics only** — D59's pin: it explains what happened and is never an input to redoing it. An item with no grams freezes **nothing**, because guessing a weight to make the arithmetic work is [[D112]]'s fabrication.

### Three states, and the third needed a table before it meant anything

`–` not measured · `0.00` measured zero · `<step` present but below the displayed step. A display rule over stored values, no schema change — the corpus already distinguishes the first two because absence is NaN.

**But "<0.01" is meaningless until each unit declares its own step.** g, mg and µg cannot share one: 0.05 is a *value* in grams and a *trace* in micrograms. `PANEL_STEP` is pinned per unit and gated, and the trace renders in the nutrient's **own** unit.

### Where a completeness claim is possible, and where it is not

**A "3 of 5 carried" claim needs a closed, declarable membership.** A chemical family has one; *"Vitamins"* does not. So membership is declared only for the fatty-acid families, and a group without one shows its rows and **makes no claim** — rather than inventing a denominator so every heading can have a number.

**The denominator is the declared list, never the rendered rows.** Otherwise *"3 of 3"* restates the rows and is unfalsifiable by construction. Omega-3 is **3 of 5**: ALA and EPA did not clear the ≥90% bar, and the panel names which are missing rather than only how many.

**Computed equivalents sit beside their inputs, never above them.** RAE, niacin equivalent and DFE are each *derived from* their siblings; drawing one as a parent would invite a reader to check that the children sum to it, and they never will. Gated: no group lists an equivalent as a parent.

**Protein is a row, not a section.** No amino acid cleared the bar, and a heading over a single line is a heading pretending to be a section.

### No percentages at all, stated on the page

[[D32]] requires a citation for a target, and the app has **no cited intake targets** — its sourced bands are blood analytes, which are a different thing. So the panel shows **no percentages**, and says so where a reader would look for them. What it can honestly show is the user's own **typical**, on [[D95]]'s terms: same 28-day window, same eight-day floor, descriptive and never prescriptive — and **below the floor, nothing rather than a thinner typical**.

### What the defect pass found

**Thirteen plants, thirteen failing their own named gates**, after one repair: the typical-floor plant scored **VACUOUS** because the fixture had no days carrying the slot, so `vals.length` was 0 and the floor could have been 8 or 1 with the same answer. **The fixture could not make the wrong behaviour possible** ([[D96]]), and was seeded with three days — between one and the floor — so the floor is what decides.

**Suite: 2,321 assertions** (2,292 → 2,321).

### Still open

The panel renders *values*; nothing yet **offers** a resolve from an item row, so `resolveItem` has a caller only in tests. That is the next surface, and it is where [[D119]]'s decline line becomes visible: above 0.20 the user is handed the candidate list, below it a single proposal to confirm.

## D121 — The resolve surface: the next tap, and a persistent route — v0.43.0 (2026-09-23)

### The measurement inverted the premise of the slice

Against the real 35 items, in the CNF namespace the user actually uses:

| source | gets at least one candidate |
|---|---|
| ai-paste | **26 of 27 (96%)** |
| scan | 6 of 8 (75%) |

**And no scanned item can be composition-verified: 0 of 8 carry `grams`.** `buildScanItem` does write it — [[D57]] made the portion data — but the scans were logged **16–17 July and 2–4 September**, and **D57 was ruled 7 September**. Every one predates it. The photo items are all 7–14 September and 24 of 27 carry grams.

> **The panel serves the scans and the resolve surface serves the photos.** The slice was proposed on the opposite assumption — that the panel showed nothing for the 27 photo captures and the surface would fix that for them — which is true of the panel and backwards for the surface. D119's mode 1, the cleverer half, has **no subject in existing data**.

**The scan path ships anyway, knowingly dormant**, and this is the reason: it is already built and gated in [[D119]], and holding it back would mean building it twice. The next real scan is its device test.

### Two affordances, because they answer different questions

**The next tap.** A photo meal that just landed is exactly when resolving should be offered, so `photoSave` starts a **walk** through that meal's unresolved items — offered once, dismissable, and it advances rather than asking again. *"What did I just eat."*

**A persistent route.** Every already-logged row carries a chip, because all 27 existing items need one and a prompt that only fires at save time would leave them unreachable. *"What was that thing last Tuesday."*

**And no badge on an unresolved row.** Twenty-seven rows announcing themselves would be worse than the silence it replaces; the panel already states coverage honestly.

### `resolvePlan` is pure, and it is where D119's ruling lives

Four outcomes, and **every one of them is a question**: no candidates is its own answer; a photo item gets the list because there is no distance and nothing for a threshold to do; below the line **one proposal to confirm**; above it the matcher **declines and hands over the list**. Gated that no phase applies anything.

**The branch is taken on SOURCE, not on whether the arithmetic happens to be possible.** A photo item's macros are the model's estimate, and scoring against them would be treating a guess as evidence — so even a photo item with perfect grams and macros takes the no-basis branch.

### No score is shown, and the reason is measured

**C1.** A number the user cannot act on invites being read as confidence, and [[D119]] measured name similarity as unusable for exactly that: same-food pairs at 0.60 token-Jaccard, different-food pairs at 0.67. The list shows corpus names and nothing else.

### The no-candidate class, named

**Brand names** (*"Craisins"*) and **transliterated dishes** (*"siu mai"*) — three of the 35 items, and neither kind is in a composition database under that spelling. The surface says so plainly and offers a search on a different word. No amount of ranking finds what is not there, and [[D74]]'s `undecidable` stays a finished answer.

### What the defect pass found

**C1 was built and not gated.** The plant that showed the score scored **VACUOUS**, because nothing asserted the rendered list omits it — the ruling was implemented and unprotected. `resolveRowsHTML` is now a pure exported seam with its own gate. *A ruling that is implemented but ungated survives exactly as long as nobody edits that line.*

**And a plant's EXPECTATION was wrong rather than its gate.** The same plant listed `D121-row` alongside `D121-ui`; showing a score in the list has nothing to do with the row, so the runner reported MISSED against a gate that was right not to fire. The expectation was corrected, not the gate — worth distinguishing, because "MISSED" reads like a hole in the gates and here it was a hole in the bookkeeping.

**Module-level view state crossed a section boundary.** `RESOLVE_WALK`, left set by an earlier photo-save case, rendered *"find nutrients for N items"* into a later section — which is the string the row assertions matched on. Same family as [[D113]]'s pinned clock: **shared state that fails somewhere other than where it was set**. Cleared in the fixture, with the reason written beside it.

**Defect pass: nine plants, nine failing their own named gates.**

**Suite: 2,341 assertions** (2,321 → 2,341).

## D122 — Dry and cooked are not the same food, and the matcher was treating them as one — v0.44.0 (2026-09-23)

**Reported from the device against v0.43.0:** *"ramen noodles"*, logged at **270 g cooked**, was offered four **dry** instant-noodle rows first. Picking one scales dry per-100 g values onto 270 g of cooked food, and every micronutrient comes out overstated by the same factor — **silently**, because nothing on the row said which was which.

**Measured, on the exact pair:**

| | kcal / 100 g |
|---|---|
| `Pasta, egg noodles, enriched, dry` | **385** |
| `Pasta, egg noodles, enriched, cooked` | **138** |

**2.8×**, which is the *"roughly 3×"* the report estimated.

### The cause is partly this code, and that is the part worth recording

`matchTokens` strips `raw cooked boiled fresh dried prepared` as **stop words** — and those are the **highest-frequency state markers in the corpus**: measured across CNF, `raw` 987, `boiled` 378, `cooked` 301, `dry` 278. **The ranking discards the one distinction that separates a 385 from a 138, and then ranks the two as equals.**

The stop list is **left alone**, because changing it would invalidate the ranking [[D119]] measured. State is handled as **its own signal** instead — which is also the more honest shape: state is not a name-similarity question.

### Three answers, because 44% of names say nothing

Measured: **55.7% of CNF names and 57.1% of FDC names** carry a state word. The rest carry none, so **unknown is a third answer and never a guess**:

- **same state** — offered first,
- **unknown** — offered next, because *unknown is not wrong, it is unstated*,
- **mismatched** — offered last, and **saying so on the row**.

Within each band the name ranking D119 measured is preserved exactly, so this reorders without re-deciding.

**An item's own state:** its name wins if it says; otherwise a **photographed meal is as-eaten by construction** (the template asks for *"as consumed"*); otherwise **unknown**, because a scanned package is whatever its label is and the name does not reveal it. And with an unknown item state **nothing is reordered at all** — the app does not invent a state to sort by.

### Two facts, not a verdict

Every candidate now shows **its own kcal per 100 g**, beside the item's own. Dry ramen reads 440, cooked egg noodles 138, and the right pick becomes **visible rather than ranked for you**. This is not a score and not a distance — [[C1]]'s refusal stands and is still gated — it is two numbers the app already holds, put side by side.

**And the panel says what picking does:** *"Its vitamins and minerals will be used for your item, scaled to its weight."* A choice whose consequence is unstated is a choice made without the thing that decides it.

### Gated on the ruled fixture

A **cooked item whose top candidate is dry** — the device's exact shape. The fixture asserts first that the top candidate really is dry and a cooked one really is present, because otherwise the ranking has nothing to reorder and the gate would pass on a defect ([[D96]]).

**Defect pass: nine plants, nine failing their own named gates**, first pass, no repairs.

**Suite: 2,358 assertions** (2,341 → 2,358).

## D123 — Flow, part one: the date jump, and four surfaces that did something without showing it — v0.45.0 (2026-09-24)

**H16 was measured before it was designed**, which the brief required: *"Report each as it is today before proposing anything."* Every number below came from clicking real elements on the shipped page at 390×844, not from reading the source and reasoning about what the path ought to be.

### The five journeys, as they were

| # | journey | taps | where the thumb went |
|---|---|---|---|
| 0 | a past day → I'm on it | **15** | `‹` at y=116, fifteen times |
| 1 | eat → logged → I see my day | **4** | 802 → 381 → 660 → 210 |
| 2 | a dose → logged → on the timeline | **4** | 802 → 787 → 578 → 130 |
| 3 | a medication → saved → drug info | **8** | 802 → 753 → ... → **26** (the gear) → 144 → 396 |
| 4 | an old item → resolved → in the panel | **18** from today | 15 of them are journey 0 |

**Journey zero was exact as reported.** `.daysel` was a plain `<div>`, `.hrow` rows were inert, and `stepDay(+/-1)` was the whole of navigation — there was no alternative route at all.

### The finding that mattered more than the tap counts

**Three of the five journeys reached their outcome without showing it.** A dose landed on a timeline **1531px down — 1.8 screens below the fold**. A saved medication left its information **three taps away, inside Settings, behind a card collapsed by default**. A resolved item's numbers appeared in a panel that is **closed by default and 785px down**, which is exactly why finding it needed written directions. That is the principle's real target, and it is not a tap count.

### What shipped in this commit

**The date jump (ruled A3).** A transparent `<input type="date">` over the date itself, clamped to the logged range — so the tap target *is* the thing it changes, with no icon and no second control, and the OS wheel does the picking. Plus the history rows, which already rendered date, status and totals and were **inert**, now navigate: the native picker cannot say which days have data, and that is the one thing the list is good at.

**A VISITED DAY IS NEVER CREATED**, and this is the rule worth carrying forward. Every day-creation site in the app calls `maybeInjectSupplement` (D8/4). Creating a day on arrival would therefore put a **supplement item — real, counted intake — on a day the user only looked at**, which is precisely the *"zero days' worth of fabricated intake"* the Phase R gate exists to forbid. So `current` may name a day with no record, the day view renders it honestly empty, and the record is created by the first thing **written** to it. **Navigation must never be a write.**

A consequence found while building: `stepDay` stepped by **array index**, and `indexOf` returns `-1` for a day that is not in the log — which reads as *no previous and no next*, and would have **disabled both arrows and stranded the thumb** on any day the jump reached. Neighbours are now found by date comparison. The index form was not wrong before; it was only ever asked about days that existed.

**The four endings (ruled G1).** One grammar: what just happened, and the **one** move that follows. After adding food, *See my day*. After a dose, *See it on the timeline* — which needed the timeline row to start carrying its record id, so the ending can find **that** dose rather than scrolling to a day's worth of rows. After saving a medication, *Drug info*, which opens Settings, expands the card and aims the drug surface at the medication just saved, in one tap. After a resolve pick, *See it in the panel*.

The endings are **persistent, not the undo toast**: that toast clears itself after seven seconds, and an ending on a timer is a race, not a route. And the sheet is **not** auto-closed on a successful add — three items in a meal would cost three re-openings, measured as 6 taps today versus 9 — so the exit is offered instead of taken.

**The panel now remembers whether it is open.** It was closing itself on every refresh, which made it unusable as the destination of anything that writes — including the resolve step whose whole purpose is to fill it. A latent defect the ending exposed.

### Two gates re-pointed, carrying their history ([[D92]])

Both read an **HTML substring as a proxy** for what the user sees, and both broke the moment the element gained a control — not because the rule changed.

- **DT-header** sliced `innerHTML` between `class="daysel"` and the next `</div>` to assert the header carries no year. The date input's `value` is an ISO date: a year in the markup that nobody can read. It now reads `textContent`, which is what *"renders without a year"* always meant.
- **D120-optin** matched the literal string `<details class="mpanel">`, so **any** attribute added to the panel failed it. It now reads `open` off the element, which is stricter: a property cannot be faked by a tag that merely looks right.

### The rule, recorded because it has now cost two gates

**A gate that asserts a rendered string asserts the markup, not the meaning.** Read the state where the state exists — `textContent` for what is read, a property for what is set, the DOM node for whether it is there. A substring of `innerHTML` passes and fails for reasons that have nothing to do with the rule it was written for, and it fails **late**, in the commit of whoever next touches the element.

This is the same shape as [[D109]] (a gate that read a mutable value) and [[D115]] (a gate over unreachable code): in each, the assertion was true and about the wrong thing.

### The tap-count gate

`tests/flow-gate.ps1` — the **tenth** CDP gate — pins each journey as a tap count on the shipped page, because a tap count is a property of the page and nothing in a DOM-free core knows what a tap is. **It fails by name whenever a journey grows a tap, and that is intended and ruled**: flow is not asserted once and trusted afterwards, it is a number that drifts one plausible control at a time, and nothing else in the suite would notice.

| journey | was | pinned |
|---|---|---|
| 0 | 15 | **≤ 2**, including a day with no record |
| 1 | 4 | **4**, and the day is offered |
| 2 | 4 | **4**, and the dose is **in view** |
| 3 | 8 | **6** |
| 4 | 18 from today | **3** standing on the day |

**Journey 4 stays 3 taps standing on the day.** The third becomes *offered* instead of *hunted*; its 18 → 5 comes entirely from the date jump. A reduction that isn't there is not claimed.

**J1 and J2 are pinned at 4, not at the slice's target of 3, and that is not a missed target.** Both spend their first two taps reaching the right form — the FAB opens on **Scan**, so Manual and the dose form are each a second tap. **The quick-add row is what removes that tap**, and it ships in the second commit; the pin moves to 3 there, in the same commit that earns it. A pin is what the page does today, not what the slice intends — a gate that pinned 3 now would be red for a reason that is not a defect.

### Still to ship in this slice (second commit)

Quick add ([[B3]]/[[C1]]) and repeat items ([[D1]]/[[E1]]/[[F1]]). Recorded there, not here.

### The defect pass found things about the defect pass

**A gate can also assert an attribute's PRESENCE instead of its value, and that is the same mistake one layer down.** `J2` matched `.tlrow[data-sid]`. The plant that nulled the row's identity still rendered `data-sid=""`, so the selector matched and the plant failed nothing. Tightening it to compare the **value** against the record the app had stored made it fail — **on clean code**, because **signal records have no `id` at all**: this app identifies a timeline record by its **index**, as `deleteSignal(date, idx)` and `openRecordEdit(date, idx)` both do. The ending had been calling `revealTimeline('undefined')`, finding nothing, and falling back to flashing the whole card — so *"See it on the timeline"* scrolled to the right place and then left the eye to find the dose, which is most of the defect it exists to remove. Fixed to the identity the app already has, with the **date captured at the moment of the offer** rather than read when it is taken ([[D54]]'s reason: an offer taken after a day-nav would otherwise reveal whatever record now sits at that index).

**INCONCLUSIVE is not VACUOUS, and the difference saved twelve gates.** A run whose tree does not carry the plant reports **no failures**, which scores as VACUOUS — *"your gate is worthless"*. It is the one verdict shaped like a reason to go and weaken a gate that is fine. The runner now reads the plant back off the disk **before and after** each run, and a tree that lost it is INCONCLUSIVE, never a verdict about the gate. It fired twelve times immediately afterwards, correctly.

**Two defect passes must never share a tree, and this was already known — in the other repo.** Concurrent passes destroying each other's planted trees happened in the **collectibles** repo about two weeks earlier, and a **PID lock** was the fix there. It was never ported here, so it happened again: two runners, each planting `app.js` while the other measured, both producing verdicts about a tree neither had written. The runner now takes an exclusive lock and refuses to start while one is held.

**The rule the user drew from it, which is the more useful half:** *a lesson learned in one of two sibling repos and not carried to the other is the cross-repo version of citing the wrong repo's decisions.* When a harness finding lands in either repo, **check whether the other has the same exposure.**

**And my own error, recorded because it caused the collision.** I twice read an empty process listing as proof that a pass had died, and twice it had not — it was still alive, still planting. **Absence of evidence taken as proof**, which is precisely what I would fail a gate for. The lock is the right fix for exactly that reason: it is **positive evidence, held by the process itself**, so nothing has to be inferred from a silence.

**Suite: 2,373 assertions** (2,358 → 2,373), plus the tenth gate script. **Defect pass: 20 plants, 20 failing their own named gates.**
