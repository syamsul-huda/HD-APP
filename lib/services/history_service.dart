import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_records.dart';
import '../models/recent_file.dart';

/// Riwayat per fitur (Downloader, Reader, Scanner), disimpan di
/// SharedPreferences. Jumlah item maksimum bisa diatur 1–100 per fitur.
class HistoryService {
  HistoryService._();

  static const minLimit = 1;
  static const maxLimit = 100;
  static const defaultLimit = 20;

  static const _downloadKey = 'history_downloader';
  static const _scanKey = 'history_scanner';

  static final downloaderLimit = ValueNotifier<int>(defaultLimit);
  static final readerLimit = ValueNotifier<int>(defaultLimit);
  static final scannerLimit = ValueNotifier<int>(defaultLimit);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    downloaderLimit.value =
        prefs.getInt('history_limit_downloader') ?? defaultLimit;
    readerLimit.value = prefs.getInt('history_limit_reader') ?? defaultLimit;
    scannerLimit.value = prefs.getInt('history_limit_scanner') ?? defaultLimit;
  }

  /// Ubah batas riwayat dan langsung pangkas data lama yang melebihi batas.
  static Future<void> setLimit(ValueNotifier<int> which, int value) async {
    value = value.clamp(minLimit, maxLimit);
    which.value = value;
    final prefs = await SharedPreferences.getInstance();
    if (identical(which, downloaderLimit)) {
      await prefs.setInt('history_limit_downloader', value);
      await saveDownloads(await loadDownloads());
    } else if (identical(which, readerLimit)) {
      await prefs.setInt('history_limit_reader', value);
      await saveRecentFiles(await loadRecentFiles());
    } else {
      await prefs.setInt('history_limit_scanner', value);
      await saveScans(await loadScans());
    }
  }

  // ── Downloader ──────────────────────────────────────────────────────────────
  static Future<List<DownloadRecord>> loadDownloads() async {
    final list = await _loadJson(_downloadKey);
    return list
        .map(DownloadRecord.fromJson)
        .take(downloaderLimit.value)
        .toList();
  }

  static Future<void> saveDownloads(List<DownloadRecord> items) => _saveJson(
      _downloadKey,
      items.take(downloaderLimit.value).map((e) => e.toJson()).toList());

  static Future<List<DownloadRecord>> addDownload(DownloadRecord r) async {
    final items = await loadDownloads()
      ..removeWhere((e) => e.filePath == r.filePath)
      ..insert(0, r);
    await saveDownloads(items);
    return items.take(downloaderLimit.value).toList();
  }

  // ── Reader ──────────────────────────────────────────────────────────────────
  static Future<List<RecentFile>> loadRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(RecentFile.prefKey);
    if (raw == null) return [];
    try {
      return RecentFile.decodeList(raw).take(readerLimit.value).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecentFiles(List<RecentFile> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(RecentFile.prefKey,
        RecentFile.encodeList(items.take(readerLimit.value).toList()));
  }

  /// Pindahkan/tambahkan file ke paling atas riwayat Reader.
  static Future<List<RecentFile>> touchRecentFile(
      String path, String name, String ext) async {
    final items = await loadRecentFiles()
      ..removeWhere((f) => f.path == path)
      ..insert(
          0,
          RecentFile(
            path: path,
            name: name,
            extension: ext.toLowerCase(),
            lastOpened: DateTime.now().millisecondsSinceEpoch,
          ));
    await saveRecentFiles(items);
    return items.take(readerLimit.value).toList();
  }

  // ── Scanner ─────────────────────────────────────────────────────────────────
  static Future<List<ScanRecord>> loadScans() async {
    final list = await _loadJson(_scanKey);
    return list.map(ScanRecord.fromJson).take(scannerLimit.value).toList();
  }

  static Future<void> saveScans(List<ScanRecord> items) => _saveJson(
      _scanKey, items.take(scannerLimit.value).map((e) => e.toJson()).toList());

  static Future<List<ScanRecord>> addScan(ScanRecord r) async {
    final items = await loadScans()
      ..insert(0, r);
    await saveScans(items);
    return items.take(scannerLimit.value).toList();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> _loadJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveJson(
      String key, List<Map<String, dynamic>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }
}

/// "5 minutes ago", "2 days ago", ...
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  return '${d.day}/${d.month}/${d.year}';
}
