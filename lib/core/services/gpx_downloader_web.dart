import 'dart:convert';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [xml] as [filename] by clicking a
/// temporary data-URL anchor.
void downloadGpx(String xml, String filename) {
  final bytes = utf8.encode(xml);
  final anchor = web.HTMLAnchorElement()
    ..href = 'data:text/xml;charset=utf-8;base64,${base64Encode(bytes)}'
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
