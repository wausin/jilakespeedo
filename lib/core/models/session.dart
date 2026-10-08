/// A session target: distance (meters) or duration (minutes).
sealed class SessionTarget {
  const SessionTarget();

  Map<String, dynamic> toJson();

  factory SessionTarget.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    switch (kind) {
      case 'distance':
        return DistanceTarget((json['meters'] as num).toDouble());
      case 'duration':
        return DurationTarget((json['minutes'] as num).toInt());
      default:
        throw FormatException('Unknown session target kind: $kind');
    }
  }

  /// Creates a distance target in meters.
  factory SessionTarget.distance(double meters) = DistanceTarget;

  /// Creates a duration target in minutes.
  factory SessionTarget.duration(int minutes) = DurationTarget;
}

/// Target: cover a total distance (meters).
class DistanceTarget extends SessionTarget {
  final double meters;

  const DistanceTarget(this.meters);

  @override
  Map<String, dynamic> toJson() => {'kind': 'distance', 'meters': meters};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DistanceTarget && other.meters == meters;

  @override
  int get hashCode => Object.hash('distance', meters);
}

/// Target: ride for a total duration (minutes).
class DurationTarget extends SessionTarget {
  final int minutes;

  const DurationTarget(this.minutes);

  @override
  Map<String, dynamic> toJson() => {'kind': 'duration', 'minutes': minutes};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DurationTarget && other.minutes == minutes;

  @override
  int get hashCode => Object.hash('duration', minutes);
}

/// Summary stats for a completed (or in-progress) session.
class SessionSummary {
  double topSpeedMs;
  double avgSpeedMs;
  double distanceM;
  int elapsedMs;

  SessionSummary({
    required this.topSpeedMs,
    required this.avgSpeedMs,
    required this.distanceM,
    required this.elapsedMs,
  });

  Map<String, dynamic> toJson() => {
        'topSpeedMs': topSpeedMs,
        'avgSpeedMs': avgSpeedMs,
        'distanceM': distanceM,
        'elapsedMs': elapsedMs,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> json) =>
      SessionSummary(
        topSpeedMs: (json['topSpeedMs'] as num).toDouble(),
        avgSpeedMs: (json['avgSpeedMs'] as num).toDouble(),
        distanceM: (json['distanceM'] as num).toDouble(),
        elapsedMs: (json['elapsedMs'] as num).toInt(),
      );

  SessionSummary copyWith({
    double? topSpeedMs,
    double? avgSpeedMs,
    double? distanceM,
    int? elapsedMs,
  }) =>
      SessionSummary(
        topSpeedMs: topSpeedMs ?? this.topSpeedMs,
        avgSpeedMs: avgSpeedMs ?? this.avgSpeedMs,
        distanceM: distanceM ?? this.distanceM,
        elapsedMs: elapsedMs ?? this.elapsedMs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionSummary &&
          other.topSpeedMs == topSpeedMs &&
          other.avgSpeedMs == avgSpeedMs &&
          other.distanceM == distanceM &&
          other.elapsedMs == elapsedMs;

  @override
  int get hashCode => Object.hash(topSpeedMs, avgSpeedMs, distanceM, elapsedMs);
}

/// Status of a session.
enum SessionStatus { running, completed, stopped }

/// A recorded session with its target and summary.
class Session {
  String id;
  String vehicleId;
  SessionTarget target;
  int startedAtMs;
  int? endedAtMs;
  SessionStatus status;
  SessionSummary? summary;

  Session({
    required this.id,
    required this.vehicleId,
    required this.target,
    required this.startedAtMs,
    this.endedAtMs,
    this.status = SessionStatus.running,
    this.summary,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'target': target.toJson(),
        'startedAtMs': startedAtMs,
        'endedAtMs': endedAtMs,
        'status': status.name,
        'summary': summary?.toJson(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        vehicleId: json['vehicleId'] as String,
        target: SessionTarget.fromJson(json['target'] as Map<String, dynamic>),
        startedAtMs: (json['startedAtMs'] as num).toInt(),
        endedAtMs: (json['endedAtMs'] as num?)?.toInt(),
        status: SessionStatus.values.firstWhere(
          (s) => s.name == json['status'] as String,
          orElse: () =>
              throw FormatException('unknown session status: ${json['status']}'),
        ),
        summary: json['summary'] == null
            ? null
            : SessionSummary.fromJson(json['summary'] as Map<String, dynamic>),
      );

  Session copyWith({
    String? id,
    String? vehicleId,
    SessionTarget? target,
    int? startedAtMs,
    int? endedAtMs,
    SessionStatus? status,
    SessionSummary? summary,
  }) =>
      Session(
        id: id ?? this.id,
        vehicleId: vehicleId ?? this.vehicleId,
        target: target ?? this.target,
        startedAtMs: startedAtMs ?? this.startedAtMs,
        endedAtMs: endedAtMs ?? this.endedAtMs,
        status: status ?? this.status,
        summary: summary ?? this.summary,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          other.id == id &&
          other.vehicleId == vehicleId &&
          other.target == target &&
          other.startedAtMs == startedAtMs &&
          other.endedAtMs == endedAtMs &&
          other.status == status &&
          other.summary == summary;

  @override
  int get hashCode => Object.hash(
      id, vehicleId, target, startedAtMs, endedAtMs, status, summary);
}
