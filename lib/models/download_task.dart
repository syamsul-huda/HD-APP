import 'package:dio/dio.dart';

enum DownloadStatus { preparing, downloading, completed, failed, cancelled }

class DownloadTask {
  final String id;
  final String title;
  final String? thumbnail;
  final String url;
  final String formatId;
  final String quality;
  final String platform;
  final bool isAudio;
  final String audioFormat; // 'mp3', 'm4a', 'opus'
  DownloadStatus status;
  double progress;
  int received;
  int total;
  String? filePath;
  String? error;
  CancelToken? cancelToken;

  DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.formatId,
    required this.quality,
    required this.platform,
    this.thumbnail,
    this.isAudio = false,
    this.audioFormat = 'mp3',
    this.status = DownloadStatus.preparing,
    this.progress = 0,
    this.received = 0,
    this.total = 0,
    this.filePath,
    this.error,
    this.cancelToken,
  });

  double speedBps = 0;
  DateTime? _lastSpeedTime;
  int _lastSpeedReceived = 0;

  bool get isActive =>
      status == DownloadStatus.preparing || status == DownloadStatus.downloading;

  String get typeLabel => isAudio ? '🎵 ${audioFormat.toUpperCase()}' : '📹 Video';

  // Dipanggil setiap kali received berubah untuk menghitung kecepatan
  void tickSpeed(int newReceived) {
    final now = DateTime.now();
    if (_lastSpeedTime != null) {
      final ms = now.difference(_lastSpeedTime!).inMilliseconds;
      if (ms >= 200) {
        speedBps = (newReceived - _lastSpeedReceived) * 1000 / ms;
        _lastSpeedTime = now;
        _lastSpeedReceived = newReceived;
      }
    } else {
      _lastSpeedTime = now;
      _lastSpeedReceived = newReceived;
    }
  }

  String get statusText {
    switch (status) {
      case DownloadStatus.preparing:
        return 'Memproses di server...';
      case DownloadStatus.downloading:
        final speed = speedBps >= 1024 ? ' · ${_fmtD(speedBps)}/s' : '';
        return total > 0
            ? '${_fmt(received)} / ${_fmt(total)}$speed'
            : '${_fmt(received)} diunduh...$speed';
      case DownloadStatus.completed:
        return 'Selesai';
      case DownloadStatus.failed:
        return 'Gagal: ${error ?? ""}';
      case DownloadStatus.cancelled:
        return 'Dibatalkan';
    }
  }

  static String _fmt(int b) {
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  }

  static String _fmtD(double b) {
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  }
}
