import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../offline/secure_book.dart';
import '../services/settlement_service.dart';
import '../services/app_preferences.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen(
      {super.key,
      required this.state,
      required this.onSubmitted,
      this.expense});
  final FlaitState state;
  final VoidCallback onSubmitted;
  final ExpenseRequest? expense;
  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController(),
      descriptionController = TextEditingController(),
      amountController = TextEditingController(),
      reason = TextEditingController();
  final weights = <String, TextEditingController>{};
  final selected = <String>{};
  String category = 'Household', mode = 'equal';
  String? receipt;
  bool shareReceipt = false, saving = false;
  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    for (final m in widget.state.members.where((m) => m.active)) {
      selected.add(m.id);
      weights[m.id] = TextEditingController(
          text: e?.shares[m.id] != null
              ? (e!.shares[m.id]! / 100).toStringAsFixed(2)
              : '');
    }
    if (e != null) {
      titleController.text = e.title;
      descriptionController.text = e.description;
      amountController.text = e.amount.toStringAsFixed(2);
      category = e.category;
      mode = e.shares.isEmpty ? 'equal' : 'custom';
      selected
        ..clear()
        ..addAll(e.shares.keys);
      if (selected.isEmpty) selected.addAll(weights.keys);
      receipt = e.receiptReference;
      shareReceipt = receipt != null;
    }
  }

  @override
  void dispose() {
    for (final c in [
      titleController,
      descriptionController,
      amountController,
      reason,
      ...weights.values
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> shares() {
    final n = double.tryParse(amountController.text.trim());
    if (!validMoneyAmount(n)) throw ArgumentError('Enter a valid amount.');
    final total = (n! * 100).round();
    final values = <String, int>{};
    for (final id in selected) {
      final raw =
          mode == 'equal' ? 1.0 : double.tryParse(weights[id]!.text.trim());
      if (raw == null ||
          !raw.isFinite ||
          raw < 0 ||
          (mode == 'custom' &&
              (raw * 100 - (raw * 100).round()).abs() > 0.0001)) {
        throw ArgumentError('Enter valid shares for every selected member.');
      }
      values[id] = mode == 'equal' ? 1 : (raw * 100).round();
    }
    if (mode == 'percentage' &&
        values.values.fold(0, (a, b) => a + b) != 10000) {
      throw ArgumentError('Percentages must total exactly 100%.');
    }
    return allocateShares(total, values, exact: mode == 'custom');
  }

  Future<void> chooseReceipt() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png'],
          withData: true);
      if (picked == null) return;
      final f = picked.files.single;
      if (f.size > 500000 || f.bytes == null) {
        throw StateError('Choose a photo below 500 KB.');
      }
      final encoded = validateReceipt(base64Encode(f.bytes!));
      if (mounted) setState(() => receipt = encoded);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: AppText('$e')));
      }
    }
  }

  Future<void> submit() async {
    if (saving || !(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    try {
      final allocation = shares(), e = widget.expense;
      if (e != null) {
        await widget.state.amendExpense(e,
            title: titleController.text,
            description: descriptionController.text,
            category: category,
            amount: double.parse(amountController.text),
            shares: allocation,
            reason: reason.text);
      } else {
        final id = randomCode();
        await widget.state.submitExpense(
            title: titleController.text,
            description: descriptionController.text,
            category: category,
            amount: double.parse(amountController.text),
            shares: allocation,
            receipt: shareReceipt ? receipt : null,
            requestId: id);
        if (receipt != null && !shareReceipt) {
          await widget.state.saveLocalReceipt(id, receipt!);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: AppText(
              'Saved locally. Paired apps sync automatically when online.')));
      if (e == null) {
        titleController.clear();
        descriptionController.clear();
        amountController.clear();
        setState(() => receipt = null);
      }
      widget.onSubmitted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: AppText('$e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        PageHeading(
            title: widget.expense == null
                ? tr(context, 'New expense request', 'نیا خرچہ')
                : tr(context, 'Correct expense', 'خرچہ درست کریں'),
            subtitle: tr(
                context,
                'Date and time are added automatically when you save.',
                'محفوظ کرتے وقت تاریخ اور وقت خود شامل ہوں گے۔')),
        Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Card(
                        child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Form(
                                key: formKey,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                          controller: titleController,
                                          decoration: InputDecoration(
                                              labelText: tr(
                                                  context,
                                                  'Expense title',
                                                  'خرچے کا عنوان')),
                                          validator: (v) => (v ?? '')
                                                          .trim()
                                                          .length <
                                                      2 ||
                                                  (v ?? '').length > 120
                                              ? 'Enter a title of 2–120 characters.'
                                              : null),
                                      const SizedBox(height: 14),
                                      TextFormField(
                                          controller: amountController,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                              labelText:
                                                  'Amount (${widget.state.currency})'),
                                          validator: (v) => validMoneyAmount(
                                                  double.tryParse(
                                                      (v ?? '').trim()))
                                              ? null
                                              : 'Enter a positive amount with at most 2 decimals.'),
                                      const SizedBox(height: 14),
                                      DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          initialValue: category,
                                          decoration: InputDecoration(
                                              labelText: tr(
                                                  context, 'Category', 'قسم')),
                                          items: {
                                            'Household',
                                            'Groceries',
                                            'Utilities',
                                            'Maintenance',
                                            'Internet',
                                            'Rent',
                                            'Other',
                                            category
                                          }
                                              .map((v) => DropdownMenuItem(
                                                  value: v, child: AppText(v)))
                                              .toList(),
                                          onChanged: (v) =>
                                              setState(() => category = v!)),
                                      const SizedBox(height: 14),
                                      TextFormField(
                                          controller: descriptionController,
                                          minLines: 2,
                                          maxLines: 4,
                                          maxLength: 4000,
                                          decoration: InputDecoration(
                                              labelText: tr(context,
                                                  'Description', 'تفصیل'))),
                                      const Divider(),
                                      AppText(
                                          tr(context, 'Split between members',
                                              'ارکان میں تقسیم'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          initialValue: mode,
                                          decoration: const InputDecoration(
                                              labelText: 'Split method'),
                                          items: const [
                                            DropdownMenuItem(
                                                value: 'equal',
                                                child: AppText('Equal shares')),
                                            DropdownMenuItem(
                                                value: 'percentage',
                                                child: AppText(
                                                    'Percentage (total 100%)')),
                                            DropdownMenuItem(
                                                value: 'custom',
                                                child:
                                                    AppText('Custom amounts'))
                                          ],
                                          onChanged: (v) =>
                                              setState(() => mode = v!)),
                                      for (final m in widget.state.members
                                          .where((m) => m.active))
                                        Row(children: [
                                          Expanded(
                                              child: CheckboxListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: AppText(m.name),
                                                  value:
                                                      selected.contains(m.id),
                                                  onChanged: (v) =>
                                                      setState(() {
                                                        if (v == true) {
                                                          selected.add(m.id);
                                                        } else {
                                                          selected.remove(m.id);
                                                        }
                                                      }))),
                                          if (mode != 'equal' &&
                                              selected.contains(m.id))
                                            SizedBox(
                                                width: 110,
                                                child: TextField(
                                                    controller: weights[m.id],
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true),
                                                    decoration: InputDecoration(
                                                        labelText:
                                                            mode == 'percentage'
                                                                ? '%'
                                                                : widget.state
                                                                    .currency)))
                                        ]),
                                      const AppText(
                                          'Rounding is exact to the smallest currency unit. Only approved claims affect shared cost allocation.'),
                                      const Divider(),
                                      if (widget.expense == null) ...[
                                        OutlinedButton.icon(
                                            onPressed:
                                                saving ? null : chooseReceipt,
                                            icon: const Icon(Icons.attach_file),
                                            label: AppText(receipt == null
                                                ? 'Attach receipt (JPEG/PNG, 500 KB max)'
                                                : 'Replace receipt')),
                                        if (receipt != null) ...[
                                          Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Image.memory(
                                                  base64Decode(receipt!),
                                                  height: 140)),
                                          SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              value: shareReceipt,
                                              title: const AppText(
                                                  'Share receipt with flatmates'),
                                              subtitle: const AppText(
                                                  'Off: stays only on this device and in your encrypted backup. On: included in encrypted shared history; cannot be recalled from other devices.'),
                                              onChanged: (v) => setState(
                                                  () => shareReceipt = v))
                                        ],
                                      ],
                                      if (widget.expense != null) ...[
                                        const AppText(
                                            'A correction resets all votes and keeps the previous values in history.'),
                                        TextFormField(
                                            controller: reason,
                                            maxLength: 300,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'Reason for correction'),
                                            validator: (v) =>
                                                (v ?? '').trim().length < 3
                                                    ? 'Enter a reason.'
                                                    : null)
                                      ],
                                      const SizedBox(height: 18),
                                      SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                              onPressed: saving ? null : submit,
                                              icon: const Icon(
                                                  Icons.save_outlined),
                                              label: AppText(saving
                                                  ? 'Saving…'
                                                  : widget.expense == null
                                                      ? tr(
                                                          context,
                                                          'Submit for approval',
                                                          'منظوری کے لیے بھیجیں')
                                                      : 'Save correction'))),
                                      const SizedBox(height: 12),
                                      const AppText(
                                          'Submitting a request does not spend pool money. Reimbursement and personal settlements are recorded separately.'),
                                    ])))))))
      ]);
}
