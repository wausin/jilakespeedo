// Jilake Speedo service worker: app-shell caching so the PWA launches and
// works offline (GPS, sessions, and recording need no network; only map
// tiles do).
//
// Flutter's generated service worker is deprecated and the default build
// ships a self-unregistering (no-cache) one, which is why the app failed to
// open in airplane mode. This replaces it: cache-first for the app shell,
// network-first (with cache fallback) for everything else.

const CACHE = 'jilake-speedo-v1';

// Core shell files fetched at install. Flutter's hashed asset manifest is
// read at runtime from AssetManifest, but these cover a cold offline start.
const CORE = [
  './',
  './index.html',
  './main.dart.js',
  './flutter_bootstrap.js',
  './manifest.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // Best-effort: a missing optional file must not fail the install.
      Promise.all(
        CORE.map((url) =>
          cache.add(url).catch(() => undefined)
        )
      )
    )
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Never cache map tiles or cross-origin requests: they need the network,
  // and offline the map simply shows its dark surface.
  if (url.origin !== self.location.origin) return;

  // Cache-first for the app shell so offline launch is fast and reliable.
  event.respondWith(
    (async () => {
      const cached = await caches.match(request);
      if (cached) {
        // Refresh in the background (stale-while-revalidate).
        event.waitUntil(
          fetch(request)
            .then((resp) => {
              if (resp && resp.ok) {
                caches.open(CACHE).then((c) => c.put(request, resp.clone()));
              }
            })
            .catch(() => undefined)
        );
        return cached;
      }
      try {
        const resp = await fetch(request);
        if (resp && resp.ok) {
          const copy = resp.clone();
          caches.open(CACHE).then((c) => c.put(request, copy));
        }
        return resp;
      } catch (e) {
        // Offline and not cached: fall back to the shell for navigations.
        if (request.mode === 'navigate') {
          const shell = await caches.match('./index.html');
          if (shell) return shell;
        }
        throw e;
      }
    })()
  );
});
