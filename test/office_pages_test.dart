import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_app_hd/screens/docx_viewer_screen.dart';
import 'package:super_app_hd/utils/office/doc_model.dart';
import 'package:super_app_hd/utils/office/doc_paginate.dart';
import 'package:super_app_hd/utils/office/doc_render.dart';
import 'package:super_app_hd/utils/office/docx_parser.dart';
import 'dart:io';
import 'office_fixtures.dart';

const _w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

Future<void> _loadFonts() async {
  final l = FontLoader('Carlito');
  for (final f in ['Carlito-Regular', 'Carlito-Bold']) {
    l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f.ttf').readAsBytesSync())));
  }
  await l.load();
}

void main() {
  test('Word rendered page breaks split paragraphs/tables; footer PAGE field; page setup', () {
    final doc = parseDocx(zip({
      'word/document.xml': '''<w:document $_w><w:body>
        <w:p><w:r><w:t xml:space="preserve">Akhir halaman satu </w:t></w:r><w:r><w:lastRenderedPageBreak/><w:t>awal halaman dua</w:t></w:r></w:p>
        <w:p><w:r><w:t>Sebelum</w:t></w:r><w:r><w:br w:type="page"/><w:t>Sesudah</w:t></w:r></w:p>
        <w:tbl><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>
          <w:tr><w:trPr><w:tblHeader/></w:trPr><w:tc><w:p><w:r><w:t>Header</w:t></w:r></w:p></w:tc></w:tr>
          <w:tr><w:tc><w:p><w:r><w:t>Baris 1</w:t></w:r></w:p></w:tc></w:tr>
          <w:tr><w:tc><w:p><w:r><w:lastRenderedPageBreak/><w:t>Baris 2</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl>
        <w:sectPr><w:footerReference w:type="default" r:id="rF"/><w:pgSz w:w="12240" w:h="15840"/>
          <w:pgMar w:top="1440" w:bottom="1440" w:left="1800" w:right="1800" w:header="720" w:footer="708"/></w:sectPr>
      </w:body></w:document>''',
      'word/_rels/document.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rF" Type="footer" Target="footer1.xml"/></Relationships>',
      'word/footer1.xml': '''<w:ftr $_w><w:p><w:r><w:t xml:space="preserve">Halaman </w:t></w:r>
        <w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> PAGE \\* MERGEFORMAT </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>
        <w:r><w:t>7</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>
        <w:r><w:t xml:space="preserve"> dari </w:t></w:r><w:fldSimple w:instr="NUMPAGES"><w:r><w:t>9</w:t></w:r></w:fldSimple></w:p></w:ftr>''',
    }));
    expect(doc.hasRenderedBreaks, isTrue);
    expect(doc.page.width, 612);
    expect(doc.page.marginLeft, 90);
    expect(doc.page.footerDistance, 35.4);
    final b = doc.blocks;
    expect((b[0] as DocParagraph).plainText, 'Akhir halaman satu ');
    expect((b[1] as DocPageBreak).soft, isTrue);
    expect((b[2] as DocParagraph).plainText, 'awal halaman dua');
    expect((b[3] as DocParagraph).plainText, 'Sebelum');
    expect((b[4] as DocPageBreak).soft, isFalse);
    expect((b[5] as DocParagraph).plainText, 'Sesudah');
    expect((b[6] as DocTable).rows.length, 2);
    expect(b[7], isA<DocPageBreak>());
    final cont = b[8] as DocTable;
    expect(cont.rows.length, 2, reason: 'header row repeated');
    expect(cont.rows.first.header, isTrue);

    final footer = (doc.footer.single as DocParagraph).inlines.whereType<DocText>().toList();
    expect(footer.map((t) => t.field), [null, 'PAGE', null, 'NUMPAGES']);
    expect(footer.map((t) => t.text).join(), 'Halaman 1 dari 1', reason: 'cached 7/9 dropped');

    final pages = paginateDocument(doc, DocRenderer(scale: 1));
    expect(pages.length, 4);
    final r = DocRenderer(scale: 1, pageNumber: 3, pageCount: 4);
    expect(footer.map(r.displayText).join(), 'Halaman 3 dari 4');
  });

  testWidgets('footnotes, endnotes and comments are kept and placed', (tester) async {
    await tester.runAsync(_loadFonts);
    const rels = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
    final long = List.generate(30, (i) => 'Kalimat isi nomor $i untuk mengisi halaman.').join(' ');
    final doc = parseDocx(zip({
      'word/document.xml': '''<w:document $_w><w:body>
        ${List.generate(6, (_) => '<w:p><w:r><w:t>$long</w:t></w:r></w:p>').join()}
        <w:p><w:r><w:t xml:space="preserve">Kutipan penting</w:t></w:r><w:r><w:footnoteReference w:id="2"/></w:r>
          <w:r><w:t xml:space="preserve"> dan istilah</w:t></w:r><w:r><w:endnoteReference w:id="5"/></w:r>
          <w:commentRangeStart w:id="0"/><w:r><w:t xml:space="preserve"> yang dikomentari</w:t></w:r><w:commentRangeEnd w:id="0"/><w:r><w:commentReference w:id="0"/></w:r></w:p>
        <w:sectPr/></w:body></w:document>''',
      'word/_rels/document.xml.rels': '<Relationships $rels>'
          '<Relationship Id="rF" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>'
          '<Relationship Id="rE" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes" Target="endnotes.xml"/>'
          '<Relationship Id="rC" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/></Relationships>',
      'word/footnotes.xml': '''<w:footnotes $_w><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
        <w:footnote w:id="2"><w:p><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> Sumber: Laporan Tahunan 2024, hlm. 12.</w:t></w:r></w:p></w:footnote></w:footnotes>''',
      'word/endnotes.xml': '''<w:endnotes $_w><w:endnote w:id="5"><w:p><w:r><w:endnoteRef/></w:r><w:r><w:t xml:space="preserve"> Definisi istilah lengkap.</w:t></w:r></w:p></w:endnote></w:endnotes>''',
      'word/comments.xml': '''<w:comments $_w><w:comment w:id="0" w:author="Budi"><w:p><w:r><w:annotationRef/></w:r><w:r><w:t>Mohon dicek ulang.</w:t></w:r></w:p></w:comment></w:comments>''',
    }));
    // Isi catatan utuh, berlabel sesuai urutan
    expect(doc.footnotes.keys, ['1']);
    expect((doc.footnotes['1']!.single as DocParagraph).plainText, '1 Sumber: Laporan Tahunan 2024, hlm. 12.');
    expect(doc.endnotes.single.label, 'i');
    expect((doc.endnotes.single.blocks.single as DocParagraph).plainText, 'i Definisi istilah lengkap.');
    expect(doc.comments.single.author, 'Budi');
    expect((doc.comments.single.blocks.single as DocParagraph).plainText, 'Mohon dicek ulang.');
    final last = doc.blocks.last as DocParagraph;
    expect(last.plainText, 'Kutipan penting1 dan istilahi yang dikomentariC1');
    expect(last.inlines.whereType<DocText>().where((t) => t.footnote == '1').length, 1);

    // Footnote berada di halaman yang sama dengan rujukannya; endnote & komentar di akhir
    final r = DocRenderer(scale: 20, exact: true);
    final pages = paginateDocument(doc, r);
    final refPage = pages.indexWhere((p) => p.any((b) => footnoteLabels(b).contains('1')));
    expect(refPage, greaterThanOrEqualTo(0));
    final tail = pages.last.whereType<DocParagraph>().map((p) => p.plainText).join('|');
    expect(tail, contains('Endnotes'));
    expect(tail, contains('Definisi istilah lengkap.'));
    expect(tail, contains('Comments'));
    expect(tail, contains('Mohon dicek ulang.'));
    // Ruang footnote disisakan: isi + footnote tidak melebihi tinggi halaman
    final h = (doc.page.height - doc.page.marginTop - doc.page.marginBottom) * 20;
    final used = pages[refPage].fold<double>(0, (a, b) => a + r.measure(b, doc.textWidth * 20));
    final noteH = r.measure(doc.footnotes['1']!.single, doc.textWidth * 20) + 12 * 20;
    expect(used + noteH, lessThanOrEqualTo(h + 0.5 * 20 + 8 * 20));

    // Tampilan mobile memuat footnote juga
    final mobile = documentAppendix(doc, mobile: true).whereType<DocParagraph>().map((p) => p.plainText).join('|');
    expect(mobile, contains('Footnotes'));
    expect(mobile, contains('Sumber: Laporan Tahunan 2024'));
  });

  testWidgets('measured pagination: long paragraphs split by lines with widow/orphan control', (tester) async {
    await tester.runAsync(_loadFonts);
    final long = List.generate(60, (i) => 'Kalimat nomor $i dalam paragraf panjang.').join(' ');
    final doc = DocDocument([
      for (var i = 0; i < 6; i++) DocParagraph(inlines: [DocText(long)], spaceAfter: 8),
      DocParagraph(inlines: [DocText('Judul Bab', bold: true, fontSize: 16)], headingLevel: 1),
      DocParagraph(inlines: [DocText('Isi setelah judul.')]),
    ]);
    final r = DocRenderer(scale: 4);
    final pages = paginateDocument(doc, r);
    expect(pages.length, greaterThan(2));
    final h = (doc.page.height - doc.page.marginTop - doc.page.marginBottom) * 4;
    for (final p in pages) {
      final used = p.fold<double>(0, (a, b) => a + r.measure(b, doc.textWidth * 4));
      expect(used, lessThanOrEqualTo(h + 0.5));
    }
    // Teks tidak hilang / dobel saat dipecah
    final all = pages.expand((p) => p).whereType<DocParagraph>().map((p) => p.plainText).join(' ');
    expect(RegExp('Kalimat nomor 59').allMatches(all).length, 6);
    expect(RegExp('Kalimat nomor 0 ').allMatches(all).length, 6);
    // Bagian pecahan paragraf minimal 2 baris
    for (final p in pages.expand((p) => p).whereType<DocParagraph>()) {
      if (p.plainText.startsWith('Kalimat')) {
        expect(r.measure(p, doc.textWidth * 4), greaterThan(11 * 4 * 1.22 * 2 - 4));
      }
    }
  });

  testWidgets('page view renders pages with header/footer and page badge', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final doc = DocDocument(
      [
        for (var i = 0; i < 40; i++) DocParagraph(inlines: [DocText('Paragraf $i ' * 12)], spaceAfter: 6),
        DocTable(columnWidths: [200, 251], borders: true, rows: [
          for (var i = 0; i < 30; i++)
            DocTableRow([DocTableCell([DocParagraph(inlines: [DocText('R$i')])]), DocTableCell([DocParagraph(inlines: [DocImage(pngBytes, 40, 20)])])], header: i == 0),
        ]),
      ],
      header: [DocParagraph(inlines: [DocText('Kop Surat')])],
      footer: [DocParagraph(inlines: [DocText('1', field: 'PAGE')], align: TextAlign.center)],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DocPageView(doc: doc))));
    // Pagination bertahap: tunggu sampai semua halaman selesai dihitung
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('+'), findsNothing);
    expect(find.textContaining('Page 1 of'), findsOneWidget);
    expect(find.text('Kop Surat', findRichText: true), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Page 1 of'), findsNothing);
  });
}
