import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Racing-gauge painter: dark carbon dial, 270° sweep from 225° to 495°
/// (start bottom-left), ticks + digits, glowing red needle, thin red peak
/// marker, redline arc over the last 10% of the range, and an amber
/// weak-signal dot.
///
/// Purely declarative: every frame is fully described by [rangeKmh],
/// [speedFraction], [peakFraction] and [weakSignal]. Per-frame needle motion
/// is driven by repainting with new fractions (see `SpeedoGauge`), so the
/// whole screen never rebuilds during the animation.
class GaugePainter extends CustomPainter {
  const GaugePainter({
    required this.rangeKmh,
    required this.speedFraction,
    required this.peakFraction,
    required this.weakSignal,
  });

  /// Gauge full-scale value in km/h.
  final double rangeKmh;

  /// Needle position as a fraction (0..1, clamped) of [rangeKmh].
  final double speedFraction;

  /// Peak marker position as a fraction (0..1, clamped) of [rangeKmh].
  final double peakFraction;

  /// Whether the GPS signal is weak (accuracy worse than 50 m).
  final bool weakSignal;

  /// Start of the sweep: 225° (bottom-left).
  static const double startAngleDeg = 225;

  /// Sweep extent: 270° (ends at 495°, bottom-right).
  static const double sweepAngleDeg = 270;

  static const Color _dialColor = Color(0xFF141416);
  static const Color _tickColor = Color(0xFFE8E8EA);
  static const Color _redlineColor = Color(0xFFFF3B30);
  static const Color _amberColor = Color(0xFFFFB300);

  static double _degToRad(double deg) => deg * math.pi / 180;

  /// Angle (radians) for [fraction] along the sweep.
  static double angleForFraction(double fraction) =>
      _degToRad(startAngleDeg + sweepAngleDeg * fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;

    _paintDial(canvas, center, radius);
    _paintTicksAndDigits(canvas, center, radius);
    _paintPeakMarker(canvas, center, radius);
    _paintNeedle(canvas, center, radius);
    if (weakSignal) {
      _paintWeakSignalDot(canvas, center, radius);
    }
  }

  void _paintDial(Canvas canvas, Offset center, double radius) {
    final dialPaint = Paint()..color = _dialColor;
    canvas.drawCircle(center, radius, dialPaint);

    // Redline arc over the last 10% of the range.
    final redlinePaint = Paint()
      ..color = _redlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.045
      ..strokeCap = StrokeCap.butt;
    final arcRect = Rect.fromCircle(center: center, radius: radius * 0.90);
    canvas.drawArc(
      arcRect,
      angleForFraction(0.9),
      _degToRad(sweepAngleDeg * 0.1),
      false,
      redlinePaint,
    );
  }

  void _paintTicksAndDigits(Canvas canvas, Offset center, double radius) {
    final range = rangeKmh.round();
    if (range <= 0) return;

    final tickPaint = Paint()
      ..color = _tickColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final digitStyle = ui.TextStyle(
      color: _tickColor,
      fontSize: radius * 0.10,
      fontWeight: FontWeight.w600,
    );

    final outerR = radius * 0.86;
    for (var kmh = 0; kmh <= range; kmh += 10) {
      final isMajor = kmh % 20 == 0;
      final hasLabel = kmh % 40 == 0;
      final fraction = kmh / range;
      final angle = angleForFraction(fraction);
      final cos = math.cos(angle);
      final sin = math.sin(angle);

      final innerR = isMajor ? outerR - radius * 0.10 : outerR - radius * 0.05;
      tickPaint.strokeWidth = isMajor ? 3 : 1.5;
      canvas.drawLine(
        center + Offset(cos * innerR, sin * innerR),
        center + Offset(cos * outerR, sin * outerR),
        tickPaint,
      );

      if (hasLabel) {
        final labelR = innerR - radius * 0.09;
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: TextAlign.center),
        )
          ..pushStyle(digitStyle)
          ..addText('$kmh');
        final paragraph = builder.build()
          ..layout(ui.ParagraphConstraints(width: radius * 0.34));
        final labelCenter = center + Offset(cos * labelR, sin * labelR);
        canvas.drawParagraph(
          paragraph,
          labelCenter -
              Offset(paragraph.width / 2, paragraph.height / 2),
        );
      }
    }
  }

  void _paintPeakMarker(Canvas canvas, Offset center, double radius) {
    final fraction = peakFraction.clamp(0.0, 1.0);
    if (fraction <= 0) return;
    final angle = angleForFraction(fraction);
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final markerPaint = Paint()
      ..color = _redlineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + Offset(cos * radius * 0.62, sin * radius * 0.62),
      center + Offset(cos * radius * 0.86, sin * radius * 0.86),
      markerPaint,
    );
  }

  void _paintNeedle(Canvas canvas, Offset center, double radius) {
    final fraction = speedFraction.clamp(0.0, 1.0);
    final angle = angleForFraction(fraction);
    final tip = center +
        Offset(
          math.cos(angle) * radius * 0.78,
          math.sin(angle) * radius * 0.78,
        );

    // Glowing red needle: blurred underlay + crisp core.
    final glowPaint = Paint()
      ..color = _redlineColor.withValues(alpha: 0.85)
      ..strokeWidth = radius * 0.05
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.04);
    canvas.drawLine(center, tip, glowPaint);

    final corePaint = Paint()
      ..color = _redlineColor
      ..strokeWidth = radius * 0.022
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip, corePaint);

    // Center hub.
    final hubPaint = Paint()..color = const Color(0xFF2A2A2E);
    canvas.drawCircle(center, radius * 0.07, hubPaint);
    final hubRingPaint = Paint()
      ..color = _redlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius * 0.07, hubRingPaint);
  }

  void _paintWeakSignalDot(Canvas canvas, Offset center, double radius) {
    final dotCenter = center + Offset(0, -radius * 0.42);
    final glowPaint = Paint()
      ..color = _amberColor.withValues(alpha: 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.03);
    canvas.drawCircle(dotCenter, radius * 0.045, glowPaint);
    final dotPaint = Paint()..color = _amberColor;
    canvas.drawCircle(dotCenter, radius * 0.028, dotPaint);
  }

  @override
  bool shouldRepaint(GaugePainter oldDelegate) =>
      oldDelegate.rangeKmh != rangeKmh ||
      oldDelegate.speedFraction != speedFraction ||
      oldDelegate.peakFraction != peakFraction ||
      oldDelegate.weakSignal != weakSignal;
}
