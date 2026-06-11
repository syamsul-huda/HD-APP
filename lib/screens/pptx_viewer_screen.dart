import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class PptxViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  const PptxViewerScreen({super.key, required this.path, required this.title});

  @override
  State<PptxViewerScreen> createState() => _PptxViewerScreenState();
}

class _PptxViewerScreenState extends State<PptxViewerScreen> {
  List<_Slide> _slides = [];
  int _current = 0;
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

      // Kumpulkan slide files, urut berdasarkan nomor
      final slideFiles = archive.files
          .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
          .toList()
        ..sort((a, b) {
          final na = int.tryParse(RegExp(r'\d+').stringMatch(a.name) ?? '0') ?? 0;
          final nb = int.tryParse(RegExp(r'\d+').stringMatch(b.name) ?? '0') ?? 0;
          return na.compareTo(nb);
        });

      final slides = <_Slide>[];
      for (final file in slideFiles) {
        final xmlStr = utf8.decode(file.content as List<int>);
        final doc = XmlDocument.parse(xmlStr);

        String title = '';
        final textBlocks = <String>[];

        for (final txBody in doc.descendantElements.where((e) => e.localName == 'txBody')) {
          final paras = <String>[];
          for (final para in txBody.descendantElements.where((e) => e.localName == 'p')) {
            final text = para.descendantElements
                .where((e) => e.localName == 't')
                .map((e) => e.innerText)
                .join();
            if (text.trim().isNotEmpty) paras.add(text);
          }
          if (paras.isEmpty) continue;

          // Cek apakah ini title shape (ph type=title atau ctrTitle)
          final ph = txBody.parent?.descendantElements
              .where((e) => e.localName == 'ph')
              .firstOrNull;
          final phType = ph?.getAttribute('type') ?? '';
          if ((phType == 'title' || phType == 'ctrTitle') && title.isEmpty) {
            title = paras.join(' ');
          } else {
            textBlocks.addAll(paras);
          }
        }

        slides.add(_Slide(title: title, content: textBlocks));
      }

      setState(() { _slides = slides; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_loading && _slides.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${_current + 1}/${_slides.length}',
                    style: const TextStyle(fontSize: 13, color: Colors.white60)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B8BFF)))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Gagal membaca: $_error',
                      style: const TextStyle(color: Colors.redAccent)),
                ))
              : _slides.isEmpty
                  ? const Center(child: Text('Tidak ada konten',
                      style: TextStyle(color: Colors.white38)))
                  : Column(
                      children: [
                        _buildSlideNav(),
                        Expanded(child: _buildSlide(_slides[_current])),
                      ],
                    ),
    );
  }

  Widget _buildSlideNav() {
    return Container(
      height: 56,
      color: const Color(0xFF1E2640),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _slides.length,
        itemBuilder: (_, i) {
          final active = i == _current;
          return GestureDetector(
            onTap: () => setState(() => _current = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF7B8BFF).withOpacity(0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: active ? const Color(0xFF7B8BFF) : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 11,
                        color: active ? const Color(0xFF7B8BFF) : Colors.white38,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlide(_Slide slide) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slide.title.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF7B8BFF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF7B8BFF).withOpacity(0.3)),
              ),
              child: Text(
                slide.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7B8BFF),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...slide.content.map((text) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 14)),
                    Expanded(
                      child: SelectableText(text,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white70, height: 1.5)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _Slide {
  final String title;
  final List<String> content;
  _Slide({required this.title, required this.content});
}
