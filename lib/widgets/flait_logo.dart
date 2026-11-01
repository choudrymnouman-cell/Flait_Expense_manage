import 'package:flutter/material.dart';

class FlaitLogo extends StatelessWidget {
  const FlaitLogo({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Flait logo',
      image: true,
      child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox.square(
              dimension: size, child: CustomPaint(painter: _LogoPainter()))));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 192, size.height / 192);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 192, 192), const Radius.circular(44)),
        Paint()..color = const Color(0xFF3659C9));
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(38, 86)
          ..lineTo(96, 40)
          ..lineTo(154, 86)
          ..lineTo(154, 149)
          ..lineTo(38, 149)
          ..close(),
        stroke);
    stroke.strokeWidth = 10;
    canvas.drawPath(
        Path()
          ..moveTo(78, 146)
          ..lineTo(78, 103)
          ..lineTo(117, 103)
          ..moveTo(78, 122)
          ..lineTo(107, 122),
        stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
