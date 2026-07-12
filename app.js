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
  if (!state.days[today]) {
    state.days[today] = blankDay();
    maybeInjectSupplement(state, today);   // device-side day creation (D8/4)
    changed = true;
  }
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

// ---- supplement + ingest (DECISIONS.md D8) --------------------------------
function nowTime() {
  const d = new Date();
  return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}

// A day is fillable by a full-days merge only if it holds no real information:
// no items AND no water AND still in_progress. A complete day (even empty — a
// deliberately-closed fast) or a water-only day is never overwritten (D8/1).
function fillable(day) {
  return day.items.length === 0 && day.water_l === 0 && day.status === 'in_progress';
}

// Build the configured supplement as a flagged, non-deletable item. Nutrients are
// user-attested label amounts, so micros are allowed (source 'supplement').
function buildSupplementItem(sup) {
  const n = (sup && sup.nutrients) || {};
  return normalizeItem({
    name: (sup && sup.name) || 'Daily supplement',
    meal: 'supplement', time: nowTime(),
    kcal: n.kcal, protein_g: n.protein_g, fat_g: n.fat_g, carb_g: n.carb_g,
    fiber_g: n.fiber_g, soluble_fiber_g: n.soluble_fiber_g,
    confidence: 'measured', notes: 'auto-applied daily supplement',
    source: 'supplement', _auto: true, micros: n.micros,
  }, true);
}

// Inject the supplement at device-side day creation, if enabled and absent (D8/4).
// Wholesale-arriving days (full-days merge / restore) do NOT call this.
function maybeInjectSupplement(state, dayKey) {
  const sup = (state.settings && state.settings.supplement) || {};
  if (!sup.enabled) return false;
  const day = state.days[dayKey];
  if (!day || day.items.some((i) => i._auto)) return false;
  day.items.push(buildSupplementItem(sup));
  return true;
}

function blankReport() {
  return { ok: true, added: [], created: [], supplemented: [], reopened: [], stripped: 0, skipped: [], mergedDays: [], rejectedItems: 0 };
}
function bumpAdded(report, d) {
  const e = report.added.find((x) => x.date === d);
  if (e) e.count++; else report.added.push({ date: d, count: 1 });
}
function finalizeIngest(report) {
  normalizeStatuses(APP_STATE);
  report.saved = Store.saveState(APP_STATE);
  refresh();
  return report;
}

// AI-paste channel: force source/confidence, strip micros — the boundary can't
// verify intent, so it never honors a self-declared source (D8/2).
function toAiPasteItem(raw) {
  const clean = Object.assign({}, raw);
  delete clean.micros;
  clean.source = 'ai-paste';
  clean.confidence = 'eyeballed';
  return normalizeItem(clean, true);
}

// Four-shape non-destructive ingest. Returns a structured report (D8/5).
function ingest(raw) {
  const text = cleanJSON(raw);
  if (!text) return { ok: false, error: 'Nothing to ingest.' };
  let o;
  try { o = JSON.parse(text); }
  catch (e) { return { ok: false, error: 'Bad JSON: ' + e.message }; }
  const report = blankReport();
  if (o && typeof o === 'object' && !Array.isArray(o) && o.days && typeof o.days === 'object') {
    return ingestFullDays(o, report);   // full-days merge (own-data channel)
  }
  return ingestItems(o, report);        // item shapes (AI-paste channel)
}

// Full-days: same validation + version guard as restore (D8/6), then a
// non-destructive DAY merge (days only; settings/priceLog untouched).
function ingestFullDays(o, report) {
  if (!Object.keys(o.days).every((k) => /^\d{4}-\d{2}-\d{2}$/.test(k)))
    return { ok: false, error: 'Invalid day key — dates must be YYYY-MM-DD.' };
  const v = o.version;
  if (typeof v !== 'number') return { ok: false, error: 'Unrecognized log format (no version).' };
  if (v > SCHEMA_VERSION) return { ok: false, error: 'This export is from a newer version of the app.' };
  const incoming = (v === 1) ? migrateV1toV2(o, new Date().toISOString()) : normalizeState(o);
  Object.keys(incoming.days).forEach((d) => {
    const local = APP_STATE.days[d];
    if (!local || fillable(local)) {
      APP_STATE.days[d] = incoming.days[d];   // wholesale, as-is — no supplement injection
      report.mergedDays.push(d);
    } else {
      report.skipped.push(d);
    }
  });
  return finalizeIngest(report);
}

function ensureIngestDay(d, report) {
  if (!APP_STATE.days[d]) {
    APP_STATE.days[d] = blankDay();
    report.created.push(d);
    if (maybeInjectSupplement(APP_STATE, d)) report.supplemented.push(d);   // device-side creation (D8/4)
  }
}
function ingestItems(o, report) {
  let arr;
  if (Array.isArray(o)) arr = o;
  else if (o && Array.isArray(o.items)) arr = o.items;
  else if (o && typeof o === 'object' && o.name != null) arr = [o];
  else return { ok: false, error: 'Not a recognized ingest shape.' };

  const topDate = (o && !Array.isArray(o) && typeof o.date === 'string') ? o.date : null;
  const today = localDate();

  arr.forEach((raw) => {
    if (!raw || typeof raw !== 'object' || raw.name == null || String(raw.name) === '') { report.rejectedItems++; return; }
    const d = (typeof raw.date === 'string') ? raw.date : (topDate || today);   // item.date > top.date > today
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) { report.rejectedItems++; return; }
    if (raw.micros) report.stripped++;
    const existed = !!APP_STATE.days[d];
    ensureIngestDay(d, report);
    const day = APP_STATE.days[d];
    if (existed && day.status === 'complete') {
      day.status = 'in_progress';
      if (report.reopened.indexOf(d) < 0) report.reopened.push(d);   // append reopens (D8/1)
    }
    day.items.push(toAiPasteItem(raw));
    bumpAdded(report, d);
  });
  return finalizeIngest(report);
}

// Persistent honesty panel — the app explaining what it did to the data (D8/5).
function renderIngestReport(report) {
  const el = document.getElementById('ingestReport');
  if (!el) return;
  if (!report.ok) { el.innerHTML = `<div class="ireport bad">${esc(report.error)}</div>`; return; }
  const L = [];
  const totalAdded = report.added.reduce((a, x) => a + x.count, 0);
  if (totalAdded) L.push('Added ' + totalAdded + ' item(s): ' + report.added.map((x) => esc(x.date) + ' (' + x.count + ')').join(', '));
  if (report.mergedDays.length) L.push('Merged ' + report.mergedDays.length + ' day(s): ' + report.mergedDays.map(esc).join(', '));
  if (report.created.length) L.push('Created ' + report.created.length + ' new day(s): ' + report.created.map(esc).join(', '));
  if (report.supplemented.length) L.push('Supplement injected: ' + report.supplemented.map(esc).join(', '));
  if (report.reopened.length) L.push('Reopened (was complete): ' + report.reopened.map(esc).join(', '));
  if (report.stripped) L.push('Stripped micros from ' + report.stripped + ' AI-paste item(s) — honesty rule');
  if (report.skipped.length) L.push('Skipped ' + report.skipped.length + ' populated day(s): ' + report.skipped.map(esc).join(', '));
  if (report.rejectedItems) L.push('Rejected ' + report.rejectedItems + ' item(s) (no name / bad date)');
  if (!L.length) L.push('Nothing to add.');
  el.innerHTML = L.map((line) => `<div class="ireport">${line}</div>`).join('');
}
function doIngest() {
  const box = document.getElementById('ingestBox');
  const raw = box ? box.value : '';
  if (!raw.trim()) { toast('Paste JSON to ingest first'); return; }
  const report = ingest(raw);
  renderIngestReport(report);
  if (report.ok) { if (box) box.value = ''; toast('Ingested'); }
  else toast(report.error || 'Ingest failed');
}

// ---- day view + goals (Phase 1) -------------------------------------------
let PRIMARY_NUTRIENT = 'kcal';
const RING_NUTRIENTS = ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fiber_g'];
const NUTRIENT_LABELS = { kcal: 'kcal', protein_g: 'protein', fat_g: 'fat', carb_g: 'carbs', fiber_g: 'fiber' };
const CONF_DOT = { weighed: 'good', measured: 'accent', eyeballed: 'warn' };

function curDay() { return APP_STATE && APP_STATE.days[APP_STATE.current]; }

// Direction-aware goal progress: floor ('min') is short when under; ceiling
// ('max') is over when above. (v4 Goals display.)
function goalProgress(current, goal) {
  const cur = num(current), target = num(goal && goal.value);
  const pct = target > 0 ? Math.round((cur / target) * 100) : 0;
  const dir = (goal && goal.direction === 'max') ? 'max' : 'min';
  const status = dir === 'max' ? (cur > target ? 'over' : 'good') : (cur >= target ? 'met' : 'short');
  return { current: cur, target: target, pct: pct, direction: dir, status: status };
}

// Micro rollup with coverage: per micro key present, total + N items carrying it of M.
function microRollup(day) {
  const items = (day && day.items) || [];
  const out = {};
  items.forEach((it) => {
    if (it.micros) Object.keys(it.micros).forEach((k) => {
      if (!out[k]) out[k] = { total: 0, n: 0 };
      out[k].total += num(it.micros[k]);
      out[k].n += 1;
    });
  });
  Object.keys(out).forEach((k) => { out[k].m = items.length; });
  return out;
}

function ringSVG(frac, status) {
  const R = 74, C = 2 * Math.PI * R, L = C * Math.max(Math.min(frac, 1), 0);
  const color = (status === 'over' || status === 'short') ? 'var(--warn)'
    : (status === 'none' ? 'var(--muted)' : 'var(--accent)');
  return `<svg viewBox="0 0 180 180" class="ring">
      <circle cx="90" cy="90" r="${R}" fill="none" stroke="var(--line)" stroke-width="14"/>
      <circle cx="90" cy="90" r="${R}" fill="none" stroke="${color}" stroke-width="14" stroke-linecap="round"
        stroke-dasharray="${L} ${C - L}" transform="rotate(-90 90 90)"/>
    </svg>`;
}

function renderGoalsHTML(t, day) {
  const goals = (APP_STATE.settings && APP_STATE.settings.goals) || {};
  const prim = PRIMARY_NUTRIENT;
  const primVal = num(t[prim]);
  const primGoal = goals[prim];
  let frac, inner, status;
  if (primGoal) {
    const gp = goalProgress(primVal, primGoal);
    frac = gp.pct / 100; status = gp.status;
    inner = `<b>${esc(rDisp(primVal))}</b><span>of ${esc(rDisp(gp.target))} ${esc(NUTRIENT_LABELS[prim] || prim)}</span><span class="gpct ${esc(gp.status)}">${esc(gp.pct)}%</span>`;
  } else {
    frac = 0; status = 'none';
    inner = `<b>${esc(rDisp(primVal))}</b><span>${esc(NUTRIENT_LABELS[prim] || prim)}</span><span class="gpct">set a goal</span>`;
  }
  let html = `<div class="ringbox">${ringSVG(frac, status)}<div class="ringval">${inner}</div></div>`;
  html += `<div class="primsel">` + RING_NUTRIENTS.map((k) =>
    `<button class="${k === prim ? 'on' : ''}" onclick="setPrimary('${k}')">${esc(NUTRIENT_LABELS[k] || k)}</button>`).join('') + `</div>`;
  const gk = Object.keys(goals);
  if (gk.length) {
    html += `<div class="goalstrip">` + gk.map((k) => {
      const gp = goalProgress(num(t[k]), goals[k]);
      return `<div class="goalcell ${esc(gp.status)}"><span>${esc(NUTRIENT_LABELS[k] || k)}</span>` +
        `<b>${esc(rDisp(gp.current))}/${esc(rDisp(gp.target))}</b>` +
        `<small>${esc(gp.direction === 'max' ? 'ceiling' : 'floor')} · ${esc(gp.pct)}%</small>` +
        `<button class="grm" onclick="removeGoal('${esc(k)}')" title="remove goal">×</button></div>`;
    }).join('') + `</div>`;
  }
  const micros = microRollup(day);
  const mk = Object.keys(micros);
  if (mk.length) {
    html += `<div class="summary"><div class="sumhead">Micros present</div>` + mk.map((k) => {
      const mv = micros[k];
      return `<div class="sumrow"><span>${esc(k)}</span><span>${esc(rDisp(mv.total))} <small>from ${esc(mv.n)} of ${esc(mv.m)} items</small></span></div>`;
    }).join('') + `</div>`;
  }
  return html;
}

function renderDay() {
  const host = document.getElementById('dayView');
  if (!host || !APP_STATE) return;
  const dk = APP_STATE.current;
  const day = APP_STATE.days[dk];
  if (!day) { host.innerHTML = ''; return; }
  const dates = Object.keys(APP_STATE.days).sort();
  const di = dates.indexOf(dk);
  const complete = day.status === 'complete';
  const t = dayTotals(day);

  let html = `<div class="daynav">
      <button class="navbtn" onclick="stepDay(-1)" ${di <= 0 ? 'disabled' : ''}>‹</button>
      <div class="daysel">${esc(dk)}${dk === localDate() ? ' · today' : ''} <span class="dstat ${complete ? 'done' : ''}">${esc(day.status.replace('_', ' '))}</span></div>
      <button class="navbtn" onclick="stepDay(1)" ${di < 0 || di >= dates.length - 1 ? 'disabled' : ''}>›</button>
    </div>`;

  html += renderGoalsHTML(t, day);

  const groups = {};
  day.items.forEach((it, idx) => { const m = MEALS.indexOf(it.meal) >= 0 ? it.meal : 'other'; (groups[m] = groups[m] || []).push({ it: it, idx: idx }); });
  MEALS.concat('other').forEach((m) => {
    if (!groups[m]) return;
    const gt = dayTotals({ items: groups[m].map((x) => x.it) });
    html += `<div class="mealgrp"><div class="mealhead"><span>${esc(m)}</span><span>${esc(rDisp(gt.kcal))} kcal</span></div>`;
    groups[m].forEach((row) => {
      const it = row.it, idx = row.idx;
      const dot = CONF_DOT[it.confidence] || 'muted';
      const rm = it._auto ? '' : `<button class="rm" onclick="deleteItem(${idx})" title="delete">×</button>`;
      const chip = it._auto ? '' : `<button class="mealchip" onclick="cycleMeal(${idx})" title="change meal">${esc(it.meal)}</button>`;
      html += `<div class="mitem"><div class="mmain">
          <div class="mname">${esc(it.name)}</div>
          <div class="mmeta">${it.time ? esc(it.time) + ' · ' : ''}<span class="dot ${dot}"></span>${esc(it.confidence)} · P ${esc(rDisp(it.protein_g))} F ${esc(rDisp(it.fat_g))} C ${esc(rDisp(it.carb_g))} · ${esc(rDisp(it.fiber_g))} fib · <span class="src">${esc(it.source || '')}</span></div>
          ${chip}
        </div><div class="mkcal">${esc(rDisp(it.kcal))}<small> kcal</small></div>${rm}</div>`;
    });
    html += `</div>`;
  });

  html += `<div class="daytot"><span>Total (est.)</span><span>${esc(rDisp(t.kcal))} kcal · ${esc(rDisp(t.protein_g))}P ${esc(rDisp(t.fat_g))}F ${esc(rDisp(t.carb_g))}C · ${esc(rDisp(t.fiber_g))} fib</span></div>`;
  const w = day.water_l || 0;
  html += `<div class="waterrow"><span>Water <b>${esc(rDisp(w))}</b> L</span>
      <span class="wbtns"><button onclick="addWater(-0.25)">−</button><button onclick="addWater(0.25)">+0.25</button><button onclick="addWater(0.5)">+0.5</button></span></div>`;
  html += `<button class="btn big ${complete ? 'reopen' : 'close'}" onclick="toggleDayStatus()">${complete ? '✓ Complete — tap to reopen' : 'End &amp; complete this day'}</button>`;
  html += `<button class="clrday" onclick="clearDay()">Clear this day</button>`;

  host.innerHTML = html;
}

// ---- day / goal interactions ----------------------------------------------
function stepDay(dir) {
  const dates = Object.keys(APP_STATE.days).sort();
  const j = dates.indexOf(APP_STATE.current) + dir;
  if (j < 0 || j >= dates.length) return;
  APP_STATE.current = dates[j];
  Store.saveState(APP_STATE); refresh();
}
function setPrimary(k) { PRIMARY_NUTRIENT = k; refresh(); }
function deleteItem(idx) {
  const day = curDay(); if (!day) return;
  const it = day.items[idx];
  if (!it || it._auto) return;               // supplement is non-deletable
  day.items.splice(idx, 1);
  Store.saveState(APP_STATE); refresh();
}
function cycleMeal(idx) {
  const day = curDay(); if (!day) return;
  const it = day.items[idx]; if (!it || it._auto) return;
  it.meal = MEALS[(MEALS.indexOf(it.meal) + 1) % MEALS.length];
  Store.saveState(APP_STATE); refresh();
}
function toggleDayStatus() {
  const day = curDay(); if (!day) return;
  day.status = day.status === 'complete' ? 'in_progress' : 'complete';
  Store.saveState(APP_STATE); refresh();
  toast(day.status === 'complete' ? 'Day completed' : 'Day reopened');
}
function clearDay() {
  const day = curDay(); if (!day) return;
  if (!window.confirm('Clear all items and water for ' + APP_STATE.current + '? This cannot be undone.')) return;
  day.items = []; day.water_l = 0;
  Store.saveState(APP_STATE); refresh();
  toast('Day cleared');
}
function addWater(delta) {
  const day = curDay(); if (!day) return;
  day.water_l = Math.max(0, Math.round(((day.water_l || 0) + delta) * 100) / 100);
  Store.saveState(APP_STATE); refresh();
}
function setGoal(key, value, direction) {
  if (!APP_STATE.settings.goals) APP_STATE.settings.goals = {};
  APP_STATE.settings.goals[key] = { value: clampNonNeg(value), direction: direction === 'max' ? 'max' : 'min' };
  Store.saveState(APP_STATE); refresh();
}
function removeGoal(key) {
  if (APP_STATE.settings.goals) delete APP_STATE.settings.goals[key];
  Store.saveState(APP_STATE); refresh();
}
function setGoalFromForm() {
  const k = document.getElementById('goalNutrient').value;
  const v = document.getElementById('goalValue').value;
  const d = document.getElementById('goalDir').value;
  if (!v) { toast('Enter a target value'); return; }
  setGoal(k, v, d);
  document.getElementById('goalValue').value = '';
  toast('Goal set');
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
function refresh() { renderBadge(); renderDay(); renderHistory(); renderDataStatus(); }

function main() { boot(); refresh(); }

// Console seam for review/testing.
window.HT = {
  Store, boot, migrateV1toV2, normalizeState, refresh,
  exportJSON, parseImport, restore,
  ingest, maybeInjectSupplement, buildSupplementItem, fillable,
  goalProgress, microRollup, dayTotals, setGoal,
  keys: { STORE_KEY, PRERESTORE_KEY, PREMIGRATION_KEY },
  state: () => APP_STATE,
  resave: () => Store.saveState(APP_STATE),
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', main);
else main();
