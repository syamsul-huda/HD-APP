import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_app_hd/screens/docx_viewer_screen.dart';
import 'package:super_app_hd/screens/pptx_viewer_screen.dart';
import 'package:super_app_hd/screens/reader_screen.dart';
import 'package:super_app_hd/screens/xlsx_viewer_screen.dart';
import 'package:super_app_hd/utils/office/doc_model.dart';
import 'package:super_app_hd/utils/office/sheet_model.dart';
import 'package:super_app_hd/utils/office/slide_model.dart';
import 'office_fixtures.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('document view renders paragraphs, lists, tables, images, pages', (tester) async {
    phone(tester);
    final doc = DocDocument([
      DocParagraph(inlines: [DocText('Judul Laporan', bold: true, fontSize: 20)], headingLevel: 1),
      DocParagraph(
          inlines: [DocText('Butir pertama')], listLabel: '1.', indentLeft: 36, firstLine: -18),
      DocParagraph(inlines: [
        DocText('Kunjungi '),
        DocText('situs', link: 'https://example.com', underline: true),
        DocText(' dan teks\tber-tab', highlight: Colors.yellow),
        DocImage(pngBytes, 20, 20),
      ]),
      DocParagraph(inlines: [DocImage(pngBytes, 900, 300), DocImage(null, 50, 50)]),
      DocParagraph(inlines: []),
      DocTable(columnWidths: [100, 200, 150], borders: true, rows: [
        DocTableRow([
          DocTableCell([DocParagraph(inlines: [DocText('Gabung dua')])],
              colSpan: 2, shading: Colors.amber),
          DocTableCell([DocParagraph(inlines: [DocText('C1')])]),
        ]),
        DocTableRow([
          DocTableCell([DocParagraph(inlines: [DocText('A2 dengan teks yang cukup panjang untuk wrap')])]),
          DocTableCell([], mergedContinue: true),
        ]),
      ]),
      // Kolom super sempit berisi gambar: tidak boleh crash
      DocTable(columnWidths: [1, 450], rows: [
        DocTableRow([
          DocTableCell([DocParagraph(inlines: [DocImage(pngBytes, 100, 100)])]),
          DocTableCell([DocParagraph(inlines: [DocText('lebar')])]),
        ]),
      ]),
      DocPageBreak(),
      DocParagraph(inlines: [DocText('Halaman dua')], pageBreakBefore: true),
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DocDocumentView(doc: doc))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Judul Laporan', findRichText: true), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.textContaining('Gabung dua', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);

    await tester.dragUntilVisible(find.textContaining('Halaman dua', findRichText: true),
        find.byType(ListView), const Offset(0, -300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet grid paints and selects tapped cell (merge → anchor)', (tester) async {
    phone(tester);
    final sheet = SheetData(
      name: 'S',
      cells: {
        0: {
          0: const SheetCell('Header panjang sekali yang meluber',
              style: SheetCellStyle(bold: true, fill: Colors.green, borderBottom: Colors.black)),
          2: const SheetCell('123', isNumber: true),
        },
        1: {0: const SheetCell('Baris\nwrap', style: SheetCellStyle(wrap: true, vAlign: VAlign.top))},
        3: {1: const SheetCell('Merged', style: SheetCellStyle(align: TextAlign.center))},
      },
      rowCount: 5,
      colCount: 3,
      merges: const [CellRange(3, 1, 4, 2)],
    );
    (int, int)? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (_, set) => SheetGridView(
            sheet: sheet,
            selected: selected,
            onSelect: (c) => set(() => selected = c),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    // Sel C5 berada di dalam merge B4:C5 → yang terpilih adalah B4
    final origin = tester.getTopLeft(find.byType(SheetGridView));
    await tester.tapAt(origin + const Offset(44 + 64 * 2 + 10, 22 + 20 * 4 + 5));
    await tester.pump();
    expect(selected, (3, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('slide canvas renders every shape kind', (tester) async {
    phone(tester);
    SlideText txt(String t, {TextAnchor anchor = TextAnchor.top, int turns = 0}) => SlideText(
          paragraphs: [
            SlideParagraph(runs: [SlideRun(t, size: 24, bold: true)], align: TextAlign.center),
            SlideParagraph(runs: [SlideRun('Poin', size: 18)], bullet: '•', marginLeft: 20, indent: -14),
            SlideParagraph(runs: []),
          ],
          anchor: anchor,
          quarterTurns: turns,
        );
    final deck = SlideDeck(960, 540, [
      SlideData(background: const Color(0xFFEEEEEE), backgroundImage: pngBytes, shapes: [
        SlideShape(rect: const Rect.fromLTWH(40, 30, 880, 80), text: txt('Judul Presentasi')),
        SlideShape(rect: const Rect.fromLTWH(40, 140, 200, 100), geom: ShapeGeom.roundRect, fill: Colors.blue, lineColor: Colors.black, lineWidth: 2, text: txt('Kotak', anchor: TextAnchor.center)),
        SlideShape(rect: const Rect.fromLTWH(260, 140, 100, 100), geom: ShapeGeom.ellipse, fill: Colors.red, rotation: 30),
        SlideShape(rect: const Rect.fromLTWH(380, 140, 100, 100), geom: ShapeGeom.triangle, fill: Colors.green),
        SlideShape(rect: const Rect.fromLTWH(500, 140, 100, 100), geom: ShapeGeom.diamond, fill: Colors.orange),
        SlideShape(rect: const Rect.fromLTWH(40, 260, 300, 0), geom: ShapeGeom.line, lineColor: Colors.black, lineWidth: 1, flipV: true),
        SlideShape(rect: const Rect.fromLTWH(620, 140, 100, 100), geom: ShapeGeom.path, fill: Colors.purple, path: const [
          PathCmd('M', [Offset(0, 1)]), PathCmd('L', [Offset(0.5, 0), Offset(1, 1)]),
          PathCmd('C', [Offset(0.8, 0.8), Offset(0.2, 0.8), Offset(0, 1)]), PathCmd('Z', []),
        ]),
        SlideShape(rect: const Rect.fromLTWH(740, 140, 120, 90), image: pngBytes, geom: ShapeGeom.ellipse, flipH: true),
        SlideShape(rect: const Rect.fromLTWH(740, 250, 120, 90), imageUnsupported: true),
        SlideShape(rect: const Rect.fromLTWH(40, 280, 300, 200), isChart: true),
        SlideShape(rect: const Rect.fromLTWH(880, 250, 60, 250), text: txt('Vertikal', turns: 3)),
        SlideShape(
          rect: const Rect.fromLTWH(360, 280, 500, 200),
          table: SlideTable([200, 150, 150], [40, 40], [
            [
              SlideTableCell(txt('H1'), fill: Colors.indigo, colSpan: 2),
              SlideTableCell(SlideText(paragraphs: []), merged: true),
              SlideTableCell(txt('H3'), fill: Colors.indigo),
            ],
            [
              SlideTableCell(txt('a')),
              SlideTableCell(txt('b')),
              SlideTableCell(txt('c')),
            ],
          ]),
        ),
      ]),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 360, height: 203, child: SlideCanvas(deck: deck, slide: deck.slides.first)))),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Judul Presentasi', findRichText: true), findsOneWidget);
    expect(find.text('Chart'), findsOneWidget);
    expect(find.text('H1', findRichText: true), findsOneWidget);
  });

  group('viewer screens with real files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('office_viewers'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pumpLoaded(WidgetTester tester, Widget screen) async {
      phone(tester);
      await tester.pumpWidget(MaterialApp(home: screen));
      // Parsing berjalan di isolate (compute): beri waktu nyata
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      expect(tester.takeException(), isNull);
    }

    testWidgets('DOCX screen', (tester) async {
      final f = File('${dir.path}/surat.docx')
        ..writeAsBytesSync(zip({
          'word/document.xml':
              '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
                  '<w:p><w:r><w:t>Isi surat resmi</w:t></w:r></w:p></w:body></w:document>',
        }));
      await pumpLoaded(tester, DocxViewerScreen(path: f.path, title: 'surat.docx'));
      expect(find.text('Isi surat resmi', findRichText: true), findsOneWidget);
      expect(find.byTooltip('Original layout (PDF)'), findsOneWidget);
    });

    testWidgets('XLSX screen shows value in formula bar after tap', (tester) async {
      final f = File('${dir.path}/data.xlsx')
        ..writeAsBytesSync(zip({
          'xl/workbook.xml':
              '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                  'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                  '<sheets><sheet name="Penjualan" sheetId="1" r:id="rId1"/></sheets></workbook>',
          'xl/_rels/workbook.xml.rels':
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                  '<Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
          'xl/worksheets/sheet1.xml':
              '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
                  '<row r="1"><c r="A1" t="inlineStr"><is><t>Total omzet</t></is></c></row></sheetData></worksheet>',
        }));
      await pumpLoaded(tester, XlsxViewerScreen(path: f.path, title: 'data.xlsx'));
      expect(find.text('Penjualan'), findsOneWidget);
      final grid = tester.getTopLeft(find.byType(SheetGridView));
      await tester.tapAt(grid + const Offset(44 + 10, 22 + 8));
      await tester.pump();
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('Total omzet'), findsOneWidget);
    });

    testWidgets('PPTX screen with thumbnails and swipe', (tester) async {
      const ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
      String slide(String t) => '<p:sld $ns><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2" name="t"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
          '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="6000000" cy="1000000"/></a:xfrm></p:spPr>'
          '<p:txBody><a:bodyPr/><a:p><a:r><a:t>$t</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
      final f = File('${dir.path}/deck.pptx')
        ..writeAsBytesSync(zip({
          'ppt/presentation.xml': '<p:presentation $ns><p:sldIdLst><p:sldId id="256" r:id="rId1"/><p:sldId id="257" r:id="rId2"/></p:sldIdLst></p:presentation>',
          'ppt/_rels/presentation.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/><Relationship Id="rId2" Type="slide" Target="slides/slide2.xml"/></Relationships>',
          'ppt/slides/slide1.xml': slide('Slide pembuka'),
          'ppt/slides/slide2.xml': slide('Slide penutup'),
        }));
      await pumpLoaded(tester, PptxViewerScreen(path: f.path, title: 'deck.pptx'));
      expect(find.text('1 / 2'), findsOneWidget);
      // Slide utama + thumbnail
      expect(find.text('Slide pembuka', findRichText: true), findsNWidgets(2));
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('content sniffing recognizes files without a proper extension', () async {
      final docx = File('${dir.path}/download')
        ..writeAsBytesSync(zip({'word/document.xml': '<w:document/>'}));
      final pdf = File('${dir.path}/file.bin')..writeAsStringSync('%PDF-1.7 ...');
      final ole = File('${dir.path}/old')
        ..writeAsBytesSync([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      expect(await sniffDocumentType(docx.path, ''), 'docx');
      expect(await sniffDocumentType(pdf.path, 'bin'), 'pdf');
      expect(await sniffDocumentType(ole.path, ''), 'doc');
      expect(await sniffDocumentType(pdf.path, 'xlsx'), 'xlsx'); // ekstensi dikenal dipercaya
    });
  });
}
