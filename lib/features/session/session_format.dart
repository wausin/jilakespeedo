import '../../core/models/models.dart';

/// Shared formatting helpers for session/analytics UI.

/// Label for a distance amount in the display unit (`1 km`, `0.5 mi`).
String distanceLabel(double meters, SpeedUnit unit) {
  final value = convertDistance(meters: meters, unit: unit);
  final suffix = unit == SpeedUnit.kmh ? 'km' : 'mi';
  return '${trimZero(value)} $suffix';
}

/// Label for an elapsed duration (`m:ss` under an hour, `h:mm:ss` above).
String elapsedLabel(int ms) {
  final totalSeconds = ms ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Wall-clock elapsed label clamped to 0..[budgetMs].
String elapsedLabelAt(int startFixMs, int nowMs, int budgetMs) {
  final elapsedMs = (nowMs - startFixMs).clamp(0, budgetMs);
  return elapsedLabel(elapsedMs);
}

/// Drops a trailing `.0` from a one-decimal number string.
String trimZero(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
