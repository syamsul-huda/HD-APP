import 'dart:io';
import 'package:excel/excel.dart';
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
    if (v is TextCellValue) return v.value;
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    if (v is BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
    if (v is DateCellValue) return '${v.year}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B8BFF)))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Gagal membaca: $_error',
                      style: const TextStyle(color: Colors.redAccent)),
                ))
              : Column(
                  children: [
                    if ((_excel?.tables.keys.length ?? 0) > 1) _buildSheetTabs(),
                    Expanded(child: _buildTable()),
                  ],
                ),
    );
  }

  Widget _buildSheetTabs() {
    final sheets = _excel!.tables.keys.toList();
    return Container(
      height: 42,
      color: const Color(0xFF1E2640),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: sheets.length,
        itemBuilder: (_, i) {
          final name = sheets[i];
          final active = name == _activeSheet;
          return GestureDetector(
            onTap: () => setState(() => _activeSheet = name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF7B8BFF).withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: active ? const Color(0xFF7B8BFF) : Colors.white24,
                ),
              ),
              child: Center(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 12,
                        color: active ? const Color(0xFF7B8BFF) : Colors.white54,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTable() {
    if (_activeSheet == null || _excel == null) {
      return const Center(child: Text('Tidak ada data', style: TextStyle(color: Colors.white38)));
    }

    final sheet = _excel!.tables[_activeSheet!]!;
    final rows = sheet.rows;

    if (rows.isEmpty) {
      return const Center(child: Text('Sheet kosong', style: TextStyle(color: Colors.white38)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: Colors.white12, width: 0.5),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: rows.asMap().entries.map((entry) {
            final isHeader = entry.key == 0;
            return TableRow(
              decoration: BoxDecoration(
                color: isHeader
                    ? const Color(0xFF7B8BFF).withOpacity(0.15)
                    : entry.key.isEven
                        ? const Color(0xFF1E2640)
                        : const Color(0xFF181E36),
              ),
              children: entry.value.map((cell) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                    _cellText(cell),
                    style: TextStyle(
                      fontSize: 12,
                      color: isHeader ? const Color(0xFF7B8BFF) : Colors.white70,
                      fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}
