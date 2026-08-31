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
const SCHEMA_VERSION   = 5;
const APP_VERSION      = '0.10.0';                           // D14 OFF UA token + D6 update version (bumps every release; gated)

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

// D29 — timezone offset capture. `tzo` is the DEVICE's UTC offset in whole
// minutes, EAST-POSITIVE (UTC-4 -> -240). JS getTimezoneOffset() is
// west-positive, hence the negation. Capture-only: nothing reads it yet.
const TZO_MAX = 840;                                  // +/- 14 h, the real-world extreme
const nowTZO = () => -new Date().getTimezoneOffset();
// Coerce to an integer offset in range, else UNDEFINED (the field is simply
// absent). Deliberately NOT clamped: clamping would launder a garbage value into
// a real-looking zone. Absence is a first-class state (D29 Pin 2) -- every
// pre-capture record is absent, and that is honest.
function normalizeTzo(v) {
  if (v == null || v === '' || typeof v === 'boolean' || typeof v === 'object') return undefined;
  const n = Number(v);
  if (!Number.isFinite(n)) return undefined;
  const i = Math.round(n);
  return (i >= -TZO_MAX && i <= TZO_MAX) ? i : undefined;
}

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
  return { goals: {}, supplement: { enabled: false, name: '', nutrients: {} }, presets: [], currency: '', signalUnits: {}, fasting: { enabled: true, minHours: 16 }, nudges: { enabled: true, habits: {} } };
}
function emptyState() {
  return { version: SCHEMA_VERSION, days: {}, current: '', settings: defaultSettings(), priceLog: {}, timeline: {}, fastLog: {}, regimens: { active: '', list: [], log: {} } };
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
//
// NOTE (D29): this and the sibling record normalizers are ALLOWLIST REBUILDS, not
// passthroughs -- an unknown TOP-LEVEL key is dropped. (Only normalizeMicros
// genuinely preserves unknown keys.) So an additive field like `tzo` must be
// listed explicitly here to survive; that is deliberate, since opening a
// passthrough would let arbitrary keys cross the untrusted paste boundary.
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
  const tzo = normalizeTzo(it.tzo);      // D29: PRESERVE only -- creation paths supply it,
  if (tzo !== undefined) out.tzo = tzo;  // this boundary never invents one (Pin 3).
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
    fasting: normalizeFasting(s.fasting),   // D22: fasting detection config
    nudges: normalizeNudges(s.nudges),      // D25: nudge state (load-bearing markers)
  };
}
// D22: fasting config. enabled defaults true (always-on-but-silent — only real
// >= minHours gaps ever surface); minHours default 16 (16:8), clamped > 0.
function normalizeFasting(f) {
  f = (f && typeof f === 'object' && !Array.isArray(f)) ? f : {};
  const mh = num(f.minHours);
  return { enabled: f.enabled !== false, minHours: mh > 0 ? mh : 16 };
}
// D25 restore hardening. PRESERVES state + `at` timestamps EXACTLY (load-bearing
// intervention markers). Unknown/invalid state dropped; any habit id kept (curriculum
// may evolve — old decisions survive); enabled defaults true.
function normalizeNudges(n) {
  n = (n && typeof n === 'object' && !Array.isArray(n)) ? n : {};
  const src = (n.habits && typeof n.habits === 'object' && !Array.isArray(n.habits)) ? n.habits : {};
  const habits = {};
  Object.keys(src).forEach((id) => {
    const e = src[id] || {};
    if (['accepted', 'declined', 'snoozed', 'retired'].indexOf(e.state) < 0) return;
    habits[id] = { state: e.state, at: typeof e.at === 'string' ? e.at : '' };
  });
  return { enabled: n.enabled !== false, habits: habits };
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
      const pe = { price: clampNonNeg(e.price), currency: String(e.currency == null ? '' : e.currency), store: String(e.store == null ? '' : e.store), date: date };
      const ptz = normalizeTzo(e.tzo);            // D29: preserve only
      if (ptz !== undefined) pe.tzo = ptz;
      return pe;
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
// D22 add-only v3 -> v4: introduce the empty fastLog store (days/settings/
// priceLog/timeline byte-preserved). Same shape as migrateV2toV3.
function migrateV3toV4(v3, nowISO) {
  const out = {
    version: 4,
    days: (v3.days && typeof v3.days === 'object') ? v3.days : {},
    current: typeof v3.current === 'string' ? v3.current : '',
    settings: (v3.settings && typeof v3.settings === 'object') ? v3.settings : defaultSettings(),
    priceLog: (v3.priceLog && typeof v3.priceLog === 'object') ? v3.priceLog : {},
    timeline: (v3.timeline && typeof v3.timeline === 'object') ? v3.timeline : {},
    fastLog: {},   // add-only
    migratedAt: typeof v3.migratedAt === 'string' ? v3.migratedAt : nowISO,
  };
  if (typeof v3.knownDropped === 'number') out.knownDropped = v3.knownDropped;
  return out;
}
// D27 add-only v4 -> v5: introduce the empty regimens store (templates + fulfillment
// log). All prior stores byte-preserved.
function migrateV4toV5(v4, nowISO) {
  const out = {
    version: 5,
    days: (v4.days && typeof v4.days === 'object') ? v4.days : {},
    current: typeof v4.current === 'string' ? v4.current : '',
    settings: (v4.settings && typeof v4.settings === 'object') ? v4.settings : defaultSettings(),
    priceLog: (v4.priceLog && typeof v4.priceLog === 'object') ? v4.priceLog : {},
    timeline: (v4.timeline && typeof v4.timeline === 'object') ? v4.timeline : {},
    fastLog: (v4.fastLog && typeof v4.fastLog === 'object') ? v4.fastLog : {},
    regimens: { active: '', list: [], log: {} },   // add-only
    migratedAt: typeof v4.migratedAt === 'string' ? v4.migratedAt : nowISO,
  };
  if (typeof v4.knownDropped === 'number') out.knownDropped = v4.knownDropped;
  return out;
}
// Chain the in-place migrators to the latest schema (D7/D20/D22/D27). version-absent
// is treated as v1 defensively (our key). The same migrator serves boot + restore.
function migrateToLatest(blob, nowISO) {
  let out = blob;
  const v = (typeof blob.version === 'number') ? blob.version : 1;
  if (v < 2) out = migrateV1toV2(out, nowISO);
  if ((out.version || 2) < 3) out = migrateV2toV3(out, nowISO);
  if ((out.version || 3) < 4) out = migrateV3toV4(out, nowISO);
  if ((out.version || 4) < 5) out = migrateV4toV5(out, nowISO);
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
    fastLog: normalizeFastLog(o.fastLog),      // D22: persisted fasting resolutions
    regimens: normalizeRegimens(o.regimens),   // D27: timeline templates + fulfillment log
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

// D22 restore-boundary hardening for fastLog (like normalizeTimeline). Only
// RESOLVED states persist (fasted | ate_didnt_log) — pending = absence, so a
// stored 'pending'/unknown state or a bad key is dropped. Keyed by a valid start
// ISO; hours clamped >= 0; resolved_by kept as a string (tolerates a future
// 'biometric' resolver — Pin 2). Round-trips a resolved entry exactly.
function normalizeFastLog(o) {
  const src = (o && typeof o === 'object' && !Array.isArray(o)) ? o : {};
  const isoRe = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;
  const out = {};
  Object.keys(src).forEach((k) => {
    const e = src[k] || {};
    const state = (e.state === 'fasted' || e.state === 'ate_didnt_log') ? e.state : null;
    const start = String(e.start == null ? k : e.start);
    if (!state || !isoRe.test(start)) return;                              // pending/unknown/bad-key -> dropped
    const rec = {
      start: start,
      end: isoRe.test(String(e.end)) ? String(e.end) : '',
      hours: clampNonNeg(e.hours),
      state: state,
      resolved_by: (typeof e.resolved_by === 'string' && e.resolved_by) ? e.resolved_by : 'user',
      resolved_at: typeof e.resolved_at === 'string' ? e.resolved_at : '',
    };
    if (e.notes != null && String(e.notes) !== '') rec.notes = String(e.notes);
    const ftz = normalizeTzo(e.tzo);              // D29: preserve only
    if (ftz !== undefined) rec.tzo = ftz;
    out[start] = rec;
  });
  return out;
}

// D27 restore hardening for the regimens store (templates + fulfillment log). Lenient
// (salvage what's valid); parseRegimen is the strict authoring boundary. Every text
// field kept raw (escaped at render).
const REGIMEN_KINDS = ['food', 'medication', 'event'];
function normalizeRegimenEntry(e) {
  e = e || {};
  const kind = REGIMEN_KINDS.indexOf(e.kind) >= 0 ? e.kind : null;
  if (!kind) return null;
  const out = { id: String(e.id || ''), time: /^\d{2}:\d{2}$/.test(String(e.time)) ? String(e.time) : '', kind: kind };
  if (Array.isArray(e.days)) { const d = e.days.map((x) => parseInt(x, 10)).filter((x) => x >= 0 && x <= 6); if (d.length) out.days = d; }
  if (kind === 'food') out.presetId = String(e.presetId || '');
  else if (kind === 'medication') {
    out.name = String(e.name || '');
    if (e.dose != null && String(e.dose) !== '') out.dose = clampNonNeg(e.dose);
    if (e.dose_unit) out.dose_unit = String(e.dose_unit);
    if (e.form) out.form = String(e.form);
    if (e.route) out.route = String(e.route);
  } else {
    out.type = String(e.type || '');
    if (e.value != null && String(e.value) !== '') out.value = clampNonNeg(e.value);
    if (e.unit) out.unit = String(e.unit);
  }
  if (e.notes != null && String(e.notes) !== '') out.notes = String(e.notes);
  return out;
}
function normalizeRegimen(r) {
  r = r || {};
  const out = { id: String(r.id || ''), name: String(r.name || ''), entries: Array.isArray(r.entries) ? r.entries.map(normalizeRegimenEntry).filter(Boolean) : [] };
  if (r.window && typeof r.window === 'object' && /^\d{2}:\d{2}$/.test(String(r.window.start)) && /^\d{2}:\d{2}$/.test(String(r.window.end)))
    out.window = { start: String(r.window.start), end: String(r.window.end) };
  return out;
}
function normalizeRegimens(o) {
  o = (o && typeof o === 'object' && !Array.isArray(o)) ? o : {};
  const list = Array.isArray(o.list) ? o.list.map(normalizeRegimen).filter((r) => r.id) : [];
  const src = (o.log && typeof o.log === 'object' && !Array.isArray(o.log)) ? o.log : {};
  const log = {};
  Object.keys(src).forEach((d) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d) || typeof src[d] !== 'object' || Array.isArray(src[d])) return;
    const day = {};
    Object.keys(src[d]).forEach((eid) => { const k = src[d][eid]; if (k === 'template' || k === 'substituted') day[String(eid)] = k; });
    if (Object.keys(day).length) log[d] = day;
  });
  return { active: typeof o.active === 'string' ? o.active : '', list: list, log: log };
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
  if (!state.fastLog || typeof state.fastLog !== 'object') { state.fastLog = {}; dirty = true; }       // D22
  if (!state.regimens || typeof state.regimens !== 'object') { state.regimens = { active: '', list: [], log: {} }; dirty = true; }   // D27
  if (!state.settings.fasting || typeof state.settings.fasting !== 'object') { state.settings.fasting = { enabled: true, minHours: 16 }; dirty = true; }   // D22
  if (!state.settings.nudges || typeof state.settings.nudges !== 'object') { state.settings.nudges = { enabled: true, habits: {} }; dirty = true; }         // D25

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

// ---- undo on logging (D22 amendment): the protection is UNDO, not confirmation.
// Each log handler registers offerUndo(label, fn) after its INSTANT add; fn removes
// the just-created record(s) BY REFERENCE. Because fasting candidates are derived,
// removing the record recomputes the gap with no special-case repair. No confirm
// dialogs anywhere on the log paths — undo protects only where the failure is.
let _undoFn = null, _undoT = null;
function offerUndo(label, fn) {
  _undoFn = fn;
  const e = document.getElementById('toast'); if (!e) return;
  e.innerHTML = esc(label) + ' <button type="button" class="tundo" onclick="doUndo()">Undo</button>';
  e.classList.add('show');
  clearTimeout(_undoT);
  _undoT = setTimeout(function () { e.classList.remove('show'); e.textContent = ''; _undoFn = null; }, 7000);
}
function doUndo() {
  const fn = _undoFn; _undoFn = null;
  clearTimeout(_undoT);
  const e = document.getElementById('toast'); if (e) { e.classList.remove('show'); e.textContent = ''; }
  if (typeof fn === 'function') { fn(); toast('Undone'); }
}
// Remove created record(s) by reference (survives array reordering), persist, refresh.
function undoRemove(arr, refs) {
  return function () {
    (Array.isArray(refs) ? refs : [refs]).forEach(function (r) {
      if (Array.isArray(arr)) { const i = arr.indexOf(r); if (i >= 0) arr.splice(i, 1); }
    });
    Store.saveState(APP_STATE); refresh();
  };
}
// Food log: the label carries FAST CONTEXT (D22 amendment 3) — a log that ended a
// >= minHours fast says so; undo removes the item and the candidate recomputes away.
function offerFoodUndo(dateKey, item) {
  const arr = (APP_STATE.days[dateKey] && APP_STATE.days[dateKey].items) || [];
  const h = fastEndedByItem(dateKey, item.time);
  offerUndo('Logged ' + item.name + (h ? (' — this ended a ' + rDisp(h) + 'h fast') : ''), undoRemove(arr, [item]));
}
function offerSignalUndo(records, label) {
  offerUndo(label, undoRemove(APP_STATE.timeline[localDate()] || [], records));
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
    source: 'supplement', _auto: true, micros: n.micros, tzo: nowTZO(),   // D29 (stamped)
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
  return { ok: true, added: [], created: [], supplemented: [], reopened: [], stripped: 0, skipped: [], mergedDays: [], rejectedItems: 0, itemRefs: [] };
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
    const aiItem = toAiPasteItem(raw);
    day.items.push(aiItem);
    report.itemRefs.push({ d: d, it: aiItem });   // D22 undo: refs for a batch undo of the AI-paste channel
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
  if (report.ok) {
    if (box) box.value = '';
    const refs = report.itemRefs || [];   // AI-paste channel only; full-days merge has no per-item refs (see report)
    if (refs.length) offerUndo('Ingested ' + refs.length + ' item' + (refs.length > 1 ? 's' : ''),
      function () { refs.forEach(function (x) { const a = APP_STATE.days[x.d] && APP_STATE.days[x.d].items; if (a) { const i = a.indexOf(x.it); if (i >= 0) a.splice(i, 1); } }); Store.saveState(APP_STATE); refresh(); });
    else toast('Ingested');
  }
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
  const gk = Object.keys(goals).filter(isNutrientGoal);   // D24: food ring is nutrient goals ONLY (mixed-namespace filter contract)
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
// settings.goals is a MIXED NAMESPACE (D24): nutrient keys = daily-sum goals (food
// ring); signal-type keys = latest-reading goals (Mirror + chip-float). Signal goals
// carry a `unit`. Every consumer MUST filter to the kind it means (isNutrientGoal).
function isNutrientGoal(key) { return RING_NUTRIENTS.indexOf(key) >= 0; }
function setGoal(key, value, direction, unit) {
  if (!APP_STATE.settings.goals) APP_STATE.settings.goals = {};
  const g = { value: clampNonNeg(value), direction: direction === 'max' ? 'max' : 'min' };
  if (unit) g.unit = String(unit);                       // signal goals only
  APP_STATE.settings.goals[key] = g;
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
  const unit = SIGNAL_BY_TYPE[k] ? signalUnitDefault(k) : '';   // signal type -> store its current display unit
  setGoal(k, v, d, unit);
  document.getElementById('goalValue').value = '';
  toast('Goal set');
}
function onGoalTypeChange() {
  const sel = document.getElementById('goalNutrient'); if (!sel) return;
  const hint = document.getElementById('goalUnitHint'); if (!hint) return;
  hint.textContent = SIGNAL_BY_TYPE[sel.value] ? signalUnitDefault(sel.value) : '';
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
  const item = normalizeItem(Object.assign({}, raw, { source: 'manual', tzo: nowTZO() }), true);   // D29 (stamped)
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
// Shared preset->item builder (D27): the ONE source both manual logPreset and a
// regimen food instantiation use, so their records are byte-identical at a given time.
// D29 Fork 2: the offset is stamped HERE, inside the shared builder, so byte-identity
// survives by construction. The scheduled `time` answers "when" (D27 Fork B supplies
// it); `tzo` answers "where was the device when this was recorded" — different
// questions, different sources, each field its own truth.
function buildPresetItem(p, time) {
  return normalizeItem({
    name: p.name, meal: p.meal, time: time, confidence: p.confidence,
    kcal: p.kcal, protein_g: p.protein_g, fat_g: p.fat_g, carb_g: p.carb_g,
    fiber_g: p.fiber_g, soluble_fiber_g: p.soluble_fiber_g, source: 'preset', micros: p.micros,
    tzo: nowTZO(),   // D29 (stamped)
  }, true);
}
function logPreset(id) {
  const presets = (APP_STATE.settings && APP_STATE.settings.presets) || [];
  const p = presets.find((x) => x.id === id);
  if (!p) return { ok: false };
  const item = buildPresetItem(p, nowTime());
  const day = curDay(); if (!day) return { ok: false };
  if (day.status === 'complete') day.status = 'in_progress';
  day.items.push(item);
  Store.saveState(APP_STATE); refresh();
  offerFoodUndo(APP_STATE.current, item);
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
    micros: s.micros, tzo: nowTZO(),   // D29 (stamped)
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
  if (r.ok) offerFoodUndo(APP_STATE.current, r.item);
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
  const petz = normalizeTzo(raw.tzo != null ? raw.tzo : nowTZO());   // D29 (stamped)
  if (petz !== undefined) entry.tzo = petz;
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
// In-app adapters that may DECLARE their source through addSignal (D19's "one
// contract, many adapters"). A later device adapter (D28) joins this list; it is
// an allowlist so a source can never be self-asserted by data we did not create.
const SIGNAL_ADAPTERS = ['manual', 'lab'];
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
  const tzo = normalizeTzo(raw.tzo);   // D29: preserve only -- addSignal supplies it
  if (tzo !== undefined) rec.tzo = tzo;
  // D34 lab fields, allowlist additions (the tzo pattern — this normalizer is a
  // rebuild, so an additive field must be listed here to survive). panelId is a
  // GROUPING KEY: losing it degrades grouping but loses no value, so it is
  // precision rather than content and needs no schema bump (D29's asymmetry test).
  if (raw.panelId != null && String(raw.panelId) !== '') rec.panelId = String(raw.panelId);
  if (raw.ref_low  != null && String(raw.ref_low)  !== '') rec.ref_low  = clampNonNeg(raw.ref_low);
  if (raw.ref_high != null && String(raw.ref_high) !== '') rec.ref_high = clampNonNeg(raw.ref_high);
  if (raw.ref_src === 'lab-report') rec.ref_src = 'lab-report';
  return rec;
}

// Restore-boundary hardening (like normalizePriceLog): validate date keys, coerce
// each record. Unknown TOP-LEVEL keys on a record are DROPPED (normalizeSignal is
// an allowlist rebuild) -- what is tolerated is an unknown `type` VALUE and an
// unknown `source` string, so a future adapter needs no substrate change (D19).
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
  // The adapter entry point (D19: one contract, many adapters; manual is the
  // zeroth). A trusted in-app adapter may DECLARE its source from the allowlist —
  // anything else falls back to 'manual', so a source is never self-asserted by
  // untrusted data. (Ingest/restore never reach here; timeline is restore's job.)
  // D29: stamps the device offset unless the caller supplied one.
  const src = SIGNAL_ADAPTERS.indexOf(raw.source) >= 0 ? raw.source : 'manual';
  const rec = normalizeSignal(Object.assign({}, raw, { source: src, tzo: raw.tzo != null ? raw.tzo : nowTZO() }));
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
// The unit field is a picker, not free text: tapping it offers the type's
// alternatives (weight kg/lb, glucose mg/dL·mmol/L, breath ketones ppm·mmol/L). A
// native <select> is the only reliably-tappable picker on iOS (datalist is not),
// and constraining to the SIGNAL_SPEC set feeds the Layer-2 trend pin (normalize a
// type's records to one unit before comparing). A remembered non-spec unit is kept
// as an extra option so nothing already logged is lost.
function fillUnitOptions(type, isBP) {
  const sel = document.getElementById('sigUnit'); if (!sel) return;
  const spec = SIGNAL_BY_TYPE[type];
  const units = isBP ? ['mmHg'] : ((spec && spec.units && spec.units.length) ? spec.units.slice() : ['']);
  const want = isBP ? 'mmHg' : signalUnitDefault(type);
  if (want && units.indexOf(want) < 0) units.unshift(want);
  sel.innerHTML = units.map((u) => `<option value="${esc(u)}">${esc(u)}</option>`).join('');
  sel.value = want;
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
  fillUnitOptions(sel.value, isBP);
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
// Belt-and-suspenders for any residual horizontal-scroll case with a mouse
// (a narrow window where the wrap media queries didn't apply): translate a
// vertical wheel to horizontal scroll, but only while the strip actually
// overflows and isn't at an edge — otherwise the page scrolls normally.
function wireChipStripWheel() {
  const el = document.getElementById('sigChips'); if (!el || el.dataset.wheelWired) return;
  el.dataset.wheelWired = '1';
  el.addEventListener('wheel', function (e) {
    if (el.scrollWidth <= el.clientWidth) return;                 // wrapped / no overflow — let the page scroll
    const dy = e.deltaY; if (!dy) return;
    const atStart = el.scrollLeft <= 0;
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 1;
    if ((dy < 0 && atStart) || (dy > 0 && atEnd)) return;         // at an edge — hand the scroll back to the page
    el.scrollLeft += dy; e.preventDefault();
  }, { passive: false });
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
  const spec = SIGNAL_BY_TYPE[type];
  const lbl = (type === 'bp')
    ? ('Logged BP ' + rDisp(r.systolic.value) + '/' + rDisp(r.diastolic.value))
    : ('Logged ' + (spec ? spec.label : type) + (r.record.value != null ? ' ' + rDisp(r.record.value) : '') + (r.record.unit ? ' ' + r.record.unit : ''));
  offerSignalUndo((type === 'bp') ? [r.systolic, r.diastolic] : [r.record], lbl);
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
  offerSignalUndo([r.record], 'Logged ' + (r.record.name || 'medication'));
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

// ---- fasting candidates DOM (D22): passive, inline resolve, mirror-never-nag --
// Surface candidates that ENDED on the viewed day (Fork 6); silent when none (no
// badge/count/nag). Resolve buttons write through the same resolveFast contract.
function fmtSpan(iso) {                                   // 'YYYY-MM-DDTHH:MM'
  const d = iso.slice(0, 10), t = iso.slice(11);
  return (d === APP_STATE.current ? '' : (d.slice(5) + ' ')) + t;   // omit date if same day
}
function renderFastCandidates() {
  const el = document.getElementById('fastCandidates'); if (!el || !APP_STATE) return;
  const cands = detectFastCandidates().filter((c) => c.end.slice(0, 10) === APP_STATE.current);
  if (!cands.length) { el.innerHTML = ''; return; }                // silent when none
  el.innerHTML = cands.map((c) => {
    const span = `<small>${esc(fmtSpan(c.start) + ' → ' + fmtSpan(c.end))}</small>`;
    const lng = c.tooLong ? ' <span class="flong">long — check</span>' : '';
    const undo = `<button type="button" class="fundo" onclick="resolveFastAt('${c.start}','${c.end}',${c.hours},'pending')">undo</button>`;
    if (c.state === 'fasted')
      return `<div class="fcand done"><span class="fmain">Fast · ${esc(rDisp(c.hours))}h ✓${lng} ${span}</span>${undo}</div>`;
    if (c.state === 'ate_didnt_log')
      return `<div class="fcand denied"><span class="fmain">${esc(rDisp(c.hours))}h gap · ate, didn't log ${span}</span>${undo}</div>`;
    return `<div class="fcand"><span class="fmain">Possible fast · ${esc(rDisp(c.hours))}h${lng} ${span}</span>`
      + `<span class="fbtns"><button type="button" onclick="resolveFastAt('${c.start}','${c.end}',${c.hours},'fasted')">Fasted</button>`
      + `<button type="button" onclick="resolveFastAt('${c.start}','${c.end}',${c.hours},'ate_didnt_log')">Ate, didn't log</button></span></div>`;
  }).join('');
}
function resolveFastAt(start, end, hours, state) { resolveFast(start, end, hours, state); }
function renderFastingForm() {
  const f = (APP_STATE.settings && APP_STATE.settings.fasting) || { enabled: true, minHours: 16 };
  const en = document.getElementById('fastEnabled'); if (en) en.checked = f.enabled !== false;
  const mh = document.getElementById('fastMinHours'); if (mh && !mh.value) mh.value = f.minHours || 16;
}
function setFastingFromForm() {
  const en = document.getElementById('fastEnabled');
  const mh = document.getElementById('fastMinHours');
  const v = mh ? num(mh.value) : 16;
  APP_STATE.settings.fasting = { enabled: !(en && !en.checked), minHours: v > 0 ? v : 16 };
  Store.saveState(APP_STATE); refresh();
  toast('Fasting settings saved');
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
  offerFoodUndo(APP_STATE.current, r.item);
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

// ---- fasting candidates (D22): derived detection, persisted resolutions ----
// A fast-breaking food EVENT is any item with kcal > 0 that isn't the auto-
// supplement (Fork 1b: kcal>0 is a protocol stance; the ~5 kcal _auto daily
// supplement is exempt). Events are (date + time) across ALL days, chronological
// — fasting is cross-day (dinner -> next-day lunch spans two date keys).
function fastEvents() {
  const evs = [];
  Object.keys(APP_STATE.days).forEach((d) => {
    (APP_STATE.days[d].items || []).forEach((it) => {
      if (num(it.kcal) > 0 && it._auto !== true && /^\d{2}:\d{2}$/.test(String(it.time)))
        evs.push(d + 'T' + it.time);
    });
  });
  return evs.sort();
}
// A candidate = the span between two CONSECUTIVE events >= minHours (bounded on
// both ends; the trailing open gap is never a candidate — it's an in-progress
// fast). Derived every call; resolutions matched in from fastLog, default pending.
function detectFastCandidates() {
  const cfg = (APP_STATE.settings && APP_STATE.settings.fasting) || {};
  if (cfg.enabled === false) return [];                                  // off-switch (Fork 7)
  const minH = num(cfg.minHours) > 0 ? num(cfg.minHours) : 16;
  const evs = fastEvents();
  const out = [];
  for (let i = 1; i < evs.length; i++) {
    const start = evs[i - 1], end = evs[i];
    if (start === end) continue;
    const hrs = (Date.parse(end) - Date.parse(start)) / 3600000;
    if (hrs >= minH) {
      const res = matchResolution(start, end);
      out.push({ id: start, start: start, end: end, hours: Math.round(hrs * 10) / 10,
                 tooLong: hrs > 48, state: res.state, resolved_by: res.resolved_by });
    }
  }
  return out;
}
// Match a derived candidate to a persisted resolution: exact start key first, then
// tolerance (±15 min on start AND end) so a small boundary-meal edit doesn't orphan
// a confirmation. No match -> pending (the absence IS the pending state).
const FAST_TOL_MS = 15 * 60000;
function matchResolution(start, end) {
  const fl = (APP_STATE.fastLog && typeof APP_STATE.fastLog === 'object') ? APP_STATE.fastLog : {};
  if (fl[start]) return { state: fl[start].state, resolved_by: fl[start].resolved_by || 'user' };
  const ks = Object.keys(fl);
  for (let i = 0; i < ks.length; i++) {
    const e = fl[ks[i]];
    if (Math.abs(Date.parse(e.start) - Date.parse(start)) <= FAST_TOL_MS &&
        Math.abs(Date.parse(e.end || '') - Date.parse(end)) <= FAST_TOL_MS)
      return { state: e.state, resolved_by: e.resolved_by || 'user' };
  }
  return { state: 'pending', resolved_by: null };
}
// The SOLE surface any average/analysis/correlation reads (Pin 1): confirmed fasts
// only. Pending (absence) and ate_didnt_log are excluded by construction.
function confirmedFasts() {
  return detectFastCandidates().filter((c) => c.state === 'fasted');
}
// Resolve a candidate. Only resolved states persist; 'pending' deletes the record
// (pending = absence). A future biometric resolver writes resolved_by:'biometric'.
function resolveFast(start, end, hours, state, resolvedBy) {
  if (state !== 'fasted' && state !== 'ate_didnt_log' && state !== 'pending') return { ok: false };
  if (!APP_STATE.fastLog || typeof APP_STATE.fastLog !== 'object') APP_STATE.fastLog = {};
  if (state === 'pending') { delete APP_STATE.fastLog[start]; }
  else {
    // D29 (stamped): start/end are zone-less local wall-clock, so the resolving
    // device's offset is the only record of which zone they were read in.
    const fr = {
      start: start, end: String(end || ''), hours: clampNonNeg(hours), state: state,
      resolved_by: resolvedBy || 'user', resolved_at: new Date().toISOString(),
    };
    const ftz = normalizeTzo(nowTZO());
    if (ftz !== undefined) fr.tzo = ftz;
    APP_STATE.fastLog[start] = fr;
  }
  Store.saveState(APP_STATE); refresh();
  return { ok: true };
}
// Did the food event at (dateKey, timeStr) END a >= minHours fast? Reuses the
// detector (DRY): a candidate ending exactly here means this log closed a fast.
// Returns the fast length in hours, or 0. (Only food can end a fast.)
function fastEndedByItem(dateKey, timeStr) {
  if (!/^\d{2}:\d{2}$/.test(String(timeStr))) return 0;
  const target = dateKey + 'T' + timeStr;
  const c = detectFastCandidates().filter((x) => x.end === target)[0];
  return c ? c.hours : 0;
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

// ---- Mirror (Layer 2, D23): descriptive self-trends, READ-ONLY ---------------
// The feedback half — the person's own data over a window, figures only, no
// interpretation. WHO-INITIATES-THE-PAIRING line: v1 is single-variable only.
const TREND_MIN_POINTS = 3;                                 // never draw a 2-point "trend"
let TREND_WINDOW = 90;                                      // UI state (non-persisted, v1)
// Finite per-type unit conversion (the D20/D22 pin). Only truly inter-convertible
// units; a type absent here has single/non-convertible units (a record is kept only
// if its unit already matches the target — e.g. breath-ketones ppm vs mmol/L measure
// DIFFERENT things and must never be force-converted).
const UNIT_CONVERT = {
  weight:  { 'kg>lb': function (v) { return v * 2.2046226; }, 'lb>kg': function (v) { return v / 2.2046226; } },
  glucose: { 'mg/dL>mmol/L': function (v) { return v / 18.0182; }, 'mmol/L>mg/dL': function (v) { return v * 18.0182; } },
};
// CONTRACT (D34, changed): null means NOT CONVERTIBLE — the caller must DISPLAY
// THE READING AS ENTERED, unconverted and LABELLED with its own unit. It must
// NEVER drop the point. Silently excluding an unconvertible reading is how an
// analyte vanishes from its own series; that is the one behaviour this contract
// exists to forbid.
function convertUnit(type, value, fromU, toU) {
  if (fromU === toU) return num(value);
  const tbl = UNIT_CONVERT[type] || LAB_CONVERT[type];
  const fn = tbl && tbl[fromU + '>' + toU];
  return fn ? fn(num(value)) : null;                        // null = display as entered + labelled, NEVER dropped
}
function windowCutoff(days) {
  if (!days || days === 'all') return '0000-00-00';         // include everything
  const c = new Date(localDate() + 'T00:00:00');
  c.setDate(c.getDate() - (days - 1));
  return localDate(c);
}
// A biometric series in ONE unit over a window: every reading, time-ordered,
// normalized to the type's current display unit; off-unit non-convertible readings
// EXCLUDED (counted for an honest coverage note — absence != fabrication).
function signalSeries(type, days) {
  const spec = SIGNAL_BY_TYPE[type];
  const targetUnit = signalUnitDefault(type);
  const cut = windowCutoff(days);
  const pts = []; let unconverted = 0, total = 0;
  Object.keys(APP_STATE.timeline || {}).forEach((d) => {
    if (d < cut) return;
    (APP_STATE.timeline[d] || []).forEach((r) => {
      if (r.type !== type || r.value == null) return;
      total++;
      const from = r.unit || targetUnit;
      const v = convertUnit(type, r.value, from, targetUnit);
      // D34 contract: an unconvertible reading is KEPT, as entered and labelled
      // with its own unit — never excluded. `excluded` is retained at 0 for
      // callers that still read it, and is now always 0 by construction.
      if (v == null) {
        unconverted++;
        pts.push({ t: d + 'T' + (r.time || '00:00'), v: Math.round(num(r.value) * 100) / 100, unit: from, converted: false });
        return;
      }
      pts.push({ t: d + 'T' + (r.time || '00:00'), v: Math.round(v * 100) / 100 });
    });
  });
  pts.sort((a, b) => (a.t < b.t ? -1 : a.t > b.t ? 1 : 0));
  return { type: type, label: spec ? spec.label : type, unit: targetUnit, points: pts,
           excluded: 0, unconverted: unconverted, total: total };
}
// Factual summary only (no interpretation): latest, min, max, avg, delta, n.
function seriesSummary(s) {
  // D34: the series KEEPS every reading (nothing vanishes), but statistics are
  // computed over the CONVERTED ones only — averaging ppm with mmol/L would be a
  // worse dishonesty than the drop this contract replaced. The unconverted count
  // is reported so the caller can state them explicitly instead.
  const conv = s.points.filter((p) => p.converted !== false);
  const vals = conv.map((p) => p.v);
  const n = vals.length;
  if (!n) return { n: 0, unconverted: s.points.length };
  const sum = vals.reduce((a, b) => a + b, 0);
  const r2 = (x) => Math.round(x * 100) / 100;
  return { n: n, latest: vals[n - 1], min: Math.min.apply(null, vals), max: Math.max.apply(null, vals),
           avg: r2(sum / n), delta: r2(vals[n - 1] - vals[0]), unconverted: s.points.length - n };
}
// Macro trend: daily total of a nutrient over the window, COMPLETE DAYS ONLY (D10).
function macroSeries(nutrient, days) {
  const cut = windowCutoff(days);
  const pts = [];
  Object.keys(APP_STATE.days || {}).forEach((d) => {
    if (d < cut) return;
    const day = APP_STATE.days[d];
    if (!day || day.status !== 'complete') return;          // complete days only (labeled in the view)
    pts.push({ t: d, v: Math.round(num(dayTotals(day)[nutrient]) * 10) / 10 });
  });
  pts.sort((a, b) => (a.t < b.t ? -1 : a.t > b.t ? 1 : 0));
  return { nutrient: nutrient, points: pts };
}
// Fasting stats over a window, CONFIRMED only (D22). Streak = consecutive days
// (ending today, else yesterday) with a confirmed fast; pending candidates in-window
// are surfaced ("N unresolved") — never inflate (pending != fasted) nor silently hide
// that resolving could change it (the streak pin).
function fastingStats(days) {
  const cut = windowCutoff(days);
  const cands = detectFastCandidates();
  const confirmed = cands.filter((c) => c.state === 'fasted' && c.end.slice(0, 10) >= cut);
  const pendingInWin = cands.filter((c) => c.state === 'pending' && c.end.slice(0, 10) >= cut).length;
  const hrs = confirmed.map((c) => c.hours);
  const confirmedDays = {};
  confirmed.forEach((c) => { confirmedDays[c.end.slice(0, 10)] = true; });
  let streak = 0;
  const cur = new Date(localDate() + 'T00:00:00');
  if (!confirmedDays[localDate(cur)]) cur.setDate(cur.getDate() - 1);   // a fast completed yesterday still counts as current
  while (confirmedDays[localDate(cur)]) { streak++; cur.setDate(cur.getDate() - 1); }
  return {
    count: confirmed.length,
    avg: hrs.length ? Math.round((hrs.reduce((a, b) => a + b, 0) / hrs.length) * 10) / 10 : 0,
    longest: hrs.length ? Math.max.apply(null, hrs) : 0,
    streak: streak, pending: pendingInWin,
  };
}
// Hand-rolled inline SVG sparkline (theme-aware via CSS; no deps). Optional refVal
// draws a NEUTRAL dashed goal line (D24: no met/unmet color — the goal is factual,
// the user judges the gap); the value range expands to keep the line visible.
function sparklineSVG(points, refVal) {
  const W = 240, H = 40, pad = 3;
  if (!points.length) return '';
  const vs = points.map((p) => p.v);
  let mn = Math.min.apply(null, vs), mx = Math.max.apply(null, vs);
  if (refVal != null) { mn = Math.min(mn, refVal); mx = Math.max(mx, refVal); }
  const span = (mx - mn) || 1, n = points.length;
  const yFor = (v) => H - pad - ((v - mn) / span) * (H - 2 * pad);
  const pts = points.map((p, i) => {
    const x = n === 1 ? W / 2 : pad + (i / (n - 1)) * (W - 2 * pad);
    return (Math.round(x * 10) / 10) + ',' + (Math.round(yFor(p.v) * 10) / 10);
  }).join(' ');
  const dot = n === 1 ? `<circle cx="${W / 2}" cy="${refVal != null ? Math.round(yFor(vs[0]) * 10) / 10 : H / 2}" r="2.5"/>` : '';
  const ref = refVal != null ? `<line class="tref" x1="${pad}" y1="${Math.round(yFor(refVal) * 10) / 10}" x2="${W - pad}" y2="${Math.round(yFor(refVal) * 10) / 10}"/>` : '';
  return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true">${ref}<polyline points="${pts}"/>${dot}</svg>`;
}
function setTrendWindow(d) { TREND_WINDOW = d; renderTrends(); }
function renderTrends() {
  const el = document.getElementById('trends'); if (!el || !APP_STATE) return;
  const win = TREND_WINDOW;
  const winLabel = win === 'all' ? 'all time' : ('last ' + win + ' days');
  let html = '<div class="twin">' + [30, 90, 'all'].map((w) =>
    `<button type="button" class="${w === win ? 'on' : ''}" onclick="setTrendWindow(${w === 'all' ? "'all'" : w})">${w === 'all' ? 'All' : w + 'd'}</button>`).join('') + '</div>';
  let bio = '';
  SIGNAL_SPEC.forEach((sp) => {
    if (sp.kind !== 'biometric') return;
    const s = signalSeries(sp.type, win);
    if (s.points.length < TREND_MIN_POINTS) return;          // min-data
    const sm = seriesSummary(s);
    const plot = s.points.filter((p) => p.converted !== false);
    const asEntered = s.points.filter((p) => p.converted === false);
    // D34 contract: an unconvertible reading is SHOWN AS ENTERED and labelled --
    // never dropped, and never plotted on a scale it does not belong to.
    const cov = asEntered.length
      ? ` <small class="tcov">${esc(asEntered.length)} shown as entered in ${esc(asEntered[0].unit)} — not converted</small>` : '';
    if (sm.n === 0) {                                        // every reading unconverted: still show them
      bio += `<div class="trow"><div class="thead">${esc(s.label)}${cov}</div>`
        + `<div class="tsum">${asEntered.map((p) => esc(rDisp(p.v)) + ' ' + esc(p.unit)).join(' · ')}</div></div>`;
      return;
    }
    // D24 signal goal: factual target + a neutral reference line (fully neutral — no
    // met/unmet color/word). Normalize the goal to the series unit; a non-convertible
    // goal unit surfaces the mismatch and is not drawn (same never-force rule as D23).
    const goal = (APP_STATE.settings.goals || {})[sp.type];
    let goalStr = '', refVal = null;
    if (goal && goal.value != null) {
      const gv = convertUnit(sp.type, goal.value, goal.unit || s.unit, s.unit);
      if (gv == null) goalStr = ` <small class="tcov">target set in ${esc(goal.unit || '?')} — not comparable to ${esc(s.unit)}</small>`;
      else { refVal = gv; goalStr = ` <small class="tgoal">target ${goal.direction === 'max' ? '&le;' : '&ge;'} ${esc(rDisp(gv))} ${esc(s.unit)}</small>`; }
    }
    bio += `<div class="trow"><div class="thead">${esc(s.label)} <small>${esc(s.unit)}</small>${cov}${goalStr}</div>${sparklineSVG(plot, refVal)}`
      + `<div class="tsum">latest ${esc(rDisp(sm.latest))} · avg ${esc(rDisp(sm.avg))} · ${esc(rDisp(sm.min))}–${esc(rDisp(sm.max))} · &Delta; ${sm.delta >= 0 ? '+' : ''}${esc(rDisp(sm.delta))} · n=${esc(sm.n)}`
      + (sm.unconverted > 0 ? ` <small class="tcov">avg over ${esc(sm.n)} of ${esc(sm.n + sm.unconverted)} readings (${esc(sm.unconverted)} unconverted, shown as entered)</small>` : '')
      + `</div></div>`;
  });
  html += bio;
  const fs = fastingStats(win);
  if (fs.count > 0 || fs.pending > 0) {
    const pend = fs.pending > 0 ? ` <small class="tcov">${esc(fs.pending)} unresolved — resolve to update</small>` : '';
    html += `<div class="trow"><div class="thead">Fasting</div><div class="tsum">streak ${esc(fs.streak)} day${fs.streak === 1 ? '' : 's'}${pend} · ${esc(fs.count)} confirmed · avg ${esc(rDisp(fs.avg))}h · longest ${esc(rDisp(fs.longest))}h</div></div>`;
  }
  const ms = macroSeries('kcal', win);
  let macroShown = false;
  if (ms.points.length >= TREND_MIN_POINTS) {
    macroShown = true;
    const mv = ms.points.map((p) => p.v);
    const avg = Math.round(mv.reduce((a, b) => a + b, 0) / mv.length);
    html += `<div class="trow"><div class="thead">Energy <small>kcal · complete days only</small></div>${sparklineSVG(ms.points)}`
      + `<div class="tsum">avg ${esc(avg)} · ${esc(Math.min.apply(null, mv))}–${esc(Math.max.apply(null, mv))} · n=${esc(ms.points.length)}</div></div>`;
  }
  if (!bio && fs.count === 0 && fs.pending === 0 && !macroShown)
    html += `<div class="note" style="margin:8px 0 0">Keep logging — trends appear here once you have a few days of data (${esc(winLabel)}).</div>`;
  else
    html += `<div class="note" style="margin:10px 0 0">Your own data over ${esc(winLabel)} — figures only, no interpretation.</div>`;
  el.innerHTML = html;
}

// ---- Nudge (Layer 3, D25): paced, established-practice-only good habits --------
// Curriculum is CONTENT (builder-authored); list order = offer order. Delivery
// machinery only. Readiness + offer key on ENGAGEMENT (days logged), never on what
// the readings SAY. Accept = a current focus with a factual wear-indicator (linked
// occurrence counts/dates, never values). No check-ins, no scoring, no scold.
const NUDGE_CURRICULUM = [
  { id: 'walk_after_dinner',   title: 'A short walk after dinner',         rationale: 'Many people find a 10-minute walk after dinner an easy add.',        category: 'movement',  linkedType: 'walk' },
  { id: 'veg_at_lunch',        title: 'A vegetable at lunch',              rationale: 'Adding one vegetable to lunch is a small, repeatable change.',       category: 'nutrition' },
  { id: 'water_before_coffee', title: 'Water before your first coffee',    rationale: 'A glass of water on waking, before your coffee.',                   category: 'hydration' },
  { id: 'protein_breakfast',   title: 'Some protein at breakfast',         rationale: 'Front-loading a little protein at breakfast works for many.',        category: 'nutrition' },
  { id: 'morning_daylight',    title: 'A few minutes of morning daylight', rationale: 'A short spell of outdoor daylight early in the day.',                category: 'circadian' },
  { id: 'winddown_before_bed', title: 'A wind-down before bed',            rationale: 'Dimming screens ~30 min before bed is a common wind-down.',          category: 'sleep' },
  { id: 'stand_hourly',        title: 'Stand and stretch hourly',          rationale: 'A brief stand or stretch once an hour breaks up long sitting.',      category: 'movement' },
];
const NUDGE_BY_ID = NUDGE_CURRICULUM.reduce((m, h) => { m[h.id] = h; return m; }, {});
const NUDGE_MIN_DAYS = 7, NUDGE_MIN_ELAPSED = 7, NUDGE_INTERVAL_DAYS = 5, NUDGE_SNOOZE_DAYS = 7, NUDGE_ADHERENCE_DAYS = 7;
const NUDGE_WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
let NUDGE_BROWSE_OPEN = false;

function dateDaysAgo(n) { const c = new Date(localDate() + 'T00:00:00'); c.setDate(c.getDate() - n); return localDate(c); }
function nudgeState() { const n = APP_STATE.settings && APP_STATE.settings.nudges; return (n && typeof n === 'object') ? n : { enabled: true, habits: {} }; }
function nudgeLinkLabel(lt) { const s = SIGNAL_BY_TYPE[lt]; return s ? s.label.toLowerCase() : lt; }

// ENGAGEMENT ONLY: distinct calendar days the user actively logged (a non-_auto food
// item, or any timeline record). Reads only THAT a day has a log, never WHAT.
function loggedDays() {
  const s = {};
  Object.keys(APP_STATE.days || {}).forEach((d) => { if ((APP_STATE.days[d].items || []).some((i) => !i._auto)) s[d] = 1; });
  Object.keys(APP_STATE.timeline || {}).forEach((d) => { if ((APP_STATE.timeline[d] || []).length) s[d] = 1; });
  return Object.keys(s).sort();
}
function nudgeReady() {
  const days = loggedDays();
  if (days.length < NUDGE_MIN_DAYS) return false;
  return Math.floor((Date.parse(localDate() + 'T00:00:00') - Date.parse(days[0] + 'T00:00:00')) / 86400000) >= NUDGE_MIN_ELAPSED;
}
// One focus, else (ready + interval elapsed) the next eligible habit in curriculum
// order, else nothing. Depends ONLY on engagement (day COUNT) + persisted state.
function currentNudge() {
  const cfg = nudgeState();
  if (cfg.enabled === false) return { kind: 'off' };
  const habits = cfg.habits || {};
  const focus = NUDGE_CURRICULUM.map((h) => h.id).filter((id) => habits[id] && habits[id].state === 'accepted')[0];
  if (focus) return { kind: 'focus', id: focus };
  if (!nudgeReady()) return { kind: 'none' };
  const resolved = Object.keys(habits).filter((id) => ['declined', 'snoozed', 'retired'].indexOf(habits[id].state) >= 0)
    .map((id) => String(habits[id].at || '').slice(0, 10)).filter(Boolean).sort();
  const last = resolved.length ? resolved[resolved.length - 1] : '';
  if (last && last > dateDaysAgo(NUDGE_INTERVAL_DAYS)) return { kind: 'none' };   // quiet interval since last resolution
  const next = NUDGE_CURRICULUM.filter((h) => {
    const st = habits[h.id];
    if (!st) return true;
    if (st.state === 'snoozed') return String(st.at || '').slice(0, 10) <= dateDaysAgo(NUDGE_SNOOZE_DAYS);
    return false;                                                                 // accepted/declined/retired -> not eligible
  })[0];
  return next ? { kind: 'offer', id: next.id } : { kind: 'none' };
}
// The wear-indicator (D25): counts the linkedType's timeline OCCURRENCES (dates only,
// NEVER values) since acceptance, within the window. Value-blind by construction.
function focusAdherence(id) {
  const h = NUDGE_BY_ID[id]; const st = nudgeState().habits[id];
  if (!h || !h.linkedType || !st) return null;
  const since = String(st.at || '').slice(0, 10);
  const dates = [];
  Object.keys(APP_STATE.timeline || {}).forEach((d) => {
    if (since && d < since) return;
    (APP_STATE.timeline[d] || []).forEach((r) => { if (r.type === h.linkedType) dates.push(d); });   // occurrence, not value
  });
  dates.sort();
  const recent = dates.filter((d) => d >= dateDaysAgo(NUDGE_ADHERENCE_DAYS - 1));
  return { type: h.linkedType, count: recent.length, last: dates.length ? dates[dates.length - 1] : '' };
}
function setNudge(id, state) {
  if (!NUDGE_BY_ID[id]) return { ok: false };
  if (!APP_STATE.settings.nudges) APP_STATE.settings.nudges = { enabled: true, habits: {} };
  const habits = APP_STATE.settings.nudges.habits = APP_STATE.settings.nudges.habits || {};
  if (state === 'accepted') Object.keys(habits).forEach((k) => { if (habits[k].state === 'accepted') habits[k] = { state: 'retired', at: new Date().toISOString() }; });   // one focus at a time
  habits[id] = { state: state, at: new Date().toISOString() };
  Store.saveState(APP_STATE); refresh();
  return { ok: true };
}
function acceptNudge(id) { return setNudge(id, 'accepted'); }
function declineNudge(id) { return setNudge(id, 'declined'); }
function snoozeNudge(id) { return setNudge(id, 'snoozed'); }
function retireNudge(id) { return setNudge(id, 'retired'); }
function setNudgesEnabled(on) {
  if (!APP_STATE.settings.nudges) APP_STATE.settings.nudges = { enabled: true, habits: {} };
  APP_STATE.settings.nudges.enabled = !!on;
  Store.saveState(APP_STATE); refresh();
}
function toggleNudgeBrowse() { NUDGE_BROWSE_OPEN = !NUDGE_BROWSE_OPEN; renderNudge(); }
function renderNudgeBrowse() {
  const habits = nudgeState().habits || {};
  return '<div class="nbrowse">' + NUDGE_CURRICULUM.map((h) => {
    const st = habits[h.id];
    const lbl = st ? (st.state === 'accepted' ? 'focus' : st.state) : '';
    const act = (!st || st.state !== 'accepted') ? `<button type="button" class="linklike" onclick="acceptNudge('${h.id}')">Focus on this</button>` : '';
    return `<div class="nbrow"><span class="nbtitle">${esc(h.title)}${lbl ? ` <small>${esc(lbl)}</small>` : ''}</span>${act}</div>`;
  }).join('') + '</div>';
}
function renderNudge() {
  const el = document.getElementById('nudge'); if (!el || !APP_STATE) return;
  const en = document.getElementById('nudgeEnabled'); if (en) en.checked = nudgeState().enabled !== false;
  const cur = currentNudge();
  if (cur.kind === 'off') { el.innerHTML = ''; return; }
  let html = '';
  if (cur.kind === 'offer') {
    const h = NUDGE_BY_ID[cur.id];
    html += `<div class="nudgeoffer"><div class="nudgetitle">${esc(h.title)}</div><div class="nudgewhy">${esc(h.rationale)}</div>`
      + (h.howTo ? `<div class="nudgewhy">${esc(h.howTo)}</div>` : '')
      + `<div class="nudgebtns"><button type="button" class="btn" onclick="acceptNudge('${h.id}')">Worth trying</button>`
      + `<button type="button" class="linklike" onclick="snoozeNudge('${h.id}')">Not now</button>`
      + `<button type="button" class="linklike" onclick="declineNudge('${h.id}')">Not for me</button></div></div>`;
  } else if (cur.kind === 'focus') {
    const h = NUDGE_BY_ID[cur.id]; const ad = focusAdherence(cur.id);
    let adh = '';
    if (ad) adh = ad.count > 0
      ? `<div class="nudgeadh">${esc(nudgeLinkLabel(ad.type))} logged ${esc(ad.count)} time${ad.count === 1 ? '' : 's'} in the last ${NUDGE_ADHERENCE_DAYS} days${ad.last ? ' · last: ' + esc(NUDGE_WD[new Date(ad.last + 'T00:00:00').getDay()]) : ''}</div>`
      : `<div class="nudgeadh">no ${esc(nudgeLinkLabel(ad.type))} logged in the last ${NUDGE_ADHERENCE_DAYS} days</div>`;
    html += `<div class="nudgefocus"><div class="nudgetitle">Current focus: ${esc(h.title)}</div>${adh}<button type="button" class="linklike" onclick="retireNudge('${h.id}')">Got it — retire</button></div>`;
  }
  html += `<div class="nbrowsewrap"><button type="button" class="linklike" onclick="toggleNudgeBrowse()">${NUDGE_BROWSE_OPEN ? 'Hide all habits' : 'Browse all habits'}</button>${NUDGE_BROWSE_OPEN ? renderNudgeBrowse() : ''}</div>`;
  el.innerHTML = html;
}

// ---- Regimen (D27): a named timeline template for a repeating day ------------
// Composition over existing machinery; NEVER auto-logs. JSON paste-authoring with
// specific per-entry errors + a self-consistency-gated in-app template/sample.
const REGIMEN_TEMPLATE = [
  'Paste a regimen as JSON. Shape:',
  '{',
  '  "name": "My protocol",',
  '  "window": { "start": "12:00", "end": "18:00" },        // optional eating window (display only)',
  '  "entries": [',
  '    { "kind": "medication", "time": "04:30", "name": "Nattokinase", "dose": 2000, "dose_unit": "unit" },',
  '    { "kind": "event", "time": "05:30", "type": "red_light", "value": 10, "unit": "min" },',
  '    { "kind": "food", "time": "12:00", "presetId": "<a saved preset id>" },',
  '    { "kind": "food", "time": "18:00", "presetId": "<preset id>", "days": [1,3,5,0] }   // Mon/Wed/Fri/Sun (Sun=0)',
  '  ]',
  '}',
  'kind is food | medication | event. time is "HH:MM". days is optional [0-6] (Sun=0); omit for every day.',
  'food references a SAVED preset by id; medication uses name/dose/dose_unit; event uses an event type.',
].join('\n');
const REGIMEN_SAMPLE = JSON.stringify({
  name: 'Sample day',
  window: { start: '12:00', end: '18:00' },
  entries: [
    { kind: 'medication', time: '04:30', name: 'Nattokinase', dose: 2000, dose_unit: 'unit' },
    { kind: 'event', time: '05:30', type: 'red_light', value: 10, unit: 'min' },
    { kind: 'food', time: '12:00', presetId: 'lunch' },
  ],
}, null, 2);
let REGIMEN_CONFIRM = null;   // inline confirm state: {entryId, reason, ...}

// Strict authoring boundary: cleanJSON + validate with SPECIFIC per-entry messages.
function parseRegimen(raw) {
  const text = cleanJSON(raw);
  if (!text) return { ok: false, error: 'Nothing to load.' };
  let o; try { o = JSON.parse(text); } catch (e) { return { ok: false, error: 'Bad JSON: ' + e.message }; }
  if (!o || typeof o !== 'object' || Array.isArray(o)) return { ok: false, error: 'A regimen must be a JSON object.' };
  if (!o.name || String(o.name).trim() === '') return { ok: false, error: 'Regimen needs a "name".' };
  if (!Array.isArray(o.entries) || !o.entries.length) return { ok: false, error: 'Regimen needs a non-empty "entries" array.' };
  if (o.window && (!/^\d{2}:\d{2}$/.test(String(o.window.start || '')) || !/^\d{2}:\d{2}$/.test(String(o.window.end || ''))))
    return { ok: false, error: 'window.start / window.end must be "HH:MM".' };
  const presets = (APP_STATE.settings && APP_STATE.settings.presets) || [];
  for (let i = 0; i < o.entries.length; i++) {
    const e = o.entries[i]; const at = 'entry ' + (i + 1) + ': ';
    if (!e || typeof e !== 'object') return { ok: false, error: at + 'not an object.' };
    if (REGIMEN_KINDS.indexOf(e.kind) < 0) return { ok: false, error: at + 'kind must be food | medication | event.' };
    if (!/^\d{2}:\d{2}$/.test(String(e.time || ''))) return { ok: false, error: at + '(' + e.kind + ') time must be "HH:MM".' };
    if (e.days != null && (!Array.isArray(e.days) || !e.days.every((x) => Number.isInteger(x) && x >= 0 && x <= 6))) return { ok: false, error: at + 'days must be an array of 0-6 (Sun=0).' };
    if (e.kind === 'food' && (!e.presetId || String(e.presetId).trim() === '')) return { ok: false, error: at + 'food needs a "presetId".' };
    if (e.kind === 'food' && !presets.some((p) => p.id === e.presetId)) return { ok: false, error: at + 'presetId "' + e.presetId + '" matches no saved preset.' };
    if (e.kind === 'medication' && (!e.name || String(e.name).trim() === '')) return { ok: false, error: at + 'medication needs a "name".' };
    if (e.kind === 'event' && (!e.type || String(e.type).trim() === '')) return { ok: false, error: at + 'event needs a "type".' };
  }
  const reg = normalizeRegimen(o);
  if (!reg.id) reg.id = 'reg_' + ((APP_STATE.regimens && APP_STATE.regimens.list.length) || 0) + '_' + String(o.name).replace(/[^a-z0-9]/gi, '').slice(0, 10).toLowerCase();
  reg.entries.forEach((en, idx) => { if (!en.id) en.id = reg.id + '_e' + idx; });
  return { ok: true, regimen: reg };
}
function addRegimenFromJSON(raw) {
  const r = parseRegimen(raw);
  if (!r.ok) return r;
  if (!APP_STATE.regimens) APP_STATE.regimens = { active: '', list: [], log: {} };
  APP_STATE.regimens.list.push(r.regimen);
  if (!APP_STATE.regimens.active) APP_STATE.regimens.active = r.regimen.id;
  Store.saveState(APP_STATE); refresh();
  return { ok: true, regimen: r.regimen };
}
function setActiveRegimen(id) { if (APP_STATE.regimens) { APP_STATE.regimens.active = String(id || ''); Store.saveState(APP_STATE); refresh(); } }
function deleteRegimen(id) {   // template only — fulfillment log + logged records untouched (D27/Fork E)
  const rg = APP_STATE.regimens; if (!rg) return;
  rg.list = rg.list.filter((r) => r.id !== id);
  if (rg.active === id) rg.active = rg.list.length ? rg.list[0].id : '';
  Store.saveState(APP_STATE); refresh();
}
function activeRegimen() { const rg = APP_STATE.regimens; if (!rg || !rg.active) return null; return (rg.list || []).filter((r) => r.id === rg.active)[0] || null; }
function todayWeekday() { return new Date(localDate() + 'T00:00:00').getDay(); }
function regimenToday() {
  const reg = activeRegimen(); if (!reg) return null;
  const wd = todayWeekday(), today = localDate();
  const flags = (APP_STATE.regimens.log && APP_STATE.regimens.log[today]) || {};
  const entries = (reg.entries || []).filter((e) => !e.days || e.days.indexOf(wd) >= 0)
    .map((e) => ({ entry: e, fulfilled: flags[e.id] || '' }))
    .sort((a, b) => (a.entry.time < b.entry.time ? -1 : a.entry.time > b.entry.time ? 1 : 0));
  return { regimen: reg, window: reg.window, entries: entries };
}
function timeToMin(t) { const m = /^(\d{2}):(\d{2})$/.exec(String(t)); return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : null; }
function isGrosslyLate(scheduled, now) { const s = timeToMin(scheduled), n = timeToMin(now); return (s == null || n == null) ? false : Math.abs(n - s) > 120; }
function setFulfillment(entryId, kind) {   // 'template' | 'substituted' | null(clear)
  const rg = APP_STATE.regimens; if (!rg) return;
  if (!rg.log) rg.log = {};
  const today = localDate();
  if (kind === null) { if (rg.log[today]) { delete rg.log[today][entryId]; if (!Object.keys(rg.log[today]).length) delete rg.log[today]; } }
  else { if (!rg.log[today]) rg.log[today] = {}; rg.log[today][entryId] = kind; }
}
// Instantiate an entry through the SAME machinery (byte-identical record) + set a
// 'template' fulfillment flag. Confirm-gated: grossly-late surfaces the scheduled
// time; an already-fulfilled entry asks. Undo removes BOTH the record and the flag.
function logRegimenEntry(entryId, opts) {
  opts = opts || {};
  const reg = activeRegimen(); if (!reg) return { ok: false, error: 'No active regimen.' };
  const e = (reg.entries || []).filter((x) => x.id === entryId)[0];
  if (!e) return { ok: false, error: 'Entry not found.' };
  const today = localDate();
  const already = ((APP_STATE.regimens.log || {})[today] || {})[entryId];
  if (already && !opts.force) return { ok: false, needsConfirm: 'already', message: 'Already marked ' + (already === 'substituted' ? 'logged elsewhere' : 'logged') + ' — log again?' };
  const now = opts.now || nowTime();
  if (isGrosslyLate(e.time, now) && !opts.confirmedLate && !opts.time) return { ok: false, needsConfirm: 'late', scheduledTime: e.time, message: 'Log at ' + e.time + ' (scheduled)?' };
  const t = opts.time || e.time || now;
  let record = null, arr = null;
  if (e.kind === 'food') {
    const p = ((APP_STATE.settings && APP_STATE.settings.presets) || []).filter((x) => x.id === e.presetId)[0];
    if (!p) return { ok: false, error: 'The preset for this entry was deleted.' };
    const day = curDay(); if (!day) return { ok: false };
    if (day.status === 'complete') day.status = 'in_progress';
    record = buildPresetItem(p, t); day.items.push(record); arr = day.items;
  } else if (e.kind === 'medication') {
    const r = addSignal({ kind: 'medication', name: e.name, dose: e.dose, dose_unit: e.dose_unit, form: e.form, route: e.route, time: t, notes: e.notes });
    if (!r.ok) return r; record = r.record; arr = APP_STATE.timeline[localDate()];
  } else {
    const r = addSignal({ type: e.type, value: e.value, unit: e.unit, time: t, notes: e.notes });
    if (!r.ok) return r; record = r.record; arr = APP_STATE.timeline[localDate()];
  }
  setFulfillment(entryId, 'template');
  Store.saveState(APP_STATE); refresh();
  const lbl = e.kind === 'food' ? record.name : (e.kind === 'medication' ? (e.name || 'medication') : (SIGNAL_BY_TYPE[e.type] ? SIGNAL_BY_TYPE[e.type].label : e.type));
  offerUndo('Logged ' + lbl, function () { if (Array.isArray(arr)) { const i = arr.indexOf(record); if (i >= 0) arr.splice(i, 1); } setFulfillment(entryId, null); Store.saveState(APP_STATE); refresh(); });
  return { ok: true, record: record };
}
function substituteRegimenEntry(entryId) {   // attest a substitution -> a FLAG, no record
  const reg = activeRegimen(); if (!reg || !(reg.entries || []).some((x) => x.id === entryId)) return { ok: false };
  setFulfillment(entryId, 'substituted'); Store.saveState(APP_STATE); refresh(); return { ok: true };
}
function unfulfillRegimenEntry(entryId) { setFulfillment(entryId, null); Store.saveState(APP_STATE); refresh(); return { ok: true }; }
function regimenEntryDesc(e) {
  if (e.kind === 'food') { const p = ((APP_STATE.settings && APP_STATE.settings.presets) || []).filter((x) => x.id === e.presetId)[0]; return esc(p ? p.name : '(preset missing)'); }
  if (e.kind === 'medication') return esc(e.name || 'medication') + (e.dose != null ? ' <small>' + esc(rDisp(e.dose)) + ' ' + esc(e.dose_unit || '') + '</small>' : '');
  const sp = SIGNAL_BY_TYPE[e.type]; return esc(sp ? sp.label : e.type) + (e.value != null ? ' <small>' + esc(rDisp(e.value)) + ' ' + esc(e.unit || '') + '</small>' : '');
}
function regimenLogTap(entryId) {
  const r = logRegimenEntry(entryId);
  if (r.ok) { REGIMEN_CONFIRM = null; return; }
  if (r.needsConfirm) { REGIMEN_CONFIRM = { entryId: entryId, reason: r.needsConfirm, scheduledTime: r.scheduledTime, message: r.message }; renderRegimenChecklist(); return; }
  toast(r.error || 'Could not log');
}
function regimenConfirmLog(entryId, mode) {
  const reason = REGIMEN_CONFIRM ? REGIMEN_CONFIRM.reason : '';
  REGIMEN_CONFIRM = null;
  const opts = { force: true };
  if (mode === 'now') opts.time = nowTime(); else if (reason === 'late') opts.confirmedLate = true;
  const r = logRegimenEntry(entryId, opts);
  if (!r.ok) toast(r.error || 'Could not log');
}
function regimenConfirmCancel() { REGIMEN_CONFIRM = null; renderRegimenChecklist(); }
function renderRegimenChecklist() {
  const el = document.getElementById('regimenChecklist'); if (!el || !APP_STATE) return;
  const rt = regimenToday();
  if (!rt || !rt.entries.length) { el.innerHTML = ''; return; }        // silent-empty (Pin 3 / RG-empty)
  let html = '<div class="rgtitle">Today’s regimen</div>';
  if (rt.window) html += `<div class="rgwindow">eating window ${esc(rt.window.start)}–${esc(rt.window.end)}</div>`;
  html += rt.entries.map((x) => {
    const e = x.entry, tag = e.kind;
    if (REGIMEN_CONFIRM && REGIMEN_CONFIRM.entryId === e.id) {
      const late = REGIMEN_CONFIRM.reason === 'late';
      return `<div class="rgrow confirm"><span class="rgtime">${esc(e.time)}</span><span class="rgmain">${esc(REGIMEN_CONFIRM.message)}`
        + `<span class="rgbtns"><button type="button" class="linklike" onclick="regimenConfirmLog('${e.id}','scheduled')">${late ? 'Log ' + esc(e.time) : 'Yes, log again'}</button>`
        + (late ? `<button type="button" class="linklike" onclick="regimenConfirmLog('${e.id}','now')">Log now</button>` : '')
        + `<button type="button" class="linklike" onclick="regimenConfirmCancel()">cancel</button></span></span></div>`;
    }
    if (x.fulfilled) {
      const lbl = x.fulfilled === 'substituted' ? 'logged elsewhere' : 'logged';
      const undo = x.fulfilled === 'substituted' ? `<button type="button" class="linklike" onclick="unfulfillRegimenEntry('${e.id}')">undo</button>` : '';
      return `<div class="rgrow done"><span class="rgtime">${esc(e.time)}</span><span class="rgtag ${esc(tag)}">${esc(tag)}</span><span class="rgmain">${regimenEntryDesc(e)} <small>✓ ${esc(lbl)}</small></span>${undo}</div>`;
    }
    return `<div class="rgrow"><span class="rgtime">${esc(e.time)}</span><span class="rgtag ${esc(tag)}">${esc(tag)}</span><span class="rgmain">${regimenEntryDesc(e)}</span>`
      + `<span class="rgbtns"><button type="button" class="linklike" onclick="regimenLogTap('${e.id}')">Log</button>`
      + `<button type="button" class="linklike" onclick="substituteRegimenEntry('${e.id}')">Logged elsewhere</button></span></div>`;
  }).join('');
  el.innerHTML = html;
}
function renderRegimenAuthor() {
  const el = document.getElementById('regimenList'); if (!el || !APP_STATE) return;
  const rg = APP_STATE.regimens || { active: '', list: [] };
  if (!rg.list.length) { el.innerHTML = '<div class="note" style="margin:0 0 8px">No regimens yet — paste one below.</div>'; return; }
  el.innerHTML = rg.list.map((r) =>
    `<div class="rgmrow"><label class="checkline" style="margin:0"><input type="radio" name="rgactive" ${r.id === rg.active ? 'checked' : ''} onchange="setActiveRegimen('${r.id}')"> ${esc(r.name)} <small>${esc(r.entries.length)} entries</small></label><button type="button" class="linklike" onclick="deleteRegimen('${r.id}')">delete</button></div>`
  ).join('');
}
function doRegimenPaste() {
  const box = document.getElementById('regimenPaste');
  const r = addRegimenFromJSON(box ? box.value : '');
  const rep = document.getElementById('regimenReport');
  if (r.ok) { if (box) box.value = ''; if (rep) rep.innerHTML = ''; toast('Regimen "' + r.regimen.name + '" loaded'); }
  else if (rep) rep.innerHTML = `<div class="warn">${esc(r.error)}</div>`;
}
function copyRegimenTemplate() { if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(REGIMEN_TEMPLATE + '\n\n' + REGIMEN_SAMPLE).then(function () { toast('Template + sample copied'); }).catch(function () {}); }
function renderRegimenTemplate() { const el = document.getElementById('regimenTemplate'); if (el) el.textContent = REGIMEN_TEMPLATE + '\n\n' + REGIMEN_SAMPLE; }

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
// The collapsed "All days" line carries a signal, not just a label — a
// mini-mirror at a glance. Both counts are computed from the SAME key list the
// expanded rows render from, so the line can never disagree with the list
// (gated). `logged` is the number of day rows; `in progress` is the flagged
// subset. The <details> lives in the shell, so re-rendering never collapses it
// mid-use, and a reload resets it to collapsed (like the Trends window).
function historyCounts() {
  const keys = Object.keys((APP_STATE && APP_STATE.days) || {}).sort();
  let inProgress = 0;
  keys.forEach((d) => { if (APP_STATE.days[d].status !== 'complete') inProgress++; });
  return { keys: keys, logged: keys.length, inProgress: inProgress };
}
function renderHistorySummary() {
  const el = document.getElementById('historySummary');
  if (!el) return;
  const c = historyCounts();
  el.textContent = c.logged
    ? `All days · ${c.logged} logged · ${c.inProgress} in progress`
    : 'All days';
}
function renderHistory() {
  const el = document.getElementById('history');
  renderHistorySummary();
  if (!el || !APP_STATE) return;
  const keys = historyCounts().keys;
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
function refresh() { renderBadge(); renderOnboarding(); renderRegimenChecklist(); renderDay(); renderSignalChips(); renderQuickChips(); renderLabTrends(); renderFastCandidates(); renderTimelineOverlay(); renderTrends(); renderNudge(); renderAverages(); renderPresets(); renderRegimenAuthor(); renderScanButton(); renderScan(); renderHistory(); renderDataStatus(); }

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
  { v: '0.4.2', note: 'Tap the unit to switch it — kg/lb, mg/dL vs mmol/L, ppm vs mmol/L.' },
  { v: '0.4.3', note: 'Fix: on a mouse/desktop the quick-log chips now wrap to rows so every chip is reachable (they only scrolled by touch before).' },
  { v: '0.5.0', note: 'Fasting: long gaps between meals surface as candidates you resolve (fasted / ate-didn\'t-log) — pending never counts. Plus Undo on every log.' },
  { v: '0.5.1', note: 'Updates now also apply when you reopen the app from the switcher, not only on a full launch.' },
  { v: '0.6.0', note: 'Trends: see your own weight, biometrics, fasting streak, and energy over time — figures only, your data, no interpretation.' },
  { v: '0.6.1', note: 'Set targets on biometrics (weight, HRV, glucose, BP, …): they show as a line on your trend and float that signal to the front of the quick-log chips.' },
  { v: '0.7.0', note: 'Habits: after a couple of weeks of tracking, the app can gently suggest one established good habit at a time — always optional, one tap to pass, off in settings.' },
  { v: '0.8.0', note: 'Regimens: build a named daily template (meds, events, preset meals, weekday rotation, eating window) and work through today’s checklist — one tap logs each, nothing is ever auto-logged.' },
  { v: '0.8.1', note: 'New logs now also record your device’s time zone, so days logged while travelling stay accurate for later comparison. Nothing else changes, and nothing already logged is altered.' },
  { v: '0.9.0', note: 'Simpler main screen: it now shows your day, timeline, trends and averages, and one “+” button logs everything — scan, quick items, photo/AI paste, or manual. Setting things up (regimen, goals, supplement, presets, fasting, habits, export and restore) moved to Settings. Nothing was removed and nothing you have logged changed.' },
  { v: '0.9.1', note: 'Clearer entry points: the log button now reads “+ Log” and Settings is labelled, so nothing is hidden behind an icon. “All days” starts collapsed to a single line showing how many days you have logged.' },
  { v: '0.10.0', note: 'Lab panels: enter a dated blood panel (ApoB, LDL, HbA1c, fasting glucose, vitamin D, ferritin, liver, thyroid and more) and see each value against its reference range — cited Canadian targets where they exist, your own lab’s printed interval otherwise. Figures only, never a verdict.' },
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

// ---- Lab panels (D34) ------------------------------------------------------
// A dated lab panel enters as PER-VALUE biometric records with source 'lab',
// sharing an optional panelId (Fork A) — never a second record system (D27).
// LAB_SPEC is a SUB-REGISTRY (Fork B): authored separately because lab analytes
// carry reference-range metadata no other signal has, then MERGED into
// SIGNAL_BY_TYPE at load so normalizeSignal / signalSeries / chipLabel need no
// change. It is deliberately NOT merged into SIGNAL_SPEC: that array drives the
// event/biometric picker and the chip strip, and ApoB does not belong beside Sauna.
//
// CONTENT BAR (ruled, split two ways):
//  - GUIDELINE analytes carry a cited, versioned Canadian target (D32).
//  - LAB-INTERVAL analytes have no single honest universal range, so the honest
//    range is the REPORTING LAB'S PRINTED INTERVAL, entered by the user with the
//    value (`ref_src: 'lab-report'`). Five cited analytes, not fourteen.
const LAB_GUIDELINE = {
  ccs:  { org: 'Canadian Cardiovascular Society', cite: 'Pearson et al., Can J Cardiol 2021', version: '2021', jurisdiction: 'CA' },
  dc:   { org: 'Diabetes Canada',                 cite: 'Diabetes Canada Clinical Practice Guidelines', version: '2018', jurisdiction: 'CA' },
  // Origin citation is the 2010 CMAJ guideline; the target is still Osteoporosis
  // Canada's stated one per their Dec-2024 position statement, so the version
  // records both rather than implying the 2010 document is the latest word.
  osc:  { org: 'Osteoporosis Canada',             cite: 'Hanley et al., CMAJ 2010', version: '2010 (reaffirmed 2024)', jurisdiction: 'CA' },
};
// The CCS lipid tiers, stated in full so the overlay can never read as a single
// universal cutoff. The app displays these; it never selects a tier for the user.
const CCS_APPLICABILITY = 'general intensification threshold for statin-indicated patients; '
  + 'a stricter tier applies to very-high-risk secondary prevention (LDL-C \u2265 1.8 mmol/L / ApoB \u2265 0.7 g/L / non-HDL-C \u2265 2.4 mmol/L); '
  + 'CCS prefers non-HDL-C or ApoB over LDL-C when triglycerides exceed 1.5 mmol/L';
const LAB_SPEC = [
  // --- guideline-cited (5) ---
  // CCS lipid targets are RISK-STRATIFIED (statin-indicated vs primary prevention
  // by risk tier). A single band would silently assume a risk category, and the app
  // must never infer one — so lipids take the LAB'S PRINTED INTERVAL as their band
  // and carry the CCS figure as a LABELLED OVERLAY whose applicability is stated.
  { type: 'apo_b',            label: 'ApoB',              unit: 'g/L',      units: ['g/L', 'mg/dL'],        warn: 10,
    rangeSource: 'lab-report',
    overlay: Object.assign({ value: 0.80, direction: 'max', unit: 'g/L', applicability: CCS_APPLICABILITY }, LAB_GUIDELINE.ccs) },
  { type: 'ldl_c',            label: 'LDL-C',             unit: 'mmol/L',   units: ['mmol/L', 'mg/dL'],     warn: 30,
    rangeSource: 'lab-report',
    overlay: Object.assign({ value: 2.0, direction: 'max', unit: 'mmol/L', applicability: CCS_APPLICABILITY }, LAB_GUIDELINE.ccs) },
  { type: 'hba1c',            label: 'HbA1c',             unit: '%',        units: ['%', 'mmol/mol'],       warn: 25,
    guideline: LAB_GUIDELINE.dc,  bands: [{ max: 6.0, label: 'below the diabetes range' }, { min: 6.0, max: 6.5, label: 'in the prediabetes range (6.0 to under 6.5%)' }, { min: 6.5, label: 'at or above the diabetes threshold' }] },
  { type: 'glucose_fasting',  label: 'Fasting glucose',   unit: 'mmol/L',   units: ['mmol/L', 'mg/dL'],     warn: 60,
    guideline: LAB_GUIDELINE.dc,  bands: [{ max: 6.1, label: 'below the impaired-fasting-glucose range' }, { min: 6.1, max: 7.0, label: 'in the impaired-fasting-glucose range (6.1 to under 7.0 mmol/L)' }, { min: 7.0, label: 'at or above the diabetes threshold' }] },
  { type: 'vit_d_25oh',       label: '25-OH vitamin D',   unit: 'nmol/L',   units: ['nmol/L', 'ng/mL'],     warn: 1000,
    guideline: LAB_GUIDELINE.osc, bands: [{ max: 75, label: 'below the sufficiency threshold' }, { min: 75, label: 'at or above the sufficiency threshold' }],
    disclosure: 'Health Canada/IOM and many Canadian labs define sufficiency at 50 nmol/L; your lab\u2019s printed interval may differ from this target.' },
  // --- lab-report interval (9): the reporting lab's printed range is the honest one ---
  { type: 'hdl_c',            label: 'HDL-C',             unit: 'mmol/L',   units: ['mmol/L', 'mg/dL'],     warn: 20,  rangeSource: 'lab-report' },
  { type: 'triglycerides',    label: 'Triglycerides',     unit: 'mmol/L',   units: ['mmol/L', 'mg/dL'],     warn: 60,  rangeSource: 'lab-report' },
  { type: 'insulin_fasting',  label: 'Fasting insulin',   unit: 'uIU/mL',   units: ['uIU/mL', 'pmol/L'],    warn: 1000, rangeSource: 'lab-report' },
  { type: 'hs_crp',           label: 'hs-CRP',            unit: 'mg/L',     units: ['mg/L'],                warn: 500, rangeSource: 'lab-report' },
  { type: 'ferritin',         label: 'Ferritin',          unit: 'ug/L',     units: ['ug/L'],                warn: 5000, rangeSource: 'lab-report' },
  { type: 'alt',              label: 'ALT',               unit: 'U/L',      units: ['U/L'],                 warn: 2000, rangeSource: 'lab-report' },
  { type: 'ast',              label: 'AST',               unit: 'U/L',      units: ['U/L'],                 warn: 2000, rangeSource: 'lab-report' },
  { type: 'egfr',             label: 'eGFR',              unit: 'mL/min/1.73m2', units: ['mL/min/1.73m2'],  warn: 300, rangeSource: 'lab-report' },
  { type: 'tsh',              label: 'TSH',               unit: 'mIU/L',    units: ['mIU/L'],               warn: 500, rangeSource: 'lab-report' },
];
// Fork B's seam: one runtime lookup table, two authoring surfaces.
LAB_SPEC.forEach((s) => { SIGNAL_BY_TYPE[s.type] = Object.assign({ kind: 'biometric', lab: true }, s); });
const LAB_BY_TYPE = LAB_SPEC.reduce((m, s) => { m[s.type] = s; return m; }, {});
function isLabType(t) { return !!LAB_BY_TYPE[t]; }

// Per-analyte conversions for the convertible set (ruled). HbA1c is a FORMULA,
// not a factor (NGSP% <-> IFCC mmol/mol), so it cannot ride the multiply table.
// Everything else is store-as-entered — and, per the contract change below, an
// unconvertible reading is DISPLAYED AS ENTERED, never dropped.
const LAB_CONVERT = {
  glucose_fasting:  { 'mg/dL>mmol/L': (v) => v / 18.0182,  'mmol/L>mg/dL': (v) => v * 18.0182 },
  ldl_c:            { 'mg/dL>mmol/L': (v) => v / 38.67,    'mmol/L>mg/dL': (v) => v * 38.67 },
  hdl_c:            { 'mg/dL>mmol/L': (v) => v / 38.67,    'mmol/L>mg/dL': (v) => v * 38.67 },
  triglycerides:    { 'mg/dL>mmol/L': (v) => v / 88.57,    'mmol/L>mg/dL': (v) => v * 88.57 },
  vit_d_25oh:       { 'ng/mL>nmol/L': (v) => v * 2.496,    'nmol/L>ng/mL': (v) => v / 2.496 },
  insulin_fasting:  { 'uIU/mL>pmol/L': (v) => v * 6.945,   'pmol/L>uIU/mL': (v) => v / 6.945 },
  hba1c:            { '%>mmol/mol': (v) => (v - 2.15) * 10.929, 'mmol/mol>%': (v) => (v / 10.929) + 2.15 },
};

// Classify a value against its reference band. Returns null when NO range is
// available — the caller must still DISPLAY the value (a missing range is never
// a reason to hide a reading). `rec` supplies the lab-report interval.
function labBand(type, value, unit, rec) {
  const spec = LAB_BY_TYPE[type];
  if (!spec) return null;
  rec = rec || {};
  if (spec.guideline && spec.bands) {
    const v = convertUnit(type, value, unit || spec.unit, spec.unit);
    if (v == null) return null;                       // unconvertible -> no band claim, value still shown
    // HALF-OPEN intervals [min, max) -- deliberate and gated at the boundaries:
    // a reading exactly at 6.5 % or 7.0 mmol/L bands as the DIABETES range, not
    // below it. Never change `<` to `<=` here.
    for (let i = 0; i < spec.bands.length; i++) {
      const b = spec.bands[i];
      if ((b.min == null || v >= b.min) && (b.max == null || v < b.max))
        return { label: b.label, src: 'guideline', org: spec.guideline.org, cite: spec.guideline.cite, version: spec.guideline.version };
    }
    return null;
  }
  const lo = rec.ref_low, hi = rec.ref_high;
  if (lo == null && hi == null) return null;          // no printed interval entered yet
  const v = num(value);
  let label = 'within the lab’s reference interval';
  if (lo != null && v < num(lo)) label = 'below the lab’s reference interval';
  else if (hi != null && v > num(hi)) label = 'above the lab’s reference interval';
  return { label: label, src: 'lab-report', org: 'reporting laboratory', cite: 'printed reference interval', version: '' };
}

// Measurement-class-aware persistence (ruled, restating D32 for lab cadence):
//   1 point  -> the band is displayed FACTUALLY, no trend claim
//   >= 2 consecutive measured panels in the SAME band -> a trend row
//   >= 3 points -> directional commentary
// A single out-of-band value is therefore never silently un-displayed.
const LAB_TREND_MIN = 2, LAB_DIRECTION_MIN = 3;
function labRecords(type) {
  const out = [];
  Object.keys(APP_STATE.timeline || {}).forEach((d) => {
    (APP_STATE.timeline[d] || []).forEach((r) => {
      if (r.type === type && r.source === 'lab' && r.value != null) out.push({ date: d, rec: r });
    });
  });
  out.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return out;
}
function labTrend(type) {
  const rows = labRecords(type);
  if (!rows.length) return null;
  const spec = LAB_BY_TYPE[type];
  const last = rows[rows.length - 1];
  const band = labBand(type, last.rec.value, last.rec.unit, last.rec);
  const out = {
    type: type, label: spec ? spec.label : type, n: rows.length,
    latest: { date: last.date, value: num(last.rec.value), unit: last.rec.unit || (spec ? spec.unit : ''), converted: true },
    band: band, overlay: (spec && spec.overlay) || null,
    disclosure: (spec && spec.disclosure) || null,
    labInterval: (last.rec.ref_low != null || last.rec.ref_high != null)
      ? { low: last.rec.ref_low, high: last.rec.ref_high } : null,
    showTrendRow: false, direction: null,
  };
  if (rows.length >= LAB_TREND_MIN) {
    const prev = rows[rows.length - 2];
    const pband = labBand(type, prev.rec.value, prev.rec.unit, prev.rec);
    out.showTrendRow = !!(band && pband && band.label === pband.label);   // persistent band across consecutive panels
  }
  if (rows.length >= LAB_DIRECTION_MIN) {
    const spec2 = spec || {};
    const val = (row) => {
      const c = convertUnit(type, row.rec.value, row.rec.unit || spec2.unit, spec2.unit);
      return c == null ? num(row.rec.value) : c;      // unconvertible -> as entered, never dropped
    };
    const a = val(rows[rows.length - 3]), c = val(rows[rows.length - 1]);
    out.direction = c > a ? 'up' : (c < a ? 'down' : 'flat');
  }
  return out;
}

// Panels are a DERIVED grouping (Fork A): exact when panelId is present,
// date-based otherwise. The panel is never a record of its own.
function labPanels() {
  const map = {};
  Object.keys(APP_STATE.timeline || {}).forEach((d) => {
    (APP_STATE.timeline[d] || []).forEach((r) => {
      if (r.source !== 'lab' || !isLabType(r.type)) return;
      const key = r.panelId ? ('p:' + r.panelId) : ('d:' + d);
      (map[key] = map[key] || { date: d, panelId: r.panelId || '', values: [] }).values.push(r);
    });
  });
  return Object.keys(map).map((k) => map[k]).sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
}

let _panelSeq = 0;
function newPanelId() { _panelSeq++; return 'lp' + Date.now().toString(36) + '_' + _panelSeq; }

// Write a dated panel as per-value records through the SAME addSignal adapter
// (D19/D20 contract, one path). Returns a report; zero valid values writes nothing.
function addLabPanel(date, entries) {
  const d = /^\d{4}-\d{2}-\d{2}$/.test(String(date)) ? String(date) : localDate();
  const list = Array.isArray(entries) ? entries : [];
  const panelId = newPanelId();
  const written = [], rejected = [];
  list.forEach((e) => {
    e = e || {};
    if (!isLabType(e.type)) { rejected.push({ type: String(e.type || ''), why: 'unknown analyte' }); return; }
    if (e.value == null || String(e.value).trim() === '') return;             // blank row = not measured, not an error
    const spec = LAB_BY_TYPE[e.type];
    const raw = {
      type: e.type, kind: 'biometric', value: e.value, source: 'lab',
      unit: (spec.units.indexOf(e.unit) >= 0 ? e.unit : spec.unit),
      time: /^\d{2}:\d{2}$/.test(String(e.time)) ? String(e.time) : '09:00',
      date: d, notes: e.notes == null ? '' : e.notes, panelId: panelId,
    };
    // The reporting lab prints an interval for every analyte, so it is storable on
    // every analyte. Where there is no guideline band it BECOMES the band; where
    // there is one it is displayed ALONGSIDE it (the two can legitimately differ).
    if (e.ref_low  != null && String(e.ref_low)  !== '') { raw.ref_low  = clampNonNeg(e.ref_low);  raw.ref_src = 'lab-report'; }
    if (e.ref_high != null && String(e.ref_high) !== '') { raw.ref_high = clampNonNeg(e.ref_high); raw.ref_src = 'lab-report'; }
    const r = addSignal(raw);
    if (r.ok) { written.push(r.record); } else { rejected.push({ type: e.type, why: r.error || 'rejected' }); }
  });
  if (written.length) Store.saveState(APP_STATE);
  refresh();
  return { ok: written.length > 0, date: d, panelId: panelId, written: written.length, records: written, rejected: rejected };
}

// ---- lab rendering ---------------------------------------------------------
// Mirror grammar (D23) + D32: the user's value, the cited band, and the factual
// relationship between them. No verdict per reading; the "discuss with your
// doctor" line is STANDING CONTEXT for the section, never attached to a flag.
function labUnitOptions(spec, sel) {
  return spec.units.map((u) => `<option value="${esc(u)}"${u === sel ? ' selected' : ''}>${esc(u)}</option>`).join('');
}
function renderLabForm() {
  const el = document.getElementById('labRows');
  if (!el) return;
  const d = document.getElementById('labDate');
  if (d && !d.value) d.value = localDate();
  el.innerHTML = LAB_SPEC.map((s) => {
    const refs = `<div style="flex:0 0 74px"><label>Ref low</label><input id="lab_lo_${esc(s.type)}" type="number" inputmode="decimal" placeholder="—"></div>
         <div style="flex:0 0 74px"><label>Ref high</label><input id="lab_hi_${esc(s.type)}" type="number" inputmode="decimal" placeholder="—"></div>`;
    return `<div class="row" style="align-items:flex-end">
      <div style="flex:1.3"><label>${esc(s.label)}</label><input id="lab_v_${esc(s.type)}" type="number" inputmode="decimal" placeholder="—"></div>
      <div style="flex:0 0 96px"><label>Unit</label><select id="lab_u_${esc(s.type)}">${labUnitOptions(s, s.unit)}</select></div>
      ${refs}
    </div>`;
  }).join('');
}
function readLabForm() {
  const g = (id) => { const el = document.getElementById(id); return el ? el.value : ''; };
  return LAB_SPEC.map((s) => ({
    type: s.type, value: g('lab_v_' + s.type), unit: g('lab_u_' + s.type),
    ref_low: g('lab_lo_' + s.type), ref_high: g('lab_hi_' + s.type),
  }));
}
function addLabPanelFromForm() {
  const dEl = document.getElementById('labDate');
  const r = addLabPanel(dEl ? dEl.value : '', readLabForm());
  const rep = document.getElementById('labReport');
  if (rep) {
    rep.innerHTML = r.ok
      ? `<div class="note" style="color:var(--good)">Saved ${r.written} value${r.written === 1 ? '' : 's'} for ${esc(r.date)}.</div>`
      : `<div class="note" style="color:var(--warn)">Nothing saved — enter at least one value.</div>`;
  }
  if (r.ok) { renderLabForm(); toast('Lab panel saved'); }
  return r;
}
function labBandCite(b) {
  if (!b) return '';
  return b.src === 'guideline'
    ? `<small class="labcite">${esc(b.org)} · ${esc(b.cite)}${b.version ? ' (' + esc(b.version) + ')' : ''}</small>`
    : `<small class="labcite">${esc(b.org)} · ${esc(b.cite)}</small>`;
}
function renderLabTrends() {
  const el = document.getElementById('labTrends');
  if (!el) return;
  const rows = LAB_SPEC.map((s) => labTrend(s.type)).filter(Boolean);
  if (!rows.length) { el.innerHTML = ''; return; }
  const body = rows.map((t) => {
    const val = `${esc(rDisp(t.latest.value))} ${esc(t.latest.unit)}`;
    // 1 point: the band is stated factually, with NO trend claim.
    const band = t.band ? `<div class="labband">${esc(t.band.label)} ${labBandCite(t.band)}</div>`
                        : `<div class="labband labnorange">no reference interval entered — value shown as recorded</div>`;
    // A risk-stratified guideline figure is shown as a LABELLED OVERLAY with its
    // applicability stated — never as this user's band, because that would assume
    // a risk category the app has no way to know and must never infer.
    const ov = t.overlay
      ? `<div class="labtrend labov">${esc(t.overlay.org)} ${t.overlay.direction === 'max' ? '&le;' : '&ge;'} ${esc(rDisp(t.overlay.value))} ${esc(t.overlay.unit)}
         <small class="labcite">${esc(t.overlay.applicability)} — this app does not know your risk category and does not assume one · ${esc(t.overlay.cite)} (${esc(t.overlay.version)})</small></div>` : '';
    const disc = t.disclosure ? `<div class="labtrend labov">${esc(t.disclosure)}</div>` : '';
    const li = t.labInterval
      ? `<div class="labtrend">your lab’s printed interval: ${esc(t.labInterval.low == null ? '—' : rDisp(t.labInterval.low))}–${esc(t.labInterval.high == null ? '—' : rDisp(t.labInterval.high))} ${esc(t.latest.unit)}</div>`
      : '';
    const trend = t.showTrendRow
      ? `<div class="labtrend">${esc(t.n)} consecutive panels ${esc(t.band ? t.band.label : '')}</div>` : '';
    const dir = t.direction
      ? `<div class="labtrend">${t.direction === 'flat' ? 'unchanged' : t.direction} across the last ${esc(Math.min(t.n, 3))} panels</div>` : '';
    return `<div class="labrow"><div class="labhead"><b>${esc(t.label)}</b><span class="labval">${val}</span></div>
      <div class="labmeta">${esc(t.latest.date)} · ${esc(t.n)} panel${t.n === 1 ? '' : 's'}</div>${band}${li}${disc}${ov}${trend}${dir}</div>`;
  }).join('');
  el.innerHTML = `<h2 style="margin-top:14px">Labs</h2>${body}
    <div class="note">Your values against the cited range. Figures only — no interpretation.
    Reference ranges differ by laboratory and by person; <b>these are worth discussing with your doctor</b>.</div>`;
}

// ---- D30: single entry point ----------------------------------------------
// Presentation only. The main surface carries today's state + one-tap responses
// (regimen checklist, nudge offer, fast-candidate resolution — the ATTESTATION
// half); authoring and configuration live in a flat settings list. One persistent
// `+` opens the entry sheet. Nothing here writes a record: opening, closing and
// mode-switching are pure view state (gated).
const SHEET_MODES = ['scan', 'quick', 'photo', 'manual', 'signal', 'med', 'lab'];
let SHEET_MODE = 'scan';

function setSheetMode(mode) {
  if (SHEET_MODES.indexOf(mode) < 0) return { ok: false };
  if (SHEET_MODE === 'scan' && mode !== 'scan') cancelScan();   // full teardown on leaving Scan (scanner spec)
  SHEET_MODE = mode;
  SHEET_MODES.forEach((m) => {
    const pane = document.getElementById('pane-' + m);
    if (pane) pane.classList.toggle('on', m === mode);
    const btn = document.getElementById('mode-' + m);
    if (btn) btn.classList.toggle('on', m === mode);
  });
  if (mode === 'quick') renderQuickChips();
  return { ok: true, mode: mode };
}
// Scan is the default mode: the only path that returns micronutrients in one tap.
function openSheet(mode) {
  const sheet = document.getElementById('entrySheet'), scrim = document.getElementById('sheetScrim');
  if (sheet) sheet.style.display = 'flex';
  if (scrim) scrim.style.display = 'block';
  setSheetMode(SHEET_MODES.indexOf(mode) >= 0 ? mode : 'scan');
  return { ok: true, mode: SHEET_MODE };
}
function closeSheet() {
  cancelScan();                                                  // never leave the camera running
  const sheet = document.getElementById('entrySheet'), scrim = document.getElementById('sheetScrim');
  if (sheet) sheet.style.display = 'none';
  if (scrim) scrim.style.display = 'none';
  return { ok: true };
}
function openSettings() {
  const p = document.getElementById('settingsPanel'), s = document.getElementById('settingsScrim');
  if (p) p.style.display = 'flex';
  if (s) s.style.display = 'block';
  return { ok: true };
}
function closeSettings() {
  const p = document.getElementById('settingsPanel'), s = document.getElementById('settingsScrim');
  if (p) p.style.display = 'none';
  if (s) s.style.display = 'none';
  return { ok: true };
}
// Quick mode: one chip per saved preset, logged through the SAME logPreset path
// (byte-identical record — one contract, one path, as with the signal chips).
// Presets ship empty, so the honest empty state points at where they come from.
function renderQuickChips() {
  const el = document.getElementById('quickChips');
  if (!el) return;
  const presets = (APP_STATE.settings && APP_STATE.settings.presets) || [];
  if (!presets.length) {
    el.innerHTML = '<div class="note" style="margin-top:0">No quick items yet. Add one with <b>Manual</b> → “Save as preset”, or manage them under Settings › Presets.</div>';
    return;
  }
  el.innerHTML = presets.map((p) => {
    const sub = [rDisp(num(p.kcal)) + ' kcal', p.portion ? String(p.portion) : ''].filter(Boolean).join(' · ');
    return `<button type="button" class="qchip" onclick="quickLog('${esc(String(p.id))}')">${esc(p.name)}<small>${esc(sub)}</small></button>`;
  }).join('');
}
function quickLog(id) {
  const r = logPreset(id);
  if (r && r.ok) toast('Logged ' + r.item.name);
  return r;
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
  renderFastingForm();
  renderLabForm();
  onGoalTypeChange();
  renderRegimenTemplate();
  wireChipStripWheel();
  refresh();
}

// Console seam for review/testing.
window.HT = {
  Store, boot, migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateToLatest, normalizeState, refresh,
  // D29 — timezone-offset capture (capture-only; nothing reads it yet)
  nowTZO, normalizeTzo, TZO_MAX, normalizeItem, addWater, setFulfillment,
  historyCounts, renderHistorySummary, renderHistory, SIGNAL_SPEC, SIGNAL_BY_TYPE, seriesSummary,
  // D34 — lab panels (per-value records + panelId; LAB_SPEC merged at load)
  LAB_SPEC, LAB_BY_TYPE, LAB_CONVERT, LAB_GUIDELINE, SIGNAL_ADAPTERS, isLabType, labBand, labTrend, labRecords, labPanels,
  addLabPanel, addLabPanelFromForm, renderLabForm, readLabForm, renderLabTrends, LAB_TREND_MIN, LAB_DIRECTION_MIN,
  // D30 — single entry point (presentation only)
  openSheet, closeSheet, setSheetMode, openSettings, closeSettings, renderQuickChips, quickLog, SHEET_MODES,
  // Phase 4 Slice — Regimen / timeline templates (D27)
  parseRegimen, addRegimenFromJSON, normalizeRegimens, setActiveRegimen, deleteRegimen, activeRegimen, regimenToday,
  logRegimenEntry, substituteRegimenEntry, unfulfillRegimenEntry, isGrosslyLate, buildPresetItem, REGIMEN_TEMPLATE, REGIMEN_SAMPLE,
  renderRegimenChecklist, renderRegimenAuthor,
  // Phase 4 Slice X — fasting candidates + undo (D22)
  detectFastCandidates, confirmedFasts, resolveFast, matchResolution, fastEvents, fastEndedByItem,
  normalizeFastLog, normalizeFasting, offerUndo, doUndo, undoRemove,
  renderFastCandidates, renderFastingForm, setFastingFromForm, resolveFastAt, addManualItem, addMedicationFromForm, doIngest,
  // Phase 4 Slice — Mirror / Layer 2 self-trends (D23)
  signalSeries, seriesSummary, macroSeries, fastingStats, convertUnit, windowCutoff, sparklineSVG, renderTrends, setTrendWindow, UNIT_CONVERT,
  // Phase 4 Slice — Nudge / Layer 3 (D25)
  NUDGE_CURRICULUM, loggedDays, nudgeReady, currentNudge, focusAdherence, acceptNudge, declineNudge, snoozeNudge, retireNudge, setNudgesEnabled, normalizeNudges, renderNudge, toggleNudgeBrowse,
  // Phase 4 Slice T — timeline substrate (D20)
  SIGNAL_SPEC, SIGNAL_KINDS, MED_DOSE_UNITS, MED_FORMS, MED_ROUTES,
  normalizeSignal, normalizeTimeline, signalWarnings, addSignal, logBP, timelineForDay,
  // Phase 4 Layer-1 adherence — quick-log chips (D21)
  chipOrder, CHIP_DEFAULT, pickSignal, renderSignalChips, renderSignalForm, addSignalFromForm,
  exportJSON, parseImport, restore,
  ingest, maybeInjectSupplement, buildSupplementItem, fillable,
  goalProgress, microRollup, dayTotals, setGoal, removeGoal, isNutrientGoal, renderGoalsHTML, onGoalTypeChange,   // D24 signal goals (mixed namespace)
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
