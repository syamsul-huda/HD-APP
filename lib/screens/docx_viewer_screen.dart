import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class DocxViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  const DocxViewerScreen({super.key, required this.path, required this.title});

  @override
  State<DocxViewerScreen> createState() => _DocxViewerScreenState();
}

class _DocxViewerScreenState extends State<DocxViewerScreen> {
  List<_Para> _paragraphs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? docFile;
      for (final f in archive) {
        if (f.name == 'word/document.xml') { docFile = f; break; }
      }
      if (docFile == null) throw Exception('Format tidak valid');

      final xmlStr = utf8.decode(docFile.content as List<int>);
      final doc = XmlDocument.parse(xmlStr);

      XmlElement? body;
      for (final el in doc.descendantElements) {
        if (el.localName == 'body') { body = el; break; }
      }
      if (body == null) throw Exception('Konten tidak ditemukan');

      final result = <_Para>[];
      for (final para in body.childElements.where((e) => e.localName == 'p')) {
        final pPr = para.childElements.where((e) => e.localName == 'pPr').firstOrNull;
        final styleVal = pPr?.childElements
            .where((e) => e.localName == 'pStyle')
            .firstOrNull
            ?.getAttribute('w:val') ?? '';

        final spans = <_Run>[];
        for (final run in para.childElements.where((e) => e.localName == 'r')) {
          final text = run.childElements
              .where((e) => e.localName == 't')
              .map((e) => e.innerText)
              .join();
          if (text.isEmpty) continue;

          final rPr = run.childElements.where((e) => e.localName == 'rPr').firstOrNull;
          final bold = rPr?.childElements.any((e) => e.localName == 'b') ?? false;
          final italic = rPr?.childElements.any((e) => e.localName == 'i') ?? false;
          final szEl = rPr?.childElements.where((e) => e.localName == 'sz').firstOrNull;
          final sz = int.tryParse(szEl?.getAttribute('w:val') ?? '0') ?? 0;

          spans.add(_Run(text: text, bold: bold, italic: italic,
              fontSize: sz > 0 ? sz / 2.0 : null));
        }

        result.add(_Para(runs: spans, style: styleVal));
      }

      setState(() { _paragraphs = result; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B8BFF)))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Gagal membaca: $_error',
                      style: const TextStyle(color: Colors.redAccent)),
                ))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _paragraphs.map(_buildPara).toList(),
                  ),
                ),
    );
  }

  Widget _buildPara(_Para para) {
    if (para.runs.isEmpty) return const SizedBox(height: 8);

    double baseFontSize = 14;
    FontWeight baseWeight = FontWeight.normal;
    final s = para.style.toLowerCase();
    if (s.contains('heading1') || s == 'h1') {
      baseFontSize = 22; baseWeight = FontWeight.bold;
    } else if (s.contains('heading2') || s == 'h2') {
      baseFontSize = 18; baseWeight = FontWeight.bold;
    } else if (s.contains('heading3') || s == 'h3') {
      baseFontSize = 16; baseWeight = FontWeight.w600;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectableText.rich(
        TextSpan(
          style: TextStyle(fontSize: baseFontSize, fontWeight: baseWeight,
              color: Colors.white70, height: 1.6),
          children: para.runs.map((r) => TextSpan(
            text: r.text,
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.bold : null,
              fontStyle: r.italic ? FontStyle.italic : null,
              fontSize: r.fontSize,
            ),
          )).toList(),
        ),
      ),
    );
  }
}

class _Para {
  final List<_Run> runs;
  final String style;
  _Para({required this.runs, required this.style});
}

class _Run {
  final String text;
  final bool bold;
  final bool italic;
  final double? fontSize;
  _Run({required this.text, required this.bold, required this.italic, this.fontSize});
}
