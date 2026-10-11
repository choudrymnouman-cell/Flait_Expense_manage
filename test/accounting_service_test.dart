import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/models/flat_models.dart';
import 'package:flait_expense_manage/services/accounting_service.dart';

void main() {
  const accounting = AccountingService();
  final members = const [
    FlatMember(id: 'a', name: 'A', role: MemberRole.treasurer),
    FlatMember(id: 'b', name: 'B', role: MemberRole.member),
    FlatMember(id: 'c', name: 'C', role: MemberRole.member),
    FlatMember(id: 'd', name: 'D', role: MemberRole.member),
  ];

  test('pool balance changes only by ledger entries', () {
    final entries = [
      LedgerEntry(id: '1', type: LedgerType.contribution, amount: 10000, actorId: 'a', description: 'Contribution', createdAt: DateTime(2025)),
      LedgerEntry(id: '2', type: LedgerType.expensePayment, amount: 1200, actorId: 'b', description: 'Paid expense', createdAt: DateTime(2025)),
      LedgerEntry(id: '3', type: LedgerType.withdrawal, amount: 300, actorId: 'a', description: 'Withdrawal', createdAt: DateTime(2025)),
    ];
    expect(accounting.poolBalance(entries), 8500);
  });

  test('requester is excluded from approval votes', () {
    final expense = ExpenseRequest(
      id: 'e1', title: 'Soap', description: '', category: 'Household',
      amount: 500, requesterId: 'a', createdAt: DateTime(2025),
      votes: [
        ExpenseVote(memberId: 'b', approved: true, at: DateTime(2025)),
        ExpenseVote(memberId: 'c', approved: true, at: DateTime(2025)),
      ],
    );
    expect(accounting.evaluate(expense: expense, members: members), ExpenseStatus.approved);
  });

  test('a single approval is not enough for three eligible voters', () {
    final expense = ExpenseRequest(
      id: 'e1', title: 'Soap', description: '', category: 'Household',
      amount: 500, requesterId: 'a', createdAt: DateTime(2025),
      votes: [ExpenseVote(memberId: 'b', approved: true, at: DateTime(2025))],
    );
    expect(accounting.evaluate(expense: expense, members: members), ExpenseStatus.pending);
  });
}
