import 'dart:typed_data';
import 'dart:ui';
import 'chart_model.dart';

/// Model spreadsheet (XLSX / ODS / CSV). Ukuran kolom/baris dalam pixel
/// logis seperti Excel pada zoom 100%; ukuran font dalam point.
class SheetBook {
  final List<SheetData> sheets;
  const SheetBook(this.sheets);
}

class SheetData {
  final String name;

  /// Sheet disembunyikan di file asli (tetap bisa dibuka, ditandai).
  final bool hidden;

  /// Sel sparse: baris → kolom → sel (indeks mulai 0).
  final Map<int, Map<int, SheetCell>> cells;
  final int rowCount;
  final int colCount;
  final Map<int, double> colWidths;
  final Map<int, double> rowHeights;
  final double defaultColWidth;
  final double defaultRowHeight;
  final List<CellRange> merges;
  final bool showGrid;
  final List<SheetDrawing> drawings;

  SheetData({
    required this.name,
    this.hidden = false,
    required this.cells,
    required this.rowCount,
    required this.colCount,
    this.colWidths = const {},
    this.rowHeights = const {},
    this.defaultColWidth = 64,
    this.defaultRowHeight = 20,
    this.merges = const [],
    this.showGrid = true,
    this.drawings = const [],
  });

  SheetCell? cell(int r, int c) => cells[r]?[c];
  double colWidth(int c) => colWidths[c] ?? defaultColWidth;
  double rowHeight(int r) => rowHeights[r] ?? defaultRowHeight;
}

/// Gambar / chart yang menempel di sheet. Posisi = sel awal + offset (px);
/// ukuran dari sel akhir + offset, atau [width]/[height] jika tanpa sel akhir.
class SheetDrawing {
  final int fromRow, fromCol;
  final double fromRowOff, fromColOff;
  final int? toRow, toCol;
  final double toRowOff, toColOff;
  final double width, height;
  final Uint8List? image;
  final ChartData? chart;

  const SheetDrawing({
    this.fromRow = 0,
    this.fromCol = 0,
    this.fromRowOff = 0,
    this.fromColOff = 0,
    this.toRow,
    this.toCol,
    this.toRowOff = 0,
    this.toColOff = 0,
    this.width = 0,
    this.height = 0,
    this.image,
    this.chart,
  });
}

class SheetCell {
  /// Teks tampilan (sudah diformat seperti di Excel).
  final String text;
  final bool isNumber;
  final SheetCellStyle style;

  /// Isi asli untuk formula bar: rumus ("=SUM(A1:A3)") atau nilai lengkap
  /// tanpa pembulatan tampilan. null = sama dengan [text].
  final String? content;

  const SheetCell(this.text,
      {this.isNumber = false, this.style = SheetCellStyle.plain, this.content});

  String get editText => content ?? text;
}

enum VAlign { top, center, bottom }

class SheetCellStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final double fontSize; // pt
  final String? font;
  final Color? color;
  final Color? fill;
  final TextAlign? align; // null = General (angka kanan, teks kiri)
  final VAlign vAlign;
  final bool wrap;
  final Color? borderLeft;
  final Color? borderRight;
  final Color? borderTop;
  final Color? borderBottom;

  const SheetCellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSize = 11,
    this.font,
    this.color,
    this.fill,
    this.align,
    this.vAlign = VAlign.bottom,
    this.wrap = false,
    this.borderLeft,
    this.borderRight,
    this.borderTop,
    this.borderBottom,
  });

  static const plain = SheetCellStyle();
}

class CellRange {
  final int r1, c1, r2, c2; // inklusif
  const CellRange(this.r1, this.c1, this.r2, this.c2);
  bool contains(int r, int c) => r >= r1 && r <= r2 && c >= c1 && c <= c2;
}

/// "B12" → (11, 1). Mengembalikan null jika tidak valid.
/// Ditulis manual (tanpa regex) karena dipanggil untuk setiap sel.
(int, int)? parseCellRef(String ref) {
  var i = 0, col = 0, row = 0;
  final n = ref.length;
  if (i < n && ref.codeUnitAt(i) == 0x24) i++; // $
  final colStart = i;
  while (i < n) {
    var c = ref.codeUnitAt(i);
    if (c >= 0x61 && c <= 0x7A) c -= 32; // huruf kecil
    if (c < 0x41 || c > 0x5A) break;
    col = col * 26 + (c - 64);
    i++;
  }
  if (i == colStart) return null;
  if (i < n && ref.codeUnitAt(i) == 0x24) i++;
  final rowStart = i;
  while (i < n) {
    final c = ref.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return null;
    row = row * 10 + (c - 0x30);
    i++;
  }
  if (i == rowStart || row == 0) return null;
  return (row - 1, col - 1);
}

String columnLetter(int index) {
  var n = index;
  var s = '';
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}
