import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/timeline/timeline_map.dart';

void main() {
  final segments = <TimelineSegment>[
    RideSegment(
      points: [
        TrackPoint(
          lat: 0.0,
          lng: 0.0,
          speedMs: 5.0,
          accuracyM: 10.0,
          timestampMs: 0,
        ),
        TrackPoint(
          lat: 0.001,
          lng: 0.001,
          speedMs: 20.0,
          accuracyM: 10.0,
          timestampMs: 10000,
        ),
        TrackPoint(
          lat: 0.002,
          lng: 0.002,
          speedMs: 40.0,
          accuracyM: 10.0,
          timestampMs: 20000,
        ),
      ],
    ),
    StopSegment(
      center: TrackPoint(
        lat: 0.002,
        lng: 0.002,
        speedMs: 0.0,
        accuracyM: 0.0,
        timestampMs: 20000,
      ),
      startMs: 20000,
      endMs: 20000 + 12 * 60000,
    ),
  ];

  testWidgets('builds with a fixed segment list, polyline layer and '
      'attribution present, stop marker shows dwell label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineMap(segments: segments, gaugeMaxMs: 30),
        ),
      ),
    );
    await tester.pump();

    // The map itself is present.
    expect(find.byType(FlutterMap), findsOneWidget);

    // Polyline layer present (speed-colored route).
    expect(find.byType(PolylineLayer), findsOneWidget);

    // Attribution text (Global Constraint, verbatim string contains it).
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);

    // Stop marker dwell label.
    expect(find.text('12 min'), findsOneWidget);
  });

  testWidgets('renders on a dark surface (never a naked white background)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineMap(segments: segments, gaugeMaxMs: 30),
        ),
      ),
    );
    await tester.pump();

    // The map sits on a dark container so tile-load failure never shows a
    // white screen.
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.byType(FlutterMap),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = container.decoration as BoxDecoration?;
    final bg = decoration?.color ?? container.color;
    expect(bg, isNotNull, reason: 'map must have a background color');
    // Dark racing theme: every channel well below mid-grey.
    expect(bg!.r, lessThan(0.3));
    expect(bg.g, lessThan(0.3));
    expect(bg.b, lessThan(0.3));
  });

  testWidgets('shows a Loading map hint on open and clears it after a delay',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineMap(segments: segments, gaugeMaxMs: 30),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading map…'), findsOneWidget);

    // After the loading window elapses, the hint is gone.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Loading map…'), findsNothing);
  });

  testWidgets('with no route, centers on the provided current position',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineMap(
            segments: const [],
            gaugeMaxMs: 30,
            currentPosition: PositionFix(
              lat: 3.139,
              lng: 101.6869,
              speedMs: 0,
              accuracyM: 5,
              headingDeg: 0,
              timestampMs: 0,
              hasNativeSpeed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, closeTo(3.139, 1e-6));
    expect(map.options.initialCenter.longitude, closeTo(101.6869, 1e-6));
    // Common (wider) default zoom, not a deep street-level zoom.
    expect(map.options.initialZoom, 12);
  });
}
