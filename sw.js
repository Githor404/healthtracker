'use strict';
/* HealthTracker service worker — see DECISIONS.md D6.
   Caches the app SHELL only. Data lives in localStorage and is never cached here.
   Offline = shell from cache + the data layer reading localStorage. */

const VERSION = 1;                            // bump on any shell change
const SHELL_PREFIX = 'healthtracker-shell-';
const SHELL_CACHE = SHELL_PREFIX + 'v' + VERSION;

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
  // No skipWaiting: a new SW waits and activates on next launch (D6).
  event.waitUntil(caches.open(SHELL_CACHE).then((c) => c.addAll(PRECACHE)));
});

self.addEventListener('activate', (event) => {
  // Amendment A: delete only stale SHELL caches — never other app caches
  // (e.g. the Phase-2 healthtracker-runtime ZXing cache).
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((k) => k.startsWith(SHELL_PREFIX) && k !== SHELL_CACHE)
          .map((k) => caches.delete(k))
    ))
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;                     // never cache writes
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;      // cross-origin passthrough
                                                        //   (Phase-2 ZXing runtime cache hooks here)

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
