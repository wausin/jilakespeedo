import 'dart:math' as math;

import 'package:jilake_speedo/core/models/timeline_entry.dart';
import 'package:jilake_speedo/core/models/track_point.dart';
import 'package:jilake_speedo/core/services/location_service.dart';

/// Live segmentation state of the timeline recorder.
///
/// While riding, fixes accumulate in [currentRide]. A run of fixes that
/// stays within [StopDetector.radiusM] of its own centroid (a running mean,
/// so GPS jitter cannot push the boundary away) is a candidate stop: if it
/// endures for [StopDetector.minStopMs] the ride closes and a stop opens
/// ([inStop]); if a fix leaves the radius earlier, the candidate is
/// abandoned and its fixes simply continue the ride. When a fix beyond the
/// radius ends an open stop, the stop is appended to [closedSegments] and
/// the fixes from that departure on begin a new ride in [currentRide] —
/// yielding Google-Timeline-like "went here, stayed N minutes" entries.
class StopDetectorState {
  /// Whether a stop segment is currently open.
  bool inStop;

  /// Fixes of the ride in progress (empty while a stop is open).
  List<TrackPoint> currentRide;

  /// Finished segments, in chronological order. The ride currently in
  /// progress is not here — it is [currentRide] until a stop closes it.
  List<TimelineSegment> closedSegments;

  StopDetectorState({
    required this.inStop,
    required this.currentRide,
    required this.closedSegments,
  });
}

/// Segments a GPS fix stream into ride and stop segments.
///
/// Pure Dart, no platform or Flutter dependencies: the timeline controller
/// feeds it [PositionFix]es from the location service and renders [state].
class StopDetector {
  /// Radius around the stationary centroid that still counts as "stayed".
  final double radiusM;

  /// How long fixes must stay within [radiusM] before a stop opens.
  final int minStopMs;

  static const double _earthRadiusM = 6371000.0;

  final StopDetectorState _state =
      StopDetectorState(inStop: false, currentRide: [], closedSegments: []);

  /// Candidate stop cluster: the fixes currently within [radiusM] of the
  /// centroid below. Null while riding with no stationary run in progress.
  List<TrackPoint>? _cluster;

  /// Running mean of the cluster's latitudes.
  double _centroidLat = 0;

  /// Running mean of the cluster's longitudes.
  double _centroidLng = 0;

  /// Timestamp of the most recent stationary fix; the open stop's end.
  int _stopEndMs = 0;

  StopDetector({this.radiusM = 25, this.minStopMs = 180000});

  StopDetectorState get state => _state;

  /// Folds [fix] into the timeline segmentation.
  void onFix(PositionFix fix) {
    final point = TrackPoint(
      lat: fix.lat,
      lng: fix.lng,
      speedMs: fix.speedMs,
      accuracyM: fix.accuracyM,
      timestampMs: fix.timestampMs,
    );

    if (_state.inStop) {
      if (_withinRadius(fix.lat, fix.lng)) {
        _absorbIntoCluster(point);
        _stopEndMs = point.timestampMs;
      } else {
        _closeStop();
        _state.currentRide.add(point);
        _startCluster(point);
      }
      return;
    }

    final cluster = _cluster;
    if (cluster != null && _withinRadius(fix.lat, fix.lng)) {
      // Stationary: the point extends the candidate cluster, and stays in
      // the ride too for now — if the cluster never matures into a stop,
      // its points are simply ride points.
      _absorbIntoCluster(point);
      _state.currentRide.add(point);
      if (point.timestampMs - cluster.first.timestampMs >= minStopMs) {
        _openStop();
      }
    } else {
      _state.currentRide.add(point);
      _startCluster(point);
    }
  }

  /// Discards all segments and detection state, ready for a new recording.
  void reset() {
    _state.inStop = false;
    _state.currentRide = [];
    _state.closedSegments = [];
    _cluster = null;
    _centroidLat = 0;
    _centroidLng = 0;
    _stopEndMs = 0;
  }

  /// Whether ([lat], [lng]) is within [radiusM] of the current centroid.
  bool _withinRadius(double lat, double lng) =>
      _haversineM(_centroidLat, _centroidLng, lat, lng) <= radiusM;

  /// Folds [point] into the cluster and recenters the running mean.
  void _absorbIntoCluster(TrackPoint point) {
    final cluster = _cluster!;
    _centroidLat =
        (_centroidLat * cluster.length + point.lat) / (cluster.length + 1);
    _centroidLng =
        (_centroidLng * cluster.length + point.lng) / (cluster.length + 1);
    cluster.add(point);
  }

  /// Begins a fresh candidate cluster at [point].
  void _startCluster(TrackPoint point) {
    _cluster = [point];
    _centroidLat = point.lat;
    _centroidLng = point.lng;
  }

  /// Opens the stop: the cluster's fixes (anchor included) are pulled back
  /// out of the ride — the anchor begins the dwell, it is not a ride
  /// point — the remaining pre-stop ride closes, and the cluster becomes
  /// the stop's dwell window.
  void _openStop() {
    final cluster = _cluster!;
    _state.currentRide.removeRange(
        _state.currentRide.length - cluster.length, _state.currentRide.length);
    if (_state.currentRide.isNotEmpty) {
      _state.closedSegments.add(RideSegment(points: _state.currentRide));
    }
    _state.currentRide = [];
    _stopEndMs = cluster.last.timestampMs;
    _state.inStop = true;
  }

  /// Closes the open stop on the fix that left the radius: appends the
  /// [StopSegment]; the fixes from that departure on accumulate in
  /// [StopDetectorState.currentRide] as the next, still-open ride.
  void _closeStop() {
    final cluster = _cluster!;
    _state.closedSegments.add(StopSegment(
      center: TrackPoint(
        lat: _centroidLat,
        lng: _centroidLng,
        speedMs: 0,
        accuracyM: 0,
        timestampMs: cluster.first.timestampMs,
      ),
      startMs: cluster.first.timestampMs,
      endMs: _stopEndMs,
    ));
    _state.inStop = false;
  }

  /// Great-circle distance in meters between two coordinates (spherical earth).
  static double _haversineM(double latA, double lngA, double latB, double lngB) {
    double rad(double deg) => deg * math.pi / 180.0;
    final dLat = rad(latB - latA);
    final dLng = rad(lngB - lngA);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(latA)) *
            math.cos(rad(latB)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadiusM * math.asin(math.sqrt(h));
  }
}
