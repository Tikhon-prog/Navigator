"use strict";
const CACHE_NAME = "pokolenie-website-v0.2.1";
const SHELL = [
  "./", "./index.html", "./manifest.webmanifest",
  "./assets/app.css", "./assets/app.js",
  "./assets/app-icon.svg", "./assets/apple-touch-icon.png"
];
self.addEventListener("install", function (event) {
  event.waitUntil(caches.open(CACHE_NAME).then(function (cache) {
    return cache.addAll(SHELL);
  }).then(function () { return self.skipWaiting(); }));
});
self.addEventListener("activate", function (event) {
  event.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.map(function (key) {
      if (key.indexOf("pokolenie-website-") === 0 && key !== CACHE_NAME) return caches.delete(key);
      return false;
    }));
  }).then(function () { return self.clients.claim(); }));
});
self.addEventListener("fetch", function (event) {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  const scope = new URL(self.registration.scope);
  if (url.origin !== scope.origin ||
      url.pathname.split("/").indexOf("api") !== -1 ||
      req.headers.has("Authorization")) return;
  if (req.mode === "navigate") {
    event.respondWith(fetch(req).then(function (response) {
      if (response && response.ok && response.type === "basic") {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(function (cache) { cache.put("./index.html", copy); });
      }
      return response;
    }).catch(function () { return caches.match("./index.html"); }));
    return;
  }
  event.respondWith(caches.match(req).then(function (cached) {
    if (cached) return cached;
    return fetch(req).then(function (response) {
      if (response && response.ok && response.type === "basic") {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(function (cache) { cache.put(req, copy); });
      }
      return response;
    });
  }));
});