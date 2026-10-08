// Generates PWA icons for Jilake Speedo.
//
// Run once with: dart run tool/gen_icons.dart
// Output PNGs are committed to web/icons/.
//
// Design: solid #0E0E10 rounded square with a red needle arc at 60%.

import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  _generate(192, 'web/icons/Icon-192.png');
  _generate(512, 'web/icons/Icon-512.png');
  _generateMaskable(192, 'web/icons/Icon-maskable-192.png');
  _generateMaskable(512, 'web/icons/Icon-maskable-512.png');
  stdout.writeln('Icons generated in web/icons/');
}

void _generate(int size, String path) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  // Transparent background
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  final radius = size * 0.22;
  _drawRoundedSquare(image, size, radius, 14, 14, 16);

  _drawGauge(image, size);
  _savePng(image, path);
}

void _generateMaskable(int size, String path) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  // Maskable icons must fill the entire square (safe zone is inner 80%)
  img.fill(image, color: img.ColorRgba8(14, 14, 16, 255));

  _drawGauge(image, size);
  _savePng(image, path);
}

void _drawRoundedSquare(
  img.Image image,
  int size,
  double radius,
  int r,
  int g,
  int b,
) {
  final color = img.ColorRgba8(r, g, b, 255);
  // Fill center rect
  img.fillRect(
    image,
    x1: radius.round(),
    y1: 0,
    x2: size - radius.round(),
    y2: size,
    color: color,
  );
  img.fillRect(
    image,
    x1: 0,
    y1: radius.round(),
    x2: size,
    y2: size - radius.round(),
    color: color,
  );
  // Fill corners
  final centers = [
    [radius, radius],
    [size - radius, radius],
    [radius, size - radius],
    [size - radius, size - radius],
  ];
  for (final c in centers) {
    img.fillCircle(
      image,
      x: c[0].round(),
      y: c[1].round(),
      radius: radius.round(),
      color: color,
    );
  }
}

void _drawGauge(img.Image image, int size) {
  final center = size / 2;
  final radius = size * 0.32;
  final red = img.ColorRgba8(230, 57, 70, 255); // #E63946
  final darkRed = img.ColorRgba8(180, 40, 50, 255);
  final white = img.ColorRgba8(240, 240, 240, 255);

  // Arc from 135° to 405° (270° sweep), needle at 60% = 135 + 270*0.6 = 297°
  const startAngle = 135.0;
  const sweep = 270.0;
  const needleAngle = startAngle + sweep * 0.6;

  // Draw arc track (subtle dark red)
  _drawArc(image, center, radius, startAngle, startAngle + sweep, darkRed, size * 0.02);

  // Draw needle
  final needleRad = needleAngle * pi / 180;
  final nx = center + radius * 0.85 * cos(needleRad);
  final ny = center + radius * 0.85 * sin(needleRad);
  img.drawLine(
    image,
    x1: center.round(),
    y1: center.round(),
    x2: nx.round(),
    y2: ny.round(),
    color: red,
    thickness: (size * 0.03).round(),
  );

  // Center dot
  img.fillCircle(
    image,
    x: center.round(),
    y: center.round(),
    radius: (size * 0.06).round(),
    color: white,
  );
}

void _drawArc(
  img.Image image,
  double center,
  double radius,
  double startDeg,
  double endDeg,
  img.Color color,
  double thickness,
) {
  final steps = ((endDeg - startDeg) * radius / 2).round();
  for (var i = 0; i <= steps; i++) {
    final angle = (startDeg + (endDeg - startDeg) * i / steps) * pi / 180;
    final x = center + radius * cos(angle);
    final y = center + radius * sin(angle);
    img.fillCircle(
      image,
      x: x.round(),
      y: y.round(),
      radius: (thickness / 2).round().clamp(1, 999),
      color: color,
    );
  }
}

void _savePng(img.Image image, String path) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
}
