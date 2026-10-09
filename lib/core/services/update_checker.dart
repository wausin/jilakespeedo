/// Polls the deployed `version.json` and reports whether the running build
/// is outdated.
///
/// Abstraction so tests can substitute a fake; the web implementation lives
/// in `update_checker_web.dart`.
abstract class UpdateChecker {
  /// The version string baked into the running build (`--dart-define`).
  String get runningVersion;

  /// Fetches the server's version. Returns `null` on any failure (offline,
  /// 404, malformed JSON) — failures must never crash the app or produce a
  /// false "update available".
  Future<String?> fetchServerVersion();

  /// True when the server version differs from the running version.
  Future<bool> isUpdateAvailable() async {
    final server = await fetchServerVersion();
    if (server == null) return false;
    return server != runningVersion;
  }
}
