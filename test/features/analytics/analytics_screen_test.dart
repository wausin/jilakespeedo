import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/models/models.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/features/analytics/analytics_screen.dart';
import 'package:sembast/sembast_memory.dart';

Session _session({
  required String id,
  double? distanceM,
  double? topMs,
}) =>
    Session(
      id: id,
      vehicleId: 'v1',
      target: const DistanceTarget(1000),
      startedAtMs: 0,
      endedAtMs: 10000,
      status: SessionStatus.completed,
      summary: distanceM == null
          ? null
          : SessionSummary(
              topSpeedMs: topMs ?? 0,
              avgSpeedMs: 0,
              distanceM: distanceM,
              elapsedMs: 10000,
            ),
    );

void main() {
  group('AnalyticsAggregate.from', () {
    test('sums distance, counts sessions, finds best top speed', () {
      final agg = AnalyticsAggregate.from([
        _session(id: 's1', distanceM: 1000, topMs: 20),
        _session(id: 's2', distanceM: 2000, topMs: 30),
      ]);
      expect(agg.sessionCount, 2);
      expect(agg.totalDistanceM, 3000);
      expect(agg.bestTopSpeedMs, 30);
    });

    test('skips sessions without a summary', () {
      final agg = AnalyticsAggregate.from([
        _session(id: 's1', distanceM: 1000, topMs: 20),
        _session(id: 's2'), // running / no summary
      ]);
      expect(agg.sessionCount, 1);
      expect(agg.totalDistanceM, 1000);
      expect(agg.bestTopSpeedMs, 20);
    });

    test('empty list yields zeroes', () {
      final agg = AnalyticsAggregate.from(const []);
      expect(agg.sessionCount, 0);
      expect(agg.totalDistanceM, 0);
      expect(agg.bestTopSpeedMs, 0);
    });
  });

  group('sessionsForVehicleProvider', () {
    test('reloads after invalidation when a new session is saved', () async {
      final storage =
          IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
      await storage.init();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      // Initially empty.
      expect(
        await container.read(sessionsForVehicleProvider('v1').future),
        isEmpty,
      );

      // A session is persisted directly, then the provider is invalidated
      // (as the session controller does when a session ends).
      await storage.saveSession(_session(id: 's1', distanceM: 1000, topMs: 20));
      container.invalidate(sessionsForVehicleProvider('v1'));

      final reloaded =
          await container.read(sessionsForVehicleProvider('v1').future);
      expect(reloaded, hasLength(1));
      expect(reloaded.single.id, 's1');
    });
  });
}
