import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Forces the app to fetch the freshly deployed build.
///
/// A plain `location.reload()` can be answered from the HTTP cache or a
/// service worker, so the user keeps seeing the old build after tapping
/// Update. This actively unregisters service workers and clears the Cache
/// Storage, then navigates to the current URL with a cache-busting query
/// parameter so the HTML/JS are re-fetched from the network.
void reloadApp() {
  _reload().ignore();
}

Future<void> _reload() async {
  // Unregister any service workers so none can serve the old app shell.
  try {
    final container = web.window.navigator.serviceWorker;
    final regs = await container.getRegistrations().toDart;
    for (final reg in regs.toDart) {
      await reg.unregister().toDart;
    }
  } catch (_) {
    // No service worker support — continue.
  }

  // Drop Cache Storage entries (belt and braces).
  try {
    final keys = await web.window.caches.keys().toDart;
    for (final key in keys.toDart) {
      await web.window.caches.delete(key.toDart).toDart;
    }
  } catch (_) {
    // Cache API unavailable — continue.
  }

  // Navigate with a cache-busting query so the document itself is re-fetched.
  final url = web.window.location.href;
  final sep = url.contains('?') ? '&' : '?';
  final busted = '$url${sep}v=${DateTime.now().millisecondsSinceEpoch}';
  web.window.location.replace(busted);
}
