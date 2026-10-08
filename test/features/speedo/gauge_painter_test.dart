import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/features/speedo/gauge_painter.dart';

void main() {
  group('GaugePainter.shouldRepaint', () {
    const base = GaugePainter(
      rangeMax: 240,
      speedFraction: 0.5,
      peakFraction: 0.75,
      weakSignal: false,
    );

    test('false when all fields are identical', () {
      const other = GaugePainter(
        rangeMax: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isFalse);
    });

    test('true when rangeMax differs', () {
      const other = GaugePainter(
        rangeMax: 180,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when speedFraction differs', () {
      const other = GaugePainter(
        rangeMax: 240,
        speedFraction: 0.6,
        peakFraction: 0.75,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when peakFraction differs', () {
      const other = GaugePainter(
        rangeMax: 240,
        speedFraction: 0.5,
        peakFraction: 0.8,
        weakSignal: false,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when weakSignal differs', () {
      const other = GaugePainter(
        rangeMax: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: true,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('true when weakPulse differs', () {
      const other = GaugePainter(
        rangeMax: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: true,
        weakPulse: 0.4,
      );
      expect(
        const GaugePainter(
          rangeMax: 240,
          speedFraction: 0.5,
          peakFraction: 0.75,
          weakSignal: true,
        ).shouldRepaint(other),
        isTrue,
      );
    });
  });

  group('GaugePainter.paint', () {
    test('paints without exception and issues draw calls', () {
      const painter = GaugePainter(
        rangeMax: 240,
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

    test('paints the weak-signal dot without exception when weak', () {
      const painter = GaugePainter(
        rangeMax: 240,
        speedFraction: 0.5,
        peakFraction: 0.75,
        weakSignal: true,
        weakPulse: 0.3,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      painter.paint(canvas, const Size(300, 300));

      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, greaterThan(0));
    });
  });

  group('SpeedoGauge weak-signal pulse', () {
    GaugePainter painterOf(WidgetTester tester) => tester
            .widget<CustomPaint>(find.descendant(
          of: find.byType(SpeedoGauge),
          matching: find.byType(CustomPaint),
        ))
            .painter!
        as GaugePainter;

    Widget host({required bool weakSignal}) => MaterialApp(
          home: Scaffold(
            body: SpeedoGauge(
              rangeMax: 240,
              speedFraction: 0.5,
              peakFraction: 0.75,
              weakSignal: weakSignal,
            ),
          ),
        );

    testWidgets('dot pulse animates while weakSignal is true', (tester) async {
      await tester.pumpWidget(host(weakSignal: true));

      final v0 = painterOf(tester).weakPulse;
      await tester.pump(const Duration(milliseconds: 300));
      final v1 = painterOf(tester).weakPulse;
      await tester.pump(const Duration(milliseconds: 300));
      final v2 = painterOf(tester).weakPulse;

      expect(v1, isNot(v0));
      expect(v2, isNot(v1));

      // Stop the pulse so no ticker is active at teardown.
      await tester.pumpWidget(host(weakSignal: false));
      await tester.pump();
    });

    testWidgets('pulse stays at full alpha while weakSignal is false',
        (tester) async {
      await tester.pumpWidget(host(weakSignal: false));

      expect(painterOf(tester).weakPulse, 1.0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(painterOf(tester).weakPulse, 1.0);
    });

    testWidgets('pulse stops when weakSignal clears', (tester) async {
      await tester.pumpWidget(host(weakSignal: true));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(host(weakSignal: false));
      await tester.pump();
      final stopped = painterOf(tester).weakPulse;
      await tester.pump(const Duration(milliseconds: 300));
      expect(painterOf(tester).weakPulse, stopped);
    });
  });
}
