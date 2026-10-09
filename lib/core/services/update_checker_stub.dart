import 'update_checker.dart';

/// Stub for non-web platforms (VM tests): no update checking on native.
UpdateChecker createUpdateChecker() => _StubUpdateChecker();

class _StubUpdateChecker extends UpdateChecker {
  @override
  String get runningVersion => 'stub';

  @override
  Future<String?> fetchServerVersion() async => null;
}
