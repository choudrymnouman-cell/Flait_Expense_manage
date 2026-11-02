import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../services/app_preferences.dart';
import '../services/report_export.dart';
import '../widgets/flait_widgets.dart';
import 'expense_details_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.state});
  final FlaitState state;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final search = TextEditingController();
  String member = '', category = '', status = '';
  DateTimeRange? range;
  bool busy = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<ExpenseRequest> filtered() => widget.state.expenses.where((e) {
        final q = search.text.toLowerCase().trim(), d = e.createdAt.toLocal();
        return (q.isEmpty ||
                '${e.title} ${e.description} ${widget.state.memberName(e.requesterId)}'
                    .toLowerCase()
                    .contains(q)) &&
            (member.isEmpty || e.requesterId == member) &&
            (category.isEmpty || category == e.category) &&
            (status.isEmpty ||
                (e.cancelled ? 'cancelled' : e.status.name) == status) &&
            (range == null ||
                (!d.isBefore(range!.start) &&
                    d.isBefore(range!.end.add(const Duration(days: 1)))));
      }).toList();
  Future<void> export(bool pdf) async {
    setState(() => busy = true);
    try {
      await exportReport(widget.state, filtered(), pdf: pdf);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: AppText('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final rows = filtered();
        final totals = <String, int>{};
        for (final e in rows.where((e) =>
            !e.cancelled &&
            [ExpenseStatus.approved, ExpenseStatus.paid].contains(e.status))) {
          totals[e.category] =
              (totals[e.category] ?? 0) + (e.amount * 100).round();
        }
        final total = totals.values.fold(0, (a, b) => a + b);
        return Scaffold(
            appBar: AppBar(
                title: AppText(tr(context, 'Reports & expense search',
                    'رپورٹس اور خرچ کی تلاش'))),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: tr(
                          context,
                          'Search title, description or member',
                          'عنوان، تفصیل یا رکن تلاش کریں'),
                      prefixIcon: const Icon(Icons.search))),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                        key: ValueKey('member$member'),
                        initialValue: member,
                        decoration: const InputDecoration(labelText: 'Member'),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: AppText('All members')),
                          for (final m in widget.state.members)
                            DropdownMenuItem(
                                value: m.id,
                                child: AppText(m.name,
                                    overflow: TextOverflow.ellipsis))
                        ],
                        onChanged: (v) => setState(() => member = v!))),
                SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                        key: ValueKey('category$category'),
                        initialValue: category,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: AppText('All categories')),
                          for (final c
                              in widget.state.expenses
                                  .map((e) => e.category)
                                  .toSet()
                                  .toList()
                                ..sort())
                            DropdownMenuItem(value: c, child: AppText(c))
                        ],
                        onChanged: (v) => setState(() => category = v!))),
                SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                        key: ValueKey('status$status'),
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final s in [
                            '',
                            'pending',
                            'approved',
                            'paid',
                            'rejected',
                            'cancelled'
                          ])
                            DropdownMenuItem(
                                value: s,
                                child: AppText(s.isEmpty ? 'All statuses' : s))
                        ],
                        onChanged: (v) => setState(() => status = v!))),
                OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDateRange: range);
                      if (picked != null) setState(() => range = picked);
                    },
                    icon: const Icon(Icons.date_range),
                    label: AppText(range == null
                        ? 'Date range'
                        : '${range!.start.toString().substring(0, 10)} – ${range!.end.toString().substring(0, 10)}')),
                TextButton(
                    onPressed: () => setState(() {
                          search.clear();
                          member = '';
                          category = '';
                          status = '';
                          range = null;
                        }),
                    child: const AppText('Clear filters')),
                TextButton(
                    onPressed: () => setState(() {
                          final n = DateTime.now();
                          range = DateTimeRange(
                              start: DateTime(n.year, n.month),
                              end: DateTime(n.year, n.month + 1, 0));
                        }),
                    child: const AppText('This month')),
              ]),
              const SizedBox(height: 20),
              AppText(
                  'Confirmed approved/paid total: ${money(total / 100, currency: widget.state.currency)}',
                  style: Theme.of(context).textTheme.titleLarge),
              const AppText(
                  'Pending, rejected and cancelled requests are excluded from category spending. The list and exports include exactly your filtered records.'),
              for (final c in totals.entries) ...[
                const SizedBox(height: 10),
                AppText(
                    '${c.key} · ${money(c.value / 100, currency: widget.state.currency)}'),
                LinearProgressIndicator(
                    value: total == 0 ? 0 : c.value / total,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5))
              ],
              const SizedBox(height: 20),
              Wrap(spacing: 12, children: [
                FilledButton.icon(
                    onPressed: busy ? null : () => export(false),
                    icon: const Icon(Icons.table_view),
                    label: const AppText('Export CSV')),
                OutlinedButton.icon(
                    onPressed: busy ? null : () => export(true),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const AppText('Export PDF'))
              ]),
              const Divider(),
              AppText('${rows.length} expenses · newest first'),
              if (rows.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: AppText(
                        'No matching expenses. Clear filters or add your first expense.')),
              for (final e in rows)
                Card(
                    child: ListTile(
                        title: AppText(e.title),
                        subtitle: AppText(
                            '${widget.state.memberName(e.requesterId)} · ${e.category}\n${expenseDate(e.createdAt)} · ${e.cancelled ? 'cancelled' : e.status.name}'),
                        isThreeLine: true,
                        trailing: AppText(
                            money(e.amount, currency: widget.state.currency)),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => ExpenseDetailsScreen(
                                    state: widget.state, id: e.id))))),
            ]));
      });
}
