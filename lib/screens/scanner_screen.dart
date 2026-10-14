import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/history_records.dart';
import '../services/history_service.dart';
import '../utils/app_theme.dart';
import '../utils/swipe_to_delete.dart';
import 'pdf_viewer_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  List<String> _pages = [];
  bool _saving = false;
  int _viewPage = 0;
  final _pageCtrl = PageController();

  List<ScanRecord> _history = [];

  static const _accent = AppTheme.scannerColor;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final items = await HistoryService.loadScans();
    if (mounted) setState(() => _history = items);
  }

  Future<void> _addHistory(String type, List<String> paths) async {
    final items = await HistoryService.addScan(ScanRecord(
      type: type,
      paths: paths,
      pageCount: _pages.length,
      date: DateTime.now().millisecondsSinceEpoch,
    ));
    if (mounted) setState(() => _history = items);
  }

  static const _docTypes = [
    ('ID Card', Icons.credit_card_rounded, Color(0xFF1565C0)),
    ('Diploma', Icons.school_rounded, Color(0xFF217346)),
    ('License', Icons.directions_car_rounded, Color(0xFFE65100)),
    ('Certificate', Icons.workspace_premium_rounded, Color(0xFF7B8BFF)),
    ('Other', Icons.description_rounded, Color(0xFF546E7A)),
  ];

  Future<void> _startScan() async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        isGalleryImportAllowed: true,
      );
      if (pictures != null && pictures.isNotEmpty) {
        setState(() {
          _pages = pictures;
          _viewPage = 0;
        });
        if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      }
    } catch (e) {
      _snack('Camera not available: $e');
    }
  }

  Future<void> _saveAsPdf() async {
    if (_pages.isEmpty) return;
    setState(() => _saving = true);
    try {
      final pdf = pw.Document();
      for (final p in _pages) {
        final imgBytes = await File(p).readAsBytes();
        final image = pw.MemoryImage(imgBytes);
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
        ));
      }

      final dir = Directory('/storage/emulated/0/Download/SuperAppHD/Scans');
      await dir.create(recursive: true);
      final name = 'scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(await pdf.save());
      await _addHistory('pdf', [file.path]);

      _snack('Saved: $name',
          action: SnackBarAction(
            label: 'OPEN',
            textColor: _accent,
            onPressed: () => OpenFilex.open(file.path),
          ));
    } catch (e) {
      _snack('Failed to save: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _saveAsImages() async {
    if (_pages.isEmpty) return;
    setState(() => _saving = true);
    try {
      final dir = Directory('/storage/emulated/0/Download/SuperAppHD/Scans');
      await dir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final saved = <String>[];
      for (int i = 0; i < _pages.length; i++) {
        final out = '${dir.path}/scan_${ts}_${i + 1}.jpg';
        await File(_pages[i]).copy(out);
        saved.add(out);
      }
      await _addHistory('jpg', saved);
      _snack('${_pages.length} images saved to Downloads/SuperAppHD/Scans');
    } catch (e) {
      _snack('Failed to save: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      action: action,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Scanner'),
        actions: [
          if (_pages.isNotEmpty)
            TextButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Rescan'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
        ],
      ),
      body: PopScope(
        canPop: _pages.isEmpty,
        // Back dari halaman hasil scan kembali ke beranda Scanner
        onPopInvoked: (didPop) {
          if (!didPop) setState(() => _pages = []);
        },
        child: _pages.isEmpty ? _buildEmpty() : _buildResult(),
      ),
    );
  }

  Widget _buildEmpty() {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        // Scan button hero
        SoftCard(
          onTap: _startScan,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          shadowTint: _accent,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_accent, Color.lerp(_accent, Colors.black, 0.18)!],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.document_scanner_rounded,
                    color: Colors.white, size: 44),
              ),
              const SizedBox(height: 16),
              const Text('Start Scanning',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text('Tap to open the camera',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.85))),
            ],
          ),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 32),
          _buildHistorySection(),
        ],
        const SizedBox(height: 24),
        Text('DOCUMENTS YOU CAN SCAN',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: sub,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _docTypes.map((d) {
            final (label, icon, color) = d;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
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
        const SizedBox(height: 32),
        Text('Tips', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildTip(Icons.wb_sunny_rounded, 'Use good lighting',
            'Make sure the document is bright and free of shadows'),
        const SizedBox(height: 8),
        _buildTip(Icons.crop_free_rounded, 'Position it properly',
            'Place the document on a flat, even surface'),
        const SizedBox(height: 8),
        _buildTip(Icons.hd_rounded, 'Hold the camera steady',
            'Avoid shaking for a sharp scan'),
      ],
    );
  }

  // ── History ─────────────────────────────────────────────────────────────────
  Widget _buildHistorySection() {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('History', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(
            onPressed: _clearHistory,
            child:
                Text('Clear all', style: TextStyle(fontSize: 12, color: sub)),
          ),
        ]),
        Text('Swipe left on an item to delete it',
            style: TextStyle(fontSize: 12, color: sub)),
        const SizedBox(height: 8),
        ..._history.map(_buildHistoryCard),
      ],
    );
  }

  Widget _buildHistoryCard(ScanRecord r) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = r.isPdf ? const Color(0xFFE53935) : _accent;
    final pages = '${r.pageCount} page${r.pageCount == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeToDelete(
        key: ValueKey('${r.date}_${r.type}'),
        confirmTitle: 'Delete from history?',
        confirmMessage: 'Remove this scan from history? '
            'The saved ${r.isPdf ? 'PDF' : 'images'} will not be deleted.',
        onDelete: () async {
          setState(() => _history.remove(r));
          await HistoryService.saveScans(_history);
        },
        child: SoftCard(
          onTap: () => _openHistory(r),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              child: Container(
                width: 48,
                height: 56,
                color: color.withOpacity(0.12),
                child: r.isPdf
                    ? Icon(Icons.picture_as_pdf_rounded, color: color)
                    : Image.file(File(r.paths.first),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.image_rounded, color: color)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                        '${r.type.toUpperCase()} · $pages · ${timeAgo(r.dateTime)}',
                        style: TextStyle(fontSize: 12, color: sub)),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded, color: sub),
          ]),
        ),
      ),
    );
  }

  Future<void> _openHistory(ScanRecord r) async {
    final path = r.paths.first;
    if (!await File(path).exists()) {
      _snack('File not found. It may have been moved or deleted.');
      return;
    }
    if (!mounted) return;
    if (r.isPdf) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PdfViewerScreen(path: path, title: r.name)));
    } else {
      await OpenFilex.open(path);
    }
  }

  Future<void> _clearHistory() async {
    final ok = await confirmDialog(context,
        title: 'Clear scan history?',
        message: 'All ${_history.length} items will be removed from history. '
            'Saved files will not be deleted.',
        confirmLabel: 'Clear all');
    if (!ok) return;
    setState(() => _history.clear());
    await HistoryService.saveScans([]);
  }

  Widget _buildTip(IconData icon, String title, String desc) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
            ),
            child: Icon(icon, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Preview halaman aktif
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF0B0D14) : const Color(0xFFE6E8EF),
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _viewPage = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Image.file(File(_pages[i]), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Panel bawah: thumbnail + aksi
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusCard)),
            boxShadow: AppTheme.softShadow(context),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_pages.length > 1)
                SizedBox(
                  height: 72,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _pageCtrl.animateToPage(i,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: i == _viewPage
                                ? _accent
                                : scheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(_pages[i]),
                              width: 52, height: 68, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Text('Page ${_viewPage + 1} of ${_pages.length}',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12)),
                    const Spacer(),
                    _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: _accent))
                        : Row(
                            children: [
                              _actionBtn(
                                  Icons.image_rounded, 'JPG', _saveAsImages,
                                  filled: false),
                              const SizedBox(width: 8),
                              _actionBtn(Icons.picture_as_pdf_rounded,
                                  'Save PDF', _saveAsPdf,
                                  filled: true),
                            ],
                          ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap,
      {required bool filled}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? _accent : _accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: filled ? Colors.white : _accent),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: filled ? Colors.white : _accent,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
