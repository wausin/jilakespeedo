import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/services/connectivity_service.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/timeline/timeline_screen.dart';
import 'package:sembast/sembast_memory.dart';

/// Controllable [ConnectivityService] for tests.
class FakeConnectivityService implements ConnectivityService {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _offline = false;

  @override
  Stream<bool> get offlineStream => _controller.stream;

  @override
  bool get isOffline => _offline;

  void goOffline() {
    _offline = true;
    _controller.add(true);
  }

  void goOnline() {
    _offline = false;
    _controller.add(false);
  }
}

/// Minimal fake [LocationService].
class FakeLocationService implements LocationService {
  @override
  bool get isSupported => true;

  @override
  LocationStatus get status => LocationStatus.idle;

  @override
  Stream<PositionFix> watch() => const Stream.empty();

  @override
  Stream<LocationStatus> get statusStream => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

const String _offlineText = 'Offline — tiles may not load';

void main() {
  late FakeConnectivityService connectivity;
  late IdbStorageService storage;

  setUp(() async {
    connectivity = FakeConnectivityService();
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  Future<void> pumpScreen(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityServiceProvider.overrideWithValue(connectivity),
          storageServiceProvider.overrideWithValue(storage),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
        ],
        child: const MaterialApp(home: TimelineScreen()),
      ),
    );
  }

  testWidgets('offline banner appears when connectivity is lost and '
      'disappears when it returns', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // Online: no banner.
    expect(find.text(_offlineText), findsNothing);

    connectivity.goOffline();
    await tester.pumpAndSettle();
    expect(find.text(_offlineText), findsOneWidget);

    connectivity.goOnline();
    await tester.pumpAndSettle();
    expect(find.text(_offlineText), findsNothing);
  });
}
