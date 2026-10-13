import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/app_theme.dart';

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

  static const _accent = AppTheme.scannerColor;

  static const _docTypes = [
    ('KTP', Icons.credit_card_rounded, Color(0xFF1565C0)),
    ('Ijazah', Icons.school_rounded, Color(0xFF217346)),
    ('SIM', Icons.directions_car_rounded, Color(0xFFE65100)),
    ('Sertifikat', Icons.workspace_premium_rounded, Color(0xFF7B8BFF)),
    ('Dokumen Lain', Icons.description_rounded, Color(0xFF546E7A)),
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
      _snack('Kamera tidak tersedia: $e');
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

      _snack('Tersimpan: $name',
          action: SnackBarAction(
            label: 'BUKA',
            textColor: _accent,
            onPressed: () => OpenFilex.open(file.path),
          ));
    } catch (e) {
      _snack('Gagal simpan: $e');
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
      for (int i = 0; i < _pages.length; i++) {
        await File(_pages[i]).copy('${dir.path}/scan_${ts}_${i + 1}.jpg');
      }
      _snack('${_pages.length} gambar tersimpan di Downloads/SuperAppHD/Scans');
    } catch (e) {
      _snack('Gagal simpan: $e');
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
        title: const Text('Scanner Dokumen'),
        actions: [
          if (_pages.isNotEmpty)
            TextButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Scan Ulang'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
        ],
      ),
      body: _pages.isEmpty ? _buildEmpty() : _buildResult(),
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
              const Text('Mulai Scan',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text('Tap untuk membuka kamera',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.85))),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('JENIS DOKUMEN YANG BISA DISCAN',
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
        _buildTip(Icons.wb_sunny_rounded, 'Gunakan pencahayaan yang cukup',
            'Pastikan dokumen terang dan tidak ada bayangan'),
        const SizedBox(height: 8),
        _buildTip(Icons.crop_free_rounded, 'Posisikan dengan benar',
            'Letakkan dokumen di permukaan datar dan rata'),
        const SizedBox(height: 8),
        _buildTip(Icons.hd_rounded, 'Pegang kamera stabil',
            'Hindari guncangan untuk hasil scan yang tajam'),
      ],
    );
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
                    Text('${_viewPage + 1} / ${_pages.length} halaman',
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
                                  'Simpan PDF', _saveAsPdf,
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
