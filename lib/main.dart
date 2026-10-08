import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast_web/sembast_web.dart';

import 'app.dart';
import 'core/controllers/providers.dart';
import 'core/services/idb_storage_service.dart';
import 'core/services/web_location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DatabaseFactory factory = databaseFactoryWeb;
  final storage = IdbStorageService(databaseFactory: factory);
  await storage.init();
  runApp(
    ProviderScope(
      overrides: [
        databaseFactoryProvider.overrideWithValue(factory),
        storageServiceProvider.overrideWithValue(storage),
        locationServiceProvider.overrideWithValue(WebLocationService()),
      ],
      child: const JilakeSpeedoApp(),
    ),
  );
}
