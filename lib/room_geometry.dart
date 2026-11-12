import 'dart:math' as math;

class FurnitureSize {
  const FurnitureSize(
    this.sku,
    this.en,
    this.ar,
    this.width,
    this.depth,
    this.height, {
    this.modelAsset,
    this.image,
    this.store = 0,
  });
  final String sku, en, ar;
  final int width, depth, height;
  final int store;
  final String? modelAsset, image;
  String get productId => '${store == 0 ? 'factory' : 'cityw'}:$sku';
}

const furnitureSizes = [
  FurnitureSize(
    '10_14_3',
    'London three-seater',
    'كنبة لندن، ثلاثة مقاعد',
    210,
    103,
    100,
    modelAsset: 'assets/london-10_14_3.glb',
    image:
        'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-1.jpg',
  ),
  FurnitureSize(
    '6_14_5',
    'London chair',
    'كرسي لندن',
    84,
    95,
    94,
    modelAsset: 'assets/london-6_14_5.glb',
    image:
        'https://thefactoryfurniture.com/wp-content/uploads/2026/11/06-14-00005-1.jpg',
  ),
];

/// All planner coordinates are centimetres. Wire coordinates are metres.
double? parseMeasurement(String input, {bool metres = false}) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  var value = input.trim().replaceAll('٫', '.').replaceAll(',', '.');
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
  }
  final n = double.tryParse(value);
  if (n == null || !n.isFinite || n < 0) return null;
  return n * (metres ? 100 : 1);
}

class RoomPiece {
  const RoomPiece(
    this.product,
    this.x,
    this.y,
    this.angle, {
    this.modelVersion,
  });
  final FurnitureSize product;
  final double x, y;
  final int angle;
  final String? modelVersion;

  RoomPiece move(double x, double y) =>
      RoomPiece(product, x, y, angle, modelVersion: modelVersion);
  RoomPiece turn([int step = 15]) => RoomPiece(
    product,
    x,
    y,
    (angle + step) % 360,
    modelVersion: modelVersion,
  );
  RoomPiece replace(FurnitureSize next) => RoomPiece(next, x, y, angle);

  /// Moves the whole footprint inside a room, without changing its size.
  RoomPiece? contained(int width, int length) {
    final gaps = margins(width, length);
    final spanX = width - gaps[0] - gaps[2];
    final spanY = length - gaps[1] - gaps[3];
    if (spanX > width + 1e-7 || spanY > length + 1e-7) return null;
    return move(
      x + math.max(0, -gaps[0]) - math.max(0, -gaps[2]),
      y + math.max(0, -gaps[1]) - math.max(0, -gaps[3]),
    );
  }

  bool fits(int width, int length, int height) =>
      product.height <= height &&
      margins(width, length).every((n) => n >= -1e-7);

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
    if (modelVersion != null) 'modelVersion': modelVersion!,
  };

  static RoomPiece fromJson(Map<String, dynamic> data) {
    final item = furnitureSizes.firstWhere((p) => p.sku == data['sku']);
    final x = (data['x'] as num).toDouble();
    final y = (data['y'] as num).toDouble();
    if (!x.isFinite || !y.isFinite)
      throw const FormatException('Invalid position');
    return RoomPiece(
      item,
      x,
      y,
      (data['angle'] as int) % 360,
      modelVersion: data['modelVersion'] as String?,
    );
  }
}
