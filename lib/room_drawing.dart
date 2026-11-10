import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'room_geometry.dart';

enum Wall { top, right, bottom, left }

class Opening {
  const Opening(
    this.wall,
    this.offset,
    this.width,
    this.window,
    this.sill,
    this.height,
    this.reverse,
  );
  final Wall wall;
  final int offset, width, sill, height;
  final bool window, reverse;

  Map<String, Object> toJson() => {
    'wall': wall.index,
    'offset': offset,
    'width': width,
    'window': window,
    'sill': sill,
    'height': height,
    'reverse': reverse,
  };

  static Opening fromJson(Map<String, dynamic> data) => Opening(
    Wall.values[data['wall'] as int],
    data['offset'] as int,
    data['width'] as int,
    data['window'] as bool,
    data['sill'] as int,
    data['height'] as int,
    data['reverse'] as bool,
  );

  bool fits(int w, int l, int roomHeight) {
    final span = wall == Wall.top || wall == Wall.bottom ? w : l;
    return offset >= 0 &&
        width > 0 &&
        offset + width <= span &&
        sill >= 0 &&
        height > 0 &&
        sill + height <= roomHeight;
  }

  (Offset, Offset, Offset) line(double w, double l) => switch (wall) {
    Wall.top => (
      Offset(offset.toDouble(), 0),
      Offset((offset + width).toDouble(), 0),
      const Offset(0, 1),
    ),
    Wall.bottom => (
      Offset(offset.toDouble(), l),
      Offset((offset + width).toDouble(), l),
      const Offset(0, -1),
    ),
    Wall.left => (
      Offset(0, offset.toDouble()),
      Offset(0, (offset + width).toDouble()),
      const Offset(1, 0),
    ),
    Wall.right => (
      Offset(w, offset.toDouble()),
      Offset(w, (offset + width).toDouble()),
      const Offset(-1, 0),
    ),
  };
}

class RoomDrawing extends CustomPainter {
  const RoomDrawing(
    this.pieces,
    this.openings,
    this.selected,
    this.width,
    this.length,
  );
  final List<RoomPiece> pieces;
  final List<Opening> openings;
  final int selected, width, length;

  static const ink = Color(0xff554c42);
  static const upholstery = Color(0xffe7d8c0);
  static const cushion = Color(0xfff5e9d5);
  static const teal = Color(0xff236450);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / width;
    canvas.scale(scale);
    final room = Rect.fromLTWH(0, 0, width.toDouble(), length.toDouble());
    canvas.drawRect(room, Paint()..color = const Color(0xffe9ddc9));
    for (var y = 0.0; y < length; y += 23) {
      canvas.drawLine(
        Offset(0, y),
        Offset(width.toDouble(), y),
        Paint()
          ..color = const Color(0xffd5c4aa)
          ..strokeWidth = .7 / scale,
      );
      final stagger = ((y / 23).round() % 2) * 43.0;
      for (var x = stagger; x < width; x += 86) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + 23, length.toDouble())),
          Paint()
            ..color = const Color(0xffd5c4aa)
            ..strokeWidth = .7 / scale,
        );
      }
    }
    canvas.save();
    canvas.clipRect(room);
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.angle * math.pi / 180);
      final w = p.product.width.toDouble(), d = p.product.depth.toDouble();
      final box = Rect.fromCenter(center: Offset.zero, width: w, height: d);
      final outer = RRect.fromRectAndRadius(box, Radius.circular(d * .12));
      canvas.drawRRect(
        outer.shift(const Offset(4, 6)),
        Paint()..color = const Color(0x455a4431),
      );
      canvas.drawRRect(outer, Paint()..color = upholstery);
      void panel(double x, double y, double pw, double pd, Color color) {
        final rect = Rect.fromLTWH(
          box.left + x * w,
          box.top + y * d,
          pw * w,
          pd * d,
        );
        final rounded = RRect.fromRectAndRadius(
          rect,
          Radius.circular(d * .075),
        );
        canvas.drawRRect(rounded, Paint()..color = color);
        canvas.drawRRect(
          rounded,
          Paint()
            ..color = const Color(0xffae9a80)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .65 / scale,
        );
      }

      panel(.10, .04, .80, .23, const Color(0xffc6b091));
      panel(.015, .10, .15, .84, upholstery);
      panel(.835, .10, .15, .84, upholstery);
      final seats = p.product.sku == '6_14_5' ? 1 : 3;
      for (var seat = 0; seat < seats; seat++) {
        panel(.18 + seat * .64 / seats, .30, .62 / seats, .61, cushion);
      }
      if (i == selected) {
        final invalid = p.margins(width, length).any((v) => v < -1e-4);
        canvas.drawRRect(
          outer,
          Paint()
            ..color = invalid ? Colors.red.shade700 : teal
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / scale,
        );
      }
      canvas.restore();
    }
    canvas.restore();
    canvas.drawRect(
      room,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale,
    );
    for (final opening in openings) {
      final (a, b, normal) = opening.line(room.width, room.height);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xffe9ddc9)
          ..strokeWidth = 4 / scale,
      );
      if (opening.window) {
        final window = Paint()
          ..color = const Color(0xff447f9a)
          ..strokeWidth = 1.6 / scale;
        canvas.drawLine(a, b, window);
        canvas.drawLine(
          a + normal * (3 / scale),
          b + normal * (3 / scale),
          window,
        );
      } else {
        final hinge = opening.reverse ? b : a;
        final edge = opening.reverse ? a : b;
        final arcEnd = hinge + normal * opening.width.toDouble();
        final angle = (edge - hinge).direction;
        final turn = (arcEnd - hinge).direction - angle;
        final sweep = math.atan2(math.sin(turn), math.cos(turn));
        final stroke = Paint()
          ..color = ink
          ..strokeWidth = 1.1 / scale
          ..style = PaintingStyle.stroke;
        canvas.drawLine(hinge, arcEnd, stroke);
        canvas.drawArc(
          Rect.fromCircle(center: hinge, radius: opening.width.toDouble()),
          angle,
          sweep,
          false,
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant RoomDrawing oldDelegate) => true;
}
