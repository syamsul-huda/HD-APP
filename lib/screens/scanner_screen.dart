import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  List<String> _pages = [];
  bool _saving = false;
  int _viewPage = 0;

  static const _docTypes = [
    ('KTP', Icons.credit_card_rounded, Color(0xFF1565C0)),
    ('Ijazah', Icons.school_rounded, Color(0xFF2E7D32)),
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
        setState(() { _pages = pictures; _viewPage = 0; });
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

      _snack('Tersimpan: $name', action: SnackBarAction(
        label: 'BUKA',
        textColor: const Color(0xFF7B8BFF),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.document_scanner_rounded, color: Color(0xFF4ECDC4), size: 20),
            SizedBox(width: 8),
            Text('Scanner Dokumen'),
          ],
        ),
        actions: [
          if (_pages.isNotEmpty)
            TextButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Scan Ulang'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF7B8BFF)),
            ),
        ],
      ),
      body: _pages.isEmpty ? _buildEmpty() : _buildResult(),
    );
  }

  Widget _buildEmpty() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scan button hero
          GestureDetector(
            onTap: _startScan,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2640),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECDC4).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.document_scanner_rounded,
                        color: Color(0xFF4ECDC4), size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text('Mulai Scan',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold,
                          color: Color(0xFF4ECDC4))),
                  const SizedBox(height: 6),
                  const Text('Tap untuk membuka kamera',
                      style: TextStyle(fontSize: 13, color: Colors.white38)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('JENIS DOKUMEN YANG BISA DISCAN',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: Colors.white38, letterSpacing: 1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _docTypes.map((d) {
              final (label, icon, color) = d;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(fontSize: 12, color: color,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          _buildTip(Icons.wb_sunny_rounded, 'Gunakan pencahayaan yang cukup',
              'Pastikan dokumen terang dan tidak ada bayangan'),
          const SizedBox(height: 8),
          _buildTip(Icons.crop_free_rounded, 'Posisikan dengan benar',
              'Letakkan dokumen di permukaan datar dan rata'),
          const SizedBox(height: 8),
          _buildTip(Icons.hd_rounded, 'Pegang kamera stabil',
              'Hindari guncangan untuk hasil scan yang tajam'),
        ],
      ),
    );
  }

  Widget _buildTip(IconData icon, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2640),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7B8BFF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                Text(desc, style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    return Column(
      children: [
        // Preview halaman aktif
        Expanded(
          child: Container(
            color: const Color(0xFF151929),
            child: PageView.builder(
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _viewPage = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(
                  child: Image.file(File(_pages[i]), fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
        // Thumbnail strip
        if (_pages.length > 1)
          Container(
            height: 72,
            color: const Color(0xFF1E2640),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              itemCount: _pages.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() => _viewPage = i),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: i == _viewPage
                          ? const Color(0xFF7B8BFF)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(File(_pages[i]),
                        width: 48, height: 56, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
        // Action bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          color: const Color(0xFF1E2640),
          child: Row(
            children: [
              Text('${_pages.length} halaman',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const Spacer(),
              _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Color(0xFF7B8BFF)))
                  : Row(
                      children: [
                        _actionBtn(Icons.image_rounded, 'Simpan JPG',
                            _saveAsImages, const Color(0xFF8FA4FF)),
                        const SizedBox(width: 10),
                        _actionBtn(Icons.picture_as_pdf_rounded, 'Simpan PDF',
                            _saveAsPdf, const Color(0xFF4ECDC4)),
                      ],
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
