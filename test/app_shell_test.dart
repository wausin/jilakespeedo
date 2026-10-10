import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/app.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/controllers/update_controller.dart';
import 'package:jilake_speedo/core/services/connectivity_service.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/core/services/update_checker.dart';
import 'package:jilake_speedo/features/analytics/analytics_screen.dart';
import 'package:jilake_speedo/features/settings/settings_screen.dart';
import 'package:jilake_speedo/features/speedo/speedo_screen.dart';
import 'package:jilake_speedo/features/timeline/timeline_screen.dart';
import 'package:jilake_speedo/features/update/update_badge.dart';
import 'package:sembast/sembast_memory.dart';

/// Fake [LocationService] with a controllable fix stream and status stream.
class FakeLocationService implements LocationService {
  final StreamController<PositionFix> fixes =
      StreamController<PositionFix>.broadcast();
  final StreamController<LocationStatus> statuses =
      StreamController<LocationStatus>.broadcast();

  LocationStatus _status = LocationStatus.idle;
  int startCount = 0;

  @override
  bool get isSupported => true;

  @override
  LocationStatus get status => _status;

  @override
  Stream<PositionFix> watch() => fixes.stream;

  @override
  Stream<LocationStatus> get statusStream => statuses.stream;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {}

  void emitStatus(LocationStatus status) {
    _status = status;
    statuses.add(status);
  }
}

/// Always-online [ConnectivityService] for the shell tests.
class FakeConnectivityService implements ConnectivityService {
  @override
  Stream<bool> get offlineStream => const Stream.empty();

  @override
  bool get isOffline => false;
}

/// [UpdateChecker] that always reports an update available.
class _AvailableUpdateChecker extends UpdateChecker {
  @override
  String get runningVersion => 'test-old';

  @override
  Future<String?> fetchServerVersion() async => 'test-new';
}

/// [UpdateChecker] that never reports an update.
class _CurrentUpdateChecker extends UpdateChecker {
  @override
  String get runningVersion => 'test-same';

  @override
  Future<String?> fetchServerVersion() async => 'test-same';
}

/// Recording [WakeLockService]: ref-counted like the real one, no platform
/// wakelock behind it (same pattern as the session/timeline tests).
class FakeWakeLockService extends WakeLockService {
  int holdCount = 0;
  int releaseCount = 0;

  @override
  Future<void> hold() async {
    holdCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

void main() {
  late FakeLocationService locationService;
  late IdbStorageService storage;
  late FakeWakeLockService wakeLock;

  setUp(() async {
    locationService = FakeLocationService();
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
    wakeLock = FakeWakeLockService();
  });

  Future<void> pumpApp(WidgetTester tester, {UpdateChecker? updateChecker}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(locationService),
          storageServiceProvider.overrideWithValue(storage),
          wakeLockServiceProvider.overrideWithValue(wakeLock),
          connectivityServiceProvider
              .overrideWithValue(FakeConnectivityService()),
          updateCheckerProvider
              .overrideWithValue(updateChecker ?? _CurrentUpdateChecker()),
        ],
        child: const JilakeSpeedoApp(),
      ),
    );
  }

  testWidgets('navigation bar has 4 destinations and taps navigate',
      (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    // 4 destinations.
    expect(find.byType(NavigationDestination), findsNWidgets(4));

    // Starts on the speedo screen.
    expect(find.byKey(SpeedoScreen.markerKey), findsOneWidget);

    // Tap Analytics.
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.byKey(AnalyticsScreen.markerKey), findsOneWidget);

    // Tap Timeline.
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.byKey(TimelineScreen.markerKey), findsOneWidget);

    // Tap Settings.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsScreen.markerKey), findsOneWidget);

    // Back to Speedo.
    await tester.tap(find.text('Speedo'));
    await tester.pumpAndSettle();
    expect(find.byKey(SpeedoScreen.markerKey), findsOneWidget);
  });

  testWidgets('settings unit toggle switches displayed labels km/h -> mph',
      (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    // Default unit is km/h.
    expect(find.byKey(SpeedoScreen.markerKey), findsOneWidget);
    expect(find.text('km/h'), findsWidgets);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('km/h'), findsWidgets);

    // Toggle the unit.
    await tester.tap(find.byKey(SettingsScreen.unitToggleKey));
    await tester.pumpAndSettle();

    // Settings now shows mph.
    expect(find.text('mph'), findsWidgets);
    expect(find.text('km/h'), findsNothing);

    // Speedo also shows mph (unit changes notify all screens).
    await tester.tap(find.text('Speedo'));
    await tester.pumpAndSettle();
    expect(find.text('mph'), findsWidgets);
    expect(find.text('km/h'), findsNothing);
  });

  testWidgets('permission-denied status shows friendly screen with retry',
      (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(SpeedoScreen.markerKey), findsOneWidget);

    locationService.emitStatus(LocationStatus.permissionDenied);
    await tester.pumpAndSettle();

    expect(find.byKey(AppShell.permissionDeniedKey), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(SpeedoScreen.markerKey), findsNothing);

    // Tapping retry restarts the location service.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(locationService.startCount, greaterThan(0));
  });

  testWidgets('wake lock is held on the speedo tab and released when '
      'switching away', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    // Starts on the speedo tab: lock held so the screen stays on while riding.
    expect(find.byKey(SpeedoScreen.markerKey), findsOneWidget);
    expect(wakeLock.holdCount, 1);
    expect(wakeLock.releaseCount, 0);

    // Switch to Analytics: speedo no longer visible, lock released.
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(wakeLock.holdCount, 1);
    expect(wakeLock.releaseCount, 1);

    // Switch to Timeline: still released.
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(wakeLock.holdCount, 1);
    expect(wakeLock.releaseCount, 1);

    // Back to Speedo: held again.
    await tester.tap(find.text('Speedo'));
    await tester.pumpAndSettle();
    expect(wakeLock.holdCount, 2);
    expect(wakeLock.releaseCount, 1);
  });

  testWidgets('update badge appears when a newer build is on the server',
      (tester) async {
    await pumpApp(tester, updateChecker: _AvailableUpdateChecker());
    // The badge has an always-running breathing animation, so pumpAndSettle
    // never settles; pump fixed durations instead to let the check land.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(UpdateBadge.badgeKey), findsOneWidget);
  });

  testWidgets('no update badge when the build is current', (tester) async {
    await pumpApp(tester, updateChecker: _CurrentUpdateChecker());
    await tester.pumpAndSettle();

    expect(find.byKey(UpdateBadge.badgeKey), findsNothing);
  });
}
