import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen({super.key, required this.state, required this.onSubmitted});
  final FlaitState state;
  final VoidCallback onSubmitted;

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final amountController = TextEditingController();
  String category = 'Household';
  bool saving = false;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    amountController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving || !(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    try {
      await widget.state.submitExpense(
        title: titleController.text,
        description: descriptionController.text,
        category: category,
        amount: double.parse(amountController.text.trim()),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request submitted for flatmate approval.')));
      titleController.clear();
      descriptionController.clear();
      amountController.clear();
      widget.onSubmitted();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''))));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 28), children: [
    const PageHeading(title: 'New expense request', subtitle: 'Submit a purchase made with your personal cash for review.'),
    Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Card(
        child: Padding(padding: const EdgeInsets.all(22), child: Form(key: formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Purchase details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          TextFormField(controller: titleController, decoration: const InputDecoration(labelText: 'Expense title', hintText: 'e.g. Kitchen cleaning supplies'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title.' : null, textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          TextFormField(controller: amountController, decoration: const InputDecoration(labelText: 'Amount (PKR)', prefixText: 'Rs. '), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse((v ?? '').trim()); return n == null || !n.isFinite || n <= 0 ? 'Enter an amount greater than zero.' : null; }, textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Category'), items: const ['Household', 'Groceries', 'Utilities', 'Maintenance', 'Internet', 'Other'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => category = v ?? 'Other')),
          const SizedBox(height: 14),
          TextFormField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Description', hintText: 'What was purchased and why?'), minLines: 3, maxLines: 5),
          const SizedBox(height: 18),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF3F5FB), borderRadius: BorderRadius.circular(12)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: Color(0xFF3659C9)),
            SizedBox(width: 10),
            Expanded(child: Text('Submitting a request does not take money from the pool. If approved, the treasurer must record the reimbursement payment separately.')),
          ])),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving ? null : submit, icon: const Icon(Icons.send_outlined), label: Text(saving ? 'Submitting…' : 'Submit for approval'))),
        ]))),
      ),
    ))),
  ]);
}
