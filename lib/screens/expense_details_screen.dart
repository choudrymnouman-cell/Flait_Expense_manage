import '../services/app_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';
import 'expense_entry_screen.dart';

class ExpenseDetailsScreen extends StatelessWidget {
  const ExpenseDetailsScreen(
      {super.key, required this.state, required this.id});
  final FlaitState state;
  final String id;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final matches = state.expenses.where((e) => e.id == id);
        if (matches.isEmpty) {
          return const Scaffold(
              body: Center(
                  child: AppText('Expense unavailable. Reload local data.')));
        }
        final e = matches.first,
            receipt = e.receiptReference ?? state.localReceipts[id] as String?;
        final history = state.view?.history[id] ?? [];
        return Scaffold(
            appBar: AppBar(title: const AppText('Expense & history')),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              AppText(e.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              AppText(
                  '${money(e.amount, currency: state.currency)} · ${expenseDate(e.createdAt)}'),
              AppText(
                  '${state.memberName(e.requesterId)} · ${e.category} · ${e.cancelled ? 'cancelled' : e.status.name} · revision ${e.revision}'),
              AppText(e.description),
              if (!state.view!.expenses.containsKey(id))
                const AppText(
                    'Waiting for owner confirmation. This request is still local.'),
              const Divider(),
              const AppText('Cost allocation',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (e.shares.isEmpty)
                const AppText(
                    'Legacy request: no allocation was recorded. Its reimbursement remains in the pool ledger.'),
              for (final s in e.shares.entries)
                ListTile(
                    title: AppText(state.memberName(s.key)),
                    trailing: AppText(
                        money(s.value / 100, currency: state.currency))),
              if (receipt != null) ...[
                const Divider(),
                AppText(e.receiptReference == null
                    ? 'Receipt · only on this device'
                    : 'Receipt · shared in encrypted history'),
                Image.memory(base64Decode(receipt),
                    height: 320,
                    errorBuilder: (_, __, ___) =>
                        const AppText('Receipt preview unavailable.'))
              ],
              if (state.view!.expenses.containsKey(id) && !e.cancelled) ...[
                if (e.requesterId == state.currentMemberId &&
                    e.status == ExpenseStatus.pending)
                  OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                  appBar: AppBar(
                                      title: const AppText('Correct request')),
                                  body: ExpenseEntryScreen(
                                      state: state,
                                      expense: e,
                                      onSubmitted: () =>
                                          Navigator.pop(context))))),
                      icon: const Icon(Icons.edit_outlined),
                      label: const AppText('Correct pending expense')),
                if (e.status != ExpenseStatus.paid &&
                    (state.isOwner || e.requesterId == state.currentMemberId))
                  TextButton.icon(
                      onPressed: () async {
                        final c = TextEditingController();
                        final reason = await showDialog<String>(
                            context: context,
                            builder: (d) => AlertDialog(
                                    title: const AppText('Cancel expense'),
                                    content: TextField(
                                        controller: c,
                                        maxLength: 300,
                                        decoration: const InputDecoration(
                                            labelText: 'Reason (required)')),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(d),
                                          child: const AppText('Keep')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(d, c.text),
                                          child:
                                              const AppText('Cancel expense'))
                                    ]));
                        if (reason == null) return;
                        try {
                          await state.cancelExpense(id, reason);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: AppText('$error')));
                          }
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const AppText('Cancel with reason')),
              ],
              const Divider(),
              const AppText('Signed audit history',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final event in history)
                ListTile(
                    leading: const Icon(Icons.history),
                    title: AppText(
                        '${event['action']} · ${state.memberName(event['actor'] as String)}'),
                    subtitle: AppText(
                        '${event['at']}\n${event['reason'] ?? ''}\n${event['data'] is Map ? '${(event['data'] as Map)['title'] ?? ''} · ${((event['data'] as Map)['cents'] as int? ?? 0) / 100}' : ''}')),
              const AppText(
                  'History cannot be erased by editing. Other devices may retain records and receipts already shared with them.'),
            ]));
      });
}
