enum MemberRole { admin, treasurer, member }
enum ExpenseStatus { pending, approved, rejected, paid }
enum LedgerType { contribution, expensePayment, withdrawal, repayment }

class FlatMember {
  const FlatMember({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.active = true,
  });

  final String id;
  final String name;
  final MemberRole role;
  final String email;
  final bool active;
}

class ExpenseVote {
  const ExpenseVote({
    required this.memberId,
    required this.approved,
    required this.at,
    this.comment = '',
  });

  final String memberId;
  final bool approved;
  final DateTime at;
  final String comment;
}

class ExpenseRequest {
  const ExpenseRequest({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.amount,
    required this.requesterId,
    required this.createdAt,
    this.status = ExpenseStatus.pending,
    this.votes = const [],
    this.receiptReference,
    this.paidAt,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final double amount;
  final String requesterId;
  final DateTime createdAt;
  final ExpenseStatus status;
  final List<ExpenseVote> votes;
  final String? receiptReference;
  final DateTime? paidAt;

  ExpenseRequest copyWith({
    ExpenseStatus? status,
    List<ExpenseVote>? votes,
    DateTime? paidAt,
  }) => ExpenseRequest(
    id: id,
    title: title,
    description: description,
    category: category,
    amount: amount,
    requesterId: requesterId,
    createdAt: createdAt,
    status: status ?? this.status,
    votes: votes ?? this.votes,
    receiptReference: receiptReference,
    paidAt: paidAt ?? this.paidAt,
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.actorId,
    required this.description,
    required this.createdAt,
    this.relatedExpenseId,
  });

  final String id;
  final LedgerType type;
  /// Positive amount; type determines how the pool balance changes.
  final double amount;
  final String actorId;
  final String description;
  final DateTime createdAt;
  final String? relatedExpenseId;

  double get poolDelta => switch (type) {
    LedgerType.contribution || LedgerType.repayment => amount,
    LedgerType.expensePayment || LedgerType.withdrawal => -amount,
  };
}
