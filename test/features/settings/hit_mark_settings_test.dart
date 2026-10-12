import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/models/models.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late IdbStorageService storage;

  setUp(() async {
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('hit-mark defaults to 100 km/h', () {
    final container = makeContainer();
    expect(container.read(settingsControllerProvider).hitMarkKmh, 100);
  });

  test('setHitMark persists and clamps', () async {
    final container = makeContainer();
    final notifier = container.read(settingsControllerProvider.notifier);

    await notifier.setHitMark(150);
    expect(container.read(settingsControllerProvider).hitMarkKmh, 150);

    // Below the floor clamps to 10.
    await notifier.setHitMark(2);
    expect(container.read(settingsControllerProvider).hitMarkKmh, 10);

    // Above the ceiling clamps to 400.
    await notifier.setHitMark(9999);
    expect(container.read(settingsControllerProvider).hitMarkKmh, 400);
  });

  test('changing the unit keeps the hit-mark value', () async {
    final container = makeContainer();
    final notifier = container.read(settingsControllerProvider.notifier);
    await notifier.setHitMark(120);
    await notifier.setUnit(SpeedUnit.mph);
    final s = container.read(settingsControllerProvider);
    expect(s.unit, SpeedUnit.mph);
    expect(s.hitMarkKmh, 120); // stored in km/h regardless of display unit
  });
}
