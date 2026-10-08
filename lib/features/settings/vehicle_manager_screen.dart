import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';

/// Vehicle manager: lists all vehicles with pin/delete affordances and an
/// add button; editing opens a form dialog (name, type, gauge max, pin).
class VehicleManagerScreen extends ConsumerWidget {
  const VehicleManagerScreen({super.key});

  /// Marker used by tests to verify the manager opened.
  static const Key markerKey = Key('vehicle-manager-screen');

  /// Marker for the add-vehicle button.
  static const Key addButtonKey = Key('vehicle-add');

  /// Pin toggle key for the vehicle with [id].
  static Key pinKeyFor(String id) => Key('vehicle-pin-$id');

  /// Delete button key for the vehicle with [id].
  static Key deleteKeyFor(String id) => Key('vehicle-delete-$id');

  /// Tile key for the vehicle with [id].
  static Key tileKeyFor(String id) => Key('vehicle-tile-$id');

  static String _typeLabel(VehicleType type) => switch (type) {
        VehicleType.bike => 'Bike',
        VehicleType.motorcycle => 'Motorcycle',
        VehicleType.car => 'Car',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(vehiclesProvider);
    final notifier = ref.read(vehiclesProvider.notifier);

    return Scaffold(
      key: markerKey,
      appBar: AppBar(title: const Text('Vehicles')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Pin up to ${VehiclesController.maxPinned} vehicles to the '
              'speedo switcher. The first pinned vehicle is selected on '
              'start.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final vehicle in state.vehicles)
            ListTile(
              key: tileKeyFor(vehicle.id),
              leading: Icon(
                vehicle.id == state.activeVehicleId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: vehicle.id == state.activeVehicleId
                    ? theme.colorScheme.primary
                    : null,
              ),
              title: Text(vehicle.name),
              subtitle: Text(
                '${_typeLabel(vehicle.type)} · '
                '${vehicle.gaugeMaxKmh.round()} km/h max',
              ),
              onTap: () => _openForm(context, ref, vehicle: vehicle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: pinKeyFor(vehicle.id),
                    tooltip: vehicle.isPinned ? 'Unpin' : 'Pin to switcher',
                    icon: Icon(
                      vehicle.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      color: vehicle.isPinned
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    onPressed: () => notifier.pin(
                      vehicle.id,
                      pinned: !vehicle.isPinned,
                    ),
                  ),
                  IconButton(
                    key: deleteKeyFor(vehicle.id),
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        _confirmDelete(context, notifier, vehicle),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: addButtonKey,
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VehiclesController notifier,
    Vehicle vehicle,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text('Remove "${vehicle.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.delete(vehicle.id);
    }
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Vehicle? vehicle,
  }) async {
    final result = await showDialog<Vehicle>(
      context: context,
      builder: (_) => _VehicleFormDialog(vehicle: vehicle),
    );
    if (result != null) {
      await ref.read(vehiclesProvider.notifier).upsert(result);
    }
  }
}

/// Add/edit form: name, type, gauge max (km/h), pin toggle.
class _VehicleFormDialog extends StatefulWidget {
  const _VehicleFormDialog({this.vehicle});

  final Vehicle? vehicle;

  @override
  State<_VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends State<_VehicleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _gaugeMaxController;
  late VehicleType _type;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    _nameController = TextEditingController(text: vehicle?.name ?? '');
    _gaugeMaxController = TextEditingController(
      text: (vehicle?.gaugeMaxKmh ?? Vehicle.defaultGaugeMaxKmh)
          .round()
          .toString(),
    );
    _type = vehicle?.type ?? VehicleType.motorcycle;
    _pinned = vehicle?.isPinned ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gaugeMaxController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final vehicle = widget.vehicle;
    Navigator.of(context).pop(
      Vehicle(
        id: vehicle?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        type: _type,
        gaugeMaxKmh: double.parse(_gaugeMaxController.text.trim()),
        isPinned: _pinned,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.vehicle == null ? 'Add vehicle' : 'Edit vehicle'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('vehicle-form-name'),
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<VehicleType>(
              key: const Key('vehicle-form-type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final type in VehicleType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(VehicleManagerScreen._typeLabel(type)),
                  ),
              ],
              onChanged: (type) {
                if (type != null) setState(() => _type = type);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('vehicle-form-gauge-max'),
              controller: _gaugeMaxController,
              decoration:
                  const InputDecoration(labelText: 'Gauge max (km/h)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed < 1) {
                  return 'Enter a positive number';
                }
                return null;
              },
            ),
            SwitchListTile(
              key: const Key('vehicle-form-pin'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Pin to switcher'),
              value: _pinned,
              onChanged: (pinned) => setState(() => _pinned = pinned),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('vehicle-form-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
