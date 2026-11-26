import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

/// Public Roomle identifiers only. No customer, room or pairing data is sent.
class Roomle {
  const Roomle({
    this.configuratorId = '',
    this.catalogRootTag = '',
    this.productIds = const {},
  });

  final String configuratorId;
  final String catalogRootTag;
  final Map<String, String> productIds;

  static final configured = fromSettings(
    const String.fromEnvironment('ROOMLE_CONFIGURATOR_ID'),
    const String.fromEnvironment('ROOMLE_CATALOG_ROOT_TAG'),
    const String.fromEnvironment('ROOMLE_PRODUCT_IDS', defaultValue: '{}'),
  );

  static Roomle fromSettings(String id, String tag, String mapping) {
    final products = <String, String>{};
    try {
      final decoded = jsonDecode(mapping);
      if (decoded is! Map) return const Roomle();
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) {
          return const Roomle();
        }
        final sku = (entry.key as String).trim();
        final item = (entry.value as String).trim();
        if (sku.isEmpty || item.isEmpty) return const Roomle();
        products[sku] = item;
      }
    } on FormatException {
      return const Roomle();
    }
    return Roomle(
      configuratorId: id.trim(),
      catalogRootTag: tag.trim(),
      productIds: Map.unmodifiable(products),
    );
  }

  Uri? plannerUri() {
    if (configuratorId.trim().isEmpty || catalogRootTag.trim().isEmpty) {
      return null;
    }
    return Uri.https('www.roomle.com', '/t/cp/', {
      'configuratorId': configuratorId,
      'catalogRootTag': catalogRootTag,
      'moc': 'true',
      'startInDetail': 'false',
      'state.mode': 'room',
      'api': 'false',
    });
  }

  Uri? productUri(String sku) {
    final item = productIds[sku];
    if (configuratorId.trim().isEmpty || item == null || item.trim().isEmpty) {
      return null;
    }
    return Uri.https('www.roomle.com', '/t/cp/', {
      'configuratorId': configuratorId,
      'id': item,
      'api': 'false',
    });
  }

  Future<bool> openPlanner() => _open(plannerUri());
  Future<bool> openProduct(String sku) => _open(productUri(sku));

  Future<bool> _open(Uri? uri) async {
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
