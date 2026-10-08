/// Stub for non-web platforms (VM tests): the browser download is never
/// invoked from tests, so this throws if reached.
void downloadGpx(String xml, String filename) {
  throw UnsupportedError('GpxExporter.download is only supported on the web');
}
