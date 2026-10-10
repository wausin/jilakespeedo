/// Map tile configuration.
///
/// Prefers MapTiler (reliable, free 100k tiles/month, needs an API key
/// injected at build time via `--dart-define=MAPTILER_KEY=...`). When no key
/// is present (local dev without the define), falls back to CARTO dark
/// basemaps, which are keyless but can be rate-limited/blocked on some
/// networks — never ship a release without a MapTiler key.
class MapConfig {
  const MapConfig._();

  /// Injected at build time: `--dart-define=MAPTILER_KEY=...`.
  static const String mapTilerKey =
      String.fromEnvironment('MAPTILER_KEY', defaultValue: '');

  /// Whether a MapTiler key is available.
  static bool get hasMapTiler => mapTilerKey.isNotEmpty;

  /// Tile URL template for the active provider.
  ///
  /// MapTiler `basic-v2-dark` is a dark raster style close to the racing
  /// theme. CARTO is the keyless fallback.
  static String get tileUrl => hasMapTiler
      ? 'https://api.maptiler.com/maps/basic-v2-dark/{z}/{x}/{y}.png'
          '?key=$mapTilerKey'
      : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  /// Subdomains (only meaningful for the CARTO fallback).
  static List<String> get subdomains =>
      hasMapTiler ? const [] : const ['a', 'b', 'c', 'd'];

  /// Required attribution.
  static String get attribution => hasMapTiler
      ? '© MapTiler © OpenStreetMap contributors'
      : '© OpenStreetMap contributors © CARTO';
}
