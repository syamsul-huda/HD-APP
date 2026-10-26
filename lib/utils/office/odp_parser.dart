import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'chart_parser.dart';
import 'odf_styles.dart';
import 'office_common.dart';
import 'slide_model.dart';

/// Parser ODP (LibreOffice Impress) ke model slide berposisi absolut.
SlideDeck parseOdp(Uint8List data) => _OdpParser(OfficePackage(data)).parse();

class _OdpParser {
  final OfficePackage pkg;
  late final OdfStyles styles;
  final Map<String, String> _fillImages = {};
  final Map<String, Color> _gradients = {};
  double _pageW = 793.7, _pageH = 446.5;

  _OdpParser(this.pkg);

  SlideDeck parse() {
    final content = pkg.xml('content.xml');
    final pres = content?.first('presentation');
    if (pres == null) throw const FormatException('Not a valid ODP presentation');
    styles = OdfStyles(pkg);

    final stylesDoc = pkg.xml('styles.xml');
    for (final e in stylesDoc?.descendantElements ?? const Iterable<XmlElement>.empty()) {
      final name = e.attr('name');
      if (name == null) continue;
      if (e.localName == 'fill-image') {
        _fillImages[name] = e.attr('href') ?? '';
      } else if (e.localName == 'gradient') {
        final a = parseHexColor(e.attr('start-color'));
        final b = parseHexColor(e.attr('end-color'));
        final c = a != null && b != null ? Color.lerp(a, b, 0.5) : a ?? b;
        if (c != null) _gradients[name] = c;
      }
    }

    var w = 793.7, h = 446.5; // 28 cm × 15.75 cm (16:9)
    final firstMaster = styles.masterPages.values.firstOrNull;
    final layout = styles.pageLayouts[firstMaster?.attr('page-layout-name')]
        ?.child('page-layout-properties');
    if (layout != null) {
      w = odfLength(layout.attr('page-width')) ?? w;
      h = odfLength(layout.attr('page-height')) ?? h;
    }

    _pageW = w;
    _pageH = h;
    final slides = <SlideData>[];
    for (final page in pres.kids('page')) {
      final master = styles.masterPages[page.attr('master-page-name')];
      final (bg, bgImage) = _background(page, master);
      final shapes = <SlideShape>[];
      final pageProps = styles.props('drawing-page', page.attr('style-name'), 'drawing-page-properties');
      final showMaster = pageProps.every((p) => p.attr('background-objects-visible') != 'false');
      if (master != null && showMaster) _shapes(master, shapes, template: true);
      _shapes(page, shapes, template: false);

      var notes = '';
      final n = page.child('notes');
      if (n != null) {
        notes = n.descendantElements
            .where((e) => e.localName == 'p')
            .map((p) => p.innerText)
            .join('\n')
            .trim();
      }
      final hidden = pageProps.any((p) => p.attr('visibility') == 'hidden') ||
          page.attr('visibility') == 'hidden';
      slides.add(SlideData(
          background: bg, backgroundImage: bgImage, shapes: shapes, notes: notes, hidden: hidden));
    }
    return SlideDeck(w, h, slides);
  }

  (Color, Uint8List?) _background(XmlElement page, XmlElement? master) {
    for (final name in [page.attr('style-name'), master?.attr('style-name')]) {
      if (name == null) continue;
      for (final p in styles.props('drawing-page', name, 'drawing-page-properties').reversed) {
        final fill = p.attr('fill');
        if (fill == 'solid' || (fill == null && p.attr('fill-color') != null)) {
          return (parseHexColor(p.attr('fill-color')) ?? kWhite, null);
        }
        if (fill == 'bitmap') {
          final href = _fillImages[p.attr('fill-image-name')];
          if (href != null && isRenderableImage(href)) return (kWhite, pkg.bytes(href));
        }
        if (fill == 'gradient') {
          final c = _gradients[p.attr('fill-gradient-name')];
          if (c != null) return (c, null);
        }
        if (fill == 'none') break;
      }
    }
    return (kWhite, null);
  }

  void _shapes(XmlElement parent, List<SlideShape> out, {required bool template}) {
    for (final el in parent.childElements) {
      if (el.localName == 'g') {
        _shapes(el, out, template: template);
        continue;
      }
      if (el.localName == 'notes' || el.localName == 'forms') continue;
      // Placeholder kosong ("Klik untuk menambah judul") tidak ditampilkan
      if (el.attr('placeholder') == 'true') continue;
      if (template && el.attr('class') != null) continue;
      final s = _shape(el);
      if (s != null) out.add(s);
    }
  }

  ({Rect rect, double rot})? _geometry(XmlElement el) {
    if (el.localName == 'line' || el.localName == 'connector') {
      final x1 = odfLength(el.attr('x1')) ?? 0, y1 = odfLength(el.attr('y1')) ?? 0;
      final x2 = odfLength(el.attr('x2')) ?? 0, y2 = odfLength(el.attr('y2')) ?? 0;
      return (rect: Rect.fromPoints(Offset(x1, y1), Offset(x2, y2)), rot: 0.0);
    }
    final w = odfLength(el.attr('width'));
    final h = odfLength(el.attr('height'));
    if (w == null || h == null) return null;
    final tr = el.attr('transform');
    if (tr != null) {
      final rot = double.tryParse(
              RegExp(r'rotate\s*\(\s*([-\d.eE]+)').firstMatch(tr)?.group(1) ?? '') ??
          0;
      final t = RegExp(r'translate\s*\(\s*([-\d.]+[a-z]*)\s+([-\d.]+[a-z]*)').firstMatch(tr);
      final tx = odfLength(t?.group(1)) ?? 0;
      final ty = odfLength(t?.group(2)) ?? 0;
      // Rotasi ODF berlawanan arah jarum jam terhadap titik asal shape
      final cx = tx + (w / 2) * math.cos(rot) + (h / 2) * math.sin(rot);
      final cy = ty - (w / 2) * math.sin(rot) + (h / 2) * math.cos(rot);
      return (
        rect: Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
        rot: -rot * 180 / math.pi
      );
    }
    final x = odfLength(el.attr('x')) ?? 0;
    final y = odfLength(el.attr('y')) ?? 0;
    return (rect: Rect.fromLTWH(x, y, w, h), rot: 0.0);
  }

  SlideShape? _shape(XmlElement el) {
    const handled = {
      'frame', 'custom-shape', 'rect', 'ellipse', 'circle', 'line', //
      'connector', 'polygon', 'polyline', 'caption'
    };
    if (!handled.contains(el.localName)) return null;
    // Tanpa ukuran: tampilkan di area isi standar agar isinya tidak hilang
    final g = _geometry(el) ??
        (rect: Rect.fromLTWH(_pageW * 0.05, _pageH * 0.2, _pageW * 0.9, _pageH * 0.7), rot: 0.0);

    final isFrame = el.localName == 'frame';
    // Frame placeholder memakai style presentasi, shape biasa style grafis
    final presStyle = el.attrNs('presentation', 'style-name');
    final family = presStyle != null ? 'presentation' : 'graphic';
    final styleName = presStyle ?? el.attrNs('draw', 'style-name');
    final gp = styles.props(family, styleName, 'graphic-properties');
    String? gAttr(String n) {
      for (final p in gp.reversed) {
        final v = p.attr(n);
        if (v != null) return v;
      }
      return null;
    }

    // Isi & garis
    final fillMode = gAttr('fill') ?? (isFrame ? 'none' : 'solid');
    Color? fill;
    Uint8List? fillImage;
    if (fillMode == 'solid') {
      fill = parseHexColor(gAttr('fill-color')) ?? const Color(0xFF729FCF);
    } else if (fillMode == 'gradient') {
      fill = _gradients[gAttr('fill-gradient-name')];
    } else if (fillMode == 'bitmap') {
      final href = _fillImages[gAttr('fill-image-name')];
      if (href != null && isRenderableImage(href)) fillImage = pkg.bytes(href);
    }
    final isLine = el.localName == 'line' || el.localName == 'connector';
    final strokeMode = gAttr('stroke') ?? (isFrame ? 'none' : 'solid');
    Color? stroke;
    var strokeW = 0.0;
    if (strokeMode != 'none') {
      stroke = parseHexColor(gAttr('stroke-color')) ?? const Color(0xFF3465A4);
      strokeW = odfLength(gAttr('stroke-width')) ?? 0;
      if (strokeW <= 0) strokeW = 0.75;
    }

    // Geometri
    var geom = isLine ? ShapeGeom.line : ShapeGeom.rect;
    final path = <PathCmd>[];
    if (el.localName == 'ellipse' || el.localName == 'circle') geom = ShapeGeom.ellipse;
    if (el.localName == 'custom-shape') {
      final type = el.child('enhanced-geometry')?.attr('type') ?? 'rectangle';
      geom = switch (type) {
        'ellipse' || 'circle' || 'ring' => ShapeGeom.ellipse,
        'round-rectangle' || 'round-square' || 'flowchart-alternate-process' => ShapeGeom.roundRect,
        'isosceles-triangle' || 'flowchart-extract' => ShapeGeom.triangle,
        'diamond' || 'flowchart-decision' => ShapeGeom.diamond,
        _ => ShapeGeom.rect,
      };
    }
    if (el.localName == 'polygon' || el.localName == 'polyline') {
      final vb = (el.attr('viewBox') ?? '').split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
      final pts = RegExp(r'(-?[\d.]+),(-?[\d.]+)')
          .allMatches(el.attr('points') ?? '')
          .map((m) => Offset(double.parse(m.group(1)!), double.parse(m.group(2)!)))
          .toList();
      if (vb.length == 4 && vb[2] != null && vb[3] != null && vb[2]! > 0 && vb[3]! > 0 && pts.isNotEmpty) {
        final norm = pts
            .map((p) => Offset((p.dx - (vb[0] ?? 0)) / vb[2]!, (p.dy - (vb[1] ?? 0)) / vb[3]!))
            .toList();
        geom = ShapeGeom.path;
        path.add(PathCmd('M', [norm.first]));
        if (norm.length > 1) path.add(PathCmd('L', norm.sublist(1)));
        if (el.localName == 'polygon') path.add(const PathCmd('Z', []));
        if (el.localName == 'polyline') fill = null;
      }
    }

    // Konten frame
    Uint8List? image;
    var unsupported = false;
    var isChart = false;
    XmlElement textHost = el;
    if (isFrame) {
      final imgs = el.kids('image').toList();
      if (imgs.isNotEmpty) {
        final ok = imgs.where((i) => isRenderableImage(i.attr('href') ?? '')).firstOrNull;
        if (ok != null) {
          image = pkg.bytes(ok.attr('href')!);
        } else {
          unsupported = true;
        }
      }
      final obj = el.child('object');
      if (obj != null || el.child('object-ole') != null) {
        ChartData? chart;
        try {
          final href = obj?.attr('href');
          if (href != null) chart = parseOdfChart(pkg, href);
        } catch (_) {}
        if (chart != null) {
          return SlideShape(rect: g.rect, rotation: g.rot, chart: chart);
        }
        isChart = true;
      }
      final tbl = el.child('table');
      if (tbl != null) {
        return SlideShape(rect: g.rect, rotation: g.rot, table: _table(tbl, g.rect));
      }
      textHost = el.child('text-box') ?? el;
    }

    final text = _text(textHost, family, styleName, gAttr);
    final hasVisual = fill != null || fillImage != null || stroke != null || image != null ||
        unsupported || isChart;
    if (!hasVisual && (text == null || text.isEmpty)) return null;

    return SlideShape(
      rect: g.rect,
      rotation: g.rot,
      geom: geom,
      fill: fill,
      lineColor: stroke,
      lineWidth: strokeW,
      image: image ?? fillImage,
      imageUnsupported: unsupported && image == null,
      isChart: isChart && image == null,
      text: text,
      path: path,
      flipV: isLine && _lineGoesUp(el),
    );
  }

  bool _lineGoesUp(XmlElement el) {
    final x1 = odfLength(el.attr('x1')) ?? 0, y1 = odfLength(el.attr('y1')) ?? 0;
    final x2 = odfLength(el.attr('x2')) ?? 0, y2 = odfLength(el.attr('y2')) ?? 0;
    return (x2 - x1) * (y2 - y1) < 0;
  }

  SlideText? _text(XmlElement host, String family, String? styleName,
      String? Function(String) gAttr) {
    final base = _RunStyle();
    for (final p in styles.props(family, styleName, 'text-properties')) {
      base.apply(p);
    }
    final baseAlign = _align(styles.props(family, styleName, 'paragraph-properties'));
    final paragraphs = <SlideParagraph>[];
    _paragraphs(host, base, baseAlign, paragraphs, level: -1);
    if (paragraphs.isEmpty) return null;

    return SlideText(
      paragraphs: paragraphs,
      anchor: switch (gAttr('textarea-vertical-align')) {
        'middle' => TextAnchor.center,
        'bottom' => TextAnchor.bottom,
        _ => TextAnchor.top,
      },
      insetL: odfLength(gAttr('padding-left')) ?? 7.2,
      insetR: odfLength(gAttr('padding-right')) ?? 7.2,
      insetT: odfLength(gAttr('padding-top')) ?? 3.6,
      insetB: odfLength(gAttr('padding-bottom')) ?? 3.6,
    );
  }

  TextAlign? _align(List<XmlElement> props) {
    TextAlign? a;
    for (final p in props) {
      a = switch (p.attr('text-align')) {
        'center' => TextAlign.center,
        'end' || 'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        'start' || 'left' => TextAlign.left,
        _ => a,
      };
    }
    return a;
  }

  void _paragraphs(XmlElement parent, _RunStyle base, TextAlign? baseAlign,
      List<SlideParagraph> out, {required int level, bool bulletFirst = false}) {
    var first = bulletFirst;
    for (final el in parent.childElements) {
      if (el.localName == 'list') {
        for (final item in el.kids('list-item')) {
          _paragraphs(item, base, baseAlign, out, level: level + 1, bulletFirst: true);
        }
      } else if (el.localName == 'p' || el.localName == 'h') {
        final ps = el.attr('style-name');
        final rs = base.copy();
        for (final p in styles.props('paragraph', ps, 'text-properties')) {
          rs.apply(p);
        }
        final pprops = styles.props('paragraph', ps, 'paragraph-properties');
        var marginLeft = 0.0, indent = 0.0, before = 0.0, after = 0.0;
        for (final p in pprops) {
          marginLeft = odfLength(p.attr('margin-left')) ?? marginLeft;
          indent = odfLength(p.attr('text-indent')) ?? indent;
          before = odfLength(p.attr('margin-top')) ?? before;
          after = odfLength(p.attr('margin-bottom')) ?? after;
        }
        final runs = <SlideRun>[];
        _runs(el, rs, runs);
        final hasText = runs.any((r) => r.text.trim().isNotEmpty);
        if (level >= 0 && marginLeft == 0) {
          marginLeft = 18.0 * (level + 1);
          indent = -14;
        }
        out.add(SlideParagraph(
          runs: runs,
          align: _align(pprops) ?? baseAlign ?? TextAlign.left,
          marginLeft: marginLeft,
          indent: indent,
          bullet: first && level >= 0 && hasText ? bulletForLevel(level) : null,
          spaceBefore: before,
          spaceAfter: after,
          emptySize: rs.size,
        ));
        first = false;
      }
    }
  }

  void _runs(XmlElement parent, _RunStyle style, List<SlideRun> out) {
    for (final n in parent.children) {
      if (n is XmlText) {
        final t = n.value.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) out.add(style.run(t));
      } else if (n is XmlElement) {
        switch (n.localName) {
          case 'span':
            final s = style.copy();
            for (final p in styles.props('text', n.attr('style-name'), 'text-properties')) {
              s.apply(p);
            }
            _runs(n, s, out);
          case 's':
            out.add(style.run(' ' * (int.tryParse(n.attr('c') ?? '') ?? 1)));
          case 'tab':
            out.add(style.run('\t'));
          case 'line-break':
            out.add(style.run('\n'));
          default:
            _runs(n, style, out);
        }
      }
    }
  }

  SlideTable _table(XmlElement table, Rect rect) {
    final widths = <double>[];
    for (final c in table.descendantElements.where((e) => e.localName == 'table-column')) {
      final rep = int.tryParse(c.attr('number-columns-repeated') ?? '') ?? 1;
      final props =
          styles.props('table-column', c.attr('style-name'), 'table-column-properties');
      final w = props.isEmpty ? null : odfLength(props.last.attr('column-width'));
      for (var i = 0; i < rep && widths.length < 64; i++) {
        widths.add(w ?? 0);
      }
    }
    final rows = <List<SlideTableCell>>[];
    final heights = <double>[];
    for (final tr in table.descendantElements.where((e) => e.localName == 'table-row')) {
      final props = styles.props('table-row', tr.attr('style-name'), 'table-row-properties');
      heights.add(props.isEmpty ? 0 : odfLength(props.last.attr('row-height')) ?? 0);
      final cells = <SlideTableCell>[];
      for (final tc in tr.childElements) {
        if (tc.localName == 'covered-table-cell') {
          cells.add(SlideTableCell(SlideText(paragraphs: []), merged: true));
          continue;
        }
        if (tc.localName != 'table-cell') continue;
        Color? fill;
        for (final p in styles.props('table-cell', tc.attr('style-name'), 'graphic-properties')) {
          if (p.attr('fill') == 'solid') fill = parseHexColor(p.attr('fill-color'));
        }
        for (final p in styles.props('table-cell', tc.attr('style-name'), 'table-cell-properties')) {
          fill = parseHexColor(p.attr('background-color')) ?? fill;
        }
        final paras = <SlideParagraph>[];
        _paragraphs(tc, _RunStyle(), null, paras, level: -1);
        cells.add(SlideTableCell(
          SlideText(paragraphs: paras),
          fill: fill,
          colSpan: int.tryParse(tc.attr('number-columns-spanned') ?? '') ?? 1,
          rowSpan: int.tryParse(tc.attr('number-rows-spanned') ?? '') ?? 1,
          border: const Color(0xFF999999),
        ));
      }
      rows.add(cells);
    }
    if (widths.isEmpty || widths.every((w) => w == 0)) {
      final n = rows.fold<int>(0, (m, r) => math.max(m, r.length));
      widths
        ..clear()
        ..addAll(List.filled(n, n == 0 ? 0 : rect.width / n));
    }
    return SlideTable(widths, heights, rows);
  }
}

class _RunStyle {
  bool bold = false, italic = false, underline = false, strike = false;
  double size = 18;
  Color color = kBlack;
  String? font;
  double baseline = 0;

  _RunStyle copy() => _RunStyle()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..size = size
    ..color = color
    ..font = font
    ..baseline = baseline;

  void apply(XmlElement p) {
    final w = p.attrNs('fo', 'font-weight');
    if (w != null) bold = w == 'bold' || (int.tryParse(w) ?? 400) >= 600;
    final st = p.attrNs('fo', 'font-style');
    if (st != null) italic = st == 'italic';
    final u = p.attr('text-underline-style');
    if (u != null) underline = u != 'none';
    final lt = p.attr('text-line-through-style');
    if (lt != null) strike = lt != 'none';
    final fs = p.attrNs('fo', 'font-size');
    if (fs != null) {
      if (fs.endsWith('%')) {
        size = size * (double.tryParse(fs.replaceAll('%', '')) ?? 100) / 100;
      } else {
        size = odfLength(fs) ?? size;
      }
    }
    color = parseHexColor(p.attrNs('fo', 'color')) ?? color;
    font = p.attr('font-name') ?? font;
    final pos = p.attr('text-position');
    if (pos != null) baseline = pos.startsWith('super') ? 30 : (pos.startsWith('sub') ? -25 : 0);
  }

  SlideRun run(String t) => SlideRun(t,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      size: size,
      color: color,
      font: font,
      baseline: baseline);
}
