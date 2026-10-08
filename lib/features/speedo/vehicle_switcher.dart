import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/vehicle.dart';
import 'speedo_screen.dart';

/// Horizontal bar of pinned vehicles (max 3) with a trailing "manage"
/// button. Tapping a vehicle makes it active; tapping the manage button —
/// or long-pressing anywhere on the bar — opens the Settings screen
/// (vehicles section) via [SpeedoScreen.onManageVehicles].
class VehicleSwitcher extends ConsumerWidget {
  const VehicleSwitcher({super.key});

  /// At most this many pinned vehicles are shown.
  static const int maxPinned = 3;

  /// Marker for the trailing manage button.
  static const Key manageButtonKey = Key('vehicle-switcher-manage');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesState = ref.watch(vehiclesProvider);
    final pinned = vehiclesState.vehicles
        .where((vehicle) => vehicle.isPinned)
        .take(maxPinned)
        .toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: SpeedoScreen.onManageVehicles,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final vehicle in pinned)
              _VehicleChip(
                key: Key('vehicle-chip-${vehicle.id}'),
                vehicle: vehicle,
                isActive: vehicle.id == vehiclesState.activeVehicleId,
                onTap: () =>
                    ref.read(vehiclesProvider.notifier).setActive(vehicle.id),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                key: manageButtonKey,
                icon: const Icon(Icons.tune),
                tooltip: 'Manage vehicles',
                onPressed: SpeedoScreen.onManageVehicles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleChip extends StatelessWidget {
  const _VehicleChip({
    super.key,
    required this.vehicle,
    required this.isActive,
    required this.onTap,
  });

  final Vehicle vehicle;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(vehicle.name),
        selected: isActive,
        onSelected: (_) => onTap(),
        selectedColor: colorScheme.primary.withValues(alpha: 0.35),
        labelStyle: TextStyle(
          color: isActive ? colorScheme.primary : colorScheme.onSurface,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
        ),
        side: BorderSide(
          color: isActive ? colorScheme.primary : colorScheme.outline,
        ),
      ),
    );
  }
}
