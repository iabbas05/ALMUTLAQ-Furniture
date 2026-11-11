import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:london_showroom/room_geometry.dart';
import 'package:london_showroom/room_document.dart';
import 'package:london_showroom/app_release.dart';

void main() {
  test(
    'Arabic, Persian, and English measurements use the same physical size',
    () {
      expect(parseMeasurement('٤٫٢٠', metres: true), closeTo(420, .00001));
      expect(parseMeasurement('۴٫۲۰', metres: true), closeTo(420, .00001));
      expect(parseMeasurement('4.20', metres: true), closeTo(420, .00001));
      expect(parseMeasurement('420'), 420);
      for (final v in ['NaN', 'Infinity', '-4', '4m', '']) {
        expect(parseMeasurement(v), isNull);
      }
    },
  );

  test('A rotated footprint stays inside without stretching furniture', () {
    final p = RoomPiece(furnitureSizes.first, 5, 5, 90);
    final contained = p.contained(400, 500)!;
    expect(contained.fits(400, 500, 280), isTrue);
    expect(contained.product.width, 210);
    expect(contained.product.depth, 103);
    expect(
      RoomPiece(furnitureSizes.first, 50, 50, 0).contained(100, 100),
      isNull,
    );
  });

  test('Wire round-trip preserves metres, placement and model version', () {
    final doc = RoomDocument(400, 500, 280, [], [
      RoomPiece(furnitureSizes.first, 200, 120, 90, modelVersion: 'test-v1'),
    ]);
    final wire = doc.toWire();
    expect(wire['room'], {'width': 4.0, 'depth': 5.0, 'height': 2.8});
    expect((wire['items'] as List).first['position'], {'x': 2.0, 'z': 1.2});
    final restored = RoomDocument.fromWire(
      jsonDecode(doc.encode()) as Map<String, dynamic>,
    );
    expect(restored.pieces.single.angle, 90);
    expect(restored.pieces.single.modelVersion, 'test-v1');
    expect(restored.width, 400);
  });

  test('The complete furniture footprint is validated before sending', () {
    final doc = RoomDocument(400, 500, 280, [], [
      RoomPiece(furnitureSizes.first, 0, 0, 0),
    ]);
    expect(doc.toWire, throwsFormatException);
  });

  test('Release downloads only use the exact repository and matching tag', () {
    Map<String, dynamic> release(String url) => {
      'tag_name': 'app-v0.8.0-b8',
      'draft': false,
      'body': 'Preview',
      'assets': [
        {'name': 'Almutlaq.apk', 'size': 100, 'browser_download_url': url},
      ],
    };
    const correct =
        'https://github.com/iabbas05/ALMUTLAQ-Furniture/releases/download/app-v0.8.0-b8/Almutlaq.apk';
    expect(AppRelease.parse(release(correct))!.build, 8);
    for (final bad in [
      correct.replaceFirst('https:', 'http:'),
      correct.replaceFirst('github.com', 'github.com.attacker.example'),
      correct.replaceFirst('app-v0.8.0-b8/', 'app-v0.7.0-b7/'),
      correct.replaceFirst('iabbas05/', 'other/'),
    ]) {
      expect(AppRelease.parse(release(bad)), isNull);
    }
  });
}
