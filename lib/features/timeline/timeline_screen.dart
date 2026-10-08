import 'package:flutter/material.dart';

/// Timeline screen (placeholder content).
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('timeline-screen');

  @override
  Widget build(BuildContext context) {
    return Center(
      key: markerKey,
      child: Text(
        'Timeline',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
