/// Exponential smoothing of GPS speed samples.
///
/// Damps single-sample GPS speed spikes so the displayed and recorded speed
/// stays stable. Output is clamped to [0, 75] m/s (75 m/s = 270 km/h).
class SpeedSmoother {
  static const double alpha = 0.4;
  static const double maxOutputMs = 75.0;

  double? _smoothed;

  /// Folds [newMs] into the moving average and returns the smoothed value.
  ///
  /// The first sample is returned as-is (no history to average with).
  double smooth(double newMs, int timestampMs) {
    if (_smoothed == null) {
      _smoothed = _clamp(newMs);
      return _smoothed!;
    }
    _smoothed = _clamp(alpha * newMs + (1 - alpha) * _smoothed!);
    return _smoothed!;
  }

  /// Forgets all history so the next sample is returned as-is again.
  void reset() => _smoothed = null;

  static double _clamp(double v) => v.clamp(0.0, maxOutputMs);
}
