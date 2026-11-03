import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../offline/live_sync.dart';
import '../offline/secure_book.dart';
import '../state/app_state.dart';
import 'entry_form.dart';
import 'monthly_state.dart';

const sectionNames = {
  'meal': 'Meal With Friends',
  'flat': 'Flait Friends',
  'loan': 'Loan',
};

class GroupsScreen extends StatelessWidget {
  const GroupsScreen(this.state, this.kind, {super.key});
  final MonthlyState state;
  final String kind;

  Future<void> create(BuildContext context) async {
    if (kind == 'loan') {
      await createLoan(context);
      return;
    }
    final input = await entryForm(context, 'Create group', const [
      EntryField('name', 'Group name'),
    ]);
    if (input == null || !context.mounted) return;
    await perform(context, () async {
      final group = await state.newGroup(kind, name: input['name']!.trim());
      if (context.mounted) await openGroup(context, group);
    });
  }

  Future<void> createLoan(BuildContext context) async {
    final people = {
      for (final m in state.contacts) m.id: m.name,
      'new': 'Invite by code',
    };
    final now = DateTime.now();
    final input = await entryForm(context, 'Create loan', [
      EntryField('member', 'Member', options: people),
      const EntryField(
        'direction',
        'Loan type',
        options: {'given': 'Given', 'taken': 'Taken'},
      ),
      const EntryField('amount', 'Amount', money: true),
    ]);
    if (input == null || !context.mounted) return;
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateUtils.dateOnly(now),
      lastDate: DateTime(now.year + 20),
      helpText: 'Return date',
    );
    if (date == null || !context.mounted) return;
    await perform(context, () async {
      final amount = parseMoney(input['amount']!);
      final member = input['member']!;
      final group = await state.newGroup(
        'loan',
        name: member == 'new' ? 'New loan' : 'Loan with ${people[member]}',
        invitee: member == 'new' ? null : member,
      );
      if (member != 'new') await group.addMember(member, people[member]!);
      await group.operation('loan_entry', {
        'month': state.currentMonth,
        'cents': amount,
        'due': dateOf(date),
        'direction': input['direction'],
      });
      if (context.mounted) await openGroup(context, group);
    });
  }

  Future<void> join(BuildContext context) async {
    final input = await entryForm(context, 'Join with code', const [
      EntryField('code', 'Invitation code'),
    ]);
    if (input == null || !context.mounted) return;
    final code = input['code']!.trim();
    if (!RegExp(r'^FLAIT2-[A-Za-z0-9_-]{43}$').hasMatch(code)) {
      await perform(
        context,
        () async => throw const FormatException('Invalid invitation code.'),
      );
      return;
    }
    await perform(context, () async {
      final group = await state.newGroup(kind);
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PairingScreen(
            group: group,
            kind: kind,
            invite: code,
            acceptGroup: (id) =>
                !state.groups.values.any((g) => g.flatId == id),
          ),
        ),
      );
      if (group.book != null && context.mounted) {
        await openGroup(context, group);
      }
    });
  }

  Future<void> openGroup(BuildContext context, FlaitState group) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => GroupDetail(state, group, kind)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(sectionNames[kind]!)),
        body: AnimatedBuilder(
          animation: state,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => create(context),
                    icon: const Icon(Icons.add),
                    label:
                        Text(kind == 'loan' ? 'Create loan' : 'Create group'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => join(context),
                    icon: const Icon(Icons.key),
                    label: const Text('Join with code'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final group in state.ofKind(kind))
                if (kind != 'loan' ||
                    (group.preferences['hiddenLoan'] != true &&
                        group.view!.monthly.values.any(
                          (r) => r['type'] == 'loan',
                        )))
                  Card(
                    child: ListTile(
                      title: Text(group.flatName),
                      subtitle: Text(
                        kind == 'loan'
                            ? loanSummary(group)
                            : '${group.members.where((m) => m.active).length} members',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openGroup(context, group),
                    ),
                  ),
            ],
          ),
        ),
      );
}

String loanSummary(FlaitState group) {
  final loan = group.view!.monthly.values.firstWhere(
    (r) => r['type'] == 'loan',
  );
  return '${MonthlyState.isLender(group, loan) ? 'Given' : 'Taken'} · ${rupees(loan['cents'] as int)}';
}

class PairingScreen extends StatefulWidget {
  const PairingScreen({
    required this.group,
    required this.kind,
    this.invite,
    this.acceptGroup,
    super.key,
  });
  final FlaitState group;
  final String kind;
  final String? invite;
  final bool Function(String)? acceptGroup;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late final SyncSession session;
  String? error;

  @override
  void initState() {
    super.initState();
    session = SyncSession(
      widget.group,
      host: widget.invite == null,
      expectedKind: widget.kind,
      acceptGroup: widget.acceptGroup,
    );
    unawaited(start());
  }

  Future<void> start() async {
    try {
      await session.start(invite: widget.invite);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Could not connect. Check the code and internet.',
        );
      }
    }
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title:
              Text(widget.invite == null ? 'Invite member' : 'Join with code'),
        ),
        body: AnimatedBuilder(
          animation: session,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error != null) Text(error!),
              if (widget.invite == null && session.connected) ...[
                SelectableText(session.code),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: session.code)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy code'),
                ),
              ],
              if (session.awaitingAdmission)
                FilledButton(
                  onPressed: () => perform(context, session.approveMember),
                  child: Text('Add ${session.peerName ?? 'member'}'),
                ),
              if (session.completed)
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              if (!session.completed && error == null)
                Text(
                  session.awaitingAdmission
                      ? 'Waiting for approval'
                      : session.status,
                ),
            ],
          ),
        ),
      );
}

class GroupDetail extends StatelessWidget {
  const GroupDetail(this.state, this.group, this.kind, {super.key});
  final MonthlyState state;
  final FlaitState group;
  final String kind;

  Future<void> addMeal(BuildContext context) async {
    final people = {
      for (final m in group.members.where((m) => m.active)) m.id: m.name,
    };
    final bill = await entryForm(context, 'Add meal', const [
      EntryField('title', 'Meal name'),
      EntryField('amount', 'Total bill', money: true),
      EntryField(
        'mode',
        'Payment',
        options: {'one': 'Pay one', 'contribution': 'Contribution'},
      ),
    ]);
    if (bill == null || !context.mounted) return;
    await perform(context, () async {
      final total = parseMoney(bill['amount']!);
      final paid = <String, int>{};
      if (bill['mode'] == 'one') {
        final payer = await entryForm(context, 'Pay one', [
          EntryField('member', 'Paid by', options: people),
        ]);
        if (payer == null) return;
        paid[payer['member']!] = total;
      } else {
        final contributions = await entryForm(context, 'Contribution', [
          for (final m in people.entries)
            EntryField(m.key, m.value, money: true, initial: '0'),
        ]);
        if (contributions == null) return;
        paid.addAll(
          contributions.map(
            (key, value) => MapEntry(key, parseMoney(value, zero: true)),
          ),
        );
      }
      await group.operation('meal_entry', {
        'month': state.currentMonth,
        'title': bill['title'],
        'cents': total,
        'paid': paid,
      });
    });
  }

  Future<void> setBudget(BuildContext context) async {
    final input = await entryForm(context, 'Monthly flat budget', const [
      EntryField('amount', 'Budget', money: true),
    ]);
    if (input == null || !context.mounted) return;
    await perform(
      context,
      () => group.operation('flat_budget', {
        'month': state.currentMonth,
        'cents': parseMoney(input['amount']!),
      }),
    );
  }

  Future<void> addFlatItem(BuildContext context) async {
    final input = await entryForm(context, 'Add item', const [
      EntryField('title', 'Item name'),
      EntryField('amount', 'Price', money: true),
      EntryField(
        'pay',
        'Payment',
        options: {'admin': 'Pay by admin', 'individual': 'Individual pay'},
      ),
    ]);
    if (input == null || !context.mounted) return;
    await perform(
      context,
      () => group.operation('flat_item', {
        'month': state.currentMonth,
        'title': input['title'],
        'cents': parseMoney(input['amount']!),
        'pay': input['pay'],
      }),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final rows = group.view!.monthly.entries
              .where((e) => e.value['month'] == state.currentMonth)
              .toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(group.flatName),
              actions: [
                if (group.isOwner)
                  IconButton(
                    tooltip: 'Invite member',
                    icon: const Icon(Icons.person_add_outlined),
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PairingScreen(group: group, kind: kind),
                      ),
                    ),
                  ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (kind == 'meal') ...[
                  FilledButton.icon(
                    onPressed: () => addMeal(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add meal'),
                  ),
                  for (final row
                      in rows.where((r) => r.value['type'] == 'meal'))
                    mealCard(row.value),
                ],
                if (kind == 'flat') ...flatSection(context, rows),
                if (kind == 'loan')
                  for (final row in group.view!.monthly.entries.where(
                    (r) => r.value['type'] == 'loan',
                  ))
                    loanCard(context, row),
                if (kind != 'loan') ...[
                  const SizedBox(height: 12),
                  const Text('Members'),
                  for (final member in group.members.where((m) => m.active))
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(member.name),
                      trailing: member.id == group.book!.owner
                          ? const Text('Admin')
                          : null,
                    ),
                ],
                if (group.proposals.any(
                  (p) => asMap(p['body'])['author'] == group.currentMemberId,
                ))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Pending admin confirmation'),
                  ),
              ],
            ),
          );
        },
      );

  Widget mealCard(Map<String, dynamic> row) {
    final shares = asMap(row['shares']), paid = asMap(row['paid']);
    final debts = group.settlement.suggestions(mealBalances(row));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row['title']} · ${rupees(row['cents'] as int)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final s in shares.entries)
              Text(
                '${group.memberName(s.key)} · Share ${rupees(s.value as int)} · Paid ${rupees(paid[s.key] as int? ?? 0)}',
              ),
            for (final debt in debts)
              Text(
                  '${group.memberName(debt.from)} owes ${group.memberName(debt.to)} ${rupees(debt.cents)}'),
          ],
        ),
      ),
    );
  }

  List<Widget> flatSection(
    BuildContext context,
    List<MapEntry<String, Map<String, dynamic>>> rows,
  ) {
    final budget = group.view!.monthly['budget:${state.currentMonth}'];
    final items = rows.where((r) => r.value['type'] == 'item').toList();
    final approved = items.where((r) => r.value['approved'] == true);
    final spent = approved.fold<int>(
      0,
      (sum, r) => sum + (r.value['cents'] as int),
    );
    final total = budget?['cents'] as int? ?? 0;
    return [
      Text(state.currentMonth),
      ListTile(
        title: const Text('Monthly budget'),
        trailing: Text(rupees(total)),
      ),
      ListTile(
        title: const Text('Approved expenses'),
        trailing: Text(rupees(spent)),
      ),
      ListTile(
        title: const Text('Remaining budget'),
        trailing: Text(rupees(total - spent)),
      ),
      Wrap(
        spacing: 8,
        children: [
          if (group.isOwner)
            OutlinedButton(
              onPressed: () => setBudget(context),
              child: const Text('Set budget'),
            ),
          if (budget != null)
            FilledButton(
              onPressed: () => addFlatItem(context),
              child: const Text('Add item'),
            ),
        ],
      ),
      for (final item in items)
        Card(
          child: ListTile(
            title: Text(item.value['title'] as String),
            subtitle: Text(
              '${rupees(item.value['cents'] as int)} · ${group.memberName(item.value['payer'] as String)} · ${item.value['approved'] == true ? 'Approved' : 'Pending approval'}',
            ),
            trailing: item.value['approved'] != true &&
                    (item.value['eligible'] as List).contains(
                      group.currentMemberId,
                    ) &&
                    !(item.value['votes'] as List).contains(
                      group.currentMemberId,
                    )
                ? TextButton(
                    onPressed: () => perform(
                      context,
                      () => group.operation('flat_approve', {
                        'month': state.currentMonth,
                        'target': item.key,
                      }),
                    ),
                    child: const Text('Approve'),
                  )
                : null,
          ),
        ),
      const Text('Individual contributions'),
      for (final member in group.members)
        ListTile(
          title: Text(member.name),
          subtitle: Text(
            'Budget share ${rupees(asMap(budget?['shares'] ?? {})[member.id] as int? ?? 0)}',
          ),
          trailing: Text(
            rupees(
              approved
                  .where(
                    (r) =>
                        r.value['pay'] == 'individual' &&
                        r.value['payer'] == member.id,
                  )
                  .fold<int>(0, (sum, r) => sum + (r.value['cents'] as int)),
            ),
          ),
        ),
    ];
  }

  Widget loanCard(
    BuildContext context,
    MapEntry<String, Map<String, dynamic>> entry,
  ) {
    final row = entry.value;
    final returned = row['returned'] == true;
    final lender = MonthlyState.isLender(group, row);
    final other =
        group.members.where((m) => m.id != group.currentMemberId).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${lender ? 'Given' : 'Taken'} · ${rupees(row['cents'] as int)}',
            ),
            if (other != null) Text(other.name),
            Text('Return date · ${row['due']}'),
            if (returned) const Text('Returned'),
            if (lender && !returned)
              FilledButton(
                onPressed: () => perform(
                  context,
                  () => group.operation('loan_return', {
                    'month': state.currentMonth,
                    'target': entry.key,
                  }),
                ),
                child: const Text('Mark returned'),
              ),
            if (returned)
              TextButton(
                onPressed: () async {
                  await group.setPreference('hiddenLoan', true);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Remove from list'),
              ),
          ],
        ),
      ),
    );
  }
}
