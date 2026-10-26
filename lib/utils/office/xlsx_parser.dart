import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'chart_parser.dart' show parseOoxmlChart, readThemeScheme;
import 'fast_xml.dart';
import 'office_common.dart';
import 'sheet_model.dart';

/// Parser XLSX: nilai hasil rumus (cache), format angka/tanggal, style sel
/// (font, isi, border, perataan), warna tema, merge, lebar kolom & tinggi baris.
SheetBook parseXlsx(Uint8List data) {
  final pkg = OfficePackage(data);
  final wb = pkg.xml('xl/workbook.xml');
  if (wb == null) throw const FormatException('Not a valid Excel workbook');
  final rels = pkg.rels('xl/workbook.xml');
  final date1904 = wb.first('workbookPr')?.attr('date1904');
  final ctx = _XlsxContext(pkg, date1904 == '1' || date1904 == 'true');

  final sheets = <SheetData>[];
  for (final s in wb.descendantElements.where((e) => e.localName == 'sheet')) {
    // Sheet tersembunyi tetap dimuat (ditandai) agar datanya bisa dilihat
    final hidden = s.attr('state') == 'hidden' || s.attr('state') == 'veryHidden';
    final path = rels[s.attr('id')];
    if (path == null) continue;
    // Sheet bisa berukuran puluhan MB: dipindai langsung tanpa DOM
    final xml = pkg.text(path);
    if (xml == null || !xml.contains('sheetData')) continue; // chartsheet
    sheets.add(ctx.sheet(s.attr('name') ?? 'Sheet', xml, path, hidden: hidden));
  }
  return SheetBook(sheets);
}

class _XlsxContext {
  final OfficePackage pkg;
  final bool date1904;
  final List<String> shared = [];
  final List<Color> theme = [];
  final Map<int, String> numFmts = {};
  final List<_Xf> xfs = [];

  _XlsxContext(this.pkg, this.date1904) {
    _loadTheme();
    _loadShared();
    _loadStyles();
  }

  void _loadTheme() {
    final doc = pkg.xml('xl/theme/theme1.xml');
    final scheme = doc?.first('clrScheme');
    if (scheme == null) return;
    final byName = <String, Color>{};
    for (final e in scheme.childElements) {
      final c = e.childElements.firstOrNull;
      if (c == null) continue;
      final color = c.localName == 'sysClr'
          ? sysColor(c)
          : parseHexColor(c.attr('val'));
      if (color != null) byName[e.localName] = color;
    }
    // Indeks tema Excel: 0=lt1, 1=dk1, 2=lt2, 3=dk2, lalu accent1..6, hlink
    for (final n in [
      'lt1', 'dk1', 'lt2', 'dk2', 'accent1', 'accent2', 'accent3', //
      'accent4', 'accent5', 'accent6', 'hlink', 'folHlink'
    ]) {
      theme.add(byName[n] ?? kBlack);
    }
  }

  void _loadShared() {
    final xml = pkg.text('xl/sharedStrings.xml');
    if (xml == null) return;
    // <si> berisi <t> langsung atau beberapa <r><t>; teks phonetic (<rPh>) dilewati
    StringBuffer? cur;
    var inPhonetic = false;
    for (final tag in scanTags(xml)) {
      switch (tag.name) {
        case 'si':
          if (tag.closing) {
            shared.add(cur?.toString() ?? '');
            cur = null;
          } else if (tag.selfClosing) {
            shared.add('');
          } else {
            cur = StringBuffer();
          }
        case 'rPh':
          inPhonetic = !tag.closing && !tag.selfClosing;
        case 't':
          if (!tag.closing && !inPhonetic) cur?.write(innerTextOf(xml, tag));
      }
    }
  }

  Color? color(XmlElement? e) {
    if (e == null) return null;
    Color? c;
    if (e.attr('rgb') != null) {
      c = parseHexColor(e.attr('rgb'));
    } else if (e.attr('theme') != null) {
      final i = int.tryParse(e.attr('theme')!) ?? -1;
      if (i >= 0 && i < theme.length) c = theme[i];
    } else if (e.attr('indexed') != null) {
      final i = int.tryParse(e.attr('indexed')!) ?? -1;
      if (i >= 0 && i < _indexed.length) c = Color(_indexed[i]);
    }
    if (c == null) return null;
    final tint = double.tryParse(e.attr('tint') ?? '');
    return tint == null ? c : applyTint(c, tint);
  }

  void _loadStyles() {
    final doc = pkg.xml('xl/styles.xml');
    if (doc == null) return;
    for (final f in doc.descendantElements.where((e) => e.localName == 'numFmt')) {
      final id = int.tryParse(f.attr('numFmtId') ?? '');
      if (id != null) numFmts[id] = f.attr('formatCode') ?? 'General';
    }

    final fonts = <_Font>[];
    for (final f in doc.first('fonts')?.kids('font') ?? <XmlElement>[]) {
      final u = f.child('u');
      fonts.add(_Font(
        bold: f.toggle('b') ?? false,
        italic: f.toggle('i') ?? false,
        underline: u != null && (u.attr('val') ?? 'single') != 'none',
        strike: f.toggle('strike') ?? false,
        size: double.tryParse(f.child('sz')?.attr('val') ?? '') ?? 11,
        name: f.child('name')?.attr('val'),
        color: color(f.child('color')),
      ));
    }

    final fills = <Color?>[];
    for (final f in doc.first('fills')?.kids('fill') ?? <XmlElement>[]) {
      final p = f.child('patternFill');
      final g = f.child('gradientFill');
      if (p != null && (p.attr('patternType') ?? 'none') != 'none') {
        fills.add(color(p.child('fgColor')) ?? color(p.child('bgColor')));
      } else if (g != null) {
        fills.add(color(g.descendant('color')));
      } else {
        fills.add(null);
      }
    }

    final borders = <List<Color?>>[];
    for (final b in doc.first('borders')?.kids('border') ?? <XmlElement>[]) {
      Color? side(String name) {
        final e = b.child(name);
        if (e == null || (e.attr('style') ?? 'none') == 'none') return null;
        return color(e.child('color')) ?? kBlack;
      }

      borders.add([
        side('left') ?? side('start'),
        side('right') ?? side('end'),
        side('top'),
        side('bottom'),
      ]);
    }

    for (final xf in doc.first('cellXfs')?.kids('xf') ?? <XmlElement>[]) {
      T? at<T>(List<T> list, String attr) {
        final i = int.tryParse(xf.attr(attr) ?? '');
        return i != null && i >= 0 && i < list.length ? list[i] : null;
      }

      final font = at(fonts, 'fontId') ?? _Font();
      final border = at(borders, 'borderId') ?? const <Color?>[null, null, null, null];
      final al = xf.child('alignment');
      final style = SheetCellStyle(
        bold: font.bold,
        italic: font.italic,
        underline: font.underline,
        strike: font.strike,
        fontSize: font.size,
        font: font.name,
        color: font.color,
        fill: at<Color?>(fills, 'fillId'),
        align: switch (al?.attr('horizontal')) {
          'center' || 'centerContinuous' => TextAlign.center,
          'right' => TextAlign.right,
          'left' || 'fill' => TextAlign.left,
          'justify' || 'distributed' => TextAlign.justify,
          _ => null,
        },
        vAlign: switch (al?.attr('vertical')) {
          'top' => VAlign.top,
          'center' => VAlign.center,
          _ => VAlign.bottom,
        },
        wrap: al?.attr('wrapText') == '1' || al?.attr('wrapText') == 'true',
        borderLeft: border[0],
        borderRight: border[1],
        borderTop: border[2],
        borderBottom: border[3],
      );
      xfs.add(_Xf(int.tryParse(xf.attr('numFmtId') ?? '') ?? 0, style));
    }
  }

  SheetData sheet(String name, String xml, String path, {bool hidden = false}) {
    var defaultColWidth = _colPx(8.71);
    var defaultRowHeight = 20.0;
    String? grid;
    final colWidths = <int, double>{};
    final cells = <int, Map<int, SheetCell>>{};
    final rowHeights = <int, double>{};
    final merges = <CellRange>[];
    var maxRow = 0, maxCol = 0;
    var nextRow = 0, r = 0, nextCol = 0;
    var sawView = false;

    // Sel yang sedang dibaca
    String? cellRef, cellStyle, cellType, cellValue, cellFormula;
    StringBuffer? inline;
    var inCell = false, inInline = false, inPhonetic = false;

    void finishCell() {
      final pos = cellRef == null ? null : parseCellRef(cellRef!);
      final col = pos?.$2 ?? nextCol;
      nextCol = col + 1;
      final xfIdx = int.tryParse(cellStyle ?? '') ?? 0;
      final xf = xfIdx < xfs.length ? xfs[xfIdx] : null;
      final style = xf?.style ?? SheetCellStyle.plain;
      final (text, isNum) = _value(cellType ?? 'n', cellValue, inline?.toString(), xf?.numFmt ?? 0);
      final visible = text.isNotEmpty || style.fill != null || _hasBorder(style);
      if (visible) {
        (cells[r] ??= {})[col] = SheetCell(text,
            isNumber: isNum,
            style: style,
            content: _content(cellType ?? 'n', cellValue, cellFormula, text, xf?.numFmt ?? 0));
        maxRow = math.max(maxRow, r + 1);
        maxCol = math.max(maxCol, col + 1);
      }
      cellRef = cellStyle = cellType = cellValue = cellFormula = null;
      inline = null;
      inCell = false;
    }

    for (final tag in scanTags(xml)) {
      switch (tag.name) {
        case 'sheetFormatPr':
          final baseW = double.tryParse(tag.attr('baseColWidth') ?? '') ?? 8;
          final defW = double.tryParse(tag.attr('defaultColWidth') ?? '');
          defaultColWidth = defW != null ? _colPx(defW) : _colPx(baseW + 0.71);
          defaultRowHeight = (double.tryParse(tag.attr('defaultRowHeight') ?? '') ?? 15) * 4 / 3;
        case 'sheetView':
          if (!sawView && !tag.closing) {
            grid = tag.attr('showGridLines');
            sawView = true;
          }
        case 'col':
          if (tag.closing) break;
          final min = int.tryParse(tag.attr('min') ?? '') ?? 1;
          final max = math.min(int.tryParse(tag.attr('max') ?? '') ?? min, 16384);
          final hidden = tag.attr('hidden') == '1' || tag.attr('hidden') == 'true';
          final w = double.tryParse(tag.attr('width') ?? '');
          if (max - min > 1000 && !hidden && w == null) break;
          for (var c = min; c <= max && c - min < 1000; c++) {
            if (hidden) {
              colWidths[c - 1] = 0;
            } else if (w != null) {
              colWidths[c - 1] = _colPx(w);
            }
          }
        case 'row':
          if (tag.closing) break;
          r = (int.tryParse(tag.attr('r') ?? '') ?? (nextRow + 1)) - 1;
          nextRow = r + 1;
          nextCol = 0;
          final hidden = tag.attr('hidden') == '1' || tag.attr('hidden') == 'true';
          final ht = double.tryParse(tag.attr('ht') ?? '');
          if (hidden) {
            rowHeights[r] = 0;
          } else if (ht != null) {
            rowHeights[r] = ht * 4 / 3;
          }
        case 'c':
          if (tag.closing) {
            if (inCell) finishCell();
          } else {
            cellRef = tag.attr('r');
            cellStyle = tag.attr('s');
            cellType = tag.attr('t');
            inCell = true;
            if (tag.selfClosing) finishCell();
          }
        case 'v':
          if (inCell && !tag.closing) cellValue = innerTextOf(xml, tag);
        case 'f':
          if (inCell && !tag.closing && !tag.selfClosing) {
            final f = innerTextOf(xml, tag);
            if (f.isNotEmpty) cellFormula = f;
          }
        case 'is':
          inInline = !tag.closing && !tag.selfClosing;
          if (inInline) inline = StringBuffer();
        case 'rPh':
          inPhonetic = !tag.closing && !tag.selfClosing;
        case 't':
          if (inInline && !inPhonetic && !tag.closing) inline?.write(innerTextOf(xml, tag));
        case 'mergeCell':
          final parts = (tag.attr('ref') ?? '').split(':');
          if (parts.length != 2) break;
          final a = parseCellRef(parts[0]);
          final b = parseCellRef(parts[1]);
          if (a == null || b == null) break;
          merges.add(CellRange(a.$1, a.$2, b.$1, b.$2));
          maxRow = math.max(maxRow, b.$1 + 1);
          maxCol = math.max(maxCol, b.$2 + 1);
      }
    }

    final drawings = _drawings(path);
    for (final d in drawings) {
      maxRow = math.max(maxRow, (d.toRow ?? d.fromRow) + 1);
      maxCol = math.max(maxCol, (d.toCol ?? d.fromCol) + 1);
    }

    return SheetData(
      name: name,
      cells: cells,
      rowCount: maxRow,
      colCount: maxCol,
      colWidths: colWidths,
      rowHeights: rowHeights,
      defaultColWidth: defaultColWidth,
      defaultRowHeight: defaultRowHeight,
      merges: merges,
      showGrid: !(grid == '0' || grid == 'false'),
      drawings: drawings,
      hidden: hidden,
    );
  }

  /// Gambar & chart dari xl/drawings/drawingN.xml milik sheet ini.
  List<SheetDrawing> _drawings(String sheetPath) {
    final drawingPath =
        pkg.rels(sheetPath).values.where((p) => p.contains('/drawings/') && p.endsWith('.xml')).firstOrNull;
    final doc = drawingPath == null ? null : pkg.xml(drawingPath);
    if (doc == null) return const [];
    final rels = pkg.rels(drawingPath!);
    final scheme = readThemeScheme(pkg.xml('xl/theme/theme1.xml'));
    double px(String? emu) => (double.tryParse(emu ?? '') ?? 0) / 9525;

    final out = <SheetDrawing>[];
    for (final a in doc.rootElement.childElements) {
      if (!a.localName.endsWith('Anchor')) continue;
      Uint8List? image;
      ChartData? chart;
      final blip = a.descendant('blip');
      final chartRef = a.descendant('graphicData')?.child('chart');
      if (chartRef != null) {
        final cdoc = pkg.xml(rels[chartRef.attrNs('r', 'id')] ?? '');
        try {
          chart = cdoc == null ? null : parseOoxmlChart(cdoc, scheme);
        } catch (_) {}
      } else if (blip != null) {
        final p = rels[blip.attr('embed')];
        if (p != null && isRenderableImage(p)) image = pkg.bytes(p);
      }
      if (image == null && chart == null) continue;

      final from = a.child('from');
      final to = a.child('to');
      final ext = a.child('ext');
      final pos = a.child('pos');
      int cell(XmlElement? e, String n) => int.tryParse(e?.child(n)?.innerText ?? '') ?? 0;
      out.add(SheetDrawing(
        fromRow: cell(from, 'row'),
        fromCol: cell(from, 'col'),
        fromRowOff: from != null ? px(from.child('rowOff')?.innerText) : px(pos?.attr('y')),
        fromColOff: from != null ? px(from.child('colOff')?.innerText) : px(pos?.attr('x')),
        toRow: to == null ? null : cell(to, 'row'),
        toCol: to == null ? null : cell(to, 'col'),
        toRowOff: px(to?.child('rowOff')?.innerText),
        toColOff: px(to?.child('colOff')?.innerText),
        width: px(ext?.attr('cx')),
        height: px(ext?.attr('cy')),
        image: image,
        chart: chart,
      ));
    }
    return out;
  }

  static bool _hasBorder(SheetCellStyle s) =>
      s.borderLeft != null ||
      s.borderRight != null ||
      s.borderTop != null ||
      s.borderBottom != null;

  static double _colPx(double chars) => (chars * 7 + 5).roundToDouble();

  /// Isi formula bar seperti Excel: rumus, atau nilai lengkap tanpa
  /// pembulatan tampilan (tanggal & persen tetap dalam bentuk yang terbaca).
  String? _content(String t, String? v, String? formula, String text, int numFmt) {
    if (formula != null) return '=$formula';
    if (t != 'n' || v == null) return null;
    final n = double.tryParse(v);
    if (n == null) return null;
    final code = numFmts[numFmt] ?? _builtinFormats[numFmt] ?? 'General';
    final sec = _splitSections(code).first;
    if (_isDateFormat(sec)) return null; // tanggal: tampilan sudah lengkap
    final full = _fullPrecision(n);
    if (_stripLiterals(sec).contains('%')) return '${_fullPrecision(n * 100)}%';
    return full == text ? null : full;
  }

  /// Hingga 15 digit signifikan (presisi Excel), tanpa nol di belakang.
  static String _fullPrecision(double n) {
    if (n == n.truncateToDouble() && n.abs() < 1e15) return n.toInt().toString();
    final s = n.toStringAsPrecision(15);
    if (s.contains('e')) return s;
    return _trimZeros(s);
  }

  (String, bool) _value(String t, String? v, String? inlineText, int numFmt) {
    switch (t) {
      case 's':
        final i = int.tryParse(v ?? '');
        return (i != null && i < shared.length ? shared[i] : '', false);
      case 'inlineStr':
        return (inlineText ?? '', false);
      case 'str':
        return (v ?? '', false);
      case 'b':
        return (v == '1' ? 'TRUE' : 'FALSE', false);
      case 'e':
        return (v ?? '#ERROR', false);
      case 'd':
        return (v ?? '', true);
      default:
        if (v == null || v.isEmpty) return ('', false);
        final n = double.tryParse(v);
        if (n == null) return (v, false);
        final code = numFmts[numFmt] ?? _builtinFormats[numFmt] ?? 'General';
        return (formatExcelNumber(n, code, date1904: date1904), true);
    }
  }
}

class _Font {
  final bool bold, italic, underline, strike;
  final double size;
  final String? name;
  final Color? color;
  _Font({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.size = 11,
    this.name,
    this.color,
  });
}

class _Xf {
  final int numFmt;
  final SheetCellStyle style;
  _Xf(this.numFmt, this.style);
}

const _builtinFormats = {
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'dd/mm/yyyy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'dd/mm/yyyy h:mm',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;[Red](#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;[Red](#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mmss.0',
  48: '##0.0E+0',
  49: '@',
};

// ── Format angka Excel ───────────────────────────────────────────────────────

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December'
];
const _days = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

/// Format nilai numerik sesuai kode format Excel (subset yang umum dipakai).
String formatExcelNumber(double v, String code, {bool date1904 = false}) {
  if (code == 'General' || code.isEmpty) return generalNumber(v);
  if (code == '@') return generalNumber(v);

  final sections = _splitSections(code);
  var sec = sections[0];
  var value = v;
  if (v < 0 && sections.length > 1 && sections[1].isNotEmpty) {
    sec = sections[1];
    value = -v;
  } else if (v == 0 && sections.length > 2 && sections[2].isNotEmpty) {
    sec = sections[2];
  }

  // Buang warna/kondisi [Red] [>=100], ambil simbol mata uang [$Rp-421]
  sec = sec.replaceAllMapped(RegExp(r'\[\$([^\]-]*)(-[^\]]*)?\]'), (m) => '"${m.group(1)}"');
  sec = sec.replaceAll(RegExp(r'\[(?!h\]|hh\]|m\]|mm\]|s\]|ss\])[^\]]*\]', caseSensitive: false), '');

  if (_isDateFormat(sec)) return _formatDate(value, sec, date1904);
  if (sec.toLowerCase() == 'general') return generalNumber(value);
  return _formatNumeric(value, sec);
}

List<String> _splitSections(String code) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQuote = false;
  for (var i = 0; i < code.length; i++) {
    final ch = code[i];
    if (ch == '"') inQuote = !inQuote;
    if (ch == '\\' && i + 1 < code.length) {
      sb.write(ch);
      sb.write(code[++i]);
      continue;
    }
    if (ch == ';' && !inQuote) {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out;
}

String _stripLiterals(String s) => s
    .replaceAll(RegExp(r'"[^"]*"'), '')
    .replaceAll(RegExp(r'\\.'), '')
    .replaceAll(RegExp(r'[_*].'), '');

bool _isDateFormat(String sec) {
  final s = _stripLiterals(sec).toLowerCase();
  if (s.contains('0') || s.contains('#')) {
    // "mm:ss.0" tetap tanggal/waktu
    if (!RegExp(r'[hs]').hasMatch(s)) return false;
  }
  return RegExp(r'[ymdhs]').hasMatch(s);
}

/// Format "General" Excel (maks. ~10 digit signifikan). Tanpa regex karena
/// dipanggil untuk setiap sel angka.
String generalNumber(double v) {
  if (v.isNaN || v.isInfinite) return v.toString();
  if (v == v.truncateToDouble() && v.abs() < 1e11) return v.toInt().toString();
  final a = v.abs();
  if (a >= 1e11 || a < 1e-9) {
    // 1.23450e+12 → 1.2345E+12
    final s = v.toStringAsExponential(5);
    final e = s.indexOf('e');
    return '${_trimZeros(s.substring(0, e))}E${s.substring(e + 1)}';
  }
  final s = v.toStringAsPrecision(10);
  if (s.contains('e')) return s;
  return s.contains('.') ? _trimZeros(s) : s;
}

String _trimZeros(String s) {
  if (!s.contains('.')) return s;
  var end = s.length;
  while (end > 0 && s.codeUnitAt(end - 1) == 0x30) {
    end--;
  }
  if (end > 0 && s.codeUnitAt(end - 1) == 0x2E) end--;
  return s.substring(0, end);
}

String _formatNumeric(double v, String sec) {
  // Pisahkan literal (prefix/suffix) dari placeholder angka
  final prefix = StringBuffer();
  final suffix = StringBuffer();
  final pattern = StringBuffer();
  var seenNumber = false;
  var percent = false;

  for (var i = 0; i < sec.length; i++) {
    final ch = sec[i];
    String? lit;
    if (ch == '"') {
      final end = sec.indexOf('"', i + 1);
      lit = sec.substring(i + 1, end < 0 ? sec.length : end);
      i = end < 0 ? sec.length : end;
    } else if (ch == '\\' && i + 1 < sec.length) {
      lit = sec[++i];
    } else if (ch == '_' && i + 1 < sec.length) {
      i++;
      lit = ' ';
    } else if (ch == '*' && i + 1 < sec.length) {
      i++;
      lit = '';
    } else if ('0#?.,'.contains(ch) || (ch == 'E' || ch == 'e') && seenNumber) {
      pattern.write(ch);
      seenNumber = true;
      if ((ch == 'E' || ch == 'e') && i + 1 < sec.length && '+-'.contains(sec[i + 1])) {
        pattern.write(sec[++i]);
      }
      continue;
    } else if (ch == '%') {
      percent = true;
      lit = '%';
    } else {
      lit = ch;
    }
    (seenNumber ? suffix : prefix).write(lit);
  }

  final p = pattern.toString();
  if (p.isEmpty) return '$prefix$suffix'.trim().isEmpty ? generalNumber(v) : '$prefix$suffix';
  var value = percent ? v * 100 : v;

  final eIdx = p.toUpperCase().indexOf('E');
  if (eIdx >= 0) {
    final mant = p.substring(0, eIdx);
    final dec = mant.contains('.') ? mant.split('.')[1].length : 0;
    final s = value.toStringAsExponential(dec).toUpperCase().replaceFirstMapped(
        RegExp(r'E([+-])(\d)$'), (m) => 'E${m.group(1)}0${m.group(2)}');
    return '$prefix$s$suffix';
  }

  final dot = p.indexOf('.');
  var intPart = dot >= 0 ? p.substring(0, dot) : p;
  final decPart = dot >= 0 ? p.substring(dot + 1).replaceAll(',', '') : '';
  // Koma di akhir pola = bagi 1000 per koma
  while (intPart.endsWith(',')) {
    value /= 1000;
    intPart = intPart.substring(0, intPart.length - 1);
  }
  final thousands = intPart.contains(',');
  final minInt = '0'.allMatches(intPart).length;
  final minDec = '0'.allMatches(decPart).length;
  final maxDec = decPart.length;

  var s = value.abs().toStringAsFixed(maxDec);
  var ip = s.split('.')[0];
  var dp = s.contains('.') ? s.split('.')[1] : '';
  while (dp.length > minDec && dp.endsWith('0')) {
    dp = dp.substring(0, dp.length - 1);
  }
  if (ip == '0' && minInt == 0) ip = '';
  ip = ip.padLeft(minInt, '0');
  if (thousands) {
    ip = ip.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
  final sign = v < 0 && value.abs() > 0 ? '-' : '';
  final num = dp.isEmpty ? ip : '$ip.$dp';
  return '$sign$prefix$num$suffix';
}

String _formatDate(double serial, String sec, bool date1904) {
  final base = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
  final days = serial.floor();
  final ms = ((serial - days) * 86400000).round();
  final dt = base.add(Duration(days: days, milliseconds: ms));
  final elapsedHours = (serial * 24).floor();

  final hasAmPm = sec.toUpperCase().contains('AM/PM') || sec.toUpperCase().contains('A/P');
  final tokens = RegExp(r'"[^"]*"|\\.|\[h+\]|\[m+\]|\[s+\]|AM/PM|A/P|y+|m+|d+|h+|s+|0+|.',
          caseSensitive: false)
      .allMatches(sec)
      .map((m) => m.group(0)!)
      .toList();

  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    final lower = tok.toLowerCase();
    String two(int n) => n.toString().padLeft(2, '0');

    if (tok.startsWith('"')) {
      out.write(tok.substring(1, tok.length - 1));
    } else if (tok.startsWith('\\')) {
      out.write(tok.substring(1));
    } else if (lower.startsWith('[h')) {
      out.write(elapsedHours);
    } else if (lower.startsWith('[m')) {
      out.write((serial * 1440).floor());
    } else if (lower.startsWith('[s')) {
      out.write((serial * 86400).floor());
    } else if (lower == 'am/pm') {
      out.write(dt.hour < 12 ? 'AM' : 'PM');
    } else if (lower == 'a/p') {
      out.write(dt.hour < 12 ? 'A' : 'P');
    } else if (lower.startsWith('y')) {
      out.write(lower.length <= 2 ? two(dt.year % 100) : dt.year);
    } else if (lower.startsWith('d')) {
      out.write(switch (lower.length) {
        1 => '${dt.day}',
        2 => two(dt.day),
        3 => _days[dt.weekday - 1].substring(0, 3),
        _ => _days[dt.weekday - 1],
      });
    } else if (lower.startsWith('h')) {
      var h = dt.hour;
      if (hasAmPm) h = h % 12 == 0 ? 12 : h % 12;
      out.write(lower.length >= 2 ? two(h) : '$h');
    } else if (lower.startsWith('s')) {
      out.write(lower.length >= 2 ? two(dt.second) : '${dt.second}');
    } else if (lower.startsWith('m')) {
      // "m" setelah jam atau sebelum detik = menit
      bool isMinute() {
        for (var j = i - 1; j >= 0; j--) {
          final t = tokens[j].toLowerCase();
          if (t.startsWith('h') || t.startsWith('[h')) return true;
          if (RegExp(r'^[ymd]').hasMatch(t)) break;
        }
        for (var j = i + 1; j < tokens.length; j++) {
          final t = tokens[j].toLowerCase();
          if (t.startsWith('s')) return true;
          if (RegExp(r'^[ymdh]').hasMatch(t)) break;
        }
        return false;
      }

      if (lower.length <= 2 && isMinute()) {
        out.write(lower.length == 2 ? two(dt.minute) : '${dt.minute}');
      } else {
        out.write(switch (lower.length) {
          1 => '${dt.month}',
          2 => two(dt.month),
          3 => _months[dt.month - 1].substring(0, 3),
          5 => _months[dt.month - 1][0],
          _ => _months[dt.month - 1],
        });
      }
    } else if (tok.startsWith('0')) {
      // pecahan detik: ss.0
      final frac = (serial * 86400) % 1;
      out.write(frac.toStringAsFixed(tok.length).substring(2));
    } else {
      out.write(tok);
    }
  }
  return out.toString();
}

/// Palet warna terindeks standar Excel (indeks 0–63).
const _indexed = [
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00, //
  0xFFFF00FF, 0xFF00FFFF, 0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00,
  0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF, 0xFF800000, 0xFF008000,
  0xFF000080, 0xFF808000, 0xFF800080, 0xFF008080, 0xFFC0C0C0, 0xFF808080,
  0xFF9999FF, 0xFF993366, 0xFFFFFFCC, 0xFFCCFFFF, 0xFF660066, 0xFFFF8080,
  0xFF0066CC, 0xFFCCCCFF, 0xFF000080, 0xFFFF00FF, 0xFFFFFF00, 0xFF00FFFF,
  0xFF800080, 0xFF800000, 0xFF008080, 0xFF0000FF, 0xFF00CCFF, 0xFFCCFFFF,
  0xFFCCFFCC, 0xFFFFFF99, 0xFF99CCFF, 0xFFFF99CC, 0xFFCC99FF, 0xFFFFCC99,
  0xFF3366FF, 0xFF33CCCC, 0xFF99CC00, 0xFFFFCC00, 0xFFFF9900, 0xFFFF6600,
  0xFF666699, 0xFF969696, 0xFF003366, 0xFF339966, 0xFF003300, 0xFF333300,
  0xFF993300, 0xFF993366, 0xFF333399, 0xFF333333,
];
