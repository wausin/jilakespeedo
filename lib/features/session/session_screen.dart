import 'package:flutter/material.dart';

/// Session screen (placeholder content).
class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('session-screen');

  @override
  Widget build(BuildContext context) {
    return Center(
      key: markerKey,
      child: Text(
        'Session',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
