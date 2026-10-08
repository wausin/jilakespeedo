import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';

/// Speedometer screen (placeholder content).
class SpeedoScreen extends ConsumerWidget {
  const SpeedoScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('speedo-screen');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(
      settingsControllerProvider.select((s) => s.unit),
    );
    return Center(
      key: markerKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Speedo',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            unitLabel(unit),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
