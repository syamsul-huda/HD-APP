import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_app_hd/models/history_records.dart';
import 'package:super_app_hd/services/history_service.dart';

ScanRecord _scan(int i) =>
    ScanRecord(type: 'pdf', paths: ['/scan_$i.pdf'], pageCount: 1, date: i);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HistoryService.load();
  });

  test('history keeps at most the configured limit, newest first', () async {
    await HistoryService.setLimit(HistoryService.scannerLimit, 3);
    for (var i = 1; i <= 5; i++) {
      await HistoryService.addScan(_scan(i));
    }
    final items = await HistoryService.loadScans();
    expect(items.map((e) => e.date), [5, 4, 3]);
  });

  test('lowering the limit trims existing history', () async {
    for (var i = 1; i <= 10; i++) {
      await HistoryService.addScan(_scan(i));
    }
    await HistoryService.setLimit(HistoryService.scannerLimit, 2);

    // Naikkan lagi: item yang sudah terpangkas tidak kembali
    await HistoryService.setLimit(HistoryService.scannerLimit, 100);
    final items = await HistoryService.loadScans();
    expect(items.map((e) => e.date), [10, 9]);
  });

  test('limit is clamped to 1..100 and persisted', () async {
    await HistoryService.setLimit(HistoryService.downloaderLimit, 500);
    expect(HistoryService.downloaderLimit.value, 100);
    await HistoryService.setLimit(HistoryService.downloaderLimit, 0);
    expect(HistoryService.downloaderLimit.value, 1);

    await HistoryService.setLimit(HistoryService.readerLimit, 42);
    HistoryService.readerLimit.value = 20;
    await HistoryService.load();
    expect(HistoryService.readerLimit.value, 42);
  });

  test('reader: reopening a file moves it to the top without duplicates',
      () async {
    await HistoryService.touchRecentFile('/a.pdf', 'a.pdf', 'pdf');
    await HistoryService.touchRecentFile('/b.pdf', 'b.pdf', 'pdf');
    final items = await HistoryService.touchRecentFile('/a.pdf', 'a.pdf', 'pdf');
    expect(items.map((e) => e.name), ['a.pdf', 'b.pdf']);
  });
}
