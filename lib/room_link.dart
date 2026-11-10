import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_document.dart';

class RoomLinkClient {
  RoomLinkClient(this.preferences, {HttpClient? client})
    : _client = client ?? HttpClient();
  final SharedPreferences preferences;
  final HttpClient _client;
  static const defaultEndpoint = String.fromEnvironment(
    'SHOWROOM_SERVICE_URL',
    defaultValue: 'http://127.0.0.1:8766',
  );

  Uri get base {
    final uri = Uri.tryParse(
      preferences.getString('showroom-endpoint') ?? defaultEndpoint,
    );
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host.isEmpty ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['127.0.0.1', 'localhost'].contains(uri.host)))) {
      throw const FormatException('Use HTTPS, or localhost for the USB demo.');
    }
    return uri;
  }

  bool get paired => (preferences.getString('showroom-token') ?? '').isNotEmpty;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final req = await _client
        .openUrl(body == null ? 'GET' : 'POST', base.resolve(path))
        .timeout(const Duration(seconds: 5));
    req.headers.contentType = ContentType.json;
    if (authenticated) {
      final token = preferences.getString('showroom-token');
      if (token == null) throw const HttpException('Pair the device first.');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) req.write(jsonEncode(body));
    final response = await req.close().timeout(const Duration(seconds: 5));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 409)
      throw const HttpException('The room changed. Review it and send again.');
    if (response.statusCode == 401) {
      await preferences.remove('showroom-token');
      throw const HttpException('Pairing expired. Pair this device again.');
    }
    if (response.statusCode != 200)
      throw HttpException('Service returned ${response.statusCode}.');
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> pair(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code))
      throw const FormatException('Enter six digits.');
    final value = await request(
      '/api/pair',
      body: {'code': code},
      authenticated: false,
    );
    if (value['token'] is! String)
      throw const FormatException('Invalid pairing response.');
    await preferences.setString('showroom-token', value['token'] as String);
  }

  Future<Map<String, dynamic>> send(RoomDocument room) async {
    final current = await request('/api/state');
    return request(
      '/api/state',
      body: {...room.toWire(), 'expectedRevision': current['revision']},
    );
  }

  void close() => _client.close(force: true);
}

class RoomLinkPanel extends StatefulWidget {
  const RoomLinkPanel({
    super.key,
    required this.preferences,
    required this.arabic,
    required this.document,
  });
  final SharedPreferences preferences;
  final bool arabic;
  final RoomDocument Function() document;
  @override
  State<RoomLinkPanel> createState() => _RoomLinkPanelState();
}

class _RoomLinkPanelState extends State<RoomLinkPanel> {
  late final client = RoomLinkClient(widget.preferences);
  final code = TextEditingController();
  bool busy = false;
  String? status;
  String t(String ar, String en) => widget.arabic ? ar : en;

  @override
  void dispose() {
    client.close();
    code.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
    } on FormatException {
      if (mounted)
        setState(
          () => status = t(
            'راجع القياسات ورمز الربط. لازم كل قطعة تكون داخل الغرفة.',
            'Check the measurements and pairing code. All pieces must fit inside the room.',
          ),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => status = t(
            'تعذر الاتصال. شغّل لوحة الموظف وتحقق من ربط USB أو عنوان الخدمة.',
            'Connection unavailable. Start the staff service and check USB or the service address.',
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('إرسال تصميمك للمعرض', 'Send your design to the showroom'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            t(
              'اربط الجهاز مرة برمز من لوحة الموظف. التأكيد يظهر عقب تطبيق التصميم على النظارة.',
              'Pair once with a code from the staff panel. Confirmation appears after the headset applies the design.',
            ),
          ),
          const SizedBox(height: 12),
          if (!client.paired)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: t('رمز الربط', 'Pairing code'),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => perform(() async {
                          await client.pair(code.text.trim());
                          if (mounted)
                            setState(
                              () =>
                                  status = t('تم ربط الجهاز', 'Device paired'),
                            );
                        }),
                  child: Text(t('ربط', 'Pair')),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.send_outlined),
                  onPressed: busy
                      ? null
                      : () => perform(() async {
                          final value = await client.send(widget.document());
                          if (mounted)
                            setState(
                              () => status = t(
                                'انرسل الإصدار ${value['revision']}، بانتظار تأكيد النظارة.',
                                'Revision ${value['revision']} sent. Waiting for headset confirmation.',
                              ),
                            );
                        }),
                  label: Text(t('إرسال', 'Send')),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => perform(() async {
                          final value = await client.request('/api/state');
                          final applied =
                              value['appliedRevision'] == value['revision'];
                          if (mounted)
                            setState(
                              () => status = applied
                                  ? t(
                                      'النظارة أكدت تطبيق الإصدار ${value['revision']}',
                                      'Headset applied revision ${value['revision']}',
                                    )
                                  : t(
                                      'بانتظار تأكيد النظارة للإصدار ${value['revision']}',
                                      'Waiting for headset revision ${value['revision']}',
                                    ),
                            );
                        }),
                  child: Text(t('فحص التأكيد', 'Check confirmation')),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await widget.preferences.remove('showroom-token');
                          if (mounted) setState(() => status = null);
                        },
                  child: Text(t('فصل الجهاز', 'Unpair')),
                ),
              ],
            ),
          if (busy) const LinearProgressIndicator(),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(status!, key: const ValueKey('room-link-status')),
            ),
        ],
      ),
    ),
  );
}
