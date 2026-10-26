import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

/// Konversi dokumen Office → PDF lewat backend (LibreOffice) untuk tampilan
/// yang identik dengan Microsoft Office, termasuk format lama .doc/.xls/.ppt.
/// Hasil disimpan di cache sehingga file yang sama tidak dikonversi ulang.
class DocumentConvertService {
  /// Format yang tidak bisa dibaca langsung di aplikasi, wajib dikonversi.
  static const legacyFormats = {
    'doc', 'dot', 'rtf', 'wps', 'xls', 'xlt', 'ppt', 'pps', 'pot',
  };

  static Future<File> _cacheFile(String path) async {
    final src = File(path);
    final stat = await src.stat();
    final key = _fnv1a(
        '${src.uri.pathSegments.last}|${stat.size}|${stat.modified.millisecondsSinceEpoch}');
    final dir = Directory('${(await getTemporaryDirectory()).path}/converted');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$key.pdf');
  }

  /// PDF hasil konversi dari cache, jika sudah pernah dikonversi.
  static Future<File?> cached(String path) async {
    final f = await _cacheFile(path);
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  static Future<File> toPdf(
    String path, {
    String? fileName,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final out = await _cacheFile(path);
    if (await out.exists() && await out.length() > 0) return out;

    final dio = Dio(BaseOptions(
      baseUrl: ApiService().backendUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 5),
    ));
    final name = fileName ?? File(path).uri.pathSegments.last;
    try {
      final resp = await dio.post<List<int>>(
        '/api/convert',
        data: FormData.fromMap(
            {'file': await MultipartFile.fromFile(path, filename: name)}),
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
        // Upload = 70% progress, download hasil = 30%
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(0.7 * sent / total);
        },
        onReceiveProgress: (got, total) {
          if (total > 0) onProgress?.call(0.7 + 0.3 * got / total);
        },
      );
      final bytes = resp.data;
      if (bytes == null || bytes.length < 5 || utf8.decode(bytes.sublist(0, 5)) != '%PDF-') {
        throw Exception('The server returned an invalid PDF');
      }
      await out.writeAsBytes(bytes, flush: true);
      return out;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw Exception(_friendlyError(e));
    }
  }

  static String _friendlyError(DioException e) {
    final data = e.response?.data;
    if (data is List<int>) {
      try {
        final detail = (jsonDecode(utf8.decode(data)) as Map)['detail'];
        if (detail is String) return detail;
      } catch (_) {}
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out while converting the document.';
      case DioExceptionType.connectionError:
        return 'Cannot connect to the conversion server.\n'
            'Make sure the backend is running and the URL in Settings ⚙ is correct.';
      default:
        return e.message ?? e.toString();
    }
  }

  static String _fnv1a(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16);
  }
}
