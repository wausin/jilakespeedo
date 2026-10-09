import 'package:sembast/sembast.dart';

import '../models/models.dart';
import 'storage_service.dart';

/// Sembast-backed [StorageService].
///
/// The [databaseFactory] is injected: tests pass a memory factory
/// (`newDatabaseFactoryMemory()` from `package:sembast/sembast_memory.dart`)
/// while the app passes a factory with web/IndexedDB storage.
class IdbStorageService implements StorageService {
  IdbStorageService({required DatabaseFactory databaseFactory})
    : _factory = databaseFactory;

  static const String _dbName = 'jilake_speedo.db';
  static const int _dbVersion = 1;

  static const String _trackPointSessionIdKey = 'sessionId';

  final DatabaseFactory _factory;
  final _vehiclesStore = stringMapStoreFactory.store('vehicles');
  final _sessionsStore = stringMapStoreFactory.store('sessions');
  final _trackPointsStore = intMapStoreFactory.store('track_points');
  final _timelineEntriesStore = stringMapStoreFactory.store('timeline_entries');
  final _settingsStore = stringMapStoreFactory.store('settings');

  Database? _db;

  /// The `settings` string store (keyed string map), exposed so settings
  /// controllers can persist small values without a full model.
  StoreRef<String, String> get settingsStore =>
      _settingsStore.cast<String, String>();

  /// The opened database; throws if [init] has not completed.
  Database get database => _database;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('StorageService.init() must be called first');
    }
    return db;
  }

  /// Local-midnight ISO key for a day, stable across write and read.
  String _dayKey(DateTime day) =>
      DateTime(day.year, day.month, day.day).toIso8601String();

  @override
  Future<void> init() async {
    _db ??= await _factory.openDatabase(_dbName, version: _dbVersion);
  }

  /// Decodes one stored row, or null when the row is corrupt (bad shape,
  /// unknown enum name). A single corrupt row must never brick a list read.
  static T? _tryDecode<T>(T Function() decode) {
    try {
      return decode();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Vehicle>> vehicles() async {
    final records = await _vehiclesStore.find(_database);
    return [
      for (final r in records)
        ?_tryDecode(() => Vehicle.fromJson(r.value)),
    ];
  }

  @override
  Future<void> upsertVehicle(Vehicle vehicle) =>
      _vehiclesStore.record(vehicle.id).put(_database, vehicle.toJson());

  @override
  Future<void> deleteVehicle(String id) =>
      _vehiclesStore.record(id).delete(_database);

  @override
  Future<void> saveSession(Session session) =>
      _sessionsStore.record(session.id).put(_database, session.toJson());

  @override
  Future<List<Session>> sessionsForVehicle(
    String vehicleId, {
    int? limit,
  }) async {
    final records = await _sessionsStore.find(
      _database,
      finder: Finder(
        filter: Filter.equals('vehicleId', vehicleId),
        sortOrders: [SortOrder('startedAtMs', false)],
        limit: limit,
      ),
    );
    return [
      for (final r in records)
        ?_tryDecode(() => Session.fromJson(r.value)),
    ];
  }

  @override
  Future<void> appendTrackPoints(
    String sessionId,
    List<TrackPoint> points,
  ) async {
    if (points.isEmpty) return;
    await _database.transaction((txn) {
      return _trackPointsStore.addAll(
        txn,
        points
            .map((p) => {...p.toJson(), _trackPointSessionIdKey: sessionId})
            .toList(),
      );
    });
  }

  @override
  Future<List<TrackPoint>> trackPoints(String sessionId) async {
    final records = await _trackPointsStore.find(
      _database,
      finder: Finder(
        filter: Filter.equals(_trackPointSessionIdKey, sessionId),
        sortOrders: [SortOrder(Field.key)],
      ),
    );
    return [
      for (final r in records)
        ?_tryDecode(() => TrackPoint.fromJson(r.value)),
    ];
  }

  /// Timeline entries are keyed by day at local midnight; non-midnight
  /// days are normalized before storing and matching.
  @override
  Future<void> upsertTimelineEntry(TimelineEntry entry) {
    final dayKey = _dayKey(entry.day);
    return _timelineEntriesStore.record(dayKey).put(_database, {
      ...entry.toJson(),
      'id': dayKey,
      'day': dayKey,
    });
  }

  @override
  Future<List<TimelineEntry>> timelineEntriesForDay(DateTime day) async {
    final records = await _timelineEntriesStore.find(
      _database,
      finder: Finder(filter: Filter.equals('day', _dayKey(day))),
    );
    return [
      for (final r in records)
        ?_tryDecode(() => TimelineEntry.fromJson(r.value)),
    ];
  }

  @override
  Future<List<DateTime>> timelineDays() async {
    final records = await _timelineEntriesStore.find(
      _database,
      finder: Finder(sortOrders: [SortOrder(Field.key, false)]),
    );
    return records
        .map((r) => DateTime.parse(r.value['day'] as String))
        .toList();
  }
}
