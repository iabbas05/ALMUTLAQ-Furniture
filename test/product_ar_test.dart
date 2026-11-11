import 'package:flutter_test/flutter_test.dart';
import 'package:london_showroom/product_ar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Unknown products never open an incorrect London model', () async {
    expect(await ProductAR.open('missing'), isFalse);
  });
  test('Android fallback requires a published HTTPS AR URL', () async {
    expect(await ProductAR.open('10_14_3'), isFalse);
    expect(await ProductAR.open('6_14_5', website: 'http://example.com'), isFalse);
  });
}
