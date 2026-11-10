import 'dart:math' as math;

class FurnitureSize {
  const FurnitureSize(
    this.sku,
    this.en,
    this.ar,
    this.width,
    this.depth,
    this.height,
  );
  final String sku, en, ar;
  final int width, depth, height;
}

const furnitureSizes = [
  FurnitureSize(
    '10_14_3',
    'London three-seater',
    'كنبة لندن ثلاثية',
    210,
    103,
    100,
  ),
  FurnitureSize('6_14_5', 'London chair', 'كرسي لندن', 84, 95, 94),
  FurnitureSize(
    '23_88_1',
    'Warm Beige three-seater',
    'كنبة بيج دافئ',
    230,
    101,
    78,
  ),
];

class RoomPiece {
  const RoomPiece(this.product, this.x, this.y, this.angle);
  final FurnitureSize product;
  final double x, y;
  final int angle;

  RoomPiece move(double x, double y) => RoomPiece(product, x, y, angle);
  RoomPiece turn() => RoomPiece(product, x, y, (angle + 15) % 360);
  RoomPiece replace(FurnitureSize next) => RoomPiece(next, x, y, angle);

  List<math.Point<double>> get corners {
    final radians = angle * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return [
      for (final (a, b) in [
        (-product.width / 2, -product.depth / 2),
        (product.width / 2, -product.depth / 2),
        (product.width / 2, product.depth / 2),
        (-product.width / 2, product.depth / 2),
      ])
        math.Point(x + a * cos - b * sin, y + a * sin + b * cos),
    ];
  }

  List<double> margins(int width, int length) {
    final points = corners;
    return [
      points.map((p) => p.x).reduce(math.min),
      points.map((p) => p.y).reduce(math.min),
      width - points.map((p) => p.x).reduce(math.max),
      length - points.map((p) => p.y).reduce(math.max),
    ];
  }

  bool overlaps(RoomPiece other) {
    final a = corners;
    final b = other.corners;
    for (final polygon in [a, b]) {
      for (var i = 0; i < 2; i++) {
        final edge = polygon[i + 1] - polygon[i];
        final axis = math.Point(-edge.y, edge.x);
        double project(math.Point<double> p) => p.x * axis.x + p.y * axis.y;
        final p = a.map(project).toList();
        final q = b.map(project).toList();
        if (p.reduce(math.max) <= q.reduce(math.min) + 1e-7 ||
            q.reduce(math.max) <= p.reduce(math.min) + 1e-7)
          return false;
      }
    }
    return true;
  }

  Map<String, Object> toJson() => {
    'sku': product.sku,
    'x': x,
    'y': y,
    'angle': angle,
  };

  static RoomPiece fromJson(Map<String, dynamic> data) {
    final item = furnitureSizes.firstWhere((p) => p.sku == data['sku']);
    final x = (data['x'] as num).toDouble();
    final y = (data['y'] as num).toDouble();
    if (!x.isFinite || !y.isFinite)
      throw const FormatException('Invalid position');
    return RoomPiece(item, x, y, (data['angle'] as int) % 360);
  }
}
