import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recent_file.dart';
import '../services/history_service.dart';
import '../utils/app_theme.dart';
import '../utils/fullscreen_reader.dart';
import '../utils/swipe_to_delete.dart';
import 'pdf_viewer_screen.dart';
import 'docx_viewer_screen.dart';
import 'xlsx_viewer_screen.dart';
import 'pptx_viewer_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<RecentFile> _recent = [];
  Map<String, int> _pdfPages = {};
  bool _loading = false;

  static const _formats = [
    ('PDF', Icons.picture_as_pdf_rounded, Color(0xFFE53935)),
    ('Word', Icons.article_rounded, Color(0xFF1565C0)),
    ('Excel', Icons.table_chart_rounded, Color(0xFF217346)),
    ('PPT', Icons.slideshow_rounded, Color(0xFFD24726)),
    ('TXT', Icons.text_snippet_rounded, Color(0xFF546E7A)),
    ('CSV', Icons.grid_on_rounded, Color(0xFF00695C)),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final list = await HistoryService.loadRecentFiles();
    final valid = <RecentFile>[];
    for (final f in list) {
      if (await File(f.path).exists()) valid.add(f);
    }
    if (!mounted) return;
    setState(() => _recent = valid);
    _loadPdfPages();
  }

  Future<void> _addToRecent(String path, String name, String ext) async {
    final items = await HistoryService.touchRecentFile(path, name, ext);
    if (mounted) setState(() => _recent = items);
  }

  Future<void> _pickFile() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'odt',
          'ods',
          'odp',
        ],
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;
      await _openFile(result.files.first);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFile(PlatformFile file) async {
    String? path = file.path;

    if (path == null && file.bytes != null) {
      final dir = await getTemporaryDirectory();
      final tmp = File('${dir.path}/${file.name}');
      await tmp.writeAsBytes(file.bytes!);
      path = tmp.path;
    }

    if (path == null) {
      _snack('Unable to read this file');
      return;
    }

    final ext = (file.extension ?? '').toLowerCase();
    final name = file.name;
    await _addToRecent(path, name, ext);
    await _navigateToViewer(path, name, ext);
  }

  Future<void> _openRecent(RecentFile file) async {
    if (!await File(file.path).exists()) {
      await _removeRecent(file.path);
      _snack('File not found. It may have been moved or deleted.');
      return;
    }
    await _addToRecent(file.path, file.name, file.extension);
    await _navigateToViewer(file.path, file.name, file.extension);
  }

  Future<void> _navigateToViewer(String path, String name, String ext) async {
    if (!mounted) return;
    final opened = await openDocumentViewer(context, path, name, ext);
    _loadPdfPages();
    if (!opened && mounted) {
      _snack(
          '.${ext.toUpperCase()} files are not supported in-app. Install WPS Office to open them.');
    }
  }

  Future<void> _removeRecent(String path) async {
    setState(() => _recent.removeWhere((f) => f.path == path));
    final all = await HistoryService.loadRecentFiles()
      ..removeWhere((f) => f.path == path);
    await HistoryService.saveRecentFiles(all);
  }

  Future<void> _clearAll() async {
    final ok = await confirmDialog(context,
        title: 'Clear all history?',
        message: 'All ${_recent.length} documents will be removed from Recent. '
            'The files themselves will not be deleted.',
        confirmLabel: 'Clear all');
    if (!ok) return;
    setState(() => _recent.clear());
    await HistoryService.saveRecentFiles([]);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Document Reader')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _buildPickCard(theme),
          const SizedBox(height: 16),
          _buildFormatsSection(theme),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildRecentSection(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildPickCard(ThemeData theme) {
    const a = AppTheme.readerColor;
    return SoftCard(
      onTap: _loading ? null : _pickFile,
      padding: const EdgeInsets.all(20),
      shadowTint: a,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, Color.lerp(a, Colors.black, 0.18)!],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          child: _loading
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : const Icon(Icons.folder_open_rounded,
                  color: Colors.white, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_loading ? 'Opening...' : 'Choose a Document',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text('Read it right inside the app',
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withOpacity(0.85))),
          ]),
        ),
        const Icon(Icons.arrow_forward_rounded, color: Colors.white),
      ]),
    );
  }

  Widget _buildFormatsSection(ThemeData theme) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUPPORTED FORMATS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _formats.map((f) {
              final (label, icon, color) = f;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(label,
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
      ),
    );
  }

  Widget _buildRecentSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: _clearAll,
              child: Text('Clear all',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
        Text('Swipe left on a document to delete it',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        ..._recent.map((f) => _buildRecentCard(f, theme)),
      ],
    );
  }

  Widget _buildRecentCard(RecentFile file, ThemeData theme) {
    final color = _extColor(file.extension);
    final icon = _extIcon(file.extension);
    final sub = theme.colorScheme.onSurfaceVariant;
    final timeStr = timeAgo(file.date);
    final page = _pdfPages[file.path];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeToDelete(
        key: ValueKey(file.path),
        confirmTitle: 'Delete document?',
        confirmMessage: 'Remove "${file.name}" from Recent? '
            'The file itself will not be deleted.',
        onDelete: () => _removeRecent(file.path),
        child: SoftCard(
          onTap: () => _openRecent(file),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${file.extension.toUpperCase()} · $timeStr',
                        style: TextStyle(fontSize: 12, color: sub)),
                  ],
                ),
              ),
              if (page != null && page > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.readerColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bookmark_rounded,
                        size: 13, color: AppTheme.readerColor),
                    const SizedBox(width: 4),
                    Text('Page ${page + 1}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.readerColor)),
                  ]),
                )
              else
                Icon(Icons.chevron_right_rounded, color: sub),
            ],
          ),
        ),
      ),
    );
  }

  // Halaman terakhir dibaca untuk tiap PDF di daftar "Baru Dibuka"
  Future<void> _loadPdfPages() async {
    final pages = <String, int>{};
    for (final f in _recent.where((f) => f.extension == 'pdf')) {
      final p = await PdfViewerScreen.lastReadPage(f.path);
      if (p != null) pages[f.path] = p;
    }
    if (mounted) setState(() => _pdfPages = pages);
  }

  Color _extColor(String ext) {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFE53935);
      case 'doc':
      case 'docx':
      case 'odt':
        return const Color(0xFF1565C0);
      case 'xls':
      case 'xlsx':
      case 'ods':
        return const Color(0xFF217346);
      case 'ppt':
      case 'pptx':
      case 'odp':
        return const Color(0xFFD24726);
      case 'txt':
        return const Color(0xFF546E7A);
      case 'csv':
        return const Color(0xFF00695C);
      default:
        return const Color(0xFF7B8BFF);
    }
  }

  IconData _extIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'odt':
        return Icons.article_rounded;
      case 'xls':
      case 'xlsx':
      case 'ods':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Icons.slideshow_rounded;
      case 'txt':
        return Icons.text_snippet_rounded;
      case 'csv':
        return Icons.grid_on_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

/// Buka dokumen dengan viewer in-app yang sesuai (atau aplikasi eksternal).
/// Mengembalikan false jika format tidak bisa dibuka.
Future<bool> openDocumentViewer(
    BuildContext context, String path, String name, String ext) async {
  ext = ext.toLowerCase();
  Widget? screen;
  if (ext == 'pdf') {
    screen = PdfViewerScreen(path: path, title: name);
  } else if (ext == 'txt' || ext == 'csv') {
    final content = await File(path).readAsString();
    screen = _TextViewerScreen(title: name, content: content);
  } else if (ext == 'docx' || ext == 'odt') {
    screen = DocxViewerScreen(path: path, title: name);
  } else if (ext == 'xlsx' || ext == 'ods') {
    screen = XlsxViewerScreen(path: path, title: name);
  } else if (ext == 'pptx' || ext == 'odp') {
    screen = PptxViewerScreen(path: path, title: name);
  }

  if (screen == null) {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }
  if (!context.mounted) return false;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
  return true;
}

// ── In-app text viewer ────────────────────────────────────────────────────────

class _TextViewerScreen extends StatefulWidget {
  final String title;
  final String content;

  const _TextViewerScreen({required this.title, required this.content});

  @override
  State<_TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<_TextViewerScreen>
    with FullscreenReaderMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: isFullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              title: Text(widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF1A1A2E))),
              actions: [fullscreenButton(color: const Color(0xFF1A1A2E))],
            ),
      body: fullscreenBody(
        child: SafeArea(
          top: isFullscreen,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              widget.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.7,
                fontFamily: 'monospace',
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
