import '../models/models.dart';

/// Persistence seam for all app data (IndexedDB on the web).
abstract class StorageService {
  /// Opens the underlying database; must be called before any other method.
  Future<void> init();

  /// All stored vehicles.
  Future<List<Vehicle>> vehicles();

  /// Inserts or updates a vehicle by id.
  Future<void> upsertVehicle(Vehicle vehicle);

  /// Removes the vehicle with the given id.
  Future<void> deleteVehicle(String id);

  /// Inserts or updates a session by id.
  Future<void> saveSession(Session session);

  /// Sessions for a vehicle, newest-first by startedAt.
  ///
  /// When [limit] is given, only the most recent [limit] sessions are
  /// returned.
  Future<List<Session>> sessionsForVehicle(String vehicleId, {int? limit});

  /// Appends a batch of track points to a session's recording.
  Future<void> appendTrackPoints(String sessionId, List<TrackPoint> points);

  /// All track points recorded for a session, in insertion order.
  Future<List<TrackPoint>> trackPoints(String sessionId);

  /// Inserts or updates a day's timeline entry by day.
  Future<void> upsertTimelineEntry(TimelineEntry entry);

  /// Timeline entries stored for [day] (matched at local midnight).
  Future<List<TimelineEntry>> timelineEntriesForDay(DateTime day);

  /// Distinct days that have timeline entries, newest-first.
  Future<List<DateTime>> timelineDays();
}
