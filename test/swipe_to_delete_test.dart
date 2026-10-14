import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_app_hd/utils/swipe_to_delete.dart';

void main() {
  Future<List<String>> pumpList(WidgetTester tester) async {
    final items = ['a.pdf', 'b.pdf'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ListView(
            children: [
              for (final name in items)
                SwipeToDelete(
                  key: ValueKey(name),
                  confirmTitle: 'Delete document?',
                  confirmMessage: 'Remove $name?',
                  onDelete: () async => setState(() => items.remove(name)),
                  child: SizedBox(height: 72, child: Text(name)),
                ),
            ],
          ),
        ),
      ),
    ));
    return items;
  }

  testWidgets('swipe left reveals Delete, confirm removes item',
      (tester) async {
    final items = await pumpList(tester);

    await tester.drag(find.text('a.pdf'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsWidgets);

    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete document?'), findsOneWidget);

    // Tombol Delete di dialog
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(items, ['b.pdf']);
    expect(find.text('a.pdf'), findsNothing);
  });

  testWidgets('cancel keeps item and closes the swipe', (tester) async {
    final items = await pumpList(tester);

    await tester.drag(find.text('a.pdf'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(items, ['a.pdf', 'b.pdf']);
    expect(find.text('a.pdf'), findsOneWidget);
  });
}
