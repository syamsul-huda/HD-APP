import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'chart_parser.dart';
import 'odf_styles.dart';
import 'xlsx_parser.dart' show generalNumber;
import 'office_common.dart';
import 'sheet_model.dart';

// Pengulangan berisi data disalin utuh (baris berulang berbagi map yang sama
// sehingga murah); batas ini hanya mencegah file rusak/ekstrem membuat
// jutaan entri. Baris/kolom berulang yang KOSONG tidak pernah disalin.
const _maxRepeatWithContent = 1048576;

/// Parser ODS (LibreOffice Calc). Teks tampilan sudah diformat di file,
/// jadi tidak perlu format angka sendiri.
SheetBook parseOds(Uint8List data) {
  final pkg = OfficePackage(data);
  final content = pkg.xml('content.xml');
  final body = content?.first('spreadsheet');
  if (body == null) throw const FormatException('Not a valid ODS spreadsheet');
  final styles = OdfStyles(pkg);
  final cellStyleCache = <String?, SheetCellStyle>{};

  SheetCellStyle cellStyle(String? name) => cellStyleCache.putIfAbsent(name, () {
        var bold = false, italic = false, underline = false, strike = false;
        double size = 10;
        String? font;
        Color? color, fill;
        TextAlign? align;
        var vAlign = VAlign.bottom;
        var wrap = false;
        Color? bl, br, bt, bb;
        Color? border(String? v) {
          if (v == null || v == 'none') return null;
          return parseHexColor(RegExp(r'#[0-9a-fA-F]{6}').stringMatch(v)) ?? kBlack;
        }

        for (final p in styles.props('table-cell', name, 'text-properties')) {
          final w = p.attrNs('fo', 'font-weight');
          if (w != null) bold = w == 'bold';
          final st = p.attrNs('fo', 'font-style');
          if (st != null) italic = st == 'italic';
          final u = p.attr('text-underline-style');
          if (u != null) underline = u != 'none';
          final lt = p.attr('text-line-through-style');
          if (lt != null) strike = lt != 'none';
          size = odfLength(p.attrNs('fo', 'font-size')) ?? size;
          font = p.attr('font-name') ?? font;
          color = parseHexColor(p.attrNs('fo', 'color')) ?? color;
        }
        for (final p in styles.props('table-cell', name, 'table-cell-properties')) {
          final bg = p.attr('background-color');
          if (bg != null) fill = bg == 'transparent' ? null : parseHexColor(bg);
          if (p.attr('wrap-option') == 'wrap') wrap = true;
          final va = p.attr('vertical-align');
          if (va == 'top') vAlign = VAlign.top;
          if (va == 'middle') vAlign = VAlign.center;
          final all = p.attr('border');
          if (all != null) bl = br = bt = bb = border(all);
          bl = border(p.attr('border-left')) ?? bl;
          br = border(p.attr('border-right')) ?? br;
          bt = border(p.attr('border-top')) ?? bt;
          bb = border(p.attr('border-bottom')) ?? bb;
        }
        for (final p in styles.props('table-cell', name, 'paragraph-properties')) {
          align = switch (p.attr('text-align')) {
            'center' => TextAlign.center,
            'end' || 'right' => TextAlign.right,
            'start' || 'left' => TextAlign.left,
            'justify' => TextAlign.justify,
            _ => align,
          };
        }
        return SheetCellStyle(
          bold: bold,
          italic: italic,
          underline: underline,
          strike: strike,
          fontSize: size,
          font: font,
          color: color,
          fill: fill,
          align: align,
          vAlign: vAlign,
          wrap: wrap,
          borderLeft: bl,
          borderRight: br,
          borderTop: bt,
          borderBottom: bb,
        );
      });

  final sheets = <SheetData>[];
  for (final table in body.kids('table')) {
    final colWidths = <int, double>{};
    final colDefaultStyle = <int, String?>{};
    var col = 0;
    void columns(XmlElement parent) {
      for (final c in parent.childElements) {
        if (c.localName == 'table-column') {
          final rep = int.tryParse(c.attr('number-columns-repeated') ?? '') ?? 1;
          final props = styles.props(
              'table-column', c.attr('style-name'), 'table-column-properties');
          final w = props.isEmpty ? null : odfLength(props.last.attr('column-width'));
          final hidden = c.attr('visibility') == 'collapse';
          for (var i = 0; i < rep && col < 1024; i++, col++) {
            if (hidden) {
              colWidths[col] = 0;
            } else if (w != null) {
              colWidths[col] = w * 4 / 3;
            }
            colDefaultStyle[col] = c.attr('default-cell-style-name');
          }
        } else if (c.localName.startsWith('table-column') ||
            c.localName == 'table-header-columns') {
          columns(c);
        }
      }
    }

    columns(table);

    final cells = <int, Map<int, SheetCell>>{};
    final rowHeights = <int, double>{};
    final merges = <CellRange>[];
    var maxRow = 0, maxCol = 0;
    var r = 0;

    void rows(XmlElement parent) {
      for (final row in parent.childElements) {
        if (row.localName == 'table-header-rows' ||
            row.localName == 'table-rows' ||
            row.localName == 'table-row-group') {
          rows(row);
          continue;
        }
        if (row.localName != 'table-row') continue;
        final rep = int.tryParse(row.attr('number-rows-repeated') ?? '') ?? 1;
        final rowProps = styles.props(
            'table-row', row.attr('style-name'), 'table-row-properties');
        final h = rowProps.isEmpty ? null : odfLength(rowProps.last.attr('row-height'));
        final hidden = row.attr('visibility') == 'collapse';

        // Baca sel satu kali, lalu salin untuk baris yang diulang
        final rowCells = <int, SheetCell>{};
        final rowMerges = <(int, int, int)>[]; // kolom, colSpan, rowSpan
        var c = 0;
        for (final cell in row.childElements) {
          final crep = int.tryParse(cell.attr('number-columns-repeated') ?? '') ?? 1;
          if (cell.localName == 'covered-table-cell') {
            c += crep;
            continue;
          }
          if (cell.localName != 'table-cell') continue;
          final text = cell
              .kids('p')
              .map((p) => _odfText(p))
              .join('\n');
          final type = cell.attr('value-type');
          final styleName = cell.attr('style-name') ?? colDefaultStyle[c];
          final style = cellStyle(styleName);
          final hasContent = text.isNotEmpty || style.fill != null;
          final cs = int.tryParse(cell.attr('number-columns-spanned') ?? '') ?? 1;
          final rs = int.tryParse(cell.attr('number-rows-spanned') ?? '') ?? 1;
          if (cs > 1 || rs > 1) rowMerges.add((c, cs, rs));
          if (hasContent) {
            // Formula bar: rumus asli atau nilai lengkap (tanpa pembulatan tampilan)
            final formula = cell.attr('formula');
            final raw = cell.attr('value') ?? cell.attr('date-value') ?? cell.attr('time-value');
            final content = formula != null
                ? '=${formula.replaceFirst(RegExp(r'^of:='), '').replaceAllMapped(RegExp(r'\[\.?([A-Z$]+[0-9$]+)(:\.?([A-Z$]+[0-9$]+))?\]'), (m) => m.group(3) == null ? m.group(1)! : '${m.group(1)}:${m.group(3)}')}'
                : (type == 'float' || type == 'currency') && raw != null && raw != text
                    ? raw
                    : type == 'percentage' && raw != null
                        ? '${generalNumber((double.tryParse(raw) ?? 0) * 100)}%'
                        : null;
            final sc = SheetCell(text,
                isNumber: type != null && type != 'string' && type != 'boolean',
                style: style,
                content: content);
            for (var i = 0; i < math.min(crep, 1024); i++) {
              rowCells[c + i] = sc;
            }
          }
          c += crep;
        }

        final copies = rowCells.isEmpty && rowMerges.isEmpty
            ? 0
            : math.min(rep, _maxRepeatWithContent);
        for (var i = 0; i < copies; i++) {
          if (rowCells.isNotEmpty) {
            cells[r + i] = rowCells;
            maxRow = math.max(maxRow, r + i + 1);
            maxCol = math.max(maxCol, rowCells.keys.reduce(math.max) + 1);
          }
          for (final (mc, cs, rs) in rowMerges) {
            merges.add(CellRange(r + i, mc, r + i + rs - 1, mc + cs - 1));
            maxRow = math.max(maxRow, r + i + rs);
            maxCol = math.max(maxCol, mc + cs);
          }
        }
        if (rep < 2000) {
          for (var i = 0; i < rep; i++) {
            if (hidden) {
              rowHeights[r + i] = 0;
            } else if (h != null) {
              rowHeights[r + i] = h * 4 / 3;
            }
          }
        }
        r += rep;
      }
    }

    rows(table);

    // Gambar & chart: posisi svg:x/y absolut dari pojok sheet
    final drawings = <SheetDrawing>[];
    for (final f in table.descendantElements.where((e) => e.localName == 'frame')) {
      final x = (odfLength(f.attr('x')) ?? 0) * 4 / 3;
      final y = (odfLength(f.attr('y')) ?? 0) * 4 / 3;
      final w = (odfLength(f.attr('width')) ?? 0) * 4 / 3;
      final h = (odfLength(f.attr('height')) ?? 0) * 4 / 3;
      if (w <= 0 || h <= 0) continue;
      ChartData? chart;
      Uint8List? image;
      final obj = f.child('object');
      if (obj?.attr('href') != null) {
        try {
          chart = parseOdfChart(pkg, obj!.attr('href')!);
        } catch (_) {}
      }
      final img = f.kids('image').where((i) => isRenderableImage(i.attr('href') ?? '')).firstOrNull;
      if (chart == null && img != null) image = pkg.bytes(img.attr('href')!);
      if (chart == null && image == null) continue;
      drawings.add(SheetDrawing(fromColOff: x, fromRowOff: y, width: w, height: h, image: image, chart: chart));
    }

    final tableStyle = styles.props('table', table.attr('style-name'), 'table-properties');
    sheets.add(SheetData(
      name: table.attr('name') ?? 'Sheet${sheets.length + 1}',
      hidden: tableStyle.any((p) => p.attr('display') == 'false'),
      cells: cells,
      rowCount: maxRow,
      colCount: maxCol,
      colWidths: colWidths,
      rowHeights: rowHeights,
      defaultColWidth: 85, // 2.26 cm, default LibreOffice
      defaultRowHeight: 17,
      merges: merges,
      drawings: drawings,
    ));
  }
  return SheetBook(sheets);
}

String _odfText(XmlElement e) {
  final sb = StringBuffer();
  for (final n in e.children) {
    if (n is XmlText) {
      sb.write(n.value);
    } else if (n is XmlElement) {
      switch (n.localName) {
        case 's':
          sb.write(' ' * (int.tryParse(n.attr('c') ?? '') ?? 1));
        case 'tab':
          sb.write('\t');
        case 'line-break':
          sb.write('\n');
        case 'annotation':
          break;
        default:
          sb.write(_odfText(n));
      }
    }
  }
  return sb.toString();
}

// ── CSV / TSV ────────────────────────────────────────────────────────────────

final _numberLike = RegExp(r'^[-+]?[\d.,]+%?$');

/// Parser CSV dengan deteksi pemisah (`,` `;` tab `|`) dan kutip RFC 4180.
SheetBook parseCsv(Uint8List data, {String name = 'Sheet1'}) {
  var text = decodeText(data);
  if (text.startsWith('﻿')) text = text.substring(1);
  final delim = _detectDelimiter(text);

  final cells = <int, Map<int, SheetCell>>{};
  final widths = <int, double>{};
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var r = 0, maxCol = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row[0].isEmpty)) {
      final map = <int, SheetCell>{};
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        if (v.isEmpty) continue;
        final numeric = _numberLike.hasMatch(v.trim());
        map[c] = SheetCell(v,
            isNumber: numeric,
            style: r == 0 ? const SheetCellStyle(bold: true) : SheetCellStyle.plain);
        final w = math.min(320.0, v.length * 7.5 + 12);
        if (w > (widths[c] ?? 0)) widths[c] = w;
      }
      cells[r] = map;
      maxCol = math.max(maxCol, row.length);
    }
    r++;
    row = [];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (ch == delim) {
      endField();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();

  for (final c in widths.keys.toList()) {
    widths[c] = math.max(widths[c]!, 64);
  }
  return SheetBook([
    SheetData(
      name: name,
      cells: cells,
      rowCount: r,
      colCount: maxCol,
      colWidths: widths,
    )
  ]);
}

String _detectDelimiter(String text) {
  final sample = text.split('\n').take(10).join('\n');
  var best = ',';
  var bestCount = 0;
  for (final d in [',', ';', '\t', '|']) {
    // Hitung di luar tanda kutip
    var count = 0;
    var q = false;
    for (final ch in sample.split('')) {
      if (ch == '"') q = !q;
      if (!q && ch == d) count++;
    }
    if (count > bestCount) {
      best = d;
      bestCount = count;
    }
  }
  return best;
}
