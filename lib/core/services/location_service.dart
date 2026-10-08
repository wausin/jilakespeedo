/// A single GPS position fix, normalized across platforms.
class PositionFix {
  double lat;
  double lng;
  double speedMs;
  double accuracyM;
  double headingDeg;
  int timestampMs;

  /// Whether the platform reported a native speed for this fix
  /// (`coords.speed !== null`). When false, `speedMs` was derived from
  /// consecutive positions (delta distance / delta time, smoothed).
  bool hasNativeSpeed;

  PositionFix({
    required this.lat,
    required this.lng,
    required this.speedMs,
    required this.accuracyM,
    required this.headingDeg,
    required this.timestampMs,
    required this.hasNativeSpeed,
  });
}

/// Status of the location service, surfaced to the UI shell.
enum LocationStatus {
  /// Not started / idle.
  idle,

  /// Watching position.
  active,

  /// Permission denied (GeolocationPositionError code 1).
  permissionDenied,

  /// Position unavailable (code 2).
  positionUnavailable,

  /// Timed out waiting for a fix (code 3).
  timeout,

  /// Geolocation unsupported by the browser.
  unsupported,
}

/// Platform seam for GPS position streams.
abstract class LocationService {
  /// Whether the platform supports geolocation at all.
  bool get isSupported;

  /// Starts producing fixes on [watch].
  Future<void> start();

  /// Stops producing fixes (clears the platform watch).
  Future<void> stop();

  /// Broadcast stream of position fixes; listenable before [start].
  ///
  /// The stream itself never errors; problems are reported via
  /// [statusStream].
  Stream<PositionFix> watch();

  /// Current service status (idle/active/permission-denied/...).
  LocationStatus get status;

  /// Broadcast stream of status changes; emits after every transition.
  ///
  /// The shell listens here to surface a friendly permission-denied
  /// screen with a retry option.
  Stream<LocationStatus> get statusStream;
}
