import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/models/flat_models.dart';

void main() {
  test('expense status updates preserve request details and votes', () {
    final createdAt = DateTime(2026, 10, 11);
    final request = ExpenseRequest(
      id: 'expense-1',
      title: 'Cleaning supplies',
      description: 'Soap and sponges',
      category: 'Household',
      amount: 1250,
      requesterId: 'member-1',
      createdAt: createdAt,
      votes: [ExpenseVote(memberId: 'member-2', approved: true, at: createdAt)],
    );

    final approved = request.copyWith(status: ExpenseStatus.approved);
    expect(approved.id, 'expense-1');
    expect(approved.title, 'Cleaning supplies');
    expect(approved.amount, 1250);
    expect(approved.createdAt, createdAt);
    expect(approved.votes, hasLength(1));
    expect(approved.status, ExpenseStatus.approved);
  });

  test('ledger entry sign is derived from entry type', () {
    final contribution = LedgerEntry(
      id: 'entry-1', type: LedgerType.contribution, amount: 3000,
      actorId: 'member-1', description: 'Pool funds', createdAt: DateTime(2026, 10, 11),
    );
    final payment = LedgerEntry(
      id: 'entry-2', type: LedgerType.expensePayment, amount: 900,
      actorId: 'member-1', description: 'Paid claim', createdAt: DateTime(2026, 10, 11),
    );
    expect(contribution.poolDelta, 3000);
    expect(payment.poolDelta, -900);
  });
}
