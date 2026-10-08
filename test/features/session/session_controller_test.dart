import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/models/session.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/session/session_controller.dart';
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

/// Builds a good-accuracy fix on the equator heading east.
PositionFix fix({required int timestampMs, double lng = 0.0}) => PositionFix(
      lat: 0.0,
      lng: lng,
      speedMs: 10.0,
      accuracyM: 10.0,
      headingDeg: 90.0,
      timestampMs: timestampMs,
      hasNativeSpeed: true,
    );

/// Minimal host that keeps the session controller alive.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionControllerProvider);
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

  /// Pumps the host inside [tester.runAsync] so the async stream listeners
  /// and persistence writes run on the real event loop.
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

  /// Emits [fix] and waits for the (real-async) stream listener to run.
  Future<void> emit(PositionFix f) async {
    locationService.fixes.add(f);
    await Future<void>.delayed(Duration.zero);
  }

  testWidgets('10 m/s fixes 1 s apart finish a 100 m distance target after '
      '10 s worth of fixes', (tester) async {
    await tester.runAsync(() async {
      final container = await pumpHost(tester);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start(const DistanceTarget(100));

      // Let the host build and the controller publish the started state.
      await Future<void>.delayed(Duration.zero);

      // Starting holds the wake lock.
      expect(wakeLock.holdCount, 1);
      expect(wakeLock.releaseCount, 0);

      // 11 fixes at 10 m/s, 1 s apart: 10 legs of 10 m = exactly 100 m.
      // The first fix only seeds the engine's baseline (no distance yet).
      await emit(fix(timestampMs: 0));
      for (var i = 1; i <= 10; i++) {
        await emit(fix(timestampMs: i * 1000, lng: lngAt(i * 10.0)));
      }

      final state = container.read(sessionControllerProvider);
      expect(state.live, isNotNull);
      expect(state.live!.finished, isTrue);
      expect(state.live!.cumulativeDistanceM, closeTo(100, 0.01));
      expect(state.progress, closeTo(1.0, 1e-9));

      // Let the fire-and-forget persist complete.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
        if (container.read(sessionControllerProvider).lastSummary != null) {
          break;
        }
      }

      // Summary exposed and consistent: 10 s elapsed at 10 m/s.
      final summary = container.read(sessionControllerProvider).lastSummary;
      expect(summary, isNotNull);
      expect(summary!.topSpeedMs, 10.0);
      expect(summary.avgSpeedMs, closeTo(10.0, 1e-9));
      expect(summary.distanceM, closeTo(100, 0.01));
      expect(summary.elapsedMs, 10000);

      // Session + track points saved to storage.
      final sessions = await storage.sessionsForVehicle('default');
      expect(sessions, hasLength(1));
      final saved = sessions.single;
      expect(saved.status, SessionStatus.completed);
      expect(saved.target, const DistanceTarget(100));
      expect(saved.summary!.distanceM, closeTo(100, 0.01));
      final points = await storage.trackPoints(saved.id);
      expect(points, hasLength(11));

      // Wake lock released after the finish.
      expect(wakeLock.holdCount, 1);
      expect(wakeLock.releaseCount, 1);
    });
  });

  testWidgets('stop() mid-session saves the session with status stopped',
      (tester) async {
    await tester.runAsync(() async {
      final container = await pumpHost(tester);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start(const DistanceTarget(100));

      await emit(fix(timestampMs: 0));
      for (var i = 1; i <= 4; i++) {
        await emit(fix(timestampMs: i * 1000, lng: lngAt(i * 10.0)));
      }
      expect(
        container.read(sessionControllerProvider).live!.finished,
        isFalse,
      );

      await controller.stop();

      final state = container.read(sessionControllerProvider);
      expect(state.live, isNull);
      expect(state.lastSummary, isNotNull);
      expect(state.lastSummary!.distanceM, closeTo(40, 0.01));
      expect(state.lastSummary!.elapsedMs, 4000);

      final sessions = await storage.sessionsForVehicle('default');
      expect(sessions, hasLength(1));
      final saved = sessions.single;
      expect(saved.status, SessionStatus.stopped);
      expect(saved.summary!.distanceM, closeTo(40, 0.01));
      final points = await storage.trackPoints(saved.id);
      expect(points, hasLength(5));

      // Wake lock released on stop.
      expect(wakeLock.holdCount, 1);
      expect(wakeLock.releaseCount, 1);
    });
  });
}
