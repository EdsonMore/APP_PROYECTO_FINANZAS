import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Línea de runway (una serie, sin ejes ni tooltips). Cada null corta el trazo;
/// un tramo de un solo punto se dibuja como punto. Escala Y de 0 al máximo
/// visible; los valores con tope (999) quedan arriba.
class RunwayLine extends CustomPainter {
  const RunwayLine({required this.series, required this.color});
  final List<int?> series;
  final Color color;

  /// Tramos continuos: listas de (índice, valor).
  static List<List<(int, int)>> segments(List<int?> series) {
    final out = <List<(int, int)>>[];
    var current = <(int, int)>[];
    for (final (i, v) in series.indexed) {
      if (v == null) {
        if (current.isNotEmpty) out.add(current);
        current = [];
      } else {
        current.add((i, v));
      }
    }
    if (current.isNotEmpty) out.add(current);
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (series.nonNulls.isEmpty) return;
    final max = series.nonNulls.reduce((a, b) => b > a ? b : a);
    const stroke = 2.0;
    // Margen de medio trazo para que la línea no se corte en los bordes.
    final h = size.height - stroke;
    double x(int i) => series.length == 1 ? size.width / 2 : i * size.width / (series.length - 1);
    double y(int v) => stroke / 2 + h - (max == 0 ? 0 : v / max * h);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = color;
    for (final seg in segments(series)) {
      if (seg.length == 1) {
        canvas.drawCircle(Offset(x(seg.first.$1), y(seg.first.$2)), stroke, dot);
        continue;
      }
      final path = Path()..moveTo(x(seg.first.$1), y(seg.first.$2));
      for (final (i, v) in seg.skip(1)) {
        path.lineTo(x(i), y(v));
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(RunwayLine old) => old.color != color || !listEquals(old.series, series);
}
