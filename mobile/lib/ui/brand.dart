import 'package:flutter/material.dart';

// Radian brand palette, shared with the web dashboard.
const nightInk = Color(0xFF0B1220);
const radianBlue = Color(0xFF2563EB);
const signalBlue = Color(0xFF4F8BFF); // the mark and accents on dark grounds
const liveAmber = Color(0xFFF59E0B); // reserved for the live vehicle
const paper = Color(0xFFF6F8FB);

const monoFamily = 'Geist Mono';

/// The Radian "Sweep": a sector exactly one radian wide (its arc is as long
/// as its radius). Dispatch sweeping a search radius from an origin and
/// landing on a live vehicle, the amber dot.
class RadianMark extends StatelessWidget {
  const RadianMark({super.key, this.size = 48, this.color, this.ground, this.simplified});

  final double size;

  /// The sweep's colour; defaults to Radian Blue on light, Signal on dark.
  final Color? color;

  /// What the mark sits on, used for the ring that separates the vehicle dot.
  final Color? ground;

  /// Drops the inner arc and pivot; defaults to true below 40 px.
  final bool? simplified;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Radian',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _SweepPainter(
          color: color ?? (dark ? signalBlue : radianBlue),
          ground: ground ?? Theme.of(context).scaffoldBackgroundColor,
          simplified: simplified ?? size < 40,
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.color, required this.ground, required this.simplified});

  final Color color;
  final Color ground;
  final bool simplified;

  // Geometry in a 64-unit box: origin (15, 46), radius 34, 1 rad sweep.
  static const _origin = Offset(15, 46);
  static const _start = Offset(49, 46);
  static const _vehicle = Offset(33.37, 17.39);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    final wedge = Path()
      ..moveTo(_origin.dx, _origin.dy)
      ..lineTo(_start.dx, _start.dy)
      ..arcToPoint(_vehicle, radius: const Radius.circular(34), clockwise: false)
      ..close();
    canvas.drawPath(wedge, Paint()..color = color.withValues(alpha: simplified ? 0.28 : 0.2));

    if (!simplified) {
      final inner = Path()
        ..moveTo(35, 46)
        ..arcToPoint(const Offset(25.81, 29.17), radius: const Radius.circular(20), clockwise: false);
      canvas.drawPath(inner, Paint.from(stroke)
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.6));
    }

    final arc = Path()
      ..moveTo(_start.dx, _start.dy)
      ..arcToPoint(_vehicle, radius: const Radius.circular(34), clockwise: false);
    canvas.drawPath(arc, Paint.from(stroke)..strokeWidth = simplified ? 6 : 5);
    canvas.drawLine(_origin, _start, Paint.from(stroke)..strokeWidth = simplified ? 5 : 3);
    if (!simplified) canvas.drawCircle(_origin, 3.5, Paint()..color = color);

    canvas.drawCircle(_vehicle, simplified ? 8.5 : 7.25, Paint()..color = ground);
    canvas.drawCircle(_vehicle, simplified ? 7 : 6, Paint()..color = liveAmber);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.color != color || old.ground != ground || old.simplified != simplified;
}

/// The lowercase "radian" wordmark.
class RadianWordmark extends StatelessWidget {
  const RadianWordmark({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'radian',
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.045 * size,
        height: 1,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
