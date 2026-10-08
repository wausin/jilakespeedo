import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/app.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/session/session_screen.dart';
import 'package:jilake_speedo/features/settings/settings_screen.dart';
import 'package:jilake_speedo/features/speedo/speedo_screen.dart';
import 'package:jilake_speedo/features/timeline/timeline_screen.dart';
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

void main() {
  late FakeLocationService locationService;
  late IdbStorageService storage;

  setUp(() async {
    locationService = FakeLocationService();
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(locationService),
          storageServiceProvider.overrideWithValue(storage),
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

    // Tap Session.
    await tester.tap(find.text('Session'));
    await tester.pumpAndSettle();
    expect(find.byKey(SessionScreen.markerKey), findsOneWidget);

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
}
