import 'dart:typed_data';
import 'dart:ui';
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'chart_parser.dart';
import 'doc_model.dart';
import 'office_common.dart';

/// Parser DOCX: styles.xml (pewarisan style), numbering.xml (nomor list),
/// tabel, gambar, hyperlink, text box, dan tracked changes.
DocDocument parseDocx(Uint8List data) => _DocxParser(OfficePackage(data)).parse();

class _DocxParser {
  final OfficePackage pkg;
  late Map<String, String> _rels;
  bool _keepCellBreaks = false;

  // Footnote / endnote / komentar: XML sumber per id + hasil per label
  final Map<String, XmlElement> _noteXml = {}; // "footnote:3" → <w:footnote>
  final Map<String, String> _noteParts = {}; // "footnote" → path part
  final Map<String, List<DocBlock>> _footnotes = {};
  final List<DocNote> _endnotes = [];
  final List<DocNote> _comments = [];
  String? _noteLabel; // label catatan yang sedang diparse (untuk w:footnoteRef)
  bool _renderedBreaks = false;
  final _fieldSkip = <bool>[]; // stack field kompleks: lewati hasil cache?
  final _instr = StringBuffer();
  final Map<String, _Style> _styles = {};
  String? _defaultParaStyle;
  String? _defaultTableStyle;
  final _RunProps _defaultRun = _RunProps();
  final _ParaProps _defaultPara = _ParaProps();
  late final _Numbering _numbering;
  final Map<String, String> _linkTargets = {};
  String? _majorFont, _minorFont;
  Map<String, Color> _scheme = {};

  _DocxParser(this.pkg);

  /// `theme:major` / `theme:minor` (dari w:asciiTheme) → nama font di tema.
  String? _resolveFont(String? f) => switch (f) {
        'theme:major' => _majorFont,
        'theme:minor' => _minorFont,
        _ => f,
      };

  DocDocument parse() {
    var mainPart = 'word/document.xml';
    final ct = pkg.xml('[Content_Types].xml');
    if (ct != null) {
      for (final o in ct.descendantElements.where((e) => e.localName == 'Override')) {
        if ((o.attr('ContentType') ?? '').contains('wordprocessingml.document.main')) {
          mainPart = (o.attr('PartName') ?? '/$mainPart').substring(1);
        }
      }
    }
    final doc = pkg.xml(mainPart);
    if (doc == null) throw const FormatException('Not a valid Word document');
    _rels = pkg.rels(mainPart);
    _loadLinkTargets(mainPart);
    final theme = pkg.xml('word/theme/theme1.xml');
    _scheme = readThemeScheme(theme);
    _majorFont = theme?.first('majorFont')?.child('latin')?.attr('typeface');
    _minorFont = theme?.first('minorFont')?.child('latin')?.attr('typeface');
    _loadStyles();
    _numbering = _Numbering(pkg.xml('word/numbering.xml'));
    _loadNotes(mainPart);

    final body = doc.first('body');
    if (body == null) throw const FormatException('Document body not found');

    final sect = body.child('sectPr');
    final blocks = _blocks(body, topLevel: true);

    final pgSz = sect?.child('pgSz');
    final pgMar = sect?.child('pgMar');
    double tw(XmlElement? e, String a, double def) {
      final v = e?.attr(a);
      return v == null ? def : twipToPt(v).abs();
    }

    var page = const DocPageSetup();
    if (pgSz != null) {
      page = DocPageSetup(
        width: tw(pgSz, 'w', 595.3),
        height: tw(pgSz, 'h', 841.9),
        marginTop: tw(pgMar, 'top', 72),
        marginBottom: tw(pgMar, 'bottom', 72),
        marginLeft: tw(pgMar, 'left', tw(pgMar, 'start', 72)),
        marginRight: tw(pgMar, 'right', tw(pgMar, 'end', 72)),
        headerDistance: tw(pgMar, 'header', 35.4),
        footerDistance: tw(pgMar, 'footer', 35.4),
      );
      if (page.width - page.marginLeft - page.marginRight < 100) page = const DocPageSetup();
    }
    final titlePg = sect?.toggle('titlePg') ?? false;

    return DocDocument(
      blocks,
      page: page,
      header: _headerFooter(sect, 'header', 'default') ?? const [],
      footer: _headerFooter(sect, 'footer', 'default') ?? const [],
      firstHeader: titlePg ? _headerFooter(sect, 'header', 'first') ?? const [] : null,
      firstFooter: titlePg ? _headerFooter(sect, 'footer', 'first') ?? const [] : null,
      hasRenderedBreaks: _renderedBreaks,
      footnotes: _footnotes,
      endnotes: _endnotes,
      comments: _comments,
    );
  }

  void _loadNotes(String mainPart) {
    final relDoc = pkg.xml(
        '${mainPart.substring(0, mainPart.lastIndexOf('/'))}/_rels/${mainPart.split('/').last}.rels');
    for (final r in relDoc?.descendantElements.where((e) => e.localName == 'Relationship') ??
        const Iterable<XmlElement>.empty()) {
      final type = (r.getAttribute('Type') ?? '').split('/').last;
      if (type != 'footnotes' && type != 'endnotes' && type != 'comments') continue;
      final path = _rels[r.getAttribute('Id')];
      final doc = path == null ? null : pkg.xml(path);
      if (doc == null) continue;
      final kind = type.substring(0, type.length - 1); // footnote / endnote / comment
      _noteParts[kind] = path!;
      for (final n in doc.rootElement.childElements.where((e) => e.localName == kind)) {
        final id = n.attr('id');
        if (id != null) _noteXml['$kind:$id'] = n;
      }
    }
  }

  /// Parse isi catatan dengan relasi part-nya sendiri (gambar di footnote, dll).
  List<DocBlock> _noteBlocks(String kind, String id, String label) {
    final xml = _noteXml['$kind:$id'];
    final path = _noteParts[kind];
    if (xml == null || path == null) return const [];
    final savedRels = _rels;
    final savedLabel = _noteLabel;
    _rels = pkg.rels(path);
    _noteLabel = label;
    try {
      return _blocks(xml);
    } finally {
      _rels = savedRels;
      _noteLabel = savedLabel;
    }
  }

  /// Penanda rujukan catatan di teks (superscript).
  void _noteRef(String kind, String? id, _RunProps rp, String? link, List<DocInline> out) {
    if (id == null) return;
    final String label;
    switch (kind) {
      case 'footnote':
        label = '${_footnotes.length + 1}';
        _footnotes[label] = _noteBlocks(kind, id, label);
      case 'endnote':
        label = toRoman(_endnotes.length + 1).toLowerCase();
        _endnotes.add(DocNote(label, _noteBlocks(kind, id, label)));
      default:
        label = 'C${_comments.length + 1}';
        _comments.add(DocNote(label, _noteBlocks(kind, id, label),
            author: _noteXml['comment:$id']?.attr('author')));
    }
    final mark = rp.copy()..vertAlign = 'superscript';
    if (kind == 'comment') mark.color = const Color(0xFFC0504D);
    out.add(mark.toText(label, link, _resolveFont, footnote: kind == 'footnote' ? label : null));
  }

  /// Header/footer (w:hdr / w:ftr) dengan relasi gambarnya sendiri.
  List<DocBlock>? _headerFooter(XmlElement? sect, String kind, String type) {
    final ref = sect?.kids('${kind}Reference').where((e) => e.attr('type') == type).firstOrNull;
    final path = ref == null ? null : _rels[ref.attrNs('r', 'id')];
    final doc = path == null ? null : pkg.xml(path);
    if (doc == null) return null;
    final saved = _rels;
    _rels = pkg.rels(path!);
    try {
      return _blocks(doc.rootElement);
    } finally {
      _rels = saved;
    }
  }

  void _loadLinkTargets(String mainPart) {
    final slash = mainPart.lastIndexOf('/');
    final relDoc = pkg.xml(
        '${mainPart.substring(0, slash)}/_rels/${mainPart.substring(slash + 1)}.rels');
    if (relDoc == null) return;
    for (final r in relDoc.descendantElements.where((e) => e.localName == 'Relationship')) {
      if (r.getAttribute('TargetMode') == 'External') {
        _linkTargets[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
      }
    }
  }

  // ── Styles ────────────────────────────────────────────────────────────────

  void _loadStyles() {
    final doc = pkg.xml('word/styles.xml');
    if (doc == null) return;
    final defaults = doc.first('docDefaults');
    final rPr = defaults?.child('rPrDefault')?.child('rPr');
    final pPr = defaults?.child('pPrDefault')?.child('pPr');
    if (rPr != null) _defaultRun.apply(rPr);
    if (pPr != null) _defaultPara.apply(pPr);

    for (final s in doc.descendantElements.where((e) => e.localName == 'style')) {
      final id = s.attr('styleId');
      if (id == null) continue;
      final type = s.attr('type') ?? 'paragraph';
      _styles[id] = _Style(
        type: type,
        name: s.child('name')?.attr('val')?.toLowerCase() ?? '',
        basedOn: s.child('basedOn')?.attr('val'),
        pPr: s.child('pPr'),
        rPr: s.child('rPr'),
        tblPr: s.child('tblPr'),
      );
      final isDefault = s.attr('default') == '1' || s.attr('default') == 'true';
      if (isDefault && type == 'paragraph') _defaultParaStyle = id;
      if (isDefault && type == 'table') _defaultTableStyle = id;
    }
  }

  /// Rantai style dari yang paling dasar → paling spesifik.
  List<_Style> _chain(String? id) {
    final out = <_Style>[];
    final seen = <String>{};
    var cur = id;
    while (cur != null && seen.add(cur)) {
      final s = _styles[cur];
      if (s == null) break;
      out.insert(0, s);
      cur = s.basedOn;
    }
    return out;
  }

  // ── Blocks ────────────────────────────────────────────────────────────────

  List<DocBlock> _blocks(XmlElement container, {bool topLevel = false}) {
    final out = <DocBlock>[];
    for (final el in container.childElements) {
      switch (el.localName) {
        case 'p':
          _paragraph(el, out, topLevel: topLevel);
        case 'tbl':
          out.addAll(topLevel ? _splitTable(el) : [_table(el)]);
        case 'sdt':
          final content = el.child('sdtContent');
          if (content != null) out.addAll(_blocks(content, topLevel: topLevel));
        case 'customXml':
        case 'ins':
        case 'smartTag':
          out.addAll(_blocks(el, topLevel: topLevel));
        case 'AlternateContent':
          final choice = el.child('Choice') ?? el.child('Fallback');
          if (choice != null) out.addAll(_blocks(choice, topLevel: topLevel));
      }
    }
    return out;
  }

  void _paragraph(XmlElement p, List<DocBlock> out, {bool topLevel = false}) {
    final pPr = p.child('pPr');
    final styleId = pPr?.child('pStyle')?.attr('val') ?? _defaultParaStyle;
    final chain = _chain(styleId);

    final pp = _defaultPara.copy();
    final rp = _defaultRun.copy();
    for (final s in chain) {
      if (s.pPr != null) pp.apply(s.pPr!);
      if (s.rPr != null) rp.apply(s.rPr!);
    }

    // Numbering bisa datang dari style atau langsung dari paragraf
    final numPr = pPr?.child('numPr');
    if (numPr?.child('numId') != null) pp.numId = numPr!.child('numId')!.attr('val');
    if (numPr?.child('ilvl') != null) {
      pp.ilvl = int.tryParse(numPr!.child('ilvl')!.attr('val') ?? '') ?? 0;
    }
    String? label;
    if (pp.numId != null && pp.numId != '0') {
      final lvl = _numbering.level(pp.numId!, pp.ilvl);
      if (lvl != null) {
        if (lvl.pPr != null) pp.apply(lvl.pPr!);
        label = _numbering.next(pp.numId!, pp.ilvl);
      }
    }
    if (pPr != null) pp.apply(pPr);

    // Properti run "paragraph mark" tidak dipakai untuk teks
    final inlines = <DocInline>[];
    final extraBlocks = <DocBlock>[];
    _inlines(p, rp, null, inlines, extraBlocks);

    final name = chain.isEmpty ? '' : chain.last.name;
    var heading = 0;
    final hm = RegExp(r'heading (\d)').firstMatch(name);
    if (hm != null) {
      heading = int.parse(hm.group(1)!);
    } else if (name == 'title') {
      heading = 1;
    } else if (pp.outlineLvl != null && pp.outlineLvl! < 9) {
      heading = pp.outlineLvl! + 1;
    }

    final para = DocParagraph(
      inlines: inlines.where((i) => i is! DocBreakMarker).toList(),
      align: pp.align,
      indentLeft: pp.indLeft,
      indentRight: pp.indRight,
      firstLine: pp.firstLine,
      spaceBefore: pp.spaceBefore,
      spaceAfter: pp.spaceAfter,
      lineHeight: pp.line,
      lineExact: pp.lineExact,
      lineAtLeast: pp.lineAtLeast,
      listLabel: label,
      shading: pp.shading,
      headingLevel: heading,
      pageBreakBefore: pp.pageBreakBefore,
      keepNext: pp.keepNext,
    );

    // Pecah paragraf di penanda pindah halaman (hanya di badan dokumen)
    final parts = <List<DocInline>>[[]];
    final breaks = <bool>[];
    for (final i in inlines) {
      if (i is DocBreakMarker) {
        if (!topLevel) continue;
        if (i.soft) _renderedBreaks = true;
        breaks.add(i.soft);
        parts.add([]);
      } else {
        parts.last.add(i);
      }
    }
    if (parts.length == 1) {
      out.add(para);
    } else {
      bool hasContent(List<DocInline> l) =>
          l.any((x) => x is! DocText || x.text.trim().isNotEmpty || x.field != null);
      for (var k = 0; k < parts.length; k++) {
        if (k > 0) out.add(DocPageBreak(soft: breaks[k - 1]));
        if (!hasContent(parts[k])) continue;
        out.add(k == 0
            ? para.head(parts[k])
            : k == parts.length - 1
                ? para.continuation(parts[k])
                : para.continuation(parts[k]).head(parts[k]));
      }
    }
    out.addAll(extraBlocks);
  }

  static String? _fieldKind(String instr) {
    final word = instr.trim().split(RegExp(r'\s+')).first.toUpperCase();
    return switch (word) {
      'PAGE' => 'PAGE',
      'NUMPAGES' || 'SECTIONPAGES' => 'NUMPAGES',
      _ => null,
    };
  }

  void _inlines(XmlElement parent, _RunProps paraRun, String? link,
      List<DocInline> out, List<DocBlock> extra) {
    for (final el in parent.childElements) {
      switch (el.localName) {
        case 'r':
          _run(el, paraRun, link, out, extra);
        case 'hyperlink':
          final id = el.attr('id');
          final anchor = el.attr('anchor');
          final target = id != null ? _linkTargets[id] : (anchor != null ? '#$anchor' : null);
          _inlines(el, paraRun, target ?? link, out, extra);
        case 'fldSimple':
          final kind = _fieldKind(el.attr('instr') ?? '');
          if (kind != null) {
            final r = el.descendant('rPr');
            final rp = paraRun.copy();
            if (r != null) rp.apply(r);
            out.add(rp.toText('1', link, _resolveFont).copyWith(field: kind));
          } else {
            _inlines(el, paraRun, link, out, extra);
          }
        case 'ins':
        case 'smartTag':
        case 'customXml':
        case 'bdo':
        case 'dir':
          _inlines(el, paraRun, link, out, extra);
        case 'sdt':
          final c = el.child('sdtContent');
          if (c != null) _inlines(c, paraRun, link, out, extra);
        case 'oMathPara':
        case 'oMath':
          // Rumus (OMML) ditampilkan sebagai teks linear: (a)/(b), x², √(x)
          final t = _math(el);
          if (t.isNotEmpty) {
            out.add((paraRun.copy()..italic = true..font = 'Cambria Math').toText(t, link, _resolveFont));
          }
        case 'AlternateContent':
          final choice = el.child('Choice') ?? el.child('Fallback');
          if (choice != null) _inlines(choice, paraRun, link, out, extra);
        // 'del' (teks dihapus) & 'moveFrom' sengaja dilewati
      }
    }
  }

  void _run(XmlElement r, _RunProps paraRun, String? link, List<DocInline> out,
      List<DocBlock> extra) {
    final rPr = r.child('rPr');
    final rp = paraRun.copy();
    final rStyle = rPr?.child('rStyle')?.attr('val');
    for (final s in _chain(rStyle)) {
      if (s.rPr != null) rp.apply(s.rPr!);
    }
    if (rPr != null) rp.apply(rPr);
    if (rp.vanish) return;

    final sb = StringBuffer();
    void flush() {
      if (sb.isEmpty) return;
      out.add(rp.toText(sb.toString(), link, _resolveFont));
      sb.clear();
    }

    for (final c in r.childElements) {
      // Field kompleks: begin → instrText → separate → hasil cache → end
      if (c.localName == 'fldChar') {
        switch (c.attr('fldCharType')) {
          case 'begin':
            _fieldSkip.add(false);
            _instr.clear();
          case 'separate':
            final kind = _fieldKind(_instr.toString());
            if (kind != null && _fieldSkip.isNotEmpty) {
              flush();
              out.add(rp.toText('1', link, _resolveFont).copyWith(field: kind));
              _fieldSkip[_fieldSkip.length - 1] = true;
            }
          case 'end':
            if (_fieldSkip.isNotEmpty) _fieldSkip.removeLast();
        }
        continue;
      }
      if (c.localName == 'instrText') {
        _instr.write(c.innerText);
        continue;
      }
      if (_fieldSkip.contains(true) && c.localName != 'lastRenderedPageBreak') continue;
      switch (c.localName) {
        case 't':
          sb.write(c.innerText);
        case 'tab':
        case 'ptab':
          sb.write('\t');
        case 'br':
          if (c.attr('type') == 'page') {
            flush();
            out.add(DocBreakMarker(false));
          } else {
            sb.write('\n');
          }
        case 'cr':
          sb.write('\n');
        case 'noBreakHyphen':
          sb.write('‑');
        case 'softHyphen':
          break;
        case 'sym':
          final code = int.tryParse(c.attr('char') ?? '', radix: 16);
          if (code != null) sb.write(sanitizeBullet(String.fromCharCode(code), 0));
        case 'lastRenderedPageBreak':
          flush();
          out.add(DocBreakMarker(true));
        case 'footnoteReference':
        case 'endnoteReference':
        case 'commentReference':
          flush();
          _noteRef(c.localName.replaceFirst('Reference', ''), c.attr('id'), rp, link, out);
        case 'footnoteRef':
        case 'endnoteRef':
          // Nomor catatan di awal isi footnote/endnote
          if (_noteLabel != null) {
            flush();
            out.add((rp.copy()..vertAlign = 'superscript').toText(_noteLabel!, link, _resolveFont));
          }
        case 'drawing':
        case 'pict':
        case 'object':
          flush();
          _drawing(c, out, extra);
        case 'AlternateContent':
          final choice = c.child('Choice') ?? c.child('Fallback');
          if (choice != null) {
            flush();
            for (final d in choice.childElements) {
              if (d.localName == 'drawing' || d.localName == 'pict') _drawing(d, out, extra);
            }
          }
      }
    }
    flush();
  }

  void _drawing(XmlElement d, List<DocInline> out, List<DocBlock> extra) {
    // Text box: isinya ditampilkan sebagai blok setelah paragraf
    // Semua text box (grup shape bisa berisi beberapa); text box bertingkat
    // sudah ikut terbaca lewat text box induknya
    for (final txbx in d.descendantElements.where((e) => e.localName == 'txbxContent')) {
      final nested = txbx.ancestorElements
          .takeWhile((a) => a != d)
          .any((a) => a.localName == 'txbxContent');
      if (!nested) extra.addAll(_blocks(txbx));
    }

    final extent = d.descendant('extent');
    var w = emuToPt(extent?.attr('cx'));
    var h = emuToPt(extent?.attr('cy'));

    // Chart: c:chart r:id → word/charts/chartN.xml
    final chartRef = d.descendant('graphicData')?.child('chart');
    if (chartRef != null) {
      final path = _rels[chartRef.attrNs('r', 'id')];
      final doc = path == null ? null : pkg.xml(path);
      ChartData? chart;
      try {
        chart = doc == null ? null : parseOoxmlChart(doc, _scheme);
      } catch (_) {}
      if (chart != null) {
        out.add(DocChart(chart, w > 0 ? w : 432, h > 0 ? h : 252));
        return;
      }
    }

    String? relId;
    final blip = d.descendant('blip');
    if (blip != null) {
      relId = blip.attr('embed') ?? blip.attr('link');
    } else {
      final imgData = d.descendant('imagedata'); // VML lama
      relId = imgData?.attr('id');
      if (imgData != null && w == 0) {
        final style = d.descendant('shape')?.attr('style') ?? '';
        w = _vmlLength(style, 'width');
        h = _vmlLength(style, 'height');
      }
    }
    if (relId == null) return;
    final path = _rels[relId];
    if (path == null) return;
    if (w <= 0 || h <= 0) {
      w = 200;
      h = 150;
    }
    out.add(DocImage(isRenderableImage(path) ? pkg.bytes(path) : null, w, h));
  }

  static const _sup = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', //
    '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', 'n': 'ⁿ', 'i': 'ⁱ',
  };
  static const _sub = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', //
    '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋',
  };

  static String _script(String t, Map<String, String> map, String fallback) =>
      t.split('').every(map.containsKey) ? t.split('').map((c) => map[c]).join() : '$fallback($t)';

  static String _math(XmlElement e) {
    String part(String name) {
      final c = e.child(name);
      return c == null ? '' : _math(c);
    }

    String wrap(String t) => t.length <= 1 ? t : '($t)';
    switch (e.localName) {
      case 't':
        return e.innerText;
      case 'f':
        return '${wrap(part('num'))}/${wrap(part('den'))}';
      case 'sSup':
        return part('e') + _script(part('sup'), _sup, '^');
      case 'sSub':
        return part('e') + _script(part('sub'), _sub, '_');
      case 'sSubSup':
        return part('e') + _script(part('sub'), _sub, '_') + _script(part('sup'), _sup, '^');
      case 'rad':
        final deg = part('deg');
        return '${deg.isEmpty ? '' : _script(deg, _sup, '^')}√${wrap(part('e'))}';
      case 'd':
        final pr = e.child('dPr');
        final beg = pr?.child('begChr')?.attr('val') ?? '(';
        final end = pr?.child('endChr')?.attr('val') ?? ')';
        return '$beg${e.kids('e').map(_math).join(', ')}$end';
      case 'nary':
        final chr = e.child('naryPr')?.child('chr')?.attr('val') ?? '∫';
        return '$chr${_script(part('sub'), _sub, '_')}${_script(part('sup'), _sup, '^')} ${part('e')}';
      case 'rPr':
      case 'ctrlPr':
      case 'oMathParaPr':
      case 'fPr':
      case 'sSupPr':
      case 'sSubPr':
      case 'radPr':
      case 'naryPr':
      case 'dPr':
        return '';
      default:
        return e.childElements.map(_math).join();
    }
  }

  double _vmlLength(String style, String key) {
    final m = RegExp('$key:\\s*([\\d.]+)(pt|in|px|cm|mm)?').firstMatch(style);
    if (m == null) return 0;
    return odfLength('${m.group(1)}${m.group(2) ?? 'pt'}') ?? 0;
  }

  // ── Tabel ─────────────────────────────────────────────────────────────────

  DocTable _table(XmlElement tbl) {
    final tblPr = tbl.child('tblPr');
    final styleId = tblPr?.child('tblStyle')?.attr('val') ?? _defaultTableStyle;

    bool hasBorders(XmlElement? pr) {
      final b = pr?.child('tblBorders');
      if (b == null) return false;
      return b.childElements.any((e) {
        final v = e.attr('val');
        return v != null && v != 'nil' && v != 'none';
      });
    }

    var borders = hasBorders(tblPr);
    if (!borders && tblPr?.child('tblBorders') == null) {
      borders = _chain(styleId).any((s) => hasBorders(s.tblPr));
    }

    // Margin sel: tblPr langsung → style tabel → style tabel default
    // ("Normal Table", biasanya 0.08"). Tanpa definisi sama sekali Word memakai 0.
    double? mar(String side, [String? alt]) {
      for (final pr in [
        tblPr,
        ..._chain(styleId).reversed.map((s) => s.tblPr),
        if (_defaultTableStyle != styleId) ..._chain(_defaultTableStyle).reversed.map((s) => s.tblPr),
      ]) {
        final m = pr?.child('tblCellMar');
        final e = m?.child(side) ?? (alt == null ? null : m?.child(alt));
        if (e != null) return twipToPt(e.attr('w'));
      }
      return null;
    }

    final cellH = mar('left', 'start') ?? 0;
    final cellTop = mar('top') ?? 0;
    final cellBottom = mar('bottom') ?? 0;

    final widths = tbl
        .child('tblGrid')
        ?.kids('gridCol')
        .map((g) => twipToPt(g.attr('w')))
        .toList() ??
        <double>[];

    final rows = <DocTableRow>[];
    for (final tr in tbl.childElements.where((e) => e.localName == 'tr')) {
      final header = tr.child('trPr')?.toggle('tblHeader') ?? false;
      final cantSplit = tr.child('trPr')?.toggle('cantSplit') ?? false;
      final cells = <DocTableCell>[];
      for (final tc in _rowCells(tr)) {
        final tcPr = tc.child('tcPr');
        final span = int.tryParse(tcPr?.child('gridSpan')?.attr('val') ?? '') ?? 1;
        final vMerge = tcPr?.child('vMerge');
        final cont = vMerge != null && (vMerge.attr('val') ?? 'continue') == 'continue';
        final fill = tcPr?.child('shd')?.attr('fill');
        cells.add(DocTableCell(
          // topLevel: penanda pindah halaman Word di dalam sel dipertahankan
          // sebagai DocPageBreak agar baris bisa dipecah di posisi yang sama
          cont ? [] : _blocks(tc, topLevel: _keepCellBreaks),
          colSpan: span < 1 ? 1 : span,
          shading: fill == 'auto' ? null : parseHexColor(fill),
          mergedContinue: cont,
        ));
      }
      rows.add(DocTableRow(cells, header: header, cantSplit: cantSplit));
    }

    if (widths.isEmpty || widths.every((w) => w <= 0)) {
      final n = rows.fold<int>(0, (m, r) {
        final c = r.cells.fold<int>(0, (s, x) => s + x.colSpan);
        return c > m ? c : m;
      });
      return DocTable(
          columnWidths: List.filled(n, 1),
          rows: rows,
          borders: borders,
          cellMarginH: cellH,
          cellMarginTop: cellTop,
          cellMarginBottom: cellBottom);
    }
    return DocTable(
        columnWidths: widths,
        rows: rows,
        borders: borders,
        cellMarginH: cellH,
        cellMarginTop: cellTop,
        cellMarginBottom: cellBottom);
  }

  /// Pecah tabel di posisi pindah halaman hasil render Word: sebelum baris
  /// (baris mulai di halaman baru) atau di tengah baris (baris terpotong).
  /// Baris header (tblHeader) diulang di awal halaman berikutnya seperti Word.
  List<DocBlock> _splitTable(XmlElement tbl) {
    final saved = _keepCellBreaks;
    _keepCellBreaks = true;
    final table = _table(tbl);
    _keepCellBreaks = saved;

    bool isBreak(DocBlock b) => b is DocPageBreak && b.soft;
    List<DocBlock> clean(List<DocBlock> bs) => bs.where((b) => !isBreak(b)).toList();
    DocTableRow cleanRow(DocTableRow r) => DocTableRow(
        [for (final c in r.cells) DocTableCell(clean(c.blocks), colSpan: c.colSpan, shading: c.shading, mergedContinue: c.mergedContinue)],
        header: r.header,
        cantSplit: r.cantSplit);

    final header = table.rows.takeWhile((r) => r.header).map(cleanRow).toList();
    final out = <DocBlock>[];
    var current = <DocTableRow>[];
    void flush({required bool pageBreak}) {
      if (current.isNotEmpty) out.add(table.withRows(current));
      if (pageBreak) {
        out.add(DocPageBreak(soft: true));
        _renderedBreaks = true;
        current = out.whereType<DocTable>().isEmpty ? [] : [...header];
      } else {
        current = [];
      }
    }

    // Setelah baris terpotong, Word juga menandai awal baris berikutnya
    // (pindah halaman yang sama) — penanda kedua itu diabaikan
    var afterSplit = false;
    for (final row in table.rows) {
      final withBreak = row.cells.where((c) => c.blocks.any(isBreak)).toList();
      if (withBreak.isEmpty || afterSplit) {
        current.add(cleanRow(row));
        afterSplit = false;
        continue;
      }
      // Break sebelum konten apa pun di semua sel → baris mulai di halaman baru
      final startsNewPage = row.cells.every((c) {
        final i = c.blocks.indexWhere(isBreak);
        return i < 0 ? c.blocks.isEmpty : c.blocks.take(i).every((b) => b is DocParagraph && b.isEmpty);
      });
      if (startsNewPage) {
        if (!afterSplit && (current.length > header.length || out.isNotEmpty)) flush(pageBreak: true);
        current.add(cleanRow(row));
        afterSplit = false;
        continue;
      }
      // Baris terpotong: isi sebelum break di halaman ini, sisanya di halaman berikut
      final top = <DocTableCell>[], rest = <DocTableCell>[];
      for (final c in row.cells) {
        final i = c.blocks.indexWhere(isBreak);
        final a = i < 0 ? c.blocks : c.blocks.sublist(0, i);
        final b = i < 0 ? <DocBlock>[] : c.blocks.sublist(i + 1);
        top.add(DocTableCell(clean(a), colSpan: c.colSpan, shading: c.shading, mergedContinue: c.mergedContinue));
        rest.add(DocTableCell(clean(b), colSpan: c.colSpan, shading: c.shading, mergedContinue: true));
      }
      current.add(DocTableRow(top, header: row.header));
      flush(pageBreak: true);
      current.add(DocTableRow(rest));
      afterSplit = true;
    }
    if (current.isNotEmpty) out.add(table.withRows(current));
    return out;
  }

  Iterable<XmlElement> _rowCells(XmlElement tr) sync* {
    for (final e in tr.childElements) {
      if (e.localName == 'tc') {
        yield e;
      } else if (e.localName == 'sdt' || e.localName == 'customXml') {
        final c = e.child('sdtContent') ?? e;
        yield* c.childElements.where((x) => x.localName == 'tc');
      }
    }
  }
}

// ── Style & properti ─────────────────────────────────────────────────────────

class _Style {
  final String type;
  final String name;
  final String? basedOn;
  final XmlElement? pPr;
  final XmlElement? rPr;
  final XmlElement? tblPr;
  _Style({
    required this.type,
    required this.name,
    this.basedOn,
    this.pPr,
    this.rPr,
    this.tblPr,
  });
}

const _highlightColors = {
  'yellow': Color(0xFFFFFF00),
  'green': Color(0xFF00FF00),
  'cyan': Color(0xFF00FFFF),
  'magenta': Color(0xFFFF00FF),
  'blue': Color(0xFF0000FF),
  'red': Color(0xFFFF0000),
  'darkBlue': Color(0xFF000080),
  'darkCyan': Color(0xFF008080),
  'darkGreen': Color(0xFF008000),
  'darkMagenta': Color(0xFF800080),
  'darkRed': Color(0xFF800000),
  'darkYellow': Color(0xFF808000),
  'darkGray': Color(0xFF808080),
  'lightGray': Color(0xFFC0C0C0),
  'black': Color(0xFF000000),
  'white': Color(0xFFFFFFFF),
};

class _RunProps {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  bool caps = false;
  bool vanish = false;
  double? size;
  Color? color;
  Color? highlight;
  String? font;
  String? vertAlign;

  _RunProps copy() => _RunProps()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..caps = caps
    ..vanish = vanish
    ..size = size
    ..color = color
    ..highlight = highlight
    ..font = font
    ..vertAlign = vertAlign;

  void apply(XmlElement rPr) {
    bold = rPr.toggle('b') ?? bold;
    italic = rPr.toggle('i') ?? italic;
    strike = rPr.toggle('strike') ?? rPr.toggle('dstrike') ?? strike;
    caps = rPr.toggle('caps') ?? caps;
    vanish = rPr.toggle('vanish') ?? vanish;
    final u = rPr.child('u');
    if (u != null) underline = (u.attr('val') ?? 'single') != 'none';
    final sz = double.tryParse(rPr.child('sz')?.attr('val') ?? '');
    if (sz != null) size = sz / 2;
    final c = rPr.child('color')?.attr('val');
    if (c != null) color = c == 'auto' ? null : parseHexColor(c) ?? color;
    final hl = rPr.child('highlight')?.attr('val');
    if (hl != null) highlight = _highlightColors[hl];
    final shd = rPr.child('shd')?.attr('fill');
    if (shd != null && shd != 'auto') highlight = parseHexColor(shd) ?? highlight;
    final f = rPr.child('rFonts');
    if (f != null) {
      final theme = f.attr('asciiTheme') ?? f.attr('hAnsiTheme');
      font = f.attr('ascii') ??
          f.attr('hAnsi') ??
          (theme == null ? null : (theme.startsWith('major') ? 'theme:major' : 'theme:minor')) ??
          font;
    }
    final va = rPr.child('vertAlign')?.attr('val');
    if (va != null) vertAlign = va;
  }

  DocText toText(String text, String? link, String? Function(String?) resolveFont,
          {String? footnote}) =>
      DocText(
        text,
        bold: bold,
        italic: italic,
        underline: underline || link != null,
        strike: strike,
        fontSize: size,
        color: color ?? (link != null ? const Color(0xFF0563C1) : null),
        highlight: highlight,
        fontFamily: resolveFont(font),
        superscript: vertAlign == 'superscript',
        subscript: vertAlign == 'subscript',
        allCaps: caps,
        link: link,
        footnote: footnote,
      );
}

class _ParaProps {
  TextAlign align = TextAlign.left;
  double indLeft = 0;
  double indRight = 0;
  double firstLine = 0;
  double spaceBefore = 0;
  double spaceAfter = 0;
  double? line;
  double? lineExact;
  double? lineAtLeast;
  Color? shading;
  bool pageBreakBefore = false;
  bool keepNext = false;
  int? outlineLvl;
  String? numId;
  int ilvl = 0;

  _ParaProps copy() => _ParaProps()
    ..align = align
    ..indLeft = indLeft
    ..indRight = indRight
    ..firstLine = firstLine
    ..spaceBefore = spaceBefore
    ..spaceAfter = spaceAfter
    ..line = line
    ..lineExact = lineExact
    ..lineAtLeast = lineAtLeast
    ..shading = shading
    ..pageBreakBefore = pageBreakBefore
    ..keepNext = keepNext
    ..outlineLvl = outlineLvl
    ..numId = numId
    ..ilvl = ilvl;

  void apply(XmlElement pPr) {
    final jc = pPr.child('jc')?.attr('val');
    if (jc != null) {
      align = switch (jc) {
        'center' => TextAlign.center,
        'right' || 'end' => TextAlign.right,
        'both' || 'distribute' || 'thaiDistribute' => TextAlign.justify,
        _ => TextAlign.left,
      };
    }
    final ind = pPr.child('ind');
    if (ind != null) {
      final l = ind.attr('left') ?? ind.attr('start');
      final r = ind.attr('right') ?? ind.attr('end');
      if (l != null) indLeft = twipToPt(l);
      if (r != null) indRight = twipToPt(r);
      if (ind.attr('hanging') != null) {
        firstLine = -twipToPt(ind.attr('hanging'));
      } else if (ind.attr('firstLine') != null) {
        firstLine = twipToPt(ind.attr('firstLine'));
      }
    }
    final sp = pPr.child('spacing');
    if (sp != null) {
      if (sp.attr('before') != null) spaceBefore = twipToPt(sp.attr('before'));
      if (sp.attr('after') != null) spaceAfter = twipToPt(sp.attr('after'));
      final ln = double.tryParse(sp.attr('line') ?? '');
      if (ln != null) {
        // auto: 240 = satu spasi; exact/atLeast dalam twip
        switch (sp.attr('lineRule') ?? 'auto') {
          case 'exact':
            lineExact = ln / 20;
            line = null;
            lineAtLeast = null;
          case 'atLeast':
            lineAtLeast = ln / 20;
            line = null;
            lineExact = null;
          default:
            line = ln / 240;
            lineExact = null;
            lineAtLeast = null;
        }
      }
    }
    final shd = pPr.child('shd')?.attr('fill');
    if (shd != null) shading = shd == 'auto' ? null : parseHexColor(shd);
    pageBreakBefore = pPr.toggle('pageBreakBefore') ?? pageBreakBefore;
    keepNext = pPr.toggle('keepNext') ?? keepNext;
    final ol = int.tryParse(pPr.child('outlineLvl')?.attr('val') ?? '');
    if (ol != null) outlineLvl = ol;
    final numPr = pPr.child('numPr');
    if (numPr != null) {
      numId = numPr.child('numId')?.attr('val') ?? numId;
      ilvl = int.tryParse(numPr.child('ilvl')?.attr('val') ?? '') ?? ilvl;
    }
  }
}

// ── Numbering ────────────────────────────────────────────────────────────────

class _Lvl {
  final String fmt;
  final String text;
  final int start;
  final XmlElement? pPr;
  _Lvl(this.fmt, this.text, this.start, this.pPr);
}

class _Numbering {
  final Map<String, String> _numToAbs = {};
  final Map<String, Map<int, _Lvl>> _abs = {};
  final Map<String, Map<int, int>> _startOverride = {};
  final Map<String, List<int>> _counters = {};

  _Numbering(XmlDocument? doc) {
    if (doc == null) return;
    for (final a in doc.descendantElements.where((e) => e.localName == 'abstractNum')) {
      final id = a.attr('abstractNumId');
      if (id == null) continue;
      _abs[id] = {for (final l in a.kids('lvl')) ..._lvl(l)};
    }
    for (final n in doc.descendantElements.where((e) => e.localName == 'num')) {
      final id = n.attr('numId');
      final abs = n.child('abstractNumId')?.attr('val');
      if (id == null || abs == null) continue;
      _numToAbs[id] = abs;
      for (final o in n.kids('lvlOverride')) {
        final ilvl = int.tryParse(o.attr('ilvl') ?? '') ?? 0;
        final st = int.tryParse(o.child('startOverride')?.attr('val') ?? '');
        if (st != null) (_startOverride[id] ??= {})[ilvl] = st;
      }
    }
  }

  Map<int, _Lvl> _lvl(XmlElement l) {
    final ilvl = int.tryParse(l.attr('ilvl') ?? '') ?? 0;
    return {
      ilvl: _Lvl(
        l.child('numFmt')?.attr('val') ?? 'decimal',
        l.child('lvlText')?.attr('val') ?? '',
        int.tryParse(l.child('start')?.attr('val') ?? '') ?? 1,
        l.child('pPr'),
      )
    };
  }

  _Lvl? level(String numId, int ilvl) => _abs[_numToAbs[numId]]?[ilvl];

  /// Naikkan counter level ini, reset level lebih dalam, kembalikan label.
  String? next(String numId, int ilvl) {
    final levels = _abs[_numToAbs[numId]];
    final lvl = levels?[ilvl];
    if (lvl == null) return null;
    final counters = _counters.putIfAbsent(numId, () => List.filled(9, 0));
    int startOf(int i) => _startOverride[numId]?[i] ?? levels?[i]?.start ?? 1;

    counters[ilvl] = counters[ilvl] == 0 ? startOf(ilvl) : counters[ilvl] + 1;
    for (var i = ilvl + 1; i < counters.length; i++) {
      counters[i] = 0;
    }

    if (lvl.fmt == 'bullet') return sanitizeBullet(lvl.text, ilvl);
    if (lvl.fmt == 'none') return null;
    return lvl.text.replaceAllMapped(RegExp(r'%(\d)'), (m) {
      final i = int.parse(m.group(1)!) - 1;
      if (i < 0 || i >= counters.length) return '';
      final v = counters[i] == 0 ? startOf(i) : counters[i];
      return formatListNumber(levels?[i]?.fmt ?? 'decimal', v);
    });
  }
}
