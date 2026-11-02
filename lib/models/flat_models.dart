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
    this.shares = const {},
    this.cancelled = false,
    this.revision = 0,
    this.recurringKey,
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
  final Map<String, int> shares;
  final bool cancelled;
  final int revision;
  final String? recurringKey;

  ExpenseRequest copyWith({
    ExpenseStatus? status,
    List<ExpenseVote>? votes,
    DateTime? paidAt,
    String? title,
    String? description,
    String? category,
    double? amount,
    Map<String, int>? shares,
    bool? cancelled,
    int? revision,
    String? receiptReference,
  }) =>
      ExpenseRequest(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        amount: amount ?? this.amount,
        requesterId: requesterId,
        createdAt: createdAt,
        status: status ?? this.status,
        votes: votes ?? this.votes,
        receiptReference: receiptReference ?? this.receiptReference,
        shares: shares ?? this.shares,
        cancelled: cancelled ?? this.cancelled,
        revision: revision ?? this.revision,
        recurringKey: recurringKey,
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
    this.memberId,
  });

  final String id;
  final LedgerType type;

  /// Positive amount; type determines how the pool balance changes.
  final double amount;
  final String actorId;
  final String description;
  final DateTime createdAt;
  final String? relatedExpenseId;

  /// Contributor or recipient; actorId is the person who recorded the entry.
  /// Null on legacy entries whose contributor cannot be reconstructed.
  final String? memberId;

  double get poolDelta => switch (type) {
        LedgerType.contribution || LedgerType.repayment => amount,
        LedgerType.expensePayment || LedgerType.withdrawal => -amount,
      };
}
