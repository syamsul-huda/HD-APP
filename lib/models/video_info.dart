class VideoFormat {
  final String formatId;
  final String quality;
  final String ext;
  final int? filesize;
  final String? filesizeStr;
  final int? fps;
  final bool isAudio;
  final String? audioFmt;      // 'mp3', 'm4a', 'opus' — hanya untuk audio
  final String? description;   // label panjang untuk audio

  const VideoFormat({
    required this.formatId,
    required this.quality,
    required this.ext,
    this.filesize,
    this.filesizeStr,
    this.fps,
    this.isAudio = false,
    this.audioFmt,
    this.description,
  });

  factory VideoFormat.fromJson(Map<String, dynamic> j) => VideoFormat(
        formatId: j['format_id'] as String,
        quality: j['quality'] as String,
        ext: j['ext'] as String? ?? 'mp4',
        filesize: (j['filesize'] as num?)?.toInt(),
        filesizeStr: j['filesize_str'] as String?,
        fps: (j['fps'] as num?)?.toInt(),
        isAudio: j['is_audio'] as bool? ?? false,
        audioFmt: j['audio_fmt'] as String?,
        description: j['description'] as String?,
      );

  // Label singkat untuk chip
  String get label {
    if (isAudio) return quality; // 'MP3', 'M4A', 'Opus'
    final buf = StringBuffer(quality);
    if (fps != null && fps! > 30) buf.write(' ${fps}fps');
    if (filesizeStr != null) buf.write(' · $filesizeStr');
    return buf.toString();
  }
}

class VideoInfo {
  final String title;
  final String? thumbnail;
  final int? duration;
  final String? durationStr;
  final String? uploader;
  final String platform;
  final int? viewCount;
  final List<VideoFormat> formats;       // format video
  final List<VideoFormat> audioFormats;  // format audio saja

  const VideoInfo({
    required this.title,
    this.thumbnail,
    this.duration,
    this.durationStr,
    this.uploader,
    required this.platform,
    this.viewCount,
    required this.formats,
    this.audioFormats = const [],
  });

  factory VideoInfo.fromJson(Map<String, dynamic> j) => VideoInfo(
        title: j['title'] as String,
        thumbnail: j['thumbnail'] as String?,
        duration: (j['duration'] as num?)?.toInt(),
        durationStr: j['duration_str'] as String?,
        uploader: j['uploader'] as String?,
        platform: j['platform'] as String,
        viewCount: (j['view_count'] as num?)?.toInt(),
        formats: (j['formats'] as List)
            .map((f) => VideoFormat.fromJson(f as Map<String, dynamic>))
            .toList(),
        audioFormats: ((j['audio_formats'] as List?) ?? [])
            .map((f) => VideoFormat.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}
