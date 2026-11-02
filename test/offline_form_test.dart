import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:flait_expense_manage/offline/local_database.dart';
import 'package:flait_expense_manage/offline/secure_book.dart';
import 'package:flait_expense_manage/screens/expense_entry_screen.dart';
import 'package:flait_expense_manage/state/app_state.dart';

void main() {
  testWidgets('expense fields retain their values when moving focus',
      (tester) async {
    final db = await databaseFactoryMemory.openDatabase(randomCode());
    final state = FlaitState(LocalDatabase(db));
    await tester.runAsync(() async {
      await state.load();
      await state.prepareIdentity('Test owner');
      await state.createFlat('Test flat');
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExpenseEntryScreen(state: state, onSubmitted: () {}))));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Groceries');
    await tester.tap(fields.at(1));
    await tester.enterText(fields.at(1), '123.45');
    await tester.tap(fields.at(2));
    await tester.enterText(fields.at(2), 'Milk and bread');
    expect(tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'Groceries');
    expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text, '123.45');
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text,
        'Milk and bread');
    expect(tester.takeException(), isNull);
  });
}
