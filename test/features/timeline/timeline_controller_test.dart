import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/models/models.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/timeline/timeline_controller.dart';
import 'package:sembast/sembast_memory.dart';

/// Fake [LocationService] with a controllable fix stream (same pattern as
/// test/app_shell_test.dart).
class FakeLocationService implements LocationService {
  final StreamController<PositionFix> fixes =
      StreamController<PositionFix>.broadcast();
  final StreamController<LocationStatus> statuses =
      StreamController<LocationStatus>.broadcast();

  final LocationStatus _status = LocationStatus.idle;

  @override
  bool get isSupported => true;

  @override
  LocationStatus get status => _status;

  @override
  Stream<PositionFix> watch() => fixes.stream;

  @override
  Stream<LocationStatus> get statusStream => statuses.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// Recording [WakeLockService]: ref-counted like the real one, no platform
/// wakelock behind it.
class FakeWakeLockService extends WakeLockService {
  int holdCount = 0;
  int releaseCount = 0;

  @override
  Future<void> hold() async {
    holdCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

/// Meters per degree of longitude at the equator (sphere, R = 6371000 m),
/// so tests can place fixes at exact metric offsets.
const double _metersPerDegLng = 6371000.0 * math.pi / 180.0;

/// Longitude of a point [meters] east of the prime meridian.
double lngAt(double meters) => meters / _metersPerDegLng;

/// Builds a fix on the equator heading east at [eastM] meters.
PositionFix fix({required int timestampMs, double eastM = 0.0}) => PositionFix(
      lat: 0.0,
      lng: lngAt(eastM),
      speedMs: 10.0,
      accuracyM: 10.0,
      headingDeg: 90.0,
      timestampMs: timestampMs,
      hasNativeSpeed: true,
    );

/// Minimal host that keeps the timeline controller alive.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(timelineControllerProvider);
    return const SizedBox.shrink();
  }
}

void main() {
  late FakeLocationService locationService;
  late FakeWakeLockService wakeLock;
  late IdbStorageService storage;

  setUp(() async {
    locationService = FakeLocationService();
    wakeLock = FakeWakeLockService();
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  Future<ProviderContainer> pumpHost(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(locationService),
        wakeLockServiceProvider.overrideWithValue(wakeLock),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Host()),
      ),
    );
    return container;
  }

  /// Emits [f] and waits for the (real-async) stream listener to run.
  Future<void> emit(PositionFix f) async {
    locationService.fixes.add(f);
    await Future<void>.delayed(Duration.zero);
  }

  testWidgets('toggle ON + moving fixes grows liveSegments, toggle OFF '
      'persists a TimelineEntry with the correct day and releases the '
      'wake lock', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpHost(tester);
      final controller = container.read(timelineControllerProvider.notifier);

      await controller.toggleRecording();
      expect(container.read(timelineControllerProvider).recording, isTrue);
      expect(wakeLock.holdCount, 1);
      expect(wakeLock.releaseCount, 0);

      // 5 minutes of moving fixes, 1 fix/10 s at 10 m/s: 100 m between
      // consecutive fixes, so no stop ever opens.
      for (var i = 0; i <= 30; i++) {
        await emit(fix(timestampMs: i * 10000, eastM: i * 100.0));
      }

      final live = container.read(timelineControllerProvider).liveSegments;
      expect(live, hasLength(1));
      expect(live.single, isA<RideSegment>());
      expect((live.single as RideSegment).points, hasLength(31));

      await controller.toggleRecording();
      expect(container.read(timelineControllerProvider).recording, isFalse);

      // Persisted to storage under the fix day (epoch ms 0 is UTC; the
      // storage layer keys by local midnight, so compare via timelineDays).
      final days = await storage.timelineDays();
      expect(days, hasLength(1));
      final entries = await storage.timelineEntriesForDay(days.single);
      expect(entries, hasLength(1));
      expect(entries.single.segments, hasLength(1));
      final ride = entries.single.segments.single as RideSegment;
      expect(ride.points, hasLength(31));

      // The persisted day is also exposed as the controller's active day.
      expect(container.read(timelineControllerProvider).activeDay, days.single);
      expect(
        container.read(timelineControllerProvider).dayEntries.single.segments,
        hasLength(1),
      );

      expect(wakeLock.holdCount, 1);
      expect(wakeLock.releaseCount, 1);
    });
  });

  testWidgets('replay of a stored day populates dayEntries', (tester) async {
    await tester.runAsync(() async {
      // Pre-seed storage with an entry for "today at local midnight".
      final day = DateTime(2026, 10, 9);
      await storage.upsertTimelineEntry(
        TimelineEntry(
          day: day,
          segments: [
            RideSegment(
              points: [
                TrackPoint(
                  lat: 0.0,
                  lng: 0.0,
                  speedMs: 12.0,
                  accuracyM: 8.0,
                  timestampMs: 0,
                ),
                TrackPoint(
                  lat: 0.0,
                  lng: lngAt(200),
                  speedMs: 12.0,
                  accuracyM: 8.0,
                  timestampMs: 20000,
                ),
              ],
            ),
            StopSegment(
              center: TrackPoint(
                lat: 0.0,
                lng: lngAt(200),
                speedMs: 0.0,
                accuracyM: 0.0,
                timestampMs: 20000,
              ),
              startMs: 20000,
              endMs: 20000 + 300000,
            ),
          ],
        ),
      );

      final container = await pumpHost(tester);
      final controller = container.read(timelineControllerProvider.notifier);

      // Days load on init; pump the event loop so the async load lands.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final state = container.read(timelineControllerProvider);
      expect(state.dayEntries, hasLength(1));
      expect(state.dayEntries.single.day, day);
      expect(state.dayEntries.single.segments, hasLength(2));

      // Explicitly selecting the day yields the same entries.
      await controller.selectDay(day);
      final selected = container.read(timelineControllerProvider);
      expect(selected.activeDay, day);
      expect(selected.dayEntries, hasLength(1));
      expect(selected.dayEntries.single.segments, hasLength(2));

      // The wake lock was never touched: replay is not recording.
      expect(wakeLock.holdCount, 0);
      expect(wakeLock.releaseCount, 0);
    });
  });
}
