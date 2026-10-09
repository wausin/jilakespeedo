/// A single GPS position sample recorded during a session or timeline.
class TrackPoint {
  double lat;
  double lng;
  double speedMs;
  double accuracyM;
  int timestampMs;

  TrackPoint({
    required this.lat,
    required this.lng,
    required this.speedMs,
    required this.accuracyM,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'speedMs': speedMs,
        'accuracyM': accuracyM,
        'timestampMs': timestampMs,
      };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        speedMs: (json['speedMs'] as num).toDouble(),
        accuracyM: (json['accuracyM'] as num).toDouble(),
        timestampMs: (json['timestampMs'] as num).toInt(),
      );

  TrackPoint copyWith({
    double? lat,
    double? lng,
    double? speedMs,
    double? accuracyM,
    int? timestampMs,
  }) =>
      TrackPoint(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        speedMs: speedMs ?? this.speedMs,
        accuracyM: accuracyM ?? this.accuracyM,
        timestampMs: timestampMs ?? this.timestampMs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackPoint &&
          other.lat == lat &&
          other.lng == lng &&
          other.speedMs == speedMs &&
          other.accuracyM == accuracyM &&
          other.timestampMs == timestampMs;

  @override
  int get hashCode => Object.hash(lat, lng, speedMs, accuracyM, timestampMs);
}
