import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Digital speed readout with a thin colored arc ring: the ring fills as
/// speed goes from 0 to the vehicle's gauge maximum, and a red tick marks
/// the peak speed reached. A pulsing amber dot flags a weak GPS signal.
///
/// The big number is the primary display; the ring is the racing accent.
class DigitalMeter extends StatelessWidget {
  const DigitalMeter({
    super.key,
    required this.speed,
    required this.unit,
    required this.speedFraction,
    required this.peakFraction,
    required this.weakSignal,
  });

  /// Current speed, already converted to [unit], as a whole number.
  final int speed;

  /// Unit label (e.g. `km/h`).
  final String unit;

  /// Current speed as a fraction of the gauge maximum (clamped 0..1).
  final double speedFraction;

  /// Peak speed as a fraction of the gauge maximum (clamped 0..1).
  final double peakFraction;

  /// Whether the GPS signal is weak (accuracy > 50 m).
  final bool weakSignal;

  /// Marker for the weak-signal dot (tests).
  static const Key weakSignalKey = Key('digital-meter-weak-signal');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: DigitalMeterPainter(
                speedFraction: speedFraction.clamp(0.0, 1.0),
                peakFraction: peakFraction.clamp(0.0, 1.0),
                weakSignal: weakSignal,
                accent: accent,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      speed.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.28,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -1,
                        shadows: [
                          Shadow(
                            color: accent.withValues(alpha: 0.7),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      unit,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: size * 0.05,
                        letterSpacing: 3,
                      ),
                    ),
                    if (weakSignal) ...[
                      const SizedBox(height: 8),
                      _WeakSignalDot(key: weakSignalKey, accent: accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pulsing amber dot shown while the GPS signal is weak.
class _WeakSignalDot extends StatefulWidget {
  const _WeakSignalDot({super.key, required this.accent});

  final Color accent;

  @override
  State<_WeakSignalDot> createState() => _WeakSignalDotState();
}

class _WeakSignalDotState extends State<_WeakSignalDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_off, size: 12, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            'weak signal',
            style: TextStyle(
              color: Colors.amber.withValues(alpha: 0.9),
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the thin arc ring (background track, filled speed portion, peak
/// tick, and the weak-signal ring tint).
class DigitalMeterPainter extends CustomPainter {
  DigitalMeterPainter({
    required this.speedFraction,
    required this.peakFraction,
    required this.weakSignal,
    required this.accent,
  });

  final double speedFraction;
  final double peakFraction;
  final bool weakSignal;
  final Color accent;

  // 270° sweep starting at 135° (bottom-left), like a racing dial.
  static const double _startAngle = 135 * math.pi / 180;
  static const double _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = size.shortestSide * 0.035;

    // Background track.
    canvas.drawArc(
      rect,
      _startAngle,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    // Filled speed portion, colored from the accent.
    canvas.drawArc(
      rect,
      _startAngle,
      _sweep * speedFraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweep,
          colors: [accent.withValues(alpha: 0.5), accent],
          transform: GradientRotation(_startAngle),
        ).createShader(rect),
    );

    // Peak tick (thin red line across the ring at the peak angle).
    final peakAngle = _startAngle + _sweep * peakFraction;
    final inner = radius - stroke;
    final outer = radius + stroke * 0.5;
    final dir = Offset(math.cos(peakAngle), math.sin(peakAngle));
    canvas.drawLine(
      center + dir * inner,
      center + dir * outer,
      Paint()
        ..color = const Color(0xFFFF3B30)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(DigitalMeterPainter old) =>
      old.speedFraction != speedFraction ||
      old.peakFraction != peakFraction ||
      old.weakSignal != weakSignal ||
      old.accent != accent;
}
