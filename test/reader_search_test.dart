import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_app_hd/models/recent_file.dart';
import 'package:super_app_hd/screens/reader_screen.dart';
import 'package:super_app_hd/services/history_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reader_search');
    final names = [
      'Laporan Keuangan 2025.pdf',
      'laporan_rapat.docx',
      'Invoice March.pdf',
      'budget.xlsx',
    ];
    final files = <RecentFile>[];
    for (final n in names) {
      final f = File('${dir.path}/$n')..writeAsStringSync('x');
      files.add(RecentFile(
          path: f.path, name: n, extension: n.split('.').last, lastOpened: 0));
    }
    SharedPreferences.setMockInitialValues(
        {RecentFile.prefKey: RecentFile.encodeList(files)});
    await HistoryService.load();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pumpReader(WidgetTester tester) async {
    // Lebar layar HP biasa (logical 420 px)
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
    // _loadRecent memakai File I/O nyata: tunggu sampai daftar muncul
    for (var i = 0; i < 50 && find.byType(TextField).evaluate().isEmpty; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  bool shown(String name) =>
      find.textContaining(name, findRichText: true).evaluate().isNotEmpty;

  testWidgets('search filters recent documents by name, case-insensitive',
      (tester) async {
    await pumpReader(tester);
    expect(shown('budget.xlsx'), isTrue);

    await tester.enterText(find.byType(TextField), 'LAPORAN');
    await tester.pumpAndSettle();
    expect(find.text('2 of 4 documents'), findsOneWidget);
    expect(shown('budget.xlsx'), isFalse);
    expect(shown('Invoice March.pdf'), isFalse);
  });

  testWidgets('multiple terms must all match (name + type)', (tester) async {
    await pumpReader(tester);
    await tester.enterText(find.byType(TextField), 'laporan pdf');
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 documents'), findsOneWidget);
    expect(shown('laporan_rapat.docx'), isFalse);
  });

  testWidgets('no match shows empty state; clear restores list',
      (tester) async {
    await pumpReader(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No documents match "zzz"'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(shown('budget.xlsx'), isTrue);
    expect(find.text('Swipe left on a document to delete it'), findsOneWidget);
  });
}
