import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../services/app_preferences.dart';
import '../widgets/flait_widgets.dart';

class DuesScreen extends StatelessWidget {
  const DuesScreen({super.key, required this.state});
  final FlaitState state;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final balances = state.dues,
            suggestions = state.settlement.suggestions(balances);
        return Scaffold(
            appBar: AppBar(
                title: AppText(tr(context, 'Member dues & settlements',
                    'ارکان کے بقایاجات'))),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              AppText(
                  'Shared pool: ${money(state.poolBalance, currency: state.currency)}',
                  style: Theme.of(context).textTheme.titleLarge),
              const AppText(
                  'Positive = receivable/credit; negative = payable. Credits include unused pool contributions. Together all member balances equal the remaining pool. Pending requests and queued settlements are excluded. Legacy expenses without shares do not allocate a cost.'),
              for (final m in state.members)
                Card(
                    child: ListTile(
                        title: AppText(
                            '${m.name}${m.active ? '' : ' · inactive'}'),
                        subtitle: AppText((balances[m.id] ?? 0) >= 0
                            ? 'Receivable / pool credit'
                            : 'Payable'),
                        trailing: AppText(
                            money((balances[m.id] ?? 0).abs() / 100,
                                currency: state.currency),
                            style: TextStyle(
                                color: (balances[m.id] ?? 0) < 0
                                    ? Colors.deepOrange
                                    : Colors.teal,
                                fontWeight: FontWeight.bold)))),
              const Divider(),
              AppText(
                  tr(context, 'Suggested personal settlements',
                      'مجوزہ ذاتی ادائیگیاں'),
                  style: Theme.of(context).textTheme.titleLarge),
              const AppText(
                  'These suggestions reduce member debts. They do not withdraw money from the shared pool or perform a bank transfer. Record only a payment that actually happened; the owner confirms queued entries.'),
              if (suggestions.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: AppText(
                        'No member-to-member payment is currently due. Positive pool credits may remain.')),
              for (final p in suggestions)
                Card(
                    child: ListTile(
                        title: AppText(
                            '${state.memberName(p.from)} → ${state.memberName(p.to)}'),
                        subtitle: AppText(
                            money(p.cents / 100, currency: state.currency)),
                        trailing: [state.book!.owner, p.from, p.to]
                                .contains(state.currentMemberId)
                            ? OutlinedButton(
                                onPressed: () async {
                                  final c = TextEditingController(
                                      text: (p.cents / 100).toStringAsFixed(2));
                                  final amount = await showDialog<double>(
                                      context: context,
                                      builder: (d) => AlertDialog(
                                              title: const AppText(
                                                  'Record completed payment'),
                                              content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const AppText(
                                                        'Only record money already exchanged. This app will not transfer funds.'),
                                                    TextField(
                                                        controller: c,
                                                        keyboardType:
                                                            const TextInputType
                                                                .numberWithOptions(
                                                                decimal: true),
                                                        decoration:
                                                            const InputDecoration(
                                                                labelText:
                                                                    'Amount'))
                                                  ]),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(d),
                                                    child: const AppText(
                                                        'Cancel')),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            d,
                                                            double.tryParse(
                                                                c.text)),
                                                    child: const AppText(
                                                        'Record payment'))
                                              ]));
                                  if (amount == null) return;
                                  try {
                                    await state.recordSettlement(
                                        p.from, p.to, amount);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: AppText('$e')));
                                    }
                                  }
                                },
                                child: const AppText('Record'))
                            : null)),
              const Divider(),
              const AppText('Confirmed settlement history',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final p in state.view!.settlements.reversed)
                ListTile(
                    title: AppText(
                        '${state.memberName(p.from)} → ${state.memberName(p.to)}'),
                    trailing: AppText(
                        money(p.cents / 100, currency: state.currency))),
            ]));
      });
}
