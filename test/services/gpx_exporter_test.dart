import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/models/track_point.dart';
import 'package:jilake_speedo/core/services/gpx_exporter.dart';
import 'package:xml/xml.dart';

void main() {
  final points = [
    TrackPoint(
      lat: 43.6532,
      lng: -79.3832,
      speedMs: 5.0,
      accuracyM: 3.0,
      timestampMs: 1700000000000,
    ),
    TrackPoint(
      lat: 43.6535,
      lng: -79.3830,
      speedMs: 7.5,
      accuracyM: 3.0,
      timestampMs: 1700000001000,
    ),
    TrackPoint(
      lat: 43.6538,
      lng: -79.3828,
      speedMs: 9.0,
      accuracyM: 4.0,
      timestampMs: 1700000002000,
    ),
  ];

  test('gpx() emits GPX 1.1 with name, trk/trkseg and one trkpt per point',
      () {
    final gpx = GpxExporter.gpx(points: points, vehicleName: 'My Ride');

    // Parseable by the xml package.
    final document = XmlDocument.parse(gpx);
    final root = document.rootElement;

    expect(root.name.local, 'gpx');
    expect(root.getAttribute('version'), '1.1');

    // <name>vehicleName</name>
    expect(
      root.findElements('name').single.innerText,
      'My Ride',
    );

    // <trk><trkseg> structure with 3 track points.
    final trk = root.findElements('trk').single;
    final trkseg = trk.findElements('trkseg').single;
    final trkpts = trkseg.findElements('trkpt').toList();
    expect(trkpts, hasLength(3));

    // Each trkpt carries lat/lon attributes and a time.
    for (var i = 0; i < points.length; i++) {
      final trkpt = trkpts[i];
      expect(
        double.parse(trkpt.getAttribute('lat')!),
        closeTo(points[i].lat, 1e-9),
      );
      expect(
        double.parse(trkpt.getAttribute('lon')!),
        closeTo(points[i].lng, 1e-9),
      );
      final time = trkpt.findElements('time').single.innerText;
      expect(
        DateTime.parse(time).millisecondsSinceEpoch,
        points[i].timestampMs,
      );
    }
  });

  test('gpx() XML-escapes the vehicle name', () {
    final gpx = GpxExporter.gpx(points: const [], vehicleName: 'A & B <Ride>');
    final document = XmlDocument.parse(gpx);
    expect(
      document.rootElement.findElements('name').single.innerText,
      'A & B <Ride>',
    );
    // Raw ampersand must not appear unescaped in the output.
    expect(gpx.contains('<name>A &amp; B &lt;Ride&gt;</name>'), isTrue);
  });

  test('gpx() handles an empty point list', () {
    final gpx = GpxExporter.gpx(points: const [], vehicleName: 'Empty');
    final document = XmlDocument.parse(gpx);
    final trkseg = document.rootElement
        .findElements('trk')
        .single
        .findElements('trkseg')
        .single;
    expect(trkseg.findElements('trkpt'), isEmpty);
  });
}
