import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chart_view.dart';
import 'doc_model.dart';
import 'office_fonts.dart';

/// Membangun widget blok dokumen, sekaligus mengukur tingginya dengan
/// layout yang sama persis (dipakai pagination tampilan halaman).
///
/// [scale] = dp per point. [spacing] = faktor spasi paragraf (reflow
/// sedikit dirapatkan, tampilan halaman = 1 seperti Word).
class DocRenderer {
  final double scale;
  final double spacing;
  final double devicePixelRatio;
  final int pageNumber;
  final int pageCount;
  final List<TapGestureRecognizer> recognizers;

  /// true = tampilan halaman: margin sel & jarak tabel persis seperti Word.
  final bool exact;

  DocRenderer({
    required this.scale,
    this.exact = false,
    this.spacing = 1,
    this.devicePixelRatio = 2,
    this.pageNumber = 1,
    this.pageCount = 1,
    List<TapGestureRecognizer>? recognizers,
  }) : recognizers = recognizers ?? [];

  DocRenderer forPage(int page, int count) => DocRenderer(
        scale: scale,
        exact: exact,
        spacing: spacing,
        devicePixelRatio: devicePixelRatio,
        pageNumber: page,
        pageCount: count,
        recognizers: recognizers,
      );

  static const _imageGap = 6.0;
  static const _cellPad = 4.0;

  // ── Gaya teks ─────────────────────────────────────────────────────────────

  /// Kelipatan tinggi baris Flutter (`TextStyle.height`) untuk satu run:
  /// spasi Word × tinggi baris alami font, atau nilai tetap "Exactly".
  static double lineHeightFor(DocParagraph? p, String family, double fontSizePt) {
    if (p?.lineExact != null) return p!.lineExact! / fontSizePt;
    final natural = lineFactor(family) * (p?.lineHeight ?? 1.0);
    final least = p?.lineAtLeast;
    if (least != null) return math.max(natural, least / fontSizePt);
    return natural;
  }

  TextStyle runStyle(DocText r, [DocParagraph? para]) {
    final small = r.superscript || r.subscript;
    final family = officeFontFamily(r.fontFamily) ?? kOfficeSans;
    final sizePt = (r.fontSize ?? 11) * (small ? 0.65 : 1);
    return TextStyle(
      fontSize: sizePt * scale,
      height: lineHeightFor(para, family, sizePt).clamp(0.5, 6.0),
      fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
      color: r.color ?? Colors.black,
      backgroundColor: r.highlight,
      fontFamily: family,
      letterSpacing: 0,
      wordSpacing: 0,
      fontFeatures: _wordFeatures,
      decoration: TextDecoration.combine([
        if (r.underline) TextDecoration.underline,
        if (r.strike) TextDecoration.lineThrough,
      ]),
      decorationColor: r.color ?? Colors.black,
    );
  }

  /// Teks yang ditampilkan untuk satu run (tab → spasi, caps, field halaman).
  String displayText(DocText t) {
    if (t.field == 'PAGE') return '$pageNumber';
    if (t.field == 'NUMPAGES') return pageCount > 0 ? '$pageCount' : '…';
    final s = t.text.replaceAll('\t', '    ');
    return t.allCaps ? s.toUpperCase() : s;
  }

  // ── Layout paragraf (dipakai bersama oleh build & measure) ───────────────

  _ParaLayout _layout(DocParagraph p, double avail) {
    final s = scale;
    final firstText = p.inlines.whereType<DocText>().firstOrNull;
    final baseSize = (firstText?.fontSize ?? 11) * s;
    final family = officeFontFamily(firstText?.fontFamily) ?? kOfficeSans;
    final height = lineHeightFor(p, family, firstText?.fontSize ?? 11).clamp(0.5, 6.0).toDouble();
    final hasText = p.inlines.any((i) => i is DocText && (i.text.trim().isNotEmpty || i.field != null));
    final visuals = p.inlines.where((i) => i is DocImage || i is DocChart).toList();

    var left = p.indentLeft * s;
    double? labelW;
    if (p.listLabel != null) {
      final hanging = p.firstLine < 0 ? -p.firstLine * s : baseSize * 1.6;
      left = math.max(0, left - hanging);
      labelW = math.max(hanging, baseSize * 1.2);
    }
    left = math.min(left, avail * 0.5);
    final right = math.min(p.indentRight * s, avail * 0.3);
    final contentW = math.max(8.0, avail - left - right - (labelW ?? 0));

    return _ParaLayout(
      baseSize: baseSize,
      height: height,
      hasText: hasText,
      visuals: visuals,
      left: left,
      right: right,
      top: p.spaceBefore * s * spacing,
      bottom: p.spaceAfter * s * spacing,
      labelW: labelW,
      contentW: contentW,
      firstText: firstText,
    );
  }

  Size _visualSize(DocInline v, double avail) {
    final (w0, h0) = switch (v) {
      DocImage(:final width, :final height) => (width, height),
      DocChart(:final width, :final height) => (width, height),
      _ => (0.0, 0.0),
    };
    if (w0 <= 0) return const Size(1, 1);
    final w = math.min(w0 * scale, avail);
    final h = h0 * scale * (w / (w0 * scale));
    return Size(w, v is DocImage && v.bytes == null ? math.max(h, 40) : h);
  }

  /// Span teks + ukuran placeholder untuk gambar/chart inline.
  (List<InlineSpan>, List<Size>) _spans(DocParagraph p, double avail, {bool build = true}) {
    final spans = <InlineSpan>[];
    final sizes = <Size>[];
    if (p.firstLine > 0 && p.listLabel == null) {
      final w = p.firstLine * scale;
      spans.add(WidgetSpan(child: SizedBox(width: w)));
      sizes.add(Size(w, 0));
    }
    for (final inline in p.inlines) {
      switch (inline) {
        case DocText():
          TapGestureRecognizer? rec;
          final link = inline.link;
          if (build && link != null && link.startsWith('http')) {
            rec = TapGestureRecognizer()
              ..onTap = () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
            recognizers.add(rec);
          }
          spans.add(TextSpan(text: displayText(inline), style: runStyle(inline, p), recognizer: rec));
        case DocImage() || DocChart():
          final size = _visualSize(inline, avail);
          sizes.add(size);
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.bottom,
            child: build ? _visual(inline, avail) : SizedBox.fromSize(size: size),
          ));
        case DocBreakMarker():
          break;
      }
    }
    return (spans, sizes);
  }

  /// Gaya dasar paragraf. letterSpacing/wordSpacing dinolkan eksplisit karena
  /// tema Material menambahkan letterSpacing 0.25 (beda dengan Word & ukuran).
  TextStyle _rootStyle(_ParaLayout l) => TextStyle(
        fontSize: l.baseSize,
        height: l.height,
        color: Colors.black,
        fontFamily: kOfficeSans,
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
        letterSpacing: 0,
        wordSpacing: 0,
        fontFeatures: _wordFeatures,
      );

  /// Word tidak memakai kerning & ligatur secara default; Flutter memakainya.
  /// Dimatikan agar lebar baris (dan pindah halaman) sama dengan Word.
  static const _wordFeatures = [FontFeature.disable('kern'), FontFeature.disable('liga')];

  TextPainter _painter(DocParagraph p, _ParaLayout l) {
    final (spans, sizes) = _spans(p, l.contentW, build: false);
    final tp = TextPainter(
      text: TextSpan(
        style: _rootStyle(l),
        children: spans,
      ),
      textAlign: p.align,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );
    tp.setPlaceholderDimensions([
      for (final s in sizes)
        PlaceholderDimensions(size: s, alignment: PlaceholderAlignment.bottom),
    ]);
    tp.layout(maxWidth: l.contentW);
    return tp;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  // Sel tabel yang sangat sempit bisa memberi lebar ≤ 0
  Widget block(DocBlock b, double avail) => switch (b) {
        DocParagraph() => paragraph(b, math.max(avail, 8)),
        DocTable() => table(b, math.max(avail, 8)),
        DocPageBreak() => const SizedBox.shrink(),
      };

  Widget blocks(List<DocBlock> bs, double avail) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (final b in bs) block(b, avail)],
      );

  Widget paragraph(DocParagraph p, double avail) {
    final l = _layout(p, avail);
    if (!l.hasText && l.visuals.isEmpty) {
      return SizedBox(height: _emptyHeight(p, l));
    }

    Widget content;
    if (!l.hasText) {
      // Paragraf berisi gambar/chart saja: tampilkan sebagai blok (lebih stabil)
      content = Wrap(
        alignment: switch (p.align) {
          TextAlign.center => WrapAlignment.center,
          TextAlign.right => WrapAlignment.end,
          _ => WrapAlignment.start,
        },
        spacing: _imageGap,
        runSpacing: _imageGap,
        children: [for (final v in l.visuals) _visual(v, l.contentW)],
      );
    } else {
      final (spans, _) = _spans(p, l.contentW);
      content = Text.rich(
        TextSpan(
          style: _rootStyle(l),
          children: spans,
        ),
        textAlign: p.align,
      );
    }

    if (l.labelW != null) {
      final ft = l.firstText;
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: l.labelW,
            child: Text(p.listLabel!,
                style: ft != null
                    ? runStyle(ft, p).copyWith(decoration: TextDecoration.none, backgroundColor: Colors.transparent)
                    : TextStyle(fontSize: l.baseSize, color: Colors.black, fontFamily: kOfficeSans),
                strutStyle: StrutStyle(fontSize: l.baseSize, height: l.height, forceStrutHeight: true)),
          ),
          Expanded(child: content),
        ],
      );
    }

    return Container(
      color: p.shading,
      padding: EdgeInsets.only(left: l.left, right: l.right, top: l.top, bottom: l.bottom),
      child: content,
    );
  }

  double _emptyHeight(DocParagraph p, _ParaLayout l) =>
      l.baseSize * l.height + l.top + l.bottom;

  Widget _visual(DocInline v, double avail) {
    final size = _visualSize(v, avail);
    if (v is DocChart) {
      return SizedBox.fromSize(
        size: size,
        child: ChartView(data: v.chart, ptScale: scale * size.width / (v.width * scale)),
      );
    }
    final img = v as DocImage;
    if (img.bytes == null) {
      return Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          border: Border.all(color: const Color(0xFFCCCCCC)),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Color(0xFF999999)),
        ),
      );
    }
    return Image.memory(
      img.bytes!,
      width: size.width,
      height: size.height,
      fit: BoxFit.contain,
      cacheWidth: (size.width * devicePixelRatio).round().clamp(32, 2400),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox.fromSize(
        size: size,
        child: const Icon(Icons.broken_image_outlined, color: Color(0xFF999999)),
      ),
    );
  }

  (double, List<double>) _tableGeometry(DocTable t, double avail) {
    final widths = t.columnWidths.map((w) => w <= 0 ? 36.0 : w).toList();
    final total = widths.fold<double>(0, (a, b) => a + b);
    final natural = total * scale;
    // Tabel sedikit lebih lebar dari layar dipadatkan; tabel lebar bisa digeser
    final width = natural <= avail * 1.6 ? math.min(natural, avail) : natural;
    final factor = total <= 0 ? 1.0 : width / total;
    return (width, [for (final w in widths) w * factor]);
  }

  /// Lebar tiap sel di baris (mengikuti colSpan); sisa kolom kosong di akhir.
  static List<(DocTableCell?, double)> _rowCells(DocTableRow row, List<double> cols) {
    final out = <(DocTableCell?, double)>[];
    var col = 0;
    for (final cell in row.cells) {
      if (col >= cols.length) break;
      final span = math.min(cell.colSpan, cols.length - col);
      out.add((cell, cols.sublist(col, col + span).fold<double>(0, (a, b) => a + b)));
      col += span;
    }
    if (col < cols.length) out.add((null, cols.sublist(col).fold<double>(0, (a, b) => a + b)));
    return out;
  }

  /// Padding sel: persis margin Word di tampilan halaman, sedikit lebih lega
  /// di tampilan mobile.
  ///
  /// Container menambahkan tebal border ke padding; di Word margin sel diukur
  /// dari garis sel, jadi tebal border dikurangkan agar lebar teks sama.
  EdgeInsets _cellPadding(DocTable t) {
    if (!exact) return EdgeInsets.all(_cellPad * scale / 1.25);
    final bw = _borderW(t);
    final h = math.max(0.0, t.cellMarginH * scale - bw);
    return EdgeInsets.fromLTRB(h, t.cellMarginTop * scale, h, t.cellMarginBottom * scale);
  }

  /// Lebar teks di dalam sel (border kiri/kanan ikut mengurangi ruang).
  double _cellTextWidth(DocTable t, double cellW) =>
      cellW - _cellPadding(t).horizontal - (t.borders ? (exact ? _borderW(t) : 0.6) * 2 : 0);

  /// Garis border tabel menambah tinggi baris (Word: ½ pt per garis).
  double _borderW(DocTable t) => t.borders ? 0.5 * scale : 0;

  Widget table(DocTable t, double avail) {
    if (t.rows.isEmpty || t.columnWidths.isEmpty) return const SizedBox.shrink();
    final (width, cols) = _tableGeometry(t, avail);
    final bw = exact ? _borderW(t) : 0.6;
    final border = BorderSide(color: const Color(0xFF8C8C8C), width: bw);
    final pad = _cellPadding(t);

    final rows = <Widget>[];
    for (var ri = 0; ri < t.rows.length; ri++) {
      final row = t.rows[ri];
      // Mode halaman: baris bersebelahan berbagi satu garis (seperti Word)
      final topBorder = !exact || ri == 0;
      final cells = <Widget>[];
      for (final (cell, w) in _rowCells(row, cols)) {
        if (cell == null) {
          cells.add(SizedBox(width: w));
          continue;
        }
        cells.add(Container(
          width: w,
          padding: pad,
          decoration: BoxDecoration(
            color: cell.shading,
            border: t.borders
                ? Border(
                    left: border,
                    right: border,
                    top: cell.mergedContinue || !topBorder ? BorderSide.none : border,
                    bottom: border,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [for (final b in cell.blocks) block(b, _cellTextWidth(t, w))],
          ),
        ));
      }
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ));
    }

    final tableW = SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _tableVPad),
      child: width > avail + 0.5
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: tableW)
          : tableW,
    );
  }

  double get _tableVPad => exact ? 0 : 6 * scale / 1.25;

  // ── Measure (untuk pagination) ───────────────────────────────────────────

  // Cache ukuran per objek blok/baris (pagination memeriksa blok yang sama
  // berkali-kali, mis. tabel panjang yang dipecah ke banyak halaman)
  final _blockCache = Expando<Map<double, double>>();
  final _rowCache = Expando<Map<double, double>>();

  double measure(DocBlock b, double avail) {
    final cache = _blockCache[b] ??= {};
    return cache[avail] ??= switch (b) {
      DocParagraph() => _measurePara(b, math.max(avail, 8)),
      DocTable() => measureTable(b, math.max(avail, 8)),
      DocPageBreak() => 0,
    };
  }

  double _measurePara(DocParagraph p, double avail) {
    final l = _layout(p, avail);
    if (!l.hasText && l.visuals.isEmpty) return _emptyHeight(p, l);
    double content;
    if (!l.hasText) {
      // Simulasi Wrap
      var rowW = 0.0, rowH = 0.0, total = 0.0;
      for (final v in l.visuals) {
        final s = _visualSize(v, l.contentW);
        if (rowW > 0 && rowW + _imageGap + s.width > l.contentW) {
          total += rowH + _imageGap;
          rowW = 0;
          rowH = 0;
        }
        rowW += (rowW > 0 ? _imageGap : 0) + s.width;
        rowH = math.max(rowH, s.height);
      }
      content = total + rowH;
    } else {
      content = _painter(p, l).height;
    }
    if (l.labelW != null) content = math.max(content, l.baseSize * l.height);
    return content + l.top + l.bottom;
  }

  List<double> rowHeights(DocTable t, double avail) {
    final (_, cols) = _tableGeometry(t, avail);
    final pad = _cellPadding(t);
    // Border bawah tiap baris (+ atas di baris pertama / semua baris di mobile)
    double borders(int ri) {
      if (!t.borders) return 0;
      if (!exact) return 1.2;
      return _borderW(t) * (ri == 0 ? 2 : 1);
    }

    double content(DocTableRow row) {
      final cache = _rowCache[row] ??= {};
      return cache[avail] ??= _rowCells(row, cols).fold<double>(0, (m, e) {
        final (cell, w) = e;
        if (cell == null) return m;
        return math.max(m, cell.blocks.fold<double>(0, (a, b) => a + measure(b, _cellTextWidth(t, w))));
      });
    }

    return [
      for (var ri = 0; ri < t.rows.length; ri++) content(t.rows[ri]) + pad.vertical + borders(ri)
    ];
  }

  double measureTable(DocTable t, double avail) {
    if (t.rows.isEmpty || t.columnWidths.isEmpty) return 0;
    return rowHeights(t, avail).fold<double>(0, (a, b) => a + b) + _tableVPad * 2;
  }

  double get tableVerticalPadding => _tableVPad;

  /// Tinggi minimum blok agar bisa dimulai di halaman ini: spasi sebelum +
  /// [lines] baris pertama paragraf (aturan widow Word), atau baris pertama tabel.
  double minStartHeight(DocBlock b, double avail, {int lines = 2}) {
    if (b is DocTable) {
      final hs = rowHeights(b, avail);
      return (hs.isEmpty ? 0 : hs.first) + _tableVPad;
    }
    if (b is! DocParagraph) return 0;
    final l = _layout(b, avail);
    if (!l.hasText) return _measurePara(b, avail);
    final metrics = _painter(b, l).computeLineMetrics();
    if (metrics.length <= 3) return _measurePara(b, avail) - l.bottom;
    return l.top + metrics.take(lines).fold<double>(0, (a, m) => a + m.height);
  }

  /// Ruang ekstra spasi kelipatan (>1×) pada baris terakhir di dasar halaman.
  /// Word menaruh tambahan itu di bawah teks dan membiarkannya terpotong.
  double lineSlack(DocParagraph p) {
    final mult = p.lineHeight;
    if (mult == null || mult <= 1 || p.lineExact != null) return 0;
    final t = p.inlines.whereType<DocText>().firstOrNull;
    final family = officeFontFamily(t?.fontFamily) ?? kOfficeSans;
    return (mult - 1) * lineFactor(family) * (t?.fontSize ?? 11) * scale;
  }

  /// Kelonggaran baris tabel di dasar halaman: slack terbesar dari paragraf
  /// terakhir di tiap sel baris itu.
  double rowSlack(DocTableRow row) {
    var m = 0.0;
    for (final c in row.cells) {
      final last = c.blocks.whereType<DocParagraph>().lastOrNull;
      if (last != null) m = math.max(m, lineSlack(last));
    }
    return m;
  }

  /// Pecah satu baris tabel agar bagian atasnya muat dalam [maxHeight]
  /// (Word: baris boleh terpotong ke halaman berikutnya). Tiap sel dipotong
  /// di batas paragraf/baris teks; sel yang sudah habis kosong di lanjutan.
  (DocTableRow, DocTableRow)? splitRow(DocTable t, DocTableRow row, double avail, double maxHeight, {required bool firstRow}) {
    if (row.cantSplit) return null;
    final (_, cols) = _tableGeometry(t, avail);
    final pad = _cellPadding(t);
    final border = t.borders ? (exact ? _borderW(t) : 0.6) * (firstRow ? 2 : 1) : 0.0;
    final room = maxHeight - pad.vertical - border;
    if (room <= 0) return null;

    final top = <DocTableCell>[], rest = <DocTableCell>[];
    var anyTop = false, anyRest = false;
    for (final (cell, w) in _rowCells(row, cols)) {
      if (cell == null) continue;
      final cw = _cellTextWidth(t, w);
      final a = <DocBlock>[], b = <DocBlock>[];
      var used = 0.0;
      var overflow = false;
      for (final blk in cell.blocks) {
        if (overflow) {
          b.add(blk);
          continue;
        }
        final h = measure(blk, cw);
        if (used + h - (blk is DocParagraph ? blk.spaceAfter * scale + lineSlack(blk) : 0) <= room) {
          a.add(blk);
          used += h;
          continue;
        }
        overflow = true;
        final parts = blk is DocParagraph ? split(blk, cw, room - used, minLines: 1) : null;
        if (parts != null) {
          a.add(parts.$1);
          b.add(parts.$2);
        } else {
          b.add(blk);
        }
      }
      if (a.isNotEmpty) anyTop = true;
      if (b.isNotEmpty) anyRest = true;
      top.add(DocTableCell(a, colSpan: cell.colSpan, shading: cell.shading, mergedContinue: cell.mergedContinue));
      rest.add(DocTableCell(b, colSpan: cell.colSpan, shading: cell.shading, mergedContinue: true));
    }
    if (!anyTop || !anyRest) return null;
    return (DocTableRow(top, header: row.header), DocTableRow(rest, cantSplit: false));
  }

  /// Pecah paragraf agar bagian pertama muat dalam [maxHeight]. Mengikuti
  /// kontrol widow/orphan Word (minimal 2 baris di tiap bagian).
  (DocParagraph, DocParagraph)? split(DocParagraph p, double avail, double maxHeight, {int minLines = 2}) {
    final l = _layout(p, avail);
    if (!l.hasText) return null;
    final tp = _painter(p, l);
    final lines = tp.computeLineMetrics();
    if (lines.length < minLines * 2) return null;
    var y = l.top;
    var fit = 0;
    final slack = lineSlack(p);
    for (final m in lines) {
      if (y + m.height - slack > maxHeight) break;
      y += m.height;
      fit++;
    }
    if (lines.length - fit < minLines) fit = lines.length - minLines;
    if (fit < minLines) return null;
    final lineTop = lines.take(fit).fold<double>(0, (a, m) => a + m.height);
    final offset = tp.getPositionForOffset(Offset(1, lineTop + lines[fit].height / 2)).offset;
    // Mundur ke awal baris (getPositionForOffset bisa jatuh di tengah kata)
    final boundary = tp.getLineBoundary(TextPosition(offset: offset)).start;
    final (a, b) = _splitInlines(p, boundary);
    if (a.isEmpty || b.isEmpty) return null;
    return (p.head(a), p.continuation(b));
  }

  /// Bagi inline di posisi karakter [at] (koordinat teks tampilan).
  (List<DocInline>, List<DocInline>) _splitInlines(DocParagraph p, int at) {
    var pos = p.firstLine > 0 && p.listLabel == null ? 1 : 0;
    final a = <DocInline>[], b = <DocInline>[];
    for (final inline in p.inlines) {
      if (inline is DocBreakMarker) continue;
      final len = inline is DocText ? displayText(inline).length : 1;
      if (pos + len <= at) {
        a.add(inline);
      } else if (pos >= at) {
        b.add(inline);
      } else if (inline is DocText && inline.field == null) {
        // Petakan offset tampilan → offset teks asli (tab = 4 spasi)
        final local = at - pos;
        var disp = 0, orig = 0;
        while (orig < inline.text.length && disp < local) {
          disp += inline.text[orig] == '\t' ? 4 : 1;
          orig++;
        }
        a.add(inline.copyWith(text: inline.text.substring(0, orig)));
        final rest = inline.text.substring(orig).replaceFirst(RegExp(r'^ +'), '');
        if (rest.isNotEmpty) b.add(inline.copyWith(text: rest));
      } else {
        a.add(inline);
      }
      pos += len;
    }
    return (a, b);
  }
}

class _ParaLayout {
  final double baseSize, height, left, right, top, bottom, contentW;
  final double? labelW;
  final bool hasText;
  final List<DocInline> visuals;
  final DocText? firstText;
  _ParaLayout({
    required this.baseSize,
    required this.height,
    required this.hasText,
    required this.visuals,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.labelW,
    required this.contentW,
    required this.firstText,
  });
}
