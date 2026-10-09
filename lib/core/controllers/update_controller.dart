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

/// Outcome of a manual update check, for display in the UI.
class UpdateCheckResult {
  const UpdateCheckResult({required this.available, required this.message});

  /// Whether the server has a newer build.
  final bool available;

  /// Human-readable summary for a snackbar.
  final String message;
}

/// Runs a single update check and returns a displayable result.
///
/// Distinguishes three cases so the user is never misled: an update is
/// available, the build is current, or the server could not be reached.
Future<UpdateCheckResult> checkUpdateNow(UpdateChecker checker) async {
  final server = await checker.fetchServerVersion();
  if (server == null) {
    return UpdateCheckResult(
      available: false,
      message: 'Could not reach the server — check your connection.',
    );
  }
  if (server != checker.runningVersion) {
    return UpdateCheckResult(
      available: true,
      message: 'Update available ($server). Tap the Update badge to reload.',
    );
  }
  return UpdateCheckResult(
    available: false,
    message: "You're up to date (${checker.runningVersion}).",
  );
}

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
