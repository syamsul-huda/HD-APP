import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/fullscreen_reader.dart';
import '../utils/office/doc_model.dart';
import '../utils/office/doc_paginate.dart';
import '../utils/office/doc_render.dart';
import '../utils/office/docx_parser.dart';
import '../utils/office/odt_parser.dart';
import 'converted_pdf_screen.dart';

DocDocument _parse((Uint8List, String) args) =>
    args.$2 == 'odt' ? parseOdt(args.$1) : parseDocx(args.$1);

// Word-like document viewer (DOCX / ODT): tampilan halaman atau reflow.
class DocxViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  final String? ext;
  const DocxViewerScreen(
      {super.key, required this.path, required this.title, this.ext});

  @override
  State<DocxViewerScreen> createState() => _DocxViewerScreenState();
}

class _DocxViewerScreenState extends State<DocxViewerScreen>
    with FullscreenReaderMixin {
  static const _wordBlue = Color(0xFF1565C0);
  static const _modeKey = 'doc_page_view';
  DocDocument? _doc;
  bool _loading = true;
  String? _error;
  bool _pageView = true;

  String get _ext =>
      (widget.ext ?? widget.path.split('.').last).toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Preferensi tampilan opsional: gagal dibaca tidak boleh menggagalkan dokumen
      try {
        final prefs = await SharedPreferences.getInstance();
        _pageView = prefs.getBool(_modeKey) ?? true;
      } catch (_) {}
      final bytes = await File(widget.path).readAsBytes();
      final doc = await compute(_parse, (bytes, _ext));
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error): '), '');
        _loading = false;
      });
    }
  }

  Future<void> _toggleMode() async {
    setState(() => _pageView = !_pageView);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_modeKey, _pageView);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8D8D8),
      appBar: isFullscreen
          ? null
          : AppBar(
              backgroundColor: _wordBlue,
              title: Text(widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description_outlined,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(_ext.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (_doc != null)
                  IconButton(
                    tooltip: _pageView ? 'Mobile view' : 'Page view',
                    icon: Icon(
                        _pageView ? Icons.phone_android_rounded : Icons.article_outlined,
                        color: Colors.white),
                    onPressed: _toggleMode,
                  ),
                originalLayoutButton(context, widget.path, widget.title),
                fullscreenButton(),
              ],
            ),
      body: fullscreenBody(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _wordBlue))
            : _error != null
                ? _buildError()
                : _pageView
                    ? DocPageView(doc: _doc!, compact: isFullscreen)
                    : DocDocumentView(doc: _doc!, compact: isFullscreen),
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
            Text('Failed to read document:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF555770))),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _wordBlue),
              onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ConvertedPdfScreen(
                          path: widget.path, title: widget.title))),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Open original layout'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pinch-to-zoom bersama ─────────────────────────────────────────────────────

/// Dua jari di atas daftar mengubah [zoom]. Memakai Listener sehingga tidak
/// berebut gesture dengan scroll.
mixin _PinchZoom<T extends StatefulWidget> on State<T> {
  double zoom = 1;
  double get minZoom => 0.6;
  double get maxZoom => 3;
  final _pointers = <int, Offset>{};
  double? _pinchStartDist;
  double _pinchStartZoom = 1;
  bool showZoom = false;

  Widget pinchArea({required Widget child}) => Stack(children: [
        Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: child,
        ),
        if (showZoom)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('${(zoom * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ),
      ]);

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      final p = _pointers.values.toList();
      _pinchStartDist = (p[0] - p[1]).distance;
      _pinchStartZoom = zoom;
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStartDist;
    if (_pointers.length != 2 || start == null || start < 20) return;
    final p = _pointers.values.toList();
    final z = (_pinchStartZoom * (p[0] - p[1]).distance / start).clamp(minZoom, maxZoom);
    if ((z - zoom).abs() > 0.02) {
      setState(() {
        zoom = z;
        showZoom = true;
      });
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDist = null;
    if (_pointers.isEmpty && showZoom) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && _pointers.isEmpty) setState(() => showZoom = false);
      });
    }
  }
}

// ── Tampilan halaman (Print Layout) ──────────────────────────────────────────

/// Halaman seperti Word: ukuran kertas, margin, header/footer, nomor halaman.
/// Dirender dalam satuan point lalu diskalakan ke lebar layar × zoom.
class DocPageView extends StatefulWidget {
  final DocDocument doc;
  final bool compact;
  const DocPageView({super.key, required this.doc, this.compact = false});

  @override
  State<DocPageView> createState() => _DocPageViewState();
}

class _DocPageViewState extends State<DocPageView> with _PinchZoom {
  /// Halaman di-layout dalam twip (20 unit per point, unit internal Word) lalu
  /// diperkecil. Engine teks membulatkan tinggi baris ke unit bulat; pada
  /// 1 unit/pt galatnya ≈0.5 pt per baris sehingga pindah halaman bergeser.
  static const _u = 20.0;
  List<List<DocBlock>>? _pages;
  final _scroll = ScrollController();
  final _hScroll = ScrollController();
  final _recognizers = <TapGestureRecognizer>[];
  int _current = 0;

  @override
  double get minZoom => 1;
  @override
  double get maxZoom => 4;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Pagination butuh font & layout engine: jalankan setelah frame pertama
    WidgetsBinding.instance.addPostFrameCallback((_) => _paginate());
  }

  @override
  void didUpdateWidget(DocPageView old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) _paginate();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _hScroll.dispose();
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Iterator<List<DocBlock>>? _pager;
  bool _paginating = false;

  /// Pagination bertahap: tiap frame menghitung halaman selama ±12 ms
  /// sehingga dokumen ratusan halaman tetap responsif saat dibuka.
  void _paginate() {
    if (!mounted) return;
    _pager = paginateIncrementally(widget.doc, DocRenderer(scale: _u, exact: true)).iterator;
    _pages = [];
    _paginating = true;
    _step();
  }

  void _step() {
    final pager = _pager;
    if (!mounted || pager == null) return;
    final sw = Stopwatch()..start();
    final pages = _pages!;
    var done = false;
    while (sw.elapsedMilliseconds < 12) {
      if (!pager.moveNext()) {
        done = true;
        break;
      }
      pages.add(pager.current);
    }
    setState(() {
      if (done) {
        _paginating = false;
        _pager = null;
        if (pages.isEmpty) pages.add([]);
      }
    });
    if (!done) WidgetsBinding.instance.addPostFrameCallback((_) => _step());
  }

  double _pageScale(double viewportW) {
    final pad = widget.compact ? 0.0 : 24.0;
    return (viewportW - pad) / widget.doc.page.width * zoom;
  }

  double _viewportW = 0;

  void _onScroll() {
    final pages = _pages;
    if (pages == null || _viewportW == 0) return;
    final extent = widget.doc.page.height * _pageScale(_viewportW) + 14;
    final p = ((_scroll.offset + extent * 0.4) / extent).floor().clamp(0, pages.length - 1);
    if (p != _current) setState(() => _current = p);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == null || pages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)));
    }
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    return LayoutBuilder(builder: (context, c) {
      _viewportW = c.maxWidth;
      final scale = _pageScale(c.maxWidth);
      final pageW = widget.doc.page.width * scale;
      final contentW = pageW + (widget.compact ? 0 : 24);
      final dpr = MediaQuery.devicePixelRatioOf(context);

      Widget list = SizedBox(
        width: math.max(contentW, c.maxWidth),
        child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 0 : 12),
            itemCount: pages.length,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(bottom: i == pages.length - 1 ? 0 : 14),
              child: Center(
                child: SizedBox(
                  width: pageW,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: _page(i, pages, dpr * scale),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (contentW > c.maxWidth + 0.5) {
        list = Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: list,
          ),
        );
      }

      return Stack(children: [
        pinchArea(child: list),
        Positioned(
          left: 12,
          bottom: 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Page ${_current + 1} of ${pages.length}${_paginating ? '+' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _page(int i, List<List<DocBlock>> pages, double pxPerPt) {
    final doc = widget.doc;
    final setup = doc.page;
    final r = DocRenderer(
      scale: _u,
      exact: true,
      devicePixelRatio: pxPerPt / _u,
      pageNumber: i + 1,
      pageCount: _paginating ? 0 : pages.length,
      recognizers: _recognizers,
    );
    final textW = doc.textWidth * _u;
    final header = i == 0 && doc.firstHeader != null ? doc.firstHeader! : doc.header;
    final footer = i == 0 && doc.firstFooter != null ? doc.firstFooter! : doc.footer;
    // Footnote yang dirujuk di halaman ini (urut sesuai kemunculan)
    final notes = <String>{
      for (final b in pages[i]) ...footnoteLabels(b),
    }.where(doc.footnotes.containsKey).toList();

    // Ukuran dalam point; teks tidak ikut skala font sistem agar sama dengan Word
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        width: setup.width * _u,
        constraints: BoxConstraints(minHeight: setup.height * _u),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 6 * _u, offset: const Offset(0, 2 * _u)),
          ],
        ),
        child: Stack(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(setup.marginLeft * _u, setup.marginTop * _u,
                setup.marginRight * _u, setup.marginBottom * _u),
            child: r.blocks(pages[i], textW),
          ),
          if (header.isNotEmpty)
            Positioned(
              top: setup.headerDistance * _u,
              left: setup.marginLeft * _u,
              right: setup.marginRight * _u,
              child: r.blocks(header, textW),
            ),
          if (notes.isNotEmpty)
            Positioned(
              bottom: setup.marginBottom * _u,
              left: setup.marginLeft * _u,
              right: setup.marginRight * _u,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Garis pemisah footnote seperti Word (sepertiga lebar)
                  SizedBox(height: 6 * _u),
                  Container(width: textW / 3, height: 0.75 * _u, color: Colors.black54),
                  SizedBox(height: 5.25 * _u),
                  for (final l in notes) r.blocks(doc.footnotes[l]!, textW),
                ],
              ),
            ),
          if (footer.isNotEmpty)
            Positioned(
              bottom: setup.footerDistance * _u,
              left: setup.marginLeft * _u,
              right: setup.marginRight * _u,
              child: r.blocks(footer, textW),
            ),
        ]),
      ),
    );
  }
}

// ── Tampilan mobile (reflow) ─────────────────────────────────────────────────

/// Satu item di daftar: tepi atas/bawah kertas, atau satu blok konten.
sealed class _Item {}

class _Edge extends _Item {
  final bool top;
  final int page;
  _Edge(this.top, this.page);
}

class _Block extends _Item {
  final DocBlock block;
  _Block(this.block);
}

/// Teks mengikuti lebar layar (seperti "Mobile view" Word) dengan pinch-to-zoom.
class DocDocumentView extends StatefulWidget {
  final DocDocument doc;
  final bool compact;
  const DocDocumentView({super.key, required this.doc, this.compact = false});

  @override
  State<DocDocumentView> createState() => _DocDocumentViewState();
}

class _DocDocumentViewState extends State<DocDocumentView> with _PinchZoom {
  // 1 pt di dokumen = 1.25 dp pada zoom 100% (11 pt ≈ 14 dp, nyaman di HP)
  static const _baseScale = 1.25;
  late List<_Item> _items;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  double get maxZoom => 2.5;

  List<DocBlock> get _allBlocks =>
      [...widget.doc.blocks, ...documentAppendix(widget.doc, mobile: true)];

  @override
  void initState() {
    super.initState();
    _items = _paginate(_allBlocks);
  }

  @override
  void didUpdateWidget(DocDocumentView old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) _items = _paginate(_allBlocks);
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<_Item> _paginate(List<DocBlock> blocks) {
    final items = <_Item>[_Edge(true, 0)];
    var page = 0;
    var pageHasContent = false;
    void breakPage() {
      if (!pageHasContent) return;
      items.add(_Edge(false, page));
      page++;
      items.add(_Edge(true, page));
      pageHasContent = false;
    }

    for (final b in blocks) {
      if (b is DocPageBreak) {
        // Pindah halaman otomatis Word tidak relevan saat teks di-reflow
        if (!b.soft) breakPage();
        continue;
      }
      if (b is DocParagraph && b.pageBreakBefore) breakPage();
      items.add(_Block(b));
      pageHasContent = true;
    }
    items.add(_Edge(false, page));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    // Semua item dibangun ulang (delegate baru) → recognizer lama tidak dipakai lagi
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final renderer = DocRenderer(
      scale: _baseScale * zoom,
      spacing: 0.8,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      recognizers: _recognizers,
    );
    return LayoutBuilder(builder: (context, c) {
      final hPad = widget.compact ? 0.0 : 12.0;
      final paperW = math.min(c.maxWidth - hPad * 2,
          (widget.doc.textWidth + 72 * 2) * renderer.scale);
      final margin = (paperW * 0.07).clamp(14.0, 56.0 * zoom);
      final textW = paperW - margin * 2;

      return pinchArea(
        child: SelectionArea(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 0 : 16, horizontal: hPad),
            itemCount: _items.length,
            itemBuilder: (_, i) => Center(
              child: SizedBox(
                width: paperW,
                child: _buildItem(_items[i], margin, textW, renderer),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildItem(_Item item, double margin, double textW, DocRenderer r) {
    switch (item) {
      case _Edge(:final top, :final page):
        // Tepi kertas + jarak antar halaman
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (top && page > 0) const SizedBox(height: 14),
          Container(
            height: margin * 0.9,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: Offset(0, top ? -1 : 3),
                ),
              ],
            ),
          ),
        ]);
      case _Block(:final block):
        return Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: margin),
          child: r.block(block, textW),
        );
    }
  }
}
