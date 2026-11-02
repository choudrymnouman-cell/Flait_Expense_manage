import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/main.dart';
import 'package:flait_expense_manage/services/app_preferences.dart';
import 'package:flait_expense_manage/screens/expense_entry_screen.dart';
import 'offline_book_test.dart' show device;

void main() {
  testWidgets('root setup preserves entered fields while identity is persisted',
      (tester) async {
    final s = (await tester.runAsync(() => device('Initial')))!;
    await tester.pumpWidget(OfflineFlaitApp(state: s));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Root owner');
    await tester.enterText(fields.at(1), 'Root flat');
    await tester.tap(find.text('Create flat on this device'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)));
    await tester.pumpAndSettle();
    expect(s.flatName, 'Root flat');
    expect(find.text('Reports & search'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('small-screen expense form renders in Urdu dark mode',
      (tester) async {
    final s = (await tester.runAsync(() async {
      final state = await device('Owner');
      await state.createFlat('Flat');
      await state.setPreference('language', 'ur');
      return state;
    }))!;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppPreferences(
        state: s,
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                    body: ExpenseEntryScreen(state: s, onSubmitted: () {}))))));
    await tester.pumpAndSettle();
    expect(find.text('نیا خرچہ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
