import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/speedo/speedo_controller.dart';

/// Fake [LocationService] with a controllable fix stream (same pattern as
/// test/app_shell_test.dart).
class FakeLocationService implements LocationService {
  final StreamController<PositionFix> fixes =
      StreamController<PositionFix>.broadcast();
  final StreamController<LocationStatus> statuses =
      StreamController<LocationStatus>.broadcast();

  final LocationStatus _status = LocationStatus.idle;

  @override
  bool get isSupported => true;

  @override
  LocationStatus get status => _status;

  @override
  Stream<PositionFix> watch() => fixes.stream;

  @override
  Stream<LocationStatus> get statusStream => statuses.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

PositionFix fix({required double speedMs, double accuracyM = 10}) =>
    PositionFix(
      lat: 0,
      lng: 0,
      speedMs: speedMs,
      accuracyM: accuracyM,
      headingDeg: 0,
      timestampMs: 0,
      hasNativeSpeed: true,
    );

/// Minimal host that only instantiates the controller.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(speedoControllerProvider);
    return const SizedBox.shrink();
  }
}

void main() {
  late FakeLocationService locationService;

  setUp(() {
    locationService = FakeLocationService();
  });

  Future<ProviderContainer> pumpHost(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(locationService),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Host()),
      ),
    );
    return container;
  }

  testWidgets('fix at 20 m/s animates display speed toward 20 and peaks',
      (tester) async {
    final container = await pumpHost(tester);

    locationService.fixes.add(fix(speedMs: 20));
    await tester.pump();
    // Mid-animation: already approaching 20, above the initial 0.
    await tester.pump(const Duration(milliseconds: 150));
    final mid = container.read(speedoControllerProvider);
    expect(mid.displaySpeedMs, greaterThan(0));
    expect(mid.displaySpeedMs, lessThan(20));
    expect(mid.peakSpeedMs, 20);

    // Animation finished: display reached the target.
    await tester.pump(const Duration(milliseconds: 200));
    final done = container.read(speedoControllerProvider);
    expect(done.displaySpeedMs, closeTo(20, 1e-6));
    expect(done.peakSpeedMs, 20);
    expect(done.weakSignal, isFalse);
  });

  testWidgets('bad fix (accuracy 120) flags weak signal and is ignored',
      (tester) async {
    final container = await pumpHost(tester);

    locationService.fixes.add(fix(speedMs: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(speedoControllerProvider).displaySpeedMs,
      closeTo(20, 1e-6),
    );

    locationService.fixes.add(fix(speedMs: 99, accuracyM: 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final state = container.read(speedoControllerProvider);
    expect(state.weakSignal, isTrue);
    expect(state.displaySpeedMs, closeTo(20, 1e-6));
    expect(state.peakSpeedMs, 20);
  });

  testWidgets('peak stays after speed drops', (tester) async {
    final container = await pumpHost(tester);

    locationService.fixes.add(fix(speedMs: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    locationService.fixes.add(fix(speedMs: 5));
    await tester.pump();
    // Settle frame: lets the ticker start before advancing past its duration
    // (fake-async tickers skip when start and elapse happen in one pump).
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 400));
    final state = container.read(speedoControllerProvider);
    expect(state.peakSpeedMs, 20);
    expect(state.displaySpeedMs, closeTo(5, 1e-6));
  });
}
