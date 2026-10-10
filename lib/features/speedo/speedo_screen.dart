import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';
import 'digital_meter.dart';
import 'session_bar.dart';
import 'speedo_controller.dart';
import 'vehicle_switcher.dart';

/// Speedometer screen: a digital speed readout with a racing arc ring, the
/// collapsible session bar, and the pinned vehicle switcher.
class SpeedoScreen extends ConsumerWidget {
  const SpeedoScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('speedo-screen');

  /// Marker for the peak-speed readout (landscape stats column).
  static const Key peakReadoutKey = Key('speedo-peak-readout');

  /// Opens the Settings screen (vehicles section). Wired by `AppShell`.
  static void Function()? onManageVehicles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(
      settingsControllerProvider.select((s) => s.unit),
    );
    final activeVehicle = ref.watch(
      vehiclesProvider.select((s) => s.activeVehicle),
    );
    final speedo = ref.watch(
      speedoControllerProvider.select(
        (s) => (
          display: s.displaySpeedMs,
          peak: s.peakSpeedMs,
          weakSignal: s.weakSignal,
        ),
      ),
    );

    final rangeKmh = activeVehicle?.gaugeMaxKmh ?? Vehicle.defaultGaugeMaxKmh;
    final rangeInUnit = convertSpeed(ms: rangeKmh / 3.6, unit: unit);
    final gaugeRange = rangeInUnit < 1 ? 1.0 : rangeInUnit;
    final speedInUnit = convertSpeed(ms: speedo.display, unit: unit);
    final peakInUnit = convertSpeed(ms: speedo.peak, unit: unit);

    final meter = DigitalMeter(
      speed: speedInUnit.round(),
      unit: unitLabel(unit),
      speedFraction: speedInUnit / gaugeRange,
      peakFraction: peakInUnit / gaugeRange,
      weakSignal: speedo.weakSignal,
    );

    return SafeArea(
      key: markerKey,
      child: OrientationBuilder(
        builder: (context, orientation) {
          if (orientation == Orientation.portrait) {
            return Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: meter,
                  ),
                ),
                const SessionBar(),
                const VehicleSwitcher(),
              ],
            );
          }
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: meter,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PeakStat(
                            key: peakReadoutKey,
                            peak: peakInUnit.round(),
                            unit: unitLabel(unit),
                          ),
                          const SizedBox(height: 16),
                          const VehicleSwitcher(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SessionBar(),
            ],
          );
        },
      ),
    );
  }
}

class _PeakStat extends StatelessWidget {
  const _PeakStat({super.key, required this.peak, required this.unit});

  final int peak;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'PEAK',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 3,
          ),
        ),
        Text(
          '$peak $unit',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
