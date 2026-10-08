import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/models/models.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/features/settings/vehicle_manager_screen.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/src/cooperator.dart' as sembast_cooperator;

void main() {
  late IdbStorageService storage;

  setUpAll(() {
    // Sembast's cooperator pauses with Future.delayed after 4 ms of real
    // work; inside the widget-test fake-async zone that timer would stay
    // pending and fail the binding invariant. Disable it for these tests.
    sembast_cooperator.disableSembastCooperator();
  });

  setUp(() async {
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  Future<void> seedVehicles(List<Vehicle> vehicles) async {
    for (final vehicle in vehicles) {
      await storage.upsertVehicle(vehicle);
    }
  }

  Future<ProviderContainer> pumpManager(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: VehicleManagerScreen()),
      ),
    );
    // Let VehiclesController._load() complete.
    await tester.pump();
    return container;
  }

  testWidgets('pin limit: pinning a 4th vehicle unpins the oldest pinned',
      (tester) async {
    await seedVehicles([
      Vehicle(id: 'a', name: 'Alpha', type: VehicleType.bike, isPinned: true),
      Vehicle(
        id: 'b',
        name: 'Bravo',
        type: VehicleType.motorcycle,
        isPinned: true,
      ),
      Vehicle(id: 'c', name: 'Charlie', type: VehicleType.car, isPinned: true),
      Vehicle(id: 'd', name: 'Delta', type: VehicleType.bike),
    ]);
    final container = await pumpManager(tester);

    // Pin Delta (the 4th) via its pin toggle.
    await tester.tap(find.byKey(VehicleManagerScreen.pinKeyFor('d')));
    await tester.pump();

    final vehicles = container.read(vehiclesProvider).vehicles;
    bool pinned(String id) => vehicles.firstWhere((v) => v.id == id).isPinned;

    expect(pinned('d'), isTrue, reason: 'newly pinned vehicle stays pinned');
    expect(
      pinned('a'),
      isFalse,
      reason: 'oldest pinned vehicle is unpinned to respect the limit',
    );
    expect(pinned('b'), isTrue);
    expect(pinned('c'), isTrue);

    // The unpin persisted to storage as well.
    final stored = await storage.vehicles();
    expect(stored.firstWhere((v) => v.id == 'a').isPinned, isFalse);
    expect(stored.firstWhere((v) => v.id == 'd').isPinned, isTrue);
  });

  testWidgets('delete active vehicle falls back to first remaining',
      (tester) async {
    await seedVehicles([
      Vehicle(id: 'a', name: 'Alpha', type: VehicleType.bike),
      Vehicle(id: 'b', name: 'Bravo', type: VehicleType.car),
      Vehicle(id: 'c', name: 'Charlie', type: VehicleType.motorcycle),
    ]);
    final container = await pumpManager(tester);

    // Make Charlie active, then delete it (confirm the dialog).
    container.read(vehiclesProvider.notifier).setActive('c');
    await tester.tap(find.byKey(VehicleManagerScreen.deleteKeyFor('c')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete vehicle?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(vehiclesProvider);
    expect(state.vehicles.map((v) => v.id), ['a', 'b']);
    expect(
      state.activeVehicleId,
      'a',
      reason: 'active falls back to the first remaining vehicle',
    );

    // The deletion persisted to storage as well.
    final stored = await storage.vehicles();
    expect(stored.map((v) => v.id), isNot(contains('c')));
  });
}
