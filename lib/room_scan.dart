import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoomScan {
  static const _channel = MethodChannel('com.showroomxr/room_scan');
  static bool get offered => Platform.isIOS;
  static Future<Map<String, dynamic>?> capture(
    BuildContext context,
    bool arabic,
  ) async {
    String t(String ar, String en) => arabic ? ar : en;
    try {
      final supported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
      if (!context.mounted) return null;
      if (!supported) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              t('المسح غير متاح على هالجهاز', 'Room scanning is unavailable'),
            ),
            content: Text(
              t(
                'المسح يحتاج جهاز يدعم LiDAR وRoomPlan. تقدر تدخل القياسات يدويًا.',
                'Scanning needs a device with LiDAR and RoomPlan. Enter the measurements manually.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('تمام', 'OK')),
              ),
            ],
          ),
        );
        return null;
      }
      final value = await _channel.invokeMapMethod<String, dynamic>('scan', {
        'arabic': arabic,
      });
      if (value == null || !context.mounted) return null;
      return value;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') return null;
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'تعذر المسح. راجع إذن الكاميرا أو أدخل القياسات يدويًا.',
                'Scanning failed. Check camera access or enter measurements manually.',
              ),
            ),
          ),
        );
      return null;
    } on MissingPluginException {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'المسح يحتاج نسخة iOS المجهزة له. الإدخال اليدوي متاح.',
                'Scanning needs the iOS scanning build. Manual entry is available.',
              ),
            ),
          ),
        );
      return null;
    }
  }
}
