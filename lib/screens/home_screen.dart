import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlCtrl = TextEditingController();
  final _api = ApiService();

  bool _fetching = false;
  VideoInfo? _info;
  VideoFormat? _selectedFormat;
  String? _fetchError;
  final _downloads = <DownloadTask>[];

  // Download type: 'video' atau 'audio'
  String _downloadType = 'video';
  // Format audio yang dipilih saat mode audio
  VideoFormat? _selectedAudioFormat;

  static const _supportedPlatforms = [
    ('YouTube', '▶', Color(0xFFFF0000)),
    ('TikTok', '♫', Color(0xFF69C9D0)),
    ('Instagram', '◈', Color(0xFFE1306C)),
    ('Facebook', 'f', Color(0xFF1877F2)),
    ('Twitter / X', '✕', Color(0xFF888888)),
    ('Reddit', '●', Color(0xFFFF4500)),
    ('Telegram', '✈', Color(0xFF2CA5E0)),
    ('dan 1000+ lainnya', '∞', Color(0xFF7B8BFF)),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      setState(() {
        _urlCtrl.text = data!.text!;
        _info = null;
        _fetchError = null;
      });
    }
  }

  Future<void> _fetchInfo() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _snack('Masukkan URL video terlebih dahulu');
      return;
    }
    if (!url.startsWith('http')) {
      _snack('URL tidak valid — harus dimulai dengan http:// atau https://');
      return;
    }

    setState(() {
      _fetching = true;
      _info = null;
      _selectedFormat = null;
      _selectedAudioFormat = null;
      _fetchError = null;
    });

    try {
      final info = await _api.getInfo(url);
      setState(() {
        _info = info;
        _selectedFormat = info.formats.first;
        _selectedAudioFormat = info.audioFormats.isNotEmpty
            ? info.audioFormats.first
            : null;
        _fetching = false;
      });
    } catch (e) {
      setState(() {
        _fetchError = e.toString().replaceFirst('Exception: ', '');
        _fetching = false;
      });
    }
  }

  // Cari task aktif yang cocok dengan pilihan format saat ini
  DownloadTask? _activeTaskFor() {
    if (_info == null) return null;
    final isAudio = _downloadType == 'audio';
    final fmt = isAudio ? _selectedAudioFormat : _selectedFormat;
    if (fmt == null) return null;
    final url = _urlCtrl.text.trim();
    for (final t in _downloads) {
      if (t.isActive &&
          t.url == url &&
          t.isAudio == isAudio &&
          t.formatId == fmt.formatId &&
          (!isAudio || t.audioFormat == (fmt.audioFmt ?? 'mp3'))) {
        return t;
      }
    }
    return null;
  }

  void _startDownload() {
    if (_info == null) return;
    final isAudio = _downloadType == 'audio';
    if (isAudio && _selectedAudioFormat == null) return;
    if (!isAudio && _selectedFormat == null) return;

    // Jangan izinkan download yang sama dua kali
    if (_activeTaskFor() != null) return;

    final fmt = isAudio ? _selectedAudioFormat! : _selectedFormat!;

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _info!.title,
      thumbnail: _info!.thumbnail,
      url: _urlCtrl.text.trim(),
      formatId: fmt.formatId,
      quality: fmt.quality,
      platform: _info!.platform,
      isAudio: isAudio,
      audioFormat: isAudio ? (fmt.audioFmt ?? 'mp3') : 'mp3',
    );

    setState(() => _downloads.insert(0, task));

    _api.download(
      task: task,
      onUpdate: (status, progress, received, total) {
        setState(() {
          task.status = status;
          task.progress = progress;
          task.received = received;
          task.total = total;
          if (status == DownloadStatus.downloading) task.tickSpeed(received);
        });
      },
      onDone: (path) {
        setState(() {
          task.status = DownloadStatus.completed;
          task.filePath = path;
          task.progress = 1.0;
        });
        if (kIsWeb) {
          _snack('Download selesai! Cek folder Downloads kamu.');
        } else {
          _snack(
            'Download selesai!',
            action: SnackBarAction(
              label: 'BUKA',
              textColor: const Color(0xFF7B8BFF),
              onPressed: () => OpenFilex.open(path),
            ),
          );
        }
      },
      onError: (err) {
        if (err == 'dibatalkan') {
          setState(() => task.status = DownloadStatus.cancelled);
          return;
        }
        setState(() {
          task.status = DownloadStatus.failed;
          task.error = err;
        });
        _snack('Download gagal: $err');
      },
    );
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: action,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSettings() {
    final ctrl = TextEditingController(text: _api.backendUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2640),
        title: const Text('Pengaturan Backend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'URL Backend Server',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.x:8000',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• Android Emulator: http://10.0.2.2:8000\n'
              '• HP Fisik: http://<IP-Komputer>:8000\n'
              '• iOS Simulator: http://localhost:8000',
              style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _api.setBackendUrl(ctrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Backend URL disimpan');
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  String _platformIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('youtube')) return '▶';
    if (p.contains('tiktok')) return '♫';
    if (p.contains('instagram')) return '◈';
    if (p.contains('facebook')) return 'f';
    if (p.contains('twitter') || p.contains('x.com')) return '✕';
    if (p.contains('reddit')) return '●';
    if (p.contains('telegram')) return '✈';
    return '🌐';
  }

  String _formatViewCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M tayangan';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K tayangan';
    return '$n tayangan';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7B8BFF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: Color(0xFF7B8BFF),
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Text('VideoSaver'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 22),
            onPressed: _showSettings,
            tooltip: 'Pengaturan',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPlatformSection(),
            const SizedBox(height: 20),
            _buildUrlSection(),
            if (_fetchError != null) ...[
              const SizedBox(height: 12),
              _buildErrorCard(_fetchError!),
            ],
            if (_info != null) ...[
              const SizedBox(height: 20),
              _buildVideoInfoCard(_info!),
              const SizedBox(height: 16),
              _buildDownloadTypeToggle(),
              const SizedBox(height: 14),
              if (_downloadType == 'video')
                _buildFormatPicker(_info!)
              else
                _buildAudioFormatPicker(_info!),
              const SizedBox(height: 14),
              _buildDownloadButton(),
            ],
            if (_downloads.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: Colors.white60,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Riwayat Download',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(
                      () => _downloads.removeWhere((d) => !d.isActive),
                    ),
                    child: const Text(
                      'Hapus Selesai',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._downloads.map(_buildDownloadCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PLATFORM YANG DIDUKUNG',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _supportedPlatforms.map((p) {
            final (name, icon, color) = p;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    icon,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildUrlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'URL VIDEO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _urlCtrl,
          style: const TextStyle(fontSize: 14),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _fetchInfo(),
          onChanged: (_) {
            if (_fetchError != null || _info != null) {
              setState(() {
                _fetchError = null;
                _info = null;
              });
            }
          },
          decoration: InputDecoration(
            hintText: 'Paste URL video di sini...',
            hintStyle: const TextStyle(color: Colors.white24),
            prefixIcon: const Icon(Icons.link_rounded, color: Colors.white38, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_urlCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white38),
                    onPressed: () => setState(() {
                      _urlCtrl.clear();
                      _info = null;
                      _fetchError = null;
                    }),
                    padding: EdgeInsets.zero,
                  ),
                IconButton(
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  color: const Color(0xFF7B8BFF),
                  onPressed: _pasteFromClipboard,
                  tooltip: 'Paste dari clipboard',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _fetching ? null : _fetchInfo,
          icon: _fetching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.search_rounded),
          label: Text(_fetching ? 'Mengambil info video...' : 'Ambil Info Video'),
        ),
      ],
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfoCard(VideoInfo info) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.thumbnail != null)
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: info.thumbnail!,
                  width: double.infinity,
                  height: 190,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 190,
                    color: const Color(0xFF151929),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 100,
                    color: const Color(0xFF151929),
                    child: const Center(
                      child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.white24),
                    ),
                  ),
                ),
                if (info.durationStr != null)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        info.durationStr!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B8BFF).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_platformIcon(info.platform)} ${info.platform}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (info.uploader != null)
                      _metaItem(Icons.person_outline_rounded, info.uploader!),
                    if (info.viewCount != null)
                      _metaItem(Icons.visibility_outlined, _formatViewCount(info.viewCount!)),
                    if (info.formats.isNotEmpty)
                      _metaItem(
                        Icons.high_quality_rounded,
                        '${info.formats.length - 1} format tersedia',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white38),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }

  Widget _buildFormatPicker(VideoInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PILIH KUALITAS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: info.formats.map((fmt) {
            final selected = _selectedFormat?.formatId == fmt.formatId;
            return GestureDetector(
              onTap: () => setState(() => _selectedFormat = fmt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF7B8BFF), Color(0xFF5B6CF5)],
                        )
                      : null,
                  color: selected ? null : const Color(0xFF1E2640),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF7B8BFF)
                        : Colors.white12,
                    width: selected ? 1.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF7B8BFF).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  fmt.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Tombol Download (normal → progress bar saat downloading) ────────────────

  Widget _buildDownloadButton() {
    final isAudio = _downloadType == 'audio';
    final color = isAudio ? const Color(0xFF7B8BFF) : const Color(0xFF4ECDC4);
    final activeTask = _activeTaskFor();

    if (activeTask == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _startDownload,
          icon: Icon(isAudio ? Icons.music_note_rounded : Icons.download_rounded),
          label: Text(isAudio ? 'Download Audio' : 'Download Video'),
          style: ElevatedButton.styleFrom(backgroundColor: color),
        ),
      );
    }

    // Tombol berubah jadi progress bar saat sedang download
    final isPreparing = activeTask.status == DownloadStatus.preparing;
    final pct = activeTask.progress > 0
        ? (activeTask.progress * 100).toStringAsFixed(0)
        : null;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Latar abu-abu
            Container(color: color.withOpacity(0.12)),
            // Fill bar progress
            if (!isPreparing && activeTask.progress > 0)
              FractionallySizedBox(
                widthFactor: activeTask.progress.clamp(0.0, 1.0),
                child: Container(color: color.withOpacity(0.30)),
              ),
            // Garis border tipis
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.45), width: 1.2),
              ),
            ),
            // Konten baris
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: isPreparing
                        ? CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          )
                        : Icon(Icons.downloading_rounded, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPreparing
                          ? 'Memproses di server...'
                          : activeTask.statusText,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pct != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$pct%',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Toggle Video / Audio ────────────────────────────────────────────────────

  Widget _buildDownloadTypeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JENIS DOWNLOAD',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E2640),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _typeTab(
                icon: Icons.videocam_rounded,
                label: 'Video',
                value: 'video',
                color: const Color(0xFF4ECDC4),
              ),
              _typeTab(
                icon: Icons.music_note_rounded,
                label: 'Audio Saja',
                value: 'audio',
                color: const Color(0xFF7B8BFF),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeTab({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final selected = _downloadType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _downloadType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected
                ? Border.all(color: color.withOpacity(0.5))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? color : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? color : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Audio format picker ─────────────────────────────────────────────────────

  Widget _buildAudioFormatPicker(VideoInfo info) {
    if (info.audioFormats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Format audio tidak tersedia untuk video ini.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final audioColor = const Color(0xFF7B8BFF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PILIH FORMAT AUDIO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        ...info.audioFormats.map((fmt) {
          final selected = _selectedAudioFormat?.audioFmt == fmt.audioFmt;
          return GestureDetector(
            onTap: () => setState(() => _selectedAudioFormat = fmt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? audioColor.withOpacity(0.12)
                    : const Color(0xFF1E2640),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? audioColor : Colors.white10,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? audioColor.withOpacity(0.2)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        fmt.quality, // 'MP3', 'M4A', 'Opus'
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: selected ? audioColor : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmt.quality,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.white70,
                          ),
                        ),
                        if (fmt.description != null)
                          Text(
                            fmt.description!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        color: audioColor, size: 20),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Download card ───────────────────────────────────────────────────────────

  Widget _buildDownloadCard(DownloadTask task) {
    final isDone = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isCancelled = task.status == DownloadStatus.cancelled;

    Color statusColor = const Color(0xFF7B8BFF);
    if (isDone) statusColor = const Color(0xFF4ECDC4);
    if (isFailed) statusColor = Colors.redAccent;
    if (isCancelled) statusColor = Colors.white38;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2640),
        borderRadius: BorderRadius.circular(14),
        border: isDone
            ? Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.25))
            : null,
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 60,
              child: task.thumbnail != null
                  ? CachedNetworkImage(
                      imageUrl: task.thumbnail!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _taskIcon(statusColor, task.status),
                    )
                  : _taskIcon(statusColor, task.status),
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                Text(
                  '${task.typeLabel} · ${task.platform}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 5),
                if (task.status == DownloadStatus.preparing) ...[
                  // Fase 1: server sedang proses (yt-dlp + ffmpeg)
                  Row(
                    children: [
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Memproses di server...',
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                    ],
                  ),
                ] else if (task.status == DownloadStatus.downloading) ...[
                  // Fase 2: transfer file dengan progress akurat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        task.statusText,
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                      if (task.progress > 0)
                        Text(
                          '${(task.progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress > 0 ? task.progress : null,
                      backgroundColor: Colors.white10,
                      color: statusColor,
                      minHeight: 5,
                    ),
                  ),
                ] else ...[
                  Text(
                    task.statusText,
                    style: TextStyle(fontSize: 11, color: statusColor),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Action
          if (isDone)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!kIsWeb && task.filePath != null) ...[
                  _actionIcon(
                    Icons.open_in_new_rounded,
                    'Buka',
                    () => OpenFilex.open(task.filePath!),
                  ),
                  _actionIcon(
                    Icons.share_rounded,
                    'Bagikan',
                    () => Share.shareXFiles([XFile(task.filePath!)]),
                  ),
                ] else
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF4ECDC4), size: 24),
              ],
            )
          else if (task.isActive)
            _actionIcon(
              Icons.cancel_rounded,
              'Batalkan',
              () {
                task.cancelToken?.cancel();
                setState(() => task.status = DownloadStatus.cancelled);
              },
              color: Colors.white30,
            ),
        ],
      ),
    );
  }

  Widget _taskIcon(Color color, DownloadStatus status) {
    final icon = status == DownloadStatus.completed
        ? Icons.check_circle_rounded
        : status == DownloadStatus.failed
            ? Icons.error_rounded
            : status == DownloadStatus.cancelled
                ? Icons.cancel_rounded
                : Icons.download_rounded;

    return Container(
      color: color.withOpacity(0.1),
      child: Center(
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }

  Widget _actionIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color ?? Colors.white54,
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
