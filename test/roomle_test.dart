import 'package:flutter_test/flutter_test.dart';
import 'package:london_showroom/roomle.dart';

void main() {
  test('Unconfigured Roomle never opens demo content', () async {
    const roomle = Roomle();
    expect(roomle.plannerUri(), isNull);
    expect(roomle.productUri('10_14_3'), isNull);
    expect(await roomle.openPlanner(), isFalse);
    expect(await roomle.openProduct('10_14_3'), isFalse);
  });

  test('Planner requires both account and catalogue and sends only public IDs', () {
    expect(const Roomle(configuratorId: 'test').plannerUri(), isNull);
    final uri = const Roomle(
      configuratorId: 'test-account',
      catalogRootTag: 'test-catalog',
    ).plannerUri()!;
    expect(uri.origin, 'https://www.roomle.com');
    expect(uri.path, '/t/cp/');
    expect(uri.queryParameters, {
      'configuratorId': 'test-account',
      'catalogRootTag': 'test-catalog',
      'moc': 'true',
      'startInDetail': 'false',
      'state.mode': 'room',
      'api': 'false',
    });
  });

  test('Product mappings preserve the chosen SKU and encode identifiers', () {
    final roomle = Roomle.fromSettings(' test ', ' root ',
        '{"10_14_3":"test:sofa?a=1&b=2", "6_14_5":"test:chair"}');
    expect(roomle.productUri('10_14_3')!.queryParameters['id'], 'test:sofa?a=1&b=2');
    expect(roomle.productUri('6_14_5')!.queryParameters['id'], 'test:chair');
    expect(roomle.productUri('unknown'), isNull);
    expect(roomle.productUri('10_14_3')!.queryParameters['configuratorId'], 'test');
  });

  test('Malformed mappings fail closed without selecting a different product', () {
    for (final value in ['{', '[]', '{"10_14_3":42}', '{"":"test:item"}', '{"10_14_3":""}']) {
      final roomle = Roomle.fromSettings('test', 'root', value);
      expect(roomle.plannerUri(), isNull);
      expect(roomle.productUri('10_14_3'), isNull);
    }
  });
}
