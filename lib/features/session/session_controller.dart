import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/controllers/session_engine.dart';
import '../../core/models/models.dart';
import '../../core/services/location_service.dart';

/// State of the session feature: the live [SessionState] handed out by the
/// [SessionEngine] (mutable — render from it, never cache its fields), the
/// progress fraction toward the target, and the summary of the most recently
/// ended session (finished or stopped).
class SessionControllerState {
  const SessionControllerState({
    this.live,
    this.progress = 0,
    this.lastSummary,
  });

  /// Live session state while a session is running; stays non-null (frozen,
  /// `finished == true`) while the finished summary is shown, null when idle.
  final SessionState? live;

  /// Progress toward the session target, clamped to 0..1.
  final double progress;

  /// Summary of the last session that ended (completed or stopped).
  final SessionSummary? lastSummary;

  SessionControllerState copyWith({
    SessionState? Function()? live,
    double? progress,
    SessionSummary? Function()? lastSummary,
  }) =>
      SessionControllerState(
        live: live != null ? live() : this.live,
        progress: progress ?? this.progress,
        lastSummary: lastSummary != null ? lastSummary() : this.lastSummary,
      );
}

/// Runs a target session: feeds [LocationService] fixes into the
/// [SessionEngine], holds the wake lock while running, and on finish/stop
/// persists the [Session] and its [TrackPoint]s via the [StorageService].
class SessionController extends Notifier<SessionControllerState> {
  static const double _accuracyThresholdM = 50;

  final SessionEngine _engine = SessionEngine(
    accuracyThresholdM: _accuracyThresholdM,
  );
  StreamSubscription<PositionFix>? _subscription;
  String? _vehicleId;
  SessionTarget? _target;
  int? _startFixMs;
  Session? _session;
  List<TrackPoint> _trackPoints = [];
  bool _disposed = false;

  @override
  SessionControllerState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
    });
    return const SessionControllerState();
  }

  /// Starts a session toward [target] for the active vehicle.
  ///
  /// Holds the wake lock and subscribes to location fixes; the session is
  /// persisted when the target is met or [stop] is called.
  ///
  /// The session clock is the first accepted fix's timestamp (the engine
  /// measures elapsed time from fixes), so [Session.startedAtMs] is only
  /// resolved once that first fix arrives.
  Future<void> start(SessionTarget target) async {
    // Idempotence: a session already running keeps running.
    if (state.live != null && !state.live!.finished) return;

    await ref.read(wakeLockServiceProvider).hold();

    _vehicleId = ref.read(vehiclesProvider).activeVehicleId ?? 'default';
    _target = target;
    _startFixMs = null;
    _session = null;
    _trackPoints = [];
    unawaited(_subscription?.cancel());
    _subscription = ref.read(locationServiceProvider).watch().listen(_onFix);
    state = SessionControllerState(
      live: null,
      progress: 0,
      lastSummary: state.lastSummary,
    );
  }

  void _onFix(PositionFix fix) {
    final target = _target;
    if (target == null) return;

    // The first accepted fix anchors the session clock and record.
    if (_startFixMs == null) {
      if (fix.accuracyM > _accuracyThresholdM) return;
      final startMs = fix.timestampMs;
      _startFixMs = startMs;
      _engine.start(
        vehicleId: _vehicleId!,
        target: target,
        startedAtMs: startMs,
      );
      _session = Session(
        id: 's$startMs',
        vehicleId: _vehicleId!,
        target: target,
        startedAtMs: startMs,
      );
    }

    final sessionState = _engine.onFix(fix);
    if (sessionState == null) return;

    if (fix.accuracyM <= _accuracyThresholdM) {
      _trackPoints.add(
        TrackPoint(
          lat: fix.lat,
          lng: fix.lng,
          speedMs: fix.speedMs,
          accuracyM: fix.accuracyM,
          timestampMs: fix.timestampMs,
        ),
      );
    }

    // The engine hands back the same live, mutable instance on every fix —
    // publish the reference so the UI always renders the current numbers.
    state = SessionControllerState(
      live: sessionState,
      progress: _progressFor(sessionState),
      lastSummary: state.lastSummary,
    );

    if (sessionState.finished) {
      _endSession(SessionStatus.completed, sessionState.summary!);
    }
  }

  double _progressFor(SessionState s) {
    switch (s.target) {
      case DistanceTarget(:final meters):
        if (meters <= 0) return 1;
        return (s.cumulativeDistanceM / meters).clamp(0.0, 1.0);
      case DurationTarget(:final minutes):
        // Progress is derived from fixes (no wall clock): the engine only
        // advances a duration target on fixes, so before the finish the
        // elapsed time is "last accepted fix minus start".
        final budget = minutes * 60000;
        if (budget <= 0) return 1;
        final elapsed = _trackPoints.isEmpty
            ? 0
            : _trackPoints.last.timestampMs - s.startedAtMs;
        return (elapsed / budget).clamp(0.0, 1.0);
    }
  }

  /// Stops the running session early; the partial session is persisted with
  /// [SessionStatus.stopped].
  Future<void> stop() async {
    final target = _target;
    if (target == null) return;
    final live = state.live;
    if (live != null && live.finished) return;

    unawaited(_subscription?.cancel());
    _subscription = null;

    if (live == null) {
      // No accepted fix yet: nothing was recorded, just release the hold.
      _target = null;
      _vehicleId = null;
      await ref.read(wakeLockServiceProvider).release();
      state = const SessionControllerState();
      return;
    }

    await _endSession(SessionStatus.stopped, _partialSummary(live));
  }

  SessionSummary _partialSummary(SessionState live) {
    final samples = live.speedSamples;
    final avg = samples.isEmpty
        ? 0.0
        : samples.reduce((a, b) => a + b) / samples.length;
    final elapsed = _trackPoints.isEmpty
        ? 0
        : _trackPoints.last.timestampMs - live.startedAtMs;
    return SessionSummary(
      topSpeedMs: live.topSpeedMs,
      avgSpeedMs: avg,
      distanceM: live.cumulativeDistanceM,
      elapsedMs: elapsed < 0 ? 0 : elapsed,
    );
  }

  Future<void> _endSession(SessionStatus status, SessionSummary summary) async {
    unawaited(_subscription?.cancel());
    _subscription = null;

    final session = _session;
    if (session != null) {
      final endedAtMs = session.startedAtMs + summary.elapsedMs;
      final record = session.copyWith(
        endedAtMs: endedAtMs,
        status: status,
        summary: summary,
      );
      final storage = ref.read(storageServiceProvider);
      // Track points first: a crash between the two writes then leaves
      // orphaned points rather than a session referencing missing data.
      await storage.appendTrackPoints(session.id, _trackPoints);
      await storage.saveSession(record);
    }
    _session = null;
    _trackPoints = [];
    _target = null;
    _vehicleId = null;
    _startFixMs = null;

    await ref.read(wakeLockServiceProvider).release();

    // The persist above may resume after the provider was disposed (widget
    // tree torn down / container disposed): the session is durably saved,
    // so dropping the state update is safe.
    if (_disposed) return;
    state = SessionControllerState(
      live: status == SessionStatus.completed ? state.live : null,
      progress: status == SessionStatus.completed ? 1 : 0,
      lastSummary: summary,
    );
  }
}

/// The session controller. Kept alive app-wide so a running session survives
/// navigation between screens.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionControllerState>(
  SessionController.new,
);
