import 'dart:math' as math;

import 'package:jilake_speedo/core/models/session.dart';
import 'package:jilake_speedo/core/services/location_service.dart';

/// Live progress of the session the engine is working on.
///
/// This is the state the UI renders while riding; once [finished] is true
/// the state is frozen and [summary] holds the final numbers.
class SessionState {
  String vehicleId;
  SessionTarget target;
  int startedAtMs;
  double cumulativeDistanceM;
  double topSpeedMs;
  List<double> speedSamples;
  bool finished;
  SessionSummary? summary;

  SessionState({
    required this.vehicleId,
    required this.target,
    required this.startedAtMs,
    required this.cumulativeDistanceM,
    required this.topSpeedMs,
    required this.speedSamples,
    required this.finished,
    this.summary,
  });
}

/// Turns a stream of GPS fixes into session progress and a final summary.
///
/// Pure logic, no platform or Flutter dependencies: the session screen feeds
/// it [PositionFix]es from the location service and renders the returned
/// [SessionState]. Fixes with accuracy worse than [accuracyThresholdM] are
/// skipped entirely (no distance advance, no speed sample), so GPS glitches
/// cannot corrupt distance or top speed.
class SessionEngine {
  /// Fixes with [PositionFix.accuracyM] above this are discarded.
  final double accuracyThresholdM;

  static const double _earthRadiusM = 6371000.0;

  SessionState? _state;
  PositionFix? _lastGoodFix;

  SessionEngine({required this.accuracyThresholdM});

  /// The current [SessionState], or null when no session was started.
  ///
  /// Same live instance that [onFix] returns: reading this never advances
  /// the session (a distance target without fixes stays at zero, a duration
  /// target without fixes stays unfinished — no wall-clock progress).
  SessionState? get state => _state;

  /// Begins a new session, discarding any previous state.
  void start({
    required String vehicleId,
    required SessionTarget target,
    required int startedAtMs,
  }) {
    _state = SessionState(
      vehicleId: vehicleId,
      target: target,
      startedAtMs: startedAtMs,
      cumulativeDistanceM: 0,
      topSpeedMs: 0,
      speedSamples: [],
      finished: false,
    );
    _lastGoodFix = null;
  }

  /// Folds [fix] into the running session.
  ///
  /// Returns the current [SessionState]: null if no session was started,
  /// the frozen state if the session already finished (late fixes change
  /// nothing), and the updated state otherwise. Low-accuracy fixes return
  /// the state unchanged.
  SessionState? onFix(PositionFix fix) {
    final state = _state;
    if (state == null) return null;
    if (state.finished) return state;
    if (fix.accuracyM > accuracyThresholdM) return state;

    final lastGood = _lastGoodFix;
    if (lastGood != null) {
      state.cumulativeDistanceM += _haversineM(lastGood, fix);
    }
    _lastGoodFix = fix;

    state.speedSamples.add(fix.speedMs);
    if (fix.speedMs > state.topSpeedMs) {
      state.topSpeedMs = fix.speedMs;
    }

    switch (state.target) {
      case DistanceTarget(:final meters):
        if (state.cumulativeDistanceM >= meters) _finish(state);
      case DurationTarget(:final minutes):
        if (fix.timestampMs - state.startedAtMs >= minutes * 60000) {
          _finish(state);
        }
    }

    return state;
  }

  /// Freezes [state] and computes its final [SessionState.summary].
  void _finish(SessionState state) {
    final samples = state.speedSamples;
    final avg = samples.isEmpty
        ? 0.0
        : samples.reduce((a, b) => a + b) / samples.length;
    state.summary = SessionSummary(
      topSpeedMs: state.topSpeedMs,
      avgSpeedMs: avg,
      distanceM: state.cumulativeDistanceM,
      elapsedMs: _lastGoodFix!.timestampMs - state.startedAtMs,
    );
    state.finished = true;
  }

  /// Great-circle distance in meters between two fixes (spherical earth).
  static double _haversineM(PositionFix a, PositionFix b) {
    double rad(double deg) => deg * math.pi / 180.0;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(a.lat)) * math.cos(rad(b.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadiusM * math.asin(math.sqrt(h));
  }
}
