import '../models/track_point.dart';
import 'gpx_downloader_stub.dart'
    if (dart.library.js_interop) 'gpx_downloader_web.dart';

/// Builds GPX 1.1 documents from recorded track points, and triggers a
/// browser download for them on Flutter Web.
class GpxExporter {
  GpxExporter._();

  /// Serializes [points] to a GPX 1.1 document:
  ///
  /// ```xml
  /// <?xml version="1.0" encoding="UTF-8"?>
  /// <gpx version="1.1" creator="Jilake Speedo" xmlns="...">
  ///   <name>vehicleName</name>
  ///   <trk><trkseg>
  ///     <trkpt lat="..." lon="..."><time>...</time></trkpt>
  ///     ...
  ///   </trkseg></trk>
  /// </gpx>
  /// ```
  ///
  /// Track points carry no altitude, so each `trkpt` has lat/lon and a
  /// `<time>` only.
  static String gpx({
    required List<TrackPoint> points,
    required String vehicleName,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Jilake Speedo" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <name>${_escape(vehicleName)}</name>')
      ..writeln('  <trk>')
      ..writeln('    <trkseg>');
    for (final point in points) {
      final time = DateTime.fromMillisecondsSinceEpoch(
        point.timestampMs,
        isUtc: true,
      ).toIso8601String();
      buffer
        ..writeln('      <trkpt lat="${point.lat}" lon="${point.lng}">')
        ..writeln('        <time>$time</time>')
        ..writeln('      </trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..write('</gpx>');
    return buffer.toString();
  }

  /// Triggers a browser download of [xml] as [filename].
  ///
  /// Web-only; must not be invoked from VM code (tests exercise [gpx] only).
  static void download(String xml, String filename) =>
      downloadGpx(xml, filename);

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
