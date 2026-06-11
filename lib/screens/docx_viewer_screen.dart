import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

// Word-like document viewer (A4 paper style)
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

        // Detect list (numbering)
        final numPr = pPr?.childElements.where((e) => e.localName == 'numPr').firstOrNull;
        final isList = numPr != null;
        final indentEl = pPr?.childElements.where((e) => e.localName == 'ind').firstOrNull;
        final indentLeft = int.tryParse(indentEl?.getAttribute('w:left') ?? '0') ?? 0;

        // Alignment
        final jcEl = pPr?.childElements.where((e) => e.localName == 'jc').firstOrNull;
        final align = jcEl?.getAttribute('w:val') ?? '';

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
          final underline = rPr?.childElements.any((e) => e.localName == 'u') ?? false;
          final strike = rPr?.childElements.any((e) => e.localName == 'strike') ?? false;
          final szEl = rPr?.childElements.where((e) => e.localName == 'sz').firstOrNull;
          final sz = int.tryParse(szEl?.getAttribute('w:val') ?? '0') ?? 0;

          // Color from XML
          final colorEl = rPr?.childElements.where((e) => e.localName == 'color').firstOrNull;
          final colorVal = colorEl?.getAttribute('w:val');
          Color? textColor;
          if (colorVal != null && colorVal != 'auto' && colorVal.length == 6) {
            final hex = int.tryParse('FF$colorVal', radix: 16);
            if (hex != null) textColor = Color(hex);
          }

          spans.add(_Run(
            text: text, bold: bold, italic: italic,
            underline: underline, strike: strike,
            fontSize: sz > 0 ? sz / 2.0 : null,
            color: textColor,
          ));
        }

        result.add(_Para(
          runs: spans, style: styleVal,
          isList: isList, indent: indentLeft,
          align: align,
        ));
      }

      setState(() { _paragraphs = result; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8D8D8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        title: Text(widget.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text('DOCX', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : _error != null
              ? _buildError()
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 640),
                      // A4 paper effect
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(32, 36, 32, 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _paragraphs.map(_buildPara).toList(),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text('Gagal membaca dokumen:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF555770))),
          ],
        ),
      ),
    );
  }

  Widget _buildPara(_Para para) {
    if (para.runs.isEmpty) return const SizedBox(height: 10);

    final s = para.style.toLowerCase();
    double baseFontSize = 11;
    FontWeight baseWeight = FontWeight.normal;
    Color baseColor = const Color(0xFF1A1A2E);
    double bottomPadding = 6;
    double? topPadding;
    bool isHeading = false;
    Color? headingBorderColor;

    if (s.contains('title')) {
      baseFontSize = 26; baseWeight = FontWeight.bold;
      baseColor = const Color(0xFF1F3864);
      bottomPadding = 4; topPadding = 8;
      isHeading = true;
    } else if (s.contains('heading1') || s == 'h1' || s == '1') {
      baseFontSize = 18; baseWeight = FontWeight.bold;
      baseColor = const Color(0xFF1F3864);
      bottomPadding = 4; topPadding = 14;
      isHeading = true;
      headingBorderColor = const Color(0xFF1565C0);
    } else if (s.contains('heading2') || s == 'h2' || s == '2') {
      baseFontSize = 15; baseWeight = FontWeight.bold;
      baseColor = const Color(0xFF1F5496);
      bottomPadding = 4; topPadding = 12;
      isHeading = true;
    } else if (s.contains('heading3') || s == 'h3' || s == '3') {
      baseFontSize = 13; baseWeight = FontWeight.w600;
      baseColor = const Color(0xFF2E75B6);
      bottomPadding = 3; topPadding = 10;
      isHeading = true;
    }

    TextAlign textAlign = TextAlign.left;
    if (para.align == 'center') textAlign = TextAlign.center;
    else if (para.align == 'right') textAlign = TextAlign.right;
    else if (para.align == 'both' || para.align == 'distribute') textAlign = TextAlign.justify;

    final indentPx = (para.indent / 1440.0 * 72.0).clamp(0.0, 80.0);

    Widget content = SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: baseFontSize,
          fontWeight: baseWeight,
          color: baseColor,
          height: 1.65,
        ),
        children: para.runs.map((r) => TextSpan(
          text: r.text,
          style: TextStyle(
            fontWeight: r.bold ? FontWeight.bold : null,
            fontStyle: r.italic ? FontStyle.italic : null,
            fontSize: r.fontSize,
            color: r.color,
            decoration: r.underline
                ? TextDecoration.underline
                : r.strike
                    ? TextDecoration.lineThrough
                    : null,
          ),
        )).toList(),
      ),
      textAlign: textAlign,
    );

    if (para.isList) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Text('•',
                style: TextStyle(fontSize: baseFontSize, color: const Color(0xFF555770))),
          ),
          Expanded(child: content),
        ],
      );
    }

    Widget result = Padding(
      padding: EdgeInsets.only(
        top: topPadding ?? 0,
        bottom: bottomPadding,
        left: indentPx,
      ),
      child: content,
    );

    if (isHeading && headingBorderColor != null) {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPadding ?? 0),
          content,
          const SizedBox(height: 4),
          Container(height: 1.5, color: headingBorderColor.withOpacity(0.3)),
          SizedBox(height: bottomPadding),
        ],
      );
    }

    return result;
  }
}

class _Para {
  final List<_Run> runs;
  final String style;
  final bool isList;
  final int indent;
  final String align;
  _Para({required this.runs, required this.style,
      this.isList = false, this.indent = 0, this.align = ''});
}

class _Run {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final double? fontSize;
  final Color? color;
  _Run({
    required this.text, required this.bold, required this.italic,
    this.underline = false, this.strike = false,
    this.fontSize, this.color,
  });
}
