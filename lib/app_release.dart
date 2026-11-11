class AppRelease {
  const AppRelease(this.version, this.build, this.notes, this.apk, this.ipa);
  final String version, notes;
  final int build;
  final Uri? apk, ipa;

  static AppRelease? parse(Map<String, dynamic> data) {
    if (data['draft'] == true) return null;
    final tag = data['tag_name'];
    if (tag is! String) return null;
    final match = RegExp(r'^app-v(\d+\.\d+\.\d+)-b(\d+)$').firstMatch(tag);
    if (match == null) return null;
    Uri? asset(String filename) {
      final assets = data['assets'];
      if (assets is! List) return null;
      for (final row in assets.whereType<Map>()) {
        if (row['name'] != filename ||
            row['size'] is! int ||
            (row['size'] as int) <= 0)
          continue;
        final raw = row['browser_download_url'];
        if (raw is! String) continue;
        final uri = Uri.tryParse(raw);
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'github.com' &&
            uri.userInfo.isEmpty &&
            !uri.hasPort &&
            uri.query.isEmpty &&
            uri.fragment.isEmpty &&
            uri.path.startsWith(
              '/iabbas05/ALMUTLAQ-Furniture/releases/download/$tag/',
            ) &&
            uri.pathSegments.last == filename)
          return uri;
      }
      return null;
    }

    final apk = asset('Almutlaq.apk'), ipa = asset('Almutlaq-Unsigned.ipa');
    if (apk == null && ipa == null) return null;
    return AppRelease(
      match[1]!,
      int.parse(match[2]!),
      data['body'] is String ? data['body'] as String : '',
      apk,
      ipa,
    );
  }
}
