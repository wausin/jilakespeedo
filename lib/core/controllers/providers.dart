import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import '../services/connectivity_service.dart';
import '../services/idb_storage_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';

/// Database factory used by the app's [StorageService].
///
/// Defined as its own provider so `main.dart` can supply the web/IndexedDB
/// factory while tests can substitute an in-memory one.
final databaseFactoryProvider = Provider<DatabaseFactory>(
  (_) => throw UnimplementedError(
    'databaseFactoryProvider must be overridden (see main.dart)',
  ),
);

/// App-wide [StorageService]. Override with an initialized instance in tests.
final storageServiceProvider = Provider<StorageService>(
  (_) => throw UnimplementedError(
    'storageServiceProvider must be overridden (see main.dart)',
  ),
);

/// App-wide [LocationService].
///
/// `main.dart` overrides this with a [WebLocationService] (which imports
/// dart:js_interop and therefore cannot be referenced from VM tests);
/// tests override it with a fake.
final locationServiceProvider = Provider<LocationService>(
  (_) => throw UnimplementedError(
    'locationServiceProvider must be overridden (see main.dart)',
  ),
);

/// Broadcast stream of [LocationStatus] changes from the location service.
final locationStatusProvider = StreamProvider<LocationStatus>(
  (ref) => ref.watch(locationServiceProvider).statusStream,
);

/// Ref-counted wakelock so session and timeline can hold concurrently.
class WakeLockService {
  int _count = 0;

  /// Acquires a hold on the wakelock; enables it on the first hold.
  Future<void> hold() async {
    _count++;
    if (_count == 1) {
      await WakelockPlus.enable();
    }
  }

  /// Releases a hold; disables the wakelock when the last hold is released.
  Future<void> release() async {
    if (_count == 0) return;
    _count--;
    if (_count == 0) {
      await WakelockPlus.disable();
    }
  }
}

final wakeLockServiceProvider = Provider<WakeLockService>(
  (_) => WakeLockService(),
);

/// App-wide [ConnectivityService] (browser online/offline). `main.dart`
/// overrides with [WebConnectivityService]; tests override with a fake.
final connectivityServiceProvider = Provider<ConnectivityService>(
  (_) => throw UnimplementedError(
    'connectivityServiceProvider must be overridden (see main.dart)',
  ),
);

/// User settings state (display units, ...).
class SettingsState {
  final SpeedUnit unit;

  const SettingsState({this.unit = SpeedUnit.kmh});

  SettingsState copyWith({SpeedUnit? unit}) =>
      SettingsState(unit: unit ?? this.unit);
}

/// Loads and persists [SettingsState] via the [StorageService] settings
/// store (keyed string map).
class SettingsController extends StateNotifier<SettingsState> {
  static const String _unitKey = 'unit';

  final StoreRef<String, String> _settingsStore;
  final Database _database;

  SettingsController(this._settingsStore, this._database)
    : super(const SettingsState()) {
    unawaited(_load());
  }

  Future<void> _load() async {
    final stored = await _settingsStore.record(_unitKey).get(_database);
    if (stored == SpeedUnit.mph.name) {
      state = SettingsState(unit: SpeedUnit.mph);
    }
  }

  /// Switches the display unit and persists the choice.
  Future<void> setUnit(SpeedUnit unit) async {
    state = SettingsState(unit: unit);
    await _settingsStore.record(_unitKey).put(_database, unit.name);
  }
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
      final storage = ref.watch(storageServiceProvider);
      final idb = storage as IdbStorageService;
      return SettingsController(idb.settingsStore, idb.database);
    });

/// Vehicles state: the list plus the active vehicle id.
class VehiclesState {
  final List<Vehicle> vehicles;
  final String? activeVehicleId;

  const VehiclesState({this.vehicles = const [], this.activeVehicleId});

  Vehicle? get activeVehicle {
    final id = activeVehicleId;
    if (id == null) return null;
    for (final vehicle in vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return null;
  }

  VehiclesState copyWith({
    List<Vehicle>? vehicles,
    String? Function()? activeVehicleId,
  }) => VehiclesState(
    vehicles: vehicles ?? this.vehicles,
    activeVehicleId: activeVehicleId != null
        ? activeVehicleId()
        : this.activeVehicleId,
  );
}

/// Loads vehicles at init, creates the default vehicle on first run, and
/// keeps [StorageService] in sync on every mutation.
class VehiclesController extends StateNotifier<VehiclesState> {
  /// At most this many vehicles may be pinned (shown in the switcher).
  static const int maxPinned = 3;

  final StorageService _storage;

  VehiclesController(this._storage) : super(const VehiclesState()) {
    unawaited(_load());
  }

  Future<void> _load() async {
    var vehicles = await _storage.vehicles();
    if (vehicles.isEmpty) {
      final defaultVehicle = Vehicle(
        id: 'default',
        name: 'My Ride',
        type: VehicleType.motorcycle,
        gaugeMaxKmh: 240,
        isPinned: true,
      );
      await _storage.upsertVehicle(defaultVehicle);
      vehicles = [defaultVehicle];
    }
    String? activeId;
    for (final vehicle in vehicles) {
      if (vehicle.isPinned) {
        activeId = vehicle.id;
        break;
      }
    }
    activeId ??= vehicles.first.id;
    state = VehiclesState(vehicles: vehicles, activeVehicleId: activeId);
  }

  /// Marks [id] as the active vehicle.
  void setActive(String id) {
    state = state.copyWith(activeVehicleId: () => id);
  }

  /// Inserts or updates [vehicle].
  Future<void> upsert(Vehicle vehicle) async {
    await _storage.upsertVehicle(vehicle);
    final vehicles = [...state.vehicles];
    final index = vehicles.indexWhere((v) => v.id == vehicle.id);
    if (index >= 0) {
      vehicles[index] = vehicle;
    } else {
      vehicles.add(vehicle);
    }
    state = state.copyWith(
      vehicles: vehicles,
      activeVehicleId: () => state.activeVehicleId ?? vehicle.id,
    );
  }

  /// Removes the vehicle with [id].
  ///
  /// When the deleted vehicle was active, the first remaining vehicle (if
  /// any) becomes active.
  Future<void> delete(String id) async {
    await _storage.deleteVehicle(id);
    final vehicles = state.vehicles.where((v) => v.id != id).toList();
    String? activeId = state.activeVehicleId;
    if (activeId == id) {
      activeId = vehicles.isEmpty ? null : vehicles.first.id;
    }
    state = state.copyWith(
      vehicles: vehicles,
      activeVehicleId: () => activeId,
    );
  }

  /// Sets or clears the pinned flag on the vehicle with [id].
  ///
  /// At most [maxPinned] vehicles may be pinned; pinning another one
  /// unpins the oldest pinned (first in list order).
  Future<void> pin(String id, {required bool pinned}) async {
    final vehicle = state.vehicles.where((v) => v.id == id).firstOrNull;
    if (vehicle == null) return;
    if (pinned && !vehicle.isPinned) {
      final pinnedVehicles =
          state.vehicles.where((v) => v.isPinned).toList();
      if (pinnedVehicles.length >= maxPinned) {
        await upsert(pinnedVehicles.first.copyWith(isPinned: false));
      }
    }
    await upsert(vehicle.copyWith(isPinned: pinned));
  }
}

final vehiclesProvider = StateNotifierProvider<VehiclesController, VehiclesState>(
  (ref) => VehiclesController(ref.watch(storageServiceProvider)),
);
