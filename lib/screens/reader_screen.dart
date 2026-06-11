import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recent_file.dart';
import 'pdf_viewer_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _prefKey = 'recent_files_reader';
  static const _maxRecent = 20;

  List<RecentFile> _recent = [];
  bool _loading = false;

  static const _formats = [
    ('PDF', Icons.picture_as_pdf_rounded, Color(0xFFE53935)),
    ('Word', Icons.article_rounded, Color(0xFF1565C0)),
    ('Excel', Icons.table_chart_rounded, Color(0xFF2E7D32)),
    ('PPT', Icons.slideshow_rounded, Color(0xFFE65100)),
    ('TXT', Icons.text_snippet_rounded, Color(0xFF546E7A)),
    ('CSV', Icons.grid_on_rounded, Color(0xFF00695C)),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = RecentFile.decodeList(raw);
      // Filter file yang masih ada
      final valid = <RecentFile>[];
      for (final f in list) {
        if (await File(f.path).exists()) valid.add(f);
      }
      setState(() => _recent = valid);
    } catch (_) {}
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, RecentFile.encodeList(_recent));
  }

  Future<void> _addToRecent(String path, String name, String ext) async {
    _recent.removeWhere((f) => f.path == path);
    _recent.insert(
      0,
      RecentFile(
        path: path,
        name: name,
        extension: ext.toLowerCase(),
        lastOpened: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_recent.length > _maxRecent) _recent = _recent.sublist(0, _maxRecent);
    setState(() {});
    await _saveRecent();
  }

  Future<void> _pickFile() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc', 'docx',
          'xls', 'xlsx',
          'ppt', 'pptx',
          'txt', 'csv',
          'odt', 'ods', 'odp',
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

    // Fallback: salin ke direktori temp jika path null (Android 13+ edge case)
    if (path == null && file.bytes != null) {
      final dir = await getTemporaryDirectory();
      final tmp = File('${dir.path}/${file.name}');
      await tmp.writeAsBytes(file.bytes!);
      path = tmp.path;
    }

    if (path == null) {
      _snack('Tidak dapat membaca file ini');
      return;
    }

    final ext = (file.extension ?? '').toLowerCase();
    final name = file.name;
    await _addToRecent(path, name, ext);
    await _navigateToViewer(path, name, ext);
  }

  Future<void> _openRecent(RecentFile file) async {
    if (!await File(file.path).exists()) {
      setState(() => _recent.removeWhere((f) => f.path == file.path));
      await _saveRecent();
      _snack('File tidak ditemukan, mungkin sudah dipindah atau dihapus');
      return;
    }
    await _addToRecent(file.path, file.name, file.extension);
    await _navigateToViewer(file.path, file.name, file.extension);
  }

  Future<void> _navigateToViewer(String path, String name, String ext) async {
    if (!mounted) return;

    if (ext == 'pdf') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(path: path, title: name),
        ),
      );
      return;
    }

    if (ext == 'txt' || ext == 'csv') {
      final content = await File(path).readAsString();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _TextViewerScreen(title: name, content: content),
        ),
      );
      return;
    }

    // Word, Excel, PPT, dan format lain → buka dengan app sistem
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      _snack('Tidak ada aplikasi yang bisa membuka file ini. Install WPS Office atau Microsoft Office.');
    }
  }

  void _removeRecent(String path) async {
    setState(() => _recent.removeWhere((f) => f.path == path));
    await _saveRecent();
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
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFFD4AF37), size: 20),
            SizedBox(width: 8),
            Text('Pembaca Dokumen'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFormatsSection(),
            const SizedBox(height: 20),
            _buildPickButton(),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              _buildRecentSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FORMAT YANG DIDUKUNG',
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
          children: _formats.map((f) {
            final (label, icon, color) = f;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 5),
                  Text(
                    label,
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

  Widget _buildPickButton() {
    return ElevatedButton.icon(
      onPressed: _loading ? null : _pickFile,
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.folder_open_rounded),
      label: Text(_loading ? 'Membuka...' : 'Pilih File Dokumen'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD4AF37),
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, size: 18, color: Colors.white60),
            const SizedBox(width: 6),
            const Text(
              'Baru Dibuka',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                setState(() => _recent.clear());
                await _saveRecent();
              },
              child: const Text(
                'Hapus Semua',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._recent.map(_buildRecentCard),
      ],
    );
  }

  Widget _buildRecentCard(RecentFile file) {
    final color = _extColor(file.extension);
    final icon = _extIcon(file.extension);
    final now = DateTime.now();
    final diff = now.difference(file.date);
    final timeStr = diff.inDays > 0
        ? '${diff.inDays} hari lalu'
        : diff.inHours > 0
            ? '${diff.inHours} jam lalu'
            : '${diff.inMinutes} menit lalu';

    return Dismissible(
      key: Key(file.path),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
      ),
      onDismissed: (_) => _removeRecent(file.path),
      child: GestureDetector(
        onTap: () => _openRecent(file),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A0E),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            file.extension.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: const TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Color _extColor(String ext) {
    switch (ext) {
      case 'pdf': return const Color(0xFFE53935);
      case 'doc': case 'docx': case 'odt': return const Color(0xFF1565C0);
      case 'xls': case 'xlsx': case 'ods': return const Color(0xFF2E7D32);
      case 'ppt': case 'pptx': case 'odp': return const Color(0xFFE65100);
      case 'txt': return const Color(0xFF546E7A);
      case 'csv': return const Color(0xFF00695C);
      default: return const Color(0xFFD4AF37);
    }
  }

  IconData _extIcon(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc': case 'docx': case 'odt': return Icons.article_rounded;
      case 'xls': case 'xlsx': case 'ods': return Icons.table_chart_rounded;
      case 'ppt': case 'pptx': case 'odp': return Icons.slideshow_rounded;
      case 'txt': return Icons.text_snippet_rounded;
      case 'csv': return Icons.grid_on_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }
}

// ── In-app text viewer ────────────────────────────────────────────────────────

class _TextViewerScreen extends StatelessWidget {
  final String title;
  final String content;

  const _TextViewerScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          content,
          style: const TextStyle(
            fontSize: 13,
            height: 1.6,
            fontFamily: 'monospace',
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
