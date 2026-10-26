import 'dart:typed_data';
import 'dart:ui';
import 'chart_model.dart';

/// Model dokumen teks (DOCX / ODT). Semua ukuran dalam point (1/72 inch).
class DocDocument {
  final List<DocBlock> blocks;
  final DocPageSetup page;
  final List<DocBlock> header;
  final List<DocBlock> footer;

  /// Header/footer khusus halaman pertama (Word "Different first page").
  final List<DocBlock>? firstHeader;
  final List<DocBlock>? firstFooter;

  /// Dokumen menyimpan posisi pindah halaman hasil render Word
  /// (`w:lastRenderedPageBreak`) → pagination bisa identik dengan Word.
  final bool hasRenderedBreaks;

  /// Footnote per nomor rujukan (ditampilkan di dasar halaman perujuk).
  final Map<String, List<DocBlock>> footnotes;

  /// Endnote & komentar ditampilkan di akhir dokumen.
  final List<DocNote> endnotes;
  final List<DocNote> comments;

  const DocDocument(
    this.blocks, {
    this.page = const DocPageSetup(),
    this.header = const [],
    this.footer = const [],
    this.firstHeader,
    this.firstFooter,
    this.hasRenderedBreaks = false,
    this.footnotes = const {},
    this.endnotes = const [],
    this.comments = const [],
  });

  /// Lebar area teks halaman (lebar kertas − margin).
  double get textWidth => page.width - page.marginLeft - page.marginRight;
}

/// Catatan (endnote / komentar): label rujukan + isi.
class DocNote {
  final String label;
  final String? author;
  final List<DocBlock> blocks;
  const DocNote(this.label, this.blocks, {this.author});
}

/// Ukuran kertas & margin (default A4, margin 2.54 cm).
class DocPageSetup {
  final double width, height;
  final double marginTop, marginBottom, marginLeft, marginRight;
  final double headerDistance, footerDistance;
  const DocPageSetup({
    this.width = 595.3,
    this.height = 841.9,
    this.marginTop = 72,
    this.marginBottom = 72,
    this.marginLeft = 72,
    this.marginRight = 72,
    this.headerDistance = 35.4,
    this.footerDistance = 35.4,
  });
}

sealed class DocBlock {}

class DocParagraph extends DocBlock {
  final List<DocInline> inlines;
  final TextAlign align;
  final double indentLeft;
  final double indentRight;
  final double firstLine; // negatif = hanging
  final double spaceBefore;
  final double spaceAfter;
  final double? lineHeight; // kelipatan (1.0, 1.15, 1.5 …)
  final double? lineExact; // spasi baris tetap (pt), Word "Exactly"
  final double? lineAtLeast; // spasi baris minimum (pt), Word "At least"
  final String? listLabel;
  final Color? shading;
  final int headingLevel; // 0 = bukan heading
  final bool pageBreakBefore;

  /// Harus satu halaman dengan paragraf berikutnya (Word "Keep with next").
  final bool keepNext;

  DocParagraph({
    required this.inlines,
    this.align = TextAlign.left,
    this.indentLeft = 0,
    this.indentRight = 0,
    this.firstLine = 0,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.lineHeight,
    this.lineExact,
    this.lineAtLeast,
    this.listLabel,
    this.shading,
    this.headingLevel = 0,
    this.pageBreakBefore = false,
    this.keepNext = false,
  });

  bool get isEmpty => inlines.every((i) => i is DocText && i.text.isEmpty && i.field == null);

  /// Lanjutan paragraf di halaman berikutnya: tanpa nomor list, indent baris
  /// pertama, dan spasi sebelum.
  DocParagraph continuation(List<DocInline> rest) => DocParagraph(
        inlines: rest,
        align: align,
        indentLeft: indentLeft,
        indentRight: indentRight,
        firstLine: 0,
        spaceBefore: 0,
        spaceAfter: spaceAfter,
        lineHeight: lineHeight,
        lineExact: lineExact,
        lineAtLeast: lineAtLeast,
        shading: shading,
        headingLevel: headingLevel,
      );

  DocParagraph withInlines(List<DocInline> inl) => DocParagraph(
        inlines: inl,
        align: align,
        indentLeft: indentLeft,
        indentRight: indentRight,
        firstLine: firstLine,
        spaceBefore: spaceBefore,
        spaceAfter: spaceAfter,
        lineHeight: lineHeight,
        lineExact: lineExact,
        lineAtLeast: lineAtLeast,
        listLabel: listLabel,
        shading: shading,
        headingLevel: headingLevel,
        pageBreakBefore: pageBreakBefore,
        keepNext: keepNext,
      );

  DocParagraph withSpaceBefore(double before) => DocParagraph(
        inlines: inlines,
        align: align,
        indentLeft: indentLeft,
        indentRight: indentRight,
        firstLine: firstLine,
        spaceBefore: before,
        spaceAfter: spaceAfter,
        lineHeight: lineHeight,
        lineExact: lineExact,
        lineAtLeast: lineAtLeast,
        listLabel: listLabel,
        shading: shading,
        headingLevel: headingLevel,
        pageBreakBefore: pageBreakBefore,
        keepNext: keepNext,
      );

  /// Bagian awal paragraf yang muat di halaman ini (tanpa spasi sesudah).
  DocParagraph head(List<DocInline> part) => DocParagraph(
        inlines: part,
        align: align,
        indentLeft: indentLeft,
        indentRight: indentRight,
        firstLine: firstLine,
        spaceBefore: spaceBefore,
        spaceAfter: 0,
        lineHeight: lineHeight,
        lineExact: lineExact,
        lineAtLeast: lineAtLeast,
        listLabel: listLabel,
        shading: shading,
        headingLevel: headingLevel,
        pageBreakBefore: pageBreakBefore,
        keepNext: keepNext,
      );

  String get plainText =>
      inlines.whereType<DocText>().map((t) => t.text).join();
}

class DocTable extends DocBlock {
  final List<double> columnWidths; // pt
  final List<DocTableRow> rows;
  final bool borders;

  /// Margin sel (pt). Default Word: kiri/kanan 0.08", atas/bawah 0.
  final double cellMarginH;
  final double cellMarginTop;
  final double cellMarginBottom;

  DocTable({
    required this.columnWidths,
    required this.rows,
    this.borders = true,
    this.cellMarginH = 5.4,
    this.cellMarginTop = 0,
    this.cellMarginBottom = 0,
  });

  DocTable withRows(List<DocTableRow> rows) => DocTable(
        columnWidths: columnWidths,
        rows: rows,
        borders: borders,
        cellMarginH: cellMarginH,
        cellMarginTop: cellMarginTop,
        cellMarginBottom: cellMarginBottom,
      );
}

class DocTableRow {
  final List<DocTableCell> cells;
  final bool header;

  /// Word "Allow row to break across pages" dimatikan (w:cantSplit).
  final bool cantSplit;
  DocTableRow(this.cells, {this.header = false, this.cantSplit = false});
}

class DocTableCell {
  final List<DocBlock> blocks;
  final int colSpan;
  final Color? shading;

  /// Lanjutan sel merge vertikal (konten ada di baris atas).
  final bool mergedContinue;
  DocTableCell(this.blocks,
      {this.colSpan = 1, this.shading, this.mergedContinue = false});
}

class DocPageBreak extends DocBlock {
  /// true = posisi pindah halaman otomatis hasil render Word (bukan Ctrl+Enter).
  final bool soft;
  DocPageBreak({this.soft = false});
}

sealed class DocInline {}

class DocText extends DocInline {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final double? fontSize;
  final Color? color;
  final Color? highlight;
  final String? fontFamily;
  final bool superscript;
  final bool subscript;
  final bool allCaps;
  final String? link;

  /// Field dinamis: 'PAGE' (nomor halaman) / 'NUMPAGES' (jumlah halaman).
  final String? field;

  /// Rujukan footnote (label yang sama dengan kunci [DocDocument.footnotes]).
  final String? footnote;

  DocText(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSize,
    this.color,
    this.highlight,
    this.fontFamily,
    this.superscript = false,
    this.subscript = false,
    this.allCaps = false,
    this.link,
    this.field,
    this.footnote,
  });

  DocText copyWith({String? text, String? field}) => DocText(
        text ?? this.text,
        bold: bold,
        italic: italic,
        underline: underline,
        strike: strike,
        fontSize: fontSize,
        color: color,
        highlight: highlight,
        fontFamily: fontFamily,
        superscript: superscript,
        subscript: subscript,
        allCaps: allCaps,
        link: link,
        field: field ?? this.field,
        footnote: footnote,
      );
}

/// Penanda pindah halaman di tengah paragraf (hanya dipakai saat parsing;
/// paragraf dipecah di sini sehingga tidak muncul di model akhir).
class DocBreakMarker extends DocInline {
  final bool soft;
  DocBreakMarker(this.soft);
}

class DocImage extends DocInline {
  final Uint8List? bytes; // null = format tidak didukung (EMF/WMF)
  final double width;
  final double height;
  DocImage(this.bytes, this.width, this.height);
}

class DocChart extends DocInline {
  final ChartData chart;
  final double width;
  final double height;
  DocChart(this.chart, this.width, this.height);
}
