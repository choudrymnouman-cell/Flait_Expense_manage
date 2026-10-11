import 'package:flutter/foundation.dart';
import '../models/flat_models.dart';
import '../services/accounting_service.dart';

class FlaitState extends ChangeNotifier {
  FlaitState() {
    members = const [
      FlatMember(id: 'm1', name: 'Alex Morgan', role: MemberRole.treasurer),
      FlatMember(id: 'm2', name: 'Sam Khan', role: MemberRole.member),
      FlatMember(id: 'm3', name: 'Jamie Lee', role: MemberRole.member),
      FlatMember(id: 'm4', name: 'Taylor Ali', role: MemberRole.member),
    ];
    ledger = [
      LedgerEntry(id: 'l1', type: LedgerType.contribution, amount: 12000, actorId: 'm1', description: 'Opening pool contribution', createdAt: DateTime.now().subtract(const Duration(days: 5))),
      LedgerEntry(id: 'l2', type: LedgerType.contribution, amount: 9000, actorId: 'm2', description: 'Monthly pool contribution', createdAt: DateTime.now().subtract(const Duration(days: 4))),
      LedgerEntry(id: 'l3', type: LedgerType.contribution, amount: 9000, actorId: 'm3', description: 'Monthly pool contribution', createdAt: DateTime.now().subtract(const Duration(days: 4))),
      LedgerEntry(id: 'l4', type: LedgerType.contribution, amount: 9000, actorId: 'm4', description: 'Monthly pool contribution', createdAt: DateTime.now().subtract(const Duration(days: 4))),
    ];
    expenses = [
      ExpenseRequest(id: 'e1', title: 'Kitchen cleaning supplies', description: 'Detergent, sponges and bin liners', category: 'Household', amount: 1450, requesterId: 'm2', createdAt: DateTime.now().subtract(const Duration(hours: 3))),
      ExpenseRequest(id: 'e2', title: 'Water can delivery', description: 'Two large water cans', category: 'Utilities', amount: 600, requesterId: 'm3', createdAt: DateTime.now().subtract(const Duration(days: 1))),
    ];
  }

  late List<FlatMember> members;
  late List<LedgerEntry> ledger;
  late List<ExpenseRequest> expenses;
  final accounting = const AccountingService();
  String currentMemberId = 'm1';

  FlatMember get currentMember => members.firstWhere((m) => m.id == currentMemberId);
  double get poolBalance => accounting.poolBalance(ledger);
  int get pendingCount => expenses.where((e) => e.status == ExpenseStatus.pending).length;
  String memberName(String id) => members.where((m) => m.id == id).firstOrNull?.name ?? 'Former member';

  void submitExpense({
    required String title,
    required String description,
    required String category,
    required double amount,
  }) {
    if (title.trim().isEmpty || amount <= 0 || !amount.isFinite) {
      throw ArgumentError('Enter a title and a valid amount greater than zero.');
    }
    final duplicate = expenses.any((e) =>
      e.requesterId == currentMemberId &&
      e.title.trim().toLowerCase() == title.trim().toLowerCase() &&
      e.amount == amount &&
      DateTime.now().difference(e.createdAt).inSeconds < 30);
    if (duplicate) throw StateError('A similar request was just submitted.');
    expenses = [
      ExpenseRequest(
        id: 'e${DateTime.now().microsecondsSinceEpoch}',
        title: title.trim(),
        description: description.trim(),
        category: category,
        amount: amount,
        requesterId: currentMemberId,
        createdAt: DateTime.now(),
      ),
      ...expenses,
    ];
    notifyListeners();
  }

  void vote(String expenseId, bool approve, {String comment = ''}) {
    final index = expenses.indexWhere((e) => e.id == expenseId);
    if (index < 0) throw StateError('Expense request not found.');
    final expense = expenses[index];
    if (expense.status != ExpenseStatus.pending) throw StateError('This request is no longer pending.');
    if (expense.requesterId == currentMemberId) throw StateError('You cannot vote on your own request.');
    if (expense.votes.any((v) => v.memberId == currentMemberId)) throw StateError('You have already voted.');
    final updated = expense.copyWith(votes: [
      ...expense.votes,
      ExpenseVote(memberId: currentMemberId, approved: approve, at: DateTime.now(), comment: comment.trim()),
    ]);
    expenses[index] = updated.copyWith(status: accounting.evaluate(expense: updated, members: members));
    notifyListeners();
  }

  void recordContribution(double amount, String description) {
    if (currentMember.role != MemberRole.treasurer && currentMember.role != MemberRole.admin) {
      throw StateError('Only the treasurer or flat admin can record pool contributions.');
    }
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Amount must be greater than zero.');
    ledger = [
      LedgerEntry(id: 'l${DateTime.now().microsecondsSinceEpoch}', type: LedgerType.contribution, amount: amount, actorId: currentMemberId, description: description.trim().isEmpty ? 'Pool contribution' : description.trim(), createdAt: DateTime.now()),
      ...ledger,
    ];
    notifyListeners();
  }

  void markPaid(String expenseId) {
    if (currentMember.role != MemberRole.treasurer && currentMember.role != MemberRole.admin) {
      throw StateError('Only the treasurer or flat admin can record payments.');
    }
    final index = expenses.indexWhere((e) => e.id == expenseId);
    if (index < 0) throw StateError('Expense request not found.');
    final expense = expenses[index];
    if (expense.status != ExpenseStatus.approved) throw StateError('Only approved requests can be paid.');
    if (ledger.any((entry) => entry.relatedExpenseId == expenseId && entry.type == LedgerType.expensePayment)) {
      throw StateError('Payment has already been recorded.');
    }
    if (poolBalance < expense.amount) throw StateError('Pool balance is too low to pay this request.');
    ledger = [
      LedgerEntry(id: 'l${DateTime.now().microsecondsSinceEpoch}', type: LedgerType.expensePayment, amount: expense.amount, actorId: expense.requesterId, description: 'Reimbursement: ${expense.title}', relatedExpenseId: expenseId, createdAt: DateTime.now()),
      ...ledger,
    ];
    expenses[index] = expense.copyWith(status: ExpenseStatus.paid, paidAt: DateTime.now());
    notifyListeners();
  }

  void switchMember(String memberId) {
    if (members.any((m) => m.id == memberId && m.active)) {
      currentMemberId = memberId;
      notifyListeners();
    }
  }
}
