import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';

void main() {
  group('SessionTarget', () {
    test('SessionTarget.distance creates a distance target of meters',
        () {
      final target = SessionTarget.distance(1000);
      expect(target, isA<DistanceTarget>());
      expect((target as DistanceTarget).meters, 1000);
    });

    test('SessionTarget.duration creates a duration target of minutes',
        () {
      final target = SessionTarget.duration(5);
      expect(target, isA<DurationTarget>());
      expect((target as DurationTarget).minutes, 5);
    });

    test('fromJson/toJson round-trips a distance target', () {
      final target = SessionTarget.distance(1000);
      final restored = SessionTarget.fromJson(target.toJson());
      expect(restored, target);
    });

    test('fromJson/toJson round-trips a duration target', () {
      final target = SessionTarget.duration(5);
      final restored = SessionTarget.fromJson(target.toJson());
      expect(restored, target);
    });
  });

  group('SessionSummary', () {
    test('fromJson/toJson round-trips', () {
      final summary = SessionSummary(
        topSpeedMs: 30.0,
        avgSpeedMs: 15.0,
        distanceM: 5000.0,
        elapsedMs: 300000,
      );
      final restored = SessionSummary.fromJson(summary.toJson());
      expect(restored, summary);
    });
  });

  group('Session', () {
    test('fromJson/toJson round-trips a completed session with summary',
        () {
      final session = Session(
        id: 's1',
        vehicleId: 'v1',
        target: SessionTarget.distance(1000),
        startedAtMs: 1700000000000,
        endedAtMs: 1700000300000,
        status: SessionStatus.completed,
        summary: SessionSummary(
          topSpeedMs: 30.0,
          avgSpeedMs: 15.0,
          distanceM: 1000.0,
          elapsedMs: 300000,
        ),
      );
      final restored = Session.fromJson(session.toJson());
      expect(restored, session);
    });

    test('fromJson/toJson round-trips a running session without summary',
        () {
      final session = Session(
        id: 's1',
        vehicleId: 'v1',
        target: SessionTarget.duration(5),
        startedAtMs: 1700000000000,
      );
      final restored = Session.fromJson(session.toJson());
      expect(restored, session);
      expect(restored.status, SessionStatus.running);
      expect(restored.summary, isNull);
      expect(restored.endedAtMs, isNull);
    });

    test('distance and duration targets are not equal', () {
      expect(
        SessionTarget.distance(1000),
        isNot(SessionTarget.duration(5)),
      );
      expect(
        SessionTarget.distance(1000),
        SessionTarget.distance(1000),
      );
      expect(
        SessionTarget.duration(5),
        SessionTarget.duration(5),
      );
    });
  });
}
