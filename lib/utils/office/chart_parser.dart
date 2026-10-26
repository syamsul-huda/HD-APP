import 'dart:ui';
import 'package:xml/xml.dart';
import 'chart_model.dart';
import 'odf_styles.dart';
import 'office_common.dart';
import 'xlsx_parser.dart' show formatExcelNumber;

/// Warna skema tema (dk1, lt1, accent1..6, …) dari `theme1.xml`.
Map<String, Color> readThemeScheme(XmlDocument? theme) {
  final out = <String, Color>{};
  final cs = theme?.first('clrScheme');
  if (cs == null) return out;
  for (final e in cs.childElements) {
    final c = e.childElements.firstOrNull;
    if (c == null) continue;
    final color = c.localName == 'sysClr' ? sysColor(c) : parseHexColor(c.attr('val'));
    if (color != null) out[e.localName] = color;
  }
  return out;
}

// ── OOXML (PPTX / DOCX / XLSX) ──────────────────────────────────────────────

/// Parse `chartN.xml` (c:chartSpace). [scheme] = warna tema dokumen.
ChartData? parseOoxmlChart(XmlDocument doc, Map<String, Color> scheme) =>
    _OoxmlChart(scheme).parse(doc);

class _OoxmlChart {
  final Map<String, Color> scheme;
  _OoxmlChart(this.scheme);

  static const _mapped = {'tx1': 'dk1', 'bg1': 'lt1', 'tx2': 'dk2', 'bg2': 'lt2'};

  Color accent(int i) {
    final base = scheme['accent${i % 6 + 1}'] ?? kDefaultChartPalette[i % 6];
    // Seri ke-7 dst: variasi lebih gelap/terang seperti Office
    final round = i ~/ 6;
    if (round == 0) return base;
    return modLuminance(base, mod: round.isOdd ? 0.6 : 1, off: round.isOdd ? 0 : 0.4);
  }

  Color? colorOf(XmlElement? c) {
    if (c == null) return null;
    Color? base;
    switch (c.localName) {
      case 'srgbClr':
        base = parseHexColor(c.attr('val'));
      case 'schemeClr':
        final v = c.attr('val') ?? '';
        base = scheme[_mapped[v] ?? v];
      case 'sysClr':
        base = sysColor(c);
      case 'prstClr':
        base = switch (c.attr('val')) {
          'black' => kBlack,
          'white' => kWhite,
          'red' => const Color(0xFFFF0000),
          'blue' => const Color(0xFF0000FF),
          'green' => const Color(0xFF008000),
          _ => null,
        };
    }
    return base == null ? null : applyColorMods(base, c);
  }

  Color? fillOf(XmlElement? spPr, {bool line = false}) {
    if (spPr == null) return null;
    final src = line ? spPr.child('ln') : spPr;
    if (src == null) return null;
    if (src.child('noFill') != null) return null;
    final solid = src.child('solidFill');
    if (solid != null) return colorOf(solid.childElements.firstOrNull);
    final grad = src.child('gradFill')?.descendant('gs');
    if (grad != null) return colorOf(grad.childElements.firstOrNull);
    return null;
  }

  static String _richText(XmlElement? e) {
    if (e == null) return '';
    return e.descendantElements
        .where((x) => x.localName == 't' || x.localName == 'v')
        .map((x) => x.innerText)
        .join();
  }

  /// Titik cache (`<c:pt idx="i"><c:v>…</c:v></c:pt>`) → daftar sesuai ptCount.
  static (List<String?>, String?) _cache(XmlElement? ref) {
    if (ref == null) return ([], null);
    final cache = ref.descendantElements.firstWhere(
        (e) => e.localName == 'numCache' || e.localName == 'strCache' || e.localName == 'numLit' || e.localName == 'strLit' || e.localName == 'lvl',
        orElse: () => ref);
    final count = int.tryParse(cache.child('ptCount')?.attr('val') ?? '') ?? 0;
    final pts = cache.kids('pt').toList();
    final n = count > 0 ? count : (pts.isEmpty ? 0 : pts.map((p) => int.tryParse(p.attr('idx') ?? '') ?? 0).reduce((a, b) => a > b ? a : b) + 1);
    final out = List<String?>.filled(n, null);
    for (final p in pts) {
      final i = int.tryParse(p.attr('idx') ?? '') ?? -1;
      if (i >= 0 && i < n) out[i] = p.child('v')?.innerText;
    }
    return (out, cache.child('formatCode')?.innerText);
  }

  ChartData? parse(XmlDocument doc) {
    final chart = doc.first('chart');
    final plot = chart?.child('plotArea');
    if (chart == null || plot == null) return null;

    final groups = <ChartGroup>[];
    var categories = <String>[];
    String? firstAx;
    var seriesIndex = 0;

    for (final g in plot.childElements) {
      final name = g.localName;
      if (!name.endsWith('Chart')) continue;
      final kind = switch (name) {
        'barChart' || 'bar3DChart' =>
          g.child('barDir')?.attr('val') == 'bar' ? ChartKind.bar : ChartKind.column,
        'lineChart' || 'line3DChart' || 'stockChart' => ChartKind.line,
        'areaChart' || 'area3DChart' => ChartKind.area,
        'pieChart' || 'pie3DChart' || 'ofPieChart' => ChartKind.pie,
        'doughnutChart' => ChartKind.doughnut,
        'scatterChart' || 'bubbleChart' => ChartKind.scatter,
        'radarChart' => ChartKind.radar,
        _ => null,
      };
      if (kind == null) continue;
      final grouping = g.child('grouping')?.attr('val') ?? 'standard';
      // Office hanya memakai varyColors jika grup berisi satu seri
      final vary = g.child('varyColors')?.attr('val') == '1' && g.kids('ser').length == 1;
      final axId = g.kids('axId').firstOrNull?.attr('val');
      firstAx ??= axId;
      final groupLabels = g.child('dLbls')?.child('showVal')?.attr('val') == '1';

      final series = <ChartSeries>[];
      var anyValues = false;
      var markers = kind == ChartKind.line || kind == ChartKind.scatter || kind == ChartKind.radar;
      for (final ser in g.kids('ser')) {
        final idx = int.tryParse(ser.child('idx')?.attr('val') ?? '') ?? seriesIndex;
        final title = _richText(ser.child('tx'));
        final isLine = kind == ChartKind.line || kind == ChartKind.scatter || kind == ChartKind.radar;
        final color = fillOf(ser.child('spPr'), line: isLine) ??
            fillOf(ser.child('spPr')) ??
            accent(idx);

        final (vals, _) = _cache(ser.child('val') ?? ser.child('yVal'));
        final values = vals.map((v) => v == null ? null : double.tryParse(v)).toList();
        if (values.any((v) => v != null)) anyValues = true;

        List<double?>? xs;
        if (kind == ChartKind.scatter) {
          final (x, _) = _cache(ser.child('xVal'));
          xs = x.map((v) => v == null ? null : double.tryParse(v)).toList();
        }

        if (categories.isEmpty) {
          final (cats, fmt) = _cache(ser.child('cat') ?? ser.child('xVal'));
          categories = cats.map((c) {
            if (c == null) return '';
            final n = double.tryParse(c);
            return n != null && fmt != null ? formatExcelNumber(n, fmt) : c;
          }).toList();
        }

        final points = <int, Color>{};
        for (final dp in ser.kids('dPt')) {
          final i = int.tryParse(dp.child('idx')?.attr('val') ?? '') ?? -1;
          final c = fillOf(dp.child('spPr'));
          if (i >= 0 && c != null) points[i] = c;
        }
        if (vary || kind == ChartKind.pie || kind == ChartKind.doughnut) {
          for (var i = 0; i < values.length; i++) {
            points.putIfAbsent(i, () => accent(i));
          }
        }
        if (ser.child('marker')?.child('symbol')?.attr('val') == 'none') markers = false;

        series.add(ChartSeries(
          name: title.isEmpty ? 'Series ${idx + 1}' : title,
          values: values,
          xValues: xs,
          color: color,
          pointColors: points,
        ));
        seriesIndex++;
      }
      if (series.isEmpty || !anyValues) continue;

      final showVals = groupLabels ||
          g.kids('ser').any((s) => s.child('dLbls')?.child('showVal')?.attr('val') == '1');
      groups.add(ChartGroup(
        kind: kind,
        series: series,
        stacked: grouping == 'stacked' || grouping == 'percentStacked',
        percent: grouping == 'percentStacked',
        showValues: showVals,
        markers: markers,
        secondaryAxis: groups.isNotEmpty && axId != null && axId != firstAx,
      ));
    }
    if (groups.isEmpty) return null;

    var title = _richText(chart.child('title')?.child('tx'));
    final autoDeleted = chart.child('autoTitleDeleted')?.attr('val') == '1';
    if (title.isEmpty && chart.child('title') != null && !autoDeleted) {
      final all = groups.expand((g) => g.series).toList();
      if (all.length == 1) title = all.first.name; // judul otomatis = nama seri
    }

    final legendEl = chart.child('legend');
    final legend = legendEl == null
        ? LegendPos.none
        : switch (legendEl.child('legendPos')?.attr('val')) {
            'r' || 'tr' => LegendPos.right,
            't' => LegendPos.top,
            'l' => LegendPos.left,
            _ => LegendPos.bottom,
          };

    final sz = doc.first('txPr')?.descendant('defRPr')?.attr('sz');
    final spPr = doc.rootElement.child('spPr');
    return ChartData(
      title: title.isEmpty ? null : title,
      categories: categories,
      groups: groups,
      legend: legend,
      fontSize: sz == null ? null : (int.tryParse(sz) ?? 1000) / 100,
      background: spPr?.child('noFill') != null ? null : (fillOf(spPr) ?? kWhite),
    );
  }
}

// ── OpenDocument (ODP / ODT / ODS) ───────────────────────────────────────────

/// Parse objek chart ODF (`Object 1/content.xml`) dari tabel data lokalnya.
ChartData? parseOdfChart(OfficePackage pkg, String objectDir) {
  final dir = objectDir.replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'/$'), '');
  final doc = pkg.xml('$dir/content.xml');
  // <office:chart> membungkus <chart:chart>: keduanya bernama lokal "chart"
  final chart = doc?.descendantElements
      .where((e) => e.localName == 'chart' && e.name.prefix == 'chart')
      .firstOrNull;
  if (doc == null || chart == null) return null;
  final styles = OdfStyles.forPart(pkg, '$dir/content.xml', '$dir/styles.xml');

  String? chartProp(String? style, String name) {
    for (final p in styles.props('chart', style, 'chart-properties').reversed) {
      final v = p.attr(name);
      if (v != null) return v;
    }
    return null;
  }

  Color? fillColor(String? style) {
    for (final p in styles.props('chart', style, 'graphic-properties').reversed) {
      final c = parseHexColor(p.attr('fill-color'));
      if (c != null) return c;
    }
    return null;
  }

  final plot = chart.child('plot-area');
  final cls = (chart.attr('class') ?? 'chart:bar').replaceFirst('chart:', '');
  final vertical = chartProp(plot?.attr('style-name'), 'vertical') == 'true';
  final stacked = chartProp(plot?.attr('style-name'), 'stacked') == 'true';
  final percent = chartProp(plot?.attr('style-name'), 'percentage') == 'true';

  ChartKind kindOf(String c) => switch (c) {
        'line' => ChartKind.line,
        'area' => ChartKind.area,
        'circle' => ChartKind.pie,
        'ring' => ChartKind.doughnut,
        'scatter' || 'bubble' => ChartKind.scatter,
        'radar' || 'filled-radar' => ChartKind.radar,
        _ => vertical ? ChartKind.bar : ChartKind.column,
      };

  // Tabel lokal: baris header = nama seri, kolom pertama = kategori
  final table = chart.descendant('table');
  if (table == null) return null;
  List<XmlElement> rowsOf(String container) => table
      .descendantElements
      .where((e) => e.localName == container)
      .expand((c) => c.kids('table-row'))
      .toList();
  final header = rowsOf('table-header-rows').firstOrNull;
  final body = rowsOf('table-rows');
  if (body.isEmpty) return null;

  String cellText(XmlElement c) => c.kids('p').map((p) => p.innerText).join(' ');
  List<XmlElement> cells(XmlElement r) => r.childElements
      .where((e) => e.localName == 'table-cell' || e.localName == 'covered-table-cell')
      .toList();

  final names = header == null ? <String>[] : cells(header).skip(1).map(cellText).toList();
  final categories = <String>[];
  final columns = <List<double?>>[];
  for (final r in body) {
    final cs = cells(r);
    if (cs.isEmpty) continue;
    categories.add(cellText(cs.first));
    for (var i = 1; i < cs.length; i++) {
      while (columns.length < i) {
        columns.add([]);
      }
      final v = cs[i].attr('value') ?? cellText(cs[i]);
      columns[i - 1].add(double.tryParse(v.replaceAll(',', '.')));
    }
  }

  final seriesEls = plot?.kids('series').toList() ?? [];
  final byKind = <ChartKind, List<ChartSeries>>{};
  for (var i = 0; i < columns.length; i++) {
    final el = i < seriesEls.length ? seriesEls[i] : null;
    final kind = kindOf((el?.attr('class') ?? 'chart:$cls').replaceFirst('chart:', ''));
    final points = <int, Color>{};
    if (kind == ChartKind.pie || kind == ChartKind.doughnut) {
      var p = 0;
      for (final dp in el?.kids('data-point') ?? const Iterable<XmlElement>.empty()) {
        final rep = int.tryParse(dp.attr('repeated') ?? '') ?? 1;
        final c = fillColor(dp.attr('style-name'));
        for (var k = 0; k < rep; k++, p++) {
          points[p] = c ?? kDefaultChartPalette[p % 6];
        }
      }
      for (var k = 0; k < columns[i].length; k++) {
        points.putIfAbsent(k, () => kDefaultChartPalette[k % 6]);
      }
    }
    (byKind[kind] ??= []).add(ChartSeries(
      name: i < names.length && names[i].isNotEmpty ? names[i] : 'Series ${i + 1}',
      values: columns[i],
      color: fillColor(el?.attr('style-name')) ?? kDefaultChartPalette[i % 6],
      pointColors: points,
    ));
  }
  if (byKind.isEmpty) return null;

  final legendEl = chart.child('legend');
  final title = chart.child('title')?.kids('p').map((p) => p.innerText).join(' ');
  return ChartData(
    title: title == null || title.isEmpty ? null : title,
    categories: categories,
    groups: [
      for (final e in byKind.entries)
        ChartGroup(kind: e.key, series: e.value, stacked: stacked || percent, percent: percent)
    ],
    legend: legendEl == null
        ? LegendPos.none
        : switch (legendEl.attr('legend-position')) {
            'bottom' => LegendPos.bottom,
            'top' => LegendPos.top,
            'start' => LegendPos.left,
            _ => LegendPos.right,
          },
  );
}
