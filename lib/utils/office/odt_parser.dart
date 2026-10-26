import 'dart:typed_data';
import 'dart:ui';
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'chart_parser.dart';
import 'doc_model.dart';
import 'odf_styles.dart';
import 'office_common.dart';

/// Parser ODT (OpenDocument Text, LibreOffice Writer / Google Docs export).
DocDocument parseOdt(Uint8List data) {
  final pkg = OfficePackage(data);
  final content = pkg.xml('content.xml');
  if (content == null) throw const FormatException('Not a valid ODT document');
  final text = content.first('text');
  if (text == null) throw const FormatException('Document body not found');
  final p = _OdtParser(pkg, OdfStyles(pkg));

  // Master page pertama: ukuran kertas, margin, header & footer
  final master = p.styles.masterPages['Standard'] ?? p.styles.masterPages.values.firstOrNull;
  final layout = p.styles.pageLayouts[master?.attr('page-layout-name')]?.child('page-layout-properties') ??
      p.styles.pageLayouts.values.firstOrNull?.child('page-layout-properties');
  var page = const DocPageSetup();
  if (layout != null) {
    double v(String a, double d) => odfLength(layout.attr(a)) ?? d;
    page = DocPageSetup(
      width: v('page-width', 595.3),
      height: v('page-height', 841.9),
      marginTop: v('margin-top', 56.7),
      marginBottom: v('margin-bottom', 56.7),
      marginLeft: v('margin-left', 56.7),
      marginRight: v('margin-right', 56.7),
      headerDistance: v('margin-top', 56.7) / 2,
      footerDistance: v('margin-bottom', 56.7) / 2,
    );
    if (page.width - page.marginLeft - page.marginRight < 100) page = const DocPageSetup();
  }
  // Badan dokumen diparse dulu agar nomor catatan berurutan seperti aslinya
  final body = p.blocks(text);
  final header = master?.child('header');
  final footer = master?.child('footer');
  return DocDocument(
    body,
    page: page,
    header: header == null ? const [] : p.blocks(header),
    footer: footer == null ? const [] : p.blocks(footer),
    footnotes: p.footnotes,
    endnotes: p.endnotes,
    comments: p.comments,
  );
}

class _OdtParser {
  final OfficePackage pkg;
  final OdfStyles styles;
  final Map<String, List<DocBlock>> footnotes = {};
  final List<DocNote> endnotes = [];
  final List<DocNote> comments = [];
  _OdtParser(this.pkg, this.styles);

  List<DocBlock> blocks(XmlElement container, {_ListCtx? list}) {
    final out = <DocBlock>[];
    for (final el in container.childElements) {
      switch (el.localName) {
        case 'p':
        case 'h':
          _paragraph(el, out, list: list);
        case 'list':
          _list(el, out, list);
        case 'table':
          out.add(_table(el));
        case 'section':
        case 'index-body':
        case 'table-of-content':
        case 'alphabetical-index':
        case 'illustration-index':
        case 'bibliography':
          out.addAll(blocks(el, list: list));
      }
    }
    return out;
  }

  void _list(XmlElement listEl, List<DocBlock> out, _ListCtx? parent) {
    final styleName = listEl.attr('style-name') ?? parent?.styleName;
    final ctx = _ListCtx(styleName, (parent?.level ?? -1) + 1, styles);
    for (final item in listEl.childElements) {
      if (item.localName != 'list-item' && item.localName != 'list-header') continue;
      ctx.counter++;
      var first = true;
      for (final c in item.childElements) {
        if (c.localName == 'list') {
          _list(c, out, ctx);
        } else if (c.localName == 'p' || c.localName == 'h') {
          _paragraph(c, out,
              list: ctx, showLabel: first && item.localName == 'list-item');
          first = false;
        }
      }
    }
  }

  void _paragraph(XmlElement p, List<DocBlock> out,
      {_ListCtx? list, bool showLabel = false}) {
    final styleName = p.attr('style-name');
    final pp = _OdtPara();
    for (final e in styles.props('paragraph', styleName, 'paragraph-properties')) {
      pp.apply(e);
    }
    final tp = _OdtText();
    for (final e in styles.props('paragraph', styleName, 'text-properties')) {
      tp.apply(e);
    }

    final inlines = <DocInline>[];
    _inlines(p, tp, null, inlines);

    var heading = 0;
    if (p.localName == 'h') {
      heading = int.tryParse(p.attr('outline-level') ?? '') ?? 1;
    }

    var indent = pp.marginLeft;
    String? label;
    if (list != null) {
      indent += 18.0 * (list.level + 1);
      if (showLabel) label = list.label();
    }

    out.add(DocParagraph(
      inlines: inlines,
      align: pp.align,
      indentLeft: indent,
      indentRight: pp.marginRight,
      firstLine: pp.textIndent,
      spaceBefore: pp.marginTop,
      spaceAfter: pp.marginBottom,
      lineHeight: pp.lineHeight,
      listLabel: label,
      shading: pp.background,
      headingLevel: heading,
      pageBreakBefore: pp.breakBefore,
      keepNext: pp.keepNext || heading > 0,
    ));
  }

  void _inlines(XmlElement parent, _OdtText tp, String? link, List<DocInline> out) {
    for (final node in parent.children) {
      if (node is XmlText) {
        // Whitespace beruntun di ODF diringkas menjadi satu spasi
        final t = node.value.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) out.add(tp.toText(t, link));
        continue;
      }
      if (node is! XmlElement) continue;
      switch (node.localName) {
        case 'span':
          final s = tp.copy();
          for (final e in styles.props('text', node.attr('style-name'), 'text-properties')) {
            s.apply(e);
          }
          _inlines(node, s, link, out);
        case 'a':
          _inlines(node, tp, node.attr('href') ?? link, out);
        case 's':
          final c = int.tryParse(node.attr('c') ?? '') ?? 1;
          out.add(tp.toText(' ' * c, link));
        case 'tab':
          out.add(tp.toText('\t', link));
        case 'line-break':
          out.add(tp.toText('\n', link));
        case 'frame':
          _frame(node, out);
        case 'page-number':
          out.add(tp.toText('1', link).copyWith(field: 'PAGE'));
        case 'page-count':
          out.add(tp.toText('1', link).copyWith(field: 'NUMPAGES'));
        case 'note':
          final isEnd = node.attr('note-class') == 'endnote';
          final noteBody = node.child('note-body');
          final blocks = noteBody == null ? <DocBlock>[] : this.blocks(noteBody);
          final label = node.child('note-citation')?.innerText.trim().isNotEmpty == true
              ? node.child('note-citation')!.innerText.trim()
              : isEnd
                  ? toRoman(endnotes.length + 1).toLowerCase()
                  : '${footnotes.length + 1}';
          // Isi catatan ODF tidak memuat nomornya sendiri: tambahkan di depan
          final mark = (tp.copy()..position = 'super').toText(label, null);
          if (blocks.isNotEmpty && blocks.first is DocParagraph) {
            final first = blocks.first as DocParagraph;
            blocks[0] = first.withInlines([mark, DocText(' '), ...first.inlines]);
          }
          if (isEnd) {
            endnotes.add(DocNote(label, blocks));
          } else {
            footnotes[label] = blocks;
          }
          out.add((tp.copy()..position = 'super').toText(label, link, footnote: isEnd ? null : label));
        case 'annotation':
          final author = node.child('creator')?.innerText;
          final blocks = this.blocks(node);
          final label = 'C${comments.length + 1}';
          comments.add(DocNote(label, blocks, author: author));
          out.add((tp.copy()
                ..position = 'super'
                ..color = const Color(0xFFC0504D))
              .toText(label, link));
        case 'bookmark':
        case 'bookmark-start':
        case 'bookmark-end':
        case 'soft-page-break':
        case 'annotation-end':
        case 'deletion':
          break;
        default:
          _inlines(node, tp, link, out);
      }
    }
  }

  void _frame(XmlElement frame, List<DocInline> out) {
    final w = odfLength(frame.attr('width')) ?? 200;
    final h = odfLength(frame.attr('height')) ?? 150;
    final img = frame.child('image');
    if (img != null) {
      final href = img.attr('href') ?? '';
      out.add(DocImage(
          isRenderableImage(href) ? pkg.bytes(href) : null, w, h));
      return;
    }
    final obj = frame.child('object');
    if (obj != null) {
      ChartData? chart;
      try {
        final href = obj.attr('href');
        if (href != null) chart = parseOdfChart(pkg, href);
      } catch (_) {}
      if (chart != null) {
        out.add(DocChart(chart, w, h));
        return;
      }
    }
    final box = frame.child('text-box');
    if (box != null) {
      // Isi text box ditampilkan inline sebagai teks
      final inner = blocks(box);
      for (final b in inner.whereType<DocParagraph>()) {
        out.addAll(b.inlines);
        out.add(DocText('\n'));
      }
    }
  }

  DocTable _table(XmlElement table) {
    final widths = <double>[];
    void columns(XmlElement parent) {
      for (final c in parent.childElements) {
        if (c.localName == 'table-column') {
          final rep = int.tryParse(c.attr('number-columns-repeated') ?? '') ?? 1;
          final props = styles.props('table-column', c.attr('style-name'),
              'table-column-properties');
          final w = props.isEmpty ? null : odfLength(props.last.attr('column-width'));
          for (var i = 0; i < rep && widths.length < 256; i++) {
            widths.add(w ?? 72);
          }
        } else if (c.localName == 'table-columns' ||
            c.localName == 'table-header-columns' ||
            c.localName == 'table-column-group') {
          columns(c);
        }
      }
    }

    columns(table);

    var borders = false;
    final rows = <DocTableRow>[];
    void rowsOf(XmlElement parent, {bool header = false}) {
      for (final r in parent.childElements) {
        if (r.localName == 'table-header-rows') {
          rowsOf(r, header: true);
        } else if (r.localName == 'table-rows' || r.localName == 'table-row-group') {
          rowsOf(r, header: header);
        } else if (r.localName == 'table-row') {
          final cells = <DocTableCell>[];
          var skip = 0;
          for (final c in r.childElements) {
            if (c.localName == 'covered-table-cell') {
              if (skip > 0) {
                skip--;
              } else {
                cells.add(DocTableCell([], mergedContinue: true));
              }
              continue;
            }
            if (c.localName != 'table-cell') continue;
            final span = int.tryParse(c.attr('number-columns-spanned') ?? '') ?? 1;
            skip = span - 1;
            final props = styles.props(
                'table-cell', c.attr('style-name'), 'table-cell-properties');
            Color? bg;
            for (final p in props) {
              bg = parseHexColor(p.attr('background-color')) ?? bg;
              final b = p.attr('border') ?? p.attr('border-top') ?? p.attr('border-bottom');
              if (b != null && b != 'none') borders = true;
            }
            cells.add(DocTableCell(blocks(c), colSpan: span, shading: bg));
          }
          rows.add(DocTableRow(cells, header: header));
        }
      }
    }

    rowsOf(table);
    if (widths.isEmpty) {
      final n = rows.fold<int>(0, (m, r) => r.cells.length > m ? r.cells.length : m);
      widths.addAll(List.filled(n, 72));
    }
    return DocTable(columnWidths: widths, rows: rows, borders: borders);
  }
}

class _ListCtx {
  final String? styleName;
  final int level;
  final OdfStyles styles;
  int counter = 0;
  _ListCtx(this.styleName, this.level, this.styles);

  String label() {
    final ls = styleName == null ? null : styles.listStyles[styleName];
    XmlElement? lvl;
    if (ls != null) {
      for (final e in ls.childElements) {
        if (int.tryParse(e.attr('level') ?? '') == level + 1) lvl = e;
      }
    }
    if (lvl == null || lvl.localName == 'list-level-style-bullet') {
      return sanitizeBullet(lvl?.attr('bullet-char'), level);
    }
    final fmt = lvl.attr('num-format') ?? '1';
    if (fmt.isEmpty) return '';
    final prefix = lvl.attr('num-prefix') ?? '';
    final suffix = lvl.attr('num-suffix') ?? '.';
    return '$prefix${formatListNumber(fmt, counter)}$suffix';
  }
}

class _OdtPara {
  TextAlign align = TextAlign.left;
  double marginLeft = 0;
  double marginRight = 0;
  double textIndent = 0;
  double marginTop = 0;
  double marginBottom = 0;
  double? lineHeight;
  Color? background;
  bool breakBefore = false;
  bool keepNext = false;

  void apply(XmlElement e) {
    final a = e.attr('text-align');
    if (a != null) {
      align = switch (a) {
        'center' => TextAlign.center,
        'end' || 'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      };
    }
    marginLeft = odfLength(e.attr('margin-left')) ?? marginLeft;
    marginRight = odfLength(e.attr('margin-right')) ?? marginRight;
    textIndent = odfLength(e.attr('text-indent')) ?? textIndent;
    marginTop = odfLength(e.attr('margin-top')) ?? marginTop;
    marginBottom = odfLength(e.attr('margin-bottom')) ?? marginBottom;
    final lh = e.attr('line-height');
    if (lh != null && lh.endsWith('%')) {
      lineHeight = (double.tryParse(lh.replaceAll('%', '')) ?? 100) / 100;
    }
    final bg = e.attr('background-color');
    if (bg != null) background = bg == 'transparent' ? null : parseHexColor(bg);
    if (e.attr('break-before') == 'page') breakBefore = true;
    if (e.attr('keep-with-next') == 'always') keepNext = true;
  }
}

class _OdtText {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  bool caps = false;
  double? size;
  Color? color;
  Color? highlight;
  String? font;
  String? position;

  _OdtText copy() => _OdtText()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..caps = caps
    ..size = size
    ..color = color
    ..highlight = highlight
    ..font = font
    ..position = position;

  void apply(XmlElement e) {
    final w = e.attrNs('fo', 'font-weight');
    if (w != null) bold = w == 'bold' || (int.tryParse(w) ?? 400) >= 600;
    final st = e.attrNs('fo', 'font-style');
    if (st != null) italic = st == 'italic' || st == 'oblique';
    final u = e.attr('text-underline-style');
    if (u != null) underline = u != 'none';
    final lt = e.attr('text-line-through-style');
    if (lt != null) strike = lt != 'none';
    final fs = e.attrNs('fo', 'font-size');
    if (fs != null) {
      if (fs.endsWith('%')) {
        final pct = double.tryParse(fs.replaceAll('%', ''));
        if (pct != null) size = (size ?? 12) * pct / 100;
      } else {
        size = odfLength(fs) ?? size;
      }
    }
    final c = e.attrNs('fo', 'color');
    if (c != null) color = parseHexColor(c);
    final bg = e.attrNs('fo', 'background-color');
    if (bg != null) highlight = bg == 'transparent' ? null : parseHexColor(bg);
    font = e.attr('font-name') ?? e.attrNs('fo', 'font-family') ?? font;
    final pos = e.attr('text-position');
    if (pos != null) position = pos;
    if (e.attrNs('fo', 'text-transform') == 'uppercase') caps = true;
  }

  DocText toText(String t, String? link, {String? footnote}) => DocText(
        t,
        bold: bold,
        italic: italic,
        underline: underline || link != null,
        strike: strike,
        fontSize: size,
        color: color ?? (link != null ? const Color(0xFF0563C1) : null),
        highlight: highlight,
        fontFamily: font,
        superscript: position?.startsWith('super') ?? false,
        subscript: position?.startsWith('sub') ?? false,
        allCaps: caps,
        link: link,
        footnote: footnote,
      );
}
