import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/fullscreen_reader.dart';
import '../utils/office/chart_view.dart';
import '../utils/office/office_fonts.dart';
import '../utils/office/odp_parser.dart';
import '../utils/office/pptx_parser.dart';
import '../utils/office/slide_model.dart';
import 'converted_pdf_screen.dart';

SlideDeck _parse((Uint8List, String) a) =>
    a.$2 == 'odp' ? parseOdp(a.$1) : parsePptx(a.$1);

class PptxViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  final String? ext;
  const PptxViewerScreen(
      {super.key, required this.path, required this.title, this.ext});

  @override
  State<PptxViewerScreen> createState() => _PptxViewerScreenState();
}

class _PptxViewerScreenState extends State<PptxViewerScreen>
    with FullscreenReaderMixin {
  SlideDeck? _deck;
  bool _loading = true;
  String? _error;
  int _current = 0;
  final _pager = PageController();
  final _thumbs = ScrollController();

  static const _pptOrange = Color(0xFFD24726);

  String get _ext =>
      (widget.ext ?? widget.path.split('.').last).toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pager.dispose();
    _thumbs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final deck = await compute(_parse, (bytes, _ext));
      if (!mounted) return;
      setState(() {
        _deck = deck;
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

  void _goTo(int i) {
    final n = _deck?.slides.length ?? 0;
    if (i < 0 || i >= n) return;
    if (_pager.hasClients) {
      _pager.animateToPage(i,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      setState(() => _current = i);
    }
  }

  void _onPage(int i) {
    setState(() => _current = i);
    // Jaga thumbnail aktif tetap terlihat
    if (_thumbs.hasClients) {
      final target = (i * 108.0 - 120).clamp(0.0, _thumbs.position.maxScrollExtent);
      _thumbs.animateTo(target,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _showNotes() {
    final notes = _deck!.slides[_current].notes;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes · Slide ${_current + 1}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(notes.isEmpty ? 'No notes for this slide.' : notes,
                    style: const TextStyle(fontSize: 15, height: 1.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = _deck;
    final ready = !_loading && deck != null && deck.slides.isNotEmpty;
    return Scaffold(
      backgroundColor: isFullscreen ? Colors.black : const Color(0xFF2D2D2D),
      appBar: isFullscreen
          ? null
          : AppBar(
              backgroundColor: _pptOrange,
              title: Text(widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                if (ready)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_current + 1} / ${deck.slides.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                if (ready && deck.slides.any((s) => s.notes.isNotEmpty))
                  IconButton(
                    tooltip: 'Speaker notes',
                    icon: const Icon(Icons.speaker_notes_outlined, color: Colors.white),
                    onPressed: _showNotes,
                  ),
                originalLayoutButton(context, widget.path, widget.title),
                fullscreenButton(),
              ],
            ),
      body: fullscreenBody(
        overlay: ready ? fullscreenBadge('${_current + 1} / ${deck.slides.length}') : null,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _pptOrange))
            : _error != null
                ? _buildError()
                : !ready
                    ? const Center(
                        child: Text('No content',
                            style: TextStyle(color: Colors.white38)))
                    : Column(
                        children: [
                          Expanded(child: _buildPager(deck)),
                          if (!isFullscreen) _buildThumbnails(deck),
                        ],
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
            Text('Failed to read presentation:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _pptOrange),
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

  Widget _buildPager(SlideDeck deck) {
    return SafeArea(
      bottom: false,
      top: isFullscreen,
      child: PageView.builder(
        controller: _pager,
        itemCount: deck.slides.length,
        onPageChanged: _onPage,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.all(isFullscreen ? 0 : 12),
          child: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: AspectRatio(
                aspectRatio: deck.width / deck.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: [
                    if (!isFullscreen)
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                  ]),
                  child: Stack(children: [
                    Positioned.fill(child: SlideCanvas(deck: deck, slide: deck.slides[i])),
                    if (deck.slides[i].hidden)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.visibility_off_outlined, size: 13, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Hidden slide', style: TextStyle(fontSize: 11, color: Colors.white)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnails(SlideDeck deck) {
    const thumbW = 96.0;
    final thumbH = thumbW * deck.height / deck.width;
    return Container(
      height: thumbH + 36,
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        controller: _thumbs,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: deck.slides.length,
        itemBuilder: (_, i) {
          final active = i == _current;
          return GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: thumbW + 12,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: thumbW,
                  height: thumbH,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: active ? _pptOrange : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  // Slide tersembunyi: thumbnail diredupkan seperti di PowerPoint
                  child: Opacity(
                    opacity: deck.slides[i].hidden ? 0.45 : 1,
                    child: SlideCanvas(deck: deck, slide: deck.slides[i], thumbnail: true),
                  ),
                ),
                const SizedBox(height: 3),
                Text('${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: active ? Colors.white : Colors.white38,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    )),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Slide renderer ───────────────────────────────────────────────────────────

/// Merender satu slide pada koordinat aslinya (point) lalu diskalakan
/// agar pas dengan ruang yang tersedia — tata letak sama dengan PowerPoint.
class SlideCanvas extends StatelessWidget {
  final SlideDeck deck;
  final SlideData slide;
  final bool thumbnail;
  const SlideCanvas(
      {super.key, required this.deck, required this.slide, this.thumbnail = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final scale = c.maxWidth.isFinite ? c.maxWidth / deck.width : 1.0;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // Teks slide tidak ikut pengaturan ukuran font sistem agar layout tetap
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: deck.width,
              height: deck.height,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(child: ColoredBox(color: slide.background)),
                  if (slide.backgroundImage != null)
                    Positioned.fill(
                      child: Image.memory(slide.backgroundImage!,
                          fit: BoxFit.cover,
                          cacheWidth: (deck.width * scale * dpr).round().clamp(64, 2400),
                          gaplessPlayback: true),
                    ),
                  for (final s in slide.shapes) _positioned(s, scale * dpr),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _positioned(SlideShape s, double pxPerPt) {
    // Shape berukuran nol (garis horizontal/vertikal) tetap butuh area gambar
    final r = s.geom == ShapeGeom.line
        ? Rect.fromLTWH(s.rect.left, s.rect.top, math.max(s.rect.width, 0.01),
            math.max(s.rect.height, 0.01))
        : s.rect;
    Widget child = _ShapeView(shape: s, pxPerPt: pxPerPt, thumbnail: thumbnail);
    if (s.rotation != 0) {
      child = Transform.rotate(angle: s.rotation * math.pi / 180, child: child);
    }
    return Positioned.fromRect(rect: r, child: child);
  }
}

class _ShapeView extends StatelessWidget {
  final SlideShape shape;
  final double pxPerPt;
  final bool thumbnail;
  const _ShapeView({required this.shape, required this.pxPerPt, required this.thumbnail});

  @override
  Widget build(BuildContext context) {
    final s = shape;
    final layers = <Widget>[];

    final hasGeom = s.fill != null || (s.lineColor != null && s.lineWidth > 0);
    if (hasGeom && s.image == null) {
      layers.add(Positioned.fill(child: CustomPaint(painter: _GeomPainter(s))));
    }

    if (s.image != null) {
      Widget img = Image.memory(
        s.image!,
        fit: BoxFit.fill,
        cacheWidth: (s.rect.width * pxPerPt).round().clamp(16, 2400),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const _Placeholder(icon: Icons.broken_image_outlined),
      );
      if (s.flipH || s.flipV) {
        img = Transform.flip(flipX: s.flipH, flipY: s.flipV, child: img);
      }
      if (s.geom == ShapeGeom.ellipse) img = ClipOval(child: img);
      if (s.geom == ShapeGeom.roundRect) {
        img = ClipRRect(
            borderRadius: BorderRadius.circular(math.min(s.rect.width, s.rect.height) * 0.16),
            child: img);
      }
      layers.add(Positioned.fill(child: img));
      if (s.lineColor != null && s.lineWidth > 0) {
        layers.add(Positioned.fill(child: CustomPaint(painter: _GeomPainter(s, strokeOnly: true))));
      }
    } else if (s.imageUnsupported) {
      layers.add(const Positioned.fill(child: _Placeholder(icon: Icons.image_outlined)));
    }

    if (s.chart != null) {
      layers.add(Positioned.fill(child: ChartView(data: s.chart!)));
    }

    if (s.isChart) {
      layers.add(const Positioned.fill(
          child: _Placeholder(icon: Icons.bar_chart_rounded, label: 'Chart')));
    }

    if (s.table != null) {
      layers.add(Positioned.fill(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: _SlideTableView(table: s.table!),
        ),
      ));
    }

    final text = s.text;
    if (text != null && !text.isEmpty) {
      layers.add(Positioned.fill(child: _SlideTextView(text: text)));
    }

    return Stack(clipBehavior: Clip.none, children: layers);
  }
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String? label;
  const _Placeholder({required this.icon, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x14000000),
        border: Border.all(color: const Color(0x33000000)),
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: const Color(0x66000000), size: 32),
            if (label != null)
              Text(label!, style: const TextStyle(color: Color(0x88000000), fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _GeomPainter extends CustomPainter {
  final SlideShape s;
  final bool strokeOnly;
  _GeomPainter(this.s, {this.strokeOnly = false});

  Path _path(Size size) {
    final w = size.width, h = size.height;
    switch (s.geom) {
      case ShapeGeom.ellipse:
        return Path()..addOval(Offset.zero & size);
      case ShapeGeom.roundRect:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              Offset.zero & size, Radius.circular(math.min(w, h) * 0.16)));
      case ShapeGeom.triangle:
        return Path()
          ..moveTo(w / 2, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
      case ShapeGeom.diamond:
        return Path()
          ..moveTo(w / 2, 0)
          ..lineTo(w, h / 2)
          ..lineTo(w / 2, h)
          ..lineTo(0, h / 2)
          ..close();
      case ShapeGeom.line:
        final a = Offset(s.flipH ? w : 0, s.flipV ? h : 0);
        final b = Offset(s.flipH ? 0 : w, s.flipV ? 0 : h);
        return Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      case ShapeGeom.path:
        final p = Path();
        Offset sc(Offset o) => Offset(o.dx * w, o.dy * h);
        for (final cmd in s.path) {
          final pts = cmd.pts.map(sc).toList();
          switch (cmd.op) {
            case 'M':
              if (pts.isNotEmpty) p.moveTo(pts[0].dx, pts[0].dy);
            case 'L':
              for (final pt in pts) {
                p.lineTo(pt.dx, pt.dy);
              }
            case 'C':
              if (pts.length >= 3) {
                p.cubicTo(pts[0].dx, pts[0].dy, pts[1].dx, pts[1].dy, pts[2].dx, pts[2].dy);
              }
            case 'Q':
              if (pts.length >= 2) p.quadraticBezierTo(pts[0].dx, pts[0].dy, pts[1].dx, pts[1].dy);
            case 'Z':
              p.close();
          }
        }
        if (s.flipH || s.flipV) {
          final m = Matrix4.identity()
            ..translate(s.flipH ? w : 0.0, s.flipV ? h : 0.0)
            ..scale(s.flipH ? -1.0 : 1.0, s.flipV ? -1.0 : 1.0);
          return p.transform(m.storage);
        }
        return p;
      case ShapeGeom.rect:
        return Path()..addRect(Offset.zero & size);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    if (!strokeOnly && s.fill != null && s.geom != ShapeGeom.line) {
      canvas.drawPath(path, Paint()..color = s.fill!);
    }
    if (s.lineColor != null && s.lineWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = s.lineColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.lineWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_GeomPainter old) => old.s != s;
}

class _SlideTextView extends StatelessWidget {
  final SlideText text;

  /// true = tinggi mengikuti isi (sel tabel), tanpa inset & OverflowBox.
  final bool fitContent;
  const _SlideTextView({required this.text, this.fitContent = false});

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: text.paragraphs.map(_paragraph).toList(),
    );
    if (fitContent) return column;
    Widget body = Padding(
      padding: EdgeInsets.fromLTRB(text.insetL, text.insetT, text.insetR, text.insetB),
      child: OverflowBox(
        // PowerPoint tidak memotong teks yang melebihi kotak
        maxHeight: double.infinity,
        alignment: switch (text.anchor) {
          TextAnchor.top => Alignment.topLeft,
          TextAnchor.center => Alignment.centerLeft,
          TextAnchor.bottom => Alignment.bottomLeft,
        },
        child: column,
      ),
    );
    if (text.quarterTurns != 0) body = RotatedBox(quarterTurns: text.quarterTurns, child: body);
    return body;
  }

  Widget _paragraph(SlideParagraph p) {
    final lineH = ((p.lineSpacing ?? 1.0) * 1.2).clamp(0.8, 4.0);
    if (p.runs.isEmpty || p.plainText.isEmpty) {
      return SizedBox(height: p.emptySize * lineH + p.spaceBefore + p.spaceAfter);
    }
    final first = p.runs.first;
    final spans = p.runs.map((r) {
      final small = r.baseline != 0;
      return TextSpan(
        text: r.caps ? r.text.toUpperCase() : r.text,
        style: TextStyle(
          fontSize: r.size * (small ? 0.65 : 1),
          fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
          color: r.color,
          fontFamily: _family(r.font),
          decoration: TextDecoration.combine([
            if (r.underline) TextDecoration.underline,
            if (r.strike) TextDecoration.lineThrough,
          ]),
          decorationColor: r.color,
        ),
      );
    }).toList();

    Widget content = Text.rich(
      TextSpan(children: spans, style: TextStyle(height: lineH, fontSize: first.size)),
      textAlign: p.align,
      softWrap: true,
    );

    var left = p.marginLeft;
    if (p.bullet != null) {
      final bulletW = p.indent < 0 ? -p.indent : first.size * 0.9;
      left = math.max(0, p.marginLeft - bulletW);
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: bulletW,
            child: Text(p.bullet!,
                style: TextStyle(
                    fontSize: first.size,
                    height: lineH,
                    color: p.bulletColor ?? first.color,
                    fontWeight: first.bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Expanded(child: content),
        ],
      );
    } else if (p.indent > 0) {
      left += p.indent;
    }

    return Padding(
      padding: EdgeInsets.only(left: left, top: p.spaceBefore, bottom: p.spaceAfter),
      child: content,
    );
  }

  static String _family(String? font) => officeFontFamily(font) ?? kOfficeSans;
}

class _SlideTableView extends StatelessWidget {
  final SlideTable table;
  const _SlideTableView({required this.table});

  @override
  Widget build(BuildContext context) {
    final widths = table.colWidths;
    final rows = <Widget>[];
    for (var ri = 0; ri < table.rows.length; ri++) {
      final cells = <Widget>[];
      var col = 0;
      var skip = 0;
      for (final cell in table.rows[ri]) {
        if (col >= widths.length) break;
        if (skip > 0) {
          // Sel yang tertutup span horizontal sel sebelumnya
          skip--;
          col++;
          continue;
        }
        final span = math.min(cell.colSpan, widths.length - col);
        final w = widths.sublist(col, col + span).fold<double>(0, (a, b) => a + b);
        skip = span - 1;
        col++;
        final border = BorderSide(color: cell.border ?? const Color(0xFFFFFFFF), width: 1);
        cells.add(Container(
          width: w,
          decoration: BoxDecoration(
            color: cell.merged ? null : cell.fill,
            border: Border(right: border, bottom: border),
          ),
          child: cell.merged
              ? null
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                      cell.text.insetL, cell.text.insetT, cell.text.insetR, cell.text.insetB),
                  child: _SlideTextView(text: cell.text, fitContent: true),
                ),
        ));
      }
      final h = ri < table.rowHeights.length ? table.rowHeights[ri] : 0.0;
      rows.add(ConstrainedBox(
        constraints: BoxConstraints(minHeight: h),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
        ),
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}
