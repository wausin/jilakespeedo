import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';
import 'gauge_painter.dart';
import 'speedo_controller.dart';
import 'vehicle_switcher.dart';

/// Speedometer screen: racing gauge with digital readout plus the pinned
/// vehicle switcher.
///
/// The needle animation only changes the gauge painter's fraction inputs, so
/// per-frame ticks rebuild just the screen's lightweight widget tree — the
/// expensive dial painting happens once per frame in the [CustomPainter]
/// either way, and the switcher/navigation stay untouched.
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
    final readoutGlow = Theme.of(context).colorScheme.primary;

    final gauge = AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: GaugePainter(
          rangeKmh: gaugeRange,
          speedFraction: speedInUnit / gaugeRange,
          peakFraction: peakInUnit / gaugeRange,
          weakSignal: speedo.weakSignal,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Spacer(flex: 3),
              Text(
                speedInUnit.round().toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: readoutGlow.withValues(alpha: 0.8),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
              Text(
                unitLabel(unit),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
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
                    child: gauge,
                  ),
                ),
                const VehicleSwitcher(),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: gauge,
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
