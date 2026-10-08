import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/core/services/speed_smoother.dart';
import 'package:web/web.dart' as web;

/// JS interop surface of window.jilakeGeo (web/js/geolocation_bridge.js).
@JS('jilakeGeo')
external _JilakeGeo? get _jilakeGeo;

@JS()
extension type _JilakeGeo._(JSObject _) implements JSObject {
  external bool start(String successCallbackName, String errorCallbackName,
      [String json]);
  external void stop();
  external bool speedSeen;
}

/// Global callbacks the bridge invokes; names must be unique on window.
const String _successCallbackName = '__jilakeGeoSuccess';
const String _errorCallbackName = '__jilakeGeoError';

@JS('__jilakeGeoSuccess')
external set _successCallback(JSFunction? f);

@JS('__jilakeGeoError')
external set _errorCallback(JSFunction? f);

/// [LocationService] for Flutter Web, driving the browser Geolocation API
/// through the jilakeGeo JS bridge.
class WebLocationService implements LocationService {
  final SpeedSmoother _smoother;

  final StreamController<PositionFix> _fixes =
      StreamController<PositionFix>.broadcast();
  final StreamController<LocationStatus> _statuses =
      StreamController<LocationStatus>.broadcast();

  PositionFix? _previous;
  LocationStatus _status = LocationStatus.idle;
  bool _running = false;

  WebLocationService({SpeedSmoother? smoother})
      : _smoother = smoother ?? SpeedSmoother();

  @override
  bool get isSupported => _jilakeGeo != null;

  @override
  LocationStatus get status => _status;

  @override
  Stream<PositionFix> watch() => _fixes.stream;

  @override
  Stream<LocationStatus> get statusStream => _statuses.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    if (!isSupported) {
      _setStatus(LocationStatus.unsupported);
      return;
    }
    _successCallback = ((JSString json) {
      _onPositionJson(json.toDart);
    }).toJS;
    _errorCallback = ((JSObject error) {
      _onGeolocationError(error as web.GeolocationPositionError);
    }).toJS;

    final started =
        _jilakeGeo!.start(_successCallbackName, _errorCallbackName, '{}');
    if (!started) {
      _setStatus(LocationStatus.unsupported);
      return;
    }
    _running = true;
    _setStatus(LocationStatus.active);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _jilakeGeo!.stop();
    _successCallback = null;
    _errorCallback = null;
    _previous = null;
    _smoother.reset();
    _setStatus(LocationStatus.idle);
  }

  /// Maps GeolocationPositionError codes to [LocationStatus]:
  /// 1 = permission denied, 2 = position unavailable, 3 = timeout.
  ///
  /// A denied watch is dead — the error will repeat on every retry until the
  /// user re-grants permission — so the watch is torn down and [start] can be
  /// called again for the retry flow.
  void _onGeolocationError(web.GeolocationPositionError error) {
    switch (error.code) {
      case web.GeolocationPositionError.PERMISSION_DENIED:
        _teardown();
        _setStatus(LocationStatus.permissionDenied);
      case web.GeolocationPositionError.POSITION_UNAVAILABLE:
        _setStatus(LocationStatus.positionUnavailable);
      case web.GeolocationPositionError.TIMEOUT:
        _setStatus(LocationStatus.timeout);
      default:
        _setStatus(LocationStatus.positionUnavailable);
    }
  }

  void _teardown() {
    if (!_running) return;
    _running = false;
    _jilakeGeo!.stop();
    _successCallback = null;
    _errorCallback = null;
    _previous = null;
    _smoother.reset();
  }

  void _setStatus(LocationStatus status) {
    _status = status;
    _statuses.add(status);
  }

  void _onPositionJson(String json) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return; // malformed payload: drop rather than crash the stream
    }
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final accuracy = (data['accuracy'] as num?)?.toDouble();
    final timestamp = (data['timestamp'] as num?)?.toInt();
    if (lat == null || lng == null || accuracy == null || timestamp == null) {
      return; // incomplete payload: drop rather than crash the stream
    }
    final nativeSpeed = (data['speed'] as num?)?.toDouble();
    final fix = PositionFix(
      lat: lat,
      lng: lng,
      accuracyM: accuracy,
      headingDeg: (data['heading'] as num?)?.toDouble() ?? 0.0,
      timestampMs: timestamp,
      speedMs: 0.0,
      hasNativeSpeed: nativeSpeed != null,
    );

    // Native (Doppler-derived) speed is authoritative: use as-is.
    // Only the delta fallback needs smoothing.
    if (nativeSpeed != null) {
      fix.speedMs = nativeSpeed;
    } else {
      fix.speedMs = _fallbackSpeed(fix);
    }

    _previous = fix;
    _fixes.add(fix);
  }

  /// Delta-distance (haversine) over the previous fix divided by elapsed
  /// time, smoothed. First fix (no previous) yields 0 m/s.
  double _fallbackSpeed(PositionFix fix) {
    final previous = _previous;
    if (previous == null) return 0.0;
    final elapsedMs = fix.timestampMs - previous.timestampMs;
    if (elapsedMs <= 0) return 0.0;
    final distance = _haversineM(previous, fix);
    final deltaSpeed = distance / (elapsedMs / 1000.0);
    return _smoother.smooth(deltaSpeed, fix.timestampMs);
  }

  static double _haversineM(PositionFix a, PositionFix b) {
    const earthRadiusM = 6371000.0;
    final dLat = _degToRad(b.lat - a.lat);
    final dLng = _degToRad(b.lng - a.lng);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_degToRad(a.lat)) * math.cos(_degToRad(b.lat)) * sinLng * sinLng;
    return 2 * earthRadiusM * math.asin(math.sqrt(h));
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;
}
