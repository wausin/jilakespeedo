import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';

void main() {
  group('TrackPoint', () {
    test('fromJson/toJson round-trips', () {
      final point = TrackPoint(
        lat: 45.5,
        lng: -122.6,
        speedMs: 12.5,
        accuracyM: 8.0,
        timestampMs: 1700000000000,
      );
      final restored = TrackPoint.fromJson(point.toJson());
      expect(restored, point);
    });

    test('copyWith changes only the given fields', () {
      final point = TrackPoint(
        lat: 45.5,
        lng: -122.6,
        speedMs: 12.5,
        accuracyM: 8.0,
        timestampMs: 1700000000000,
      );
      final faster = point.copyWith(speedMs: 30.0);
      expect(faster.speedMs, 30.0);
      expect(faster.lat, point.lat);
      expect(faster.lng, point.lng);
      expect(faster.accuracyM, point.accuracyM);
      expect(faster.timestampMs, point.timestampMs);
    });
  });
}
