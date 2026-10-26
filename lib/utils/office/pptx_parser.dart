import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'chart_parser.dart';
import 'office_common.dart';
import 'slide_model.dart';

/// Parser PPTX dengan posisi absolut: placeholder mewarisi posisi & style
/// dari layout → master, warna tema + clrMap, background, grup, tabel,
/// SmartArt (drawing fallback), custom geometry, dan speaker notes.
SlideDeck parsePptx(Uint8List data) => _PptxParser(OfficePackage(data)).parse();

class _Part {
  final String path;
  final XmlDocument doc;
  final Map<String, String> rels;
  _Part(this.path, this.doc, this.rels);

  XmlElement? get spTree => doc.first('cSld')?.child('spTree');

  String? relPath(String contains) {
    for (final p in rels.values) {
      if (p.contains(contains)) return p;
    }
    return null;
  }
}

class _Master {
  final _Part part;
  final Map<String, Color> scheme;
  final Map<String, String> clrMap;
  final XmlElement? titleStyle, bodyStyle, otherStyle;
  final String? majorFont, minorFont;
  _Master(this.part, this.scheme, this.clrMap, this.titleStyle, this.bodyStyle,
      this.otherStyle, {this.majorFont, this.minorFont});
}

/// Konteks warna & style untuk satu slide.
class _Ctx {
  final _Master master;
  final _Part? layout;
  final Map<String, String> clrMap;
  final XmlElement? defaultTextStyle;
  _Ctx(this.master, this.layout, this.clrMap, this.defaultTextStyle);

  Color? scheme(String name) {
    final mapped = clrMap[name] ?? name;
    return master.scheme[mapped];
  }

  /// Warna dari elemen warna DrawingML (srgbClr/schemeClr/sysClr/prstClr).
  Color? colorOf(XmlElement? c, {Color? phClr}) {
    if (c == null) return null;
    Color? base;
    switch (c.localName) {
      case 'srgbClr':
        base = parseHexColor(c.attr('val'));
      case 'schemeClr':
        final v = c.attr('val') ?? '';
        base = v == 'phClr' ? phClr : scheme(v);
      case 'sysClr':
        base = sysColor(c);
      case 'prstClr':
        base = _presetColors[c.attr('val')];
      case 'scrgbClr':
        int ch(String a) => ((int.tryParse(c.attr(a) ?? '') ?? 0) / 100000 * 255).round();
        base = Color.fromARGB(255, ch('r'), ch('g'), ch('b'));
      case 'hslClr':
        final h = (int.tryParse(c.attr('hue') ?? '') ?? 0) / 60000;
        final s = (int.tryParse(c.attr('sat') ?? '') ?? 0) / 100000;
        final l = (int.tryParse(c.attr('lum') ?? '') ?? 0) / 100000;
        base = HSLColor.fromAHSL(1, h % 360, s.clamp(0, 1), l.clamp(0, 1)).toColor();
      default:
        return null;
    }
    return base == null ? null : applyColorMods(base, c);
  }

  /// Warna pertama di dalam container (mis. `<a:solidFill>`).
  Color? colorIn(XmlElement? container, {Color? phClr}) {
    if (container == null) return null;
    for (final e in container.childElements) {
      final c = colorOf(e, phClr: phClr);
      if (c != null) return c;
    }
    return null;
  }
}

class _Fill {
  final bool specified;
  final Color? color;
  final Uint8List? image;
  const _Fill(this.specified, [this.color, this.image]);
  static const none = _Fill(false);
}

class _Xform {
  final double offX, offY, sx, sy;
  const _Xform([this.offX = 0, this.offY = 0, this.sx = 1, this.sy = 1]);
  Rect map(Rect r) =>
      Rect.fromLTWH(offX + r.left * sx, offY + r.top * sy, r.width * sx, r.height * sy);
}

class _Geo {
  final Rect rect;
  final double rot;
  final bool flipH, flipV;
  _Geo(this.rect, this.rot, this.flipH, this.flipV);
}

class _PptxParser {
  final OfficePackage pkg;
  final Map<String, _Master> _masters = {};
  final Map<String, _Part?> _parts = {};
  XmlElement? _defaultTextStyle;
  double _slideW = 720, _slideH = 405;

  _PptxParser(this.pkg);

  /// Posisi cadangan jika shape tidak punya posisi di slide/layout/master:
  /// isinya tetap ditampilkan (area judul atau area isi standar) daripada hilang.
  _Geo _fallbackGeo(String? phType) {
    final title = phType == 'title' || phType == 'ctrTitle';
    return _Geo(
      title
          ? Rect.fromLTWH(_slideW * 0.05, _slideH * 0.04, _slideW * 0.9, _slideH * 0.18)
          : Rect.fromLTWH(_slideW * 0.05, _slideH * 0.25, _slideW * 0.9, _slideH * 0.68),
      0,
      false,
      false,
    );
  }

  _Part? _tryPart(String? path) {
    if (path == null) return null;
    if (_parts.containsKey(path)) return _parts[path];
    final doc = pkg.xml(path);
    return _parts[path] = doc == null ? null : _Part(path, doc, pkg.rels(path));
  }

  SlideDeck parse() {
    const presPath = 'ppt/presentation.xml';
    final pres = pkg.xml(presPath);
    if (pres == null) throw const FormatException('Not a valid PowerPoint file');
    final presRels = pkg.rels(presPath);
    final sz = pres.first('sldSz');
    final w = sz == null ? 720.0 : emuToPt(sz.attr('cx'));
    final h = sz == null ? 405.0 : emuToPt(sz.attr('cy'));
    _slideW = w;
    _slideH = h;
    _defaultTextStyle = pres.first('defaultTextStyle');

    final slides = <SlideData>[];
    for (final id in pres.descendantElements.where((e) => e.localName == 'sldId')) {
      final path = presRels[id.attrNs('r', 'id')];
      final slide = _tryPart(path);
      if (slide == null) continue;
      slides.add(_slide(slide, w, h, hidden: slide.doc.rootElement.attr('show') == '0'));
    }
    return SlideDeck(w, h, slides);
  }

  _Master _master(_Part part) => _masters.putIfAbsent(part.path, () {
        final themeDoc = pkg.xml(part.relPath('/theme/') ?? '');
        final scheme = <String, Color>{};
        final cs = themeDoc?.first('clrScheme');
        if (cs != null) {
          for (final e in cs.childElements) {
            final c = e.childElements.firstOrNull;
            if (c == null) continue;
            final color =
                c.localName == 'sysClr' ? sysColor(c) : parseHexColor(c.attr('val'));
            if (color != null) scheme[e.localName] = color;
          }
        }
        final clrMap = <String, String>{};
        final cm = part.doc.first('clrMap');
        for (final a in cm?.attributes ?? <XmlAttribute>[]) {
          clrMap[a.name.local] = a.value;
        }
        final tx = part.doc.first('txStyles');
        return _Master(part, scheme, clrMap, tx?.child('titleStyle'),
            tx?.child('bodyStyle'), tx?.child('otherStyle'),
            majorFont: themeDoc?.first('majorFont')?.child('latin')?.attr('typeface'),
            minorFont: themeDoc?.first('minorFont')?.child('latin')?.attr('typeface'));
      });

  SlideData _slide(_Part slide, double w, double h, {bool hidden = false}) {
    final layout = _tryPart(slide.relPath('/slideLayouts/'));
    final masterPart = _tryPart(layout?.relPath('/slideMasters/'));
    final master = masterPart != null
        ? _master(masterPart)
        : _Master(slide, {}, {}, null, null, null);

    // clrMap override pada layout/slide
    final clrMap = Map<String, String>.from(master.clrMap);
    for (final p in [layout, slide]) {
      final ov = p?.doc.first('overrideClrMapping');
      for (final a in ov?.attributes ?? <XmlAttribute>[]) {
        clrMap[a.name.local] = a.value;
      }
    }
    final ctx = _Ctx(master, layout, clrMap, _defaultTextStyle);

    final (bg, bgImage) = _background([slide, if (layout != null) layout, master.part], ctx);

    final shapes = <SlideShape>[];
    final showMaster = slide.doc.rootElement.attr('showMasterSp') != '0';
    final layoutShowsMaster = layout?.doc.rootElement.attr('showMasterSp') != '0';
    if (showMaster) {
      if (masterPart != null && layoutShowsMaster && master.part.spTree != null) {
        _shapes(master.part.spTree!, master.part, ctx, const _Xform(), shapes,
            template: true);
      }
      if (layout?.spTree != null) {
        _shapes(layout!.spTree!, layout, ctx, const _Xform(), shapes, template: true);
      }
    }
    if (slide.spTree != null) {
      _shapes(slide.spTree!, slide, ctx, const _Xform(), shapes, template: false);
    }

    return SlideData(
      background: bg,
      backgroundImage: bgImage,
      shapes: shapes,
      notes: _notes(slide),
      hidden: hidden,
    );
  }

  String _notes(_Part slide) {
    final notes = _tryPart(slide.relPath('/notesSlides/'));
    if (notes == null) return '';
    final out = <String>[];
    for (final sp in notes.doc.descendantElements.where((e) => e.localName == 'sp')) {
      final ph = sp.descendant('ph');
      if (ph?.attr('type') != 'body') continue;
      for (final p in sp.descendantElements.where((e) => e.localName == 'p')) {
        out.add(p.descendantElements
            .where((e) => e.localName == 't')
            .map((e) => e.innerText)
            .join());
      }
    }
    return out.join('\n').trim();
  }

  (Color, Uint8List?) _background(List<_Part> chain, _Ctx ctx) {
    for (final part in chain) {
      final bg = part.doc.first('cSld')?.child('bg');
      if (bg == null) continue;
      final bgPr = bg.child('bgPr');
      if (bgPr != null) {
        final f = _fill(bgPr, part, ctx);
        if (f.image != null) return (f.color ?? kWhite, f.image);
        if (f.color != null) return (f.color!, null);
        if (f.specified) return (kWhite, null);
      }
      final ref = bg.child('bgRef');
      if (ref != null) {
        final c = ctx.colorIn(ref);
        if (c != null) return (c, null);
      }
    }
    return (ctx.scheme('bg1') ?? kWhite, null);
  }

  /// Isi shape dari spPr: solid / gradient (warna tengah) / gambar / none.
  _Fill _fill(XmlElement? spPr, _Part part, _Ctx ctx, {Color? phClr}) {
    if (spPr == null) return _Fill.none;
    for (final e in spPr.childElements) {
      switch (e.localName) {
        case 'noFill':
          return const _Fill(true);
        case 'solidFill':
          return _Fill(true, ctx.colorIn(e, phClr: phClr));
        case 'gradFill':
          final stops = e.descendantElements.where((x) => x.localName == 'gs').toList();
          if (stops.isEmpty) return const _Fill(true);
          final a = ctx.colorIn(stops.first, phClr: phClr);
          final b = ctx.colorIn(stops.last, phClr: phClr);
          return _Fill(true, a != null && b != null ? Color.lerp(a, b, 0.5) : a ?? b);
        case 'blipFill':
          final id = e.descendant('blip')?.attr('embed');
          final path = part.rels[id];
          if (path != null && isRenderableImage(path)) {
            return _Fill(true, null, pkg.bytes(path));
          }
          return const _Fill(true);
        case 'pattFill':
          return _Fill(true, ctx.colorIn(e.child('fgClr'), phClr: phClr));
        case 'grpFill':
          return _Fill.none;
      }
    }
    return _Fill.none;
  }

  _Geo? _geo(XmlElement? xfrm, _Xform xf) {
    if (xfrm == null) return null;
    final off = xfrm.child('off');
    final ext = xfrm.child('ext');
    if (off == null || ext == null) return null;
    final r = Rect.fromLTWH(emuToPt(off.attr('x')), emuToPt(off.attr('y')),
        emuToPt(ext.attr('cx')), emuToPt(ext.attr('cy')));
    return _Geo(
      xf.map(r),
      (double.tryParse(xfrm.attr('rot') ?? '') ?? 0) / 60000,
      xfrm.attr('flipH') == '1',
      xfrm.attr('flipV') == '1',
    );
  }

  // ── Placeholder ───────────────────────────────────────────────────────────

  static String _phKind(String? type) => switch (type) {
        'title' || 'ctrTitle' => 'title',
        'dt' || 'ftr' || 'sldNum' || 'hdr' => type!,
        'pic' || 'chart' || 'tbl' || 'clipArt' || 'dgm' || 'media' => 'body',
        _ => 'body',
      };

  /// Cari placeholder pasangan di layout/master: utamakan idx, lalu jenis.
  XmlElement? _findPh(_Part? part, String? type, String? idx) {
    final tree = part?.spTree;
    if (tree == null) return null;
    XmlElement? byType;
    for (final sp in tree.descendantElements
        .where((e) => e.localName == 'sp' || e.localName == 'pic')) {
      final ph = sp.child('nvSpPr')?.child('nvPr')?.child('ph') ??
          sp.child('nvPicPr')?.child('nvPr')?.child('ph');
      if (ph == null) continue;
      if (idx != null && ph.attr('idx') == idx) return sp;
      if (byType == null && _phKind(ph.attr('type')) == _phKind(type)) byType = sp;
    }
    return byType;
  }

  // ── Shape tree ────────────────────────────────────────────────────────────

  void _shapes(XmlElement tree, _Part part, _Ctx ctx, _Xform xf,
      List<SlideShape> out, {required bool template}) {
    for (final el in tree.childElements) {
      switch (el.localName) {
        case 'sp':
        case 'cxnSp':
          _sp(el, part, ctx, xf, out, template: template);
        case 'pic':
          _pic(el, part, ctx, xf, out, template: template);
        case 'grpSp':
          final gx = el.child('grpSpPr')?.child('xfrm');
          final off = gx?.child('off');
          final ext = gx?.child('ext');
          final chOff = gx?.child('chOff');
          final chExt = gx?.child('chExt');
          var child = xf;
          if (off != null && ext != null && chOff != null && chExt != null) {
            final cx = emuToPt(chExt.attr('cx'));
            final cy = emuToPt(chExt.attr('cy'));
            final kx = cx == 0 ? 1.0 : emuToPt(ext.attr('cx')) / cx;
            final ky = cy == 0 ? 1.0 : emuToPt(ext.attr('cy')) / cy;
            child = _Xform(
              xf.offX + xf.sx * (emuToPt(off.attr('x')) - emuToPt(chOff.attr('x')) * kx),
              xf.offY + xf.sy * (emuToPt(off.attr('y')) - emuToPt(chOff.attr('y')) * ky),
              xf.sx * kx,
              xf.sy * ky,
            );
          }
          _shapes(el, part, ctx, child, out, template: template);
        case 'graphicFrame':
          _graphicFrame(el, part, ctx, xf, out);
        case 'AlternateContent':
          // Fallback biasanya berupa gambar yang bisa dirender (mis. rumus)
          final alt = el.child('Fallback') ?? el.child('Choice');
          if (alt != null) _shapes(alt, part, ctx, xf, out, template: template);
      }
    }
  }

  void _sp(XmlElement sp, _Part part, _Ctx ctx, _Xform xf, List<SlideShape> out,
      {required bool template}) {
    final nvPr = (sp.child('nvSpPr') ?? sp.child('nvCxnSpPr'))?.child('nvPr');
    final ph = nvPr?.child('ph');
    if (template && ph != null) return; // placeholder template tidak ditampilkan

    final phType = ph?.attr('type');
    final phIdx = ph?.attr('idx');
    XmlElement? layoutPh, masterPh;
    if (ph != null) {
      layoutPh = _findPh(ctx.layout, phType, phIdx);
      final masterType = layoutPh?.descendant('ph')?.attr('type') ?? phType;
      masterPh = _findPh(ctx.master.part, masterType, null);
    }

    final spPr = sp.child('spPr');
    final geo = _geo(spPr?.child('xfrm'), xf) ??
        _geo(layoutPh?.child('spPr')?.child('xfrm'), const _Xform()) ??
        _geo(masterPh?.child('spPr')?.child('xfrm'), const _Xform()) ??
        (sp.descendantElements.any((e) => e.localName == 't' && e.innerText.trim().isNotEmpty)
            ? _fallbackGeo(phType)
            : null);
    if (geo == null) return;

    final style = sp.child('style');
    var fill = _fill(spPr, part, ctx);
    if (!fill.specified && ph != null) {
      fill = _fill(layoutPh?.child('spPr'), ctx.layout ?? part, ctx);
      if (!fill.specified) fill = _fill(masterPh?.child('spPr'), ctx.master.part, ctx);
    }
    Color? fillColor = fill.color;
    if (!fill.specified && style != null) {
      final ref = style.child('fillRef');
      if ((int.tryParse(ref?.attr('idx') ?? '') ?? 0) > 0) fillColor = ctx.colorIn(ref);
    }

    final (lineColor, lineWidth) = _line(spPr, style, ctx);

    final prst = spPr?.child('prstGeom')?.attr('prst');
    final isConnector = sp.localName == 'cxnSp';
    var geom = _geomFor(prst, isConnector);
    final path = <PathCmd>[];
    final cust = spPr?.child('custGeom');
    if (cust != null) {
      geom = ShapeGeom.path;
      path.addAll(_customPath(cust));
    }

    final fontRef = ctx.colorIn(style?.child('fontRef'));
    final kind = ph == null ? null : _phKind(phType);
    final lstStyles = <XmlElement?>[
      sp.child('txBody')?.child('lstStyle'),
      layoutPh?.child('txBody')?.child('lstStyle'),
      masterPh?.child('txBody')?.child('lstStyle'),
      if (kind == 'title') ctx.master.titleStyle,
      if (kind == 'body') ctx.master.bodyStyle,
      if (kind == null || (kind != 'title' && kind != 'body')) ctx.master.otherStyle,
      if (kind == null) ctx.defaultTextStyle,
    ];
    final bodyPrs = [
      sp.child('txBody')?.child('bodyPr'),
      layoutPh?.child('txBody')?.child('bodyPr'),
      masterPh?.child('txBody')?.child('bodyPr'),
    ];
    final text = _text(sp.child('txBody'), lstStyles, bodyPrs, ctx, fontRef);

    // Placeholder kosong (mis. "Click to add title") tidak tampil saat presentasi
    final hasVisual = fillColor != null || fill.image != null || lineColor != null;
    if (ph != null && (text == null || text.isEmpty) && !hasVisual) return;
    if (!hasVisual && (text == null || text.isEmpty)) return;

    out.add(SlideShape(
      rect: geo.rect,
      rotation: geo.rot,
      flipH: geo.flipH,
      flipV: geo.flipV,
      geom: geom,
      fill: fill.image != null ? null : fillColor,
      image: fill.image,
      lineColor: lineColor,
      lineWidth: lineWidth,
      text: text,
      path: path,
    ));
  }

  (Color?, double) _line(XmlElement? spPr, XmlElement? style, _Ctx ctx) {
    final ln = spPr?.child('ln');
    var width = ln?.attr('w') != null ? emuToPt(ln!.attr('w')) : 0.75;
    if (width <= 0) width = 0.75;
    if (ln != null) {
      if (ln.child('noFill') != null) return (null, 0);
      final c = ctx.colorIn(ln.child('solidFill')) ??
          ctx.colorIn(ln.child('gradFill')?.descendant('gs'));
      if (c != null) return (c, width);
    }
    final ref = style?.child('lnRef');
    if (ref != null && (int.tryParse(ref.attr('idx') ?? '') ?? 0) > 0) {
      return (ctx.colorIn(ref), width);
    }
    return (null, 0);
  }

  static ShapeGeom _geomFor(String? prst, bool connector) {
    if (connector) return ShapeGeom.line;
    if (prst == null) return ShapeGeom.rect;
    if (prst == 'line' || prst.contains('Connector')) return ShapeGeom.line;
    if (prst == 'ellipse' || prst == 'pie' || prst == 'donut' || prst == 'chord') {
      return ShapeGeom.ellipse;
    }
    if (prst.startsWith('round') || prst.startsWith('snip') || prst == 'flowChartAlternateProcess') {
      return ShapeGeom.roundRect;
    }
    if (prst == 'triangle' || prst == 'flowChartExtract') return ShapeGeom.triangle;
    if (prst == 'diamond' || prst == 'flowChartDecision') return ShapeGeom.diamond;
    return ShapeGeom.rect;
  }

  List<PathCmd> _customPath(XmlElement cust) {
    final out = <PathCmd>[];
    for (final p in cust.descendantElements.where((e) => e.localName == 'path')) {
      final pw = double.tryParse(p.attr('w') ?? '') ?? 0;
      final ph = double.tryParse(p.attr('h') ?? '') ?? 0;
      if (pw <= 0 || ph <= 0) continue;
      Offset pt(XmlElement e) => Offset(
          (double.tryParse(e.attr('x') ?? '') ?? 0) / pw,
          (double.tryParse(e.attr('y') ?? '') ?? 0) / ph);
      for (final c in p.childElements) {
        final pts = c.kids('pt').map(pt).toList();
        switch (c.localName) {
          case 'moveTo':
            out.add(PathCmd('M', pts));
          case 'lnTo':
            out.add(PathCmd('L', pts));
          case 'cubicBezTo':
            out.add(PathCmd('C', pts));
          case 'quadBezTo':
            out.add(PathCmd('Q', pts));
          case 'close':
            out.add(const PathCmd('Z', []));
        }
      }
    }
    return out;
  }

  void _pic(XmlElement pic, _Part part, _Ctx ctx, _Xform xf, List<SlideShape> out,
      {required bool template}) {
    final ph = pic.child('nvPicPr')?.child('nvPr')?.child('ph');
    final spPr = pic.child('spPr');
    var geo = _geo(spPr?.child('xfrm'), xf);
    if (geo == null && ph != null) {
      final lp = _findPh(ctx.layout, ph.attr('type'), ph.attr('idx'));
      geo = _geo(lp?.child('spPr')?.child('xfrm'), const _Xform());
    }
    geo ??= _fallbackGeo(ph?.attr('type'));

    final blip = pic.child('blipFill')?.child('blip');
    final id = blip?.attr('embed') ?? blip?.attr('link');
    final path = part.rels[id];
    final ok = path != null && isRenderableImage(path);
    final (lineColor, lineWidth) = _line(spPr, pic.child('style'), ctx);
    out.add(SlideShape(
      rect: geo.rect,
      rotation: geo.rot,
      flipH: geo.flipH,
      flipV: geo.flipV,
      geom: _geomFor(spPr?.child('prstGeom')?.attr('prst'), false),
      image: ok ? pkg.bytes(path) : null,
      imageUnsupported: path != null && !ok,
      lineColor: lineColor,
      lineWidth: lineWidth,
    ));
  }

  void _graphicFrame(XmlElement gf, _Part part, _Ctx ctx, _Xform xf, List<SlideShape> out) {
    final geo = _geo(gf.child('xfrm'), xf) ?? _fallbackGeo(null);
    final data = gf.descendant('graphicData');
    final uri = data?.attr('uri') ?? '';

    final tbl = data?.child('tbl');
    if (tbl != null) {
      out.add(SlideShape(rect: geo.rect, table: _table(tbl, part, ctx)));
      return;
    }

    if (uri.endsWith('/diagram')) {
      // SmartArt: PowerPoint menyimpan hasil render di diagrams/drawingN.xml
      final relIds = data?.child('relIds');
      final dm = _tryPart(part.rels[relIds?.attr('dm')]);
      final extId = dm?.doc.first('dataModelExt')?.attr('relId');
      final drawing = _tryPart(part.rels[extId]);
      final tree = drawing?.doc.first('spTree');
      if (drawing != null && tree != null) {
        // Koordinat drawing relatif terhadap frame
        final frameOff = gf.child('xfrm')?.child('off');
        final ox = emuToPt(frameOff?.attr('x'));
        final oy = emuToPt(frameOff?.attr('y'));
        final dx = _Xform(xf.offX + xf.sx * ox, xf.offY + xf.sy * oy, xf.sx, xf.sy);
        _shapes(tree, drawing, ctx, dx, out, template: false);
      }
      return;
    }

    if (uri.endsWith('/chart')) {
      final chartDoc = _tryPart(part.rels[data?.child('chart')?.attrNs('r', 'id')])?.doc;
      // Warna tema + alias clrMap (tx1 → dk1, …) untuk seri chart
      final scheme = {
        ...ctx.master.scheme,
        for (final k in ['tx1', 'bg1', 'tx2', 'bg2'])
          if (ctx.scheme(k) != null) k: ctx.scheme(k)!,
      };
      ChartData? chart;
      try {
        chart = chartDoc == null ? null : parseOoxmlChart(chartDoc, scheme);
      } catch (_) {}
      out.add(SlideShape(rect: geo.rect, isChart: chart == null, chart: chart));
      return;
    }

    // OLE object: biasanya punya gambar pratinjau
    final pic = gf.descendant('pic');
    if (pic != null) {
      final id = pic.descendant('blip')?.attr('embed');
      final path = part.rels[id];
      if (path != null) {
        final ok = isRenderableImage(path);
        out.add(SlideShape(
            rect: geo.rect, image: ok ? pkg.bytes(path) : null, imageUnsupported: !ok));
      }
    }
  }

  SlideTable _table(XmlElement tbl, _Part part, _Ctx ctx) {
    final widths = tbl
            .child('tblGrid')
            ?.kids('gridCol')
            .map((g) => emuToPt(g.attr('w')))
            .toList() ??
        <double>[];
    final tblPr = tbl.child('tblPr');
    final firstRow = tblPr?.attr('firstRow') == '1';
    final bandRow = tblPr?.attr('bandRow') == '1';
    final accent = ctx.scheme('accent1') ?? const Color(0xFF4472C4);
    final dark = ctx.scheme('tx1') ?? kBlack;

    final heights = <double>[];
    final rows = <List<SlideTableCell>>[];
    var ri = 0;
    for (final tr in tbl.kids('tr')) {
      heights.add(emuToPt(tr.attr('h')));
      final isHeader = firstRow && ri == 0;
      final cells = <SlideTableCell>[];
      for (final tc in tr.kids('tc')) {
        final tcPr = tc.child('tcPr');
        var f = _fill(tcPr, part, ctx);
        Color? fill = f.color;
        if (!f.specified) {
          // Perkiraan style tabel default "Medium Style 2 – Accent 1"
          if (isHeader) {
            fill = accent;
          } else if (bandRow) {
            fill = ri.isOdd
                ? Color.lerp(accent, kWhite, 0.80)
                : Color.lerp(accent, kWhite, 0.90);
          }
        }
        final textColor = isHeader && !f.specified ? kWhite : dark;
        final text = _text(tc.child('txBody'), [tbl.descendant('lstStyle'), ctx.master.otherStyle],
                [tcPr], ctx, textColor, boldDefault: isHeader) ??
            SlideText(paragraphs: []);
        Color? border;
        final lnB = tcPr?.child('lnB') ?? tcPr?.child('lnT');
        if (lnB != null && lnB.child('noFill') == null) border = ctx.colorIn(lnB.child('solidFill'));
        cells.add(SlideTableCell(
          SlideText(
            paragraphs: text.paragraphs,
            anchor: switch (tcPr?.attr('anchor')) {
              'ctr' => TextAnchor.center,
              'b' => TextAnchor.bottom,
              _ => TextAnchor.top,
            },
            insetL: tcPr?.attr('marL') != null ? emuToPt(tcPr!.attr('marL')) : 7.2,
            insetR: tcPr?.attr('marR') != null ? emuToPt(tcPr!.attr('marR')) : 7.2,
            insetT: tcPr?.attr('marT') != null ? emuToPt(tcPr!.attr('marT')) : 3.6,
            insetB: tcPr?.attr('marB') != null ? emuToPt(tcPr!.attr('marB')) : 3.6,
          ),
          fill: fill,
          colSpan: int.tryParse(tc.attr('gridSpan') ?? '') ?? 1,
          rowSpan: int.tryParse(tc.attr('rowSpan') ?? '') ?? 1,
          merged: tc.attr('hMerge') == '1' || tc.attr('vMerge') == '1',
          border: border ?? kWhite,
        ));
      }
      rows.add(cells);
      ri++;
    }
    return SlideTable(widths, heights, rows);
  }

  // ── Teks ──────────────────────────────────────────────────────────────────

  SlideText? _text(XmlElement? txBody, List<XmlElement?> lstStyles,
      List<XmlElement?> bodyPrs, _Ctx ctx, Color? fontRefColor,
      {bool boldDefault = false}) {
    if (txBody == null) return null;
    String? bAttr(String name) {
      for (final b in bodyPrs) {
        final v = b?.attr(name);
        if (v != null) return v;
      }
      return null;
    }

    double inset(String name, double def) {
      final v = bAttr(name);
      return v == null ? def : emuToPt(v);
    }

    var fontScale = 1.0;
    var lnReduction = 0.0;
    for (final b in bodyPrs) {
      final na = b?.child('normAutofit');
      if (na != null) {
        fontScale = (int.tryParse(na.attr('fontScale') ?? '') ?? 100000) / 100000;
        lnReduction = (int.tryParse(na.attr('lnSpcReduction') ?? '') ?? 0) / 100000;
        break;
      }
    }

    final counters = List.filled(9, 0);
    String? lastNumType;
    final paragraphs = <SlideParagraph>[];

    for (final p in txBody.kids('p')) {
      final pPr = p.child('pPr');
      final lvl = int.tryParse(pPr?.attr('lvl') ?? '') ?? 0;
      final cands = [
        for (final s in lstStyles) s?.child('lvl${lvl + 1}pPr'),
      ];
      final srcs = [pPr, ...cands];

      String? pAttr(String n) {
        for (final s in srcs) {
          final v = s?.attr(n);
          if (v != null) return v;
        }
        return null;
      }

      XmlElement? pChild(String n) {
        for (final s in srcs) {
          final v = s?.child(n);
          if (v != null) return v;
        }
        return null;
      }

      // Sumber properti run default: pPr/defRPr → lstStyle shape → fontRef → sisanya
      final defs = [for (final s in srcs) s?.child('defRPr')];

      double runSize(XmlElement? rPr) {
        final v = rPr?.attr('sz') ?? defs.map((d) => d?.attr('sz')).firstWhere((x) => x != null, orElse: () => null);
        return ((int.tryParse(v ?? '') ?? 1800) / 100) * fontScale;
      }

      Color runColor(XmlElement? rPr) {
        final direct = ctx.colorIn(rPr?.child('solidFill'));
        if (direct != null) return direct;
        for (var i = 0; i < defs.length; i++) {
          if (i == 2 && fontRefColor != null) return fontRefColor;
          final c = ctx.colorIn(defs[i]?.child('solidFill'));
          if (c != null) return c;
        }
        return fontRefColor ?? ctx.scheme('tx1') ?? kBlack;
      }

      bool? runFlag(XmlElement? rPr, String n) {
        final v = rPr?.attr(n) ??
            defs.map((d) => d?.attr(n)).firstWhere((x) => x != null, orElse: () => null);
        return v == null ? null : (v == '1' || v == 'true');
      }

      String? runAttr(XmlElement? rPr, String n) =>
          rPr?.attr(n) ??
          defs.map((d) => d?.attr(n)).firstWhere((x) => x != null, orElse: () => null);

      String? font(XmlElement? rPr) {
        final f = rPr?.child('latin')?.attr('typeface') ??
            defs.map((d) => d?.child('latin')?.attr('typeface')).firstWhere((x) => x != null, orElse: () => null);
        // +mj-lt / +mn-lt = font judul / isi dari tema
        if (f == null || f.startsWith('+mn')) return ctx.master.minorFont;
        if (f.startsWith('+mj')) return ctx.master.majorFont;
        return f;
      }

      final runs = <SlideRun>[];
      for (final r in p.childElements) {
        if (r.localName == 'r' || r.localName == 'fld') {
          final rPr = r.child('rPr');
          final t = r.child('t')?.innerText ?? '';
          if (t.isEmpty) continue;
          final u = runAttr(rPr, 'u');
          final st = runAttr(rPr, 'strike');
          runs.add(SlideRun(
            t,
            bold: runFlag(rPr, 'b') ?? boldDefault,
            italic: runFlag(rPr, 'i') ?? false,
            underline: u != null && u != 'none',
            strike: st != null && st != 'noStrike',
            size: runSize(rPr),
            color: runColor(rPr),
            font: font(rPr),
            baseline: (int.tryParse(runAttr(rPr, 'baseline') ?? '') ?? 0) / 1000,
            caps: runAttr(rPr, 'cap') == 'all',
          ));
        } else if (r.localName == 'br') {
          final rPr = r.child('rPr');
          runs.add(SlideRun('\n', size: runSize(rPr), color: runColor(rPr)));
        }
      }

      // Bullet: cari sumber pertama yang mendefinisikan jenis bullet
      String? bullet;
      String? numType;
      var numStart = 1;
      for (final s in srcs) {
        if (s == null) continue;
        if (s.child('buNone') != null) break;
        final ch = s.child('buChar');
        if (ch != null) {
          bullet = sanitizeBullet(ch.attr('char'), lvl,
              font: pChild('buFont')?.attr('typeface'));
          break;
        }
        final an = s.child('buAutoNum');
        if (an != null) {
          numType = an.attr('type') ?? 'arabicPeriod';
          numStart = int.tryParse(an.attr('startAt') ?? '') ?? 1;
          break;
        }
        if (s.child('buBlip') != null) {
          bullet = bulletForLevel(lvl);
          break;
        }
      }
      final hasText = runs.any((r) => r.text.trim().isNotEmpty);
      if (numType != null && hasText) {
        if (lastNumType != numType && counters[lvl] == 0) counters[lvl] = numStart - 1;
        counters[lvl]++;
        for (var i = lvl + 1; i < counters.length; i++) {
          counters[i] = 0;
        }
        bullet = _autoNum(numType, counters[lvl]);
        lastNumType = numType;
      }
      if (!hasText) bullet = null;

      final firstSize = runs.isNotEmpty ? runs.first.size : runSize(p.child('endParaRPr'));
      double? spacing(XmlElement? e) {
        if (e == null) return null;
        final pts = e.child('spcPts')?.attr('val');
        if (pts != null) return (int.tryParse(pts) ?? 0) / 100;
        final pct = e.child('spcPct')?.attr('val');
        if (pct != null) return (int.tryParse(pct) ?? 0) / 100000 * firstSize;
        return null;
      }

      double? lineSpacing;
      final ls = pChild('lnSpc');
      if (ls != null) {
        final pct = ls.child('spcPct')?.attr('val');
        final pts = ls.child('spcPts')?.attr('val');
        if (pct != null) lineSpacing = (int.tryParse(pct) ?? 100000) / 100000;
        if (pts != null) lineSpacing = ((int.tryParse(pts) ?? 0) / 100) / (firstSize * 1.2);
      }
      if (lnReduction > 0) lineSpacing = (lineSpacing ?? 1.0) * (1 - lnReduction);

      paragraphs.add(SlideParagraph(
        runs: runs,
        align: switch (pAttr('algn')) {
          'ctr' => TextAlign.center,
          'r' => TextAlign.right,
          'just' || 'dist' => TextAlign.justify,
          _ => TextAlign.left,
        },
        marginLeft: emuToPt(pAttr('marL')),
        indent: emuToPt(pAttr('indent')),
        bullet: bullet,
        bulletColor: ctx.colorIn(pChild('buClr')),
        spaceBefore: spacing(pChild('spcBef')) ?? 0,
        spaceAfter: spacing(pChild('spcAft')) ?? 0,
        lineSpacing: lineSpacing,
        emptySize: firstSize,
      ));
    }

    final vert = bAttr('vert');
    return SlideText(
      paragraphs: paragraphs,
      anchor: switch (bAttr('anchor')) {
        'ctr' => TextAnchor.center,
        'b' => TextAnchor.bottom,
        _ => TextAnchor.top,
      },
      insetL: inset('lIns', 7.2),
      insetT: inset('tIns', 3.6),
      insetR: inset('rIns', 7.2),
      insetB: inset('bIns', 3.6),
      wrap: bAttr('wrap') != 'none',
      quarterTurns: switch (vert) {
        'vert' || 'eaVert' || 'wordArtVertRtl' => 1,
        'vert270' => 3,
        _ => 0,
      },
    );
  }

  static String _autoNum(String type, int n) {
    final String num;
    if (type.startsWith('roman')) {
      num = type.contains('Uc') ? toRoman(n) : toRoman(n).toLowerCase();
    } else if (type.startsWith('alpha')) {
      num = type.contains('Uc') ? toLetters(n).toUpperCase() : toLetters(n);
    } else {
      num = '$n';
    }
    if (type.endsWith('ParenBoth')) return '($num)';
    if (type.endsWith('ParenR')) return '$num)';
    if (type.endsWith('Plain')) return num;
    if (type.endsWith('Minus')) return '- $num -';
    return '$num.';
  }
}

const _presetColors = {
  'black': Color(0xFF000000),
  'white': Color(0xFFFFFFFF),
  'red': Color(0xFFFF0000),
  'green': Color(0xFF008000),
  'blue': Color(0xFF0000FF),
  'yellow': Color(0xFFFFFF00),
  'gray': Color(0xFF808080),
  'grey': Color(0xFF808080),
  'orange': Color(0xFFFFA500),
  'purple': Color(0xFF800080),
  'darkBlue': Color(0xFF00008B),
  'darkRed': Color(0xFF8B0000),
  'darkGreen': Color(0xFF006400),
  'lightGray': Color(0xFFD3D3D3),
  'navy': Color(0xFF000080),
};
