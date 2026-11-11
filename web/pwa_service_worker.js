'use strict';

const CACHE_PREFIX = 'pokolenie-pwa-shell-';
const CACHE_NAME = `${CACHE_PREFIX}v1`;

function isApiPath(pathname) {
  return /^\\/api(?:\\/|$)/.test(pathname);
}

function isStaticRequest(request, url) {
  const staticDestination = ['script', 'style', 'image', 'font', 'worker']
    .includes(request.destination);
  const bundledAsset = url.pathname.includes('/assets/');
  const staticExtension = /\\.(?:js|css|png|jpe?g|webp|svg|ico|woff2?|ttf|wasm|json)$/i
    .test(url.pathname);
  return staticDestination || bundledAsset || staticExtension;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    const scope = self.registration.scope;
    const appShell = [
      new URL('./', scope).href,
      new URL('index.html', scope).href,
      new URL('manifest.json', scope).href,
      new URL('icons/Icon-192.png', scope).href,
      new URL('icons/Icon-512.png', scope).href,
    ];

    // A missing optional icon or hosting rewrite must not prevent installation.
    await Promise.all(appShell.map(async (url) => {
      try {
        const response = await fetch(url, { cache: 'reload' });
        if (response.ok && response.type === 'basic') {
          await cache.put(url, response);
        }
      } catch (_) {
        // The app can still install; requested assets will be cached as used.
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
  if (request.method !== 'GET' || request.headers.has('Authorization')) return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin || isApiPath(url.pathname)) return;

  const isNavigation = request.mode === 'navigate';
  if (!isNavigation && !isStaticRequest(request, url)) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    try {
      const response = await fetch(request);
      if (response.ok && response.type === 'basic') {
        await cache.put(request, response.clone());
      }
      return response;
    } catch (_) {
      const cached = await cache.match(request);
      if (cached) return cached;

      if (isNavigation) {
        const fallback = new URL('index.html', self.registration.scope).href;
        const appShell = new URL('./', self.registration.scope).href;
        return (await cache.match(fallback)) ||
          (await cache.match(appShell)) ||
          Response.error();
      }
      return Response.error();
    }
  })());
});
