import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';

void main() {
  group('convertSpeed', () {
    test('1 m/s to km/h is 3.6', () {
      expect(
        convertSpeed(ms: 1, unit: SpeedUnit.kmh),
        3.6,
      );
    });

    test('1 m/s to mph is 2.236936 (approx)', () {
      expect(
        convertSpeed(ms: 1, unit: SpeedUnit.mph),
        closeTo(2.236936, 1e-6),
      );
    });
  });

  group('convertDistance', () {
    test('1000 m in kmh unit is 1.0 km', () {
      expect(
        convertDistance(meters: 1000, unit: SpeedUnit.kmh),
        1.0,
      );
    });
  });

  group('unitLabel', () {
    test('mph label is mph', () {
      expect(unitLabel(SpeedUnit.mph), 'mph');
    });

    test('kmh label is km/h', () {
      expect(unitLabel(SpeedUnit.kmh), 'km/h');
    });
  });
}
