import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';

void main() {
  group('Vehicle', () {
    test('default vehicle gaugeMaxKmh is 240', () {
      final vehicle = Vehicle(
        id: 'v1',
        name: 'My Ride',
        type: VehicleType.motorcycle,
      );
      expect(vehicle.gaugeMaxKmh, 240);
    });

    test('fromJson/toJson round-trips', () {
      final vehicle = Vehicle(
        id: 'v1',
        name: 'My Ride',
        type: VehicleType.motorcycle,
        gaugeMaxKmh: 300,
        isPinned: true,
      );
      final restored = Vehicle.fromJson(vehicle.toJson());
      expect(restored, vehicle);
    });

    test('copyWith changes only the given fields', () {
      final vehicle = Vehicle(
        id: 'v1',
        name: 'My Ride',
        type: VehicleType.motorcycle,
      );
      final renamed = vehicle.copyWith(name: 'Track Toy');
      expect(renamed.name, 'Track Toy');
      expect(renamed.id, vehicle.id);
      expect(renamed.type, vehicle.type);
      expect(renamed.gaugeMaxKmh, vehicle.gaugeMaxKmh);
      expect(renamed.isPinned, vehicle.isPinned);
    });
  });
}
