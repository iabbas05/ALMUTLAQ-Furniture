import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_release.dart';

class AppUpdates extends StatefulWidget {
  const AppUpdates(this.arabic, {super.key});
  final bool arabic;
  @override
  State<AppUpdates> createState() => _AppUpdatesState();
}

class _AppUpdatesState extends State<AppUpdates> {
  PackageInfo? installed;
  AppRelease? release;
  bool busy = true;
  String? status;
  String t(String ar, String en) => widget.arabic ? ar : en;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      status = null;
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => installed = info);
      final request = await client
          .getUrl(
            Uri.https(
              'api.github.com',
              '/repos/iabbas05/ALMUTLAQ-Furniture/releases',
              {'per_page': '30'},
            ),
          )
          .timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'AlmutlaqFurniture/${info.version}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200)
        throw const HttpException('Update lookup failed');
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (text.length > 2000000)
        throw const FormatException('Release list too large');
      final data = jsonDecode(text);
      if (data is! List) throw const FormatException('Invalid release list');
      final list =
          data
              .whereType<Map<String, dynamic>>()
              .map(AppRelease.parse)
              .whereType<AppRelease>()
              .where((r) => Platform.isIOS ? r.ipa != null : r.apk != null)
              .toList()
            ..sort((a, b) => b.build.compareTo(a.build));
      if (!mounted) return;
      final latest = list.isEmpty ? null : list.first;
      setState(() {
        release = latest;
        status = latest == null
            ? t(
                'ما في إصدار منشور للحين.',
                'No downloadable release has been published yet.',
              )
            : latest.build <= (int.tryParse(info.buildNumber) ?? 0)
            ? t(
                'عندك آخر إصدار متاح.',
                'You have the latest available version.',
              )
            : t('في إصدار أحدث متاح للتنزيل.', 'A newer version is available.');
      });
    } catch (_) {
      if (mounted)
        setState(
          () => status = t(
            'تعذر فحص التحديث. جرّب مرة ثانية عقب الاتصال.',
            'Unable to check for updates. Reconnect and try again.',
          ),
        );
    } finally {
      client.close(force: true);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    final uri = Platform.isIOS ? release?.ipa : release?.apk;
    if (uri == null) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
        throw const HttpException('No download handler');
    } catch (_) {
      if (mounted)
        setState(
          () => status = t('تعذر فتح التنزيل.', 'Unable to open the download.'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final newer =
        release != null &&
        installed != null &&
        release!.build > (int.tryParse(installed!.buildNumber) ?? 0);
    return Scaffold(
      appBar: AppBar(title: Text(t('تحديث التطبيق', 'App updates'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.system_update_alt, size: 48),
          const SizedBox(height: 24),
          Text(
            t('نسختك الحالية', 'Installed version'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (installed != null)
            Text(
              '${installed!.version} (${installed!.buildNumber})',
              textDirection: TextDirection.ltr,
            ),
          const SizedBox(height: 16),
          if (busy) const LinearProgressIndicator(),
          if (status != null) Text(status!),
          if (release != null) ...[
            const SizedBox(height: 16),
            Text(
              '${t('الإصدار المتاح', 'Available version')}: ${release!.version} (${release!.build})',
            ),
            if (release!.notes.isNotEmpty) Text(release!.notes),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : check,
            icon: const Icon(Icons.refresh),
            label: Text(t('فحص التحديث', 'Check for updates')),
          ),
          if (newer) ...[
            OutlinedButton.icon(
              onPressed: download,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                Platform.isIOS
                    ? t(
                        'تنزيل نسخة iOS للتوقيع',
                        'Download iOS build for signing',
                      )
                    : t('تنزيل التحديث', 'Download update'),
              ),
            ),
            Text(
              Platform.isIOS
                  ? t(
                      'هذي النسخة غير موقعة. تحتاج توقيعًا قبل تثبيتها. توزيع TestFlight يتجهز مع حساب الشركة.',
                      'This build is unsigned and needs signing before installation. TestFlight distribution requires the company account.',
                    )
                  : t(
                      'عقب التنزيل افتح APK ووافق على التثبيت. تحديث النسخة الحالية يحتاج نفس شهادة التوقيع.',
                      'Open the downloaded APK and approve installation. Updating an existing installation requires the same signing certificate.',
                    ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            t(
              'تحديث البرنامج يختلف عن تحديث كتالوج المنتجات.',
              'App updates are separate from product catalogue refreshes.',
            ),
          ),
        ],
      ),
    );
  }
}
