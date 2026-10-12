import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import 'speedo_controller.dart';

/// Watches the speedo speed and, on the rising edge across the configured
/// hit-mark threshold, fires the celebration: bumps [hitMarkTriggerProvider]
/// (the speedo screen watches it) and plays the hit-mark sound.
///
/// Rising-edge only, so it fires once per crossing rather than on every fix.
final hitMarkWatcherProvider =
    NotifierProvider<HitMarkWatcher, void>(HitMarkWatcher.new);

class HitMarkWatcher extends Notifier<void> {
  bool _wasAbove = false;

  @override
  void build() {
    // Re-evaluate whenever the speed or the threshold changes.
    final speed = ref.watch(
      speedoControllerProvider.select((s) => s.displaySpeedMs),
    );
    final hitMarkMs = ref.watch(
          settingsControllerProvider.select((s) => s.hitMarkKmh),
        ) /
        3.6;

    final above = speed >= hitMarkMs;
    if (above && !_wasAbove) {
      ref.read(hitMarkTriggerProvider.notifier).state++;
      ref.read(soundServiceProvider).playHitMark();
    }
    _wasAbove = above;
  }
}
