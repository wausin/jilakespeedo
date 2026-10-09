import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/services/location_service.dart';

/// Speedo gauge state.
class SpeedoState {
  const SpeedoState({
    this.displaySpeedMs = 0,
    this.peakSpeedMs = 0,
    this.weakSignal = false,
  });

  /// Needle position in m/s; eases toward the latest accepted fix's speed.
  final double displaySpeedMs;

  /// Highest accepted speed seen while this controller is alive (m/s).
  final double peakSpeedMs;

  /// True while the most recent fix had accuracy worse than
  /// [SpeedoController.accuracyThresholdM].
  final bool weakSignal;

  SpeedoState copyWith({
    double? displaySpeedMs,
    double? peakSpeedMs,
    bool? weakSignal,
  }) =>
      SpeedoState(
        displaySpeedMs: displaySpeedMs ?? this.displaySpeedMs,
        peakSpeedMs: peakSpeedMs ?? this.peakSpeedMs,
        weakSignal: weakSignal ?? this.weakSignal,
      );
}

class _NotifierTicker extends Ticker {
  _NotifierTicker(super.onTick, this.onDisposed);

  final void Function() onDisposed;

  @override
  void dispose() {
    super.dispose();
    onDisposed();
  }
}

/// Drives the speedo needle from [LocationService] fixes.
///
/// Fixes with accuracy worse than [accuracyThresholdM] are ignored for the
/// needle (they only set the weak-signal flag). Accepted fixes retarget a
/// spring animation (300 ms, easeOutCubic) and raise [SpeedoState.peakSpeedMs].
///
/// The animation ticks update [SpeedoState.displaySpeedMs]; the gauge widget
/// listens to the controller and repaints only the gauge [CustomPaint], so
/// per-frame ticks never rebuild the whole screen.
class SpeedoController extends AutoDisposeNotifier<SpeedoState>
    implements TickerProvider {
  /// GPS accuracy gate: fixes worse than this are ignored for display.
  static const double accuracyThresholdM = 50;

  final Set<Ticker> _tickers = <Ticker>{};

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(_onTick);

  StreamSubscription<PositionFix>? _subscription;
  double _animFrom = 0;
  double _animTarget = 0;

  @override
  Ticker createTicker(TickerCallback onTick) {
    late final _NotifierTicker ticker;
    ticker = _NotifierTicker(onTick, () => _tickers.remove(ticker));
    _tickers.add(ticker);
    return ticker;
  }

  @override
  SpeedoState build() {
    final locationService = ref.watch(locationServiceProvider);
    _subscription?.cancel();
    _subscription = locationService.watch().listen(_onFix);
    ref.onDispose(() {
      _subscription?.cancel();
      _animation.dispose();
      for (final ticker in _tickers.toList()) {
        ticker.dispose();
      }
      _tickers.clear();
    });
    return const SpeedoState();
  }

  void _onFix(PositionFix fix) {
    if (fix.accuracyM > accuracyThresholdM) {
      // Bad fix: flag weak signal, leave the needle alone.
      state = state.copyWith(weakSignal: true);
      return;
    }
    final target = fix.speedMs;
    _animFrom = state.displaySpeedMs;
    _animTarget = target;
    state = state.copyWith(
      weakSignal: false,
      peakSpeedMs:
          target > state.peakSpeedMs ? target : state.peakSpeedMs,
    );
    _animation.forward(from: 0);
  }

  void _onTick() {
    final eased = Curves.easeOutCubic.transform(_animation.value);
    state = state.copyWith(
      displaySpeedMs:
          _animFrom + (_animTarget - _animFrom) * eased,
    );
  }
}

/// The speedo gauge controller. Auto-disposed with the speedo screen.
final speedoControllerProvider =
    AutoDisposeNotifierProvider<SpeedoController, SpeedoState>(
  SpeedoController.new,
);
