/// Vehicle types supported by the app.
enum VehicleType { bike, motorcycle, car }

/// A vehicle profile: id, name, type, gauge max, pinned flag.
class Vehicle {
  String id;
  String name;
  VehicleType type;
  double gaugeMaxKmh;
  bool isPinned;

  static const double defaultGaugeMaxKmh = 240;

  Vehicle({
    required this.id,
    required this.name,
    required this.type,
    double? gaugeMaxKmh,
    bool? isPinned,
  })  : gaugeMaxKmh = gaugeMaxKmh ?? defaultGaugeMaxKmh,
        isPinned = isPinned ?? false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'gaugeMaxKmh': gaugeMaxKmh,
        'isPinned': isPinned,
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        name: json['name'] as String,
        type: VehicleType.values
            .firstWhere((t) => t.name == json['type'] as String),
        gaugeMaxKmh: (json['gaugeMaxKmh'] as num?)?.toDouble(),
        isPinned: json['isPinned'] as bool?,
      );

  Vehicle copyWith({
    String? id,
    String? name,
    VehicleType? type,
    double? gaugeMaxKmh,
    bool? isPinned,
  }) =>
      Vehicle(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        gaugeMaxKmh: gaugeMaxKmh ?? this.gaugeMaxKmh,
        isPinned: isPinned ?? this.isPinned,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vehicle &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.gaugeMaxKmh == gaugeMaxKmh &&
          other.isPinned == isPinned;

  @override
  int get hashCode =>
      Object.hash(id, name, type, gaugeMaxKmh, isPinned);
}
