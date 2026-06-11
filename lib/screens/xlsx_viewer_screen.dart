import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';

class XlsxViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  const XlsxViewerScreen({super.key, required this.path, required this.title});

  @override
  State<XlsxViewerScreen> createState() => _XlsxViewerScreenState();
}

class _XlsxViewerScreenState extends State<XlsxViewerScreen> {
  Excel? _excel;
  String? _activeSheet;
  bool _loading = true;
  String? _error;

  // Pre-computed per-sheet column widths cache
  final Map<String, List<double>> _colWidthCache = {};

  static const _excelGreen = Color(0xFF217346);
  static const _excelBorder = Color(0xFFD0D0D0);
  static const double _rowNumWidth = 42.0;
  static const double _minColWidth = 64.0;
  static const double _maxColWidth = 280.0;
  static const double _charWidth = 7.6; // px per char at fontSize 12
  static const double _cellPadH = 16.0; // horizontal padding total
  static const double _dataRowHeight = 30.0;
  static const double _headerRowHeight = 34.0;
  static const double _colHeaderHeight = 22.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      setState(() {
        _excel = excel;
        _activeSheet = excel.tables.keys.isNotEmpty ? excel.tables.keys.first : null;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _cellText(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final v = cell.value!;
    if (v is TextCellValue) return v.value.text ?? '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      // Keep meaningful decimals, strip trailing zeros
      final s = v.value.toStringAsFixed(4);
      return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
    }
    if (v is BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
    if (v is DateCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is DateTimeCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')} '
          '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }
    return v.toString();
  }

  /// Pre-compute column widths based on actual cell content for a sheet.
  List<double> _getColWidths(String sheetName) {
    if (_colWidthCache.containsKey(sheetName)) return _colWidthCache[sheetName]!;
    final sheet = _excel!.tables[sheetName]!;
    final rows = sheet.rows;
    if (rows.isEmpty) return [];

    final colCount = rows.map((r) => r.length).fold(0, (a, b) => b > a ? b : a);
    final widths = List.filled(colCount, _minColWidth);

    // Row 0 (header) gets a bit of extra weight — headers tend to define column meaning
    for (int ri = 0; ri < rows.length; ri++) {
      final row = rows[ri];
      for (int ci = 0; ci < row.length && ci < colCount; ci++) {
        final text = _cellText(row[ci]);
        if (text.isEmpty) continue;
        // Header row: treat font as bold (slightly wider per char)
        final w = text.length * (ri == 0 ? _charWidth * 1.15 : _charWidth) + _cellPadH;
        if (w > widths[ci]) widths[ci] = w.clamp(_minColWidth, _maxColWidth);
      }
    }

    _colWidthCache[sheetName] = widths;
    return widths;
  }

  String _colLetter(int index) {
    String result = '';
    int n = index;
    do {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    } while (n >= 0);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: AppBar(
        backgroundColor: _excelGreen,
        title: Text(widget.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.table_chart_outlined, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text('XLSX',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _excelGreen))
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildSheetTabs(),
                    Expanded(child: _buildTable()),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text('Gagal membaca file:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF555770))),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetTabs() {
    final sheets = _excel?.tables.keys.toList() ?? [];
    if (sheets.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 40,
      color: const Color(0xFF1A5C38),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: sheets.length,
        itemBuilder: (_, i) {
          final name = sheets[i];
          final active = name == _activeSheet;
          return GestureDetector(
            onTap: () => setState(() => _activeSheet = name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Center(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? _excelGreen : Colors.white70,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTable() {
    if (_activeSheet == null || _excel == null) {
      return const Center(
          child: Text('Tidak ada data',
              style: TextStyle(color: Color(0xFF9B9FAD))));
    }

    final sheet = _excel!.tables[_activeSheet!]!;
    final rows = sheet.rows;

    if (rows.isEmpty) {
      return const Center(
          child: Text('Sheet kosong',
              style: TextStyle(color: Color(0xFF9B9FAD))));
    }

    final colWidths = _getColWidths(_activeSheet!);
    final colCount = colWidths.length;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Sticky-style column letter header ──────────────────────────
              _buildColLetterHeader(colWidths, colCount),
              // ── Data rows ──────────────────────────────────────────────────
              ...rows.asMap().entries.map((entry) {
                return _buildDataRow(
                  rowIndex: entry.key,
                  cells: entry.value,
                  colWidths: colWidths,
                  colCount: colCount,
                  isFirstRow: entry.key == 0,
                  isAltRow: entry.key.isOdd,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColLetterHeader(List<double> colWidths, int colCount) {
    return Row(
      children: [
        // Corner cell
        Container(
          width: _rowNumWidth,
          height: _colHeaderHeight,
          decoration: const BoxDecoration(
            color: Color(0xFFDDDDDD),
            border: Border(
              right: BorderSide(color: _excelBorder),
              bottom: BorderSide(color: _excelBorder),
            ),
          ),
        ),
        ...List.generate(colCount, (ci) {
          return Container(
            width: colWidths[ci],
            height: _colHeaderHeight,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE8E8E8),
              border: Border(
                right: BorderSide(color: _excelBorder),
                bottom: BorderSide(color: _excelBorder),
              ),
            ),
            child: Text(
              _colLetter(ci),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555770),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDataRow({
    required int rowIndex,
    required List<Data?> cells,
    required List<double> colWidths,
    required int colCount,
    required bool isFirstRow,
    required bool isAltRow,
  }) {
    // Row 0 = first data row (styled as header)
    final isHeader = isFirstRow;
    final rowHeight = isHeader ? _headerRowHeight : _dataRowHeight;
    final rowBg = isHeader
        ? _excelGreen
        : isAltRow
            ? const Color(0xFFF3FBF4)
            : Colors.white;
    final textColor = isHeader ? Colors.white : const Color(0xFF1A1A2E);
    final fontWeight = isHeader ? FontWeight.w600 : FontWeight.normal;
    final fontSize = isHeader ? 12.0 : 12.0;

    return Row(
      children: [
        // Row number cell
        Container(
          width: _rowNumWidth,
          height: rowHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isHeader ? const Color(0xFF1A5C38) : const Color(0xFFE8E8E8),
            border: const Border(
              right: BorderSide(color: _excelBorder),
              bottom: BorderSide(color: _excelBorder),
            ),
          ),
          child: Text(
            isHeader ? '' : '${rowIndex}',
            style: TextStyle(
              fontSize: 10,
              color: isHeader ? Colors.white70 : const Color(0xFF888888),
            ),
          ),
        ),
        // Data cells — width is FIXED per column from pre-computed widths
        ...List.generate(colCount, (ci) {
          final cell = ci < cells.length ? cells[ci] : null;
          final text = _cellText(cell);

          // Detect number/date alignment
          final isNumeric = cell?.value is IntCellValue ||
              cell?.value is DoubleCellValue ||
              cell?.value is DateCellValue ||
              cell?.value is DateTimeCellValue;

          return Container(
            width: colWidths[ci],
            height: rowHeight,
            alignment: isNumeric && !isHeader
                ? Alignment.centerRight
                : Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: rowBg,
              border: const Border(
                right: BorderSide(color: _excelBorder),
                bottom: BorderSide(color: _excelBorder),
              ),
            ),
            child: text.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    text,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: textColor,
                      fontWeight: fontWeight,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                  ),
          );
        }),
      ],
    );
  }
}
