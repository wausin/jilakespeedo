import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';

TrackPoint _point(int ts) => TrackPoint(
      lat: 45.5,
      lng: -122.6,
      speedMs: 10.0,
      accuracyM: 8.0,
      timestampMs: ts,
    );

void main() {
  group('TimelineSegment', () {
    test('RideSegment fromJson/toJson round-trips', () {
      final segment = RideSegment(points: [_point(1000), _point(2000)]);
      final restored = RideSegment.fromJson(segment.toJson());
      expect(restored, segment);
    });

    test('StopSegment fromJson/toJson round-trips', () {
      final segment = StopSegment(
        center: _point(1000),
        startMs: 1000,
        endMs: 181000,
      );
      final restored = StopSegment.fromJson(segment.toJson());
      expect(restored, segment);
    });

    test('StopSegment dwellMs is endMs - startMs', () {
      final segment = StopSegment(
        center: _point(1000),
        startMs: 1000,
        endMs: 181000,
      );
      expect(segment.dwellMs, 180000);
    });
  });

  group('TimelineEntry', () {
    test('fromJson/toJson round-trips ride and stop segments', () {
      final entry = TimelineEntry(
        day: DateTime(2026, 10, 8),
        segments: [
          RideSegment(points: [_point(1000), _point(2000)]),
          StopSegment(center: _point(2000), startMs: 2000, endMs: 60000),
        ],
      );
      final restored = TimelineEntry.fromJson(entry.toJson());
      expect(restored, entry);
      expect(restored.segments[0], isA<RideSegment>());
      expect(restored.segments[1], isA<StopSegment>());
    });
  });
}
