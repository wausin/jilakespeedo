import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PWA manifest', () {
    late Map<String, dynamic> manifest;

    setUpAll(() {
      final file = File('web/manifest.json');
      expect(file.existsSync(), isTrue,
          reason: 'web/manifest.json must exist');
      manifest =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('name is "Jilake Speedo"', () {
      expect(manifest['name'], 'Jilake Speedo');
    });

    test('display is standalone', () {
      expect(manifest['display'], 'standalone');
    });

    test('theme_color is #0E0E10', () {
      expect(manifest['theme_color'], '#0E0E10');
    });

    test('background_color is #0E0E10', () {
      expect(manifest['background_color'], '#0E0E10');
    });

    test('has 192 and 512 icons', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      final sizes = icons.map((i) => i['sizes']).toSet();
      expect(sizes, containsAll(<String>['192x192', '512x512']));
    });

    test('has maskable entries for 192 and 512', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      final maskable = icons
          .where((i) => (i['purpose'] as String? ?? '').contains('maskable'))
          .map((i) => i['sizes'])
          .toSet();
      expect(maskable, containsAll(<String>['192x192', '512x512']));
    });

    test('icon files exist on disk', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      for (final icon in icons) {
        final src = icon['src'] as String;
        final file = File('web/$src');
        expect(file.existsSync(), isTrue,
            reason: 'icon file web/$src must exist');
      }
    });
  });

  group('index.html', () {
    late String html;

    setUpAll(() {
      final file = File('web/index.html');
      expect(file.existsSync(), isTrue, reason: 'web/index.html must exist');
      html = file.readAsStringSync();
    });

    test('contains theme-color meta #0E0E10', () {
      expect(html, contains('<meta name="theme-color" content="#0E0E10">'));
    });

    test('title is Jilake Speedo', () {
      expect(html, contains('<title>Jilake Speedo</title>'));
    });

    test('has apple-touch-icon', () {
      expect(html, contains('apple-touch-icon'));
    });
  });
}
