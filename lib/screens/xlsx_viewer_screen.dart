import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/fullscreen_reader.dart';
import '../utils/office/office_fonts.dart';
import '../utils/office/chart_view.dart';
import '../utils/office/ods_csv_parser.dart';
import '../utils/office/sheet_model.dart';
import '../utils/office/xlsx_parser.dart';
import 'converted_pdf_screen.dart';

SheetBook _parse((Uint8List, String, String) a) => switch (a.$2) {
      'ods' => parseOds(a.$1),
      'csv' || 'tsv' || 'txt' => parseCsv(a.$1, name: a.$3),
      _ => parseXlsx(a.$1),
    };

class XlsxViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  final String? ext;
  const XlsxViewerScreen(
      {super.key, required this.path, required this.title, this.ext});

  @override
  State<XlsxViewerScreen> createState() => _XlsxViewerScreenState();
}

class _XlsxViewerScreenState extends State<XlsxViewerScreen>
    with FullscreenReaderMixin {
  static const _excelGreen = Color(0xFF217346);
  SheetBook? _book;
  int _active = 0;
  bool _loading = true;
  String? _error;
  (int, int)? _selected;

  String get _ext =>
      (widget.ext ?? widget.path.split('.').last).toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final name = widget.title.replaceAll(RegExp(r'\.[^.]+$'), '');
      final book = await compute(_parse, (bytes, _ext, name));
      if (!mounted) return;
      setState(() {
        _book = book;
        _active = math.max(0, book.sheets.indexWhere((s) => !s.hidden));
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

  @override
  Widget build(BuildContext context) {
    final isCsv = _ext == 'csv' || _ext == 'tsv';
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: isFullscreen
          ? null
          : AppBar(
              backgroundColor: _excelGreen,
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
                      const Icon(Icons.table_chart_outlined,
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
                if (!isCsv) originalLayoutButton(context, widget.path, widget.title),
                fullscreenButton(),
              ],
            ),
      body: fullscreenBody(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _excelGreen))
            : _error != null
                ? _buildError()
                : _book!.sheets.isEmpty
                    ? const Center(
                        child: Text('No data',
                            style: TextStyle(color: Color(0xFF9B9FAD))))
                    : SafeArea(
                        top: isFullscreen,
                        child: Column(
                          children: [
                            _buildFormulaBar(),
                            Expanded(
                              child: SheetGridView(
                                key: ValueKey(_active),
                                sheet: _book!.sheets[_active],
                                selected: _selected,
                                onSelect: (cell) => setState(() => _selected = cell),
                              ),
                            ),
                            _buildSheetTabs(),
                          ],
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
            Text('Failed to read file:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF555770))),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _excelGreen),
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

  /// Seperti formula bar Excel: alamat sel + isi lengkapnya.
  Widget _buildFormulaBar() {
    final sel = _selected;
    final sheet = _book!.sheets[_active];
    // Seperti Excel: formula bar menampilkan rumus / nilai asli, bukan teks berformat
    final text = sel == null ? '' : sheet.cell(sel.$1, sel.$2)?.editText ?? '';
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFD0D0D0))),
      ),
      child: Row(children: [
        Container(
          width: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFD0D0D0))),
          ),
          child: Text(sel == null ? '' : '${columnLetter(sel.$2)}${sel.$1 + 1}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('fx',
              style: TextStyle(
                  fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF888888))),
        ),
        Expanded(
          child: SelectableText(
            text.replaceAll('\n', ' ⏎ '),
            maxLines: 1,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
          ),
        ),
      ]),
    );
  }

  Widget _buildSheetTabs() {
    final sheets = _book!.sheets;
    return Container(
      height: 40,
      color: const Color(0xFFE6E6E6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: sheets.length,
        itemBuilder: (_, i) {
          final active = i == _active;
          return GestureDetector(
            onTap: () => setState(() {
              _active = i;
              _selected = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                border: active
                    ? const Border(bottom: BorderSide(color: _excelGreen, width: 3))
                    : null,
              ),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Sheet yang disembunyikan di file asli tetap bisa dilihat
                  if (sheets[i].hidden) ...[
                    Icon(Icons.visibility_off_outlined,
                        size: 13, color: active ? _excelGreen : const Color(0xFF888888)),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    sheets[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      color: active
                          ? _excelGreen
                          : sheets[i].hidden
                              ? const Color(0xFF888888)
                              : const Color(0xFF444444),
                      fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                      fontStyle: sheets[i].hidden ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Grid ─────────────────────────────────────────────────────────────────────

/// Grid spreadsheet yang hanya menggambar sel terlihat, dengan header
/// kolom/baris tetap (sticky) dan zoom/pan via [InteractiveViewer].
class SheetGridView extends StatefulWidget {
  final SheetData sheet;
  final (int, int)? selected;
  final ValueChanged<(int, int)>? onSelect;
  const SheetGridView({super.key, required this.sheet, this.selected, this.onSelect});

  @override
  State<SheetGridView> createState() => _SheetGridViewState();
}

class _SheetGridViewState extends State<SheetGridView> {
  final _ctrl = TransformationController();
  late _Layout _layout;

  @override
  void initState() {
    super.initState();
    _layout = _Layout(widget.sheet);
  }

  @override
  void didUpdateWidget(SheetGridView old) {
    super.didUpdateWidget(old);
    if (old.sheet != widget.sheet) _layout = _Layout(widget.sheet);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap(TapUpDetails d) {
    final x = d.localPosition.dx - _Layout.rowHeaderW;
    final y = d.localPosition.dy - _Layout.colHeaderH;
    if (x < 0 || y < 0) return;
    var r = _layout.rowAt(y);
    var c = _layout.colAt(x);
    for (final m in widget.sheet.merges) {
      if (m.contains(r, c)) {
        r = m.r1;
        c = m.c1;
        break;
      }
    }
    widget.onSelect?.call((r, c));
  }

  Widget _drawing(SheetDrawing d) {
    final l = _layout;
    double colX(int c) => c < l.colX.length ? l.colX[c] : l.colX.last + (c - l.cols) * l.sheet.defaultColWidth;
    double rowY(int r) => r < l.rowY.length ? l.rowY[r] : l.rowY.last + (r - l.rows) * l.sheet.defaultRowHeight;
    final left = colX(d.fromCol) + d.fromColOff;
    final top = rowY(d.fromRow) + d.fromRowOff;
    final w = d.toCol != null ? colX(d.toCol!) + d.toColOff - left : d.width;
    final h = d.toRow != null ? rowY(d.toRow!) + d.toRowOff - top : d.height;
    if (w <= 1 || h <= 1) return const SizedBox.shrink();
    return Positioned(
      left: _Layout.rowHeaderW + left,
      top: _Layout.colHeaderH + top,
      width: w,
      height: h,
      child: d.chart != null
          ? DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD9D9D9))),
              child: ChartView(data: d.chart!, ptScale: 4 / 3),
            )
          : Image.memory(d.image!, fit: BoxFit.fill, gaplessPlayback: true,
              cacheWidth: (w * 2).round().clamp(32, 2400)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(_layout.width + _Layout.rowHeaderW,
        _layout.height + _Layout.colHeaderH);
    return ClipRect(
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GridPainter(_layout, _ctrl, widget.selected),
            ),
          ),
        ),
        // Gambar & chart ikut pan/zoom, di bawah header yang sticky
        if (widget.sheet.drawings.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, child) => Transform(
                  transform: _ctrl.value,
                  child: child,
                ),
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: SizedBox.fromSize(
                    size: size,
                    child: Stack(children: [
                      for (final d in widget.sheet.drawings) _drawing(d),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GridPainter(_layout, _ctrl, widget.selected, headers: true),
            ),
          ),
        ),
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _ctrl,
            constrained: false,
            minScale: 0.3,
            maxScale: 4,
            boundaryMargin: EdgeInsets.zero,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTap,
              child: SizedBox.fromSize(size: size),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Layout {
  static const rowHeaderW = 44.0;
  static const colHeaderH = 22.0;

  final SheetData sheet;
  late final int rows, cols;
  late final List<double> colX; // offset kiri kolom, panjang cols + 1
  late final List<double> rowY;
  final Map<int, TextPainter> _painters = {};

  _Layout(this.sheet) {
    var dCols = 0, dRows = 0;
    for (final d in sheet.drawings) {
      dCols = math.max(dCols, (d.toCol ?? d.fromCol) + 2);
      dRows = math.max(dRows, (d.toRow ?? d.fromRow) + 2);
      if (d.toCol == null) dCols = math.max(dCols, ((d.fromColOff + d.width) / sheet.defaultColWidth).ceil() + 2);
      if (d.toRow == null) dRows = math.max(dRows, ((d.fromRowOff + d.height) / sheet.defaultRowHeight).ceil() + 2);
    }
    cols = math.max(math.max(sheet.colCount + 3, 15), dCols);
    rows = math.max(math.max(sheet.rowCount + 20, 60), dRows);
    colX = List.filled(cols + 1, 0);
    for (var c = 0; c < cols; c++) {
      colX[c + 1] = colX[c] + sheet.colWidth(c);
    }
    rowY = List.filled(rows + 1, 0);
    for (var r = 0; r < rows; r++) {
      rowY[r + 1] = rowY[r] + sheet.rowHeight(r);
    }
  }

  double get width => colX.last;
  double get height => rowY.last;

  static int _search(List<double> offs, double v) {
    var lo = 0, hi = offs.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (offs[mid] <= v) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int colAt(double x) => _search(colX, x);
  int rowAt(double y) => _search(rowY, y);

  Rect cellRect(int r, int c) =>
      Rect.fromLTRB(colX[c], rowY[r], colX[c + 1], rowY[r + 1]);

  TextPainter painter(int r, int c, SheetCell cell, double maxWidth) {
    final key = r * 20000 + c;
    final cached = _painters[key];
    if (cached != null) return cached;
    if (_painters.length > 4000) _painters.clear();
    final s = cell.style;
    final tp = TextPainter(
      text: TextSpan(
        text: cell.text,
        style: TextStyle(
          fontSize: s.fontSize * 4 / 3,
          fontFamily: officeFontFamily(s.font) ?? kOfficeSans,
          fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
          color: s.color ?? Colors.black,
          decoration: TextDecoration.combine([
            if (s.underline) TextDecoration.underline,
            if (s.strike) TextDecoration.lineThrough,
          ]),
          height: 1.15,
        ),
      ),
      textAlign: _align(cell),
      textDirection: TextDirection.ltr,
      maxLines: s.wrap ? null : 1,
    )..layout(maxWidth: s.wrap ? math.max(1, maxWidth) : double.infinity);
    return _painters[key] = tp;
  }

  static TextAlign _align(SheetCell cell) =>
      cell.style.align ?? (cell.isNumber ? TextAlign.right : TextAlign.left);
}

class _GridPainter extends CustomPainter {
  final _Layout l;
  final TransformationController ctrl;
  final (int, int)? selected;

  /// true = hanya header kolom/baris (lapisan paling atas).
  final bool headers;
  _GridPainter(this.l, this.ctrl, this.selected, {this.headers = false})
      : super(repaint: ctrl);

  static const _gridColor = Color(0xFFE1E1E1);
  static const _headerBg = Color(0xFFF3F3F3);
  static const _headerLine = Color(0xFFC8C8C8);
  static const _green = Color(0xFF217346);

  @override
  void paint(Canvas canvas, Size size) {
    final m = ctrl.value;
    final s = m.getMaxScaleOnAxis();
    final tx = m.getTranslation().x;
    final ty = m.getTranslation().y;
    final sheet = l.sheet;
    const hw = _Layout.rowHeaderW, hh = _Layout.colHeaderH;

    if (headers) {
      final c0 = l.colAt(math.max(0, -tx / s - hw)), c1 = l.colAt(math.max(0, (size.width - tx) / s - hw));
      final r0 = l.rowAt(math.max(0, -ty / s - hh)), r1 = l.rowAt(math.max(0, (size.height - ty) / s - hh));
      _headers(canvas, size, s, tx, ty, c0, c1, r0, r1);
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Rentang sel terlihat (koordinat konten, tanpa header)
    final x0 = -tx / s - hw, x1 = (size.width - tx) / s - hw;
    final y0 = -ty / s - hh, y1 = (size.height - ty) / s - hh;
    final c0 = l.colAt(math.max(0, x0)), c1 = l.colAt(math.max(0, x1));
    final r0 = l.rowAt(math.max(0, y0)), r1 = l.rowAt(math.max(0, y1));

    canvas.save();
    // Konten digulir di bawah header yang tetap (sticky)
    canvas.clipRect(Rect.fromLTRB(hw * s, hh * s, size.width, size.height));
    canvas.translate(tx + hw * s, ty + hh * s);
    canvas.scale(s);

    final visibleMerges = sheet.merges
        .where((mg) => mg.r2 >= r0 && mg.r1 <= r1 && mg.c2 >= c0 && mg.c1 <= c1)
        .toList();
    bool covered(int r, int c) {
      for (final mg in visibleMerges) {
        if (mg.contains(r, c) && !(mg.r1 == r && mg.c1 == c)) return true;
      }
      return false;
    }

    Rect rectOf(int r, int c) {
      for (final mg in visibleMerges) {
        if (mg.r1 == r && mg.c1 == c) {
          final r2 = math.min(mg.r2, l.rows - 1), c2 = math.min(mg.c2, l.cols - 1);
          return Rect.fromLTRB(l.colX[c], l.rowY[r], l.colX[c2 + 1], l.rowY[r2 + 1]);
        }
      }
      return l.cellRect(r, c);
    }

    // 1. Gridlines
    if (sheet.showGrid) {
      final grid = Paint()
        ..color = _gridColor
        ..strokeWidth = 1 / s;
      final top = l.rowY[r0], bottom = l.rowY[math.min(r1 + 1, l.rows)];
      final left = l.colX[c0], right = l.colX[math.min(c1 + 1, l.cols)];
      for (var c = c0; c <= math.min(c1 + 1, l.cols); c++) {
        canvas.drawLine(Offset(l.colX[c], top), Offset(l.colX[c], bottom), grid);
      }
      for (var r = r0; r <= math.min(r1 + 1, l.rows); r++) {
        canvas.drawLine(Offset(left, l.rowY[r]), Offset(right, l.rowY[r]), grid);
      }
    }

    // 2. Area merge: tutup gridline di dalamnya
    for (final mg in visibleMerges) {
      final rect = rectOf(mg.r1, mg.c1);
      final fill = sheet.cell(mg.r1, mg.c1)?.style.fill ?? Colors.white;
      canvas.drawRect(rect.deflate(0.5 / s), Paint()..color = fill);
    }

    // 3. Isi warna, teks, border (merge anchor di luar layar ikut digambar)
    final anchors = <(int, int)>{
      for (final mg in visibleMerges) (mg.r1, mg.c1),
    };
    final rowStart = math.max(0, r0), rowEnd = math.min(r1, l.rows - 1);
    for (var r = rowStart; r <= rowEnd; r++) {
      final row = sheet.cells[r];
      if (row == null) continue;
      for (final c in row.keys) {
        if (c < c0 || c > c1) continue;
        anchors.add((r, c));
      }
    }

    final textOps = <void Function()>[];
    for (final (r, c) in anchors) {
      if (covered(r, c)) continue;
      final cell = sheet.cell(r, c);
      if (cell == null || r >= l.rows || c >= l.cols) continue;
      final rect = rectOf(r, c);
      final st = cell.style;
      if (st.fill != null) canvas.drawRect(rect, Paint()..color = st.fill!);
      if (cell.text.isNotEmpty) textOps.add(() => _text(canvas, r, c, cell, rect, c1));
      _borders(canvas, rect, st, s);
    }
    for (final op in textOps) {
      op();
    }

    // 4. Sel terpilih
    final sel = selected;
    if (sel != null && sel.$1 < l.rows && sel.$2 < l.cols) {
      canvas.drawRect(
        rectOf(sel.$1, sel.$2),
        Paint()
          ..color = _green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 / s,
      );
    }
    canvas.restore();
  }

  void _text(Canvas canvas, int r, int c, SheetCell cell, Rect rect, int lastVisibleCol) {
    final st = cell.style;
    const pad = 3.0;
    final tp = l.painter(r, c, cell, rect.width - pad * 2);
    final align = _Layout._align(cell);

    // Teks kiri yang tidak muat meluber ke sel kosong di kanannya (seperti Excel)
    var clip = rect;
    if (!st.wrap && tp.width > rect.width - pad * 2 && align == TextAlign.left && !cell.isNumber) {
      var cc = c + 1;
      var right = rect.right;
      while (cc < l.cols && cc <= lastVisibleCol + 1 && right - rect.left < tp.width + pad * 2) {
        final next = l.sheet.cell(r, cc);
        if (next != null && next.text.isNotEmpty) break;
        right = l.colX[cc + 1];
        cc++;
      }
      clip = Rect.fromLTRB(rect.left, rect.top, right, rect.bottom);
    }

    final dx = switch (align) {
      TextAlign.right => rect.right - pad - tp.width,
      TextAlign.center => rect.left + (rect.width - tp.width) / 2,
      _ => rect.left + pad,
    };
    final dy = switch (st.vAlign) {
      VAlign.top => rect.top + 1,
      VAlign.center => rect.top + (rect.height - tp.height) / 2,
      VAlign.bottom => rect.bottom - tp.height - 1,
    };
    canvas.save();
    canvas.clipRect(clip);
    tp.paint(canvas, Offset(st.wrap ? rect.left + pad : dx, math.max(rect.top, dy)));
    canvas.restore();
  }

  void _borders(Canvas canvas, Rect r, SheetCellStyle st, double s) {
    void line(Color? c, Offset a, Offset b) {
      if (c == null) return;
      canvas.drawLine(a, b, Paint()
        ..color = c
        ..strokeWidth = 1.2 / s);
    }

    line(st.borderTop, r.topLeft, r.topRight);
    line(st.borderBottom, r.bottomLeft, r.bottomRight);
    line(st.borderLeft, r.topLeft, r.bottomLeft);
    line(st.borderRight, r.topRight, r.bottomRight);
  }

  void _headers(Canvas canvas, Size size, double s, double tx, double ty, int c0,
      int c1, int r0, int r1) {
    final hw = _Layout.rowHeaderW * s, hh = _Layout.colHeaderH * s;
    final bg = Paint()..color = _headerBg;
    final line = Paint()
      ..color = _headerLine
      ..strokeWidth = 1;
    final selPaint = Paint()..color = const Color(0xFFD3E7DA);
    final ox = tx + hw, oy = ty + hh;
    final fontSize = (10.5 * s).clamp(7.0, 18.0);

    void label(String t, Rect rect, bool active) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            fontSize: fontSize,
            color: active ? _green : const Color(0xFF666666),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > rect.width + 4) return;
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }

    // Header kolom
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, hh), bg);
    for (var c = c0; c <= math.min(c1, l.cols - 1); c++) {
      final left = ox + l.colX[c] * s, right = ox + l.colX[c + 1] * s;
      if (right < hw) continue;
      final rect = Rect.fromLTRB(left, 0, right, hh);
      final active = selected?.$2 == c;
      if (active) canvas.drawRect(rect, selPaint);
      canvas.drawLine(Offset(right, 0), Offset(right, hh), line);
      label(columnLetter(c), rect, active);
    }
    canvas.drawLine(Offset(0, hh), Offset(size.width, hh), line);

    // Header baris
    canvas.drawRect(Rect.fromLTRB(0, hh, hw, size.height), bg);
    for (var r = r0; r <= math.min(r1, l.rows - 1); r++) {
      final top = oy + l.rowY[r] * s, bottom = oy + l.rowY[r + 1] * s;
      if (bottom < hh) continue;
      final rect = Rect.fromLTRB(0, math.max(hh, top), hw, bottom);
      final active = selected?.$1 == r;
      if (active) canvas.drawRect(rect, selPaint);
      canvas.drawLine(Offset(0, bottom), Offset(hw, bottom), line);
      if (top >= hh - 1) label('${r + 1}', Rect.fromLTRB(0, top, hw, bottom), active);
    }
    canvas.drawLine(Offset(hw, hh), Offset(hw, size.height), line);

    // Pojok kiri atas
    canvas.drawRect(Rect.fromLTRB(0, 0, hw, hh), Paint()..color = const Color(0xFFE6E6E6));
    canvas.drawLine(Offset(hw, 0), Offset(hw, hh), line);
    canvas.drawLine(Offset(0, hh), Offset(hw, hh), line);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.l != l || oldDelegate.selected != selected || oldDelegate.headers != headers;
}
