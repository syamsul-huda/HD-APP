import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

// PowerPoint-like presentation viewer
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

  static const _pptOrange = Color(0xFFD24726);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

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
        final textBlocks = <_TextBlock>[];

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

          final ph = txBody.parent?.descendantElements
              .where((e) => e.localName == 'ph')
              .firstOrNull;
          final phType = ph?.getAttribute('type') ?? '';
          final phIdx = ph?.getAttribute('idx') ?? '';

          if ((phType == 'title' || phType == 'ctrTitle') && title.isEmpty) {
            title = paras.join(' ');
          } else if (phType == 'subTitle' || phIdx == '1') {
            textBlocks.add(_TextBlock(text: paras.join('\n'), isSubtitle: true));
          } else {
            for (final p in paras) {
              textBlocks.add(_TextBlock(text: p));
            }
          }
        }

        slides.add(_Slide(title: title, blocks: textBlocks));
      }

      setState(() { _slides = slides; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D2D),
      appBar: AppBar(
        backgroundColor: _pptOrange,
        title: Text(widget.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_loading && _slides.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_current + 1} / ${_slides.length}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('PPTX',
                style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _pptOrange))
          : _error != null
              ? _buildError()
              : _slides.isEmpty
                  ? const Center(
                      child: Text('Tidak ada konten',
                          style: TextStyle(color: Colors.white38)))
                  : Column(
                      children: [
                        _buildSlideNav(),
                        Expanded(child: _buildSlideContent(_slides[_current])),
                      ],
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
            Text('Gagal membaca presentasi:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideNav() {
    return Container(
      height: 64,
      color: const Color(0xFF1E1E1E),
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
              width: 52,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: active ? _pptOrange : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: active ? _pptOrange : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.slideshow_rounded,
                    size: 16,
                    color: active ? Colors.white : Colors.white38,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: active ? Colors.white : Colors.white38,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlideContent(_Slide slide) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          // Slide aspect ratio approx 16:9 feel with shadow
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar (like PPT slide header)
              if (slide.title.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  decoration: BoxDecoration(
                    color: _pptOrange,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  child: Text(
                    slide.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  child: Text(
                    'Slide ${_current + 1}',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9B9FAD),
                        fontStyle: FontStyle.italic),
                  ),
                ),
              // Content area
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: slide.blocks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '— Slide kosong —',
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: slide.blocks.map((block) {
                          if (block.isSubtitle) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SelectableText(
                                block.text,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF555770),
                                  fontStyle: FontStyle.italic,
                                  height: 1.5,
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 5, right: 8),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: _pptOrange,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    block.text,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1A1A2E),
                                      height: 1.55,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide {
  final String title;
  final List<_TextBlock> blocks;
  _Slide({required this.title, required this.blocks});
}

class _TextBlock {
  final String text;
  final bool isSubtitle;
  _TextBlock({required this.text, this.isSubtitle = false});
}
