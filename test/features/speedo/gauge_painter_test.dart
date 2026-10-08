import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/features/speedo/gauge_painter.dart';

void main() {
  group('GaugePainter.shouldRepaint', () {
    const base = GaugePainter(
      rangeKmh: 240,
      speedFraction: 0.5,
      peakFraction: 0.75,
      weakSignal: false,
    );

    test('false when all fields are identical', () {
      const other = GaugePainter(
        rangeKmh: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isFalse);
    });

    test('true when rangeKmh differs', () {
      const other = GaugePainter(
        rangeKmh: 180,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when speedFraction differs', () {
      const other = GaugePainter(
        rangeKmh: 240,
        speedFraction: 0.6,
        peakFraction: 0.75,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when peakFraction differs', () {
      const other = GaugePainter(
        rangeKmh: 240,
        speedFraction: 0.5,
        peakFraction: 0.8,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when weakSignal differs', () {
      const other = GaugePainter(
        rangeKmh: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: true,
      );
      expect(base.shouldRepaint(other), isTrue);
    });
  });

  group('GaugePainter.paint', () {
    test('paints without exception and issues draw calls', () {
      const painter = GaugePainter(
        rangeKmh: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: false,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      painter.paint(canvas, const Size(300, 300));

      // Golden-lite: the picture captured at least one draw command.
      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, greaterThan(0));
    });
  });
}
