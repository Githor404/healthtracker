'use strict';
/* ===========================================================================
   HealthTracker — data layer
   ---------------------------------------------------------------------------
   Scope of THIS file today (Phase 0, first slice): persistence only.
     • storage adapter: localStorage -> memory, truthful status/badge
     • versioned schema (internal `version`), stable key (DECISIONS.md D1)
     • one-time migration of the predecessor's `uha-log-v1` (DECISIONS.md D2)
   NOT here yet (built after review): ingest, export/copy-out, destructive
   import/restore + pre-restore backup (D3), history UI, service worker, manifest.
   Every value written to the DOM goes through esc() — no exceptions.
   =========================================================================== */

// ---- keys & schema --------------------------------------------------------
const STORE_KEY      = 'healthtracker-log';            // D1: version-stable key
const PRERESTORE_KEY = 'healthtracker-log-prerestore'; // D3 (used by restore, not yet built)
const LEGACY_KEY     = 'uha-log-v1';                   // predecessor key — read-only
const SCHEMA_VERSION = 1;

const MEALS       = ['breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement'];
const CONFIDENCES = ['eyeballed', 'weighed', 'measured'];

// ---- small helpers --------------------------------------------------------
// Escaper covers & < > " ' (the predecessor missed '). Baseline rule #2.
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));

// num(): pure numeric coercion (invalid -> 0), lossless for valid numbers.
// Used for trusted migration data. Untrusted paths (OFF / pasted JSON, built
// later) additionally clamp to >= 0 at their boundary.
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const clampNonNeg = (v) => Math.max(0, num(v));

function localDate(d) {
  d = d || new Date();
  return d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0');
}

function blankDay() { return { status: 'in_progress', items: [], water_l: 0 }; }
function emptyState() { return { version: SCHEMA_VERSION, days: {}, known: [], current: '' }; }

// ---- storage adapter: localStorage -> memory ------------------------------
// The status() object is the single source of truth for the badge. It reacts
// to write failures AT WRITE TIME (baseline rule #5): a quota error after load
// flips the tier to memory so the UI can never keep claiming "saved".
const Store = (() => {
  let tier = 'unknown';     // 'local' | 'memory'
  let lastWriteOk = true;   // false only after a real write failure on 'local'
  let memoryBlob = null;    // in-memory copy when durable storage is unavailable
  let forceFail = false;    // test seam — see HT.Store.forceWriteFailure()

  function probe() {
    try {
      localStorage.setItem('__ht_probe__', '1');
      localStorage.removeItem('__ht_probe__');
      return true;
    } catch (e) { return false; }
  }

  function readRaw(key) {
    if (tier === 'memory') return null;          // durable storage unavailable
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }

  function writeRaw(key, value) {
    if (forceFail) return false;                 // simulate quota/denied writes
    try { localStorage.setItem(key, value); return true; } catch (e) { return false; }
  }

  return {
    init() { tier = probe() ? 'local' : 'memory'; return tier; },
    get tier() { return tier; },
    readRaw,

    // Persist the primary blob. On failure, degrade to memory tier and keep the
    // data in memory so the session isn't lost — but the badge now tells the truth.
    saveState(blob) {
      const json = JSON.stringify(blob);
      if (tier === 'local' && writeRaw(STORE_KEY, json)) { lastWriteOk = true; return true; }
      lastWriteOk = false;
      tier = 'memory';
      memoryBlob = blob;
      return false;
    },

    // Truthful status for the badge. ok=false => user must export to be safe.
    status() {
      if (tier === 'memory' && lastWriteOk) {
        return { tier: 'memory', ok: false,
          message: '⚠ NOT saved (private mode / storage blocked) — export before closing' };
      }
      if (!lastWriteOk) {
        return { tier: 'memory', ok: false,
          message: '⚠ storage write FAILED — data is only in memory; export now' };
      }
      return { tier: 'local', ok: true, message: '✓ saved in this browser' };
    },

    // Test seam for the Phase 0 gate (forced write failure after load).
    forceWriteFailure(on) { forceFail = !!on; },
  };
})();

// ---- schema normalization (data-layer; not the "ingest" feature) ----------
// Coerces a legacy/persisted item to the stable contract. Lossless for valid
// data; guarantees soluble_fiber_g is always present; preserves optional
// barcode / water_l / _auto. Numbers are coerced (not clamped) here because the
// source is the user's own trusted export.
function normalizeItem(it) {
  it = it || {};
  const out = {
    name:            String(it.name == null ? '' : it.name),
    meal:            MEALS.includes(it.meal) ? it.meal : 'snack',
    time:            String(it.time == null ? '' : it.time),
    kcal:            num(it.kcal),
    protein_g:       num(it.protein_g),
    fat_g:           num(it.fat_g),
    carb_g:          num(it.carb_g),
    fiber_g:         num(it.fiber_g),
    soluble_fiber_g: num(it.soluble_fiber_g),   // always present, even at 0
    confidence:      CONFIDENCES.includes(it.confidence) ? it.confidence : 'eyeballed',
    notes:           String(it.notes == null ? '' : it.notes),
  };
  if (it.barcode != null && String(it.barcode) !== '') out.barcode = String(it.barcode);
  if (it.water_l != null) out.water_l = num(it.water_l);
  if (it._auto === true) out._auto = true;
  return out;
}

// Enforce status discipline across every stored day. Returns true if it changed
// anything (so boot knows whether a re-save is warranted). Idempotent.
function normalizeStatuses(state) {
  let changed = false;
  const days = state.days || {};
  Object.keys(days).forEach((d) => {
    const day = days[d];
    if (day.status !== 'complete' && day.status !== 'in_progress') { day.status = 'in_progress'; changed = true; }
    if (!Array.isArray(day.items)) { day.items = []; changed = true; }
    if (typeof day.water_l !== 'number') { day.water_l = clampNonNeg(day.water_l); changed = true; }
  });
  return changed;
}

// Ensure today's day exists (in_progress) and is the selected day. Never
// overwrites an existing day. Returns true if it changed anything.
function ensureCurrentDay(state) {
  let changed = false;
  const today = localDate();
  if (!state.days[today]) { state.days[today] = blankDay(); changed = true; }
  if (state.current !== today) { state.current = today; changed = true; }
  return changed;
}

// ---- migration (DECISIONS.md D2: idempotent, one-directional) --------------
// Legacy shape: { days:{date:day}, known:[], current }. Preserve everything —
// item counts, per-day totals, statuses, water — and stamp the audit trail.
// NOTE: historical days are migrated exactly as exported (transport layer — no
// editorializing). The auto-supplement is NOT retro-injected here; that would
// break the lossless gate. The resulting fiber/kcal undercount and the optional,
// separate backfill utility that would address it are recorded in DECISIONS.md D4.
function migrateLegacy(legacy, nowISO) {
  const days = {};
  Object.keys(legacy.days || {}).forEach((d) => {
    const src = legacy.days[d] || {};
    days[d] = {
      status:  src.status === 'complete' ? 'complete' : 'in_progress',
      items:   Array.isArray(src.items) ? src.items.map(normalizeItem) : [],
      water_l: num(src.water_l),
    };
  });
  return {
    version:      SCHEMA_VERSION,
    days:         days,
    known:        Array.isArray(legacy.known) ? legacy.known.slice() : [],  // Phase-2 shape; preserved as-is
    current:      typeof legacy.current === 'string' ? legacy.current : '',
    migratedFrom: LEGACY_KEY,
    migratedAt:   nowISO,
  };
}

// ---- boot -----------------------------------------------------------------
let APP_STATE = null;
let APP_SOURCE = 'empty';   // 'store' | 'migrated' | 'empty'

function boot() {
  Store.init();
  const nowISO = new Date().toISOString();
  let state = null;
  let source = 'empty';
  let dirty = false;

  // D2: the new key wins UNCONDITIONALLY when present. No legacy read, no merge.
  const rawNew = Store.readRaw(STORE_KEY);
  if (rawNew) {
    try {
      const parsed = JSON.parse(rawNew);
      if (parsed && typeof parsed === 'object') { state = parsed; source = 'store'; }
    } catch (e) { state = null; }   // corrupt new-key blob: fall through, do NOT touch legacy
  }

  // Only when the new key is ABSENT do we consult legacy, migrate, and persist.
  if (!state) {
    const rawLegacy = Store.readRaw(LEGACY_KEY);
    if (rawLegacy) {
      try {
        const legacy = JSON.parse(rawLegacy);
        if (legacy && legacy.days) { state = migrateLegacy(legacy, nowISO); source = 'migrated'; dirty = true; }
      } catch (e) { state = null; }
    }
  }

  if (!state) { state = emptyState(); source = 'empty'; dirty = true; }

  // Schema-forward shape guards (idempotent; future version bumps chain here).
  if (typeof state.version !== 'number') { state.version = SCHEMA_VERSION; dirty = true; }
  if (!state.days || typeof state.days !== 'object') { state.days = {}; dirty = true; }
  if (!Array.isArray(state.known)) { state.known = []; dirty = true; }

  if (normalizeStatuses(state)) dirty = true;
  if (ensureCurrentDay(state)) dirty = true;

  if (dirty) Store.saveState(state);   // legacy key is never written to

  APP_STATE = state;
  APP_SOURCE = source;
  return { state, source, status: Store.status() };
}

// ---- Phase 0 observation harness (minimal; not the real UI) ---------------
function renderBadge() {
  const el = document.getElementById('storeBadge');
  if (!el) return;
  const s = Store.status();
  el.textContent = s.message;                       // status messages are static strings
  el.style.color = s.ok ? 'var(--good)' : 'var(--warn)';
}

function renderDataStatus() {
  const el = document.getElementById('dataStatus');
  if (!el || !APP_STATE) return;
  const dayKeys = Object.keys(APP_STATE.days || {}).sort();
  const rows = [
    ['storage tier',   Store.tier],
    ['schema version', APP_STATE.version],
    ['load source',    APP_SOURCE],
    ['migrated from',  APP_STATE.migratedFrom || '—'],
    ['migrated at',    APP_STATE.migratedAt || '—'],
    ['current day',    APP_STATE.current || '—'],
    ['days stored',    String(dayKeys.length)],
    ['known foods',    String((APP_STATE.known || []).length)],
  ];
  el.innerHTML = rows.map(([k, v]) =>
    `<div class="kv"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`
  ).join('');
}

function refresh() { renderBadge(); renderDataStatus(); }

function main() {
  boot();
  refresh();
}

// Console seam for review/testing the gate without a UI for it yet.
window.HT = {
  Store, boot, migrateLegacy, refresh,
  keys: { STORE_KEY, PRERESTORE_KEY, LEGACY_KEY },
  state: () => APP_STATE,
  resave: () => Store.saveState(APP_STATE),
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', main);
else main();
