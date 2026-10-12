import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import '../services/connectivity_service.dart';
import '../services/idb_storage_service.dart';
import '../services/location_service.dart';
import '../services/sound_service.dart';
import '../services/sound_service_stub.dart'
    if (dart.library.js_interop) '../services/sound_service_web.dart';
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

/// The latest accepted position fix, or null until the first one arrives.
///
/// Used by the timeline map to center on the user's real location (instead of
/// a hardcoded point) and by the "center on me" button.
final currentPositionProvider = StreamProvider<PositionFix?>((ref) {
  return ref
      .watch(locationServiceProvider)
      .watch()
      .map<PositionFix?>((fix) => fix);
});

/// Sessions for a vehicle, newest first. Keyed by vehicle id; invalidate
/// (via [refreshSessions]) after a session finishes so Analytics reloads.
final sessionsForVehicleProvider =
    FutureProvider.family<List<Session>, String>((ref, vehicleId) async {
  return ref.watch(storageServiceProvider).sessionsForVehicle(vehicleId);
});

/// Ref-counted wakelock so session and timeline can hold concurrently.
class WakeLockService {
  int _count = 0;

  /// Acquires a hold on the wakelock; enables it on the first hold.
  ///
  /// Best-effort: a browser without the Screen Wake Lock API (or a denied
  /// request) must never throw into the caller — the app still works, the
  /// screen just may dim.
  Future<void> hold() async {
    _count++;
    if (_count == 1) {
      try {
        await WakelockPlus.enable();
      } catch (_) {
        // Unsupported or denied — ignore.
      }
    }
  }

  /// Releases a hold; disables the wakelock when the last hold is released.
  Future<void> release() async {
    if (_count == 0) return;
    _count--;
    if (_count == 0) {
      try {
        await WakelockPlus.disable();
      } catch (_) {
        // Unsupported — ignore.
      }
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

/// App-wide [SoundService] for the hit-mark sound. Web plays real audio;
/// tests/VM use a no-op stub.
final soundServiceProvider = Provider<SoundService>(
  (_) => createSoundService(),
);

/// Increments each time the hit-mark speed is crossed (rising edge), so the
/// speedo screen can run its celebration animation. Mono-detail: kept as a
/// counter so repeated triggers are observable.
final hitMarkTriggerProvider = StateProvider<int>((_) => 0);

/// User settings state (display units, hit-mark speed, ...).
class SettingsState {
  final SpeedUnit unit;

  /// Speed (km/h) at which the hit-mark celebration triggers on the speedo.
  /// Always stored in km/h; displayed in the current unit.
  final double hitMarkKmh;

  const SettingsState({this.unit = SpeedUnit.kmh, this.hitMarkKmh = 100});

  SettingsState copyWith({SpeedUnit? unit, double? hitMarkKmh}) =>
      SettingsState(
        unit: unit ?? this.unit,
        hitMarkKmh: hitMarkKmh ?? this.hitMarkKmh,
      );
}

/// Loads and persists [SettingsState] via the [StorageService] settings
/// store (keyed string map).
class SettingsController extends StateNotifier<SettingsState> {
  static const String _unitKey = 'unit';
  static const String _hitMarkKey = 'hitMarkKmh';

  final StoreRef<String, String> _settingsStore;
  final Database _database;

  /// Set once _load has finished; further sets are not clobbered by a late
  /// load completing after a user change.
  bool _loaded = false;

  SettingsController(this._settingsStore, this._database)
    : super(const SettingsState()) {
    unawaited(_load());
  }

  Future<void> _load() async {
    final storedUnit = await _settingsStore.record(_unitKey).get(_database);
    final storedHitMark =
        await _settingsStore.record(_hitMarkKey).get(_database);
    if (_loaded || !mounted) return; // user change or disposed; don't clobber
    _loaded = true;
    state = SettingsState(
      unit: storedUnit == SpeedUnit.mph.name ? SpeedUnit.mph : SpeedUnit.kmh,
      hitMarkKmh: double.tryParse(storedHitMark ?? '') ?? 100,
    );
  }

  /// Switches the display unit and persists the choice.
  Future<void> setUnit(SpeedUnit unit) async {
    _loaded = true;
    state = state.copyWith(unit: unit);
    await _settingsStore.record(_unitKey).put(_database, unit.name);
  }

  /// Sets the hit-mark speed (km/h) and persists it.
  Future<void> setHitMark(double kmh) async {
    _loaded = true;
    final clamped = kmh.clamp(10.0, 400.0);
    state = state.copyWith(hitMarkKmh: clamped);
    await _settingsStore
        .record(_hitMarkKey)
        .put(_database, clamped.toStringAsFixed(0));
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
