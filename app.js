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
const SCHEMA_VERSION   = 3;
const APP_VERSION      = '0.4.1';                           // D14 OFF UA token + D6 update version (bumps every release; gated)

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
  return { goals: {}, supplement: { enabled: false, name: '', nutrients: {} }, presets: [], currency: '', signalUnits: {} };
}
function emptyState() {
  return { version: SCHEMA_VERSION, days: {}, current: '', settings: defaultSettings(), priceLog: {}, timeline: {} };
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

    // D13: auxiliary keys (the product cache) — persisted only on the local tier.
    // A failure is a benign no-op and NEVER flips the log's badge (lastWriteOk):
    // the cache is a disposable mirror, not user data. writeRaw already swallows
    // errors -> false, and honors the forceFail test seam.
    writeAux(key, value) {
      if (tier !== 'local') return false;
      return writeRaw(key, value);
    },
    removeAux(key) {
      if (tier !== 'local') return;
      try { localStorage.removeItem(key); } catch (e) {}
    },
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
  const rawN = (sup.nutrients && typeof sup.nutrients === 'object' && !Array.isArray(sup.nutrients)) ? sup.nutrients : {};
  const nutrients = {};
  ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fiber_g', 'soluble_fiber_g'].forEach((k) => {
    if (rawN[k] != null && rawN[k] !== '') nutrients[k] = clampNonNeg(rawN[k]);   // coerce + clamp (D12 hardening)
  });
  const micros = normalizeMicros(rawN.micros);
  if (micros) nutrients.micros = micros;
  return {
    enabled: sup.enabled === true,
    name: typeof sup.name === 'string' ? sup.name : '',
    nutrients: nutrients,
  };
}
function normalizeSettings(s) {
  s = (s && typeof s === 'object' && !Array.isArray(s)) ? s : {};
  return {
    goals: (s.goals && typeof s.goals === 'object' && !Array.isArray(s.goals)) ? s.goals : {},
    supplement: normalizeSupplement(s.supplement),
    presets: Array.isArray(s.presets) ? s.presets : [],
    currency: typeof s.currency === 'string' ? s.currency : '',   // D18: last-used price currency
    signalUnits: (s.signalUnits && typeof s.signalUnits === 'object' && !Array.isArray(s.signalUnits)) ? s.signalUnits : {},   // D20: last-used unit per signal type
  };
}

// D18: restore-boundary hardening for priceLog (was passthrough). Barcode keys
// validated 8-14 digits (a crafted key is markup waiting to render -> dropped);
// price clamped >= 0; store/currency/name kept RAW (escaped at render); a bad
// date is blanked but the entry kept (less lossy than dropping the price).
function normalizePriceLog(o) {
  const src = (o && typeof o === 'object' && !Array.isArray(o)) ? o : {};
  const out = {};
  Object.keys(src).forEach((bc) => {
    if (!/^\d{8,14}$/.test(bc)) return;                            // drop non-barcode keys
    const b = src[bc];
    if (!b || typeof b !== 'object' || Array.isArray(b)) return;
    const entries = (Array.isArray(b.entries) ? b.entries : []).map((e) => {
      e = e || {};
      const date = /^\d{4}-\d{2}-\d{2}$/.test(String(e.date)) ? String(e.date) : '';
      return { price: clampNonNeg(e.price), currency: String(e.currency == null ? '' : e.currency), store: String(e.store == null ? '' : e.store), date: date };
    });
    out[bc] = { name: String(b.name == null ? '' : b.name), entries: entries };
  });
  return out;
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

// D20: add-only in-place v2 -> v3 (add empty timeline). Days/settings/priceLog/
// current byte-preserved. migratedAt preserved if present, else stamped now.
function migrateV2toV3(v2, nowISO) {
  const out = {
    version: 3,
    days: (v2.days && typeof v2.days === 'object') ? v2.days : {},
    current: typeof v2.current === 'string' ? v2.current : '',
    settings: (v2.settings && typeof v2.settings === 'object') ? v2.settings : defaultSettings(),
    priceLog: (v2.priceLog && typeof v2.priceLog === 'object') ? v2.priceLog : {},
    timeline: {},   // add-only
    migratedAt: typeof v2.migratedAt === 'string' ? v2.migratedAt : nowISO,
  };
  if (typeof v2.knownDropped === 'number') out.knownDropped = v2.knownDropped;
  return out;
}
// Chain the in-place migrators to the latest schema (D7/D20). version-absent is
// treated as v1 defensively (our key). The same migrator serves boot + restore.
function migrateToLatest(blob, nowISO) {
  let out = blob;
  const v = (typeof blob.version === 'number') ? blob.version : 1;
  if (v < 2) out = migrateV1toV2(out, nowISO);
  if ((out.version || 2) < 3) out = migrateV2toV3(out, nowISO);
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
    priceLog: normalizePriceLog(o.priceLog),   // D18: was passthrough — now coerced at the boundary
    timeline: normalizeTimeline(o.timeline),   // D20: source-agnostic signal store
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
          // version 1 or 2 (or version-absent, defensively) -> chained in-place
          // migration to the latest schema (D7 / D20). Snapshot the untouched blob first.
          Store.snapshotPremigration(raw);
          state = migrateToLatest(parsed, nowISO);
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
  if (!state.timeline || typeof state.timeline !== 'object') { state.timeline = {}; dirty = true; }   // D20

  if (normalizeStatuses(state)) dirty = true;
  if (ensureCurrentDay(state)) dirty = true;

  if (dirty) Store.saveState(state);

  APP_STATE = state; APP_SOURCE = source;
  return { state, source, status: Store.status() };
}

// ---- export / import-restore (D5 + amendment) -----------------------------
function exportJSON() { return JSON.stringify(APP_STATE, null, 2); }

// Validate + route a pasted blob WITHOUT mutating. Version routing (D5 amend / D20):
// absent -> reject; 1/2 -> in-place migrate to latest; 3 -> as-is; > 3 -> reject.
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
    return { ok: true, state: migrateToLatest(o, new Date().toISOString()), kind: 'migrated' };   // v1 shape -> chain to v3
  return { ok: true, state: normalizeState(o), kind: (v < SCHEMA_VERSION ? 'migrated' : 'restore') };   // v2 -> upgrade; v3 -> as-is
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

// Unified day-scope application (D12): the setting governs today-while-in_progress
// + future creations; a settled (complete) day — today-once-closed or past — is
// never rewritten. Config is not a log action.
function applySupplementToToday() {
  const today = APP_STATE.days[localDate()];
  if (!today || today.status !== 'in_progress') return;   // settled/absent: never touch
  const sup = APP_STATE.settings.supplement || {};
  const hasAuto = today.items.some((i) => i._auto);
  if (sup.enabled) {
    if (hasAuto) today.items = today.items.map((i) => (i._auto ? buildSupplementItem(sup) : i));   // edit: rebuild in place
    else today.items.push(buildSupplementItem(sup));                                                // enable: inject
  } else if (hasAuto) {
    today.items = today.items.filter((i) => !i._auto);                                              // disable: remove standing dose
  }
}

// Testable core: set the supplement config and apply the day-scope rule.
function setSupplement(enabled, name, nutrients) {
  APP_STATE.settings.supplement = normalizeSupplement({ enabled: enabled, name: name, nutrients: nutrients });
  applySupplementToToday();
  Store.saveState(APP_STATE); refresh();
  return APP_STATE.settings.supplement;
}

function readSupplementForm() {
  const g = (id) => { const el = document.getElementById(id); return el ? el.value : ''; };
  const nutrients = {
    kcal: g('supKcal'), protein_g: g('supP'), fat_g: g('supF'), carb_g: g('supC'),
    fiber_g: g('supFib'), soluble_fiber_g: g('supSol'),
  };
  const micros = readMicroFields('sup_micro_');
  if (Object.keys(micros).length) nutrients.micros = micros;
  return { name: g('supName'), nutrients: nutrients };
}
function showSupplementWarnings(warns) {
  const el = document.getElementById('supWarn'); if (!el) return;
  el.innerHTML = (warns && warns.length) ? warns.map((w) => `<div class="warn">${esc(w)}</div>`).join('') : '';
}
function saveSupplement() {
  const form = readSupplementForm();
  const enabled = !!(document.getElementById('supEnabled') || {}).checked;
  const warns = manualWarnings(form.nutrients);
  setSupplement(enabled, form.name, form.nutrients);
  showSupplementWarnings(warns);
  toast(enabled ? 'Supplement saved & enabled' : 'Supplement disabled');
}
function renderSupplementForm() {
  const sup = (APP_STATE.settings && APP_STATE.settings.supplement) || {};
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = (v == null ? '' : v); };
  const en = document.getElementById('supEnabled'); if (en) en.checked = !!sup.enabled;
  set('supName', sup.name || '');
  const n = sup.nutrients || {};
  set('supKcal', n.kcal); set('supP', n.protein_g); set('supF', n.fat_g); set('supC', n.carb_g);
  set('supFib', n.fiber_g); set('supSol', n.soluble_fiber_g);
  const micros = n.micros || {};
  MICRO_SPEC.forEach((s) => { const el = document.getElementById('sup_micro_' + s.key); if (el) el.value = (micros[s.key] == null ? '' : micros[s.key]); });
  updateMicroCount('sup_micro_', 'supMicroCount');
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
    html += `<div class="summary"><div class="sumhead">Micronutrients — labeled intake only</div>` + mk.map((k) => {
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

// ---- manual add + presets (DECISIONS.md D9) -------------------------------
// One table drives the micro form fields, their units, the sane-range warnings,
// AND the read-back — generation and reading key off the same canonical key, so
// field <-> key can't cross-wire. (mcg = micrograms, kept ASCII.)
const MICRO_SPEC = [
  { key: 'sodium_mg', label: 'Sodium', unit: 'mg', warn: 10000 },
  { key: 'potassium_mg', label: 'Potassium', unit: 'mg', warn: 10000 },
  { key: 'calcium_mg', label: 'Calcium', unit: 'mg', warn: 5000 },
  { key: 'iron_mg', label: 'Iron', unit: 'mg', warn: 100 },
  { key: 'magnesium_mg', label: 'Magnesium', unit: 'mg', warn: 1000 },
  { key: 'zinc_mg', label: 'Zinc', unit: 'mg', warn: 100 },
  { key: 'cholesterol_mg', label: 'Cholesterol', unit: 'mg', warn: 5000 },
  { key: 'vitamin_a_ug', label: 'Vitamin A', unit: 'mcg', warn: 10000 },
  { key: 'vitamin_c_mg', label: 'Vitamin C', unit: 'mg', warn: 5000 },
  { key: 'vitamin_d_ug', label: 'Vitamin D', unit: 'mcg', warn: 1250 },
  { key: 'vitamin_b12_ug', label: 'Vitamin B12', unit: 'mcg', warn: 5000 },
  { key: 'folate_ug', label: 'Folate', unit: 'mcg', warn: 2000 },
  { key: 'saturated_fat_g', label: 'Saturated fat', unit: 'g', warn: 200 },
  { key: 'sugars_g', label: 'Sugars', unit: 'g', warn: 500 },
];
const MICRO_LABEL = MICRO_SPEC.reduce((m, s) => { m[s.key] = s; return m; }, {});
const MACRO_WARN = { kcal: 10000, protein_g: 1000, fat_g: 1000, carb_g: 1000, fiber_g: 1000, soluble_fiber_g: 1000 };
const MACRO_LABEL = { kcal: 'kcal', protein_g: 'protein', fat_g: 'fat', carb_g: 'carbs', fiber_g: 'fiber', soluble_fiber_g: 'soluble fiber' };

// Non-blocking sane-range warnings — catch unit/typo errors, never reject.
function manualWarnings(raw) {
  const w = [];
  Object.keys(MACRO_WARN).forEach((k) => {
    if (num(raw[k]) > MACRO_WARN[k]) w.push(MACRO_LABEL[k] + ' ' + num(raw[k]) + ' looks high (> ' + MACRO_WARN[k] + ')');
  });
  const micros = raw.micros || {};
  MICRO_SPEC.forEach((s) => {
    const v = micros[s.key];
    if (v != null && String(v) !== '' && num(v) > s.warn)
      w.push(s.label + ' ' + num(v) + ' ' + s.unit + ' looks high (> ' + s.warn + ' ' + s.unit + ') — check the unit');
  });
  return w;
}

// Core (DOM-free, testable): build + append a manual item to the selected day.
function addManualEntry(raw) {
  if (!raw || !raw.name || String(raw.name).trim() === '') return { ok: false, error: 'Name required' };
  const warnings = manualWarnings(raw);
  const item = normalizeItem(Object.assign({}, raw, { source: 'manual' }), true);
  const day = curDay(); if (!day) return { ok: false, error: 'No current day' };
  if (day.status === 'complete') day.status = 'in_progress';   // reopen (D9 / D8-1)
  day.items.push(item);
  Store.saveState(APP_STATE); refresh();
  return { ok: true, warnings: warnings, item: item };
}

let _presetSeq = 0;
function newPresetId() { _presetSeq++; return 'p' + Date.now().toString(36) + '_' + _presetSeq; }

// Core (DOM-free, testable): save a preset from raw form values.
function saveManualPreset(raw, portion) {
  if (!raw || !raw.name || String(raw.name).trim() === '') return { ok: false, error: 'Name required' };
  const item = normalizeItem(Object.assign({}, raw, { source: 'preset' }), true);
  const preset = {
    id: newPresetId(), name: item.name, meal: item.meal, confidence: item.confidence,
    kcal: item.kcal, protein_g: item.protein_g, fat_g: item.fat_g, carb_g: item.carb_g,
    fiber_g: item.fiber_g, soluble_fiber_g: item.soluble_fiber_g,
  };
  if (item.micros) preset.micros = item.micros;
  if (portion && String(portion).trim()) preset.portion = String(portion).trim();   // descriptive label only (fork A)
  if (!Array.isArray(APP_STATE.settings.presets)) APP_STATE.settings.presets = [];
  APP_STATE.settings.presets.push(preset);
  Store.saveState(APP_STATE); refresh();
  return { ok: true, preset: preset };
}

// Log a preset as a fresh copy (source preset) — a copy, never a reference (D9).
function logPreset(id) {
  const presets = (APP_STATE.settings && APP_STATE.settings.presets) || [];
  const p = presets.find((x) => x.id === id);
  if (!p) return { ok: false };
  const item = normalizeItem({
    name: p.name, meal: p.meal, time: nowTime(), confidence: p.confidence,
    kcal: p.kcal, protein_g: p.protein_g, fat_g: p.fat_g, carb_g: p.carb_g,
    fiber_g: p.fiber_g, soluble_fiber_g: p.soluble_fiber_g, source: 'preset', micros: p.micros,
  }, true);
  const day = curDay(); if (!day) return { ok: false };
  if (day.status === 'complete') day.status = 'in_progress';
  day.items.push(item);
  Store.saveState(APP_STATE); refresh();
  toast('Logged ' + p.name);
  return { ok: true, item: item };
}
// Delete a preset only — already-logged copies are untouched (D9).
function deletePreset(id) {
  if (!APP_STATE.settings.presets) return;
  APP_STATE.settings.presets = APP_STATE.settings.presets.filter((x) => x.id !== id);
  Store.saveState(APP_STATE); refresh();
}

// ---- OpenFoodFacts lookup + micros mapping + product cache (D13, D14) ------
// Data-layer half of the scan path: a DOM-free, synchronously-testable core
// (mapOffProduct / scalePortion / buildScanItem / finishLookup / ProductCache)
// behind a thin async fetch edge. Camera (getUserMedia) is a later slice; the
// manual barcode field is this slice's camera-free trigger.
const OFF_BASE   = 'https://world.openfoodfacts.org/api/v2/product/';
const OFF_FIELDS = 'product_name,brands,quantity,serving_size,serving_quantity,nutriments';
const OFF_UA     = 'HealthTracker/' + APP_VERSION + ' (https://github.com/Githor404/healthtracker)';

const PRODUCTS_KEY          = 'healthtracker-products';   // D13: capped localStorage mirror
const PRODUCT_CACHE_VERSION = 1;                          // bump when mapOffProduct's output shape changes

// OFF normalizes every nutriment _100g to grams, reported in <key>_unit (verified
// 2026-07-16). Convert from the REPORTED unit to the canonical target — the factor
// is derived, never hardcoded — defaulting to grams when _unit is absent.
function offUnitToG(u) {
  u = String(u == null ? 'g' : u).trim().toLowerCase();
  if (u === 'mg') return 1e-3;
  if (u === 'ug' || u === 'mcg' || u.charCodeAt(0) === 0xb5) return 1e-6;   // ug / mcg / micro-sign (0xB5) g
  if (u === 'kg') return 1e3;
  return 1;   // g, or unknown -> grams (OFF's _100g normalization)
}
const G_TO_TARGET = { g: 1, mg: 1e3, ug: 1e6 };
function offToTarget(value, srcUnit, targetUnit) {
  return clampNonNeg(num(value) * offUnitToG(srcUnit) * (G_TO_TARGET[targetUnit] || 1));
}

// energy: prefer the kcal key; else convert kJ -> kcal.
function offEnergyKcal(n) {
  if (n['energy-kcal_100g'] != null) return clampNonNeg(n['energy-kcal_100g']);
  if (n['energy_100g'] != null)      return clampNonNeg(num(n['energy_100g']) / 4.184);
  return 0;
}

// OFF nutriment base -> canonical micro key + target unit. Sodium is special
// (sodium OR salt-derived) and handled outside this table.
const OFF_MICRO_MAP = [
  { off: 'potassium',     key: 'potassium_mg',    unit: 'mg' },
  { off: 'calcium',       key: 'calcium_mg',      unit: 'mg' },
  { off: 'iron',          key: 'iron_mg',         unit: 'mg' },
  { off: 'magnesium',     key: 'magnesium_mg',    unit: 'mg' },
  { off: 'zinc',          key: 'zinc_mg',         unit: 'mg' },
  { off: 'cholesterol',   key: 'cholesterol_mg',  unit: 'mg' },
  { off: 'vitamin-a',     key: 'vitamin_a_ug',    unit: 'ug' },
  { off: 'vitamin-c',     key: 'vitamin_c_mg',    unit: 'mg' },
  { off: 'vitamin-d',     key: 'vitamin_d_ug',    unit: 'ug' },
  { off: 'vitamin-b12',   key: 'vitamin_b12_ug',  unit: 'ug' },
  { off: 'vitamin-b9',    key: 'folate_ug',       unit: 'ug' },   // OFF calls folate vitamin-b9
  { off: 'saturated-fat', key: 'saturated_fat_g', unit: 'g'  },
  { off: 'sugars',        key: 'sugars_g',        unit: 'g'  },
];

// Absence != zero: a micro is included ONLY when OFF returns its _100g key.
function mapOffMicros(n) {
  const micros = {};
  if (n['sodium_100g'] != null && n['sodium_100g'] !== '')
    micros.sodium_mg = offToTarget(n['sodium_100g'], n['sodium_unit'], 'mg');
  else if (n['salt_100g'] != null && n['salt_100g'] !== '')
    micros.sodium_mg = offToTarget(n['salt_100g'], n['salt_unit'], 'mg') / 2.5;   // salt -> sodium, single source
  OFF_MICRO_MAP.forEach((m) => {
    const v = n[m.off + '_100g'];
    if (v != null && v !== '') micros[m.key] = offToTarget(v, n[m.off + '_unit'], m.unit);
  });
  return micros;
}

// OFF product JSON -> normalized per-100g record. Trust boundary crossed once
// here: numbers coerced + clamped, strings kept raw (escaped at render), micros
// absence-preserving. cacheVersion-stamped (D13).
function mapOffProduct(json, barcode) {
  const p = (json && json.product && typeof json.product === 'object') ? json.product : {};
  const n = (p.nutriments && typeof p.nutriments === 'object' && !Array.isArray(p.nutriments)) ? p.nutriments : {};
  const per100 = {
    kcal:            offEnergyKcal(n),
    protein_g:       clampNonNeg(n['proteins_100g']),
    fat_g:           clampNonNeg(n['fat_100g']),
    carb_g:          clampNonNeg(n['carbohydrates_100g']),
    fiber_g:         clampNonNeg(n['fiber_100g']),
    soluble_fiber_g: clampNonNeg(n['soluble-fiber_100g']),   // usually absent -> 0 (contract: always present)
  };
  const sq = num(p.serving_quantity);
  const rec = {
    barcode:      String(barcode == null ? '' : barcode),
    name:         String(p.product_name == null ? '' : p.product_name),
    brands:       String(p.brands == null ? '' : p.brands),
    quantity:     String(p.quantity == null ? '' : p.quantity),
    serving_size: String(p.serving_size == null ? '' : p.serving_size),
    serving_g:    sq > 0 ? sq : 0,
    per100:       per100,
    cacheVersion: PRODUCT_CACHE_VERSION,
  };
  const micros = mapOffMicros(n);
  if (Object.keys(micros).length) rec.micros = micros;   // absence -> omit the key entirely
  return rec;
}

// Portion math: macros AND micros scale by the one factor; absent micros stay absent.
function portionGrams(rec, mode, customGrams) {
  if (mode === 'per_serving') return rec.serving_g > 0 ? rec.serving_g : 100;   // fallback if no serving
  if (mode === 'custom')      return clampNonNeg(customGrams);
  return 100;   // per_100g
}
function scalePortion(rec, mode, customGrams) {
  const grams = portionGrams(rec, mode, customGrams);
  const f = grams / 100;
  const out = {
    grams:           grams,
    kcal:            rec.per100.kcal * f,
    protein_g:       rec.per100.protein_g * f,
    fat_g:           rec.per100.fat_g * f,
    carb_g:          rec.per100.carb_g * f,
    fiber_g:         rec.per100.fiber_g * f,
    soluble_fiber_g: rec.per100.soluble_fiber_g * f,
  };
  if (rec.micros) {
    const m = {};
    Object.keys(rec.micros).forEach((k) => { m[k] = rec.micros[k] * f; });   // absent key never appears
    out.micros = m;
  }
  return out;
}

// A scanned item is a labeled source (honesty rule): source 'scan', confidence
// 'measured', barcode retained. Runs through normalizeItem -> contract-clean.
function buildScanItem(rec, mode, customGrams, meal) {
  const s = scalePortion(rec, mode, customGrams);
  return normalizeItem({
    name: rec.name || ('Product ' + rec.barcode),
    meal: MEALS.indexOf(meal) >= 0 ? meal : 'snack',
    time: nowTime(),
    kcal: s.kcal, protein_g: s.protein_g, fat_g: s.fat_g, carb_g: s.carb_g,
    fiber_g: s.fiber_g, soluble_fiber_g: s.soluble_fiber_g,
    confidence: 'measured', source: 'scan', barcode: rec.barcode,
    notes: 'scanned ' + rDisp(s.grams) + ' g',
    micros: s.micros,
  }, true);
}
function logScanItem(rec, mode, customGrams, meal) {
  const item = buildScanItem(rec, mode, customGrams, meal);
  const day = curDay(); if (!day) return { ok: false };
  if (day.status === 'complete') day.status = 'in_progress';   // reopen (same rule as manual/ingest)
  day.items.push(item);
  Store.saveState(APP_STATE); refresh();
  return { ok: true, item: item };
}

// Product cache: capped localStorage mirror, LRU, benign on write failure (D13).
let _cacheMax = 500, _cacheBytes = 512 * 1024;   // overridable via ProductCache._setCaps (test seam)
const ProductCache = (() => {
  function readAll() {
    const raw = Store.readRaw(PRODUCTS_KEY);
    if (!raw) return {};
    try { const o = JSON.parse(raw); return (o && typeof o === 'object' && !Array.isArray(o)) ? o : {}; }
    catch (e) { return {}; }
  }
  function writeAll(map) { return Store.writeAux(PRODUCTS_KEY, JSON.stringify(map)); }   // false = benign no-op
  function oldestKey(map) { return Object.keys(map).sort((a, b) => (map[a].lastAccess || 0) - (map[b].lastAccess || 0))[0]; }
  function evict(map) {
    while (Object.keys(map).length > _cacheMax) delete map[oldestKey(map)];
    while (Object.keys(map).length > 1 && JSON.stringify(map).length > _cacheBytes) delete map[oldestKey(map)];
  }
  return {
    get(barcode) {
      const map = readAll();
      const rec = map[barcode];
      if (!rec || rec.cacheVersion !== PRODUCT_CACHE_VERSION) return null;   // miss on absent / stale shape
      rec.lastAccess = Date.now();
      map[barcode] = rec; writeAll(map);   // best-effort LRU bump (failure ignored)
      return rec;
    },
    put(rec) {
      if (!rec || !rec.barcode) return false;
      const map = readAll();
      rec.fetchedAt = rec.fetchedAt || new Date().toISOString();
      rec.lastAccess = Date.now();
      map[rec.barcode] = rec;
      evict(map);
      return writeAll(map);
    },
    has(barcode) { return Object.prototype.hasOwnProperty.call(readAll(), barcode); },
    count() { return Object.keys(readAll()).length; },
    _all: readAll,
    _setCaps(max, bytes) { _cacheMax = max; _cacheBytes = bytes; },   // test seam
    _reset() { _cacheMax = 500; _cacheBytes = 512 * 1024; Store.removeAux(PRODUCTS_KEY); },
  };
})();

// Thin async fetch edge + a pure, synchronous decision core (finishLookup).
function guardBarcode(bc) {
  return /^\d{8,14}$/.test(bc) ? null : { found: false, barcode: bc, error: 'Enter an 8-14 digit barcode.' };
}
function offURL(barcode) {
  return OFF_BASE + encodeURIComponent(barcode) + '.json?fields=' + encodeURIComponent(OFF_FIELDS) +
    '&app_name=HealthTracker&app_version=' + encodeURIComponent(APP_VERSION);
}
// OFF signals an unknown barcode with HTTP 404 (NOT 200 + status:0), so a 404 is
// a NOT-FOUND result, not a network failure. Only genuine failures (5xx / 429 /
// fetch reject) become 'offline'. Pure seam so the status->outcome mapping is
// testable — the live path the OF16 synthetic test could never reach (D14 amend).
function offStatusKind(status) {
  if (status === 404) return 'missing';
  if (status >= 200 && status < 300) return 'ok';
  return 'error';
}
function fetchOff(barcode) {
  // Header set defensively — browsers drop User-Agent (Forbidden Header); the
  // app_name/app_version query params (offURL) are the browser-safe identity (D14).
  return fetch(offURL(barcode), { headers: { 'User-Agent': OFF_UA } }).then((res) => {
    const kind = offStatusKind(res.status);
    if (kind === 'missing') return { status: 0 };            // 404 -> finishLookup 'missing' branch
    if (kind === 'error') throw new Error('HTTP ' + res.status);
    return res.json();
  });
}
// Pure, synchronous decision from a settled fetch outcome — the tested unit.
// outcome = { ok:true, json } | { ok:false } (network failure / offline).
function finishLookup(bc, outcome) {
  if (!outcome || !outcome.ok) {
    const cached = ProductCache.get(bc);
    return cached ? { found: true, record: cached, barcode: bc, source: 'cache' }
      : { found: false, barcode: bc, offline: true, error: "Can't reach OpenFoodFacts (are you online?) — retry, or enter the details manually." };
  }
  const json = outcome.json;
  if (!json || json.status === 0 || !json.product)
    return { found: false, barcode: bc, source: 'missing', error: 'Not in OpenFoodFacts — enter the details manually.' };
  const rec = mapOffProduct(json, bc);
  ProductCache.put(rec);
  return { found: true, record: rec, barcode: bc, source: 'network' };
}
// Async orchestrator (thin): guard -> cache-first -> fetch -> finishLookup.
function lookupBarcode(barcode, opts) {
  opts = opts || {};
  const bc = String(barcode == null ? '' : barcode).trim();
  const bad = guardBarcode(bc); if (bad) return Promise.resolve(bad);
  if (!opts.refresh) { const c = ProductCache.get(bc); if (c) return Promise.resolve({ found: true, record: c, barcode: bc, source: 'cache' }); }
  const fetcher = opts.fetchImpl || fetchOff;
  return Promise.resolve().then(() => fetcher(bc))
    .then((json) => finishLookup(bc, { ok: true, json: json }))
    .catch(() => finishLookup(bc, { ok: false }));
}

// ---- scan DOM (barcode lookup, portion picker, add) -----------------------
let SCAN = null;   // transient UI state: {found:true, record, mode, grams, meal, source} | {found:false, barcode, error}

// One lookup path for BOTH the manual button and the camera handoff: show the
// "Looking up" pending state and scroll it into view, so a scan visibly advances
// (no silent gap that reads as "it didn't fire"), then lookup -> render.
function runLookup(code, opts) {
  const host = document.getElementById('scanResult');
  if (host) {
    host.innerHTML = `<div class="note" style="margin-top:8px">Looking up ${esc(code)}…</div>`;
    if (host.scrollIntoView) host.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
  lookupBarcode(code, opts || {}).then(applyLookup);
}
function doBarcodeLookup(isRefresh) {
  const box = document.getElementById('scanBarcode');
  runLookup(box ? box.value.trim() : '', { refresh: !!isRefresh });
}
function applyLookup(res) {
  // Unified SCAN state (found | not-found) so renderScan owns both and a refresh
  // (e.g. after saving a price) re-renders correctly instead of clearing it.
  if (!res.found) { SCAN = { found: false, barcode: res.barcode || '', error: res.error || 'Lookup failed.' }; renderScan(); return; }
  SCAN = { found: true, record: res.record, mode: res.record.serving_g > 0 ? 'per_serving' : 'per_100g', grams: 100, meal: 'snack', source: res.source };
  renderScan();
}
function scanSummaryHTML(s) {
  let h = `<div class="sumrow"><span>at ${esc(rDisp(s.grams))} g</span><span><b>${esc(rDisp(s.kcal))}</b> kcal</span></div>` +
    `<div class="sumrow"><span>P / F / C</span><span>${esc(rDisp(s.protein_g))} / ${esc(rDisp(s.fat_g))} / ${esc(rDisp(s.carb_g))} g</span></div>` +
    `<div class="sumrow"><span>fiber</span><span>${esc(rDisp(s.fiber_g))} g (${esc(rDisp(s.soluble_fiber_g))} sol)</span></div>`;
  if (s.micros) {
    Object.keys(s.micros).forEach((k) => {
      const spec = MICRO_LABEL[k];
      h += `<div class="sumrow"><span>${esc(spec ? spec.label : k)}</span><span>${esc(rDisp(s.micros[k]))} ${esc(spec ? spec.unit : '')}</span></div>`;
    });
  } else {
    h += `<div class="sumrow"><span class="scanmuted">no labeled micronutrients on this product</span></div>`;
  }
  return h;
}
function renderScan() {
  const host = document.getElementById('scanResult'); if (!host) return;
  if (!SCAN) { host.innerHTML = ''; return; }
  if (!SCAN.found) {
    const valid = /^\d{8,14}$/.test(SCAN.barcode);
    let h = `<div class="scanmsg"><div class="warn" style="padding:6px 0">${esc(SCAN.error)}</div>` +
      (SCAN.barcode ? `<div class="note" style="margin-top:0">Barcode <code>${esc(SCAN.barcode)}</code> kept. <a href="#" onclick="prefillManual('${esc(SCAN.barcode)}');return false">Add it manually →</a></div>` : '') +
      `</div>`;
    if (valid) h += priceCaptureHTML(SCAN.barcode, SCAN.barcode);   // price capture allowed for not-found (D18 nod)
    host.innerHTML = h;
    return;
  }
  const rec = SCAN.record, s = scalePortion(rec, SCAN.mode, SCAN.grams);
  const hasServe = rec.serving_g > 0;
  let h = `<div class="scanhead"><b>${esc(rec.name || ('Product ' + rec.barcode))}</b>` +
    (rec.brands ? ` <span class="scanbrand">${esc(rec.brands)}</span>` : '') +
    ` <small class="scansrc">${esc(SCAN.source === 'cache' ? 'cached' : 'openfoodfacts')}</small></div>`;
  h += `<div class="primsel scanmodes">` +
    `<button class="${SCAN.mode === 'per_serving' ? 'on' : ''}" ${hasServe ? '' : 'disabled'} onclick="setScanMode('per_serving')">serving${hasServe ? ' · ' + esc(rDisp(rec.serving_g)) + ' g' : ''}</button>` +
    `<button class="${SCAN.mode === 'per_100g' ? 'on' : ''}" onclick="setScanMode('per_100g')">100 g</button>` +
    `<button class="${SCAN.mode === 'custom' ? 'on' : ''}" onclick="setScanMode('custom')">custom</button></div>`;
  if (SCAN.mode === 'custom')
    h += `<label>Grams</label><input id="scanGrams" type="number" inputmode="decimal" value="${esc(SCAN.grams)}" oninput="setScanGrams(this.value)">`;
  h += `<div class="summary" id="scanSummary">${scanSummaryHTML(s)}</div>`;
  h += `<div class="row" style="align-items:flex-end;margin-top:10px">` +
    `<div><label>Meal</label><select id="scanMeal" onchange="setScanMeal(this.value)">` +
    MEALS.filter((m) => m !== 'supplement').map((m) => `<option value="${esc(m)}"${m === SCAN.meal ? ' selected' : ''}>${esc(m)}</option>`).join('') +
    `</select></div>` +
    `<div><button class="btn primary" style="width:100%" onclick="addScanToDay()">Add to day</button></div></div>`;
  h += priceCaptureHTML(rec.barcode, rec.name);   // D18: optional price capture, inline
  h += `<button class="linklike" onclick="doBarcodeLookup(true)">↻ Refresh from OpenFoodFacts</button>`;
  host.innerHTML = h;
}
function setScanMode(m) { if (!SCAN || !SCAN.found) return; SCAN.mode = m; renderScan(); }
function setScanGrams(v) {
  if (!SCAN || !SCAN.found) return;
  SCAN.grams = clampNonNeg(v);
  const el = document.getElementById('scanSummary');
  if (el) el.innerHTML = scanSummaryHTML(scalePortion(SCAN.record, SCAN.mode, SCAN.grams));   // update preview, keep focus
}
function setScanMeal(m) { if (SCAN && SCAN.found) SCAN.meal = m; }
function addScanToDay() {
  if (!SCAN || !SCAN.found) return;
  const r = logScanItem(SCAN.record, SCAN.mode, SCAN.grams, SCAN.meal);
  if (r.ok) toast('Added ' + (SCAN.record.name || SCAN.record.barcode));
}
function prefillManual(bc) {
  const name = document.getElementById('maName');
  if (name && name.scrollIntoView) name.scrollIntoView({ behavior: 'smooth', block: 'center' });
  if (name) name.focus();
  toast('Barcode ' + bc + ' — add the product manually');
}

// ---- camera scanner: two-tier detection + ZXing fallback (D15) -------------
// Pure decision logic below is committed (CAM cases); the live getUserMedia /
// detection flow is on-device attested (A1-A7). iOS Safari + Firefox have no
// BarcodeDetector -> ZXing is their ONLY scanner, so it is runtime-cached (D6
// amendment, sw.js). ZXING is the single source of truth for version/url/hash;
// tests/check-zxing.sh fails on a stale SRI hash.
const ZXING = {
  version: '0.23.0',
  url: 'https://cdn.jsdelivr.net/npm/@zxing/library@0.23.0/umd/index.min.js',
  integrity: 'sha384-0ASr5PEWAMtTnWsn0PzKmioHVDA4+QqFiJr94io/0DCrGP6E1gRAmbO6O8y5WZW9',
  global: 'ZXing',
};
const SCAN_FORMATS = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'itf'];   // retail 1D, no 2D
const SCAN_DEBOUNCE_MS = 1500;

// Pure: precondition -> which path to offer. Only 'ok' renders the Scan button.
function cameraPrecondition(env) {
  env = env || {};
  const secure = ('secureContext' in env) ? env.secureContext
    : (typeof window !== 'undefined' && window.isSecureContext);
  const hasGUM = ('hasGetUserMedia' in env) ? env.hasGetUserMedia
    : !!(typeof navigator !== 'undefined' && navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  if (!secure) return 'insecure';
  if (!hasGUM) return 'unsupported';
  return 'ok';
}
// Pure: native BarcodeDetector if present, else the ZXing fallback.
function detectorTier(env) {
  env = env || {};
  const has = ('hasBarcodeDetector' in env) ? env.hasBarcodeDetector
    : (typeof window !== 'undefined' && 'BarcodeDetector' in window);
  return has ? 'native' : 'zxing';
}
// Pure: err.name -> message. EVERY message ends in the literal manual escape
// hatch (the manual field is visible in the same card — D15 ruling).
function cameraErrorMessage(err) {
  const tail = ' — enter the barcode by hand below.';
  switch ((err && err.name) || '') {
    case 'NotAllowedError': case 'PermissionDeniedError':
      return 'Camera permission denied — enable it in your browser settings, or enter the barcode by hand below.';
    case 'NotFoundError': case 'DevicesNotFoundError': case 'OverconstrainedError': case 'ConstraintNotSatisfiedError':
      return 'No camera found' + tail;
    case 'NotReadableError': case 'TrackStartError':
      return 'The camera is in use by another app — close it and retry, or enter the barcode by hand below.';
    case 'SecurityError':
      return 'Camera blocked on an insecure page' + tail;
    case 'TypeError':
      return "This browser can't open the camera here" + tail;
    default:
      return 'Could not open the camera' + tail;
  }
}
// Pure: desired formats intersected with what the detector supports.
function intersectFormats(desired, supported) {
  const sup = supported || [];
  return desired.filter((f) => sup.indexOf(f) >= 0);
}
// Pure (injected clock): time-based ~1.5 s debounce. Guards the detection burst
// before teardown; a successful scan auto-stops the camera anyway.
function scanGate(state, code, nowMs) {
  state = state || { until: 0 };
  if (nowMs < state.until) return { accept: false, state: state };
  return { accept: true, state: { until: nowMs + SCAN_DEBOUNCE_MS } };
}
// Idempotent teardown: safe to call twice. Stops tracks, cancels loops/timers,
// resets the ZXing reader, detaches the stream.
function stopScanner(session) {
  if (!session) return;
  if (session.raf) { try { cancelAnimationFrame(session.raf); } catch (e) {} session.raf = 0; }
  if (session.timer) { clearTimeout(session.timer); session.timer = 0; }
  if (session.reader && session.reader.reset) { try { session.reader.reset(); } catch (e) {} }
  session.reader = null;
  if (session.stream) { try { session.stream.getTracks().forEach((t) => t.stop()); } catch (e) {} session.stream = null; }
  if (session.video) { try { session.video.srcObject = null; } catch (e) {} }
  session.active = false;
}

// Lazy-load ZXing from the pinned CDN with SRI + CORS (D15). 100 ms poll / ~6 s
// timeout (scanner spec). Exposed as a seam so the offline gate can prime the
// runtime cache without a camera. Cached in healthtracker-runtime by the SW.
let _zxingPromise = null;
function loadZXing() {
  if (typeof window !== 'undefined' && window.ZXing) return Promise.resolve(window.ZXing);
  if (_zxingPromise) return _zxingPromise;
  _zxingPromise = new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = ZXING.url; s.crossOrigin = 'anonymous'; s.integrity = ZXING.integrity; s.async = true;
    let waited = 0;
    const poll = setInterval(() => {
      if (window.ZXing) { clearInterval(poll); resolve(window.ZXing); }
      else if ((waited += 100) >= 6000) { clearInterval(poll); _zxingPromise = null; reject(new Error('ZXing load timeout')); }
    }, 100);
    s.onerror = () => { clearInterval(poll); _zxingPromise = null; reject(new Error('ZXing load failed (integrity/network)')); };
    document.head.appendChild(s);
  });
  return _zxingPromise;
}

let SCAN_SESSION = null;
const scanConstraints = { video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 } } };

// A valid detection: debounce -> digit hygiene -> vibrate -> auto-stop -> lookup.
function onScanCode(session, raw) {
  const g = scanGate(session.gate, String(raw), Date.now());
  session.gate = g.state;
  if (!g.accept) return;
  const code = String(raw).trim();
  if (!/^\d{8,14}$/.test(code)) return;                 // hygiene (Slice-1 guard shape)
  try { if (navigator.vibrate) navigator.vibrate(80); } catch (e) {}
  stopScanner(session); showScanView(false);
  const box = document.getElementById('scanBarcode'); if (box) box.value = code;
  runLookup(code);                                     // shared path: visible pending + scroll (auto-advance)
}

function runNativeDetect(session, video) {
  const start = (formats) => {
    let det;
    try { det = new window.BarcodeDetector({ formats: formats.length ? formats : SCAN_FORMATS }); }
    catch (e) { renderScanCamMessage(cameraErrorMessage(e)); stopScanner(session); showScanView(false); return; }
    const tick = () => {
      if (!session.active) return;
      if (video.readyState >= 2) {                       // readyState-gated (HAVE_CURRENT_DATA)
        det.detect(video).then((codes) => {
          if (codes && codes.length && codes[0].rawValue) onScanCode(session, codes[0].rawValue);
        }).catch(() => {});
      }
      session.raf = requestAnimationFrame(tick);
    };
    session.raf = requestAnimationFrame(tick);
  };
  (window.BarcodeDetector.getSupportedFormats
    ? window.BarcodeDetector.getSupportedFormats().then((sup) => intersectFormats(SCAN_FORMATS, sup)).catch(() => SCAN_FORMATS)
    : Promise.resolve(SCAN_FORMATS)
  ).then(start);
}

function runZxingDetect(session, video) {
  loadZXing().then((ZX) => {
    if (!session.active) return;
    const hints = new Map();
    try {
      hints.set(ZX.DecodeHintType.POSSIBLE_FORMATS, [
        ZX.BarcodeFormat.EAN_13, ZX.BarcodeFormat.EAN_8, ZX.BarcodeFormat.UPC_A,
        ZX.BarcodeFormat.UPC_E, ZX.BarcodeFormat.CODE_128, ZX.BarcodeFormat.ITF,
      ]);
    } catch (e) {}
    const reader = new ZX.BrowserMultiFormatReader(hints);
    session.reader = reader;
    reader.decodeFromConstraints(scanConstraints, video, (result, err) => {
      if (result && result.text) onScanCode(session, result.text);
    }).catch((e) => { renderScanCamMessage(cameraErrorMessage(e)); stopScanner(session); showScanView(false); });
  }).catch(() => {
    renderScanCamMessage('Barcode scanner failed to load — enter the barcode by hand below.');
    stopScanner(session); showScanView(false);
  });
}

// Live camera flow (attested A1-A7). Native tier owns the stream; the ZXing tier
// lets ZXing acquire it via decodeFromConstraints (single stream per tier).
function startScan() {
  const pc = cameraPrecondition();
  if (pc !== 'ok') {
    renderScanCamMessage(pc === 'insecure'
      ? 'Camera needs a secure (https) connection — enter the barcode by hand below.'
      : "This browser doesn't support camera capture — enter the barcode by hand below.");
    return;
  }
  renderScanCamMessage('');
  showScanView(true);
  const video = document.getElementById('scanVideo');
  const session = { active: true, gate: { until: 0 } };
  SCAN_SESSION = session;
  session.video = video;
  if (detectorTier() === 'zxing') { runZxingDetect(session, video); return; }
  navigator.mediaDevices.getUserMedia(scanConstraints).then((stream) => {
    if (!session.active) { stream.getTracks().forEach((t) => t.stop()); return; }
    session.stream = stream; video.srcObject = stream;
    const p = video.play(); if (p && p.catch) p.catch(() => {});
    runNativeDetect(session, video);
  }).catch((e) => { stopScanner(session); showScanView(false); renderScanCamMessage(cameraErrorMessage(e)); });
}
function cancelScan() { stopScanner(SCAN_SESSION); showScanView(false); }

function showScanView(on) {
  const v = document.getElementById('scanCamera');
  if (v) v.style.display = on ? 'block' : 'none';
  const btn = document.getElementById('scanOpenBtn');
  if (btn) btn.style.display = on ? 'none' : '';
}
function renderScanCamMessage(msg) {
  const el = document.getElementById('scanCamMsg');
  if (el) el.innerHTML = msg ? `<div class="warn" style="padding:6px 0">${esc(msg)}</div>` : '';
}
// Render the Scan button only when the camera is actually usable (precondition
// ok). Otherwise the manual field is the whole card — the escape hatch is default.
function renderScanButton() {
  const host = document.getElementById('scanOpenBtn');
  if (!host) return;
  host.style.display = (cameraPrecondition() === 'ok') ? '' : 'none';
}

// ---- personal price capture + comparison (D18) ----------------------------
// priceLog is INDEPENDENT of the food log (a product can be price-checked
// without being eaten). Personal only; nearby/community prices are Phase 3.

// Append a price entry. Never creates/touches a day or item. Duplicates append
// (accept, like D8/3). Remembers the currency as settings.currency (last-used).
function addPriceEntry(barcode, name, raw) {
  const bc = String(barcode == null ? '' : barcode).trim();
  if (!/^\d{8,14}$/.test(bc)) return { ok: false, error: 'Need a valid barcode.' };
  raw = raw || {};
  if (raw.price == null || String(raw.price).trim() === '') return { ok: false, error: 'Enter a price.' };
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(raw.date)) ? String(raw.date) : localDate();
  const entry = {
    price: clampNonNeg(raw.price),
    currency: String(raw.currency == null ? '' : raw.currency).trim(),
    store: String(raw.store == null ? '' : raw.store).trim(),
    date: date,
  };
  if (!APP_STATE.priceLog || typeof APP_STATE.priceLog !== 'object') APP_STATE.priceLog = {};
  const bucket = APP_STATE.priceLog[bc] || { name: String(name == null ? '' : name), entries: [] };
  if (!bucket.name && name) bucket.name = String(name);
  bucket.entries.push(entry);
  APP_STATE.priceLog[bc] = bucket;
  if (entry.currency) APP_STATE.settings.currency = entry.currency;   // remember last-used
  Store.saveState(APP_STATE); refresh();
  return { ok: true, entry: entry };
}

// Grouped by (store, currency) so a trend is NEVER computed across mismatched
// currencies (D18 ruling). Latest per group by date; trend = latest vs previous
// within the SAME group.
function priceComparison(priceLog, barcode) {
  const bucket = (priceLog && priceLog[barcode]) || null;
  if (!bucket || !Array.isArray(bucket.entries) || !bucket.entries.length) return { name: bucket ? bucket.name : '', groups: [] };
  const byKey = {};
  bucket.entries.forEach((e) => {
    const store = String(e.store == null ? '' : e.store);
    const currency = String(e.currency == null ? '' : e.currency);
    const k = store + '\u0000' + currency;   // NUL-joined so store/currency can't collide
    (byKey[k] = byKey[k] || { store: store, currency: currency, entries: [] }).entries.push({ price: num(e.price), date: String(e.date || '') });
  });
  const groups = Object.keys(byKey).map((k) => {
    const g = byKey[k];
    g.entries.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));   // oldest -> newest
    const n = g.entries.length, latest = g.entries[n - 1], prev = n >= 2 ? g.entries[n - 2] : null;
    const trend = !prev ? 'none' : (latest.price > prev.price ? 'up' : (latest.price < prev.price ? 'down' : 'flat'));
    return { store: g.store, currency: g.currency, latest: latest.price, latestDate: latest.date, count: n, trend: trend };
  });
  groups.sort((a, b) => (a.store < b.store ? -1 : a.store > b.store ? 1 : (a.currency < b.currency ? -1 : a.currency > b.currency ? 1 : 0)));
  return { name: bucket.name, groups: groups };
}

// Distinct store names across the whole priceLog (own history -> autocomplete).
function storeHistory(priceLog) {
  const set = {};
  Object.keys(priceLog || {}).forEach((bc) => {
    const b = priceLog[bc];
    if (b && Array.isArray(b.entries)) b.entries.forEach((e) => { const s = String(e.store == null ? '' : e.store).trim(); if (s) set[s] = 1; });
  });
  return Object.keys(set).sort();
}

// Inline optional price field + comparison (escaped). PRICE_CTX carries the
// barcode/name for saveScanPrice (works for found AND valid not-found barcodes).
let PRICE_CTX = null;
function priceCaptureHTML(barcode, name) {
  PRICE_CTX = { barcode: barcode, name: name || '' };
  const cur = (APP_STATE.settings && APP_STATE.settings.currency) || '';
  const stores = storeHistory(APP_STATE.priceLog).map((st) => `<option value="${esc(st)}"></option>`).join('');
  let h = `<div class="pricecap"><div class="sumhead">Price (optional)</div>`
    + `<div class="row" style="align-items:flex-end">`
    + `<div style="flex:2"><label>Price</label><input id="scanPrice" type="number" inputmode="decimal"></div>`
    + `<div style="flex:1"><label>Cur.</label><input id="scanCurrency" value="${esc(cur)}" placeholder="USD"></div>`
    + `<div style="flex:2"><label>Store</label><input id="scanStore" list="storeList" placeholder="store"><datalist id="storeList">${stores}</datalist></div>`
    + `</div><button class="btn" style="width:100%;margin-top:6px" onclick="saveScanPrice()">Save price</button></div>`;
  const cmp = priceComparison(APP_STATE.priceLog, barcode);
  if (cmp.groups.length) {
    h += `<div class="summary"><div class="sumhead">Your prices</div>` + cmp.groups.map((g) => {
      const arrow = g.trend === 'up' ? '↑' : g.trend === 'down' ? '↓' : (g.trend === 'flat' ? '→' : '');
      return `<div class="sumrow"><span>${esc(g.store || '(no store)')}${g.currency ? ' · ' + esc(g.currency) : ''}</span>`
        + `<span>${esc(rDisp(g.latest))} ${arrow} <small>${esc(g.count)}x</small></span></div>`;
    }).join('') + `</div>`;
  }
  return h;
}
function saveScanPrice() {
  if (!PRICE_CTX) return;
  const g = (id) => { const el = document.getElementById(id); return el ? el.value : ''; };
  const r = addPriceEntry(PRICE_CTX.barcode, PRICE_CTX.name, { price: g('scanPrice'), currency: g('scanCurrency'), store: g('scanStore') });
  if (!r.ok) { toast(r.error || 'Enter a price'); return; }
  toast('Price saved');
}

// ---- timeline substrate: biometrics + events (D20) ------------------------
// A source-agnostic store the food log is correlated against. ONE record shape,
// ONE adapter contract (normalizeSignal + addSignal); manual entry is the zeroth
// adapter, a future cloud/native adapter satisfies the same contract with no
// substrate rebuild. Events are timeline records, NOT food items (no double-count).
// One SIGNAL_SPEC table drives forms, labels, units, warnings (like MICRO_SPEC).
const SIGNAL_SPEC = [
  { type: 'weight',         kind: 'biometric', label: 'Weight',        unit: 'kg',    units: ['kg', 'lb'],        warn: 500 },
  { type: 'resting_hr',     kind: 'biometric', label: 'Resting HR',    unit: 'bpm',   units: ['bpm'],             warn: 300 },
  { type: 'hrv',            kind: 'biometric', label: 'HRV',           unit: 'ms',    units: ['ms'],              warn: 500 },
  { type: 'glucose',        kind: 'biometric', label: 'Glucose',       unit: 'mg/dL', units: ['mg/dL', 'mmol/L'], warn: 1000 },
  { type: 'breath_ketones', kind: 'biometric', label: 'Breath ketones', unit: 'ppm', units: ['ppm', 'mmol/L'],   warn: 100 },
  { type: 'bp_systolic',    kind: 'biometric', label: 'BP systolic',   unit: 'mmHg',  units: ['mmHg'],            warn: 300 },
  { type: 'bp_diastolic',   kind: 'biometric', label: 'BP diastolic',  unit: 'mmHg',  units: ['mmHg'],            warn: 250 },
  { type: 'sleep_hours',    kind: 'biometric', label: 'Sleep',         unit: 'h',     units: ['h'],               warn: 24 },
  { type: 'steps',          kind: 'biometric', label: 'Steps',         unit: 'count', units: ['count'],           warn: 100000 },
  { type: 'mood',           kind: 'biometric', label: 'Mood',          unit: '/5',    units: ['/5'],              warn: 5 },
  { type: 'energy',         kind: 'biometric', label: 'Energy',        unit: '/5',    units: ['/5'],              warn: 5 },
  { type: 'sauna',        kind: 'event', label: 'Sauna',       unit: 'min',    units: ['min'],    warn: 600 },
  { type: 'cold_plunge',  kind: 'event', label: 'Cold plunge', unit: 'min',    units: ['min'],    warn: 120 },
  { type: 'yoga',         kind: 'event', label: 'Yoga',        unit: 'min',    units: ['min'],    warn: 600 },
  { type: 'workout',      kind: 'event', label: 'Workout',     unit: 'min',    units: ['min'],    warn: 600 },
  { type: 'walk',         kind: 'event', label: 'Walk',        unit: 'min',    units: ['min'],    warn: 1440 },
  { type: 'meditation',   kind: 'event', label: 'Meditation',  unit: 'min',    units: ['min'],    warn: 600 },
  { type: 'red_light',    kind: 'event', label: 'Red light (RLT)', unit: 'min', units: ['min'],   warn: 120 },
  { type: 'hbot',         kind: 'event', label: 'HBOT',        unit: 'min',    units: ['min'],    warn: 300 },
  { type: 'alcohol',      kind: 'event', label: 'Alcohol',     unit: 'drinks', units: ['drinks'], warn: 30 },
  { type: 'other',        kind: 'event', label: 'Other',       unit: 'min',    units: ['min'],    warn: 1440 },
];
const SIGNAL_BY_TYPE = SIGNAL_SPEC.reduce((m, s) => { m[s.type] = s; return m; }, {});
const SIGNAL_KINDS = ['biometric', 'event', 'medication'];   // D20 addendum: medication is a first-class kind
// Medication closed enums (name is open-ended free text; these drive form controls,
// no cross-wiring — MICRO_SPEC/M1 discipline).
const MED_DOSE_UNITS = ['mg', 'mcg', 'g', 'mL', 'IU', 'tablet', 'capsule', 'drop', 'puff', 'unit'];
const MED_FORMS  = ['tablet', 'capsule', 'liquid', 'injection', 'topical', 'inhaler', 'patch', 'drops', 'other'];
const MED_ROUTES = ['oral', 'sublingual', 'topical', 'inhaled', 'injected', 'nasal', 'other'];

// Coerce a raw signal (from ANY adapter) to the canonical record. value clamped
// >= 0; kind validated; unknown type tolerated + preserved; source tolerated as a
// string (extensible). date is the map key, not stored in the record.
function normalizeSignal(raw) {
  raw = raw || {};
  const spec = SIGNAL_BY_TYPE[raw.type];
  const kind = SIGNAL_KINDS.indexOf(raw.kind) >= 0 ? raw.kind
    : (spec ? spec.kind : ((raw.name != null && String(raw.name) !== '') ? 'medication' : 'event'));
  const rec = {
    time:   String(raw.time == null ? '' : raw.time),
    kind:   kind,
    type:   kind === 'medication' ? 'medication' : String(raw.type == null ? '' : raw.type),
    source: (raw.source == null || String(raw.source) === '') ? 'manual' : String(raw.source),
    notes:  String(raw.notes == null ? '' : raw.notes),
  };
  if (kind === 'medication') {
    // Extended record (D20 addendum). name/prescriber/reason free text (escaped at
    // render); dose clamped; dose_unit/form/route closed-enum with tolerant fallback.
    rec.name = String(raw.name == null ? '' : raw.name);
    if (raw.dose != null && String(raw.dose) !== '') rec.dose = clampNonNeg(raw.dose);
    rec.dose_unit = MED_DOSE_UNITS.indexOf(raw.dose_unit) >= 0 ? raw.dose_unit : '';
    rec.form  = MED_FORMS.indexOf(raw.form)  >= 0 ? raw.form  : '';
    rec.route = MED_ROUTES.indexOf(raw.route) >= 0 ? raw.route : '';
    if (raw.scheduled === true) rec.scheduled = true;                        // intent only (no scheduling built)
    if (raw.prescriber != null && String(raw.prescriber) !== '') rec.prescriber = String(raw.prescriber);
    if (raw.reason != null && String(raw.reason) !== '') rec.reason = String(raw.reason);
  } else {
    rec.unit = String(raw.unit == null ? '' : raw.unit) || (spec ? spec.unit : '');
    if (raw.value != null && String(raw.value) !== '') rec.value = clampNonNeg(raw.value);
  }
  return rec;
}

// Restore-boundary hardening (like normalizePriceLog): validate date keys, coerce
// each record, tolerate unknown keys.
function normalizeTimeline(o) {
  const src = (o && typeof o === 'object' && !Array.isArray(o)) ? o : {};
  const out = {};
  Object.keys(src).forEach((d) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d) || !Array.isArray(src[d])) return;   // drop bad date keys / shapes
    out[d] = src[d].map(normalizeSignal);
  });
  return out;
}

// Sane-range soft warnings, non-blocking (D9 discipline) — catch unit/typo errors.
function signalWarnings(raw) {
  const spec = SIGNAL_BY_TYPE[raw.type];
  const w = [];
  if (spec && raw.value != null && String(raw.value) !== '' && num(raw.value) > spec.warn)
    w.push(spec.label + ' ' + num(raw.value) + ' ' + (raw.unit || spec.unit) + ' looks high (> ' + spec.warn + ') — check the value/unit');
  return w;
}

// The zeroth adapter: file a MANUAL signal under timeline[date]. Writes ONLY the
// timeline (never a day item) — events are not food (D20). Remembers the unit.
function addSignal(raw) {
  raw = raw || {};
  const spec = SIGNAL_BY_TYPE[raw.type];
  const kind = SIGNAL_KINDS.indexOf(raw.kind) >= 0 ? raw.kind : (spec ? spec.kind : null);
  if (kind === 'medication') {
    if (!raw.name || String(raw.name).trim() === '') return { ok: false, error: 'Enter the medication name.' };
  } else {
    if (!raw.type || String(raw.type).trim() === '') return { ok: false, error: 'Choose a signal type.' };
    if (spec && spec.kind === 'biometric' && (raw.value == null || String(raw.value).trim() === ''))
      return { ok: false, error: 'Enter a value.' };
  }
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(raw.date)) ? String(raw.date) : localDate();
  const warnings = signalWarnings(raw);
  const rec = normalizeSignal(Object.assign({}, raw, { source: 'manual' }));   // manual adapter forces source
  if (!APP_STATE.timeline || typeof APP_STATE.timeline !== 'object') APP_STATE.timeline = {};
  (APP_STATE.timeline[date] = APP_STATE.timeline[date] || []).push(rec);
  if (!APP_STATE.settings.signalUnits) APP_STATE.settings.signalUnits = {};   // remember last-used unit
  if (rec.kind === 'medication') { if (rec.dose_unit) APP_STATE.settings.signalUnits.medication = rec.dose_unit; }
  else if (rec.type && rec.unit) APP_STATE.settings.signalUnits[rec.type] = rec.unit;
  Store.saveState(APP_STATE); refresh();
  return { ok: true, record: rec, warnings: warnings };
}

// BP is entered as ONE paired action (D20 addendum) -> two records at one time.
function logBP(sys, dia, time, notes) {
  const t = time || nowTime();
  const rs = addSignal({ type: 'bp_systolic', value: sys, unit: 'mmHg', time: t, notes: notes });
  const rd = addSignal({ type: 'bp_diastolic', value: dia, unit: 'mmHg', time: t, notes: notes });
  return { ok: !!(rs.ok && rd.ok), systolic: rs.record, diastolic: rd.record };
}

// Overlay (read-only): a day's food items + timeline signals, merged + time-sorted.
function timelineForDay(date) {
  const rows = [];
  const day = (APP_STATE.days && APP_STATE.days[date]) || null;
  if (day) (day.items || []).forEach((it) => rows.push({ time: it.time || '', row: 'food', name: it.name, kcal: it.kcal }));
  ((APP_STATE.timeline && APP_STATE.timeline[date]) || []).forEach((s) =>
    rows.push({ time: s.time || '', row: s.kind, type: s.type, value: s.value, unit: s.unit, notes: s.notes,
                name: s.name, dose: s.dose, dose_unit: s.dose_unit }));
  rows.sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : 0));
  return rows;
}

// ---- timeline DOM (signal entry + day overlay) ----------------------------
function signalUnitDefault(type) {
  const remembered = APP_STATE.settings && APP_STATE.settings.signalUnits && APP_STATE.settings.signalUnits[type];
  const spec = SIGNAL_BY_TYPE[type];
  return remembered || (spec ? spec.unit : '');
}
function renderSignalForm() {
  const sel = document.getElementById('sigType');
  if (sel && !sel.childElementCount) {
    const bio = [], ev = [];
    SIGNAL_SPEC.forEach((s) => {
      if (s.type === 'bp_diastolic') return;                                  // paired under one "bp" option
      if (s.type === 'bp_systolic') { bio.push(`<option value="bp">Blood pressure</option>`); return; }
      (s.kind === 'biometric' ? bio : ev).push(`<option value="${esc(s.type)}">${esc(s.label)}</option>`);
    });
    sel.innerHTML = `<optgroup label="Biometrics">${bio.join('')}</optgroup><optgroup label="Events">${ev.join('')}</optgroup>`;
  }
  onSignalTypeChange();
}
function onSignalTypeChange() {
  const sel = document.getElementById('sigType'); if (!sel) return;
  const isBP = sel.value === 'bp';
  const spec = SIGNAL_BY_TYPE[sel.value];
  const unit = document.getElementById('sigUnit'); if (unit) unit.value = isBP ? 'mmHg' : signalUnitDefault(sel.value);
  const vl = document.getElementById('sigValLabel'); if (vl) vl.textContent = isBP ? 'Systolic' : ((spec && spec.kind === 'event') ? 'Duration (opt.)' : 'Value');
  const diaWrap = document.getElementById('sigDiaWrap'); if (diaWrap) diaWrap.style.display = isBP ? '' : 'none';
  const notes = document.getElementById('sigNotes'); if (notes) notes.placeholder = (sel.value === 'other') ? 'what was it?' : 'notes (optional)';
}

// Quick-log chips (D21 Layer-1 adherence: ease-of-logging is the mechanism of
// action). A curated, audience-tuned strip that is a faster PATH INTO the existing
// form -- pickSignal only sets the type + focuses the value box, never creates a
// record; logging still funnels through addSignalFromForm -> addSignal, so a
// chip-logged record is identical to a dropdown-logged one (one contract, one path).
const CHIP_DEFAULT = ['weight', 'glucose', 'breath_ketones', 'hrv', 'resting_hr', 'sleep_hours', 'steps', 'mood', 'energy', 'bp', 'sauna', 'cold_plunge', 'walk', 'workout'];
function chipLabel(type) { return type === 'bp' ? 'BP' : (SIGNAL_BY_TYPE[type] ? SIGNAL_BY_TYPE[type].label : type); }
// Goals-derived precedence (D21): a signal type the user set a goal on has been
// declared to matter, so it floats into the unscrolled prime real estate; the
// curated default orders the rest. Reads ONLY settings.goals -- the order recomputes
// on a deliberate goal add/remove, never a live reshuffle from logging a reading
// (no inference from readings -- that is clinical judgment, barred by the guidance
// gate). Adaptive most-logged ordering is deferred to Layer 2 (trend data).
function chipHasGoal(type) {
  const goals = (APP_STATE && APP_STATE.settings && APP_STATE.settings.goals) || {};
  if (type === 'bp') return !!(goals.bp_systolic || goals.bp_diastolic);
  return !!goals[type];
}
function chipOrder() {
  return CHIP_DEFAULT.filter(chipHasGoal).concat(CHIP_DEFAULT.filter((t) => !chipHasGoal(t)));
}
function renderSignalChips() {
  const el = document.getElementById('sigChips'); if (!el) return;
  const order = chipOrder(), sig = order.join(',');
  if (el.dataset.order === sig) return;                                     // re-render only when order changes (goal add/remove) -- no reshuffle on every log
  el.dataset.order = sig;
  el.innerHTML = order.map((t) => `<button type="button" class="chip" onclick="pickSignal('${t}')">${esc(chipLabel(t))}</button>`).join('');
}
// A faster path INTO the form, NOT a second code path: set the type, run the
// existing handler (unit/label/BP-pair), focus the value box. The user then types +
// taps the same Log button -> addSignalFromForm -> addSignal. No record made here.
function pickSignal(type) {
  const sel = document.getElementById('sigType'); if (!sel) return;
  sel.value = type;
  onSignalTypeChange();
  const v = document.getElementById('sigValue');
  if (v) { try { v.focus(); if (v.select) v.select(); } catch (e) {} }
}
function addSignalFromForm() {
  const g = (id) => { const el = document.getElementById(id); return el ? el.value : ''; };
  const type = g('sigType');
  let r;
  if (type === 'bp') {   // paired entry -> logBP (two records, one timestamp)
    if (String(g('sigValue')).trim() === '' || String(g('sigDia')).trim() === '') { toast('Enter systolic and diastolic'); return; }
    r = logBP(g('sigValue'), g('sigDia'), g('sigTime') || nowTime(), g('sigNotes'));
  } else {
    r = addSignal({ type: type, value: g('sigValue'), unit: g('sigUnit'), time: g('sigTime') || nowTime(), notes: g('sigNotes') });
  }
  if (!r.ok) { toast(r.error || 'Could not log'); return; }
  ['sigValue', 'sigDia', 'sigNotes'].forEach((id) => { const el = document.getElementById(id); if (el) el.value = ''; });
  showSignalWarnings(r.warnings || []);
  toast((r.warnings && r.warnings.length) ? 'Logged — see warnings' : 'Logged');
}

// Medication form (its own detailed entry — D20 addendum). Closed enums populate
// the selects; quick path = name (+ optional dose); everything else optional.
function renderMedForm() {
  const fill = (id, arr) => {
    const el = document.getElementById(id);
    if (el && !el.childElementCount) el.innerHTML = '<option value=""></option>' + arr.map((x) => `<option value="${esc(x)}">${esc(x)}</option>`).join('');
  };
  fill('medDoseUnit', MED_DOSE_UNITS); fill('medForm', MED_FORMS); fill('medRoute', MED_ROUTES);
  const du = document.getElementById('medDoseUnit');
  const remembered = APP_STATE.settings && APP_STATE.settings.signalUnits && APP_STATE.settings.signalUnits.medication;
  if (du && !du.value && remembered) du.value = remembered;
}
function addMedicationFromForm() {
  const g = (id) => { const el = document.getElementById(id); return el ? el.value : ''; };
  const checked = (id) => { const el = document.getElementById(id); return !!(el && el.checked); };
  const r = addSignal({
    kind: 'medication', name: g('medName'), dose: g('medDose'), dose_unit: g('medDoseUnit'),
    form: g('medForm'), route: g('medRoute'), scheduled: checked('medScheduled'),
    prescriber: g('medPrescriber'), reason: g('medReason'), time: g('medTime') || nowTime(), notes: g('medNotes'),
  });
  if (!r.ok) { toast(r.error || 'Enter the medication name'); return; }
  ['medName', 'medDose', 'medPrescriber', 'medReason', 'medNotes'].forEach((id) => { const el = document.getElementById(id); if (el) el.value = ''; });
  const sc = document.getElementById('medScheduled'); if (sc) sc.checked = false;
  toast('Medication logged');
}
function showSignalWarnings(warns) {
  const el = document.getElementById('sigWarn'); if (!el) return;
  el.innerHTML = (warns && warns.length) ? warns.map((w) => `<div class="warn">${esc(w)}</div>`).join('') : '';
}
function renderTimelineOverlay() {
  const el = document.getElementById('timelineOverlay');
  if (!el || !APP_STATE) return;
  const rows = timelineForDay(APP_STATE.current);
  if (!rows.length) { el.innerHTML = '<div class="note" style="margin:0">Nothing yet — log food, an event, or a biometric to see them on one timeline.</div>'; return; }
  el.innerHTML = rows.map((r) => {
    const t = r.time ? esc(r.time) : '—';
    const note = r.notes ? ` <small>${esc(r.notes)}</small>` : '';
    if (r.row === 'food')
      return `<div class="tlrow"><span class="tltime">${t}</span><span class="tltag food">food</span><span class="tlmain">${esc(r.name)} <small>${esc(rDisp(r.kcal))} kcal</small></span></div>`;
    if (r.row === 'medication') {
      const dose = (r.dose != null) ? ' ' + esc(rDisp(r.dose)) + ' ' + esc(r.dose_unit || '') : '';
      return `<div class="tlrow"><span class="tltime">${t}</span><span class="tltag medication">med</span><span class="tlmain">${esc(r.name)}${dose}${note}</span></div>`;
    }
    const spec = SIGNAL_BY_TYPE[r.type];
    const val = (r.value != null) ? ' ' + esc(rDisp(r.value)) + ' ' + esc(r.unit || '') : '';
    return `<div class="tlrow"><span class="tltime">${t}</span><span class="tltag ${esc(r.row)}">${esc(r.row)}</span><span class="tlmain">${esc(spec ? spec.label : r.type)}${val}${note}</span></div>`;
  }).join('');
}

// ---- manual-add DOM (form generation, read-back, handlers) ----------------
// One micro component, shared by the manual-add and supplement forms (D12).
// Fields are id'd `<prefix><canonical key>`; generation and read-back use the
// same MICRO_SPEC + prefix, so field <-> key can't cross-wire in either form.
function renderMicroFields(hostId, prefix, countId) {
  const host = document.getElementById(hostId);
  if (!host || host.childElementCount) return;   // build once
  host.innerHTML = MICRO_SPEC.map((s) =>
    `<div class="mafield"><label>${esc(s.label)}</label>` +
    `<div class="uinput"><input id="${esc(prefix)}${esc(s.key)}" type="number" inputmode="decimal" oninput="updateMicroCount('${esc(prefix)}','${esc(countId)}')">` +
    `<span class="unit">${esc(s.unit)}</span></div></div>`).join('');
}
function readMicroFields(prefix) {
  const micros = {};
  MICRO_SPEC.forEach((s) => { const el = document.getElementById(prefix + s.key); if (el && el.value.trim() !== '') micros[s.key] = el.value; });
  return micros;
}
function updateMicroCount(prefix, countId) {
  const el = document.getElementById(countId); if (!el) return;
  let n = 0;
  MICRO_SPEC.forEach((s) => { const i = document.getElementById(prefix + s.key); if (i && i.value.trim() !== '') n++; });
  el.textContent = n ? ' (' + n + ' entered)' : '';
}
function readManualForm() {
  const g = (id) => { const el = document.getElementById(id); return el ? el.value : ''; };
  const raw = {
    name: g('maName'), meal: g('maMeal'), time: g('maTime') || nowTime(), confidence: g('maConf'),
    kcal: g('maKcal'), protein_g: g('maP'), fat_g: g('maF'), carb_g: g('maC'),
    fiber_g: g('maFib'), soluble_fiber_g: g('maSol'),
  };
  const micros = readMicroFields('ma_micro_');
  if (Object.keys(micros).length) raw.micros = micros;
  return raw;
}
function clearManualForm() {
  ['maName', 'maKcal', 'maP', 'maF', 'maC', 'maFib', 'maSol', 'maTime', 'maPortion'].forEach((id) => { const el = document.getElementById(id); if (el) el.value = ''; });
  MICRO_SPEC.forEach((s) => { const el = document.getElementById('ma_micro_' + s.key); if (el) el.value = ''; });
  updateMicroCount('ma_micro_', 'maMicroCount'); showManualWarnings([]);
}
function showManualWarnings(warns) {
  const el = document.getElementById('maWarn'); if (!el) return;
  el.innerHTML = (warns && warns.length) ? warns.map((w) => `<div class="warn">${esc(w)}</div>`).join('') : '';
}
function addManualItem() {
  const raw = readManualForm();
  const r = addManualEntry(raw);
  if (!r.ok) { toast(r.error || 'Could not add'); return; }
  clearManualForm();
  showManualWarnings(r.warnings);
  toast(r.warnings.length ? 'Added — see warnings' : 'Added');
}
function saveAsPreset() {
  const raw = readManualForm();
  const portion = (document.getElementById('maPortion') || {}).value;
  const r = saveManualPreset(raw, portion);
  if (!r.ok) { toast(r.error || 'Could not save preset'); return; }
  showManualWarnings(manualWarnings(raw));            // advisory, form kept (fork D)
  toast('Saved preset "' + r.preset.name + '" — form kept');
}
function renderPresets() {
  const el = document.getElementById('presetList'); if (!el) return;
  const presets = (APP_STATE.settings && APP_STATE.settings.presets) || [];
  if (!presets.length) { el.innerHTML = '<div class="note">No presets yet. Fill the form above and tap "Save as preset."</div>'; return; }
  el.innerHTML = presets.map((p) =>
    `<div class="presetrow"><div class="pmain"><div class="pname">${esc(p.name)}</div>` +
    `<div class="pmeta">${esc(rDisp(p.kcal))} kcal · P ${esc(rDisp(p.protein_g))} F ${esc(rDisp(p.fat_g))} C ${esc(rDisp(p.carb_g))}` +
    `${p.portion ? ' · ' + esc(p.portion) : ''}${p.micros ? ' · micros' : ''}</div></div>` +
    `<button class="btn" onclick="logPreset('${esc(p.id)}')">Log</button>` +
    `<button class="prm" onclick="deletePreset('${esc(p.id)}')" title="delete preset">×</button></div>`).join('');
}

// ---- averages (DECISIONS.md D10) ------------------------------------------
// Complete days in the window. 'week' = calendar window (>= today-6 days);
// 'all' = every complete day. In-progress days never qualify.
function completeDaysInWindow(kind) {
  const complete = Object.keys(APP_STATE.days).filter((d) => APP_STATE.days[d].status === 'complete');
  if (kind === 'all') return complete.sort();
  const cut = new Date(localDate() + 'T00:00:00');
  cut.setDate(cut.getDate() - 6);
  const cutKey = localDate(cut);
  return complete.filter((d) => d >= cutKey).sort();
}

// Macro mean = Σ/M (full coverage). Micro mean = Σ over days-carrying-K / N_K
// (absence ≠ zero), with per-nutrient coverage N_K of M.
function averageOver(dateKeys) {
  const M = dateKeys.length;
  const macros = { kcal: 0, protein_g: 0, fat_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0 };
  const microSum = {}, microN = {};
  dateKeys.forEach((d) => {
    const day = APP_STATE.days[d];
    (day.items || []).forEach((it) => { Object.keys(macros).forEach((k) => { macros[k] += num(it[k]); }); });
    const mr = microRollup(day);   // {K:{total, n(items carrying K), m}}
    Object.keys(mr).forEach((K) => {
      if (mr[K].n > 0) { microSum[K] = (microSum[K] || 0) + mr[K].total; microN[K] = (microN[K] || 0) + 1; }
    });
  });
  const macroAvg = {};
  Object.keys(macros).forEach((k) => { macroAvg[k] = M ? macros[k] / M : 0; });
  const microAvg = {};
  Object.keys(microSum).forEach((K) => { microAvg[K] = { avg: microSum[K] / microN[K], nK: microN[K], m: M }; });
  return { n: M, macros: macroAvg, micros: microAvg };
}

function avgBlockHTML(label, a) {
  if (a.n === 0) {
    return `<div class="avgblock"><div class="avghead">${esc(label)}</div><div class="note">No complete days yet — close a day to see averages.</div></div>`;
  }
  let html = `<div class="avgblock"><div class="avghead">${esc(label)} <small>n=${esc(a.n)}</small></div>`;
  html += `<div class="avgmacros"><b>${esc(rDisp(a.macros.kcal))}</b> kcal · P ${esc(rDisp(a.macros.protein_g))} F ${esc(rDisp(a.macros.fat_g))} C ${esc(rDisp(a.macros.carb_g))} · ${esc(rDisp(a.macros.fiber_g))} fib (${esc(rDisp(a.macros.soluble_fiber_g))} sol)</div>`;
  const mk = Object.keys(a.micros);
  if (mk.length) {
    html += `<div class="avgmicros"><div class="sumhead">Micronutrients — labeled intake only</div>` + mk.map((K) => {
      const spec = MICRO_LABEL[K];
      const m = a.micros[K];
      return `<div class="avgmrow"><span>${esc(spec ? spec.label : K)}</span><span>${esc(rDisp(m.avg))} ${esc(spec ? spec.unit : '')} <small>from ${esc(m.nK)} of ${esc(m.m)} days</small></span></div>`;
    }).join('') + `</div>`;
  }
  return html + `</div>`;
}

function renderAverages() {
  const el = document.getElementById('averages');
  if (!el || !APP_STATE) return;
  el.innerHTML = avgBlockHTML('7-day', averageOver(completeDaysInWindow('week'))) +
                 avgBlockHTML('All-time', averageOver(completeDaysInWindow('all')));
}

// ---- first-run onboarding + AI prompt template (DECISIONS.md D11) ---------
const AI_TEMPLATE_VERSION = 2;   // tied to schema v2 — bump when the item contract changes

// One canonical template. It requests macros only (no micros — a photo can't
// show them), eyeballed confidence, soluble_fiber_g present, and the exact meal
// enum so an assistant can't invent values. Straight quotes only.
const AI_PROMPT_TEMPLATE =
'You are helping me log a meal from a photo into a nutrition tracker.\n' +
'Reply with JSON ONLY - no prose, no markdown, straight quotes only.\n\n' +
'Format:\n' +
'{"items":[\n' +
'  {"name":"<food + portion>","meal":"<breakfast|lunch|dinner|snack|drink|supplement>","kcal":<n>,"protein_g":<n>,"fat_g":<n>,"carb_g":<n>,"fiber_g":<n>,"soluble_fiber_g":<n>,"confidence":"eyeballed","notes":"<portion assumptions>"}\n' +
']}\n\n' +
'Rules:\n' +
'- Estimate macros only. Do not include vitamins or minerals - a photo cannot show them.\n' +
'- "confidence" is always "eyeballed".\n' +
'- Always include "soluble_fiber_g" (use 0 if unknown).\n' +
'- "meal" must be exactly one of: breakfast, lunch, dinner, snack, drink, supplement.\n' +
'- State portion assumptions honestly in "notes".';

// Adjacent sample that obeys the template — gated against real ingest() so the
// two can't drift apart.
const AI_PROMPT_SAMPLE =
'{"items":[{"name":"Grilled chicken salad, ~350g","meal":"lunch","kcal":420,"protein_g":38,"fat_g":22,"carb_g":14,"fiber_g":5,"soluble_fiber_g":1,"confidence":"eyeballed","notes":"assumed 150g chicken, olive-oil dressing"}]}';

// First-run derived from state — no stored flag (D11).
function isFirstRun() {
  if (!APP_STATE) return true;
  const days = APP_STATE.days || {};
  const hasItem = Object.keys(days).some((d) => (days[d].items || []).some((it) => !it._auto));
  const s = APP_STATE.settings || {};
  const hasPreset = (s.presets || []).length > 0;
  const hasGoal = Object.keys(s.goals || {}).length > 0;
  return !hasItem && !hasPreset && !hasGoal;
}

function renderOnboarding() {
  const el = document.getElementById('onboarding');
  if (!el) return;
  if (!isFirstRun()) { el.style.display = 'none'; el.innerHTML = ''; return; }
  el.style.display = 'block';
  el.innerHTML = `<h2>Welcome</h2>
    <p class="obtext">Two ways to log food:</p>
    <ul class="oblist">
      <li><b>AI photo:</b> copy the prompt (below), send it to your AI assistant with a meal photo, then paste the JSON it returns into <b>Ingest</b>.</li>
      <li><b>Manual:</b> type it in under <b>Add manually</b> — also where package-label micronutrients go.</li>
    </ul>
    <p class="obtext"><a href="#" onclick="scrollToGoals();return false">Set a daily goal</a> to light up the ring (optional). All data stays on this device — export anytime.</p>`;
}

function renderPromptCard() {
  const box = document.getElementById('promptTemplate');
  if (box) box.value = AI_PROMPT_TEMPLATE;
  const ver = document.getElementById('promptVersion');
  if (ver) ver.textContent = 'template v' + AI_TEMPLATE_VERSION;
}
function copyPrompt() {
  const box = document.getElementById('promptTemplate');
  if (box) { box.value = AI_PROMPT_TEMPLATE; box.focus(); box.select(); try { box.setSelectionRange(0, AI_PROMPT_TEMPLATE.length); } catch (e) {} }
  let done = false;
  try { done = document.execCommand('copy'); } catch (e) {}
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(AI_PROMPT_TEMPLATE).then(function () { toast('Prompt copied'); }).catch(function () {});
  toast(done ? 'Prompt copied' : 'Select-all + copy the prompt');
}
function scrollToGoals() {
  const d = document.getElementById('goalsDetails'); if (d) d.open = true;
  const el = document.getElementById('goalNutrient'); if (el && el.scrollIntoView) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
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
function refresh() { renderBadge(); renderOnboarding(); renderDay(); renderSignalChips(); renderTimelineOverlay(); renderAverages(); renderPresets(); renderScanButton(); renderScan(); renderHistory(); renderDataStatus(); }

// D16: ask the browser to make storage persistent (resist eviction). Best-effort
// and SILENT by contract: feature-detected, fire-and-forget (never awaited),
// never throws, and a declined prompt never blocks boot. Export (D5) is the real
// durability guarantee against a data-clearing browser; this only lowers the odds.
function requestPersistentStorage() {
  try {
    if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(function () {});
  } catch (e) { /* never blocks boot */ }
}

// ---- app version + post-update changelog notice (D6 force-and-notify) ------
// The SW forces the current version on load (skipWaiting, sw.js); this shows a
// dismissible notice AFTER the fact. APP_VERSION bumps every release (gated by
// check-version.sh) and doubles as the OFF UA version (D14). VERSION_LOG is the
// single per-release changelog — one line each, like AI_TEMPLATE_VERSION lives
// in one place. Newest entry last; its version must equal APP_VERSION.
const VERSION_LOG = [
  { v: '0.2.0', note: 'Barcode scanning, OpenFoodFacts lookup, and price capture.' },
  { v: '0.3.0', note: 'Automatic updates with this changelog, so new versions arrive without a manual refresh.' },
  { v: '0.4.0', note: 'Log weight, biometrics (HRV, resting HR, glucose, sleep, steps, mood), and events (sauna, cold plunge, yoga, ...) on one daily timeline alongside food.' },
  { v: '0.4.1', note: 'Faster logging: tap a chip (weight, glucose, HRV, sauna, ...) to jump straight to the value box.' },
];
const VERSION_KEY = 'healthtracker-version';

// Numeric compare so '0.2.0' < '0.10.0' (not string order). -1 | 0 | 1.
function cmpVersion(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x < y) return -1;
    if (x > y) return 1;
  }
  return 0;
}
// Accumulated changelog for versions in (fromV, toV] — handles multi-version
// jumps (a user who skipped releases). fromV falsy -> just the toV line.
function versionNotesBetween(fromV, toV) {
  return VERSION_LOG.filter((e) => (fromV ? cmpVersion(e.v, fromV) > 0 : e.v === toV) && cmpVersion(e.v, toV) <= 0);
}
// Pure: given the stored version, the notice to show (null = no change / downgrade).
function versionNotice(stored) {
  stored = stored || null;
  if (stored && cmpVersion(stored, APP_VERSION) >= 0) return null;   // unchanged or downgrade
  return { from: stored, to: APP_VERSION, notes: versionNotesBetween(stored, APP_VERSION) };
}

function checkVersionNotice() {
  let stored = null;
  try { stored = Store.readRaw(VERSION_KEY); } catch (e) {}
  const notice = versionNotice(stored);
  Store.writeAux(VERSION_KEY, APP_VERSION);              // persist running version so the notice fires once
  if (!notice) return;
  if (!stored && isFirstRun()) return;                  // fresh install -> no spurious "updated" notice
  renderVersionNotice(notice);
}
function renderVersionNotice(notice) {
  const el = document.getElementById('versionNotice');
  if (!el) return;
  const head = notice.from ? 'Updated from v' + esc(notice.from) + ' to v' + esc(notice.to) : 'Now on v' + esc(notice.to);
  const lines = (notice.notes || []).map((e) => `<div class="vnrow"><b>v${esc(e.v)}</b> — ${esc(e.note)}</div>`).join('');
  el.innerHTML = `<div class="vnhead"><span>${head}</span><button class="vnx" onclick="dismissVersionNotice()" title="dismiss">×</button></div>${lines}`;
  el.style.display = 'block';
}
function dismissVersionNotice() {
  const el = document.getElementById('versionNotice');
  if (el) { el.style.display = 'none'; el.innerHTML = ''; }
}

function main() {
  boot();
  requestPersistentStorage();
  checkVersionNotice();
  renderMicroFields('maMicros', 'ma_micro_', 'maMicroCount');
  renderMicroFields('supMicros', 'sup_micro_', 'supMicroCount');
  renderSupplementForm();
  renderSignalForm();
  renderMedForm();
  renderPromptCard();
  refresh();
}

// Console seam for review/testing.
window.HT = {
  Store, boot, migrateV1toV2, migrateV2toV3, migrateToLatest, normalizeState, refresh,
  // Phase 4 Slice T — timeline substrate (D20)
  SIGNAL_SPEC, SIGNAL_KINDS, MED_DOSE_UNITS, MED_FORMS, MED_ROUTES,
  normalizeSignal, normalizeTimeline, signalWarnings, addSignal, logBP, timelineForDay,
  // Phase 4 Layer-1 adherence — quick-log chips (D21)
  chipOrder, CHIP_DEFAULT, pickSignal, renderSignalChips, renderSignalForm, addSignalFromForm,
  exportJSON, parseImport, restore,
  ingest, maybeInjectSupplement, buildSupplementItem, fillable,
  goalProgress, microRollup, dayTotals, setGoal,
  manualWarnings, addManualEntry, saveManualPreset, logPreset, deletePreset,
  renderMicroFields, readMicroFields, MICRO_SPEC,
  averageOver, completeDaysInWindow,
  isFirstRun, AI_PROMPT_TEMPLATE, AI_PROMPT_SAMPLE, AI_TEMPLATE_VERSION,
  setSupplement, applySupplementToToday, normalizeSupplement,
  requestPersistentStorage,
  // D6 force-and-notify: version + changelog notice
  VERSION_LOG, cmpVersion, versionNotesBetween, versionNotice, checkVersionNotice,
  // Phase 2 Slice 1 — OFF lookup + micros + portion + cache (D13, D14)
  mapOffProduct, mapOffMicros, offToTarget, scalePortion, portionGrams,
  buildScanItem, logScanItem, ProductCache, finishLookup, lookupBarcode, applyLookup,
  guardBarcode, offURL, offStatusKind, OFF_UA, APP_VERSION, PRODUCT_CACHE_VERSION,
  // Phase 2 Slice 2 — camera scanner + ZXing (D15)
  cameraPrecondition, detectorTier, cameraErrorMessage, intersectFormats,
  scanGate, stopScanner, loadZXing, startScan, cancelScan,
  ZXING, SCAN_FORMATS,
  // Phase 2 Slice 3 — personal price capture (D18)
  addPriceEntry, priceComparison, storeHistory, normalizePriceLog, priceCaptureHTML,
  keys: { STORE_KEY, PRERESTORE_KEY, PREMIGRATION_KEY, PRODUCTS_KEY },
  state: () => APP_STATE,
  resave: () => Store.saveState(APP_STATE),
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', main);
else main();
