import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key, required this.state});
  final FlaitState state;

  @override
  Widget build(BuildContext context) {
    final pending = state.expenses.where((e) => e.status == ExpenseStatus.pending).toList();
    final approved = state.expenses.where((e) => e.status == ExpenseStatus.approved).toList();
    final canPay = state.currentMember.role == MemberRole.treasurer || state.currentMember.role == MemberRole.admin;
    return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
      const PageHeading(title: 'Approvals', subtitle: 'Review purchases and track approved reimbursements.'),
      if (pending.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No requests are waiting for a decision.')))
      else
        Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Needs your decision'),
          for (final expense in pending) Card(
            child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(expense.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 4),
                  Text('${state.memberName(expense.requesterId)} · ${expense.category}', style: const TextStyle(color: Colors.blueGrey)),
                ])),
                Text(money(expense.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ]),
              if (expense.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(expense.description)),
              const SizedBox(height: 14),
              Text('${expense.votes.length} of ${state.members.where((m) => m.active && m.id != expense.requesterId).length} eligible votes recorded', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
              const SizedBox(height: 12),
              if (expense.requesterId == state.currentMemberId)
                const Text('You submitted this request and cannot vote on it.', style: TextStyle(color: Colors.deepOrange))
              else if (expense.votes.any((v) => v.memberId == state.currentMemberId))
                const Text('Your vote has been recorded.', style: TextStyle(color: Colors.green))
              else
                Wrap(spacing: 10, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _vote(context, expense.id, false), icon: const Icon(Icons.close), label: const Text('Reject')),
                  FilledButton.icon(onPressed: () => _vote(context, expense.id, true), icon: const Icon(Icons.check), label: const Text('Approve')),
                ]),
              if (expense.votes.isNotEmpty) ...[
                const Divider(height: 26),
                for (final vote in expense.votes)
                  Padding(padding: const EdgeInsets.only(bottom: 5), child: Row(children: [
                    Icon(vote.approved ? Icons.check_circle_outline : Icons.cancel_outlined, size: 16, color: vote.approved ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${state.memberName(vote.memberId)}: ${vote.approved ? 'Approved' : 'Rejected'}')),
                  ])),
              ],
            ])),
          ),
        ])),
      if (approved.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(22, 24, 22, 12), child: SectionTitle('Approved · awaiting payment')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Column(children: [
          for (final expense in approved) Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
            title: Text(expense.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${state.memberName(expense.requesterId)} · approved, unpaid'),
            trailing: canPay ? FilledButton(onPressed: () => _pay(context, expense.id), child: const Text('Record payment')) : Text(money(expense.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
          )),
        ])),
      ],
      const Padding(padding: EdgeInsets.fromLTRB(22, 20, 22, 0), child: Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Default policy: a strict majority of eligible flatmates must approve or reject. The requester cannot vote on their own claim. Approval does not change the pool balance until the treasurer records payment. A production backend must enforce these rules.')))),
    ]);
  }

  void _vote(BuildContext context, String id, bool approve) {
    try {
      state.vote(id, approve);
      final result = state.expenses.firstWhere((e) => e.id == id).status;
      final message = result == ExpenseStatus.approved ? 'Request approved. Awaiting treasurer payment.' : result == ExpenseStatus.rejected ? 'Request rejected.' : 'Your vote has been recorded.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))));
    }
  }

  void _pay(BuildContext context, String id) {
    try {
      state.markPaid(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded and pool balance updated.')));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))));
    }
  }
}
