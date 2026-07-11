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
