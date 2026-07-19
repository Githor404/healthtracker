'use strict';
/* HealthTracker service worker — see DECISIONS.md D6.
   Caches the app SHELL only. Data lives in localStorage and is never cached here.
   Offline = shell from cache + the data layer reading localStorage. */

// Cache name is content-derived (DECISIONS.md D6 amendment): SHELL_HASH is the
// hash of the precached shell (index.html, app.js, manifest.json, icons),
// stamped in by `bash tests/check-sw-hash.sh --fix` and enforced by the gate.
// Any shell change flips the hash -> new sw.js bytes -> the browser installs a
// new SW -> force-and-notify activates it on load and the app shows the changelog
// notice. No serve-time build; sw.js's own edits are self-detecting.
const SHELL_HASH = 'a2c73e986147';
const SHELL_PREFIX = 'healthtracker-shell-';
const SHELL_CACHE = SHELL_PREFIX + SHELL_HASH;

// D15: the ZXing UMD (the app's one third-party runtime dep) is cache-first in a
// SEPARATE runtime cache. Matched by HOST (+ @zxing path), NOT the pinned version
// -> a ZXing version bump needs no SW edit. Amendment A shields this cache from
// shell cleanup. The <script> is crossorigin=anonymous (SRI), so the response is
// CORS (non-opaque): cacheable AND SRI-re-verifiable on every offline load.
const RUNTIME_CACHE = 'healthtracker-runtime';
const ZXING_HOST = 'cdn.jsdelivr.net';

// Relative paths so scope works at a GitHub Pages subpath AND at localhost root.
// Every entry is gate-checked by tests/check-precache.sh — a 404 here rejects
// the whole install and silently disables offline.
const PRECACHE = [
  './',
  './index.html',
  './app.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png',
];

// Dev (localhost) is network-first so active development never serves a stale
// shell; the deployed origin is cache-first (atomic generation). `?prod=1` on the
// SW URL forces the production path on localhost — used by the offline gate test.
const FORCE_PROD = new URL(self.location.href).searchParams.get('prod') === '1';
const HOST = self.location.hostname;
const IS_DEV = !FORCE_PROD && (HOST === 'localhost' || HOST === '127.0.0.1');

self.addEventListener('install', (event) => {
  // Force-and-notify (D6 amendment, supersedes no-skipWaiting): activate the new
  // version immediately instead of waiting for all clients to close, so the next
  // load is always current. The atomic shell keeps the swap skew-free; the page
  // shows a post-update changelog notice after the fact.
  self.skipWaiting();
  event.waitUntil(caches.open(SHELL_CACHE).then((c) => c.addAll(PRECACHE)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(Promise.all([
    // Take control of already-open clients so the update applies on this load
    // (paired with the page's controllerchange reload) — force-and-notify.
    self.clients.claim(),
    // Amendment A: delete only stale SHELL caches — never other app caches
    // (e.g. the Phase-2 healthtracker-runtime ZXing cache).
    caches.keys().then((keys) => Promise.all(
      keys.filter((k) => k.startsWith(SHELL_PREFIX) && k !== SHELL_CACHE)
          .map((k) => caches.delete(k))
    )),
  ]));
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;                     // never cache writes
  const url = new URL(req.url);

  // D15: ZXing UMD -> cache-first in the runtime cache (offline scanning for
  // BarcodeDetector-less browsers: iOS Safari, Firefox). Host-matched, version-
  // agnostic. Only cache successful CORS responses.
  if (url.hostname === ZXING_HOST && url.pathname.indexOf('@zxing/') >= 0) {
    event.respondWith(
      caches.open(RUNTIME_CACHE).then((cache) =>
        cache.match(req).then((hit) => hit || fetch(req).then((res) => {
          if (res && res.ok) cache.put(req, res.clone());
          return res;
        }))
      )
    );
    return;
  }

  if (url.origin !== self.location.origin) return;      // other cross-origin passthrough

  // Navigations resolve to the shell's index regardless of query string, so
  // '/', '/index.html' and '/?prod=1' all load offline.
  if (req.mode === 'navigate') {
    event.respondWith(
      IS_DEV
        ? fetch(req).catch(() => caches.match('./index.html'))
        : caches.match('./index.html').then((hit) => hit || fetch(req))
    );
    return;
  }

  // Same-origin assets (app.js, icons, manifest — no meaningful query string).
  event.respondWith(
    IS_DEV
      ? fetch(req).catch(() => caches.match(req))
      : caches.match(req).then((hit) => hit || fetch(req))
  );
});
