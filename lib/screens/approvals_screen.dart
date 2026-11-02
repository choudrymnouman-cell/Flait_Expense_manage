import '../services/app_preferences.dart';
import 'package:flutter/material.dart';

import '../models/flat_models.dart';
import 'expense_details_screen.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key, required this.state});
  final FlaitState state;

  @override
  Widget build(BuildContext context) {
    final pending = state.expenses
        .where((e) => e.status == ExpenseStatus.pending && !e.cancelled)
        .toList();
    final approved = state.expenses
        .where((e) => e.status == ExpenseStatus.approved && !e.cancelled)
        .toList();
    final canPay = state.currentMember.role == MemberRole.treasurer ||
        state.currentMember.role == MemberRole.admin;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        const PageHeading(
          title: 'Approvals',
          subtitle: 'Review purchases and track approved reimbursements.',
        ),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: AppText('No requests are waiting for a decision.'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Needs your decision'),
                for (final expense in pending)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      expense.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    AppText(
                                      '${state.memberName(expense.requesterId)} · ${expense.category} · ${expenseDate(expense.createdAt)}',
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AppText(
                                money(expense.amount, currency: state.currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (_) => ExpenseDetailsScreen(
                                          state: state, id: expense.id))),
                              icon: const Icon(Icons.history),
                              label: const AppText(
                                  'Details, shares & corrections')),
                          if (expense.description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: AppText(expense.description),
                            ),
                          const SizedBox(height: 14),
                          AppText(
                            '${expense.votes.length} of ${state.members.where((m) => m.active && m.id != expense.requesterId).length} eligible votes recorded',
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (expense.requesterId == state.currentMemberId)
                            const AppText(
                              'You submitted this request and cannot vote on it.',
                              style: TextStyle(color: Colors.deepOrange),
                            )
                          else if (state.voteQueued(expense.id) ||
                              expense.votes.any(
                                (v) => v.memberId == state.currentMemberId,
                              ))
                            const AppText(
                              'Your vote is saved. Sync with the owner to share local votes.',
                              style: TextStyle(color: Colors.green),
                            )
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _vote(context, expense.id, false),
                                  icon: const Icon(Icons.close),
                                  label: const AppText('Reject'),
                                ),
                                FilledButton.icon(
                                  onPressed: () =>
                                      _vote(context, expense.id, true),
                                  icon: const Icon(Icons.check),
                                  label: const AppText('Approve'),
                                ),
                              ],
                            ),
                          if (expense.votes.isNotEmpty) ...[
                            const Divider(height: 26),
                            for (final vote in expense.votes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Row(
                                  children: [
                                    Icon(
                                      vote.approved
                                          ? Icons.check_circle_outline
                                          : Icons.cancel_outlined,
                                      size: 16,
                                      color: vote.approved
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: AppText(
                                        '${state.memberName(vote.memberId)}: ${vote.approved ? 'Approved' : 'Rejected'}',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (approved.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 24, 22, 12),
            child: SectionTitle('Approved · awaiting payment'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                for (final expense in approved)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.payments_outlined),
                      ),
                      title: AppText(
                        expense.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: AppText(
                        '${state.memberName(expense.requesterId)} · approved, unpaid · ${expenseDate(expense.createdAt)}',
                      ),
                      trailing: canPay
                          ? FilledButton(
                              onPressed: state.paymentQueued(expense.id)
                                  ? null
                                  : () => _pay(context, expense.id),
                              child: AppText(state.paymentQueued(expense.id)
                                  ? 'Queued for owner'
                                  : 'Record payment'),
                            )
                          : AppText(
                              money(expense.amount, currency: state.currency),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: AppText(
                'Default policy: a strict majority of eligible flatmates must approve or reject. The requester cannot vote on their own claim. Approval does not change the pool balance until the treasurer records payment. The owner device validates and signs the shared journal. Queued votes and payments are finalized when synced with the owner.',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _vote(BuildContext context, String id, bool approve) async {
    try {
      await state.vote(id, approve);
      if (!context.mounted) return;
      final result = state.expenses.firstWhere((e) => e.id == id).status;
      final message = result == ExpenseStatus.approved
          ? 'Request approved. Awaiting treasurer payment.'
          : result == ExpenseStatus.rejected
              ? 'Request rejected.'
              : 'Your vote is saved. Sync with the owner to share local votes.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: AppText(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _pay(BuildContext context, String id) async {
    try {
      await state.markPaid(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(state.isOwner
              ? 'Payment recorded and pool balance updated.'
              : 'Payment queued locally. Sync with the owner to finalize it.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }
}
