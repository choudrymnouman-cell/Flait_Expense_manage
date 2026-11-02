import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key, required this.state});
  final FlaitState state;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          PageHeading(
            title: 'Pool ledger',
            subtitle: 'A chronological view of actual money movement.',
            trailing: FilledButton.icon(
              onPressed: state.currentMember.role == MemberRole.admin ||
                      state.currentMember.role == MemberRole.treasurer
                  ? () => _showContribution(context)
                  : null,
              icon: const Icon(Icons.add),
              label: const AppText('Add funds'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: BalanceCard(
              label: 'Current pool balance',
              value: money(state.poolBalance, currency: state.currency),
              icon: Icons.account_balance_wallet_outlined,
              emphasized: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 12),
            child: SectionTitle(
              'Transactions',
              trailing: AppText('${state.ledger.length} entries'),
            ),
          ),
          if (state.ledger.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: AppText('No transactions yet.')),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Card(
                child: Column(
                  children: [
                    for (var i = 0; i < state.ledger.length; i++) ...[
                      _LedgerTile(
                        entry: state.ledger[i],
                        actorName: state.memberName(state.ledger[i].actorId),
                        memberName: state.ledger[i].memberId == null
                            ? 'Unattributed legacy entry'
                            : state.memberName(state.ledger[i].memberId!),
                        currency: state.currency,
                      ),
                      if (i < state.ledger.length - 1)
                        const Divider(height: 1, indent: 72),
                    ],
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 22, 0),
            child: AppText(
              'Only recorded contributions, repayments, withdrawals and paid expenses affect the pool. Pending and approved-but-unpaid requests do not.',
              style: TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
          ),
        ],
      );

  Future<void> _showContribution(BuildContext context) async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => _ContributionDialog(state: state),
    );
    if (!context.mounted || recorded != true) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText(
            'Contribution saved. Treasurer entries need owner sync before affecting the shared pool.')));
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.entry,
    required this.actorName,
    required this.memberName,
    required this.currency,
  });
  final LedgerEntry entry;
  final String actorName;
  final String memberName;
  final String currency;

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
      leading: CircleAvatar(
        backgroundColor:
            incoming ? const Color(0xFFE7F6ED) : const Color(0xFFFFECEC),
        child: Icon(
          incoming ? Icons.south_west : Icons.north_east,
          color: incoming ? Colors.green : Colors.red,
        ),
      ),
      title: AppText(
        entry.description,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: AppText(
        '$label · $memberName\nRecorded by $actorName · ${entry.createdAt.toLocal().toString().substring(0, 16)}',
      ),
      isThreeLine: true,
      trailing: AppText(
        '${incoming ? '+' : '−'}${money(entry.amount, currency: currency)}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: incoming ? Colors.green : Colors.red,
        ),
      ),
    );
  }
}

class _ContributionDialog extends StatefulWidget {
  const _ContributionDialog({required this.state});
  final FlaitState state;
  @override
  State<_ContributionDialog> createState() => _ContributionDialogState();
}

class _ContributionDialogState extends State<_ContributionDialog> {
  final amount = TextEditingController();
  final description = TextEditingController();
  final requestId = const Uuid().v4();
  late String contributorId = widget.state.currentMemberId;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    final value = double.tryParse(amount.text.trim());
    if (!validMoneyAmount(value)) {
      setState(
        () => error = 'Enter a positive amount with at most 2 decimals.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.state.recordContribution(
        value!,
        description.text,
        contributorId: contributorId,
        requestId: requestId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !saving,
        child: AlertDialog(
          title: const AppText('Record pool contribution'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: contributorId,
                  decoration:
                      const InputDecoration(labelText: 'Contributed by'),
                  items: widget.state.members
                      .where((m) => m.active)
                      .map(
                        (m) => DropdownMenuItem(
                            value: m.id, child: AppText(m.name)),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (id) => setState(() => contributorId = id!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount (${widget.state.currency})',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppText(error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              onPressed: saving ? null : save,
              child: AppText(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      );
}
