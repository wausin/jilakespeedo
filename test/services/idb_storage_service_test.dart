import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:sembast/sembast_memory.dart';

TrackPoint _point(int timestampMs) => TrackPoint(
  lat: 12.3456,
  lng: 78.9101,
  speedMs: 10.5,
  accuracyM: 4.2,
  timestampMs: timestampMs,
);

Session _session({
  required String id,
  required String vehicleId,
  required int startedAtMs,
}) => Session(
  id: id,
  vehicleId: vehicleId,
  target: SessionTarget.distance(5000),
  startedAtMs: startedAtMs,
  endedAtMs: startedAtMs + 60000,
  status: SessionStatus.completed,
  summary: SessionSummary(
    topSpeedMs: 20,
    avgSpeedMs: 15,
    distanceM: 5000,
    elapsedMs: 60000,
  ),
);

void main() {
  late IdbStorageService storage;

  setUp(() async {
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  group('vehicles', () {
    test('upsert and fetch round-trips fields', () async {
      final bike = Vehicle(
        id: 'v1',
        name: 'Mountain Bike',
        type: VehicleType.bike,
        gaugeMaxKmh: 90,
        isPinned: true,
      );
      final car = Vehicle(
        id: 'v2',
        name: 'Daily Car',
        type: VehicleType.car,
        gaugeMaxKmh: 280,
      );

      await storage.upsertVehicle(bike);
      await storage.upsertVehicle(car);

      final vehicles = await storage.vehicles();
      expect(vehicles, hasLength(2));
      expect(vehicles, containsAll([bike, car]));
    });

    test('upsert with same id replaces the vehicle', () async {
      await storage.upsertVehicle(
        Vehicle(id: 'v1', name: 'Old Name', type: VehicleType.bike),
      );
      await storage.upsertVehicle(
        Vehicle(
          id: 'v1',
          name: 'New Name',
          type: VehicleType.motorcycle,
          gaugeMaxKmh: 200,
          isPinned: true,
        ),
      );

      final vehicles = await storage.vehicles();
      expect(vehicles, hasLength(1));
      expect(vehicles.single.name, 'New Name');
      expect(vehicles.single.type, VehicleType.motorcycle);
      expect(vehicles.single.isPinned, isTrue);
    });

    test('delete removes only the targeted vehicle', () async {
      final v1 = Vehicle(id: 'v1', name: 'A', type: VehicleType.bike);
      final v2 = Vehicle(id: 'v2', name: 'B', type: VehicleType.car);
      await storage.upsertVehicle(v1);
      await storage.upsertVehicle(v2);

      await storage.deleteVehicle('v1');

      final vehicles = await storage.vehicles();
      expect(vehicles, hasLength(1));
      expect(vehicles.single, equals(v2));
    });
  });

  group('sessions', () {
    test('sessionsForVehicle returns newest-first by startedAt', () async {
      final sOld = _session(id: 's1', vehicleId: 'vA', startedAtMs: 1000);
      final sMid = _session(id: 's2', vehicleId: 'vA', startedAtMs: 2000);
      final sNew = _session(id: 's3', vehicleId: 'vA', startedAtMs: 3000);
      final other = _session(id: 's4', vehicleId: 'vB', startedAtMs: 4000);
      await storage.saveSession(sOld);
      await storage.saveSession(sNew);
      await storage.saveSession(sMid);
      await storage.saveSession(other);

      final sessions = await storage.sessionsForVehicle('vA');
      expect(sessions.map((s) => s.id), ['s3', 's2', 's1']);
      expect(sessions, containsAll([sOld, sMid, sNew]));
    });

    test('limit returns only the most recent sessions', () async {
      for (var i = 0; i < 3; i++) {
        await storage.saveSession(
          _session(id: 's$i', vehicleId: 'vA', startedAtMs: 1000 + i),
        );
      }

      final limited = await storage.sessionsForVehicle('vA', limit: 2);
      expect(limited.map((s) => s.id), ['s2', 's1']);
    });

    test('round-trips target, status, and summary', () async {
      final session = Session(
        id: 's1',
        vehicleId: 'v1',
        target: SessionTarget.duration(30),
        startedAtMs: 5000,
        endedAtMs: 9000,
        status: SessionStatus.stopped,
        summary: SessionSummary(
          topSpeedMs: 30,
          avgSpeedMs: 12.5,
          distanceM: 1234.5,
          elapsedMs: 4000,
        ),
      );

      await storage.saveSession(session);

      final sessions = await storage.sessionsForVehicle('v1');
      expect(sessions.single, equals(session));
    });
  });

  group('track points', () {
    test('batched appends read back in insertion order', () async {
      final batch1 = [_point(100), _point(200), _point(300)];
      final batch2 = [_point(400), _point(500)];

      await storage.appendTrackPoints('s1', batch1);
      await storage.appendTrackPoints('s1', batch2);
      await storage.appendTrackPoints('s2', [_point(600)]);

      final points = await storage.trackPoints('s1');
      expect(points, equals(batch1 + batch2));

      final otherPoints = await storage.trackPoints('s2');
      expect(otherPoints.map((p) => p.timestampMs), [600]);
      expect(await storage.trackPoints('missing'), isEmpty);
    });
  });

  group('timeline', () {
    test('round-trips ride and stop segments', () async {
      final entry = TimelineEntry(
        day: DateTime(2026, 10, 8),
        segments: [
          RideSegment(points: [_point(1000), _point(1100), _point(1200)]),
          StopSegment(center: _point(1300), startMs: 1300, endMs: 7000),
        ],
      );

      await storage.upsertTimelineEntry(entry);

      final entries = await storage.timelineEntriesForDay(
        DateTime(2026, 10, 8),
      );
      expect(entries, hasLength(1));
      expect(entries.single, equals(entry));

      final days = await storage.timelineDays();
      expect(days, [DateTime(2026, 10, 8)]);
    });

    test('upsert for the same day replaces the entry', () async {
      final day = DateTime(2026, 10, 8);
      final first = TimelineEntry(
        day: day,
        segments: [
          RideSegment(points: [_point(100)]),
        ],
      );
      final second = TimelineEntry(
        day: day,
        segments: [StopSegment(center: _point(200), startMs: 200, endMs: 900)],
      );

      await storage.upsertTimelineEntry(first);
      await storage.upsertTimelineEntry(second);

      final entries = await storage.timelineEntriesForDay(day);
      expect(entries, hasLength(1));
      expect(entries.single, equals(second));
    });

    test('timelineDays returns distinct days newest-first', () async {
      final daysToWrite = [
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 9),
      ];
      for (final day in daysToWrite) {
        await storage.upsertTimelineEntry(
          TimelineEntry(day: day, segments: const []),
        );
      }

      final days = await storage.timelineDays();
      expect(days, [
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 9),
        DateTime(2026, 10, 8),
      ]);
    });

    test('forDay matches entries regardless of time-of-day', () async {
      final day = DateTime(2026, 10, 8, 14, 30);
      await storage.upsertTimelineEntry(
        TimelineEntry(
          day: day,
          segments: [
            RideSegment(points: [_point(100)]),
          ],
        ),
      );

      final entries = await storage.timelineEntriesForDay(
        DateTime(2026, 10, 8, 23, 59),
      );
      expect(entries, hasLength(1));
      expect(entries.single.day, DateTime(2026, 10, 8));
    });
  });
}
