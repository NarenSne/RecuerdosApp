import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marcador de mapa: un girasol con tallo. La punta del tallo es el lugar.
class Sunflower extends StatelessWidget {
  const Sunflower({super.key, this.size = 44});

  /// Ancho de la flor. El alto total es [size] * [heightFactor].
  final double size;
  static const heightFactor = 1.35;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Girasol que marca el lugar',
      child: CustomPaint(
        size: Size(size, size * heightFactor),
        painter: _SunflowerPainter(),
      ),
    );
  }
}

class _SunflowerPainter extends CustomPainter {
  static const _petalBack = Color(0xFFE59A0B);
  static const _petalFront = Color(0xFFFFC627);
  static const _centerDark = Color(0xFF4A2C14);
  static const _centerRing = Color(0xFF7A4A1F);
  static const _seed = Color(0xFFA06A2C);
  static const _stem = Color(0xFF3F7D3A);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final head = Offset(r, r);

    // Tallo con una hoja, hasta la punta exacta del lugar.
    final stem = Paint()
      ..color = _stem
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(r, r * 1.5), Offset(r, size.height - 1), stem);
    final leaf = Path()
      ..moveTo(r, size.height * 0.86)
      ..quadraticBezierTo(
        r + r * 0.55,
        size.height * 0.78,
        r + r * 0.62,
        size.height * 0.70,
      )
      ..quadraticBezierTo(
        r + r * 0.15,
        size.height * 0.72,
        r,
        size.height * 0.86,
      );
    canvas.drawPath(leaf, Paint()..color = _stem);

    // Sombra suave para que se lea sobre cualquier mapa.
    canvas.drawCircle(
      head.translate(0, r * 0.06),
      r * 0.98,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    void petals(int count, double offset, Color color, double length) {
      final paint = Paint()..color = color;
      for (var i = 0; i < count; i++) {
        final a = offset + i * 2 * math.pi / count;
        canvas.save();
        canvas.translate(head.dx, head.dy);
        canvas.rotate(a);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, -r * (0.42 + length / 2)),
            width: r * 0.36,
            height: r * length,
          ),
          paint,
        );
        canvas.restore();
      }
    }

    petals(14, math.pi / 14, _petalBack, 0.56);
    petals(14, 0, _petalFront, 0.54);

    canvas.drawCircle(head, r * 0.44, Paint()..color = _centerRing);
    canvas.drawCircle(head, r * 0.36, Paint()..color = _centerDark);

    // Semillas en espiral.
    final seed = Paint()..color = _seed;
    const golden = 2.39996;
    for (var i = 1; i < 22; i++) {
      final d = r * 0.075 * math.sqrt(i.toDouble());
      if (d > r * 0.32) break;
      canvas.drawCircle(
        head + Offset(math.cos(i * golden) * d, math.sin(i * golden) * d),
        r * 0.035,
        seed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
