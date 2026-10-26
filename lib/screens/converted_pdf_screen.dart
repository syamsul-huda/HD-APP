import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../services/document_convert_service.dart';
import 'pdf_viewer_screen.dart';

/// Mengonversi dokumen ke PDF lewat backend lalu menampilkannya dengan
/// [PdfViewerScreen]: tata letak identik dengan Microsoft Office.
class ConvertedPdfScreen extends StatefulWidget {
  final String path;
  final String title;
  const ConvertedPdfScreen({super.key, required this.path, required this.title});

  @override
  State<ConvertedPdfScreen> createState() => _ConvertedPdfScreenState();
}

class _ConvertedPdfScreenState extends State<ConvertedPdfScreen> {
  final _cancel = CancelToken();
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void dispose() {
    if (!_cancel.isCancelled) _cancel.cancel();
    super.dispose();
  }

  Future<void> _convert() async {
    setState(() {
      _error = null;
      _progress = null;
    });
    try {
      final pdf = await DocumentConvertService.toPdf(
        widget.path,
        fileName: widget.title,
        cancelToken: _cancel,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => PdfViewerScreen(path: pdf.path, title: widget.title)),
      );
    } catch (e) {
      if (!mounted || _cancel.isCancelled) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openExternal() async {
    final r = await OpenFilex.open(widget.path);
    if (r.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No other app on this device can open this file'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _error == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(
                        value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(height: 20),
                  Text('Preparing original layout…', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('The document is rendered exactly like Microsoft Office.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cloud_off_rounded, size: 56, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Could not convert the document',
                      style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _convert,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open with another app'),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// Tombol AppBar "Tampilan asli (PDF)" untuk viewer DOCX/XLSX/PPTX/ODF.
Widget originalLayoutButton(BuildContext context, String path, String title,
    {Color color = Colors.white}) {
  return IconButton(
    tooltip: 'Original layout (PDF)',
    icon: Icon(Icons.picture_as_pdf_outlined, color: color),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConvertedPdfScreen(path: path, title: title)),
    ),
  );
}
