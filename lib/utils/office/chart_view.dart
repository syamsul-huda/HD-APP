import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'chart_model.dart';
import 'office_fonts.dart';

/// Menggambar [ChartData] seperti chart Office. [ptScale] = unit kanvas
/// per point (slide: 1, dokumen: skala zoom, spreadsheet: 4/3).
class ChartView extends StatelessWidget {
  final ChartData data;
  final double ptScale;
  const ChartView({super.key, required this.data, this.ptScale = 1});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: ChartPainter(data, ptScale),
        size: Size.infinite,
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  final ChartData data;
  final double ptScale;
  ChartPainter(this.data, this.ptScale);

  static const _text = Color(0xFF595959);
  static const _grid = Color(0xFFD9D9D9);

  late double _fs;

  TextPainter _tp(String s, {double? size, Color color = _text, bool bold = false, double? maxW}) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size ?? _fs,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: kOfficeSans,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxW == null ? 1 : 2,
      ellipsis: '…',
    )..layout(maxWidth: maxW ?? double.infinity);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final minSide = math.min(size.width, size.height);
    _fs = math.min((data.fontSize ?? 10) * ptScale, minSide / 11).clamp(4.0, 40.0);
    final pad = _fs * 0.7;
    final bg = data.background;
    if (bg != null) canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    var area = Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad);

    // Judul
    final title = data.title;
    if (title != null && title.isNotEmpty) {
      final tp = _tp(title, size: _fs * 1.45, color: const Color(0xFF404040), maxW: area.width);
      tp.paint(canvas, Offset(area.center.dx - tp.width / 2, area.top));
      area = Rect.fromLTRB(area.left, area.top + tp.height + pad * 0.6, area.right, area.bottom);
    }

    area = _legend(canvas, area, pad);
    if (area.width < 10 || area.height < 10) {
      canvas.restore();
      return;
    }

    if (data.isPie) {
      _pie(canvas, area);
    } else if (data.groups.first.kind == ChartKind.radar) {
      _radar(canvas, area);
    } else if (data.groups.any((g) => g.kind == ChartKind.scatter)) {
      _scatter(canvas, area);
    } else {
      _cartesian(canvas, area);
    }
    canvas.restore();
  }

  // ── Legenda ───────────────────────────────────────────────────────────────

  List<(String, Color, bool)> get _legendItems {
    if (data.isPie) {
      final s = data.groups.first.series.first;
      return [
        for (var i = 0; i < s.values.length; i++)
          (i < data.categories.length ? data.categories[i] : '${i + 1}',
              s.pointColors[i] ?? kDefaultChartPalette[i % 6], false)
      ];
    }
    return [
      for (final g in data.groups)
        for (final s in g.series) (s.name, s.color, g.kind == ChartKind.line || g.kind == ChartKind.scatter)
    ];
  }

  Rect _legend(Canvas canvas, Rect area, double pad) {
    if (data.legend == LegendPos.none) return area;
    final items = _legendItems;
    if (items.isEmpty) return area;
    final sw = _fs * 0.75;
    final gap = _fs * 0.4;
    final tps = items.map((i) => _tp(i.$1, maxW: area.width * 0.4)).toList();

    void drawItem(int i, Offset o) {
      final (_, color, line) = items[i];
      final cy = o.dy + tps[i].height / 2;
      if (line) {
        canvas.drawLine(Offset(o.dx, cy), Offset(o.dx + sw * 1.4, cy), Paint()
          ..color = color
          ..strokeWidth = math.max(1, _fs * 0.18));
        tps[i].paint(canvas, Offset(o.dx + sw * 1.4 + gap, o.dy));
      } else {
        canvas.drawRect(Rect.fromLTWH(o.dx, cy - sw / 2, sw, sw), Paint()..color = color);
        tps[i].paint(canvas, Offset(o.dx + sw + gap, o.dy));
      }
    }

    double itemW(int i) => (items[i].$3 ? sw * 1.4 : sw) + gap + tps[i].width;

    if (data.legend == LegendPos.right || data.legend == LegendPos.left) {
      final w = List.generate(items.length, itemW).fold<double>(0, math.max);
      final h = tps.fold<double>(0, (a, t) => a + t.height + gap);
      final x = data.legend == LegendPos.right ? area.right - w : area.left;
      var y = area.center.dy - h / 2;
      for (var i = 0; i < items.length; i++) {
        drawItem(i, Offset(x, y));
        y += tps[i].height + gap;
      }
      return data.legend == LegendPos.right
          ? Rect.fromLTRB(area.left, area.top, area.right - w - pad, area.bottom)
          : Rect.fromLTRB(area.left + w + pad, area.top, area.right, area.bottom);
    }

    // Atas / bawah: baris-baris yang di-wrap, rata tengah
    final rows = <List<int>>[[]];
    var rowW = 0.0;
    for (var i = 0; i < items.length; i++) {
      final w = itemW(i) + _fs;
      if (rowW + w > area.width && rows.last.isNotEmpty) {
        rows.add([]);
        rowW = 0;
      }
      rows.last.add(i);
      rowW += w;
    }
    final lineH = tps.fold<double>(0, (a, t) => math.max(a, t.height)) + gap * 0.5;
    final totalH = rows.length * lineH;
    var y = data.legend == LegendPos.bottom ? area.bottom - totalH : area.top;
    for (final row in rows) {
      final w = row.fold<double>(0, (a, i) => a + itemW(i) + _fs) - _fs;
      var x = area.center.dx - w / 2;
      for (final i in row) {
        drawItem(i, Offset(x, y));
        x += itemW(i) + _fs;
      }
      y += lineH;
    }
    return data.legend == LegendPos.bottom
        ? Rect.fromLTRB(area.left, area.top, area.right, area.bottom - totalH - pad * 0.6)
        : Rect.fromLTRB(area.left, area.top + totalH + pad * 0.6, area.right, area.bottom);
  }

  // ── Angka & skala ────────────────────────────────────────────────────────

  static double _nice(double range, bool round) {
    if (range <= 0) return 1;
    final exp = (math.log(range) / math.ln10).floorToDouble();
    final f = range / math.pow(10, exp);
    final double nf;
    if (round) {
      nf = f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10));
    } else {
      nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
    }
    return nf * math.pow(10, exp);
  }

  static (double, double, double) _scale(double lo, double hi) {
    if (lo == hi) {
      hi = lo == 0 ? 1 : lo.abs() * 1.2 + (lo > 0 ? 0 : 0);
      if (lo > 0) lo = 0;
    }
    final step = _nice(_nice(hi - lo, false) / 5, true);
    final min = (lo / step).floorToDouble() * step;
    final max = (hi / step).ceilToDouble() * step;
    return (min, max == min ? min + step : max, step);
  }

  static String _fmt(double v, double step, {bool percent = false}) {
    final dec = step >= 1 || step == 0 ? 0 : math.min(4, (-math.log(step) / math.ln10).ceil());
    var s = v.abs().toStringAsFixed(dec);
    final parts = s.split('.');
    final ip = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    s = parts.length > 1 ? '$ip.${parts[1]}' : ip;
    return '${v < 0 ? '-' : ''}$s${percent ? '%' : ''}';
  }

  // ── Kartesius: kolom / batang / garis / area ─────────────────────────────

  (double, double) _range(Iterable<ChartGroup> groups, int n) {
    var lo = 0.0, hi = 0.0;
    var any = false;
    for (final g in groups) {
      if (g.percent) {
        lo = math.min(lo, 0);
        hi = math.max(hi, 100);
        any = true;
        continue;
      }
      if (g.stacked) {
        for (var i = 0; i < n; i++) {
          var pos = 0.0, neg = 0.0;
          for (final s in g.series) {
            final v = i < s.values.length ? s.values[i] ?? 0 : 0;
            if (v >= 0) {
              pos += v;
            } else {
              neg += v;
            }
          }
          hi = math.max(hi, pos);
          lo = math.min(lo, neg);
          any = true;
        }
      } else {
        for (final s in g.series) {
          for (final v in s.values) {
            if (v == null) continue;
            hi = math.max(hi, v);
            lo = math.min(lo, v);
            any = true;
          }
        }
      }
    }
    return any ? (lo, hi) : (0, 1);
  }

  void _cartesian(Canvas canvas, Rect area) {
    final n = math.max(
        data.categories.length, data.allSeries.fold<int>(0, (m, s) => math.max(m, s.values.length)));
    if (n == 0) return;
    final horizontal = data.groups.any((g) => g.kind == ChartKind.bar);
    final primary = data.groups.where((g) => !g.secondaryAxis).toList();
    final secondary = data.groups.where((g) => g.secondaryAxis).toList();
    final (lo, hi) = _range(primary.isEmpty ? data.groups : primary, n);
    final (min, max, step) = _scale(lo, hi);
    final percent = primary.any((g) => g.percent);
    (double, double, double)? sec;
    if (secondary.isNotEmpty) {
      final (l2, h2) = _range(secondary, n);
      sec = _scale(l2, h2);
    }

    // Label sumbu nilai
    final ticks = <double>[];
    for (var v = min; v <= max + step / 2; v += step) {
      ticks.add(v);
    }
    final tickTps = ticks.map((v) => _tp(_fmt(v, step, percent: percent))).toList();
    final secTps = sec == null
        ? <TextPainter>[]
        : [for (var v = sec.$1; v <= sec.$2 + sec.$3 / 2; v += sec.$3) _tp(_fmt(v, sec.$3))];

    final catLabels = List.generate(n, (i) => i < data.categories.length ? data.categories[i] : '${i + 1}');
    final gap = _fs * 0.5;
    Rect plot;
    if (horizontal) {
      final catTps = catLabels.map((c) => _tp(c, maxW: area.width * 0.3)).toList();
      final leftW = catTps.fold<double>(0, (m, t) => math.max(m, t.width));
      final bottomH = tickTps.fold<double>(0, (m, t) => math.max(m, t.height));
      plot = Rect.fromLTRB(area.left + leftW + gap, area.top, area.right - tickTps.last.width / 2, area.bottom - bottomH - gap);
      final band = plot.height / n;
      for (var i = 0; i < n; i++) {
        final t = catTps[i];
        // Kategori pertama di bawah seperti Excel
        final cy = plot.bottom - band * (i + 0.5);
        if (band >= t.height * 0.8 || i % (t.height / band).ceil() == 0) {
          t.paint(canvas, Offset(plot.left - gap - t.width, cy - t.height / 2));
        }
      }
      for (var k = 0; k < ticks.length; k++) {
        final x = plot.left + (ticks[k] - min) / (max - min) * plot.width;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), Paint()
          ..color = _grid
          ..strokeWidth = math.max(0.5, _fs * 0.06));
        tickTps[k].paint(canvas, Offset(x - tickTps[k].width / 2, plot.bottom + gap * 0.6));
      }
    } else {
      final leftW = tickTps.fold<double>(0, (m, t) => math.max(m, t.width));
      final rightW = secTps.fold<double>(0, (m, t) => math.max(m, t.width));
      // Label kategori: miring jika tidak muat
      final avail = (area.width - leftW - rightW - gap * 2) / n;
      final catTps = catLabels.map((c) => _tp(c, maxW: math.max(avail * 0.95, _fs * 2))).toList();
      final maxCatW = catTps.fold<double>(0, (m, t) => math.max(m, t.width));
      final rotate = maxCatW > avail * 0.98 && n > 1;
      final unrotH = catTps.fold<double>(0, (m, t) => math.max(m, t.height));
      final catH = rotate
          ? math.min(area.height * 0.35, catLabels.map((c) => _tp(c).width).fold<double>(0, math.max) * 0.72 + unrotH)
          : unrotH;
      plot = Rect.fromLTRB(area.left + leftW + gap, area.top + unrotH * 0.5,
          area.right - (rightW > 0 ? rightW + gap : _fs * 0.3), area.bottom - catH - gap);
      if (plot.height < _fs) return;
      final band = plot.width / n;
      final every = rotate ? math.max(1, (unrotH * 1.3 / band).ceil()) : 1;
      for (var i = 0; i < n; i += every) {
        final cx = plot.left + band * (i + 0.5);
        if (rotate) {
          final t = _tp(catLabels[i]);
          canvas.save();
          canvas.translate(cx, plot.bottom + gap * 0.6);
          canvas.rotate(-math.pi / 4);
          t.paint(canvas, Offset(-t.width, -t.height / 2));
          canvas.restore();
        } else {
          catTps[i].paint(canvas, Offset(cx - catTps[i].width / 2, plot.bottom + gap * 0.6));
        }
      }
      for (var k = 0; k < ticks.length; k++) {
        final y = plot.bottom - (ticks[k] - min) / (max - min) * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), Paint()
          ..color = _grid
          ..strokeWidth = math.max(0.5, _fs * 0.06));
        tickTps[k].paint(canvas, Offset(plot.left - gap - tickTps[k].width, y - tickTps[k].height / 2));
      }
      if (sec != null) {
        for (var k = 0; k < secTps.length; k++) {
          final v = sec.$1 + k * sec.$3;
          final y = plot.bottom - (v - sec.$1) / (sec.$2 - sec.$1) * plot.height;
          secTps[k].paint(canvas, Offset(plot.right + gap, y - secTps[k].height / 2));
        }
      }
    }
    // Garis sumbu kategori (di nilai 0)
    final axis = Paint()
      ..color = const Color(0xFFBFBFBF)
      ..strokeWidth = math.max(0.6, _fs * 0.08);
    if (horizontal) {
      final x0 = plot.left + (0 - min) / (max - min) * plot.width;
      canvas.drawLine(Offset(x0, plot.top), Offset(x0, plot.bottom), axis);
    } else {
      final y0 = plot.bottom - (0 - min) / (max - min) * plot.height;
      canvas.drawLine(Offset(plot.left, y0), Offset(plot.right, y0), axis);
    }

    // Seri: batang dulu, lalu area, lalu garis (garis selalu di atas)
    final barGroups = data.groups.where((g) => g.kind == ChartKind.column || g.kind == ChartKind.bar).toList();
    final barSlots = barGroups.fold<int>(0, (a, g) => a + (g.stacked ? 1 : g.series.length));
    var slot = 0;
    for (final g in barGroups) {
      final (gMin, gMax) = g.secondaryAxis && sec != null ? (sec.$1, sec.$2) : (min, max);
      _bars(canvas, plot, g, n, gMin, gMax, horizontal, slot, barSlots);
      slot += g.stacked ? 1 : g.series.length;
    }
    for (final kind in [ChartKind.area, ChartKind.line]) {
      for (final g in data.groups.where((g) => g.kind == kind)) {
        final (gMin, gMax) = g.secondaryAxis && sec != null ? (sec.$1, sec.$2) : (min, max);
        _lines(canvas, plot, g, n, gMin, gMax, horizontal);
      }
    }
  }

  void _bars(Canvas canvas, Rect plot, ChartGroup g, int n, double min, double max,
      bool horizontal, int slot0, int slots) {
    final len = horizontal ? plot.height : plot.width;
    final band = len / n;
    final groupW = band * 0.68;
    final barW = groupW / math.max(1, slots);
    double pos(double v) => horizontal
        ? plot.left + (v - min) / (max - min) * plot.width
        : plot.bottom - (v - min) / (max - min) * plot.height;
    final zero = pos(0.0.clamp(min, max));

    for (var i = 0; i < n; i++) {
      final start = horizontal
          ? plot.bottom - band * (i + 1) + (band - groupW) / 2
          : plot.left + band * i + (band - groupW) / 2;
      var total = 0.0;
      if (g.percent) {
        for (final s in g.series) {
          total += (i < s.values.length ? s.values[i] ?? 0 : 0).abs();
        }
      }
      var accPos = 0.0, accNeg = 0.0;
      for (var si = 0; si < g.series.length; si++) {
        final s = g.series[si];
        var v = i < s.values.length ? s.values[i] : null;
        if (v == null) continue;
        if (g.percent) v = total == 0 ? 0 : v / total * 100;
        final double from, to;
        if (g.stacked) {
          if (v >= 0) {
            from = accPos;
            accPos += v;
            to = accPos;
          } else {
            from = accNeg;
            accNeg += v;
            to = accNeg;
          }
        } else {
          from = 0;
          to = v;
        }
        final a = g.stacked ? pos(from) : zero;
        final b = pos(to);
        final s0 = start + barW * (slot0 + (g.stacked ? 0 : si));
        final rect = horizontal
            ? Rect.fromLTRB(math.min(a, b), s0 + barW * 0.04, math.max(a, b), s0 + barW * 0.96)
            : Rect.fromLTRB(s0 + barW * 0.04, math.min(a, b), s0 + barW * 0.96, math.max(a, b));
        canvas.drawRect(rect, Paint()..color = s.pointColors[i] ?? s.color);
        if (g.showValues) {
          final t = _tp(_fmt(s.values[i]!, _labelStep(s.values[i]!)), size: _fs * 0.85);
          final o = horizontal
              ? Offset(rect.right + _fs * 0.2, rect.center.dy - t.height / 2)
              : Offset(rect.center.dx - t.width / 2, rect.top - t.height);
          t.paint(canvas, o);
        }
      }
    }
  }

  static double _labelStep(double v) => v == v.roundToDouble() ? 1 : 0.01;

  void _lines(Canvas canvas, Rect plot, ChartGroup g, int n, double min, double max, bool horizontal) {
    final band = (horizontal ? plot.height : plot.width) / n;
    Offset pt(int i, double v) {
      final c = horizontal ? plot.bottom - band * (i + 0.5) : plot.left + band * (i + 0.5);
      final p = horizontal
          ? plot.left + (v - min) / (max - min) * plot.width
          : plot.bottom - (v - min) / (max - min) * plot.height;
      return horizontal ? Offset(p, c) : Offset(c, p);
    }

    final acc = List<double>.filled(n, 0);
    final totals = List<double>.filled(n, 0);
    if (g.percent) {
      for (final s in g.series) {
        for (var i = 0; i < n && i < s.values.length; i++) {
          totals[i] += (s.values[i] ?? 0).abs();
        }
      }
    }
    final width = math.max(1.0, _fs * 0.22);
    for (final s in g.series) {
      final pts = <Offset?>[];
      final base = <Offset>[];
      for (var i = 0; i < n; i++) {
        var v = i < s.values.length ? s.values[i] : null;
        if (v == null) {
          pts.add(null);
          base.add(pt(i, acc[i]));
          continue;
        }
        if (g.percent) v = totals[i] == 0 ? 0 : v / totals[i] * 100;
        base.add(pt(i, g.stacked ? acc[i] : 0.0.clamp(min, max)));
        if (g.stacked) acc[i] += v;
        pts.add(pt(i, g.stacked ? acc[i] : v));
      }
      final valid = [for (final p in pts) if (p != null) p];
      if (valid.isEmpty) continue;

      if (g.kind == ChartKind.area) {
        final path = Path()..moveTo(valid.first.dx, valid.first.dy);
        for (final p in valid.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        for (final p in base.reversed) {
          path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = s.color.withOpacity(g.stacked ? 1 : 0.75));
        continue;
      }
      final path = Path();
      var started = false;
      for (final p in pts) {
        if (p == null) {
          started = false;
          continue;
        }
        if (started) {
          path.lineTo(p.dx, p.dy);
        } else {
          path.moveTo(p.dx, p.dy);
          started = true;
        }
      }
      canvas.drawPath(path, Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round);
      if (g.markers && valid.length <= 60) {
        for (final p in valid) {
          canvas.drawCircle(p, width * 1.6, Paint()..color = s.color);
        }
      }
      if (g.showValues) {
        for (var i = 0; i < pts.length; i++) {
          final p = pts[i];
          final v = i < s.values.length ? s.values[i] : null;
          if (p == null || v == null) continue;
          final t = _tp(_fmt(v, _labelStep(v)), size: _fs * 0.85);
          t.paint(canvas, Offset(p.dx - t.width / 2, p.dy - t.height - width * 2));
        }
      }
    }
  }

  // ── Pie / donat ───────────────────────────────────────────────────────────

  void _pie(Canvas canvas, Rect area) {
    final g = data.groups.first;
    final s = g.series.first;
    final vals = s.values.map((v) => math.max(0.0, v ?? 0)).toList();
    final total = vals.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final r = math.min(area.width, area.height) / 2 * 0.95;
    final c = area.center;
    final rect = Rect.fromCircle(center: c, radius: r);
    var a0 = -math.pi / 2;
    final sep = Paint()
      ..color = kWhiteColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.012);
    final hole = g.kind == ChartKind.doughnut ? r * 0.5 : 0.0;
    for (var i = 0; i < vals.length; i++) {
      final sweep = vals[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      final paint = Paint()..color = s.pointColors[i] ?? kDefaultChartPalette[i % 6];
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, a0, sweep, false)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, sep);
      // Label persentase di tengah irisan
      final pct = vals[i] / total;
      if (pct >= 0.04) {
        final mid = a0 + sweep / 2;
        final lr = hole > 0 ? (r + hole) / 2 : r * 0.64;
        final label = g.showValues ? _fmt(s.values[i]!, _labelStep(s.values[i]!)) : '${(pct * 100).round()}%';
        final t = _tp(label, size: _fs * 0.95, color: kWhiteColor, bold: true);
        t.paint(canvas, Offset(c.dx + math.cos(mid) * lr - t.width / 2, c.dy + math.sin(mid) * lr - t.height / 2));
      }
      a0 += sweep;
    }
    if (hole > 0) {
      canvas.drawCircle(c, hole, Paint()..color = data.background ?? kWhiteColor);
    }
  }

  // ── Scatter ───────────────────────────────────────────────────────────────

  void _scatter(Canvas canvas, Rect area) {
    final pts = <(Offset, Color)>[];
    var xmin = double.infinity, xmax = -double.infinity, ymin = 0.0, ymax = 0.0;
    for (final s in data.allSeries) {
      for (var i = 0; i < s.values.length; i++) {
        final y = s.values[i];
        final x = s.xValues != null && i < s.xValues!.length ? s.xValues![i] : (i + 1).toDouble();
        if (x == null || y == null) continue;
        xmin = math.min(xmin, x);
        xmax = math.max(xmax, x);
        ymin = math.min(ymin, y);
        ymax = math.max(ymax, y);
        pts.add((Offset(x, y), s.color));
      }
    }
    if (pts.isEmpty) return;
    final (x0, x1, xs) = _scale(math.min(0, xmin), xmax);
    final (y0, y1, ys) = _scale(ymin, ymax);
    final yt = [for (var v = y0; v <= y1 + ys / 2; v += ys) _tp(_fmt(v, ys))];
    final xt = [for (var v = x0; v <= x1 + xs / 2; v += xs) _tp(_fmt(v, xs))];
    final leftW = yt.fold<double>(0, (m, t) => math.max(m, t.width)) + _fs * 0.5;
    final botH = xt.first.height + _fs * 0.5;
    final plot = Rect.fromLTRB(area.left + leftW, area.top, area.right - xt.last.width / 2, area.bottom - botH);
    final grid = Paint()
      ..color = _grid
      ..strokeWidth = math.max(0.5, _fs * 0.06);
    for (var k = 0; k < yt.length; k++) {
      final y = plot.bottom - (k * ys) / (y1 - y0) * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      yt[k].paint(canvas, Offset(plot.left - _fs * 0.5 - yt[k].width, y - yt[k].height / 2));
    }
    for (var k = 0; k < xt.length; k++) {
      final x = plot.left + (k * xs) / (x1 - x0) * plot.width;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      xt[k].paint(canvas, Offset(x - xt[k].width / 2, plot.bottom + _fs * 0.3));
    }
    for (final (p, color) in pts) {
      final o = Offset(plot.left + (p.dx - x0) / (x1 - x0) * plot.width,
          plot.bottom - (p.dy - y0) / (y1 - y0) * plot.height);
      canvas.drawCircle(o, math.max(1.5, _fs * 0.35), Paint()..color = color);
    }
  }

  // ── Radar ─────────────────────────────────────────────────────────────────

  void _radar(Canvas canvas, Rect area) {
    final n = data.categories.length;
    if (n < 3) return _cartesian(canvas, area);
    final labels = data.categories.map((c) => _tp(c)).toList();
    final lw = labels.fold<double>(0, (m, t) => math.max(m, t.width));
    final r = math.max(10.0, math.min(area.width / 2 - lw, area.height / 2 - _fs * 1.5));
    final c = area.center;
    final (lo, hi) = _range(data.groups, n);
    final (_, max, step) = _scale(math.min(0, lo), hi);
    Offset at(int i, double frac) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * frac;
    }

    final grid = Paint()
      ..color = _grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, _fs * 0.06);
    for (var v = step; v <= max + step / 2; v += step) {
      final path = Path()..addPolygon([for (var i = 0; i < n; i++) at(i, v / max)], true);
      canvas.drawPath(path, grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, at(i, 1), grid);
      final p = at(i, 1.08);
      labels[i].paint(canvas, Offset(p.dx - labels[i].width / 2, p.dy - labels[i].height / 2));
    }
    for (final s in data.allSeries) {
      final pts = [for (var i = 0; i < n; i++) at(i, ((i < s.values.length ? s.values[i] : 0) ?? 0) / max)];
      canvas.drawPath(Path()..addPolygon(pts, true), Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, _fs * 0.2));
    }
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.ptScale != ptScale;
}

const kWhiteColor = Color(0xFFFFFFFF);
