import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:london_showroom/room_drawing.dart';
import 'package:london_showroom/room_planner.dart';
import 'package:london_showroom/room_orbit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('London mesh retains its published dimensions in the room', () async {
    final mesh = await LondonMesh.load();
    final points = mesh.expand((face) => face.points).toList();
    expect(points, isNotEmpty);
    double extent(List<double> axis) {
      axis.sort();
      return axis.last - axis.first;
    }

    expect(extent(points.map((p) => p.x).toList()), closeTo(210, .01));
    expect(extent(points.map((p) => p.y).toList()), closeTo(103, .01));
    expect(extent(points.map((p) => p.z).toList()), closeTo(100, .01));
  });
  test('Openings respect wall length and available height', () {
    const door = Opening(Wall.top, 50, 90, false, 0, 210, false);
    const window = Opening(Wall.right, 350, 100, true, 100, 110, true);
    expect(door.fits(400, 500, 280), isTrue);
    expect(window.fits(400, 500, 280), isTrue);
    expect(window.fits(400, 420, 280), isFalse);
    expect(window.fits(400, 500, 200), isFalse);
    expect(Opening.fromJson(window.toJson()).reverse, isTrue);
  });

  testWidgets('Arabic digits resize the plan and the same room opens in 3D', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RoomPlanner(prefs, false))),
    );
    await tester.tap(find.text('Plan'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '٤٢٠');
    await tester.tap(find.text('Apply dimensions'));
    await tester.pump();
    final drawing = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RoomDrawing,
    );
    expect(
      (tester.widget<CustomPaint>(drawing).painter! as RoomDrawing).width,
      420,
    );
    await tester.tap(find.text('3D view'));
    await tester.pump();
    final updated = tester.widget<RoomOrbit>(find.byType(RoomOrbit));
    expect(updated.width, 420);
    expect(updated.length, 500);
  });
}
