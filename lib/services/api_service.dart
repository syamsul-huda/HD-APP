import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';
import '../utils/web_download.dart';

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();

  static String get _defaultUrl =>
      kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';
  static const _prefKey = 'backend_url';

  String _backendUrl = '';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString(_prefKey) ?? _defaultUrl;
  }

  String get backendUrl => _backendUrl.isEmpty ? _defaultUrl : _backendUrl;

  Future<void> setBackendUrl(String url) async {
    _backendUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _backendUrl);
  }

  Dio _dio() => Dio(BaseOptions(
        baseUrl: backendUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(hours: 2),
      ));

  Future<VideoInfo> getInfo(String url) async {
    try {
      final resp = await _dio().post<Map<String, dynamic>>(
        '/api/info',
        data: {'url': url},
      );
      return VideoInfo.fromJson(resp.data!);
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      throw Exception(detail ?? _friendlyError(e));
    }
  }

  String _friendlyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Koneksi timeout. Pastikan backend sudah berjalan.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Tidak bisa terhubung ke backend.\nPastikan server berjalan & URL benar di Settings ⚙';
    }
    return e.message ?? e.toString();
  }

  Future<void> download({
    required DownloadTask task,
    required void Function(DownloadStatus, double, int, int) onUpdate,
    required void Function(String) onDone,
    required void Function(String) onError,
  }) async {
    final encUrl = Uri.encodeComponent(task.url);
    final encFmt = Uri.encodeComponent(task.formatId);
    final encTitle = Uri.encodeComponent(task.title);
    final mode = task.isAudio ? 'audio' : 'video';
    final streamUrl = '${backendUrl}/api/stream'
        '?url=$encUrl'
        '&format_id=$encFmt'
        '&title=$encTitle'
        '&mode=$mode'
        '&audio_fmt=${task.audioFormat}';

    // ── Web: Dio download di background + simpan via blob (progress akurat, tetap di tab ini) ──
    if (kIsWeb) {
      task.cancelToken = CancelToken();
      try {
        final safe = task.title.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '').trim();
        final ext = task.isAudio ? task.audioFormat : 'mp4';
        final filename = '${safe.substring(0, safe.length.clamp(0, 50))}.$ext';

        // Tunggu respons backend (yt-dlp + ffmpeg) — task tetap di 'preparing'
        // onReceiveProgress akan memindahkan ke 'downloading' saat byte pertama tiba
        final response = await _dio().get<List<int>>(
          streamUrl,
          options: Options(responseType: ResponseType.bytes),
          cancelToken: task.cancelToken,
          onReceiveProgress: (recv, tot) => onUpdate(
            DownloadStatus.downloading,
            tot > 0 ? recv / tot : -1,
            recv,
            tot,
          ),
        );

        if (response.data != null) {
          saveFileWeb(response.data!, filename);
        }
        onDone('web_browser');
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          onError('dibatalkan');
        } else {
          final detail = (e.response?.data as Map?)?['detail'] as String?;
          onError(detail ?? _friendlyError(e));
        }
      } catch (e) {
        onError(e.toString());
      }
      return;
    }

    // ── Mobile: download ke file dengan Dio + progress ──
    try {
      final dir = await _getDir();
      final safe = task.title.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '').trim();
      final name = safe.substring(0, safe.length.clamp(0, 50));
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = task.isAudio ? task.audioFormat : 'mp4';
      final path = '$dir/${name}_$ts.$ext';

      task.cancelToken = CancelToken();
      // Tidak set onUpdate di sini — onReceiveProgress yang akan pindahkan
      // dari 'preparing' ke 'downloading' saat byte pertama tiba dari server

      await _dio().download(
        streamUrl,
        path,
        cancelToken: task.cancelToken,
        onReceiveProgress: (recv, tot) => onUpdate(
          DownloadStatus.downloading,
          tot > 0 ? recv / tot : -1,
          recv,
          tot,
        ),
      );

      onDone(path);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        onError('dibatalkan');
      } else {
        final detail = (e.response?.data as Map?)?['detail'] as String?;
        onError(detail ?? _friendlyError(e));
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<String> _getDir() async {
    if (Platform.isAndroid) {
      final d = Directory('/storage/emulated/0/Download/VideoSaver');
      if (!await d.exists()) await d.create(recursive: true);
      return d.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/VideoSaver');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }
}
