import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/stop_detector.dart';
import 'package:jilake_speedo/core/models/timeline_entry.dart';
import 'package:jilake_speedo/core/services/location_service.dart';

/// Meters per degree of longitude at the equator (sphere, R = 6371000 m),
/// so tests can place fixes at exact metric offsets.
const double _metersPerDegLng = 6371000.0 * math.pi / 180.0;

/// Longitude of a point [meters] east of the prime meridian on the equator.
double lngAt(double meters) => meters / _metersPerDegLng;

/// Builds a fix on the equator, [eastM] meters east of the prime meridian.
PositionFix fix({required int timestampMs, double eastM = 0.0}) => PositionFix(
      lat: 0.0,
      lng: lngAt(eastM),
      speedMs: 0.0,
      accuracyM: 10.0,
      headingDeg: 0.0,
      timestampMs: timestampMs,
      hasNativeSpeed: true,
    );

void main() {
  group('StopDetector while moving', () {
    test('moving fixes accumulate into currentRide, nothing closes', () {
      final detector = StopDetector();

      for (var i = 0; i < 5; i++) {
        detector.onFix(fix(timestampMs: i * 10000, eastM: i * 100.0));
      }

      expect(detector.state.inStop, isFalse);
      expect(detector.state.closedSegments, isEmpty);
      expect(detector.state.currentRide, hasLength(5));
      expect(detector.state.currentRide.first.timestampMs, 0);
      expect(detector.state.currentRide.last.timestampMs, 40000);
      expect(detector.state.currentRide.last.lng, closeTo(lngAt(400), 1e-12));
    });
  });

  group('StopDetector stop detection', () {
    test(
        'fixes clustered within 25 m for 4 min open a stop with correct '
        'start/end, then movement closes it and appends the rides', () {
      final detector = StopDetector();

      // Ride in: 3 fixes heading east, 100 m apart.
      for (var i = 0; i < 3; i++) {
        detector.onFix(fix(timestampMs: i * 10000, eastM: i * 100.0));
      }

      // Parked at 305 m for 4 minutes: 6 fixes whose first-to-last span is
      // exactly 240 s, jittering 5 m either side of the 305 m anchor (well
      // inside the 25 m radius) and averaging exactly to it.
      final parked = [305.0, 300.0, 310.0, 305.0, 300.0, 310.0];
      for (var i = 0; i < parked.length; i++) {
        detector.onFix(fix(timestampMs: 30000 + i * 48000, eastM: parked[i]));
        if (i < 3) {
          expect(detector.state.inStop, isFalse,
              reason: 'stop must not open before the 3-minute threshold');
        }
      }
      expect(detector.state.inStop, isTrue);

      // Departure: the first fix beyond the radius closes the stop.
      detector.onFix(fix(timestampMs: 300000, eastM: 400.0));
      expect(detector.state.inStop, isFalse);

      // Ride on so the post-stop ride has more than the departure point.
      detector.onFix(fix(timestampMs: 310000, eastM: 500.0));

      final closed = detector.state.closedSegments;
      expect(closed, hasLength(2));

      // The pre-stop ride closes when the stop opens.
      final rideBefore = closed[0] as RideSegment;
      expect(rideBefore.points, hasLength(3));
      expect(rideBefore.points.first.timestampMs, 0);
      expect(rideBefore.points.last.timestampMs, 20000);

      // The stop spans the whole 4-minute dwell, from the first parked fix
      // to the last stationary one; its center is the dwell centroid.
      final stop = closed[1] as StopSegment;
      expect(stop.startMs, 30000);
      expect(stop.endMs, 270000);
      expect(stop.dwellMs, 240000);
      expect(stop.center.lat, closeTo(0.0, 1e-12));
      expect(stop.center.lng, closeTo(lngAt(305.0), 1e-9));
      expect(stop.center.timestampMs, 30000);

      // The new ride after the stop is in progress: its fixes accumulate in
      // currentRide, not yet closed.
      expect(detector.state.currentRide, hasLength(2));
      expect(detector.state.currentRide.first.timestampMs, 300000);
      expect(detector.state.currentRide.last.timestampMs, 310000);
    });

    test('a slow drift that never leaves the radius keeps the stop open', () {
      final detector = StopDetector();

      // Creeping 2 m per minute: every fix stays well within 25 m of the
      // running centroid, so after 3 minutes the stop opens and holds.
      for (var i = 0; i < 4; i++) {
        detector.onFix(fix(timestampMs: i * 60000, eastM: i * 2.0));
      }

      expect(detector.state.inStop, isTrue);
      expect(detector.state.currentRide, isEmpty);

      // Still parked: nothing is closed yet, the stop is only open.
      expect(detector.state.closedSegments, isEmpty);

      // Driving off beyond the radius closes the stop and starts a ride.
      detector.onFix(fix(timestampMs: 240000, eastM: 100.0));
      expect(detector.state.inStop, isFalse);

      final closed = detector.state.closedSegments;
      expect(closed, hasLength(1));
      final stop = closed.single as StopSegment;
      expect(stop.startMs, 0);
      expect(stop.endMs, 180000);
      // Centroid of 0, 2, 4, 6 m east.
      expect(stop.center.lng, closeTo(lngAt(3.0), 1e-9));
      // The departure fix begins the follow-on ride, still in progress.
      expect(detector.state.currentRide.single.timestampMs, 240000);
    });
  });

  group('StopDetector short pause', () {
    test(
        'a 2-min pause below the 3-min threshold records no stop and the '
        'points stay in currentRide', () {
      final detector = StopDetector();

      // Ride in.
      for (var i = 0; i < 3; i++) {
        detector.onFix(fix(timestampMs: i * 10000, eastM: i * 100.0));
      }

      // Pause at 300 m for 2 minutes (< 3-minute threshold).
      for (var i = 0; i < 3; i++) {
        detector.onFix(fix(timestampMs: 30000 + i * 60000, eastM: 300.0));
      }

      // Ride away: the candidate cluster is abandoned before maturing.
      for (var i = 0; i < 2; i++) {
        detector.onFix(fix(timestampMs: 160000 + i * 10000, eastM: 400.0 + i * 100.0));
      }

      expect(detector.state.inStop, isFalse);
      expect(detector.state.closedSegments, isEmpty);
      expect(detector.state.currentRide, hasLength(8));
      expect(detector.state.currentRide.last.timestampMs, 170000);
    });
  });

  group('StopDetector lifecycle', () {
    test('reset clears everything', () {
      final detector = StopDetector();

      // Build up a closed ride + open stop so every field holds something.
      for (var i = 0; i < 3; i++) {
        detector.onFix(fix(timestampMs: i * 10000, eastM: i * 100.0));
      }
      for (var i = 0; i < 4; i++) {
        detector.onFix(fix(timestampMs: 30000 + i * 60000, eastM: 300.0));
      }
      expect(detector.state.inStop, isTrue);
      expect(detector.state.closedSegments, isNotEmpty);

      detector.reset();

      expect(detector.state.inStop, isFalse);
      expect(detector.state.currentRide, isEmpty);
      expect(detector.state.closedSegments, isEmpty);

      // And the detector works again from scratch: the next fix starts a
      // fresh ride, with no stale centroid pretending we are still parked.
      detector.onFix(fix(timestampMs: 300000, eastM: 1000.0));
      expect(detector.state.inStop, isFalse);
      expect(detector.state.currentRide, hasLength(1));
      expect(detector.state.currentRide.single.timestampMs, 300000);
    });
  });
}
