// Jilake Speedo service worker: ensures the PWA launches and works offline
// (GPS, sessions, and recording need no network; only map tiles do).
//
// Flutter's generated service worker unregisters itself (no offline cache),
// so this replaces it. Strategy:
//   - On install, precache the app shell AND Flutter's assets (fonts/icons,
//     manifests, shaders) by reading the AssetManifest, so offline the UI
//     (including icons) renders correctly.
//   - On fetch, cache-first with background refresh for same-origin GETs;
//     everything successful gets cached so nothing is missed offline.
//   - Cross-origin (map tiles) is never cached — it needs the network.

const CACHE = 'jilake-speedo-v3';

// Shell + bundled assets precached at install. This explicit list covers the
// app shell and Flutter's runtime assets (icon fonts, manifests, shaders) so
// offline the UI renders correctly — including the Material/Cupertino icons.
const CORE = [
  './',
  './index.html',
  './main.dart.js',
  './flutter_bootstrap.js',
  './flutter.js',
  './manifest.json',
  './version.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
  // Flutter runtime assets (fonts/icons/manifests/shaders).
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/FontManifest.json',
  './assets/NOTICES',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  './assets/packages/flutter_map/lib/assets/flutter_map_logo.png',
  './assets/packages/wakelock_plus/assets/no_sleep.js',
  './assets/shaders/ink_sparkle.frag',
  './assets/shaders/stretch_effect.frag',
  // CanvasKit engine (local) — required to render offline.
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // Best-effort: a missing optional file must not fail the install.
      await Promise.all(
        CORE.map((url) => cache.add(url).catch(() => undefined))
      );
    })()
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
  // Never cache cross-origin requests (map tiles): they need the network,
  // and offline the map simply shows its dark surface.
  if (url.origin !== self.location.origin) return;

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
