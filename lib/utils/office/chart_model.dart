import 'dart:ui';

/// Model grafik dari cache data chart (OOXML `numCache`/`strCache` atau
/// tabel lokal chart ODF) — bisa digambar tanpa menghitung rumus.
enum ChartKind { column, bar, line, area, pie, doughnut, scatter, radar }

enum LegendPos { none, right, bottom, top, left }

class ChartData {
  final String? title;
  final List<String> categories;
  final List<ChartGroup> groups;
  final LegendPos legend;
  final double? fontSize; // pt, null = otomatis
  final Color? background;

  const ChartData({
    this.title,
    required this.categories,
    required this.groups,
    this.legend = LegendPos.bottom,
    this.fontSize,
    this.background,
  });

  Iterable<ChartSeries> get allSeries => groups.expand((g) => g.series);

  bool get isPie => groups.isNotEmpty &&
      (groups.first.kind == ChartKind.pie || groups.first.kind == ChartKind.doughnut);
}

/// Satu jenis plot di dalam chart (chart kombinasi = beberapa grup).
class ChartGroup {
  final ChartKind kind;
  final List<ChartSeries> series;
  final bool stacked;
  final bool percent;
  final bool showValues;
  final bool markers;
  final bool secondaryAxis;

  const ChartGroup({
    required this.kind,
    required this.series,
    this.stacked = false,
    this.percent = false,
    this.showValues = false,
    this.markers = true,
    this.secondaryAxis = false,
  });
}

class ChartSeries {
  final String name;
  final List<double?> values;
  final List<double?>? xValues; // scatter
  final Color color;
  final Map<int, Color> pointColors; // warna per titik (pie)
  const ChartSeries({
    required this.name,
    required this.values,
    this.xValues,
    required this.color,
    this.pointColors = const {},
  });
}

/// Palet default Office (accent1..6) jika tema tidak tersedia.
const kDefaultChartPalette = [
  Color(0xFF4472C4), Color(0xFFED7D31), Color(0xFFA5A5A5), //
  Color(0xFFFFC000), Color(0xFF5B9BD5), Color(0xFF70AD47),
];
