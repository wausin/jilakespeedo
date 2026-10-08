import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/services/speed_smoother.dart';

void main() {
  group('SpeedSmoother', () {
    test('first sample returns as-is', () {
      final smoother = SpeedSmoother();
      expect(smoother.smooth(10.0, 1000), 10.0);
    });

    test('damps a single 40 m/s spike between zeros', () {
      final smoother = SpeedSmoother();
      final outputs = <double>[];
      for (final (speed, ts) in [
        (0.0, 1000),
        (0.0, 2000),
        (40.0, 3000),
        (0.0, 4000),
        (0.0, 5000),
      ]) {
        outputs.add(smoother.smooth(speed, ts));
      }
      expect(outputs.reduce((a, b) => a > b ? a : b), lessThan(40.0));
    });

    test('steady 10 m/s converges to ~10 within 5 samples', () {
      final smoother = SpeedSmoother();
      smoother.smooth(0.0, 1000);
      double last = 0;
      for (var i = 0; i < 5; i++) {
        last = smoother.smooth(10.0, 2000 + i * 1000);
      }
      expect(last, closeTo(10.0, 1.0));
    });

    test('clamps output to [0, 75] m/s', () {
      final smoother = SpeedSmoother();
      smoother.smooth(60.0, 1000);
      final spiked = smoother.smooth(300.0, 2000);
      expect(spiked, lessThanOrEqualTo(75.0));
      expect(spiked, greaterThanOrEqualTo(0.0));
    });
  });
}
