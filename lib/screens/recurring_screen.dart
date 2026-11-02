import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import '../offline/secure_book.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key, required this.state});
  final FlaitState state;
  Future<void> add(BuildContext context) async {
    final title = TextEditingController(),
        amount = TextEditingController(),
        day = TextEditingController(text: '1');
    final value = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (d) => AlertDialog(
                title: const AppText('Monthly bill template'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: title,
                      decoration:
                          const InputDecoration(labelText: 'Bill title')),
                  TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount')),
                  TextField(
                      controller: day,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Due day (1–28)')),
                  const AppText(
                      'Templates stay on this device. Submit each monthly request after checking its amount. New requests split equally between active members.')
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: const AppText('Cancel')),
                  FilledButton(
                      onPressed: () {
                        final n = double.tryParse(amount.text),
                            due = int.tryParse(day.text);
                        if (title.text.trim().length < 2 ||
                            !validMoneyAmount(n) ||
                            due == null ||
                            due < 1 ||
                            due > 28) {
                          ScaffoldMessenger.of(d).showSnackBar(const SnackBar(
                              content: AppText(
                                  'Enter title, valid amount and due day 1–28.')));
                          return;
                        }
                        Navigator.pop(d, {
                          'id': randomCode(),
                          'title': title.text.trim(),
                          'cents': (n! * 100).round(),
                          'day': due,
                          'category': 'Utilities'
                        });
                      },
                      child: const AppText('Save'))
                ]));
    if (value != null) await state.saveRecurring(value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const AppText('Recurring monthly bills')),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: () => add(context),
              icon: const Icon(Icons.add),
              label: const AppText('Add bill')),
          body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                const AppText(
                    'Review → submit this month → normal approval → record reimbursement. No automatic bank payments. Duplicate monthly submissions are blocked.'),
                if (asMaps(state.preferences['recurring'] ?? []).isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(30),
                      child: AppText(
                          'Add rent, electricity or internet as a monthly template.')),
                for (final b in asMaps(state.preferences['recurring'] ?? []))
                  Card(
                      child: ListTile(
                          title: AppText(b['title'] as String),
                          subtitle: AppText(
                              '${money((b['cents'] as int) / 100, currency: state.currency)} · due day ${b['day']}${DateTime.now().day >= (b['day'] as int) ? ' · due this month' : ''}'),
                          trailing: Wrap(children: [
                            IconButton(
                                tooltip: 'Submit this month',
                                icon: const Icon(Icons.add_task),
                                onPressed: () async {
                                  try {
                                    await state.submitRecurring(
                                        b, DateTime.now());
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: AppText(
                                                  'Monthly request saved.')));
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: AppText('$e')));
                                    }
                                  }
                                }),
                            IconButton(
                                tooltip: 'Remove local template',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    state.removeRecurring(b['id'] as String))
                          ]))),
              ])));
}
