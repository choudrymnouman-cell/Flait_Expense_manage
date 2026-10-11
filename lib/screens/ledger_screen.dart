import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key, required this.state});
  final FlaitState state;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 28), children: [
    PageHeading(title: 'Pool ledger', subtitle: 'A chronological view of actual money movement.', trailing: FilledButton.icon(onPressed: () => _showContribution(context), icon: const Icon(Icons.add), label: const Text('Add funds'))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: BalanceCard(label: 'Current pool balance', value: money(state.poolBalance), icon: Icons.account_balance_wallet_outlined, emphasized: true)),
    Padding(padding: const EdgeInsets.fromLTRB(22, 26, 22, 12), child: SectionTitle('Transactions', trailing: Text('${state.ledger.length} entries'))),
    if (state.ledger.isEmpty)
      const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No transactions yet.')))
    else
      Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Card(child: Column(children: [
        for (var i = 0; i < state.ledger.length; i++) ...[
          _LedgerTile(entry: state.ledger[i], actorName: state.memberName(state.ledger[i].actorId)),
          if (i < state.ledger.length - 1) const Divider(height: 1, indent: 72),
        ],
      ]))),
    const Padding(padding: EdgeInsets.fromLTRB(22, 16, 22, 0), child: Text('Only recorded contributions, repayments, withdrawals and paid expenses affect the pool. Pending and approved-but-unpaid requests do not.', style: TextStyle(color: Colors.blueGrey, fontSize: 12))),
  ]);

  void _showContribution(BuildContext context) {
    final amount = TextEditingController();
    final description = TextEditingController();
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Record pool contribution'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (PKR)', prefixText: 'Rs. ')),
        const SizedBox(height: 12),
        TextField(controller: description, decoration: const InputDecoration(labelText: 'Note')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          try {
            state.recordContribution(double.parse(amount.text.trim()), description.text);
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contribution recorded.')));
          } catch (error) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''))));
          }
        }, child: const Text('Save')),
      ],
    ));
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry, required this.actorName});
  final LedgerEntry entry;
  final String actorName;

  @override
  Widget build(BuildContext context) {
    final incoming = entry.poolDelta >= 0;
    final label = switch (entry.type) {
      LedgerType.contribution => 'Pool contribution',
      LedgerType.repayment => 'Repayment',
      LedgerType.expensePayment => 'Expense payment',
      LedgerType.withdrawal => 'Withdrawal',
    };
    return ListTile(
      leading: CircleAvatar(backgroundColor: incoming ? const Color(0xFFE7F6ED) : const Color(0xFFFFECEC), child: Icon(incoming ? Icons.south_west : Icons.north_east, color: incoming ? Colors.green : Colors.red)),
      title: Text(entry.description, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('$label · $actorName\n${entry.createdAt.toLocal().toString().substring(0, 16)}'),
      isThreeLine: true,
      trailing: Text('${incoming ? '+' : '−'}${money(entry.amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: incoming ? Colors.green : Colors.red)),
    );
  }
}
