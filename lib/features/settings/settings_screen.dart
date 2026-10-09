import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';
import '../../core/services/gpx_exporter.dart';
import '../../core/services/storage_service.dart';
import 'vehicle_manager_screen.dart';

/// Settings screen: unit toggle, vehicle manager, per-session GPX export,
/// and install/about instructions.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('settings-screen');

  /// Marker for the unit toggle control.
  static const Key unitToggleKey = Key('unit-toggle');

  /// Marker for the vehicles section (manage-vehicles entry point).
  ///
  /// A [GlobalKey] so the app shell can scroll it into view when the
  /// speedo's manage-vehicles button lands here.
  static final GlobalKey vehiclesSectionKey = GlobalKey(
    debugLabel: 'settings-vehicles-section',
  );

  /// Marker for the export section.
  static const Key exportSectionKey = Key('settings-export-section');

  /// Export row key for the session with [id].
  static Key exportKeyFor(String id) => Key('export-$id');

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
        const SizedBox(height: 16),
        _VehiclesSection(key: vehiclesSectionKey),
        const SizedBox(height: 16),
        const _ExportSection(key: exportSectionKey),
        const SizedBox(height: 16),
        const _AboutSection(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

/// Vehicles section: current vehicles summary plus a manage button that
/// opens the full vehicle manager.
class _VehiclesSection extends ConsumerWidget {
  const _VehiclesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesState = ref.watch(vehiclesProvider);
    final vehicleCount = vehiclesState.vehicles.length;
    final pinnedCount =
        vehiclesState.vehicles.where((v) => v.isPinned).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Vehicles'),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.directions_car_outlined),
          title: Text('$vehicleCount vehicle${vehicleCount == 1 ? '' : 's'}'),
          subtitle: Text('$pinnedCount pinned to the switcher'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const VehicleManagerScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Export section: lists the active vehicle's sessions; tapping one
/// downloads its track as a GPX file.
class _ExportSection extends ConsumerWidget {
  const _ExportSection({super.key});

  static String _fileNameFor(Session session) {
    final day = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final stamp =
        '${day.year}${day.month.toString().padLeft(2, '0')}'
        '${day.day.toString().padLeft(2, '0')}-'
        '${day.hour.toString().padLeft(2, '0')}'
        '${day.minute.toString().padLeft(2, '0')}';
    return 'jilake-speedo-$stamp.gpx';
  }

  static String _titleFor(Session session) {
    final day = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final date =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final time =
        '${day.hour.toString().padLeft(2, '0')}:'
        '${day.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeVehicle = ref.watch(
      vehiclesProvider.select((s) => s.activeVehicle),
    );
    final storage = ref.watch(storageServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Export'),
        const SizedBox(height: 8),
        if (activeVehicle == null)
          Text('No vehicle selected', style: theme.textTheme.bodyMedium)
        else
          FutureBuilder<List<Session>>(
            future: storage.sessionsForVehicle(activeVehicle.id, limit: 20),
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? const <Session>[];
              if (sessions.isEmpty) {
                return Text(
                  'No sessions to export yet',
                  style: theme.textTheme.bodyMedium,
                );
              }
              return Column(
                children: [
                  for (final session in sessions)
                    ListTile(
                      key: SettingsScreen.exportKeyFor(session.id),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.download_outlined),
                      title: Text(_titleFor(session)),
                      subtitle: Text(
                        '${activeVehicle.name} · GPX',
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => _export(storage, session, activeVehicle),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Future<void> _export(
    StorageService storage,
    Session session,
    Vehicle vehicle,
  ) async {
    final points = await storage.trackPoints(session.id);
    if (points.isEmpty) return;
    final xml = GpxExporter.gpx(points: points, vehicleName: vehicle.name);
    GpxExporter.download(xml, _fileNameFor(session));
  }
}

/// About/install instructions for both mobile platforms.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('About'),
        const SizedBox(height: 8),
        Text('Jilake Speedo — GPS speedometer PWA', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          'Install as an app:\n'
          '• Android: open the Chrome menu (⋮) → Install app.\n'
          '• iOS: tap the Safari share button → Add to Home Screen.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
