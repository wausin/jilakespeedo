import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/controllers/stop_detector.dart';
import '../../core/models/models.dart';
import '../../core/services/location_service.dart';

/// State of the timeline feature: whether recording is on, the live
/// (not-yet-persisted) segments for the current recording, the currently
/// selected day, and the stored entries for that day.
class TimelineState {
  const TimelineState({
    this.recording = false,
    this.liveSegments = const [],
    this.activeDay,
    this.dayEntries = const [],
    this.error,
  });

  /// Whether the recorder is currently collecting fixes.
  final bool recording;

  /// Segments of the in-progress recording, in chronological order: the
  /// detector's closed segments followed by the still-open current ride
  /// (when it has any points). Empty when not recording.
  final List<TimelineSegment> liveSegments;

  /// Day currently shown on the map/list (local midnight), or null when no
  /// day has been selected or loaded yet.
  final DateTime? activeDay;

  /// Stored entries for [activeDay].
  final List<TimelineEntry> dayEntries;

  /// Human-readable error from the last failed record start (e.g. the
  /// location stream errored), or null when there is no error to show.
  final String? error;

  TimelineState copyWith({
    bool? recording,
    List<TimelineSegment>? liveSegments,
    DateTime? Function()? activeDay,
    List<TimelineEntry>? dayEntries,
    String? Function()? error,
  }) =>
      TimelineState(
        recording: recording ?? this.recording,
        liveSegments: liveSegments ?? this.liveSegments,
        activeDay: activeDay != null ? activeDay() : this.activeDay,
        dayEntries: dayEntries ?? this.dayEntries,
        error: error != null ? error() : this.error,
      );
}

/// Records GPS fixes into a Google-Timeline-like day of ride/stop segments,
/// and replays stored days from the [StorageService].
///
/// While recording, fixes from the [LocationService] are folded into a
/// [StopDetector] (rides vs stops) and the wake lock is held. On toggle-off
/// the still-open ride is flushed and the whole recording is persisted as a
/// [TimelineEntry] keyed by the local-midnight day of its first fix.
class TimelineController extends Notifier<TimelineState> {
  final StopDetector _detector = StopDetector();
  StreamSubscription<PositionFix>? _subscription;
  bool _disposed = false;

  @override
  TimelineState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
    });
    unawaited(_loadLatestDay());
    return const TimelineState();
  }

  /// Toggles recording on/off.
  ///
  /// On: holds the wake lock, resets the detector, subscribes to fixes.
  /// Off: cancels the subscription, flushes the open ride, persists the
  /// recording as a [TimelineEntry] (when it has any segments), selects the
  /// recorded day, and releases the wake lock.
  Future<void> toggleRecording() async {
    if (state.recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    await ref.read(wakeLockServiceProvider).hold();
    _detector.reset();
    unawaited(_subscription?.cancel());
    _subscription = ref.read(locationServiceProvider).watch().listen(
          _onFix,
          onError: (Object e) => unawaited(_onStreamError(e)),
        );
    state = state.copyWith(recording: true, liveSegments: const [], error: () => null);
  }

  /// A fix-stream error (e.g. permission not yet granted on this path, or
  /// hardware failure) ends the recording gracefully instead of leaving a
  /// broken live view: cancel, release the wake lock, flip recording off,
  /// and surface a message the screen can show.
  Future<void> _onStreamError(Object error) async {
    unawaited(_subscription?.cancel());
    _subscription = null;
    await ref.read(wakeLockServiceProvider).release();
    if (_disposed) return;
    state = state.copyWith(
      recording: false,
      liveSegments: const [],
      error: () => 'Location unavailable: $error',
    );
  }

  Future<void> _stopRecording() async {
    unawaited(_subscription?.cancel());
    _subscription = null;

    final segments = _collectSegments();
    _detector.reset();

    DateTime? recordedDay;
    if (segments.isNotEmpty) {
      // Google-Timeline-style: a midnight-crossing recording is filed one
      // entry per day (each day is its own storage record).
      final byDay = _splitByDay(segments);
      final storage = ref.read(storageServiceProvider);
      try {
        for (final entry in byDay.entries) {
          await storage.upsertTimelineEntry(
            TimelineEntry(day: entry.key, segments: entry.value),
          );
        }
        recordedDay = byDay.keys.first;
      } catch (_) {
        // Best-effort persist: recording is over regardless; the wake lock
        // is still released below.
        recordedDay = null;
      }
    }

    await ref.read(wakeLockServiceProvider).release();
    if (_disposed) return;

    state = state.copyWith(recording: false, liveSegments: const []);
    if (recordedDay != null) {
      await selectDay(recordedDay);
    }
  }

  /// Selects [day] (normalized to local midnight) and loads its entries.
  Future<void> selectDay(DateTime day) async {
    final midnight = DateTime(day.year, day.month, day.day);
    final entries =
        await ref.read(storageServiceProvider).timelineEntriesForDay(midnight);
    if (_disposed) return;
    state = state.copyWith(
      activeDay: () => midnight,
      dayEntries: entries,
    );
  }

  /// Clears a surfaced error after the screen has shown it.
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: () => null);
  }

  void _onFix(PositionFix fix) {
    _detector.onFix(fix);
    state = state.copyWith(liveSegments: _collectSegments());
  }

  /// Closed segments plus the still-open current ride (when it has points).
  List<TimelineSegment> _collectSegments() {
    final detectorState = _detector.state;
    final segments = [...detectorState.closedSegments];
    if (detectorState.currentRide.isNotEmpty) {
      segments.add(RideSegment(points: [...detectorState.currentRide]));
    }
    return segments;
  }

  /// Splits [segments] at local-midnight boundaries into an ordered map of
  /// day → segments (insertion order: chronological by first occurrence).
  /// A ride's points are divided by each point's local day; a stop goes to
  /// the day its start falls in (stops straddling midnight are attributed
  /// to the start day — a deliberate simplification).
  static Map<DateTime, List<TimelineSegment>> _splitByDay(
    List<TimelineSegment> segments,
  ) {
    final byDay = <DateTime, List<TimelineSegment>>{};
    for (final segment in segments) {
      switch (segment) {
        case RideSegment(:final points):
          DateTime? currentDay;
          var currentPoints = <TrackPoint>[];
          void flush() {
            final day = currentDay;
            if (day != null && currentPoints.isNotEmpty) {
              byDay.putIfAbsent(day, () => []).add(
                    RideSegment(points: currentPoints),
                  );
            }
          }

          for (final point in points) {
            final day = _dayOfMs(point.timestampMs);
            if (day != currentDay) {
              flush();
              currentDay = day;
              currentPoints = [];
            }
            currentPoints.add(point);
          }
          flush();
        case StopSegment():
          byDay
              .putIfAbsent(_dayOfMs(segment.startMs), () => [])
              .add(segment);
      }
    }
    return byDay;
  }

  static DateTime _dayOfMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Loads the most recent recorded day as the initial selection, or selects
  /// today when nothing has been recorded yet (so a date is always active).
  Future<void> _loadLatestDay() async {
    final storage = ref.read(storageServiceProvider);
    final days = await storage.timelineDays();
    if (_disposed) return;
    if (days.isEmpty) {
      final now = DateTime.now();
      await selectDay(DateTime(now.year, now.month, now.day));
      return;
    }
    await selectDay(days.first);
  }
}

/// The timeline controller. Kept alive app-wide so recording survives
/// navigation between screens.
final timelineControllerProvider =
    NotifierProvider<TimelineController, TimelineState>(
  TimelineController.new,
);
