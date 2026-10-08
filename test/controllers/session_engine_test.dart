import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/session_engine.dart';
import 'package:jilake_speedo/core/models/session.dart';
import 'package:jilake_speedo/core/services/location_service.dart';

/// Meters per degree of longitude at the equator (sphere, R = 6371000 m),
/// so tests can place fixes at exact metric offsets.
const double _metersPerDegLng = 6371000.0 * math.pi / 180.0;

/// Builds a good-accuracy fix on the equator heading east.
PositionFix fix({
  required int timestampMs,
  double lng = 0.0,
  double speedMs = 10.0,
  double accuracyM = 10.0,
}) =>
    PositionFix(
      lat: 0.0,
      lng: lng,
      speedMs: speedMs,
      accuracyM: accuracyM,
      headingDeg: 90.0,
      timestampMs: timestampMs,
      hasNativeSpeed: true,
    );

/// Longitude of a point [meters] east of the prime meridian.
double lngAt(double meters) => meters / _metersPerDegLng;

void main() {
  group('SessionEngine distance target', () {
    test(
        'finishes exactly when cumulative distance reaches the target'
        ' and reports the summary', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.distance(1000),
        startedAtMs: 0,
      );

      // 10 fixes 10 s apart at 10 m/s: 9 legs of 100 m = ~900 m.
      SessionState? state;
      for (var i = 0; i < 10; i++) {
        state = engine.onFix(fix(timestampMs: i * 10000, lng: lngAt(i * 100.0)));
        expect(state, isNotNull);
        expect(state!.finished, isFalse, reason: 'fix $i at ${i * 100} m');
      }
      expect(state!.cumulativeDistanceM, closeTo(900, 0.01));

      // The 11th fix crosses 1000 m (1000.5 m cumulative; the 0.5 m margin
      // keeps the >= comparison clear of floating-point rounding) and must
      // finish the session on this very fix.
      state = engine.onFix(fix(timestampMs: 100000, lng: lngAt(1000.5)));
      expect(state!.finished, isTrue);
      expect(state.cumulativeDistanceM, closeTo(1000.5, 0.01));

      final summary = state.summary!;
      expect(summary.topSpeedMs, 10.0);
      expect(summary.avgSpeedMs, closeTo(10.0, 1e-9));
      expect(summary.distanceM, closeTo(1000.5, 0.01));
      expect(summary.elapsedMs, 100000);
    });
  });

  group('SessionEngine duration target', () {
    test('finishes at the 2-minute fix and freezes against later fixes', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.duration(2),
        startedAtMs: 0,
      );

      // Fixes for 3 minutes, 10 s apart at 10 m/s (100 m legs). The engine
      // hands back the same live state object every time, so capture the
      // finished flag eagerly at each fix.
      var finalState = engine.onFix(fix(timestampMs: 0));
      final finishedByFix = <bool>[finalState!.finished];
      for (var i = 1; i <= 18; i++) {
        finalState = engine
            .onFix(fix(timestampMs: i * 10000, lng: lngAt(i * 100.0)));
        finishedByFix.add(finalState!.finished);
      }

      // Still running one fix before the 2-minute mark.
      expect(finishedByFix[11], isFalse);

      // The fix at exactly 2 min reaches the target.
      expect(finishedByFix[12], isTrue);

      // Frozen summary: the 12 deltas up to and including the 2-min fix.
      final done = finalState!;
      expect(done.finished, isTrue);
      expect(done.summary!.elapsedMs, 120000);
      expect(done.summary!.distanceM, closeTo(1200, 0.01));
      expect(done.speedSamples.length, 13);

      // Every later fix returns the same frozen state, nothing changes.
      final late = engine.onFix(fix(timestampMs: 190000, lng: lngAt(1900)));
      expect(late, same(done));
      expect(done.summary!.distanceM, closeTo(1200, 0.01));
      expect(done.speedSamples.length, 13);
    });
  });

  group('SessionEngine accuracy gate', () {
    test('low-accuracy fix is skipped entirely', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.distance(100000),
        startedAtMs: 0,
      );

      expect(engine.onFix(fix(timestampMs: 0)), isNotNull);
      final before = engine.onFix(fix(timestampMs: 10000, lng: lngAt(100)));
      expect(before!.cumulativeDistanceM, closeTo(100, 0.01));

      // Bad fix: 120 m accuracy, a 50 m/s speed spike, and a 1 km teleport.
      // It is skipped entirely: the engine hands back the current state,
      // unchanged (same instance, nothing advanced, nothing sampled).
      final skipped = engine.onFix(fix(
        timestampMs: 20000,
        lng: lngAt(1100),
        speedMs: 50.0,
        accuracyM: 120.0,
      ));
      expect(skipped, same(before));

      // The next good fix advances from the last GOOD position (~100 m leg,
      // not ~1 km from the teleported one), and the spike was never sampled.
      final after = engine.onFix(fix(timestampMs: 30000, lng: lngAt(200)));
      expect(after!.cumulativeDistanceM, closeTo(200, 0.01));
      expect(after.topSpeedMs, 10.0);
      expect(after.speedSamples, [10.0, 10.0, 10.0]);
    });

    test('fix at exactly the accuracy threshold is included', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.distance(100000),
        startedAtMs: 0,
      );

      expect(engine.onFix(fix(timestampMs: 0)), isNotNull);
      final state = engine.onFix(
        fix(timestampMs: 10000, lng: lngAt(100), accuracyM: 50.0),
      );
      expect(state, isNotNull);
      expect(state!.cumulativeDistanceM, closeTo(100, 0.01));
    });

    test('bad fix as the very first fix leaves the session pristine', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.distance(100000),
        startedAtMs: 0,
      );

      final state = engine.onFix(fix(timestampMs: 0, accuracyM: 120.0));
      expect(state, isNotNull);
      expect(state!.cumulativeDistanceM, 0);
      expect(state.topSpeedMs, 0);
      expect(state.speedSamples, isEmpty);

      // The first good fix becomes the baseline (no distance yet — distance
      // resumes on the following fix); no phantom distance from the skipped
      // fix's position.
      final next = engine.onFix(fix(timestampMs: 10000, lng: lngAt(100)));
      expect(next!.cumulativeDistanceM, 0);
      expect(next.speedSamples, [10.0]);
    });
  });

  group('SessionEngine finish freeze', () {
    test('fix after finish returns the same state with no changes', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.distance(100),
        startedAtMs: 0,
      );

      expect(engine.onFix(fix(timestampMs: 0)), isNotNull);
      final done = engine.onFix(fix(timestampMs: 10000, lng: lngAt(100)));
      expect(done!.finished, isTrue);

      final late = engine.onFix(
        fix(timestampMs: 20000, lng: lngAt(200), speedMs: 30.0),
      );
      expect(late, same(done));
      expect(late!.topSpeedMs, 10.0);
      expect(late.speedSamples.length, 2);
      expect(late.cumulativeDistanceM, closeTo(100, 0.01));
      expect(late.summary!.elapsedMs, 10000);
    });
  });

  group('SessionEngine lifecycle', () {
    test('onFix before start returns null', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      expect(engine.onFix(fix(timestampMs: 0)), isNull);
    });

    test('start resets state for a new session', () {
      final engine = SessionEngine(accuracyThresholdM: 50);
      engine.start(
        vehicleId: 'v1',
        target: SessionTarget.distance(100),
        startedAtMs: 0,
      );
      expect(engine.onFix(fix(timestampMs: 0)), isNotNull);
      expect(
        engine.onFix(fix(timestampMs: 10000, lng: lngAt(100)))!.finished,
        isTrue,
      );

      engine.start(
        vehicleId: 'v2',
        target: SessionTarget.duration(5),
        startedAtMs: 60000,
      );
      final state = engine.onFix(fix(timestampMs: 60000));
      expect(state, isNotNull);
      expect(state!.vehicleId, 'v2');
      expect(state.target, SessionTarget.duration(5));
      expect(state.cumulativeDistanceM, 0);
      expect(state.topSpeedMs, 10.0);
      expect(state.speedSamples, [10.0]);
      expect(state.finished, isFalse);
      expect(state.summary, isNull);
    });
  });
}
