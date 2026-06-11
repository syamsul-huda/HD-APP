import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

class PdfViewerScreen extends StatefulWidget {
  final String path;
  final String title;

  const PdfViewerScreen({super.key, required this.path, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  PDFViewController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isReady)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
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
            backgroundColor: const Color(0xFF0D0D1A),
            onRender: (pages) => setState(() {
              _totalPages = pages ?? 0;
              _isReady = true;
            }),
            onViewCreated: (ctrl) => _controller = ctrl,
            onPageChanged: (page, _) => setState(() => _currentPage = page ?? 0),
            onError: (err) => _showError(err.toString()),
            onPageError: (page, err) => _showError('Halaman $page: $err'),
          ),
          if (!_isReady)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                  SizedBox(height: 12),
                  Text('Memuat PDF...', style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _isReady && _totalPages > 1
          ? Container(
              color: const Color(0xFF1A1A2E),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _currentPage > 0
                        ? () => _controller?.setPage(_currentPage - 1)
                        : null,
                    color: _currentPage > 0
                        ? const Color(0xFF7C4DFF)
                        : Colors.white24,
                  ),
                  Text(
                    'Halaman ${_currentPage + 1} dari $_totalPages',
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _currentPage < _totalPages - 1
                        ? () => _controller?.setPage(_currentPage + 1)
                        : null,
                    color: _currentPage < _totalPages - 1
                        ? const Color(0xFF7C4DFF)
                        : Colors.white24,
                  ),
                ],
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
