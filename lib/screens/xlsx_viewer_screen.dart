import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';

// Excel-like spreadsheet viewer
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

  static const _excelGreen = Color(0xFF217346);
  static const _excelHeaderBg = Color(0xFF217346);
  static const _excelRowAlt = Color(0xFFEEF7EE);
  static const _excelBorder = Color(0xFFD0D0D0);
  static const _excelRowBg = Colors.white;

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
      final s = v.value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
      return s;
    }
    if (v is BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
    if (v is DateCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
    }
    return v.toString();
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
                Text('XLSX', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
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
          child: Text('Tidak ada data', style: TextStyle(color: Color(0xFF9B9FAD))));
    }

    final sheet = _excel!.tables[_activeSheet!]!;
    final rows = sheet.rows;

    if (rows.isEmpty) {
      return const Center(
          child: Text('Sheet kosong', style: TextStyle(color: Color(0xFF9B9FAD))));
    }

    // Calculate column widths based on content
    final colCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row number + column letters header
            _buildColumnHeader(colCount),
            // Data rows
            ...rows.asMap().entries.map((entry) {
              final rowIdx = entry.key;
              final isHeader = rowIdx == 0;
              final isAlt = !isHeader && rowIdx.isEven;
              return _buildDataRow(
                rowIndex: rowIdx,
                cells: entry.value,
                colCount: colCount,
                isHeader: isHeader,
                isAlt: isAlt,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnHeader(int colCount) {
    return Row(
      children: [
        // Row number column
        Container(
          width: 36,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFE0E0E0),
            border: Border(
              right: BorderSide(color: _excelBorder),
              bottom: BorderSide(color: _excelBorder),
            ),
          ),
        ),
        ...List.generate(colCount, (i) {
          final letter = _colLetter(i);
          return Container(
            constraints: const BoxConstraints(minWidth: 80),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFE0E0E0),
              border: Border(
                right: BorderSide(color: _excelBorder),
                bottom: BorderSide(color: _excelBorder),
              ),
            ),
            child: Center(
              child: Text(letter,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF555770),
                  )),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDataRow({
    required int rowIndex,
    required List<Data?> cells,
    required int colCount,
    required bool isHeader,
    required bool isAlt,
  }) {
    final bg = isHeader ? _excelHeaderBg : isAlt ? _excelRowAlt : _excelRowBg;
    final textColor = isHeader ? Colors.white : const Color(0xFF1A1A2E);
    final fontWeight = isHeader ? FontWeight.w600 : FontWeight.normal;

    return Row(
      children: [
        // Row number
        Container(
          width: 36,
          height: isHeader ? 32 : 28,
          decoration: BoxDecoration(
            color: isHeader ? const Color(0xFF1A5C38) : const Color(0xFFE0E0E0),
            border: Border(
              right: const BorderSide(color: _excelBorder),
              bottom: const BorderSide(color: _excelBorder),
            ),
          ),
          child: Center(
            child: Text(
              isHeader ? '' : '${rowIndex}',
              style: TextStyle(
                fontSize: 10,
                color: isHeader ? Colors.white : const Color(0xFF555770),
              ),
            ),
          ),
        ),
        ...List.generate(colCount, (colIdx) {
          final cell = colIdx < cells.length ? cells[colIdx] : null;
          final text = _cellText(cell);
          return Container(
            constraints: BoxConstraints(minWidth: 80, minHeight: isHeader ? 32 : 28),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                right: const BorderSide(color: _excelBorder),
                bottom: const BorderSide(color: _excelBorder),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: fontWeight,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }),
      ],
    );
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
}
