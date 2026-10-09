/// Stub for non-web platforms (VM tests): reload is never invoked from
/// tests, so this throws if reached.
void reloadApp() {
  throw UnsupportedError('reloadApp is only supported on the web');
}
