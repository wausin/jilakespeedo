import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/models.dart';
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
}
