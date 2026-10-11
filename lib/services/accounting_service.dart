import '../models/flat_models.dart';

class AccountingService {
  const AccountingService();

  double poolBalance(Iterable<LedgerEntry> entries) =>
      entries.fold(0, (balance, entry) => balance + entry.poolDelta);

  /// Requester cannot vote on their own claim. A strict majority of all other
  /// active members is the default policy; the server must enforce this in prod.
  int requiredApprovals(int eligibleVoterCount) =>
      eligibleVoterCount == 0 ? 0 : (eligibleVoterCount ~/ 2) + 1;

  ExpenseStatus evaluate({
    required ExpenseRequest expense,
    required List<FlatMember> members,
  }) {
    final eligible = members.where((m) => m.active && m.id != expense.requesterId).toList();
    if (eligible.isEmpty) return ExpenseStatus.pending;
    final eligibleIds = eligible.map((m) => m.id).toSet();
    final votes = expense.votes.where((v) => eligibleIds.contains(v.memberId)).toList();
    final approvals = votes.where((v) => v.approved).length;
    final rejections = votes.where((v) => !v.approved).length;
    if (approvals >= requiredApprovals(eligible.length)) return ExpenseStatus.approved;
    if (rejections >= requiredApprovals(eligible.length)) return ExpenseStatus.rejected;
    return ExpenseStatus.pending;
  }

  /// Member net balance is based on actual ledger entries only. Contributions
  /// and repayments are credited to the contributor; pool-paid expenses are
  /// charged to the requester/purchase beneficiary according to this demo rule.
  Map<String, double> memberNetBalances({
    required List<FlatMember> members,
    required List<LedgerEntry> entries,
  }) {
    final result = {for (final member in members) member.id: 0.0};
    for (final entry in entries) {
      if (!result.containsKey(entry.actorId)) continue;
      switch (entry.type) {
        case LedgerType.contribution:
          result[entry.actorId] = result[entry.actorId]! + entry.amount;
        case LedgerType.repayment:
          result[entry.actorId] = result[entry.actorId]! + entry.amount;
        case LedgerType.expensePayment:
          result[entry.actorId] = result[entry.actorId]! - entry.amount;
        case LedgerType.withdrawal:
          break;
      }
    }
    return result;
  }
}
