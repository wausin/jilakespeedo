import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/location_service.dart';
import 'package:jilake_speedo/features/speedo/speedo_screen.dart';
import 'package:sembast/sembast_memory.dart';

class _FakeLocation implements LocationService {
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

void main() {
  testWidgets('speedo screen renders without layout errors', (tester) async {
    final storage =
        IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocation()),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SpeedoScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byKey(SpeedoScreen.markerKey), findsOneWidget);
  });
}
