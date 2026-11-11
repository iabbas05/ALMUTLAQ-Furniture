import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// iPhone uses the bundled USDZ. Android uses the configured HTTPS AR page.
class ProductAR {
  static const channel = MethodChannel('almutlaq/product_ar');
  static const supported = {'10_14_3', '6_14_5'};

  static Future<bool> open(String sku, {String website = ''}) async {
    if (!supported.contains(sku)) return false;
    if (Platform.isIOS) {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'preview',
        {'sku': sku},
      );
      return result?['opened'] == true;
    }
    final uri = Uri.tryParse(website);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return launchUrl(
      uri.replace(queryParameters: {...uri.queryParameters, 'sku': sku}),
      mode: LaunchMode.externalApplication,
    );
  }
}
