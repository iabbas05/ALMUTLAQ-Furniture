import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'room_drawing.dart';
import 'room_geometry.dart';

typedef Point3 = ({double x, double y, double z});
typedef RoomFace = ({List<Point3> points, Color color});

Point3 point(double x, double y, double z) => (x: x, y: y, z: z);

class LondonMesh {
  static final _cache = <String, List<RoomFace>>{};
  static Future<List<RoomFace>> load([
    String path = 'assets/london-10_14_3.glb',
  ]) async {
    final cached = _cache[path];
    if (cached != null) return cached;
    final result = await _decode(path);
    _cache[path] = result;
    return result;
  }

  static Future<List<RoomFace>> _decode(String path) async {
    final asset = await rootBundle.load(path);
    final bytes = Uint8List.sublistView(asset);
    final size = asset.getUint32(12, Endian.little);
    final gltf = jsonDecode(utf8.decode(bytes.sublist(20, 20 + size))) as Map;
    final List nodes = gltf['nodes'] as List;
    final List meshes = gltf['meshes'] as List;
    final List materials = gltf['materials'] as List;
    final List accessors = gltf['accessors'] as List;
    final List views = gltf['bufferViews'] as List;
    int start(Map accessor) =>
        28 +
        size +
        ((views[accessor['bufferView'] as int] as Map)['byteOffset'] as int? ??
            0) +
        (accessor['byteOffset'] as int? ?? 0);
    final faces = <RoomFace>[];
    for (final node in nodes.cast<Map>()) {
      final shift = (node['translation'] as List).cast<num>();
      final primitive =
          ((meshes[node['mesh'] as int] as Map)['primitives'] as List).first
              as Map;
      final positions =
          accessors[(primitive['attributes'] as Map)['POSITION'] as int] as Map;
      final indices = accessors[primitive['indices'] as int] as Map;
      if (positions['componentType'] != 5126 ||
          indices['componentType'] != 5123) {
        throw const FormatException('Unsupported London mesh.');
      }
      final material =
          (materials[primitive['material'] as int]
                  as Map)['pbrMetallicRoughness']
              as Map;
      final rgba = (material['baseColorFactor'] as List).cast<num>();
      int channel(int i) =>
          (math.pow(rgba[i], 1 / 2.2) * 255).round().clamp(0, 255).toInt();
      final color = Color.fromARGB(255, channel(0), channel(1), channel(2));
      final vertices = [
        for (var i = 0; i < (positions['count'] as int); i++)
          point(
            (asset.getFloat32(start(positions) + i * 12, Endian.little) +
                    shift[0]) *
                100,
            -(asset.getFloat32(start(positions) + i * 12 + 8, Endian.little) +
                    shift[2]) *
                100,
            (asset.getFloat32(start(positions) + i * 12 + 4, Endian.little) +
                    shift[1]) *
                100,
          ),
      ];
      for (var i = 0; i < (indices['count'] as int); i += 3) {
        faces.add((
          points: [
            for (var j = 0; j < 3; j++)
              vertices[asset.getUint16(
                start(indices) + (i + j) * 2,
                Endian.little,
              )],
          ],
          color: color,
        ));
      }
    }
    return faces;
  }
}

class RoomOrbit extends StatefulWidget {
  const RoomOrbit({
    super.key,
    required this.width,
    required this.length,
    required this.height,
    required this.openings,
    required this.pieces,
    required this.arabic,
  });
  final int width, length, height;
  final List<Opening> openings;
  final List<RoomPiece> pieces;
  final bool arabic;

  @override
  State<RoomOrbit> createState() => _RoomOrbitState();
}

class _RoomOrbitState extends State<RoomOrbit> {
  late final model = () async {
    final result = <String, List<RoomFace>>{};
    for (final product in furnitureSizes) {
      if (product.modelAsset != null)
        result[product.sku] = await LondonMesh.load(product.modelAsset!);
    }
    return result;
  }();
  double yaw = math.pi / 4, elevation = .55, zoom = 1, baseZoom = 1;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<Map<String, List<RoomFace>>>(
    future: model,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 315,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 315,
            child: ClipRect(
              child: GestureDetector(
                onScaleStart: (_) => baseZoom = zoom,
                onScaleUpdate: (event) => setState(() {
                  if (event.pointerCount == 1) {
                    yaw =
                        (yaw - event.focalPointDelta.dx * .014) % (2 * math.pi);
                    elevation = (elevation + event.focalPointDelta.dy * .007)
                        .clamp(.22, 1.24)
                        .toDouble();
                  }
                  zoom = (baseZoom * event.scale).clamp(.65, 2.6).toDouble();
                }),
                child: CustomPaint(
                  painter: _OrbitPainter(
                    widget,
                    snapshot.data ?? const {},
                    yaw,
                    elevation,
                    zoom,
                  ),
                ),
              ),
            ),
          ),
          Text(
            widget.arabic
                ? 'اسحب للدوران وقرّب بإصبعين'
                : 'Drag to orbit and pinch to zoom',
          ),
          if (snapshot.hasError)
            Text(
              widget.arabic
                  ? 'تعذّر تحميل موديل London. يُعرض شكل تقريبي.'
                  : 'Model unavailable. Please retry.',
            ),
          TextButton(
            onPressed: () => setState(() {
              yaw = math.pi / 4;
              elevation = .55;
              zoom = 1;
            }),
            child: Text(widget.arabic ? 'رجّع زاوية العرض' : 'Reset view'),
          ),
        ],
      );
    },
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.room, this.london, this.yaw, this.elevation, this.zoom);
  final RoomOrbit room;
  final Map<String, List<RoomFace>> london;
  final double yaw, elevation, zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final w = room.width.toDouble(),
        l = room.length.toDouble(),
        h = room.height.toDouble();
    final c = math.cos(yaw), s = math.sin(yaw);
    final e = math.sin(elevation), up = math.cos(elevation);
    final horizontal = w * c.abs() + l * s.abs();
    final vertical = (w * s.abs() + l * c.abs()) * e + h * up;
    final scale =
        math.min(
          (size.width - 22) / horizontal,
          (size.height - 22) / vertical,
        ) *
        zoom;
    final centre = size.center(Offset(0, h * up * scale / 2));
    Offset screen(Point3 p) {
      final x = p.x - w / 2, y = p.y - l / 2;
      return centre +
          Offset(x * c - y * s, (x * s + y * c) * e - p.z * up) * scale;
    }

    double depth(Point3 p) => (p.x * s + p.y * c) * up + p.z * e;
    void draw(List<Point3> points, Color color) {
      final path = Path()..addPolygon(points.map(screen).toList(), true);
      // Adjacent triangle antialiasing exposes the background as false mesh seams.
      canvas.drawPath(path, Paint()..color = color..isAntiAlias = false);
    }
    draw([
      point(0, 0, 0),
      point(w, 0, 0),
      point(w, l, 0),
      point(0, l, 0),
    ], const Color(0xffd9bc96));

    void wall(Wall side, double span) {
      Point3 at(double t, double z) => switch (side) {
        Wall.top => point(t, 0, z),
        Wall.bottom => point(t, l, z),
        Wall.left => point(0, t, z),
        Wall.right => point(w, t, z),
      };
      void panel(double a, double b, double bottom, double top, Color color) {
        if (a < b && bottom < top)
          draw([at(a, bottom), at(b, bottom), at(b, top), at(a, top)], color);
      }

      const wallColor = Color(0xffeee4d7);
      final cuts = room.openings.where((o) => o.wall == side).toList()
        ..sort((a, b) => a.offset.compareTo(b.offset));
      var cursor = 0.0;
      for (final opening in cuts) {
        final a = opening.offset.toDouble(), b = a + opening.width;
        panel(cursor, a, 0, h, wallColor);
        panel(a, b, 0, opening.sill.toDouble(), wallColor);
        panel(a, b, (opening.sill + opening.height).toDouble(), h, wallColor);
        if (opening.window) {
          panel(
            a,
            b,
            opening.sill.toDouble(),
            (opening.sill + opening.height).toDouble(),
            const Color(0xff9bc6d3),
          );
        }
        cursor = b;
      }
      panel(cursor, span, 0, h, wallColor);
    }

    wall(s >= 0 ? Wall.left : Wall.right, l);
    wall(c >= 0 ? Wall.top : Wall.bottom, w);

    final surfaces = <({List<Point3> vertices, Color color, double depth})>[];
    void add(List<Point3> vertices, Color color) {
      final a = vertices[0], b = vertices[1], d = vertices[2];
      final ab = point(b.x - a.x, b.y - a.y, b.z - a.z),
          ac = point(d.x - a.x, d.y - a.y, d.z - a.z);
      final n = point(
        ab.y * ac.z - ab.z * ac.y,
        ab.z * ac.x - ab.x * ac.z,
        ab.x * ac.y - ab.y * ac.x,
      );
      final norm = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      if (norm < .000001 || n.x * s * up + n.y * c * up + n.z * e <= 0) return;
      final brightness = ((n.z * .66 - n.x * .3 - n.y * .18) / norm)
          .clamp(0, 1)
          .toDouble();
      surfaces.add((
        vertices: vertices,
        color: Color.lerp(
          color,
          const Color(0xff685646),
          .34 * (1 - brightness),
        )!,
        depth: vertices.map(depth).reduce((a, b) => a + b) / vertices.length,
      ));
    }

    for (final piece in room.pieces) {
      final theta = piece.angle * math.pi / 180;
      final pc = math.cos(theta), ps = math.sin(theta);
      Point3 at(Point3 p) => point(
        piece.x + p.x * pc - p.y * ps,
        piece.y + p.x * ps + p.y * pc,
        p.z,
      );
      final faces = london[piece.product.sku];
      if (faces == null) continue;
      for (final face in faces) {
        add(face.points.map(at).toList(), face.color);
      }
    }
    surfaces.sort((a, b) => a.depth.compareTo(b.depth));
    for (final face in surfaces) {
      draw(face.vertices, face.color);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => true;
}
