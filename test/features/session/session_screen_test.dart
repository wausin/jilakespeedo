import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/models/session.dart';
import 'package:jilake_speedo/core/models/units.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/session/session_controller.dart';
import 'package:jilake_speedo/features/session/session_screen.dart';
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

/// Builds a good-accuracy fix on the equator heading east.
PositionFix _fix({int timestampMs = 0, double speedMs = 10.0}) => PositionFix(
      lat: 0.0,
      lng: 0.0,
      speedMs: speedMs,
      accuracyM: 10.0,
      headingDeg: 90.0,
      timestampMs: timestampMs,
      hasNativeSpeed: true,
    );

void main() {
  group('elapsedLabelAt (wall-clock live duration display)', () {
    const startMs = 1000000;
    const budgetMs = 5 * 60000;

    test('advances with the wall clock across a fix gap', () {
      expect(elapsedLabelAt(startMs, startMs, budgetMs), '0:00');
      expect(elapsedLabelAt(startMs, startMs + 65000, budgetMs), '1:05');
      expect(elapsedLabelAt(startMs, startMs + 125000, budgetMs), '2:05');
    });

    test('is clamped to the budget and never negative', () {
      expect(elapsedLabelAt(startMs, startMs + 999000, budgetMs), '5:00');
      expect(elapsedLabelAt(startMs, startMs - 5000, budgetMs), '0:00');
    });
  });

  late FakeLocationService locationService;
  late FakeWakeLockService wakeLock;
  late IdbStorageService storage;

  setUp(() async {
    locationService = FakeLocationService();
    wakeLock = FakeWakeLockService();
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
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
        child: const MaterialApp(home: Scaffold(body: SessionScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('target picker shows distance/duration options and starts a '
      'session', (tester) async {
    final container = await pumpScreen(tester);

    // Segmented control with both modes.
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);

    // Distance presets (default unit km/h).
    for (final label in ['0.5', '1', '2', '5', '10']) {
      expect(find.text(label), findsOneWidget, reason: 'distance $label km');
    }

    // Switch to duration presets.
    await tester.tap(find.text('Duration'));
    await tester.pumpAndSettle();
    for (final label in ['1', '3', '5', '10', '30']) {
      expect(find.text(label), findsOneWidget, reason: 'duration $label min');
    }

    // Start from the duration tab with the default 5 min target.
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    // Anchor the session clock with a first accepted fix. Stream listeners
    // run on the real event loop, so drive them via runAsync.
    await tester.runAsync(() async {
      locationService.fixes.add(_fix());
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    final live = container.read(sessionControllerProvider).live;
    expect(live, isNotNull);
    expect(live!.finished, isFalse);
    expect(live.target, const DurationTarget(5));
    expect(wakeLock.holdCount, 1);

    // Live progress shows a circular indicator and the stop affordance.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  /// Emits [fix] and waits for the real-async stream listener to run.
  Future<void> emit(PositionFix f) async {
    locationService.fixes.add(f);
    await Future<void>.delayed(Duration.zero);
  }

  /// Waits until the controller exposes a summary (persist settled).
  Future<void> waitForSummary(ProviderContainer container) async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
      if (container.read(sessionControllerProvider).lastSummary != null) {
        return;
      }
    }
  }

  /// Longitude of a point [meters] east of the prime meridian.
  double lngAt(double meters) =>
      meters / (6371000.0 * 3.141592653589793 / 180.0);

  testWidgets('summary card shows top/avg speed and elapsed for a distance '
      'session, unit-aware', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpScreen(tester);
      final controller = container.read(sessionControllerProvider.notifier);

      // 100 m target, 10 legs of 10 m at 10 m/s → 10 s elapsed.
      await controller.start(const DistanceTarget(100));
      await emit(_fix(timestampMs: 0));
      for (var i = 1; i <= 10; i++) {
        await emit(_fix(timestampMs: i * 1000)..lng = lngAt(i * 10.0));
      }
      await waitForSummary(container);
      await tester.pump();

      // Distance-mode summary: top/avg speed + elapsed. 10 m/s = 36 km/h.
      expect(find.text('Top speed'), findsOneWidget);
      expect(find.text('Avg speed'), findsOneWidget);
      expect(find.text('Elapsed'), findsOneWidget);
      expect(find.text('36 km/h'), findsWidgets);
      expect(find.text('0:10'), findsOneWidget);
      // Distance target shown as 0.1 km.
      expect(find.textContaining('0.1 km'), findsWidgets);

      // Switch to mph: 10 m/s = 22.4 mph, 100 m = 0.1 mi.
      await container
          .read(settingsControllerProvider.notifier)
          .setUnit(SpeedUnit.mph);
      await Future<void>.delayed(Duration.zero);
      await tester.pump();
      expect(find.text('22.4 mph'), findsWidgets);
      expect(find.textContaining('0.1 mi'), findsWidgets);
    });
  });

  testWidgets('summary card shows distance plus speeds for a duration '
      'session, unit-aware', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpScreen(tester);
      final controller = container.read(sessionControllerProvider.notifier);

      // 1-minute duration target; drive 60 s of fixes at 10 m/s → 600 m.
      await controller.start(const DurationTarget(1));
      await emit(_fix(timestampMs: 0));
      for (var i = 1; i <= 60; i++) {
        await emit(_fix(timestampMs: i * 1000)..lng = lngAt(i * 10.0));
      }
      await waitForSummary(container);
      await tester.pump();

      // Duration-mode summary leads with distance. 600 m = 0.6 km.
      expect(find.text('Distance'), findsWidgets);
      expect(find.text('0.6 km'), findsWidgets);
      expect(find.text('36 km/h'), findsWidgets);
      expect(find.text('1:00'), findsOneWidget);

      // Switch to mph: 600 m = 0.4 mi.
      await container
          .read(settingsControllerProvider.notifier)
          .setUnit(SpeedUnit.mph);
      await Future<void>.delayed(Duration.zero);
      await tester.pump();
      expect(find.text('0.4 mi'), findsWidgets);
      expect(find.text('22.4 mph'), findsWidgets);
    });
  });

  testWidgets('stopped distance session renders the distance-mode summary '
      'layout', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpScreen(tester);
      final controller = container.read(sessionControllerProvider.notifier);

      // Start a distance target and stop mid-session.
      await controller.start(const DistanceTarget(100));
      await emit(_fix(timestampMs: 0));
      for (var i = 1; i <= 4; i++) {
        await emit(_fix(timestampMs: i * 1000)..lng = lngAt(i * 10.0));
      }
      await controller.stop();
      await waitForSummary(container);
      await tester.pump();

      // A stopped distance-target session still uses the distance-mode
      // layout: top/avg speed + elapsed first, distance last.
      expect(find.text('Top speed'), findsOneWidget);
      expect(find.text('Avg speed'), findsOneWidget);
      expect(find.text('Elapsed'), findsOneWidget);
      expect(find.text('0:04'), findsOneWidget);
    });
  });

  /// Builds a good-accuracy fix on the equator heading east, timestamped
  /// [DateTime.now()]-relative so the wall-clock-driven label anchors at 0.
  PositionFix fixNow({double speedMs = 10.0}) => _fix(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        speedMs: speedMs,
      );

  testWidgets('duration target: the live elapsed label is driven by the '
      'wall clock anchored at the first fix, and a fix past the budget '
      'finishes the session', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpScreen(tester);
      final controller = container.read(sessionControllerProvider.notifier);

      // 5-minute duration target; anchor the session clock with one fix.
      await controller.start(const DurationTarget(5));
      await emit(fixNow());
      await tester.pump();

      expect(find.byKey(sessionLiveKey), findsOneWidget);
      // Wall-clock elapsed since the anchor: ~0 s. (testWidgets freezes
      // the zone clock, so this cannot advance here — the tick math is
      // covered by the elapsedLabelAt unit tests; what matters is the
      // label renders from the wall clock, not from fix progress, which
      // is also 0 at the anchor.) The 1s display ticker is drained below
      // so no timer is left pending when the tree is torn down.
      expect(find.text('0:00 / 5 min'), findsOneWidget);

      // One good fix past the budget finishes the session (fix-driven
      // engine), and the completed summary shows the fix-measured elapsed.
      locationService.fixes.add(
        _fix(timestampMs: DateTime.now().millisecondsSinceEpoch + 6 * 60000),
      );
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
        if (container.read(sessionControllerProvider).lastSummary != null) {
          break;
        }
      }
      // The display ticker is still periodic after completion; drain it so
      // the test ends with no pending timers.
      await tester.pump(const Duration(minutes: 10));
      await tester.pump();

      final state = container.read(sessionControllerProvider);
      expect(state.live!.finished, isTrue);
      expect(state.lastSummary, isNotNull);
      // Budget (5 min) + ~1 min gap; real wall-clock may add a few ms
      // between the two DateTime.now() reads.
      expect(state.lastSummary!.elapsedMs, greaterThanOrEqualTo(6 * 60000));
      expect(state.lastSummary!.elapsedMs, lessThan(6 * 60000 + 5000));
      expect(find.byKey(sessionSummaryKey), findsOneWidget);
      expect(find.byKey(sessionLiveKey), findsNothing);
    });
  });

  testWidgets('stopped duration session renders the duration-mode summary '
      'layout', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpScreen(tester);
      final controller = container.read(sessionControllerProvider.notifier);

      // Start a duration target and stop mid-session after ~30 s.
      await controller.start(const DurationTarget(1));
      await emit(_fix(timestampMs: 0));
      for (var i = 1; i <= 30; i++) {
        await emit(_fix(timestampMs: i * 1000)..lng = lngAt(i * 10.0));
      }
      await controller.stop();
      await waitForSummary(container);
      await tester.pump();

      // A stopped duration-target session uses the duration-mode layout:
      // distance first, then speeds, then elapsed. 300 m = 0.3 km.
      expect(find.text('Distance'), findsWidgets);
      expect(find.text('0.3 km'), findsWidgets);
      expect(find.text('36 km/h'), findsWidgets);
      expect(find.text('0:30'), findsOneWidget);
    });
  });
}
