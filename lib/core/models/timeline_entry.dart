import 'track_point.dart';

/// A segment of a recorded timeline: either a ride (polyline) or a stop.
sealed class TimelineSegment {
  const TimelineSegment();

  Map<String, dynamic> toJson();
}

/// A ride segment: an ordered list of track points forming a polyline.
class RideSegment extends TimelineSegment {
  final List<TrackPoint> points;

  const RideSegment({required this.points});

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'ride',
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory RideSegment.fromJson(Map<String, dynamic> json) => RideSegment(
        points: (json['points'] as List)
            .map((p) => TrackPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  RideSegment copyWith({List<TrackPoint>? points}) =>
      RideSegment(points: points ?? this.points);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideSegment && listEquals(other.points, points);

  @override
  int get hashCode => Object.hashAll(points);
}

/// A stop segment: where the user stayed for a dwell duration.
class StopSegment extends TimelineSegment {
  final TrackPoint center;
  final int startMs;
  final int endMs;

  const StopSegment({
    required this.center,
    required this.startMs,
    required this.endMs,
  });

  int get dwellMs => endMs - startMs;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'stop',
        'center': center.toJson(),
        'startMs': startMs,
        'endMs': endMs,
      };

  factory StopSegment.fromJson(Map<String, dynamic> json) => StopSegment(
        center: TrackPoint.fromJson(json['center'] as Map<String, dynamic>),
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
      );

  StopSegment copyWith({
    TrackPoint? center,
    int? startMs,
    int? endMs,
  }) =>
      StopSegment(
        center: center ?? this.center,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StopSegment &&
          other.center == center &&
          other.startMs == startMs &&
          other.endMs == endMs;

  @override
  int get hashCode => Object.hash(center, startMs, endMs);
}

/// A day's timeline: ordered segments (rides and stops).
class TimelineEntry {
  /// Day this entry belongs to (midnight local time).
  final DateTime day;

  /// Ordered segments for the day.
  final List<TimelineSegment> segments;

  const TimelineEntry({required this.day, required this.segments});

  Map<String, dynamic> toJson() => {
        'id': day.toIso8601String(),
        'day': day.toIso8601String(),
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    final segments = <TimelineSegment>[];
    for (final raw in json['segments'] as List) {
      final map = raw as Map<String, dynamic>;
      final kind = map['kind'] as String;
      switch (kind) {
        case 'ride':
          segments.add(RideSegment.fromJson(map));
        case 'stop':
          segments.add(StopSegment.fromJson(map));
        default:
          throw FormatException('Unknown segment kind: $kind');
      }
    }
    return TimelineEntry(
      day: DateTime.parse(json['day'] as String),
      segments: segments,
    );
  }

  TimelineEntry copyWith({
    DateTime? day,
    List<TimelineSegment>? segments,
  }) =>
      TimelineEntry(
        day: day ?? this.day,
        segments: segments ?? this.segments,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineEntry &&
          other.day == day &&
          listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(day, Object.hashAll(segments));
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
