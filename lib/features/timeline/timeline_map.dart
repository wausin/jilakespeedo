import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/models.dart';
import '../../core/services/location_service.dart';
import 'map_config.dart';

/// Map for the timeline screen: dark basemap tiles (MapTiler when a key is
/// configured, CARTO fallback), the day's route as a speed-colored polyline,
/// and stop markers with their dwell duration.
///
/// Color ramps blue → red as point speed goes from 30% to 70% of
/// [gaugeMaxMs] (below 30%: pure blue; above 70%: pure red).
class TimelineMap extends StatefulWidget {
  const TimelineMap({
    super.key,
    required this.segments,
    required this.gaugeMaxMs,
    this.currentPosition,
  });

  /// Segments to render (rides as polylines, stops as markers).
  final List<TimelineSegment> segments;

  /// Speed (m/s) that corresponds to the gauge maximum; anchors the color
  /// ramp's 30%/70% thresholds.
  final double gaugeMaxMs;

  /// Latest GPS fix, used to center the map on the user when there is no
  /// recorded route yet. Null until the first fix arrives.
  final PositionFix? currentPosition;

  /// Tile provider/URL/attribution come from [MapConfig] (MapTiler when a key
  /// is injected, CARTO fallback otherwise).
  static String get tileUrl => MapConfig.tileUrl;
  static List<String> get subdomains => MapConfig.subdomains;
  static String get attribution => MapConfig.attribution;

  @override
  State<TimelineMap> createState() => TimelineMapState();
}

class TimelineMapState extends State<TimelineMap> {
  final MapController _mapController = MapController();
  bool _fitPending = false;
  bool _showLoading = true;
  Timer? _loadingTimer;

  /// Wider default zoom so the map is not zoomed uncomfortably close on open.
  static const double _defaultZoom = 12;

  /// True until we have centered on the user's location (or found a route to
  /// fit to) — so the first GPS fix recenters the map on the user.
  bool _awaitingFirstFix = true;

  @override
  void initState() {
    super.initState();
    _fitPending = true;
    // Tiles are fetched fresh on open (the app shell caches the app, not the
    // tiles). Show a "Loading map" hint briefly so a blank dark surface is
    // not mistaken for a broken map; it clears once tiles have had time to
    // arrive (or the offline banner takes over).
    _loadingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showLoading = false);
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TimelineMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments) {
      _fitPending = true;
    }
  }

  /// Route color for [speedMs]: blue at/below 30% of the gauge max, red
  /// at/above 70%, lerped in between.
  static Color speedColor(double speedMs, double gaugeMaxMs) {
    if (gaugeMaxMs <= 0) return Colors.blue;
    final frac = speedMs / gaugeMaxMs;
    final t = ((frac - 0.30) / (0.70 - 0.30)).clamp(0.0, 1.0);
    return Color.lerp(Colors.blue, Colors.red, t)!;
  }

  List<LatLng> _allPoints() {
    final result = <LatLng>[];
    for (final segment in widget.segments) {
      switch (segment) {
        case RideSegment(:final points):
          for (final p in points) {
            result.add(LatLng(p.lat, p.lng));
          }
        case StopSegment(:final center):
          result.add(LatLng(center.lat, center.lng));
      }
    }
    return result;
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];
    for (final segment in widget.segments) {
      if (segment is! RideSegment) continue;
      // Split each ride into per-leg polylines so every leg can be colored
      // by its own speed (a single Polyline has one color).
      final pts = segment.points;
      for (var i = 0; i + 1 < pts.length; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        polylines.add(
          Polyline(
            points: [LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)],
            color: speedColor(b.speedMs, widget.gaugeMaxMs),
            strokeWidth: 4,
          ),
        );
      }
      // Single-point ride: nothing to draw (a leg needs two points).
    }
    return polylines;
  }

  List<Marker> _buildStopMarkers() {
    final markers = <Marker>[];
    for (final segment in widget.segments) {
      if (segment is! StopSegment) continue;
      final minutes = (segment.dwellMs / 60000).round();
      markers.add(
        Marker(
          point: LatLng(segment.center.lat, segment.center.lng),
          width: 96,
          height: 56,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$minutes min',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return markers;
  }

  void _fitBoundsIfPending() {
    if (!_fitPending) return;
    _fitPending = false;
    final points = _allPoints();
    if (points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(points);
    // fitCamera must run after the map has been laid out; deferring to the
    // end of the frame guarantees the FlutterMap widget is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    });
  }

  /// Recenters the map on the user's current location (the "center on me"
  /// button). No-op when no fix is available yet.
  void centerOnCurrent() {
    final fix = widget.currentPosition;
    if (fix == null) return;
    _mapController.move(LatLng(fix.lat, fix.lng), 15);
  }

  /// Centers on the user's location the first time a fix arrives, if there is
  /// no recorded route to fit to.
  void _centerOnLocationIfPending() {
    if (!_awaitingFirstFix) return;
    if (_allPoints().isNotEmpty) {
      _awaitingFirstFix = false;
      return;
    }
    final fix = widget.currentPosition;
    if (fix == null) return;
    _awaitingFirstFix = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(LatLng(fix.lat, fix.lng), _defaultZoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    _fitBoundsIfPending();
    _centerOnLocationIfPending();
    final points = _allPoints();
    final initialCenter = points.isNotEmpty
        ? points.first
        : (widget.currentPosition != null
            ? LatLng(widget.currentPosition!.lat, widget.currentPosition!.lng)
            : const LatLng(0, 0));

    // Dark container: if tiles fail to load (offline, provider hiccup), the
    // surface stays dark instead of flashing a naked white screen.
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0E0E10)),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _defaultZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: TimelineMap.tileUrl,
                subdomains: TimelineMap.subdomains,
                userAgentPackageName: 'com.jilake.speedo',
              ),
              PolylineLayer(polylines: _buildPolylines()),
              MarkerLayer(markers: _buildStopMarkers()),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(TimelineMap.attribution),
                ],
              ),
            ],
          ),
          if (_showLoading)
            const Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: _LoadingMapPill(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small "Loading map…" hint shown while tiles may still be arriving.
class _LoadingMapPill extends StatelessWidget {
  const _LoadingMapPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Loading map…',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
