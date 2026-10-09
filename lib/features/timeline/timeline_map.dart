import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/models.dart';

/// Map for the timeline screen: CARTO dark tiles, the day's route as a
/// speed-colored polyline, and stop markers with their dwell duration.
///
/// Color ramps blue → red as point speed goes from 30% to 70% of
/// [gaugeMaxMs] (below 30%: pure blue; above 70%: pure red).
class TimelineMap extends StatefulWidget {
  const TimelineMap({
    super.key,
    required this.segments,
    required this.gaugeMaxMs,
  });

  /// Segments to render (rides as polylines, stops as markers).
  final List<TimelineSegment> segments;

  /// Speed (m/s) that corresponds to the gauge maximum; anchors the color
  /// ramp's 30%/70% thresholds.
  final double gaugeMaxMs;

  /// Tile URL template, subdomains, and attribution per the plan's Global
  /// Constraints (verbatim).
  static const String tileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const List<String> subdomains = ['a', 'b', 'c', 'd'];
  static const String attribution =
      '© OpenStreetMap contributors © CARTO';

  @override
  State<TimelineMap> createState() => _TimelineMapState();
}

class _TimelineMapState extends State<TimelineMap> {
  final MapController _mapController = MapController();
  bool _fitPending = false;

  @override
  void initState() {
    super.initState();
    _fitPending = true;
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

  @override
  Widget build(BuildContext context) {
    _fitBoundsIfPending();
    final points = _allPoints();
    final initialCenter =
        points.isEmpty ? const LatLng(0, 0) : points.first;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: TimelineMap.tileUrl,
          subdomains: TimelineMap.subdomains,
          userAgentPackageName: 'com.jilake.speedo',
        ),
        PolylineLayer(polylines: _buildPolylines()),
        MarkerLayer(markers: _buildStopMarkers()),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution(TimelineMap.attribution),
          ],
        ),
      ],
    );
  }
}
