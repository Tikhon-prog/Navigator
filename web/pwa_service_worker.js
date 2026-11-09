'use strict';

const CACHE_PREFIX = 'pokolenie-pwa-';
const CACHE_VERSION = 'v1';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
  './flutter_bootstrap.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await Promise.all(APP_SHELL.map(async (path) => {
      try {
        const response = await fetch(path, { cache: 'reload' });
        if (response.ok) await cache.put(path, response);
      } catch (_) {
        // The first successful app launch will fill any missing shell entries.
      }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Never put authenticated API or account responses into the offline cache.
  if (/^\/(api|auth|oauth|\.well-known)(\/|$)/i.test(url.pathname)) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put('./index.html', response.clone());
        }
        return response;
      } catch (_) {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match(request)) ||
          (await cache.match('./index.html')) ||
          Response.error();
      }
    })());
    return;
  }

  const cachePromise = caches.open(CACHE_NAME);
  const networkPromise = fetch(request).then((response) => {
    if (response.ok && response.type === 'basic') {
      cachePromise.then((cache) => cache.put(request, response.clone())).catch(() => {});
    }
    return response;
  }).catch(() => null);

  // Return cached Flutter assets immediately while refreshing them in the
  // background. The worker stays alive for that refresh.
  event.waitUntil(networkPromise.then(() => undefined));
  event.respondWith(cachePromise.then(async (cache) => {
    const cached = await cache.match(request);
    if (cached) return cached;
    return (await networkPromise) || Response.error();
  }));
});
