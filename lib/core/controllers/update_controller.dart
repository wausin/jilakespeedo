import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_checker.dart';
import '../services/update_checker_stub.dart'
    if (dart.library.js_interop) '../services/update_checker_web.dart';

/// How often the app checks the server for a newly deployed build.
const updateCheckInterval = Duration(minutes: 5);

/// Platform [UpdateChecker]. Override with a fake in tests.
final updateCheckerProvider = Provider<UpdateChecker>(
  (_) => createUpdateChecker(),
);

/// True when the server hosts a build newer than the running one.
final updateAvailableProvider = StateProvider<bool>((_) => false);

/// Checks for updates immediately, then every [interval].
///
/// Web-only in practice (the stub checker never reports an update); the
/// first check is deferred past the first frame so it cannot throw during
/// `initState`.
///
/// Returns the periodic [Timer]; the caller must cancel it (e.g. in
/// `dispose`) to avoid leaks.
Future<Timer> startUpdateChecks(
  UpdateChecker checker,
  void Function(bool available) onResult, {
  Duration interval = updateCheckInterval,
}) async {
  Future<void> check() async {
    onResult(await checker.isUpdateAvailable());
  }

  await Future<void>.delayed(Duration.zero);
  await check();
  return Timer.periodic(interval, (_) => unawaited(check()));
}
