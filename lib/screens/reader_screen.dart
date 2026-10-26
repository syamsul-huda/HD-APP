import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recent_file.dart';
import '../services/document_convert_service.dart';
import '../services/history_service.dart';
import '../utils/app_theme.dart';
import '../utils/fullscreen_reader.dart';
import '../utils/office/office_common.dart';
import '../utils/swipe_to_delete.dart';
import 'pdf_viewer_screen.dart';
import 'docx_viewer_screen.dart';
import 'xlsx_viewer_screen.dart';
import 'pptx_viewer_screen.dart';
import 'converted_pdf_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<RecentFile> _recent = [];
  Map<String, int> _pdfPages = {};
  bool _loading = false;

  // Pencarian di daftar Recent
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _formats = [
    ('PDF', Icons.picture_as_pdf_rounded, Color(0xFFE53935)),
    ('Word', Icons.article_rounded, Color(0xFF1565C0)),
    ('Excel', Icons.table_chart_rounded, Color(0xFF217346)),
    ('PPT', Icons.slideshow_rounded, Color(0xFFD24726)),
    ('TXT', Icons.text_snippet_rounded, Color(0xFF546E7A)),
    ('CSV', Icons.grid_on_rounded, Color(0xFF00695C)),
    ('RTF', Icons.notes_rounded, Color(0xFF6D4C41)),
    ('OpenDocument', Icons.description_rounded, Color(0xFF0288D1)),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _terms => _query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Cocokkan nama file / ekstensi; semua kata kunci harus ada
  /// (mis. "laporan pdf" → nama berisi "laporan" dan berformat PDF).
  List<RecentFile> get _filtered {
    final terms = _terms;
    if (terms.isEmpty) return _recent;
    return _recent.where((f) {
      final hay = '${f.name} ${f.extension}'.toLowerCase();
      return terms.every(hay.contains);
    }).toList();
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
          'docm',
          'dotx',
          'rtf',
          'xls',
          'xlsx',
          'xlsm',
          'ppt',
          'pptx',
          'pptm',
          'ppsx',
          'pps',
          'txt',
          'csv',
          'tsv',
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
          '.${ext.toUpperCase()} files cannot be opened on this device.');
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
    final sub = theme.colorScheme.onSurfaceVariant;
    final results = _filtered;
    final searching = _query.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('${_recent.length}',
                style: TextStyle(fontSize: 13, color: sub)),
            const Spacer(),
            TextButton(
              onPressed: _clearAll,
              child:
                  Text('Clear all', style: TextStyle(fontSize: 12, color: sub)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search documents by name or type',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: searching
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: Icon(Icons.close_rounded, size: 18, color: sub),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _query = '';
                    }),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
            searching
                ? '${results.length} of ${_recent.length} documents'
                : 'Swipe left on a document to delete it',
            style: TextStyle(fontSize: 12, color: sub)),
        const SizedBox(height: 8),
        if (searching && results.isEmpty)
          SoftCard(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Icon(Icons.search_off_rounded, color: sub),
              const SizedBox(width: 12),
              Expanded(
                child: Text('No documents match "${_query.trim()}"',
                    style: TextStyle(fontSize: 13, color: sub)),
              ),
            ]),
          )
        else
          ...results.map((f) => _buildRecentCard(f, theme)),
      ],
    );
  }

  /// Nama file dengan bagian yang cocok dengan pencarian ditebalkan.
  Widget _highlightedName(String name, ThemeData theme) {
    const base = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    final terms = _terms;
    if (terms.isEmpty) {
      return Text(name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }

    // Tandai karakter yang termasuk salah satu kata kunci
    final lower = name.toLowerCase();
    final marked = List<bool>.filled(name.length, false);
    for (final t in terms) {
      var i = lower.indexOf(t);
      while (i >= 0) {
        for (var k = i; k < i + t.length; k++) {
          marked[k] = true;
        }
        i = lower.indexOf(t, i + t.length);
      }
    }

    final hl = base.copyWith(
      color: AppTheme.readerColor,
      backgroundColor: AppTheme.readerColor.withOpacity(0.15),
    );
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= name.length; i++) {
      if (i == name.length || marked[i] != marked[start]) {
        spans.add(TextSpan(
            text: name.substring(start, i), style: marked[start] ? hl : null));
        start = i;
      }
    }
    return Text.rich(
      TextSpan(
          style: base.copyWith(color: theme.colorScheme.onSurface),
          children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
                    _highlightedName(file.name, theme),
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
      case 'docm':
      case 'dotx':
      case 'rtf':
      case 'odt':
        return const Color(0xFF1565C0);
      case 'xls':
      case 'xlsx':
      case 'xlsm':
      case 'ods':
        return const Color(0xFF217346);
      case 'ppt':
      case 'pptx':
      case 'pptm':
      case 'pps':
      case 'ppsx':
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
      case 'docm':
      case 'dotx':
      case 'rtf':
      case 'odt':
        return Icons.article_rounded;
      case 'xls':
      case 'xlsx':
      case 'xlsm':
      case 'ods':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
      case 'pptm':
      case 'pps':
      case 'ppsx':
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

const _wordExts = {'docx', 'docm', 'dotx', 'dotm', 'odt'};
const _sheetExts = {'xlsx', 'xlsm', 'xltx', 'xltm', 'ods', 'csv', 'tsv'};
const _slideExts = {'pptx', 'pptm', 'ppsx', 'ppsm', 'potx', 'odp'};
const _textExts = {'txt', 'log', 'md', 'json', 'xml'};

/// Kenali format dari isi file jika ekstensi tidak ada / tidak dikenal
/// (mis. file dari WhatsApp atau download tanpa nama yang benar).
Future<String> sniffDocumentType(String path, String ext) async {
  const known = {'pdf', ..._wordExts, ..._sheetExts, ..._slideExts, ..._textExts};
  if (known.contains(ext) || DocumentConvertService.legacyFormats.contains(ext)) return ext;
  try {
    final raf = await File(path).open();
    final head = await raf.read(8);
    await raf.close();
    if (head.length >= 4 && String.fromCharCodes(head.take(4)) == '%PDF') return 'pdf';
    if (head.length >= 8 && head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0) {
      return 'doc'; // OLE (doc/xls/ppt lama): LibreOffice mengenali isinya sendiri
    }
    if (head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B) {
      final pkg = OfficePackage(await File(path).readAsBytes());
      if (pkg.has('word/document.xml')) return 'docx';
      if (pkg.has('xl/workbook.xml')) return 'xlsx';
      if (pkg.has('ppt/presentation.xml')) return 'pptx';
      final mime = pkg.text('mimetype') ?? '';
      if (mime.endsWith('opendocument.text')) return 'odt';
      if (mime.endsWith('opendocument.spreadsheet')) return 'ods';
      if (mime.endsWith('opendocument.presentation')) return 'odp';
    }
  } catch (_) {}
  return ext;
}

/// Buka dokumen dengan viewer in-app yang sesuai (atau aplikasi eksternal).
/// Mengembalikan false jika format tidak bisa dibuka.
Future<bool> openDocumentViewer(
    BuildContext context, String path, String name, String ext) async {
  ext = await sniffDocumentType(path, ext.toLowerCase());
  Widget? screen;
  if (ext == 'pdf') {
    screen = PdfViewerScreen(path: path, title: name);
  } else if (_textExts.contains(ext)) {
    final content = decodeText(await File(path).readAsBytes());
    screen = _TextViewerScreen(title: name, content: content);
  } else if (_wordExts.contains(ext)) {
    screen = DocxViewerScreen(path: path, title: name, ext: ext == 'odt' ? 'odt' : 'docx');
  } else if (_sheetExts.contains(ext)) {
    final kind = switch (ext) { 'ods' => 'ods', 'csv' || 'tsv' => 'csv', _ => 'xlsx' };
    screen = XlsxViewerScreen(path: path, title: name, ext: kind);
  } else if (_slideExts.contains(ext)) {
    screen = PptxViewerScreen(path: path, title: name, ext: ext == 'odp' ? 'odp' : 'pptx');
  } else if (DocumentConvertService.legacyFormats.contains(ext)) {
    // .doc/.xls/.ppt/.rtf: konversi ke PDF dengan tata letak asli
    screen = ConvertedPdfScreen(path: path, title: name);
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
