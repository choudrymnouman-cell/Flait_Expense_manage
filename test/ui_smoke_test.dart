import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/widgets/flait_widgets.dart';
import 'package:flait_expense_manage/models/flat_models.dart';

void main() {
  testWidgets('financial widgets display precise amounts and expense status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BalanceCard(
                label: 'Pool balance',
                value: money(100.25),
                icon: Icons.wallet,
              ),
              const ExpenseStatusChip(status: ExpenseStatus.approved),
            ],
          ),
        ),
      ),
    );
    expect(find.text('PKR 100.25'), findsOneWidget);
    expect(find.text('Approved · unpaid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
