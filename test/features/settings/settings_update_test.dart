import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/providers.dart';
import 'package:jilake_speedo/core/controllers/update_controller.dart';
import 'package:jilake_speedo/core/services/idb_storage_service.dart';
import 'package:jilake_speedo/core/services/update_checker.dart';
import 'package:jilake_speedo/features/settings/settings_screen.dart';
import 'package:sembast/sembast_memory.dart';

class _FakeChecker extends UpdateChecker {
  _FakeChecker({required this.running, this.server});
  final String running;
  final String? server;

  @override
  String get runningVersion => running;

  @override
  Future<String?> fetchServerVersion() async => server;
}

void main() {
  late IdbStorageService storage;

  setUp(() async {
    storage = IdbStorageService(databaseFactory: newDatabaseFactoryMemory());
    await storage.init();
  });

  Future<void> pumpSettings(WidgetTester tester, UpdateChecker checker) async {
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        updateCheckerProvider.overrideWithValue(checker),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Check for updates reports up-to-date', (tester) async {
    await pumpSettings(
      tester,
      _FakeChecker(running: '1.0.0+1', server: '1.0.0+1'),
    );

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.checkUpdateKey),
      200,
    );
    await tester.tap(find.byKey(SettingsScreen.checkUpdateKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('up to date'), findsOneWidget);
  });

  testWidgets('Check for updates reports an available update', (tester) async {
    await pumpSettings(
      tester,
      _FakeChecker(running: '1.0.0+1', server: '1.0.0+9'),
    );

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.checkUpdateKey),
      200,
    );
    await tester.tap(find.byKey(SettingsScreen.checkUpdateKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.0.0+9'), findsWidgets);
  });
}
