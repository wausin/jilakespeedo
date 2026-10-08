import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';

/// Settings screen: unit toggle (vehicle manager lands in a later task).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('settings-screen');

  /// Marker for the unit toggle control.
  static const Key unitToggleKey = Key('unit-toggle');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(
      settingsControllerProvider.select((s) => s.unit),
    );
    return ListView(
      key: markerKey,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        SwitchListTile(
          key: unitToggleKey,
          title: const Text('Speed unit'),
          subtitle: Text(unitLabel(unit)),
          value: unit == SpeedUnit.mph,
          onChanged: (mph) {
            ref
                .read(settingsControllerProvider.notifier)
                .setUnit(mph ? SpeedUnit.mph : SpeedUnit.kmh);
          },
        ),
      ],
    );
  }
}
