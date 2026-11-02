import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import '../widgets/pro_tools.dart';

import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.state,
    required this.onAddExpense,
  });
  final FlaitState state;
  final VoidCallback onAddExpense;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width >= 850
        ? MediaQuery.sizeOf(context).width -
            (MediaQuery.sizeOf(context).width >= 1100 ? 257 : 81)
        : MediaQuery.sizeOf(context).width;
    final columns = width >= 1150
        ? 3
        : width >= 650
            ? 2
            : 1;
    final balances = state.accounting.memberNetBalances(
      members: state.members,
      entries: state.ledger,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        PageHeading(
          title: 'Good day, ${state.currentMember.name.split(' ').first}',
          subtitle: 'Here is what is happening in your flat today.',
          trailing: FilledButton.icon(
            onPressed: onAddExpense,
            icon: const Icon(Icons.add),
            label: const AppText('Add expense'),
          ),
        ),
        ProTools(state: state),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: columns == 1
                    ? width - 44
                    : (width - (columns == 3 ? 68 : 56)) / columns,
                child: BalanceCard(
                  label: 'Available pool balance',
                  value: money(state.poolBalance, currency: state.currency),
                  icon: Icons.account_balance_wallet_outlined,
                  emphasized: true,
                ),
              ),
              SizedBox(
                width: columns == 1
                    ? width - 44
                    : (width - (columns == 3 ? 68 : 56)) / columns,
                child: BalanceCard(
                  label: 'Pending requests',
                  value: '${state.pendingCount}',
                  icon: Icons.pending_actions_outlined,
                ),
              ),
              SizedBox(
                width: columns == 1
                    ? width - 44
                    : (width - (columns == 3 ? 68 : 56)) / columns,
                child: BalanceCard(
                  label: 'Flatmates',
                  value: '${state.members.where((m) => m.active).length}',
                  icon: Icons.groups_outlined,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 28, 22, 0),
          child: SectionTitle('Net pool activity by member'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Card(
            child: Column(
              children: [
                for (var i = 0; i < state.members.length; i++) ...[
                  ListTile(
                    leading: CircleAvatar(
                      child: AppText(state.members[i].name.substring(0, 1)),
                    ),
                    title: AppText(
                      state.members[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: AppText(switch (state.members[i].role) {
                      MemberRole.treasurer => 'Treasurer',
                      MemberRole.admin => 'Flat admin',
                      MemberRole.member => 'Flatmate',
                    }),
                    trailing: AppText(
                      money(
                        balances[state.members[i].id] ?? 0,
                        currency: state.currency,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (i < state.members.length - 1)
                    const Divider(height: 1, indent: 72),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
          child: SectionTitle(
            'Recent requests',
            trailing: AppText('${state.expenses.length} total'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: [
              for (final expense in state.expenses.take(4))
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFEAF0FF),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: AppText(
                      expense.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: AppText(
                      '${state.memberName(expense.requesterId)} · ${expense.category} · ${expenseDate(expense.createdAt)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppText(
                          money(expense.amount, currency: state.currency),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        ExpenseStatusChip(status: expense.status),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: AppText(
            'Amounts show contributions minus reimbursements received, not who owes whom. Shared costs are not allocated. Legacy contributions without a known contributor are excluded; pool totals still include them.',
            style: TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
