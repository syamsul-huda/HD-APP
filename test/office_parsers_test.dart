import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/painting.dart';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'office_fixtures.dart';
import 'package:super_app_hd/utils/office/doc_model.dart';
import 'package:super_app_hd/utils/office/docx_parser.dart';
import 'package:super_app_hd/utils/office/odp_parser.dart';
import 'package:super_app_hd/utils/office/office_common.dart';
import 'package:super_app_hd/utils/office/ods_csv_parser.dart';
import 'package:super_app_hd/utils/office/odt_parser.dart';
import 'package:super_app_hd/utils/office/pptx_parser.dart';
import 'package:super_app_hd/utils/office/slide_model.dart';
import 'package:super_app_hd/utils/office/xlsx_parser.dart';

const _w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';

void main() {
  group('DOCX', () {
    final docx = zip({
      'word/document.xml': '''<w:document $_w><w:body>
        <w:p><w:pPr><w:pStyle w:val="Judul1"/></w:pPr><w:r><w:t>Bab Satu</w:t></w:r></w:p>
        <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Pertama</w:t></w:r></w:p>
        <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Kedua</w:t></w:r></w:p>
        <w:p><w:hyperlink r:id="rLink"><w:r><w:t>tautan</w:t></w:r></w:hyperlink>
             <w:del><w:r><w:delText>hapus</w:delText></w:r></w:del>
             <w:ins><w:r><w:t xml:space="preserve"> baru</w:t></w:r></w:ins></w:p>
        <w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/></w:tblPr>
          <w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="3000"/></w:tblGrid>
          <w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:shd w:fill="FFFF00"/></w:tcPr><w:p><w:r><w:t>Gabung</w:t></w:r></w:p></w:tc></w:tr>
          <w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl>
        <w:p><w:r><w:drawing><wp:inline><wp:extent cx="1270000" cy="635000"/>
          <a:graphic><a:graphicData><a:blip r:embed="rImg"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        <w:p><m:oMathPara xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><m:oMath>
          <m:r><m:t>x=</m:t></m:r><m:f><m:num><m:r><m:t>-b±</m:t></m:r><m:rad><m:radPr><m:degHide m:val="1"/></m:radPr><m:deg/><m:e><m:sSup><m:e><m:r><m:t>b</m:t></m:r></m:e><m:sup><m:r><m:t>2</m:t></m:r></m:sup></m:sSup><m:r><m:t>-4ac</m:t></m:r></m:e></m:rad></m:num>
          <m:den><m:r><m:t>2a</m:t></m:r></m:den></m:f></m:oMath></m:oMathPara></w:p>
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:left="1440" w:right="1440"/></w:sectPr>
      </w:body></w:document>''',
      'word/_rels/document.xml.rels': '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rImg" Type="image" Target="media/image1.png"/>
        <Relationship Id="rLink" Type="hyperlink" Target="https://example.com" TargetMode="External"/>
      </Relationships>''',
      'word/styles.xml': '''<w:styles $_w>
        <w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
        <w:style w:type="paragraph" w:styleId="Judul1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
          <w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="2F5496"/></w:rPr></w:style>
        <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/>
          <w:tblPr><w:tblBorders><w:top w:val="single"/></w:tblBorders></w:tblPr></w:style>
      </w:styles>''',
      'word/numbering.xml': '''<w:numbering $_w>
        <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>
        <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
      </w:numbering>''',
      'word/media/image1.png': pngBytes,
    });

    final doc = parseDocx(docx);

    test('heading style resolved via styles.xml name (localized id)', () {
      final h = doc.blocks[0] as DocParagraph;
      expect(h.headingLevel, 1);
      final run = h.inlines.single as DocText;
      expect(run.bold, isTrue);
      expect(run.fontSize, 16);
      expect(run.color, const Color(0xFF2F5496));
    });

    test('numbered list labels', () {
      expect((doc.blocks[1] as DocParagraph).listLabel, '1.');
      expect((doc.blocks[2] as DocParagraph).listLabel, '2.');
      expect(((doc.blocks[1] as DocParagraph).inlines.single as DocText).fontSize, 11);
    });

    test('hyperlink kept, deleted text skipped, inserted text kept', () {
      final p = doc.blocks[3] as DocParagraph;
      expect(p.plainText, 'tautan baru');
      expect((p.inlines.first as DocText).link, 'https://example.com');
    });

    test('table with span, shading and borders from table style', () {
      final t = doc.blocks[4] as DocTable;
      expect(t.borders, isTrue);
      expect(t.columnWidths, [100, 150]);
      expect(t.rows[0].cells.single.colSpan, 2);
      expect(t.rows[0].cells.single.shading, const Color(0xFFFFFF00));
      expect(t.rows[1].cells.length, 2);
    });

    test('math equations are linearized', () {
      final p = doc.blocks[6] as DocParagraph;
      expect(p.plainText, 'x=(-b±√(b²-4ac))/(2a)');
      expect((p.inlines.single as DocText).italic, isTrue);
    });

    test('inline image with size and page text width', () {
      final img = (doc.blocks[5] as DocParagraph).inlines.single as DocImage;
      expect(img.bytes, isNotNull);
      expect(img.width, 100);
      expect(img.height, 50);
      expect(doc.textWidth, closeTo(451.3, 0.1));
    });
  });

  group('XLSX', () {
    final xlsx = zip({
      'xl/workbook.xml': '''<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Data" sheetId="1" r:id="rId1"/><sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/></sheets></workbook>''',
      'xl/_rels/workbook.xml.rels': '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="worksheet" Target="/xl/worksheets/sheet2.xml"/></Relationships>''',
      'xl/sharedStrings.xml': '''<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <si><t>Produk</t></si><si><r><t>Total </t></r><r><t>Harga</t></r></si></sst>''',
      'xl/theme/theme1.xml': '''<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:themeElements><a:clrScheme name="x">
        <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
        <a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>
        <a:accent1><a:srgbClr val="4472C4"/></a:accent1></a:clrScheme></a:themeElements></a:theme>''',
      'xl/styles.xml': '''<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts><numFmt numFmtId="164" formatCode="&quot;Rp&quot;#,##0"/></numFmts>
        <fonts><font><sz val="11"/></font><font><b/><sz val="12"/><color rgb="FFFFFFFF"/></font></fonts>
        <fills><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>
          <fill><patternFill patternType="solid"><fgColor theme="4"/></patternFill></fill></fills>
        <borders><border/><border><left style="thin"/><bottom style="thin"><color rgb="FFFF0000"/></bottom></border></borders>
        <cellXfs>
          <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          <xf numFmtId="0" fontId="1" fillId="2" borderId="1"><alignment horizontal="center"/></xf>
          <xf numFmtId="4" fontId="0" fillId="0" borderId="0"/>
          <xf numFmtId="10" fontId="0" fillId="0" borderId="0"/>
          <xf numFmtId="14" fontId="0" fillId="0" borderId="0"/>
          <xf numFmtId="164" fontId="0" fillId="0" borderId="0"/>
        </cellXfs></styleSheet>''',
      'xl/worksheets/sheet1.xml': '''<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetViews><sheetView showGridLines="0"/></sheetViews>
        <cols><col min="1" max="1" width="20" customWidth="1"/><col min="3" max="3" hidden="1"/></cols>
        <sheetData>
          <row r="1"><c r="A1" t="s" s="1"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
          <row r="2" ht="30" customHeight="1"><c r="A2" s="2"><v>1234567.891</v></c><c r="B2" s="2"><f>A2*2</f><v>2469135.782</v></c></row>
          <row r="3"><c r="A3" s="3"><v>0.256</v></c><c r="B3" s="4"><v>45292</v></c><c r="D3" s="5"><v>1500000</v></c></row>
          <row r="4"><c r="A4" t="b"><v>1</v></c><c r="B4" t="e"><v>#DIV/0!</v></c><c r="C4" t="inlineStr"><is><t>inline</t></is></c></row>
        </sheetData>
        <mergeCells count="1"><mergeCell ref="A6:C7"/></mergeCells></worksheet>''',
      'xl/worksheets/sheet2.xml': '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>',
    });

    final book = parseXlsx(xlsx);
    final s = book.sheets.first;

    test('hidden sheets are kept but flagged', () {
      expect(book.sheets.map((x) => x.name), ['Data', 'Hidden']);
      expect(book.sheets.map((x) => x.hidden), [false, true]);
    });

    test('formula bar shows formula or full-precision value', () {
      expect(s.cell(1, 1)!.editText, '=A2*2');
      expect(s.cell(1, 0)!.editText, '1234567.891');
      expect(s.cell(1, 0)!.text, '1,234,567.89');
      expect(s.cell(2, 0)!.editText, '25.6%');
      expect(s.cell(2, 1)!.editText, '01/01/2024');
      expect(s.cell(0, 0)!.editText, 'Produk');
    });

    test('shared and rich strings', () {
      expect(s.cell(0, 0)!.text, 'Produk');
      expect(s.cell(0, 1)!.text, 'Total Harga');
    });

    test('formula shows cached result, not the formula', () {
      expect(s.cell(1, 1)!.text, '2,469,135.78');
      expect(s.cell(1, 0)!.text, '1,234,567.89');
    });

    test('percent, date and currency formats', () {
      expect(s.cell(2, 0)!.text, '25.60%');
      expect(s.cell(2, 1)!.text, '01/01/2024');
      expect(s.cell(2, 3)!.text, 'Rp1,500,000');
      expect(s.cell(2, 3)!.isNumber, isTrue);
    });

    test('bool, error and inline strings', () {
      expect(s.cell(3, 0)!.text, 'TRUE');
      expect(s.cell(3, 1)!.text, '#DIV/0!');
      expect(s.cell(3, 2)!.text, 'inline');
    });

    test('styles: bold, theme fill, font color, borders, alignment', () {
      final st = s.cell(0, 0)!.style;
      expect(st.bold, isTrue);
      expect(st.fill, const Color(0xFF4472C4));
      expect(st.color, const Color(0xFFFFFFFF));
      expect(st.borderBottom, const Color(0xFFFF0000));
      expect(st.borderLeft, isNotNull);
      expect(st.align, TextAlign.center);
    });

    test('column widths, hidden column, row height, merges, gridlines', () {
      expect(s.colWidth(0), 145);
      expect(s.colWidth(2), 0);
      expect(s.rowHeight(1), 40);
      expect(s.merges.single.r2, 6);
      expect(s.rowCount, 7);
      expect(s.showGrid, isFalse);
    });
  });

  test('theme color math is safe for black/white (no red from HSL NaN)', () {
    expect(modLuminance(const Color(0xFF000000), mod: 0.5, off: 0.5), const Color(0xFF808080));
    expect(applyTint(const Color(0xFF000000), 0.5), const Color(0xFF808080));
    expect(applyTint(const Color(0xFFFFFFFF), -0.5), const Color(0xFF808080));
  });

  test('symbol-font bullets map to renderable glyphs', () {
    expect(sanitizeBullet('\uf075', 1, font: 'Wingdings 3'), '▸');
    expect(sanitizeBullet('§', 0, font: 'Wingdings'), '▪');
    expect(sanitizeBullet('\uf0b7', 0, font: 'Symbol'), '•');
    expect(sanitizeBullet('–', 0), '–');
    expect(sanitizeBullet('\uf0e0', 2), '▪'); // PUA tanpa info font
  });

  test('Excel number format edge cases', () {
    expect(formatExcelNumber(-1234.5, '#,##0.00;(#,##0.00)'), '(1,234.50)');
    expect(formatExcelNumber(0.5, '0%'), '50%');
    expect(formatExcelNumber(45292.75, 'yyyy-mm-dd hh:mm'), '2024-01-01 18:00');
    expect(formatExcelNumber(45292, 'd mmmm yyyy'), '1 January 2024');
    expect(formatExcelNumber(1234, '[\$Rp-421] #,##0'), 'Rp 1,234');
    expect(formatExcelNumber(12345678, '0.00E+00'), '1.23E+07');
    expect(formatExcelNumber(42, 'General'), '42');
    expect(formatExcelNumber(1 / 3, 'General'), '0.3333333333');
    expect(formatExcelNumber(-5, '0'), '-5');
  });

  group('PPTX', () {
    const ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
    const rels = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
    final pptx = zip({
      'ppt/presentation.xml': '''<p:presentation $ns><p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>
        <p:sldSz cx="12192000" cy="6858000"/></p:presentation>''',
      'ppt/_rels/presentation.xml.rels': '<Relationships $rels><Relationship Id="rId2" Type="slide" Target="slides/slide1.xml"/></Relationships>',
      'ppt/slides/slide1.xml': '''<p:sld $ns><p:cSld><p:spTree>
        <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>
          <p:txBody><a:bodyPr/><a:p><a:r><a:rPr lang="id"/><a:t>Judul Slide</a:t></a:r></a:p></p:txBody></p:sp>
        <p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>
          <p:txBody><a:bodyPr/><a:p><a:r><a:t>Poin satu</a:t></a:r></a:p><a:p><a:pPr lvl="1"/><a:r><a:t>Sub poin</a:t></a:r></a:p></p:txBody></p:sp>
        <p:sp><p:nvSpPr><p:cNvPr id="4" name="Empty"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="2"/></p:nvPr></p:nvSpPr><p:spPr/>
          <p:txBody><a:bodyPr/><a:p/></p:txBody></p:sp>
        <p:grpSp><p:nvGrpSpPr><p:cNvPr id="5" name="G"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
          <p:grpSpPr><a:xfrm><a:off x="1270000" y="1270000"/><a:ext cx="2540000" cy="2540000"/><a:chOff x="0" y="0"/><a:chExt cx="1270000" cy="1270000"/></a:xfrm></p:grpSpPr>
          <p:sp><p:nvSpPr><p:cNvPr id="6" name="Box"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
            <p:spPr><a:xfrm><a:off x="635000" y="0"/><a:ext cx="635000" cy="635000"/></a:xfrm><a:prstGeom prst="ellipse"/><a:solidFill><a:schemeClr val="accent1"><a:lumMod val="50000"/></a:schemeClr></a:solidFill></p:spPr></p:sp>
        </p:grpSp>
        <p:pic><p:nvPicPr><p:cNvPr id="7" name="Pic"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rImg"/></p:blipFill>
          <p:spPr><a:xfrm rot="5400000"><a:off x="0" y="0"/><a:ext cx="127000" cy="127000"/></a:xfrm></p:spPr></p:pic>
      </p:spTree></p:cSld></p:sld>''',
      'ppt/slides/_rels/slide1.xml.rels': '''<Relationships $rels>
        <Relationship Id="rId1" Type="slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        <Relationship Id="rImg" Type="image" Target="../media/image1.png"/>
        <Relationship Id="rN" Type="notesSlide" Target="../notesSlides/notesSlide1.xml"/></Relationships>''',
      'ppt/notesSlides/notesSlide1.xml': '''<p:notes $ns><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2" name="n"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
        <p:txBody><a:p><a:r><a:t>Catatan pembicara</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>''',
      'ppt/slideLayouts/slideLayout1.xml': '''<p:sldLayout $ns><p:cSld><p:spTree>
        <p:sp><p:nvSpPr><p:cNvPr id="2" name="T"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
          <p:spPr><a:xfrm><a:off x="838200" y="365125"/><a:ext cx="10515600" cy="1325563"/></a:xfrm></p:spPr></p:sp>
        <p:sp><p:nvSpPr><p:cNvPr id="3" name="B"/><p:cNvSpPr/><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr>
          <p:spPr><a:xfrm><a:off x="838200" y="1825625"/><a:ext cx="10515600" cy="4351338"/></a:xfrm></p:spPr></p:sp>
        <p:sp><p:nvSpPr><p:cNvPr id="9" name="Deco"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
          <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="12700" cy="12700"/></a:xfrm><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></p:spPr></p:sp>
      </p:spTree></p:cSld></p:sldLayout>''',
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels': '<Relationships $rels><Relationship Id="rId1" Type="slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>',
      'ppt/slideMasters/slideMaster1.xml': '''<p:sldMaster $ns><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg2"/></p:bgRef></p:bg><p:spTree/></p:cSld>
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1"/>
        <p:txStyles>
          <p:titleStyle><a:lvl1pPr algn="ctr"><a:defRPr sz="4400" b="1"><a:solidFill><a:schemeClr val="tx2"/></a:solidFill></a:defRPr></a:lvl1pPr></p:titleStyle>
          <p:bodyStyle><a:lvl1pPr marL="228600" indent="-228600"><a:buChar char="•"/><a:defRPr sz="2800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill></a:defRPr></a:lvl1pPr>
            <a:lvl2pPr marL="685800" indent="-228600"><a:buFont typeface="Wingdings"/><a:buChar char="§"/><a:defRPr sz="2400"/></a:lvl2pPr></p:bodyStyle>
        </p:txStyles></p:sldMaster>''',
      'ppt/slideMasters/_rels/slideMaster1.xml.rels': '<Relationships $rels><Relationship Id="rId1" Type="theme" Target="../theme/theme1.xml"/></Relationships>',
      'ppt/theme/theme1.xml': '''<a:theme $ns><a:themeElements><a:clrScheme name="x">
        <a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
        <a:dk2><a:srgbClr val="1F3864"/></a:dk2><a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
        <a:accent1><a:srgbClr val="4472C4"/></a:accent1></a:clrScheme></a:themeElements></a:theme>''',
      'ppt/media/image1.png': pngBytes,
    });

    final deck = parsePptx(pptx);
    final slide = deck.slides.single;

    test('slide size and background from master via clrMap', () {
      expect(deck.width, 960);
      expect(deck.height, 540);
      expect(slide.background, const Color(0xFFEEECE1));
    });

    test('layout decoration rendered, empty placeholder hidden', () {
      expect(slide.shapes.first.fill, const Color(0xFFFF0000));
      expect(slide.shapes.where((s) => s.text != null).length, 2);
    });

    test('title inherits position from layout and style from master', () {
      final title = slide.shapes.firstWhere((s) => s.text?.paragraphs.first.plainText == 'Judul Slide');
      expect(title.rect.left, closeTo(66, 0.1));
      expect(title.rect.top, closeTo(28.75, 0.1));
      final p = title.text!.paragraphs.single;
      expect(p.align, TextAlign.center);
      expect(p.runs.single.size, 44);
      expect(p.runs.single.bold, isTrue);
      expect(p.runs.single.color, const Color(0xFF1F3864));
      expect(p.bullet, isNull);
    });

    test('body bullets per level from master bodyStyle', () {
      final body = slide.shapes.firstWhere((s) => s.text?.paragraphs.first.plainText == 'Poin satu');
      final ps = body.text!.paragraphs;
      expect(ps[0].bullet, '•');
      expect(ps[0].runs.single.size, 28);
      expect(ps[1].bullet, '▪'); // Wingdings § = kotak kecil
      expect(ps[1].runs.single.size, 24);
      expect(ps[1].marginLeft, 54);
    });

    test('group transform and scheme color modifiers', () {
      final circle = slide.shapes.firstWhere((s) => s.geom == ShapeGeom.ellipse);
      expect(circle.rect, const Rect.fromLTWH(200, 100, 100, 100));
      final hsl = HSLColor.fromColor(circle.fill!);
      expect(hsl.lightness, closeTo(HSLColor.fromColor(const Color(0xFF4472C4)).lightness / 2, 0.01));
    });

    test('picture with rotation, and notes', () {
      final pic = slide.shapes.firstWhere((s) => s.image != null);
      expect(pic.rotation, 90);
      expect(slide.notes, 'Catatan pembicara');
    });
  });

  test('PPTX content audit: hidden slides, orphan placeholders, tables keep all text', () {
    const ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
    const rels = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
    String ph(String type, String text) => '<p:sp><p:nvSpPr><p:cNvPr id="2" name="x"/><p:cNvSpPr/><p:nvPr><p:ph type="$type"/></p:nvPr></p:nvSpPr><p:spPr/>'
        '<p:txBody><a:bodyPr/><a:p><a:r><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>';
    final slide2 = '''<p:sld $ns show="0"><p:cSld><p:spTree>${ph('title', 'Slide rahasia')}
      <p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="3" name="t"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblGrid><a:gridCol w="914400"/><a:gridCol w="914400"/></a:tblGrid>
        <a:tr h="370840"><a:tc><a:txBody><a:bodyPr/><a:p><a:r><a:t>Rp 5.000</a:t></a:r></a:p></a:txBody></a:tc><a:tc><a:txBody><a:bodyPr/><a:p><a:r><a:t>Q3</a:t></a:r></a:p></a:txBody></a:tc></a:tr>
        </a:tbl></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>''';
    final data = zip({
      'ppt/presentation.xml': '<p:presentation $ns><p:sldIdLst><p:sldId id="256" r:id="rId1"/><p:sldId id="257" r:id="rId2"/></p:sldIdLst></p:presentation>',
      'ppt/_rels/presentation.xml.rels': '<Relationships $rels><Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/><Relationship Id="rId2" Type="slide" Target="slides/slide2.xml"/></Relationships>',
      // Tanpa layout/master: placeholder tidak punya posisi sama sekali
      'ppt/slides/slide1.xml': '<p:sld $ns><p:cSld><p:spTree>${ph('title', 'Judul tanpa posisi')}${ph('body', 'Isi penting tanpa posisi')}</p:spTree></p:cSld></p:sld>',
      'ppt/slides/slide2.xml': slide2,
    });
    final deck = parsePptx(data);
    expect(deck.slides.length, 2);
    expect(deck.slides[1].hidden, isTrue);

    // Audit: semua a:t di XML slide ada di model
    String modelText(SlideData sl) => [
          for (final sh in sl.shapes) ...[
            for (final p in sh.text?.paragraphs ?? <SlideParagraph>[]) p.plainText,
            for (final row in sh.table?.rows ?? <List<SlideTableCell>>[])
              for (final c in row) c.text.paragraphs.map((p) => p.plainText).join(),
          ]
        ].join('|');
    final arc = ZipDecoder().decodeBytes(data);
    for (var i = 0; i < 2; i++) {
      final xml = XmlDocument.parse(utf8.decode(arc.findFile('ppt/slides/slide${i + 1}.xml')!.content as List<int>));
      final model = modelText(deck.slides[i]);
      for (final t in xml.descendantElements.where((e) => e.localName == 't')) {
        expect(model, contains(t.innerText), reason: 'slide ${i + 1} kehilangan "${t.innerText}"');
      }
    }
  });

  group('OpenDocument', () {
    const odfNs = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
        'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
        'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
        'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" '
        'xmlns:office2="x"';

    test('ODT: headings, bold span, numbered list, table, image', () {
      final odt = zip({
        'content.xml': '''<office:document-content $odfNs><office:automatic-styles>
          <style:style style:name="T1" style:family="text"><style:text-properties fo:font-weight="bold" fo:color="#FF0000"/></style:style>
          <style:style style:name="P1" style:family="paragraph"><style:paragraph-properties fo:text-align="center"/></style:style>
          <text:list-style style:name="L1"><text:list-level-style-number text:level="1" style:num-format="1" style:num-suffix="."/></text:list-style>
          </office:automatic-styles><office:body><office:text>
          <text:h text:outline-level="2">Judul</text:h>
          <text:p text:style-name="P1">Halo <text:span text:style-name="T1">tebal</text:span><text:s text:c="2"/>!</text:p>
          <text:list text:style-name="L1"><text:list-item><text:p>Satu</text:p></text:list-item><text:list-item><text:p>Dua</text:p></text:list-item></text:list>
          <table:table><table:table-column table:number-columns-repeated="2"/>
            <table:table-row><table:table-cell table:number-columns-spanned="2"><text:p>Gabung</text:p></table:table-cell><table:covered-table-cell/></table:table-row>
            <table:table-row><table:table-cell><text:p>A</text:p></table:table-cell><table:table-cell><text:p>B</text:p></table:table-cell></table:table-row>
          </table:table>
          <text:p><draw:frame svg:width="2cm" svg:height="1cm"><draw:image xlink:href="Pictures/a.png"/></draw:frame></text:p>
          </office:text></office:body></office:document-content>''',
        'Pictures/a.png': pngBytes,
      });
      final doc = parseOdt(odt);
      final h = doc.blocks[0] as DocParagraph;
      expect(h.headingLevel, 2);
      final p = doc.blocks[1] as DocParagraph;
      expect(p.align, TextAlign.center);
      expect(p.plainText, 'Halo tebal  !');
      final bold = p.inlines[1] as DocText;
      expect(bold.bold, isTrue);
      expect(bold.color, const Color(0xFFFF0000));
      expect((doc.blocks[2] as DocParagraph).listLabel, '1.');
      expect((doc.blocks[3] as DocParagraph).listLabel, '2.');
      final t = doc.blocks[4] as DocTable;
      expect(t.rows[0].cells.length, 1);
      expect(t.rows[0].cells.single.colSpan, 2);
      expect(t.rows[1].cells.length, 2);
      final img = (doc.blocks[5] as DocParagraph).inlines.single as DocImage;
      expect(img.bytes, isNotNull);
      expect(img.width, closeTo(56.7, 0.1));
    });

    test('ODS: display text, repeats, spans, styles', () {
      final ods = zip({
        'content.xml': '''<office:document-content $odfNs><office:automatic-styles>
          <style:style style:name="ce1" style:family="table-cell"><style:table-cell-properties fo:background-color="#00FF00"/>
            <style:text-properties fo:font-weight="bold"/></style:style>
          <style:style style:name="co1" style:family="table-column"><style:table-column-properties style:column-width="3cm"/></style:style>
          </office:automatic-styles><office:body><office:spreadsheet><table:table table:name="Lembar1">
          <table:table-column table:style-name="co1"/><table:table-column table:number-columns-repeated="1023"/>
          <table:table-row><table:table-cell table:style-name="ce1" office:value-type="string"><text:p>Nama</text:p></table:table-cell>
            <table:table-cell office:value-type="currency" office:value="1500"><text:p>Rp1.500</text:p></table:table-cell>
            <table:table-cell table:number-columns-repeated="1022"/></table:table-row>
          <table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-spanned="2"><text:p>x</text:p></table:table-cell><table:covered-table-cell/></table:table-row>
          <table:table-row table:number-rows-repeated="1048570"><table:table-cell table:number-columns-repeated="1024"/></table:table-row>
          </table:table></office:spreadsheet></office:body></office:document-content>''',
      });
      final s = parseOds(ods).sheets.single;
      expect(s.name, 'Lembar1');
      expect(s.cell(0, 0)!.text, 'Nama');
      expect(s.cell(0, 0)!.style.bold, isTrue);
      expect(s.cell(0, 0)!.style.fill, const Color(0xFF00FF00));
      expect(s.cell(0, 1)!.text, 'Rp1.500');
      expect(s.cell(0, 1)!.isNumber, isTrue);
      expect(s.cell(2, 0)!.text, 'x');
      expect(s.merges.length, 2);
      expect(s.rowCount, 3);
      expect(s.colCount, 2);
      expect(s.colWidth(0), closeTo(113.4, 0.1));
      expect(s.cell(0, 1)!.editText, '1500', reason: 'formula bar = nilai asli');
    });

    test('ODP: page size, frames with text, shape fill, list bullets', () {
      final odp = zip({
        'styles.xml': '''<office:document-styles $odfNs><office:automatic-styles>
          <style:page-layout style:name="PM1"><style:page-layout-properties fo:page-width="28cm" fo:page-height="15.75cm"/></style:page-layout>
          </office:automatic-styles><office:master-styles><style:master-page style:name="Default" style:page-layout-name="PM1">
          <draw:frame presentation:class="title" svg:x="1cm" svg:y="1cm" svg:width="5cm" svg:height="2cm"><draw:text-box/></draw:frame>
          </style:master-page></office:master-styles></office:document-styles>''',
        'content.xml': '''<office:document-content $odfNs><office:automatic-styles>
          <style:style style:name="gr1" style:family="graphic"><style:graphic-properties draw:fill="solid" draw:fill-color="#FF0000" draw:stroke="none"/></style:style>
          <style:style style:name="pr1" style:family="presentation"><style:graphic-properties draw:fill="none" draw:textarea-vertical-align="middle"/>
            <style:text-properties fo:font-size="40pt"/></style:style>
          </office:automatic-styles><office:body><office:presentation>
          <draw:page draw:name="p1" draw:master-page-name="Default">
            <draw:frame presentation:style-name="pr1" presentation:class="title" svg:x="2cm" svg:y="1cm" svg:width="20cm" svg:height="3cm"><draw:text-box><text:p>Judul ODP</text:p></draw:text-box></draw:frame>
            <draw:frame presentation:class="outline" presentation:placeholder="true" svg:x="2cm" svg:y="5cm" svg:width="20cm" svg:height="8cm"><draw:text-box/></draw:frame>
            <draw:custom-shape draw:style-name="gr1" svg:x="1cm" svg:y="10cm" svg:width="4cm" svg:height="2cm"><draw:enhanced-geometry draw:type="ellipse"/></draw:custom-shape>
            <draw:frame svg:x="5cm" svg:y="5cm" svg:width="10cm" svg:height="4cm"><draw:text-box><text:list><text:list-item><text:p>Butir</text:p></text:list-item></text:list></draw:text-box></draw:frame>
          </draw:page></office:presentation></office:body></office:document-content>''',
      });
      final deck = parseOdp(odp);
      expect(deck.width, closeTo(793.7, 0.1));
      final shapes = deck.slides.single.shapes;
      expect(shapes.length, 3); // placeholder master & kosong tidak tampil
      final title = shapes[0];
      expect(title.text!.paragraphs.single.runs.single.size, 40);
      expect(title.text!.anchor, TextAnchor.center);
      expect(title.fill, isNull);
      expect(shapes[1].geom, ShapeGeom.ellipse);
      expect(shapes[1].fill, const Color(0xFFFF0000));
      expect(shapes[1].lineColor, isNull);
      expect(shapes[2].text!.paragraphs.single.bullet, '•');
    });
  });

  test('text encoding: Windows-1252 CSV and UTF-16 are decoded without loss', () {
    // "Café;Señor;“kutip”" dalam Windows-1252
    final cp1252 = [0x43, 0x61, 0x66, 0xE9, 0x3B, 0x53, 0x65, 0xF1, 0x6F, 0x72, 0x3B, 0x93, 0x6B, 0x75, 0x74, 0x69, 0x70, 0x94];
    final s = parseCsv(Uint8List.fromList(cp1252)).sheets.single;
    expect([for (var c = 0; c < 3; c++) s.cell(0, c)!.text], ['Café', 'Señor', '“kutip”']);
    final utf16 = [0xFF, 0xFE, 0x41, 0x00, 0x3B, 0x00, 0xE9, 0x00];
    expect(decodeText(utf16), 'A;é');
    expect(decodeText(utf8.encode('Rupiah Rp 1.000 – “ok”')), 'Rupiah Rp 1.000 – “ok”');
  });

  test('CSV: semicolon delimiter, quotes, embedded newline', () {
    final csv = utf8.encode('﻿Nama;Harga;Catatan\n"Kopi; Susu";15000;"baris1\nbaris2"\r\nTeh;8000;"kata ""kutip"""\n');
    final s = parseCsv(Uint8List.fromList(csv)).sheets.single;
    expect(s.rowCount, 3);
    expect(s.colCount, 3);
    expect(s.cell(0, 0)!.text, 'Nama');
    expect(s.cell(0, 0)!.style.bold, isTrue);
    expect(s.cell(1, 0)!.text, 'Kopi; Susu');
    expect(s.cell(1, 1)!.isNumber, isTrue);
    expect(s.cell(1, 2)!.text, 'baris1\nbaris2');
    expect(s.cell(2, 2)!.text, 'kata "kutip"');
  });
}
