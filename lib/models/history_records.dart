/// Item riwayat Video Downloader (hanya download yang selesai).
class DownloadRecord {
  final String title;
  final String platform;
  final String? thumbnail;
  final String filePath;
  final bool isAudio;
  final String audioFormat;
  final String quality;
  final int date;

  const DownloadRecord({
    required this.title,
    required this.platform,
    required this.filePath,
    required this.isAudio,
    required this.audioFormat,
    required this.quality,
    required this.date,
    this.thumbnail,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);
  String get typeLabel => isAudio ? audioFormat.toUpperCase() : 'Video';

  Map<String, dynamic> toJson() => {
        'title': title,
        'platform': platform,
        'thumbnail': thumbnail,
        'filePath': filePath,
        'isAudio': isAudio,
        'audioFormat': audioFormat,
        'quality': quality,
        'date': date,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        title: j['title'] as String,
        platform: j['platform'] as String? ?? '',
        thumbnail: j['thumbnail'] as String?,
        filePath: j['filePath'] as String,
        isAudio: j['isAudio'] as bool? ?? false,
        audioFormat: j['audioFormat'] as String? ?? 'mp3',
        quality: j['quality'] as String? ?? '',
        date: j['date'] as int,
      );
}

/// Item riwayat Scanner: satu PDF, atau beberapa JPG dari satu sesi scan.
class ScanRecord {
  final String type; // 'pdf' | 'jpg'
  final List<String> paths;
  final int pageCount;
  final int date;

  const ScanRecord({
    required this.type,
    required this.paths,
    required this.pageCount,
    required this.date,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);
  bool get isPdf => type == 'pdf';
  String get name => paths.first.split('/').last;

  Map<String, dynamic> toJson() => {
        'type': type,
        'paths': paths,
        'pageCount': pageCount,
        'date': date,
      };

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
        type: j['type'] as String,
        paths: (j['paths'] as List).cast<String>(),
        pageCount: j['pageCount'] as int? ?? 1,
        date: j['date'] as int,
      );
}
