import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/flat_models.dart';
import '../services/accounting_service.dart';

class FlaitState extends ChangeNotifier {
  FlaitState({required this.flatId});
  final String flatId;
  final db = Supabase.instance.client;
  final accounting = const AccountingService();

  bool loading = true;
  String flatName = 'My flat';
  String currency = 'PKR';
  String? loadError;
  late List<FlatMember> members = [];
  late List<LedgerEntry> ledger = [];
  late List<ExpenseRequest> expenses = [];

  String get currentMemberId => db.auth.currentUser?.id ?? '';
  FlatMember get currentMember => members.firstWhere(
    (m) => m.id == currentMemberId,
    orElse: () => FlatMember(id: currentMemberId, name: db.auth.currentUser?.email ?? 'Member', role: MemberRole.member),
  );
  double get poolBalance => accounting.poolBalance(ledger);
  int get pendingCount => expenses.where((e) => e.status == ExpenseStatus.pending).length;

  String memberName(String id) {
    for (final member in members) {
      if (member.id == id) return member.name;
    }
    return 'Former member';
  }

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final flat = await db.from('flats').select('name,currency').eq('id', flatId).single();
      flatName = flat['name'] as String? ?? 'My flat';
      currency = flat['currency'] as String? ?? 'PKR';

      final memberRows = await db.from('flat_members').select().eq('flat_id', flatId).eq('active', true);
      members = memberRows.map<FlatMember>((row) => FlatMember(
        id: row['user_id'] as String,
        name: row['display_name'] as String? ?? 'Flatmate',
        role: _role(row['role'] as String?),
        active: row['active'] as bool? ?? true,
      )).toList();

      final expenseRows = await db.from('expenses').select().eq('flat_id', flatId).order('created_at', ascending: false);
      final voteRows = await db.from('expense_votes').select().eq('flat_id', flatId).order('created_at');
      final votesByExpense = <String, List<ExpenseVote>>{};
      for (final row in voteRows) {
        (votesByExpense[row['expense_id'] as String] ??= []).add(ExpenseVote(
          memberId: row['member_id'] as String,
          approved: row['approved'] as bool,
          at: DateTime.parse(row['created_at'] as String),
          comment: row['comment'] as String? ?? '',
        ));
      }
      expenses = expenseRows.map<ExpenseRequest>((row) => ExpenseRequest(
        id: row['id'] as String,
        title: row['title'] as String,
        description: row['description'] as String? ?? '',
        category: row['category'] as String? ?? 'Other',
        amount: (row['amount'] as num).toDouble(),
        requesterId: row['requester_id'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        status: _status(row['status'] as String?),
        votes: votesByExpense[row['id'] as String] ?? const [],
        receiptReference: row['receipt_path'] as String?,
        paidAt: row['paid_at'] == null ? null : DateTime.parse(row['paid_at'] as String),
      )).toList();

      final ledgerRows = await db.from('ledger_entries').select().eq('flat_id', flatId).order('created_at', ascending: false);
      ledger = ledgerRows.map<LedgerEntry>((row) => LedgerEntry(
        id: row['id'] as String,
        type: _ledgerType(row['entry_type'] as String),
        amount: (row['amount'] as num).toDouble(),
        actorId: row['actor_id'] as String,
        description: row['description'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        relatedExpenseId: row['related_expense_id'] as String?,
      )).toList();
    } catch (e) {
      loadError = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> submitExpense({
    required String title,
    required String description,
    required String category,
    required double amount,
  }) async {
    if (title.trim().isEmpty || amount <= 0 || !amount.isFinite) {
      throw ArgumentError('Enter a title and a valid amount greater than zero.');
    }
    await db.from('expenses').insert({
      'flat_id': flatId, 'requester_id': currentMemberId,
      'title': title.trim(), 'description': description.trim(),
      'category': category, 'amount': amount, 'status': 'pending',
    });
    await load();
  }

  Future<void> vote(String expenseId, bool approve, {String comment = ''}) async {
    ExpenseRequest? expense;\n    for (final item in expenses) { if (item.id == expenseId) { expense = item; break; } }
    if (expense == null) throw StateError('Expense request not found.');
    if (expense.status != ExpenseStatus.pending) throw StateError('This request is no longer pending.');
    if (expense.requesterId == currentMemberId) throw StateError('You cannot vote on your own request.');
    if (expense.votes.any((v) => v.memberId == currentMemberId)) throw StateError('You have already voted.');
    await db.from('expense_votes').insert({
      'flat_id': flatId, 'expense_id': expenseId, 'member_id': currentMemberId,
      'approved': approve, 'comment': comment.trim(),
    });
    await load();
  }

  Future<void> recordContribution(double amount, String description) async {
    if (currentMember.role != MemberRole.treasurer && currentMember.role != MemberRole.admin) {
      throw StateError('Only the treasurer or flat admin can record pool contributions.');
    }
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Amount must be greater than zero.');
    await db.from('ledger_entries').insert({
      'flat_id': flatId, 'actor_id': currentMemberId, 'entry_type': 'contribution',
      'amount': amount, 'description': description.trim().isEmpty ? 'Pool contribution' : description.trim(),
    });
    await load();
  }

  Future<void> markPaid(String expenseId) async {
    if (currentMember.role != MemberRole.treasurer && currentMember.role != MemberRole.admin) {
      throw StateError('Only the treasurer or flat admin can record payments.');
    }
    final expense = expenses.where((e) => e.id == expenseId).firstOrNull;
    if (expense == null) throw StateError('Expense request not found.');
    if (expense.status != ExpenseStatus.approved) throw StateError('Only approved requests can be paid.');
    await db.from('expenses').update({'status': 'paid'}).eq('id', expenseId).eq('flat_id', flatId);
    await load();
  }

  MemberRole _role(String? role) => switch (role) {
    'admin' => MemberRole.admin,
    'treasurer' => MemberRole.treasurer,
    _ => MemberRole.member,
  };
  ExpenseStatus _status(String? status) => switch (status) {
    'approved' => ExpenseStatus.approved,
    'rejected' => ExpenseStatus.rejected,
    'paid' => ExpenseStatus.paid,
    _ => ExpenseStatus.pending,
  };
  LedgerType _ledgerType(String type) => switch (type) {
    'repayment' => LedgerType.repayment,
    'expense_payment' => LedgerType.expensePayment,
    'withdrawal' => LedgerType.withdrawal,
    _ => LedgerType.contribution,
  };
}
