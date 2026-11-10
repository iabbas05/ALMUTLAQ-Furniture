import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

const stores = ['The Factory', 'CityW'];
const storeHosts = ['thefactoryfurniture.com', 'cityw.com.sa'];

class Product {
  const Product(
    this.sku,
    this.store,
    this.name,
    this.arabic,
    this.size,
    this.details,
    this.arabicDetails, {
    this.image,
    this.hasModel = false,
    this.id,
    this.gallery = const [],
    this.categories = const [],
    this.attributes = const [],
    this.price = '',
    this.inStock,
    this.link,
  });

  final String sku, name, arabic, size, details, arabicDetails, price;
  final int store;
  final int? id;
  final String? image, link;
  final List<String> gallery, categories, attributes;
  final bool hasModel;
  final bool? inStock;

  String get key => '$store:${sku.isEmpty ? id : sku}';

  factory Product.fromStore(int store, Map<String, dynamic> data) {
    final sku = data['sku']?.toString() ?? '';
    final name = plainText(data['name']);
    final details = plainText(data['description']);
    final summary = plainText(data['short_description']);
    final photos = [
      for (final row in maps(data['images']))
        if (httpsUrl(row['src']) case final String url) url,
    ];
    final attributes = [
      for (final row in maps(data['attributes']))
        if (maps(row['terms']).isNotEmpty)
          '${plainText(row['name'])}: ${maps(row['terms']).map((term) => plainText(term['name'])).join(', ')}',
    ];
    Product? known;
    for (final product in sampleCatalogue) {
      if (product.store == store && product.sku == sku) known = product;
    }
    final dimensions = [
      data['dimensions'] is Map ? (data['dimensions'] as Map)['length'] : null,
      data['dimensions'] is Map ? (data['dimensions'] as Map)['width'] : null,
      data['dimensions'] is Map ? (data['dimensions'] as Map)['height'] : null,
    ];
    final size =
        dimensions.every(
          (part) => part != null && part.toString().trim().isNotEmpty,
        )
        ? dimensions.join(' × ')
        : known?.size ?? '';
    return Product(
      sku,
      store,
      name,
      known?.arabic ?? name,
      size,
      details.isNotEmpty ? details : summary,
      known?.arabicDetails ?? (details.isNotEmpty ? details : summary),
      id: data['id'] as int,
      image: photos.isEmpty ? known?.image : photos.first,
      gallery: photos.isEmpty ? known?.gallery ?? const [] : photos,
      hasModel: known?.hasModel ?? false,
      link: httpsUrl(data['permalink']),
      categories: maps(data['categories'])
          .map((row) => plainText(row['name']))
          .where((name) => name.isNotEmpty)
          .toList(),
      attributes: attributes,
      price: displayPrice(data['prices']),
      inStock: data['is_in_stock'] is bool ? data['is_in_stock'] as bool : null,
    );
  }
}

List<Map<String, dynamic>> maps(dynamic value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : [];

String plainText(dynamic value) =>
    html
        .parseFragment(
          (value?.toString() ?? '').replaceAll(
            RegExp(r'<(?:br|/p|/li)\b[^>]*>', caseSensitive: false),
            '\n',
          ),
        )
        .text
        ?.replaceAll(RegExp(r'[ \t\r]+'), ' ')
        .trim() ??
    '';

String? httpsUrl(dynamic value) {
  final url = Uri.tryParse(value?.toString() ?? '');
  return url != null && url.scheme == 'https' && url.host.isNotEmpty
      ? url.toString()
      : null;
}

String displayPrice(dynamic prices) {
  if (prices is! Map) return '';
  final digits = prices['currency_minor_unit'];
  final currency = prices['currency_code']?.toString() ?? '';
  if (digits is! int || digits < 0 || digits > 6 || currency.isEmpty) return '';
  String amount(dynamic value) {
    final minor = int.tryParse(value?.toString() ?? '');
    if (minor == null || minor < 0) return '';
    final s = minor.toString().padLeft(digits + 1, '0');
    if (digits == 0) return s;
    return '${s.substring(0, s.length - digits)}.${s.substring(s.length - digits)}';
  }

  final range = prices['price_range'];
  if (range is Map) {
    final min = amount(range['min_amount']);
    final max = amount(range['max_amount']);
    if (min.isNotEmpty && max.isNotEmpty && min != max)
      return '$min – $max $currency';
  }
  final price = amount(prices['price']);
  return price.isEmpty ? '' : '$price $currency';
}

class CatalogueClient {
  Future<List<Product>> fetch(int store) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final items = <int, Product>{};
    try {
      var totalPages = 1;
      for (var page = 1; page <= totalPages; page++) {
        final url = Uri.https(
          storeHosts[store],
          '/wp-json/wc/store/v1/products',
          {'page': '$page', 'per_page': '100'},
        );
        final request = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 12));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Catalogue request returned ${response.statusCode}',
            uri: url,
          );
        }
        final body = await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 15));
        final parsed = jsonDecode(body);
        if (parsed is! List)
          throw const FormatException('Expected a product list.');
        for (final row in maps(parsed)) {
          if (row['id'] case final int id) {
            final product = Product.fromStore(store, row);
            if (product.name.isNotEmpty) items[id] = product;
          }
        }
        if (page == 1) {
          final count = int.tryParse(
            response.headers.value('x-wp-totalpages') ?? '',
          );
          if (count == null && parsed.length == 100) {
            throw const FormatException(
              'Catalogue pagination header is unavailable.',
            );
          }
          totalPages = count ?? 1;
          if (totalPages > 1000)
            throw const FormatException('Invalid page count.');
        }
      }
      return items.values.toList();
    } finally {
      client.close(force: true);
    }
  }
}

const sampleCatalogue = [
  Product(
    '10_14_3',
    0,
    'London three-seater',
    'كنبة لندن ثلاثية',
    '210 × 103 × 100 cm',
    'White upholstered sofa with three seats.',
    'كنبة بيضاء منجّدة بثلاثة مقاعد.',
    image: 'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-1.jpg',
    gallery: [
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-1.jpg',
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-6.jpg',
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-3.jpg',
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-11.jpg',
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-7.jpg',
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-8.jpg',
      'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-2.jpg',
    ],
    link: 'https://thefactoryfurniture.com/ar/shop/sofa-three-seater-white-3-seater-london/',
    categories: ['Sofas'],
    hasModel: true,
  ),
  Product(
    '6_14_5',
    0,
    'London chair',
    'كرسي لندن',
    '84 × 95 × 94 cm',
    'White upholstered single seat.',
    'كرسي أبيض منجّد بمقعد واحد.',
    image: 'https://thefactoryfurniture.com/wp-content/uploads/2026/11/06-14-00005-1.jpg',
    link: 'https://thefactoryfurniture.com/ar/shop/sofa-chair-white-london/',
    categories: ['Chairs'],
  ),
  Product(
    '23_88_1',
    1,
    'Warm Beige three-seater',
    'كنبة بيج دافئ ثلاثية',
    '230 × 101 × 78 cm',
    'Woven fabric with a solid wood frame.',
    'قماش منسوج مع إطار من الخشب الصلب.',
    link: 'https://cityw.com.sa/product/3-seater-fabric-sofa-warm-beige-square-arm/',
    categories: ['Sofas'],
  ),
];
