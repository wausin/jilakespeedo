import 'dart:async';

/// Connectivity of the device as it affects the timeline map's tile loading.
///
/// GPS itself needs no network, so recording continues offline; only the map
/// tiles (and any future network features) care. The web implementation
/// listens to the browser's `online`/`offline` window events.
abstract class ConnectivityService {
  /// Emits `true` when connectivity is lost, `false` when it returns. The
  /// first event reflects the current state (web: `navigator.onLine`).
  Stream<bool> get offlineStream;

  /// Whether the device is currently offline.
  bool get isOffline;
}
