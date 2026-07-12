'use strict';
/* ===========================================================================
   HealthTracker — data layer (schema v2)
   ---------------------------------------------------------------------------
   Fully client-side nutrition + price tracker; a distributable app (v4). This
   file is the data layer + export/import escape hatch:
     • storage adapter: localStorage -> memory, truthful status/badge (rule #5)
     • versioned schema v2 (internal `version`), stable key (D1)
     • in-place v1 -> v2 migration with a retained pre-migration snapshot (D7)
     • export / copy-out, destructive import-restore with the D3 pre-restore
       backup, forward-version guard, and round-trip contract (D5 + amendment)
   Legacy `uha-log-v1` support is REMOVED (v4). Producers of micros/prices
   (scan / manual / ai-paste / price capture) land in later phases; this layer
   is honest about the schema now — every untrusted boundary coerces + escapes.
   =========================================================================== */

// ---- keys & schema --------------------------------------------------------
const STORE_KEY        = 'healthtracker-log';                // D1: version-stable key
const PRERESTORE_KEY   = 'healthtracker-log-prerestore';     // D3: pre-restore backup
const PREMIGRATION_KEY = 'healthtracker-log-premigration';   // D7: retained v1 rollback
const SCHEMA_VERSION   = 2;

const MEALS       = ['breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement'];
const CONFIDENCES = ['eyeballed', 'weighed', 'measured'];
const SOURCES     = ['scan', 'ai-paste', 'manual', 'preset', 'supplement'];
// Canonical micro keys (for future display). Ingest tolerates + preserves
// unknown keys; it does not restrict to this list.
const MICRO_KEYS  = ['sodium_mg', 'potassium_mg', 'calcium_mg', 'iron_mg', 'magnesium_mg',
  'zinc_mg', 'vitamin_a_ug', 'vitamin_c_mg', 'vitamin_d_ug', 'vitamin_b12_ug', 'folate_ug',
  'saturated_fat_g', 'sugars_g', 'cholesterol_mg'];

// ---- small helpers --------------------------------------------------------
// Escaper covers & < > " ' (baseline rule #2).
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));

// num(): pure coercion (invalid -> 0). clampNonNeg(): coerce + clamp >= 0 for
// untrusted boundaries (paste, OFF). The in-place migrator uses num (own trusted
// data, byte-preserved); the restore boundary uses clamp.
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const clampNonNeg = (v) => Math.max(0, num(v));

// Pasted JSON may arrive from a chat app: normalize smart quotes / non-breaking
// spaces before JSON.parse so a clean-looking paste isn't rejected as "Bad JSON".
const cleanJSON = (s) => String(s == null ? '' : s)
  .replace(new RegExp('[' + String.fromCharCode(0x201C, 0x201D, 0x201E, 0x201F, 0x2033, 0x2036) + ']', 'g'), '"')
  .replace(new RegExp('[' + String.fromCharCode(0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2035) + ']', 'g'), "'")
  .replace(new RegExp('[' + String.fromCharCode(0xA0, 0x2007, 0x202F) + ']', 'g'), ' ')
  .trim();

function localDate(d) {
  d = d || new Date();
  return d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0');
}

function blankDay() { return { status: 'in_progress', items: [], water_l: 0 }; }
function defaultSettings() {
  return { goals: {}, supplement: { enabled: false, name: '', nutrients: {} }, presets: [] };
}
function emptyState() {
  return { version: SCHEMA_VERSION, days: {}, current: '', settings: defaultSettings(), priceLog: {} };
}

// ---- storage adapter: localStorage -> memory ------------------------------
const Store = (() => {
  let tier = 'unknown';     // 'local' | 'memory'
  let lastWriteOk = true;   // false only after a real write failure on 'local'
  let memoryBlob = null;
  let forceFail = false;    // test seam — see HT.Store.forceWriteFailure()

  function probe() {
    try { localStorage.setItem('__ht_probe__', '1'); localStorage.removeItem('__ht_probe__'); return true; }
    catch (e) { return false; }
  }
  function readRaw(key) {
    if (tier === 'memory') return null;
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }
  function writeRaw(key, value) {
    if (forceFail) return false;
    try { localStorage.setItem(key, value); return true; } catch (e) { return false; }
  }

  return {
    init() { lastWriteOk = true; tier = probe() ? 'local' : 'memory'; return tier; },
    get tier() { return tier; },
    readRaw,

    saveState(blob) {
      const json = JSON.stringify(blob);
      if (tier === 'local' && writeRaw(STORE_KEY, json)) { lastWriteOk = true; return true; }
      lastWriteOk = false; tier = 'memory'; memoryBlob = blob; return false;
    },

    // D3: durable single-slot pre-restore backup.
    backup(blob) {
      if (tier !== 'local') return false;
      return writeRaw(PRERESTORE_KEY, JSON.stringify(blob));
    },
    peekBackup() { return readRaw(PRERESTORE_KEY); },
    revertBackup(snapshot) {
      if (tier !== 'local') return;
      if (snapshot == null) { try { localStorage.removeItem(PRERESTORE_KEY); } catch (e) {} }
      else writeRaw(PRERESTORE_KEY, snapshot);
    },

    // D7: one-time retained pre-migration snapshot of the untouched v1 blob.
    // Never auto-read; never overwritten once written.
    snapshotPremigration(rawV1) {
      if (tier !== 'local') return false;
      if (readRaw(PREMIGRATION_KEY) != null) return true;
      return writeRaw(PREMIGRATION_KEY, rawV1);
    },

    status() {
      if (tier === 'memory' && lastWriteOk) {
        return { tier: 'memory', ok: false, message: '⚠ NOT saved (private mode / storage blocked) — export before closing' };
      }
      if (!lastWriteOk) {
        return { tier: 'memory', ok: false, message: '⚠ storage write FAILED — data is only in memory; export now' };
      }
      return { tier: 'local', ok: true, message: '✓ saved in this browser' };
    },
    forceWriteFailure(on) { forceFail = !!on; },
  };
})();

// ---- schema normalization -------------------------------------------------
// Coerces an item to the stable contract. `clampMacros` clamps macro numbers >= 0
// (untrusted paste boundary); the migrator passes false to byte-preserve trusted
// data. Micros are always coerced + clamped >= 0; unknown micro keys are preserved.
// `source` is validated against the enum, fallback `manual`.
function normalizeMicros(micros) {
  if (!micros || typeof micros !== 'object' || Array.isArray(micros)) return null;
  const out = {};
  Object.keys(micros).forEach((k) => { out[k] = clampNonNeg(micros[k]); });
  return Object.keys(out).length ? out : null;
}
function normalizeItem(it, clampMacros) {
  const N = clampMacros ? clampNonNeg : num;
  it = it || {};
  const out = {
    name:            String(it.name == null ? '' : it.name),
    meal:            MEALS.includes(it.meal) ? it.meal : 'snack',
    time:            String(it.time == null ? '' : it.time),
    kcal:            N(it.kcal),
    protein_g:       N(it.protein_g),
    fat_g:           N(it.fat_g),
    carb_g:          N(it.carb_g),
    fiber_g:         N(it.fiber_g),
    soluble_fiber_g: N(it.soluble_fiber_g),   // always present, even at 0
    confidence:      CONFIDENCES.includes(it.confidence) ? it.confidence : 'eyeballed',
    notes:           String(it.notes == null ? '' : it.notes),
    source:          SOURCES.includes(it.source) ? it.source : 'manual',
  };
  if (it.barcode != null && String(it.barcode) !== '') out.barcode = String(it.barcode);
  if (it.water_l != null) out.water_l = N(it.water_l);
  if (it._auto === true) out._auto = true;
  const micros = normalizeMicros(it.micros);
  if (micros) out.micros = micros;
  return out;
}

function normalizeSupplement(sup) {
  sup = (sup && typeof sup === 'object' && !Array.isArray(sup)) ? sup : {};
  return {
    enabled: sup.enabled === true,
    name: typeof sup.name === 'string' ? sup.name : '',
    nutrients: (sup.nutrients && typeof sup.nutrients === 'object' && !Array.isArray(sup.nutrients)) ? sup.nutrients : {},
  };
}
function normalizeSettings(s) {
  s = (s && typeof s === 'object' && !Array.isArray(s)) ? s : {};
  return {
    goals: (s.goals && typeof s.goals === 'object' && !Array.isArray(s.goals)) ? s.goals : {},
    supplement: normalizeSupplement(s.supplement),
    presets: Array.isArray(s.presets) ? s.presets : [],
  };
}

// Enforce status discipline across every stored day. Idempotent; returns true if
// it changed anything.
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

// Ensure today's day exists (in_progress) and is selected. Never overwrites.
function ensureCurrentDay(state) {
  let changed = false;
  const today = localDate();
  if (!state.days[today]) { state.days[today] = blankDay(); changed = true; }
  if (state.current !== today) { state.current = today; changed = true; }
  return changed;
}

// ---- migration (D7): in-place v1 -> v2, add-only, byte-preserving ---------
function migrateItemV1toV2(it) {
  it = it || {};
  const source = (it._auto === true) ? 'supplement' : 'manual';   // inferred (v1 has no source)
  return normalizeItem(Object.assign({}, it, { source: source }), false);  // coerce, do NOT clamp
}
function migrateV1toV2(v1, nowISO) {
  const out = {
    version: 2,
    days: {},
    current: typeof v1.current === 'string' ? v1.current : '',
    settings: defaultSettings(),
    priceLog: {},
    migratedAt: nowISO,
  };
  Object.keys(v1.days || {}).forEach((d) => {
    const src = v1.days[d] || {};
    out.days[d] = {
      status:  src.status === 'complete' ? 'complete' : 'in_progress',
      items:   Array.isArray(src.items) ? src.items.map(migrateItemV1toV2) : [],
      water_l: num(src.water_l),   // byte-preserve (own data)
    };
  });
  const knownCount = Array.isArray(v1.known) ? v1.known.length : 0;
  if (knownCount > 0) out.knownDropped = knownCount;   // R2: dropped, count recorded
  return out;
}

// Coerce an untrusted v2 blob into a clean v2 state (restore boundary). Idempotent
// on a clean export (so v2 round-trip holds); clamps + sanitizes a hostile paste.
function normalizeState(o) {
  const s = {
    version: SCHEMA_VERSION,
    days: {},
    current: typeof o.current === 'string' ? o.current : '',
    settings: normalizeSettings(o.settings),
    priceLog: (o.priceLog && typeof o.priceLog === 'object' && !Array.isArray(o.priceLog)) ? o.priceLog : {},
  };
  Object.keys(o.days || {}).forEach((d) => {
    const src = o.days[d] || {};
    s.days[d] = {
      status:  src.status === 'complete' ? 'complete' : 'in_progress',
      items:   Array.isArray(src.items) ? src.items.map((it) => normalizeItem(it, true)) : [],
      water_l: clampNonNeg(src.water_l),   // untrusted -> clamp
    };
  });
  if (typeof o.migratedAt === 'string') s.migratedAt = o.migratedAt;      // preserve stamps (round-trip)
  if (typeof o.knownDropped === 'number') s.knownDropped = o.knownDropped;
  return s;
}

// ---- boot -----------------------------------------------------------------
let APP_STATE = null;
let APP_SOURCE = 'empty';   // 'store' | 'migrated' | 'restored' | 'empty' | 'future'

function boot() {
  Store.init();
  const nowISO = new Date().toISOString();
  let state = null, source = 'empty', dirty = false;

  const raw = Store.readRaw(STORE_KEY);
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && parsed.days) {
        const v = parsed.version;
        if (typeof v === 'number' && v > SCHEMA_VERSION) {
          // Newer app wrote this — never migrate or overwrite it (D7).
          APP_STATE = parsed; APP_SOURCE = 'future';
          return { state: parsed, source: 'future', status: Store.status() };
        }
        if (v === SCHEMA_VERSION) {
          state = parsed; source = 'store';
        } else {
          // version 1 (or version-absent, defensively) -> in-place v1 -> v2 (D7)
          Store.snapshotPremigration(raw);
          state = migrateV1toV2(parsed, nowISO);
          source = 'migrated'; dirty = true;
        }
      }
    } catch (e) { state = null; }   // corrupt blob: fall through to a fresh state
  }

  if (!state) { state = emptyState(); source = 'empty'; dirty = true; }

  // Shape guards (idempotent).
  if (typeof state.version !== 'number') { state.version = SCHEMA_VERSION; dirty = true; }
  if (!state.days || typeof state.days !== 'object') { state.days = {}; dirty = true; }
  if (!state.settings || typeof state.settings !== 'object') { state.settings = defaultSettings(); dirty = true; }
  if (!state.priceLog || typeof state.priceLog !== 'object') { state.priceLog = {}; dirty = true; }

  if (normalizeStatuses(state)) dirty = true;
  if (ensureCurrentDay(state)) dirty = true;

  if (dirty) Store.saveState(state);

  APP_STATE = state; APP_SOURCE = source;
  return { state, source, status: Store.status() };
}

// ---- export / import-restore (D5 + amendment) -----------------------------
function exportJSON() { return JSON.stringify(APP_STATE, null, 2); }

// Validate + route a pasted blob WITHOUT mutating. Version routing (D5 amendment):
// absent -> reject; 1 -> in-place migrate; 2 -> as-is; > 2 -> reject.
function parseImport(raw) {
  const text = cleanJSON(raw);
  if (!text) return { ok: false, error: 'Nothing to import.' };
  let o;
  try { o = JSON.parse(text); }
  catch (e) { return { ok: false, error: 'Bad JSON: ' + e.message }; }
  if (!o || typeof o !== 'object' || Array.isArray(o) || !o.days || typeof o.days !== 'object')
    return { ok: false, error: 'Not a HealthTracker log (no "days").' };
  if (!Object.keys(o.days).every((k) => /^\d{4}-\d{2}-\d{2}$/.test(k)))
    return { ok: false, error: 'Invalid day key — dates must be YYYY-MM-DD.' };
  const v = o.version;
  if (typeof v !== 'number')
    return { ok: false, error: 'Unrecognized log format (no version).' };   // legacy/absent rejected
  if (v > SCHEMA_VERSION)
    return { ok: false, error: 'This export is from a newer version of the app.' };
  if (v === 1)
    return { ok: true, state: migrateV1toV2(o, new Date().toISOString()), kind: 'migrated' };
  return { ok: true, state: normalizeState(o), kind: 'restore' };
}

function showPrerestore(json) {
  const el = document.getElementById('prerestoreBox');
  const wrap = document.getElementById('prerestoreWrap');
  if (el) el.value = json;
  if (wrap) wrap.style.display = 'block';
}
function hidePrerestore() {
  const wrap = document.getElementById('prerestoreWrap');
  if (wrap) wrap.style.display = 'none';
}

// Destructive full replace. Nothing mutates until a valid replacement is in hand.
function restore(raw) {
  const parsed = parseImport(raw);
  if (!parsed.ok) return { ok: false, error: parsed.error };

  const prev = APP_STATE;
  showPrerestore(JSON.stringify(prev, null, 2));
  const priorSlot = Store.peekBackup();            // snapshot existing undo slot (D5)
  const backedUp = Store.backup(prev);             // overwrite single rolling slot (D3)

  const msg = backedUp
    ? 'Replace ALL current data with the imported data?\n\nYour previous data has been backed up (shown on the page) and can be recovered — proceed?'
    : 'Replace ALL current data?\n\n⚠ Storage could NOT keep a backup. Copy the "previous data" text shown on the page FIRST, then proceed anyway?';
  if (!window.confirm(msg)) {
    Store.revertBackup(priorSlot);                 // decline = true no-op for the undo slot
    hidePrerestore();
    return { ok: false, aborted: true };
  }

  APP_STATE = parsed.state;
  normalizeStatuses(APP_STATE);
  ensureCurrentDay(APP_STATE);
  const saved = Store.saveState(APP_STATE);
  APP_SOURCE = parsed.kind === 'migrated' ? 'migrated' : 'restored';
  refresh();
  return { ok: true, kind: parsed.kind, backedUp: backedUp, saved: saved };
}

// ---- DOM handlers ---------------------------------------------------------
function copyOut() {
  const json = exportJSON();
  const box = document.getElementById('exportBox');
  if (box) { box.value = json; box.focus(); box.select(); try { box.setSelectionRange(0, json.length); } catch (e) {} }
  let done = false;
  try { done = document.execCommand('copy'); } catch (e) {}
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(json).then(function () { toast('Copied — paste to your AI or a safe place'); }).catch(function () {});
  }
  toast(done ? 'Copied' : 'Select-all + copy the text above');
}
function doRestore() {
  const box = document.getElementById('importBox');
  const raw = box ? box.value : '';
  if (!raw.trim()) { toast('Paste an export first'); return; }
  const r = restore(raw);
  if (!r.ok) { toast(r.aborted ? 'Restore cancelled' : (r.error || 'Restore failed')); return; }
  if (box) box.value = '';
  toast(r.saved ? ('Restored (' + r.kind + ')') : 'Restored to memory — export to be safe');
}
let _toastT;
function toast(m) {
  const e = document.getElementById('toast');
  if (!e) return;
  e.textContent = m; e.classList.add('show');
  clearTimeout(_toastT);
  _toastT = setTimeout(function () { e.classList.remove('show'); }, 1900);
}

// ---- per-day totals + read-only history -----------------------------------
const DISP_FIELDS = ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fiber_g'];
function dayTotals(day) {
  const t = { kcal: 0, protein_g: 0, fat_g: 0, carb_g: 0, fiber_g: 0 };
  (day.items || []).forEach((i) => DISP_FIELDS.forEach((f) => { t[f] += num(i[f]); }));
  return t;
}
const rDisp = (v) => { v = num(v); return Math.abs(v - Math.round(v)) < 0.05 ? String(Math.round(v)) : v.toFixed(1); };

// EVERY rendered value — day keys included — routes through esc() (rule #2).
function renderHistory() {
  const el = document.getElementById('history');
  if (!el || !APP_STATE) return;
  const keys = Object.keys(APP_STATE.days || {}).sort();
  if (!keys.length) { el.innerHTML = '<div class="note">No days yet.</div>'; return; }
  el.innerHTML = keys.map((d) => {
    const day = APP_STATE.days[d];
    const t = dayTotals(day);
    const flag = day.status !== 'complete' ? '<span class="flag">in progress</span>' : '';
    const items = String((day.items || []).length);
    return `<div class="hrow">
        <div class="hd"><span class="hdate">${esc(d)}</span>${flag}</div>
        <div class="hmeta">${esc(rDisp(t.kcal))} kcal · P ${esc(rDisp(t.protein_g))} · F ${esc(rDisp(t.fat_g))} · C ${esc(rDisp(t.carb_g))} · ${esc(rDisp(t.fiber_g))} fib · ${esc(items)} items · ${esc(rDisp(day.water_l))} L</div>
      </div>`;
  }).join('');
}

// ---- observation harness (minimal; not the real UI) -----------------------
function renderBadge() {
  const el = document.getElementById('storeBadge');
  if (!el) return;
  const s = Store.status();
  el.textContent = s.message;
  el.style.color = s.ok ? 'var(--good)' : 'var(--warn)';
}
function renderDataStatus() {
  const el = document.getElementById('dataStatus');
  if (!el || !APP_STATE) return;
  const st = APP_STATE.settings || {};
  const sup = st.supplement || {};
  const rows = [
    ['storage tier',   Store.tier],
    ['schema version', APP_STATE.version],
    ['load source',    APP_SOURCE],
    ['migrated at',    APP_STATE.migratedAt || '—'],
    ['current day',    APP_STATE.current || '—'],
    ['days stored',    String(Object.keys(APP_STATE.days || {}).length)],
    ['supplement',     sup.enabled ? 'on' : 'off'],
    ['goals set',      String(Object.keys(st.goals || {}).length)],
    ['presets',        String((st.presets || []).length)],
    ['price entries',  String(Object.keys(APP_STATE.priceLog || {}).length)],
  ];
  el.innerHTML = rows.map(([k, v]) =>
    `<div class="kv"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`
  ).join('');
}
function refresh() { renderBadge(); renderDataStatus(); renderHistory(); }

function main() { boot(); refresh(); }

// Console seam for review/testing.
window.HT = {
  Store, boot, migrateV1toV2, normalizeState, refresh,
  exportJSON, parseImport, restore,
  keys: { STORE_KEY, PRERESTORE_KEY, PREMIGRATION_KEY },
  state: () => APP_STATE,
  resave: () => Store.saveState(APP_STATE),
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', main);
else main();
