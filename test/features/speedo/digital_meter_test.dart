import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/features/speedo/digital_meter.dart';

void main() {
  testWidgets('renders the digital readout and unit label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DigitalMeter(
            speed: 87,
            unit: 'km/h',
            speedFraction: 0.36,
            peakFraction: 0.5,
            weakSignal: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('87'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);
  });

  testWidgets('shows a weak-signal indicator only when weak', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DigitalMeter(
            speed: 0,
            unit: 'km/h',
            speedFraction: 0,
            peakFraction: 0,
            weakSignal: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(DigitalMeter.weakSignalKey), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DigitalMeter(
            speed: 10,
            unit: 'km/h',
            speedFraction: 0.1,
            peakFraction: 0.2,
            weakSignal: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(DigitalMeter.weakSignalKey), findsNothing);
  });

  test('paints without exception across fractions', () {
    final painter = DigitalMeterPainter(
      speedFraction: 0.42,
      peakFraction: 0.7,
      weakSignal: true,
      accent: const Color(0xFFFF3B30),
    );
    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      painter.shouldRepaint(
        DigitalMeterPainter(
          speedFraction: 0.5,
          peakFraction: 0.7,
          weakSignal: true,
          accent: const Color(0xFFFF3B30),
        ),
      ),
      isTrue,
    );
  });
}
