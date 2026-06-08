import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}

class UpdateService {
  static const _apiUrl =
      'https://api.github.com/repos/syamsul-huda/HD-APP/releases/latest';

  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final dio = Dio();
      final res = await dio.get(_apiUrl);
      final data = res.data as Map<String, dynamic>;

      final tag = (data['tag_name'] as String).replaceFirst('v', '');
      if (!_isNewer(tag, current)) return null;

      final assets = (data['assets'] as List?) ?? [];
      final apkList = assets.where(
        (a) => (a['name'] as String).endsWith('.apk'),
      ).toList();
      if (apkList.isEmpty) return null;
      final apk = apkList.first;

      return UpdateInfo(
        version: tag,
        downloadUrl: apk['browser_download_url'] as String,
        releaseNotes: (data['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> downloadAndInstall(
    String url,
    void Function(double progress) onProgress,
  ) async {
    if (Platform.isAndroid) {
      await Permission.requestInstallPackages.request();
    }

    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/hd-app-update.apk';

    final dio = Dio();
    await dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    await OpenFilex.open(savePath);
  }

  static bool _isNewer(String latest, String current) {
    List<int> parse(String v) =>
        v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final l = parse(latest);
    final c = parse(current);
    for (var i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }
}
