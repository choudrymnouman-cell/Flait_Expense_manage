import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/models/flat_models.dart';
import 'package:flait_expense_manage/services/accounting_service.dart';
import 'package:flait_expense_manage/widgets/flait_widgets.dart';

void main() {
  const accounting = AccountingService();
  const members = [
    FlatMember(id: 'manager', name: 'Manager', role: MemberRole.treasurer),
    FlatMember(id: 'member', name: 'Member', role: MemberRole.member),
  ];
  LedgerEntry entry(LedgerType type, double amount, {String? memberId}) =>
      LedgerEntry(
        id: '$type',
        type: type,
        amount: amount,
        actorId: 'manager',
        memberId: memberId,
        description: 'Test',
        createdAt: DateTime(2026),
      );

  test('contribution and reimbursement belong to the member, not recorder', () {
    final balances = accounting.memberNetBalances(
      members: members,
      entries: [
        entry(LedgerType.contribution, 1000, memberId: 'member'),
        entry(LedgerType.expensePayment, 250, memberId: 'member'),
      ],
    );
    expect(balances['manager'], 0);
    expect(balances['member'], 750);
  });

  test(
    'unknown legacy contributors remain in pool but not member activity',
    () {
      final entries = [entry(LedgerType.contribution, 1000)];
      expect(accounting.poolBalance(entries), 1000);
      expect(accounting.memberNetBalances(members: members, entries: entries), {
        'manager': 0.0,
        'member': 0.0,
      });
    },
  );

  test('money preserves decimals and selected currency', () {
    expect(money(123.45), 'PKR 123.45');
    expect(money(10, currency: 'USD'), 'USD 10.00');
  });
  test('pool arithmetic uses integer cents', () {
    expect(
        accounting.poolBalance([
          entry(LedgerType.contribution, 0.1),
          entry(LedgerType.contribution, 0.2),
        ]),
        0.3);
  });

  test('money inputs reject fractional cents and nonfinite values', () {
    expect(validMoneyAmount(12.34), isTrue);
    expect(validMoneyAmount(0.001), isFalse);
    expect(validMoneyAmount(double.nan), isFalse);
    expect(validMoneyAmount(double.infinity), isFalse);
    expect(validMoneyAmount(-1), isFalse);
  });
}
