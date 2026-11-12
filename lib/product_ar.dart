import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'room_geometry.dart';

/// A product with a dimensioned 3D model for phone AR ("View in your room").
///
/// The file stem matches `tools/generate_demo_models.py`: the app bundles
/// `assets/<stem>.glb` and `assets/<stem>.usdz`, and the web AR page serves
/// the same names. Only products listed here offer a 3D or AR preview.
class ArModel {
  const ArModel(this.sku, this.store, this.stem, this.size);
  final String sku, stem;
  final int store;

  /// Planner geometry for the London pieces; an AR-only size otherwise.
  final FurnitureSize size;

  String get glb => 'assets/$stem.glb';
  String get usdz => 'assets/$stem.usdz';

  /// True when the product can also be placed in the room planner and headset.
  bool get inRoomPlanner => furnitureSizes.contains(size);
}

final arModels = [
  ArModel('10_14_3', 0, 'london-10_14_3', furnitureSizes[0]),
  ArModel('6_14_5', 0, 'london-6_14_5', furnitureSizes[1]),
  const ArModel(
    '23_88_1',
    1,
    'cityw-23_88_1',
    FurnitureSize(
      '23_88_1',
      'Warm Beige three-seater',
      'كنبة بيج دافئ ثلاثية',
      230,
      101,
      78,
      modelAsset: 'assets/cityw-23_88_1.glb',
      store: 1,
    ),
  ),
];

/// iPhone uses the bundled USDZ. Android uses the configured HTTPS AR page.
class ProductAR {
  static const channel = MethodChannel('almutlaq/product_ar');
  static Set<String> get supported => {for (final m in arModels) m.sku};

  static ArModel? model(String sku, [int? store]) {
    for (final m in arModels) {
      if (m.sku == sku && (store == null || m.store == store)) return m;
    }
    return null;
  }

  static Uri? websiteUri(String sku, String website, {String language = 'ar'}) {
    if (model(sku) == null) return null;
    final uri = Uri.tryParse(website);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'sku': sku,
        'lang': language == 'en' ? 'en' : 'ar',
      },
    );
  }

  static Future<bool> open(
    String sku, {
    String website = '',
    String language = 'ar',
  }) async {
    final m = model(sku);
    if (m == null) return false;
    if (Platform.isIOS) {
      final result = await channel.invokeMapMethod<String, dynamic>('preview', {
        'sku': sku,
        'asset': m.usdz,
      });
      return result?['opened'] == true;
    }
    final uri = websiteUri(sku, website, language: language);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
