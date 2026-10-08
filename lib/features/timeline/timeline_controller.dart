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

  TimelineState copyWith({
    bool? recording,
    List<TimelineSegment>? liveSegments,
    DateTime? Function()? activeDay,
    List<TimelineEntry>? dayEntries,
  }) =>
      TimelineState(
        recording: recording ?? this.recording,
        liveSegments: liveSegments ?? this.liveSegments,
        activeDay: activeDay != null ? activeDay() : this.activeDay,
        dayEntries: dayEntries ?? this.dayEntries,
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
    _subscription = ref.read(locationServiceProvider).watch().listen(_onFix);
    state = state.copyWith(recording: true, liveSegments: const []);
  }

  Future<void> _stopRecording() async {
    unawaited(_subscription?.cancel());
    _subscription = null;

    final segments = _collectSegments();
    _detector.reset();

    DateTime? recordedDay;
    if (segments.isNotEmpty) {
      recordedDay = _dayOfMs(_firstTimestampMs(segments));
      final storage = ref.read(storageServiceProvider);
      try {
        await storage.upsertTimelineEntry(
          TimelineEntry(day: recordedDay, segments: segments),
        );
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

  /// Local-midnight day of the first timestamp found in [segments].
  static int _firstTimestampMs(List<TimelineSegment> segments) {
    final first = segments.first;
    return switch (first) {
      RideSegment(:final points) => points.first.timestampMs,
      StopSegment(:final startMs) => startMs,
    };
  }

  static DateTime _dayOfMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Loads the most recent recorded day (if any) as the initial selection.
  Future<void> _loadLatestDay() async {
    final storage = ref.read(storageServiceProvider);
    final days = await storage.timelineDays();
    if (_disposed || days.isEmpty) return;
    await selectDay(days.first);
  }
}

/// The timeline controller. Kept alive app-wide so recording survives
/// navigation between screens.
final timelineControllerProvider =
    NotifierProvider<TimelineController, TimelineState>(
  TimelineController.new,
);
