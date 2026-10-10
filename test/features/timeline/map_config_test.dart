import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/features/timeline/map_config.dart';

void main() {
  group('MapConfig', () {
    test('falls back to CARTO when no MapTiler key is injected', () {
      // Tests run without --dart-define, so the key is empty.
      expect(MapConfig.hasMapTiler, isFalse);
      expect(MapConfig.tileUrl, contains('cartocdn.com'));
      expect(MapConfig.subdomains, isNotEmpty);
      expect(MapConfig.attribution, contains('CARTO'));
    });
  });
}
