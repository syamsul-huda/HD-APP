import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/fullscreen_reader.dart';

class PdfViewerScreen extends StatefulWidget {
  final String path;
  final String title;

  const PdfViewerScreen({super.key, required this.path, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with FullscreenReaderMixin {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  PDFViewController? _controller;
  SharedPreferences? _prefs;
  String? _bookmarkKey;
  bool _resumeAsked = false;

  @override
  void initState() {
    super.initState();
    _initBookmark();
  }

  // Penanda halaman terakhir dibaca. Key memakai nama + ukuran file karena
  // path bisa berubah (file picker menyalin file ke folder cache).
  Future<void> _initBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final file = File(widget.path);
    final size = await file.exists() ? await file.length() : 0;
    final name = file.uri.pathSegments.last;
    _prefs = prefs;
    _bookmarkKey = 'pdf_last_page:$name:$size';
    _maybeAskResume();
  }

  void _saveLastPage(int page) {
    final key = _bookmarkKey;
    if (key == null || !_resumeAsked) return;
    _prefs?.setInt(key, page);
  }

  // Dipanggil setelah PDF selesai dirender DAN bookmark sudah dimuat.
  Future<void> _maybeAskResume() async {
    if (_resumeAsked || !_isReady || _bookmarkKey == null) return;
    _resumeAsked = true;

    final lastPage = _prefs?.getInt(_bookmarkKey!) ?? 0;
    if (lastPage <= 0 || lastPage >= _totalPages || !mounted) return;

    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Continue reading?'),
        content: Text('You last read page ${lastPage + 1} of $_totalPages. '
            'Would you like to continue from there?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Start over'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Continue to page ${lastPage + 1}'),
          ),
        ],
      ),
    );

    if (resume == true) {
      await _controller?.setPage(lastPage);
    } else {
      _saveLastPage(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF525659),
      appBar: isFullscreen
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF323639),
              title: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                if (_isReady)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentPage + 1} / $_totalPages',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('PDF',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
                fullscreenButton(),
              ],
            ),
      body: fullscreenBody(
        overlay: _isReady && _totalPages > 0
            ? fullscreenBadge('${_currentPage + 1} / $_totalPages')
            : null,
        child: Stack(
          children: [
            PDFView(
              filePath: widget.path,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: false,
              pageSnap: false,
              defaultPage: 0,
              fitPolicy: FitPolicy.BOTH,
              backgroundColor: const Color(0xFF525659),
              onRender: (pages) {
                setState(() {
                  _totalPages = pages ?? 0;
                  _isReady = true;
                });
                _maybeAskResume();
              },
              onViewCreated: (ctrl) => _controller = ctrl,
              onPageChanged: (page, _) {
                setState(() => _currentPage = page ?? 0);
                _saveLastPage(_currentPage);
              },
              onError: (err) => _showError(err.toString()),
              onPageError: (page, err) => _showError('Halaman $page: $err'),
            ),
            if (!_isReady)
              Container(
                color: const Color(0xFF525659),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white70),
                      SizedBox(height: 12),
                      Text('Memuat PDF...',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: !isFullscreen && _isReady && _totalPages > 1
          ? Container(
              color: const Color(0xFF323639),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: _currentPage > 0
                          ? () => _controller?.setPage(_currentPage - 1)
                          : null,
                      color: _currentPage > 0 ? Colors.white70 : Colors.white24,
                    ),
                    Text(
                      'Halaman ${_currentPage + 1} dari $_totalPages',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white60),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: _currentPage < _totalPages - 1
                          ? () => _controller?.setPage(_currentPage + 1)
                          : null,
                      color: _currentPage < _totalPages - 1
                          ? Colors.white70
                          : Colors.white24,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: $msg'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
