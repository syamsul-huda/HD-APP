import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';
import '../models/history_records.dart';
import '../services/api_service.dart';
import '../services/history_service.dart';
import '../utils/app_theme.dart';
import '../utils/swipe_to_delete.dart';

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
  final _downloads = <DownloadTask>[]; // sesi ini: aktif / gagal / batal
  List<DownloadRecord> _history = []; // tersimpan: download selesai

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
    ('and 1000+ more', '∞', Color(0xFF7B8BFF)),
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
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
      _snack('Please enter a video URL first');
      return;
    }
    if (!url.startsWith('http')) {
      _snack('Invalid URL — it must start with http:// or https://');
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
        _selectedAudioFormat =
            info.audioFormats.isNotEmpty ? info.audioFormats.first : null;
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
      onDone: (path) async {
        setState(() {
          task.status = DownloadStatus.completed;
          task.filePath = path;
          task.progress = 1.0;
        });
        if (!kIsWeb) {
          // Pindahkan dari daftar sesi ke riwayat tersimpan
          final items = await HistoryService.addDownload(DownloadRecord(
            title: task.title,
            platform: task.platform,
            thumbnail: task.thumbnail,
            filePath: path,
            isAudio: task.isAudio,
            audioFormat: task.audioFormat,
            quality: task.quality,
            date: DateTime.now().millisecondsSinceEpoch,
          ));
          if (mounted) {
            setState(() {
              _history = items;
              _downloads.remove(task);
            });
          }
        }
        if (kIsWeb) {
          _snack('Download complete! Check your Downloads folder.');
        } else {
          _snack(
            'Download complete!',
            action: SnackBarAction(
              label: 'OPEN',
              textColor: const Color(0xFF7B8BFF),
              onPressed: () => OpenFilex.open(path),
            ),
          );
        }
      },
      onError: (err) {
        if (err == 'cancelled') {
          setState(() => task.status = DownloadStatus.cancelled);
          return;
        }
        setState(() {
          task.status = DownloadStatus.failed;
          task.error = err;
        });
        _snack('Download failed: $err');
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
        title: const Text('Backend Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend Server URL',
              style: TextStyle(fontSize: 12, color: _sub),
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
            Text(
              '• Android Emulator: http://10.0.2.2:8000\n'
              '• Physical phone: http://<Computer-IP>:8000\n'
              '• iOS Simulator: http://localhost:8000',
              style: TextStyle(fontSize: 11, color: _sub, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _api.setBackendUrl(ctrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Backend URL saved');
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            child: const Text('Save'),
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
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M views';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K views';
    return '$n views';
  }

  // ── Warna tema ──────────────────────────────────────────────────────────────
  static const _accent = AppTheme.downloaderColor; // video
  static const _audioColor = AppTheme.seed; // audio

  Color get _sub => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _border => Theme.of(context).colorScheme.outlineVariant;
  Color get _fill => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF222838)
      : const Color(0xFFF4F5FA);

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _sub,
                letterSpacing: 1)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Downloader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 22),
            onPressed: _showSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _buildUrlSection(),
          if (_fetchError != null) ...[
            const SizedBox(height: 12),
            _buildErrorCard(_fetchError!),
          ],
          if (_info != null) ...[
            const SizedBox(height: 16),
            _buildVideoInfoCard(_info!),
            const SizedBox(height: 16),
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDownloadTypeToggle(),
                  const SizedBox(height: 16),
                  if (_downloadType == 'video')
                    _buildFormatPicker(_info!)
                  else
                    _buildAudioFormatPicker(_info!),
                  const SizedBox(height: 16),
                  _buildDownloadButton(),
                ],
              ),
            ),
          ],
          if (_info == null) ...[
            const SizedBox(height: 24),
            _buildPlatformSection(),
          ],
          if (_downloads.isNotEmpty) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                Text('Downloads',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_downloads.any((d) => !d.isActive))
                  TextButton(
                    onPressed: () => setState(
                      () => _downloads.removeWhere((d) => !d.isActive),
                    ),
                    child: Text('Clear finished',
                        style: TextStyle(fontSize: 12, color: _sub)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ..._downloads.map(_buildDownloadCard),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _clearHistory,
                  child: Text('Clear all',
                      style: TextStyle(fontSize: 12, color: _sub)),
                ),
              ],
            ),
            Text('Swipe left on an item to delete it',
                style: TextStyle(fontSize: 12, color: _sub)),
            const SizedBox(height: 8),
            ..._history.map(_buildHistoryCard),
          ],
        ],
      ),
    );
  }

  Widget _buildPlatformSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SUPPORTED PLATFORMS'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _supportedPlatforms.map((p) {
            final (name, icon, color) = p;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(icon, style: TextStyle(fontSize: 11, color: color)),
                  const SizedBox(width: 6),
                  Text(name,
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Kartu utama: input URL + tombol ambil info
  Widget _buildUrlSection() {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              ),
              child: const Icon(Icons.link_rounded, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Paste a video link',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('YouTube, TikTok, Instagram & more',
                        style: TextStyle(fontSize: 12, color: _sub)),
                  ]),
            ),
          ]),
          const SizedBox(height: 16),
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
              } else {
                setState(() {}); // tampilkan/sembunyikan tombol clear
              }
            },
            decoration: InputDecoration(
              hintText: 'https://...',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_urlCtrl.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear_rounded, size: 18, color: _sub),
                      onPressed: () => setState(() {
                        _urlCtrl.clear();
                        _info = null;
                        _fetchError = null;
                      }),
                    ),
                  IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    color: _accent,
                    onPressed: _pasteFromClipboard,
                    tooltip: 'Paste from clipboard',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _fetching ? null : _fetchInfo,
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            icon: _fetching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.search_rounded),
            label:
                Text(_fetching ? 'Fetching video info...' : 'Get Video Info'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(error,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfoCard(VideoInfo info) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: _border)
            : null,
        boxShadow: AppTheme.softShadow(context),
      ),
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
                    color: _fill,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 100,
                    color: _fill,
                    child: Center(
                      child: Icon(Icons.broken_image_rounded,
                          size: 40, color: _sub),
                    ),
                  ),
                ),
                if (info.durationStr != null)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(info.durationStr!,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                    ),
                    child: Text(
                      '${_platformIcon(info.platform)} ${info.platform}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
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
                      _metaItem(Icons.visibility_outlined,
                          _formatViewCount(info.viewCount!)),
                    if (info.formats.isNotEmpty)
                      _metaItem(
                        Icons.high_quality_rounded,
                        '${info.formats.length - 1} formats available',
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
        Icon(icon, size: 14, color: _sub),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: _sub)),
      ],
    );
  }

  Widget _buildFormatPicker(VideoInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SELECT QUALITY'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: info.formats.map((fmt) {
            final selected = _selectedFormat?.formatId == fmt.formatId;
            return GestureDetector(
              onTap: () => setState(() => _selectedFormat = fmt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? _accent : _fill,
                  borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                  border:
                      Border.all(color: selected ? _accent : _border, width: 1),
                ),
                child: Text(
                  fmt.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
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
    final color = isAudio ? _audioColor : _accent;
    final activeTask = _activeTaskFor();

    if (activeTask == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _startDownload,
          icon:
              Icon(isAudio ? Icons.music_note_rounded : Icons.download_rounded),
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
      height: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        child: Stack(
          children: [
            Container(color: color.withOpacity(0.12)),
            if (!isPreparing && activeTask.progress > 0)
              FractionallySizedBox(
                widthFactor: activeTask.progress.clamp(0.0, 1.0),
                child: Container(color: color.withOpacity(0.30)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: isPreparing
                        ? CircularProgressIndicator(
                            strokeWidth: 2, color: color)
                        : Icon(Icons.downloading_rounded,
                            size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPreparing
                          ? 'Processing on server...'
                          : activeTask.statusText,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pct != null) ...[
                    const SizedBox(width: 8),
                    Text('$pct%',
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
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
        _label('DOWNLOAD TYPE'),
        Container(
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _typeTab(
                icon: Icons.videocam_rounded,
                label: 'Video',
                value: 'video',
                color: _accent,
              ),
              _typeTab(
                icon: Icons.music_note_rounded,
                label: 'Audio Only',
                value: 'audio',
                color: _audioColor,
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
            color: selected
                ? Theme.of(context).colorScheme.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusChip),
            boxShadow: selected ? AppTheme.softShadow(context) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? color : _sub),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : _sub,
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No audio formats available for this video.',
            style: TextStyle(color: _sub, fontSize: 13)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SELECT AUDIO FORMAT'),
        ...info.audioFormats.map((fmt) {
          final selected = _selectedAudioFormat?.audioFmt == fmt.audioFmt;
          return GestureDetector(
            onTap: () => setState(() => _selectedAudioFormat = fmt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? _audioColor.withOpacity(0.12) : _fill,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(
                  color: selected ? _audioColor : _border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _audioColor.withOpacity(selected ? 0.2 : 0.08),
                      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                    ),
                    child: Icon(Icons.music_note_rounded,
                        size: 18, color: selected ? _audioColor : _sub),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmt.quality,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (fmt.description != null)
                          Text(fmt.description!,
                              style: TextStyle(fontSize: 12, color: _sub)),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                        color: _audioColor, size: 20),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── History ─────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    final items = await HistoryService.loadDownloads();
    if (mounted) setState(() => _history = items);
  }

  Future<void> _removeHistory(DownloadRecord r) async {
    setState(() => _history.remove(r));
    await HistoryService.saveDownloads(_history);
  }

  Future<void> _clearHistory() async {
    final ok = await confirmDialog(context,
        title: 'Clear download history?',
        message: 'All ${_history.length} items will be removed from history. '
            'Downloaded files will not be deleted.',
        confirmLabel: 'Clear all');
    if (!ok) return;
    setState(() => _history.clear());
    await HistoryService.saveDownloads([]);
  }

  Future<void> _openHistory(DownloadRecord r) async {
    if (!await File(r.filePath).exists()) {
      _snack('File not found. It may have been moved or deleted.');
      return;
    }
    await OpenFilex.open(r.filePath);
  }

  Widget _buildHistoryCard(DownloadRecord r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeToDelete(
        key: ValueKey(r.filePath),
        confirmTitle: 'Delete from history?',
        confirmMessage: 'Remove "${r.title}" from download history? '
            'The downloaded file will not be deleted.',
        onDelete: () => _removeHistory(r),
        child: SoftCard(
          onTap: () => _openHistory(r),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: r.thumbnail != null
                      ? CachedNetworkImage(
                          imageUrl: r.thumbnail!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _historyIcon(r),
                        )
                      : _historyIcon(r),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                        '${r.typeLabel} · ${r.platform} · ${timeAgo(r.dateTime)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: _sub)),
                  ],
                ),
              ),
              _actionIcon(Icons.share_rounded, 'Share',
                  () => Share.shareXFiles([XFile(r.filePath)])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyIcon(DownloadRecord r) => Container(
        color: (r.isAudio ? _audioColor : _accent).withOpacity(0.12),
        child: Icon(r.isAudio ? Icons.music_note_rounded : Icons.movie_rounded,
            color: r.isAudio ? _audioColor : _accent),
      );

  // ── Download card ───────────────────────────────────────────────────────────

  Widget _buildDownloadCard(DownloadTask task) {
    final isDone = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isCancelled = task.status == DownloadStatus.cancelled;

    Color statusColor = _accent;
    if (isDone) statusColor = AppTheme.scannerColor;
    if (isFailed) statusColor = Colors.redAccent;
    if (isCancelled) statusColor = _sub;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              child: SizedBox(
                width: 60,
                height: 60,
                child: task.thumbnail != null
                    ? CachedNetworkImage(
                        imageUrl: task.thumbnail!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _taskIcon(statusColor, task.status),
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
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${task.typeLabel} · ${task.platform}',
                    style: TextStyle(fontSize: 12, color: _sub),
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
                          'Processing on server...',
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
                        backgroundColor: _border,
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
                      'Open',
                      () => OpenFilex.open(task.filePath!),
                    ),
                    _actionIcon(
                      Icons.share_rounded,
                      'Share',
                      () => Share.shareXFiles([XFile(task.filePath!)]),
                    ),
                  ] else
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.scannerColor, size: 24),
                ],
              )
            else if (task.isActive)
              _actionIcon(
                Icons.cancel_rounded,
                'Cancel',
                () {
                  task.cancelToken?.cancel();
                  setState(() => task.status = DownloadStatus.cancelled);
                },
                color: _sub,
              ),
          ],
        ),
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
      color: color ?? _sub,
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
