import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_app_hd/screens/xlsx_viewer_screen.dart';
import 'package:super_app_hd/utils/office/chart_model.dart';
import 'package:super_app_hd/utils/office/chart_parser.dart';
import 'package:super_app_hd/utils/office/chart_view.dart';
import 'package:super_app_hd/utils/office/doc_model.dart';
import 'package:super_app_hd/utils/office/docx_parser.dart';
import 'package:super_app_hd/utils/office/office_common.dart';
import 'package:super_app_hd/utils/office/pptx_parser.dart';
import 'package:super_app_hd/utils/office/xlsx_parser.dart';
import 'package:xml/xml.dart';
import 'office_fixtures.dart';

const _c = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

String ser(int idx, String name, List<num> vals, {String? color, List<String>? cats}) => '''
<c:ser><c:idx val="$idx"/><c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>$name</c:v></c:pt></c:strCache></c:strRef></c:tx>
${color == null ? '' : '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill></c:spPr>'}
${cats == null ? '' : '<c:cat><c:numRef><c:numCache><c:formatCode>mmm-yy</c:formatCode><c:ptCount val="${cats.length}"/>${[for (var i = 0; i < cats.length; i++) '<c:pt idx="$i"><c:v>${cats[i]}</c:v></c:pt>'].join()}</c:numCache></c:numRef></c:cat>'}
<c:val><c:numRef><c:numCache><c:ptCount val="${vals.length}"/>${[for (var i = 0; i < vals.length; i++) '<c:pt idx="$i"><c:v>${vals[i]}</c:v></c:pt>'].join()}</c:numCache></c:numRef></c:val></c:ser>''';

final comboChart = '''<c:chartSpace $_c><c:chart>
<c:title><c:tx><c:rich><a:p><a:r><a:t>Penjualan 2024</a:t></a:r></a:p></c:rich></c:tx></c:title>
<c:plotArea>
<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>${ser(0, 'Omzet', [120, 90, 150], cats: ['45292', '45323', '45352'])}${ser(1, 'Biaya', [80, 70, 95])}<c:dLbls><c:showVal val="1"/></c:dLbls><c:axId val="1"/><c:axId val="2"/></c:barChart>
<c:lineChart><c:grouping val="standard"/>${ser(2, 'Margin %', [33, 22, 37], color: 'FF0000')}<c:axId val="3"/><c:axId val="4"/></c:lineChart>
</c:plotArea><c:legend><c:legendPos val="b"/></c:legend></c:chart></c:chartSpace>''';

void main() {
  test('OOXML combo chart: title, categories (date format), colors, secondary axis', () {
    final scheme = {'accent1': const Color(0xFF4472C4), 'accent2': const Color(0xFFED7D31)};
    final c = parseOoxmlChart(XmlDocument.parse(comboChart), scheme)!;
    expect(c.title, 'Penjualan 2024');
    expect(c.categories, ['Jan-24', 'Feb-24', 'Mar-24']);
    expect(c.groups.length, 2);
    final bars = c.groups[0];
    expect(bars.kind, ChartKind.column);
    expect(bars.showValues, isTrue);
    expect(bars.series.map((s) => s.name), ['Omzet', 'Biaya']);
    expect(bars.series[0].color, const Color(0xFF4472C4));
    expect(bars.series[1].color, const Color(0xFFED7D31));
    expect(c.groups[1].kind, ChartKind.line);
    expect(c.groups[1].secondaryAxis, isTrue);
    expect(c.groups[1].series.single.color, const Color(0xFFFF0000));
    expect(c.legend, LegendPos.bottom);
  });

  test('pie chart gets per-slice colors; stacked/percent bars', () {
    final pie = parseOoxmlChart(XmlDocument.parse('''<c:chartSpace $_c><c:chart><c:plotArea>
      <c:pieChart><c:varyColors val="1"/>${ser(0, 'Pangsa', [50, 30, 20])}</c:pieChart></c:plotArea></c:chart></c:chartSpace>'''), {})!;
    expect(pie.isPie, isTrue);
    expect(pie.groups.single.series.single.pointColors.length, 3);
    expect(pie.legend, LegendPos.none);

    final bar = parseOoxmlChart(XmlDocument.parse('''<c:chartSpace $_c><c:chart><c:plotArea>
      <c:barChart><c:barDir val="bar"/><c:grouping val="percentStacked"/>${ser(0, 'A', [1, 2])}${ser(1, 'B', [3, 4])}</c:barChart></c:plotArea></c:chart></c:chartSpace>'''), {})!;
    expect(bar.groups.single.kind, ChartKind.bar);
    expect(bar.groups.single.stacked, isTrue);
    expect(bar.groups.single.percent, isTrue);
  });

  test('ODF chart from local data table', () {
    final pkg = OfficePackage(zip({
      'Object 1/content.xml': '''<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
          xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
          xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
          xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0">
        <office:automatic-styles><style:style style:name="s1" style:family="chart"><style:graphic-properties draw:fill-color="#00FF00"/></style:style></office:automatic-styles>
        <office:body><office:chart><chart:chart chart:class="chart:line"><chart:title><text:p>Tren</text:p></chart:title>
        <chart:legend chart:legend-position="bottom"/><chart:plot-area><chart:series chart:style-name="s1"/></chart:plot-area>
        <table:table><table:table-header-rows><table:table-row><table:table-cell/><table:table-cell><text:p>Kunjungan</text:p></table:table-cell></table:table-row></table:table-header-rows>
        <table:table-rows><table:table-row><table:table-cell><text:p>Senin</text:p></table:table-cell><table:table-cell office:value="10"/></table:table-row>
        <table:table-row><table:table-cell><text:p>Selasa</text:p></table:table-cell><table:table-cell office:value="14"/></table:table-row></table:table-rows></table:table>
        </chart:chart></office:chart></office:body></office:document-content>''',
    }));
    final c = parseOdfChart(pkg, './Object 1')!;
    expect(c.title, 'Tren');
    expect(c.categories, ['Senin', 'Selasa']);
    expect(c.groups.single.kind, ChartKind.line);
    expect(c.groups.single.series.single.values, [10, 14]);
    expect(c.groups.single.series.single.color, const Color(0xFF00FF00));
  });

  test('charts embedded in PPTX, DOCX and XLSX are parsed', () {
    const p = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"';
    const rels = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
    final deck = parsePptx(zip({
      'ppt/presentation.xml': '<p:presentation $p><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst></p:presentation>',
      'ppt/_rels/presentation.xml.rels': '<Relationships $rels><Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/></Relationships>',
      'ppt/slides/slide1.xml': '''<p:sld $p><p:cSld><p:spTree><p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="2" name="c"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>
        <p:xfrm><a:off x="0" y="0"/><a:ext cx="6350000" cy="3810000"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rC"/></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>''',
      'ppt/slides/_rels/slide1.xml.rels': '<Relationships $rels><Relationship Id="rC" Type="chart" Target="../charts/chart1.xml"/></Relationships>',
      'ppt/charts/chart1.xml': comboChart,
    }));
    final shape = deck.slides.single.shapes.single;
    expect(shape.chart?.title, 'Penjualan 2024');
    expect(shape.isChart, isFalse);

    final doc = parseDocx(zip({
      'word/document.xml': '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" $p
          xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body><w:p><w:r><w:drawing><wp:inline><wp:extent cx="5486400" cy="3200400"/>
          <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rC"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p></w:body></w:document>''',
      'word/_rels/document.xml.rels': '<Relationships $rels><Relationship Id="rC" Type="chart" Target="charts/chart1.xml"/></Relationships>',
      'word/charts/chart1.xml': comboChart,
    }));
    final dc = (doc.blocks.single as DocParagraph).inlines.single as DocChart;
    expect(dc.width, 432);
    expect(dc.chart.groups.length, 2);

    final book = parseXlsx(zip({
      'xl/workbook.xml': '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<Relationships $rels><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml': '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>x</t></is></c></row></sheetData><drawing r:id="rD" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></worksheet>',
      'xl/worksheets/_rels/sheet1.xml.rels': '<Relationships $rels><Relationship Id="rD" Type="drawing" Target="../drawings/drawing1.xml"/></Relationships>',
      'xl/drawings/drawing1.xml': '''<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" $p>
        <xdr:twoCellAnchor><xdr:from><xdr:col>2</xdr:col><xdr:colOff>95250</xdr:colOff><xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>
          <xdr:to><xdr:col>9</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>16</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>
          <xdr:graphicFrame><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rC"/></a:graphicData></a:graphic></xdr:graphicFrame></xdr:twoCellAnchor>
        <xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>20</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="952500" cy="476250"/>
          <xdr:pic><xdr:blipFill><a:blip r:embed="rI"/></xdr:blipFill></xdr:pic></xdr:oneCellAnchor></xdr:wsDr>''',
      'xl/drawings/_rels/drawing1.xml.rels': '<Relationships $rels><Relationship Id="rC" Type="chart" Target="../charts/chart1.xml"/><Relationship Id="rI" Type="image" Target="../media/logo.png"/></Relationships>',
      'xl/charts/chart1.xml': comboChart,
      'xl/media/logo.png': pngBytes,
    }));
    final sheet = book.sheets.single;
    expect(sheet.drawings.length, 2);
    expect(sheet.drawings[0].chart?.title, 'Penjualan 2024');
    expect(sheet.drawings[0].fromCol, 2);
    expect(sheet.drawings[0].fromColOff, 10);
    expect(sheet.drawings[0].toRow, 16);
    expect(sheet.drawings[1].image, isNotNull);
    expect(sheet.drawings[1].width, 100);
    expect(sheet.rowCount, 21);

    // Grid dengan drawing dirender tanpa error
  });

  testWidgets('every chart kind paints without errors', (tester) async {
    final cats = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei kategori panjang sekali'];
    ChartSeries s(String n, List<double?> v, Color c) => ChartSeries(name: n, values: v, color: c,
        pointColors: {for (var i = 0; i < v.length; i++) i: kDefaultChartPalette[i % 6]});
    final kinds = <ChartData>[
      for (final k in [ChartKind.column, ChartKind.bar, ChartKind.line, ChartKind.area, ChartKind.radar])
        for (final stacked in [false, true])
          ChartData(title: '$k', categories: cats, groups: [
            ChartGroup(kind: k, stacked: stacked, showValues: true, series: [
              s('A', [10, -5, 30, null, 12], Colors.blue),
              s('B', [3, 8, 4, 6, 1.5], Colors.orange),
            ]),
          ]),
      ChartData(categories: cats, legend: LegendPos.right, groups: [
        ChartGroup(kind: ChartKind.pie, series: [s('P', [1, 2, 3, 0, 4], Colors.red)]),
      ]),
      ChartData(categories: cats, groups: [
        ChartGroup(kind: ChartKind.doughnut, showValues: true, series: [s('D', [1, 2, 3, 4, 5], Colors.red)]),
      ]),
      ChartData(categories: const [], groups: [
        ChartGroup(kind: ChartKind.scatter, series: [
          ChartSeries(name: 'xy', values: const [1, 4, 9], xValues: const [1, 2, 3], color: Colors.green),
        ]),
      ]),
      ChartData(categories: cats, groups: [
        ChartGroup(kind: ChartKind.column, series: [s('x', [100, 200, 300, 400, 500], Colors.blue)]),
        ChartGroup(kind: ChartKind.line, secondaryAxis: true, percent: false, series: [s('%', [0.1, 0.2, 0.3, 0.2, 0.1], Colors.red)]),
      ]),
      ChartData(categories: const ['a'], groups: [
        ChartGroup(kind: ChartKind.column, series: [s('zero', [0], Colors.blue)]),
      ]),
    ];
    for (final c in kinds) {
      for (final size in [const Size(400, 260), const Size(90, 60)]) {
        await tester.pumpWidget(MaterialApp(
            home: Center(child: SizedBox.fromSize(size: size, child: ChartView(data: c)))));
        expect(tester.takeException(), isNull, reason: '${c.title ?? c.groups.first.kind} @ $size');
      }
    }
  });

  testWidgets('sheet grid renders drawings overlay', (tester) async {
    final chart = parseOoxmlChart(XmlDocument.parse(comboChart), {})!;
    final sheet = parseXlsx(zip({
      'xl/workbook.xml': '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml': '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>',
    })).sheets.single;
    expect(chart.title, isNotNull);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SheetGridView(sheet: sheet))));
    expect(tester.takeException(), isNull);
  });
}
