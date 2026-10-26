import 'dart:typed_data';
import 'dart:ui';
import 'chart_model.dart';

/// Model presentasi (PPTX / ODP). Semua koordinat dan ukuran dalam point,
/// relatif ke pojok kiri-atas slide — dirender dengan posisi absolut.
class SlideDeck {
  final double width;
  final double height;
  final List<SlideData> slides;
  const SlideDeck(this.width, this.height, this.slides);
}

class SlideData {
  final Color background;
  final Uint8List? backgroundImage;
  final List<SlideShape> shapes;
  final String notes;

  /// Slide disembunyikan di file asli (tetap ditampilkan, ditandai).
  final bool hidden;
  SlideData({
    required this.background,
    this.hidden = false,
    this.backgroundImage,
    required this.shapes,
    this.notes = '',
  });

  /// Teks seluruh slide (untuk ringkasan/pencarian).
  String get plainText => shapes
      .map((s) => s.text?.paragraphs.map((p) => p.plainText).join('\n') ?? '')
      .where((t) => t.trim().isNotEmpty)
      .join('\n');
}

enum ShapeGeom { rect, roundRect, ellipse, triangle, diamond, line, path }

enum TextAnchor { top, center, bottom }

class SlideShape {
  final Rect rect;
  final double rotation; // derajat, searah jarum jam
  final bool flipH;
  final bool flipV;
  final ShapeGeom geom;
  final Color? fill;
  final Color? lineColor;
  final double lineWidth;
  final Uint8List? image;

  /// Gambar ada tapi formatnya tidak bisa dirender (EMF/WMF/TIFF).
  final bool imageUnsupported;
  final SlideText? text;
  final SlideTable? table;
  final bool isChart;
  final ChartData? chart;

  /// Path custom geometry dalam koordinat 0..1 relatif terhadap [rect].
  final List<PathCmd> path;

  SlideShape({
    required this.rect,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.geom = ShapeGeom.rect,
    this.fill,
    this.lineColor,
    this.lineWidth = 0,
    this.image,
    this.imageUnsupported = false,
    this.text,
    this.table,
    this.isChart = false,
    this.chart,
    this.path = const [],
  });
}

class PathCmd {
  final String op; // M, L, C, Q, Z
  final List<Offset> pts;
  const PathCmd(this.op, this.pts);
}

class SlideText {
  final List<SlideParagraph> paragraphs;
  final TextAnchor anchor;
  final double insetL, insetT, insetR, insetB;
  final bool wrap;
  final int quarterTurns; // 1 = teks vertikal atas→bawah, 3 = bawah→atas

  SlideText({
    required this.paragraphs,
    this.anchor = TextAnchor.top,
    this.insetL = 7.2,
    this.insetT = 3.6,
    this.insetR = 7.2,
    this.insetB = 3.6,
    this.wrap = true,
    this.quarterTurns = 0,
  });

  bool get isEmpty => paragraphs.every((p) => p.plainText.trim().isEmpty);
}

class SlideParagraph {
  final List<SlideRun> runs;
  final TextAlign align;
  final double marginLeft;
  final double indent; // negatif = hanging (tempat bullet)
  final String? bullet;
  final Color? bulletColor;
  final double spaceBefore;
  final double spaceAfter;
  final double? lineSpacing; // kelipatan
  final double emptySize; // tinggi baris kosong (pt)

  SlideParagraph({
    required this.runs,
    this.align = TextAlign.left,
    this.marginLeft = 0,
    this.indent = 0,
    this.bullet,
    this.bulletColor,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.lineSpacing,
    this.emptySize = 18,
  });

  String get plainText => runs.map((r) => r.text).join();
}

class SlideRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final double size; // pt
  final Color color;
  final String? font;
  final double baseline; // >0 superscript, <0 subscript (persen)
  final bool caps;

  SlideRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.size = 18,
    this.color = const Color(0xFF000000),
    this.font,
    this.baseline = 0,
    this.caps = false,
  });
}

class SlideTable {
  final List<double> colWidths;
  final List<double> rowHeights;
  final List<List<SlideTableCell>> rows;
  SlideTable(this.colWidths, this.rowHeights, this.rows);
}

class SlideTableCell {
  final SlideText text;
  final Color? fill;
  final int colSpan;
  final int rowSpan;
  final bool merged; // tertutup oleh sel lain (hMerge / vMerge)
  final Color? border;
  SlideTableCell(this.text,
      {this.fill, this.colSpan = 1, this.rowSpan = 1, this.merged = false, this.border});
}
