import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/models/flat_models.dart';
import 'package:flait_expense_manage/state/app_state.dart';

void main() {
  test('approval does not change pool until treasurer records payment', () {
    final state = FlaitState();
    addTearDown(state.dispose);
    final initialBalance = state.poolBalance;

    state.switchMember('m2');
    state.submitExpense(title: 'Test light bulbs', description: 'Two LED bulbs', category: 'Household', amount: 100);

    final requestId = state.expenses.first.id;
    expect(state.poolBalance, initialBalance);
    expect(state.expenses.first.status, ExpenseStatus.pending);

    state.switchMember('m1');
    state.vote(requestId, true);
    state.switchMember('m3');
    state.vote(requestId, true);

    expect(state.expenses.first.status, ExpenseStatus.approved);
    expect(state.poolBalance, initialBalance);

    state.switchMember('m1');
    state.markPaid(requestId);

    expect(state.expenses.first.status, ExpenseStatus.paid);
    expect(state.poolBalance, initialBalance - 100);
    expect(state.ledger.where((e) => e.relatedExpenseId == requestId).length, 1);
  });

  test('member cannot vote on their own reimbursement', () {
    final state = FlaitState();
    addTearDown(state.dispose);
    state.switchMember('m2');
    state.submitExpense(title: 'Test dish soap', description: '', category: 'Household', amount: 50);
    final id = state.expenses.first.id;
    expect(() => state.vote(id, true), throwsStateError);
  });
}
