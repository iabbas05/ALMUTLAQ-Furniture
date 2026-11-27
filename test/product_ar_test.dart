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
  test('Web handoff carries the selected product and current language', () {
    final uri = ProductAR.websiteUri('6_14_5', 'https://example.com/ar/?source=app', language: 'en');
    expect(uri?.queryParameters, {'source': 'app', 'sku': '6_14_5', 'lang': 'en'});
    expect(ProductAR.websiteUri('missing', 'https://example.com/'), isNull);
    expect(ProductAR.websiteUri('10_14_3', 'https://user@example.com/'), isNull);
  });
}
