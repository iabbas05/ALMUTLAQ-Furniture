import 'package:flutter_test/flutter_test.dart';
import 'package:london_showroom/product_ar.dart';
import 'package:london_showroom/room_geometry.dart';
import 'package:london_showroom/room_orbit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Unknown products never open an incorrect London model', () async {
    expect(await ProductAR.open('missing'), isFalse);
  });
  test('Android fallback requires a published HTTPS AR URL', () async {
    expect(await ProductAR.open('10_14_3'), isFalse);
    expect(
      await ProductAR.open('6_14_5', website: 'http://example.com'),
      isFalse,
    );
  });
  test('Web handoff carries the selected product and current language', () {
    final uri = ProductAR.websiteUri(
      '6_14_5',
      'https://example.com/ar/?source=app',
      language: 'en',
    );
    expect(uri?.queryParameters, {
      'source': 'app',
      'sku': '6_14_5',
      'lang': 'en',
    });
    expect(ProductAR.websiteUri('missing', 'https://example.com/'), isNull);
    expect(
      ProductAR.websiteUri('10_14_3', 'https://user@example.com/'),
      isNull,
    );
  });
  test('Every AR product bundles a model at its published size', () async {
    for (final m in arModels) {
      final mesh = await LondonMesh.load(m.glb);
      final points = mesh.expand((face) => face.points).toList();
      double extent(Iterable<double> axis) {
        final values = axis.toList()..sort();
        return values.last - values.first;
      }

      expect(
        extent(points.map((p) => p.x)),
        closeTo(m.size.width, .01),
        reason: m.sku,
      );
      expect(
        extent(points.map((p) => p.y)),
        closeTo(m.size.depth, .01),
        reason: m.sku,
      );
      expect(
        extent(points.map((p) => p.z)),
        closeTo(m.size.height, .01),
        reason: m.sku,
      );
    }
  });
  test('AR-only products stay out of the room planner and headset', () {
    final beige = ProductAR.model('23_88_1', 1)!;
    expect(beige.inRoomPlanner, isFalse);
    expect(furnitureSizes.map((p) => p.sku), isNot(contains('23_88_1')));
    expect(ProductAR.model('23_88_1', 0), isNull);
    expect(ProductAR.model('10_14_3', 0)!.inRoomPlanner, isTrue);
    expect(
      ProductAR.websiteUri(
        '23_88_1',
        'https://example.com/',
      )?.queryParameters['sku'],
      '23_88_1',
    );
  });
}
