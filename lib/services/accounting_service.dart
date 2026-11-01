import '../models/flat_models.dart';

class AccountingService {
  const AccountingService();

  double poolBalance(Iterable<LedgerEntry> entries) =>
      entries.fold<int>(
        0,
        (balance, entry) => balance + (entry.poolDelta * 100).round(),
      ) /
      100;

  /// Requester cannot vote on their own claim. A strict majority of all other
  /// active members is the default policy; the server must enforce this in prod.
  int requiredApprovals(int eligibleVoterCount) =>
      eligibleVoterCount == 0 ? 0 : (eligibleVoterCount ~/ 2) + 1;

  ExpenseStatus evaluate({
    required ExpenseRequest expense,
    required List<FlatMember> members,
  }) {
    final eligible =
        members.where((m) => m.active && m.id != expense.requesterId).toList();
    if (eligible.isEmpty) return ExpenseStatus.pending;
    final eligibleIds = eligible.map((m) => m.id).toSet();
    final votes =
        expense.votes.where((v) => eligibleIds.contains(v.memberId)).toList();
    final approvals = votes.where((v) => v.approved).length;
    final rejections = votes.where((v) => !v.approved).length;
    if (approvals >= requiredApprovals(eligible.length)) {
      return ExpenseStatus.approved;
    }
    if (rejections >= requiredApprovals(eligible.length)) {
      return ExpenseStatus.rejected;
    }
    return ExpenseStatus.pending;
  }

  /// Cash supplied minus reimbursements received. This is pool activity,
  /// not a settlement balance: common-cost allocations are not included.
  Map<String, double> memberNetBalances({
    required List<FlatMember> members,
    required List<LedgerEntry> entries,
  }) {
    final result = {for (final member in members) member.id: 0.0};
    for (final entry in entries) {
      final memberId = entry.memberId;
      if (memberId == null || !result.containsKey(memberId)) continue;
      switch (entry.type) {
        case LedgerType.contribution:
          result[memberId] = result[memberId]! + entry.amount;
        case LedgerType.repayment:
          result[memberId] = result[memberId]! + entry.amount;
        case LedgerType.expensePayment:
          result[memberId] = result[memberId]! - entry.amount;
        case LedgerType.withdrawal:
          break;
      }
    }
    return result;
  }
}
