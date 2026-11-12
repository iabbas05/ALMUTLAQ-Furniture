import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:london_showroom/main.dart';
import 'package:london_showroom/room_orbit.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> font() async {
  final loader = FontLoader('NotoSansArabic');
  loader.addFont(rootBundle.load('assets/NotoSansArabic.ttf'));
  await loader.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(MaterialApp));
    await precacheImage(const AssetImage('assets/london-sofa.jpg'), context);
    await precacheImage(const AssetImage('assets/london-chair.jpg'), context);
  });
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('build/preview')..createSync(recursive: true);
    File(
      '${folder.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Arabic storefront and room render, and English switching works',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await font();
        await LondonMesh.load();
        await LondonMesh.load('assets/london-6_14_5.glb');
      });
      SharedPreferences.setMockInitialValues({'arabic': true});
      final prefs = await SharedPreferences.getInstance(), key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: FurnitureApp(prefs, fetchOnline: false),
        ),
      );
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale!.languageCode, 'ar');
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'store-ar');
      await tester.tap(find.text('كنبة لندن ثلاثية').first);
      await tester.pumpAndSettle();
      expect(find.text('أضف للسلة'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'product-ar');
      await tester.tap(find.text('أضف للسلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.shopping_bag_outlined).last);
      await tester.pumpAndSettle();
      expect(find.text('كنبة لندن ثلاثية'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'bag-ar');
      await tester.tap(find.byIcon(Icons.architecture).last);
      await tester.pumpAndSettle();
      expect(find.byType(RoomOrbit), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'room-ar');
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .locale!
            .languageCode,
        'en',
      );
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'room-en');
    },
  );
  for (final width in [320.0, 768.0]) {
    testWidgets('Arabic layout fits a $width logical pixel screen', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await font();
        await LondonMesh.load();
        await LondonMesh.load('assets/london-6_14_5.glb');
      });
      SharedPreferences.setMockInitialValues({'arabic': true});
      await tester.pumpWidget(
        FurnitureApp(await SharedPreferences.getInstance(), fetchOnline: false),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.architecture).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
