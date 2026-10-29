// R283 -- THE "READY" CONDITION EVERY GATE WAITS ON, instead of a fixed sleep.
//
// Installed by each gate with Page.addScriptToEvaluateOnNewDocument, so it runs in
// every document BEFORE the app's own script. It counts the page's async work in
// flight -- the app's short timers (<= 1 s: debounces, the resolve arm), fetches and
// their bodies, IndexedDB requests, createImageBitmap -- and `__htQuiet()` resolves
// when nothing is in flight, no finite CSS transition or animation is running (a
// toast fading in is not yet "shown"), AND the DOM has not changed for two animation
// frames. Longer timers (a toast's lifetime, a fetch's abort guard, the 60 s URL
// revoke) are not work the screen is waiting for and are not counted; nor is an
// infinite animation (a spinner).
//
// It changes nothing the app does: every wrapper calls the original with the same
// arguments and returns what it returned. Test-only; never shipped (tests/ is not
// in the service worker's shell).
(function () {
  if (window.__htQuiet) return;
  var kinds = { timer: 0, fetch: 0, body: 0, idb: 0, bitmap: 0, file: 0 };
  var lastChange = 0, frame = 0;
  var SHORT_MS = 1000;
  var total = function () { var n = 0; for (var k in kinds) n += kinds[k]; return n; };
  var inc = function (k) { kinds[k]++; };
  var dec = function (k) { if (kinds[k] > 0) kinds[k]--; };
  // ONLY THE PAGE'S OWN WORK. A script injected into every page by this machine's
  // antivirus (gc.kis.v2.scr.kaspersky-labs.com, measured: it keeps a short timer
  // going for seconds) is not work the app's screen waits for; nor is a gate's own
  // in-page polling. Counted only when a frame of the app's own origin set it.
  var ORIGIN = location.origin;
  var ours = function () {
    var s = ''; try { s = new Error().stack || ''; } catch (e) {}
    return (ORIGIN && ORIGIN !== 'null' && s.indexOf(ORIGIN + '/') >= 0) ? s : null;
  };
  var track = function (p, k) {
    if (!p || typeof p.then !== 'function' || !ours()) return p;
    inc(k);
    var done = false, end = function () { if (!done) { done = true; dec(k); } };
    p.then(end, end);
    return p;
  };
  // timers
  var _st = window.setTimeout, _ct = window.clearTimeout, live = {};
  window.setTimeout = function (fn, ms) {
    var args = Array.prototype.slice.call(arguments, 2);
    var short = !(Number(ms) > SHORT_MS);
    var id = _st.call(window, function () {
      if (live[id]) { delete live[id]; dec('timer'); }
      if (typeof fn === 'function') return fn.apply(this, args);
      return (0, eval)(String(fn));
    }, ms);
    var st = short ? ours() : null;
    if (st) {
      // where it was set: the first frame of the app's own origin
      live[id] = (st.split('\n').filter(function (l) { return l.indexOf(ORIGIN + '/') >= 0; })[0] || 'unknown').trim();
      inc('timer');
    }
    return id;
  };
  window.clearTimeout = function (id) {
    if (live[id]) { delete live[id]; dec('timer'); }
    return _ct.call(window, id);
  };
  // fetch and bodies
  if (window.fetch) {
    var _f = window.fetch;
    window.fetch = function () { return track(_f.apply(this, arguments), 'fetch'); };
  }
  if (window.Response) ['arrayBuffer', 'json', 'text', 'blob'].forEach(function (k) {
    var o = Response.prototype[k];
    if (o) Response.prototype[k] = function () { return track(o.apply(this, arguments), 'body'); };
  });
  // R284: reading a picked file is work in progress too (a backup chosen through the
  // file input is read asynchronously before anything is drawn from it).
  if (window.Blob) ['text', 'arrayBuffer'].forEach(function (k) {
    var o = Blob.prototype[k];
    if (o) Blob.prototype[k] = function () { return track(o.apply(this, arguments), 'file'); };
  });
  if (window.FileReader) ['readAsText', 'readAsArrayBuffer', 'readAsDataURL', 'readAsBinaryString'].forEach(function (k) {
    var o = FileReader.prototype[k];
    if (!o) return;
    FileReader.prototype[k] = function () {
      var fr = this;
      if (ours()) {
        inc('file');
        var done = false, end = function () { if (!done) { done = true; dec('file'); } };
        fr.addEventListener('loadend', end);
      }
      return o.apply(fr, arguments);
    };
  });
  if (window.createImageBitmap) {
    var _cib = window.createImageBitmap;
    window.createImageBitmap = function () { return track(_cib.apply(this, arguments), 'bitmap'); };
  }
  // IndexedDB READS: a request is in flight until it succeeds or fails. Writes (put, add,
  // delete, clear) are not counted: the app's cache fill writes thousands of rows in the
  // background (measured: 3,583 in forms-gate) and no screen waits for them.
  // A read is also over when its TRANSACTION completes or aborts -- no read outlives its
  // transaction -- so the count cannot leak on a path where a request's own event is missed.
  var idbLive = {}, idbSeq = 0;
  var req = function (r, label) {
    if (!r || !r.addEventListener) return r;
    var key = ++idbSeq;
    idbLive[key] = label;
    inc('idb');
    var done = false, end = function () { if (!done) { done = true; delete idbLive[key]; dec('idb'); } };
    r.addEventListener('success', end); r.addEventListener('error', end); r.addEventListener('blocked', end);
    try { var tx = r.transaction; if (tx && tx.addEventListener) { tx.addEventListener('complete', end); tx.addEventListener('abort', end); tx.addEventListener('error', end); } } catch (e) {}
    return r;
  };
  var wrapReq = function (proto, names) {
    if (!proto) return;
    names.forEach(function (k) {
      var o = proto[k];
      if (typeof o === 'function') proto[k] = function () {
        var r = o.apply(this, arguments);
        var where = ''; try { where = (this.name || (this.objectStore && this.objectStore.name) || '') + '.' + k; } catch (e) { where = k; }
        return req(r, where);
      };
    });
  };
  if (window.IDBFactory) wrapReq(IDBFactory.prototype, ['open', 'deleteDatabase']);
  if (window.IDBObjectStore) wrapReq(IDBObjectStore.prototype, ['get', 'getAll', 'getAllKeys', 'getKey', 'count', 'openCursor', 'openKeyCursor']);
  if (window.IDBIndex) wrapReq(IDBIndex.prototype, ['get', 'getAll', 'getAllKeys', 'getKey', 'count', 'openCursor', 'openKeyCursor']);
  // the DOM: when did it last change
  var watch = function () {
    try {
      new MutationObserver(function () { lastChange = frame; })
        .observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
    } catch (e) {}
  };
  if (document.documentElement) watch(); else document.addEventListener('readystatechange', watch, { once: true });
  var raf = window.requestAnimationFrame ? window.requestAnimationFrame.bind(window) : function (f) { return _st.call(window, f, 16); };
  var tick = function () { frame++; raf(tick); };
  raf(tick);
  // finite CSS transitions / animations still running (a fade-in): the screen is not settled
  var moving = function () {
    if (!document.getAnimations) return 0;
    return document.getAnimations().filter(function (a) {
      if (a.playState !== 'running') return false;
      try { var t = a.effect && a.effect.getComputedTiming(); return !t || isFinite(t.endTime); } catch (e) { return true; }
    }).length;
  };
  var why = function () {
    var b = []; for (var k in kinds) if (kinds[k]) b.push(kinds[k] + ' ' + k);
    var src = []; for (var t in live) src.push(live[t]); if (src.length) b.push('timer set at ' + src.slice(0, 2).join(' | '));
    var ir = []; for (var q in idbLive) ir.push(idbLive[q]); if (ir.length) b.push('idb: ' + ir.slice(0, 4).join(', '));
    var m = moving(); if (m) b.push(m + ' animation(s) running');
    b.push('last DOM change ' + (frame - lastChange) + ' frame(s) ago');
    return b.join(', ');
  };
  // the condition. Resolves 'quiet', or rejects after `limit` ms naming what was still
  // going on -- a failure, never a pass by timeout.
  window.__htQuiet = function (limit) {
    var t0 = performance.now(), deadline = t0 + (Number(limit) > 0 ? Number(limit) : 10000);
    return new Promise(function (resolve, reject) {
      var first = null;
      var check = function () {
        if (first === null) first = why();
        window.__htQuietWaitedOn = first;
        if (total() === 0 && document.readyState === 'complete' && frame - lastChange >= 2 && moving() === 0) {
          window.__htQuietLastMs = Math.round(performance.now() - t0);
          return resolve('quiet');
        }
        if (performance.now() > deadline) return reject(new Error('the page did not settle: ' + why()));
        _st.call(window, check, 16);
      };
      // at least two frames after the call, so a change made just now is drawn
      var f0 = frame;
      var start = function () { if (frame - f0 >= 2) check(); else _st.call(window, start, 8); };
      start();
    });
  };
  window.__htPending = function () { return why(); };
})();
