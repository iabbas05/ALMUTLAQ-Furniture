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
    this.height,
    this.perspective,
  );
  final List<RoomPiece> pieces;
  final List<Opening> openings;
  final int selected, width, length, height;
  final bool perspective;

  static const ink = Color(0xff554c42);
  static const upholstery = Color(0xffe7d8c0);
  static const cushion = Color(0xfff5e9d5);
  static const teal = Color(0xff236450);

  @override
  void paint(Canvas canvas, Size size) {
    if (perspective) {
      _paintThreeQuarter(canvas, size);
      return;
    }
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

  void _paintThreeQuarter(Canvas canvas, Size size) {
    final w = width.toDouble(), l = length.toDouble(), h = height.toDouble();
    final scale = math.min(
      (size.width - 24) / ((w + l) * .78),
      (size.height - 24) / ((w + l) * .34 + h * .78),
    );
    final origin = Offset(
      size.width / 2 + (l - w) * .39 * scale,
      12 + h * .78 * scale,
    );
    Offset project(double x, double y, double z) =>
        origin + Offset((x - y) * .78, (x + y) * .34 - z * .78) * scale;
    void surface(List<Offset> points, Color color) => canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()..color = color,
    );
    surface([
      project(0, 0, 0),
      project(w, 0, 0),
      project(w, l, 0),
      project(0, l, 0),
    ], const Color(0xffd8bd98));
    void wall(Wall side, double span) {
      Offset at(double x, double z) =>
          side == Wall.top ? project(x, 0, z) : project(0, x, z);
      void panel(double a, double b, double bottom, double top, Color color) {
        if (b <= a || top <= bottom) return;
        surface([at(a, bottom), at(b, bottom), at(b, top), at(a, top)], color);
      }

      final color = side == Wall.top
          ? const Color(0xfff3ece1)
          : const Color(0xffe6d9c7);
      final cuts = openings.where((o) => o.wall == side).toList()
        ..sort((a, b) => a.offset.compareTo(b.offset));
      var start = 0.0;
      for (final o in cuts) {
        final a = o.offset.toDouble(), b = (o.offset + o.width).toDouble();
        panel(start, a, 0, h, color);
        panel(a, b, 0, o.sill.toDouble(), color);
        panel(a, b, (o.sill + o.height).toDouble(), h, color);
        if (o.window)
          panel(
            a,
            b,
            o.sill.toDouble(),
            (o.sill + o.height).toDouble(),
            const Color(0xff9ac6d4),
          );
        start = b;
      }
      panel(start, span, 0, h, color);
    }

    wall(Wall.left, l);
    wall(Wall.top, w);
    final ordered = pieces.toList()
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    for (final piece in ordered) {
      final theta = piece.angle * math.pi / 180;
      final c = math.cos(theta), s = math.sin(theta);
      Offset at(double x, double y, double z) =>
          project(piece.x + x * c - y * s, piece.y + x * s + y * c, z);
      final pw = piece.product.width.toDouble(),
          pd = piece.product.depth.toDouble(),
          ph = piece.product.height.toDouble();
      void box(
        double x,
        double y,
        double bw,
        double bd,
        double bottom,
        double top,
        Color color,
      ) {
        final a = at(x, y, top),
            b = at(x + bw, y, top),
            c = at(x + bw, y + bd, top),
            d = at(x, y + bd, top);
        surface([
          b,
          c,
          at(x + bw, y + bd, bottom),
          at(x + bw, y, bottom),
        ], Color.lerp(color, Colors.black, .19)!);
        surface([
          c,
          d,
          at(x, y + bd, bottom),
          at(x + bw, y + bd, bottom),
        ], Color.lerp(color, Colors.black, .29)!);
        surface([a, b, c, d], color);
      }

      box(-pw / 2, -pd / 2, pw, pd, 0, ph * .42, upholstery);
      box(-pw / 2, -pd / 2, pw, pd * .22, ph * .42, ph, upholstery);
      final seats = piece.product.sku == '6_14_5' ? 1 : 3;
      for (var i = 0; i < seats; i++) {
        box(
          -pw * .34 + i * pw * .68 / seats,
          -pd * .26,
          pw * .65 / seats,
          pd * .70,
          ph * .42,
          ph * .53,
          cushion,
        );
      }
      box(
        -pw / 2,
        -pd * .36,
        pw * .15,
        pd * .86,
        ph * .42,
        ph * .72,
        upholstery,
      );
      box(
        pw * .35,
        -pd * .36,
        pw * .15,
        pd * .86,
        ph * .42,
        ph * .72,
        upholstery,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RoomDrawing oldDelegate) => true;
}
