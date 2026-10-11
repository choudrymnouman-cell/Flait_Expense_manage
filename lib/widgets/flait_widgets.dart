import 'package:flutter/material.dart';
import '../models/flat_models.dart';

String money(double value) => 'Rs. ${value.toStringAsFixed(0)}';

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.blueGrey)),
      ])),
      if (trailing != null) trailing!,
    ]),
  );
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.label, required this.value, required this.icon, this.emphasized = false});
  final String label;
  final String value;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: emphasized ? const Color(0xFF3659C9) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: emphasized ? const Color(0xFF3659C9) : const Color(0xFFE7EAF2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: emphasized ? Colors.white70 : const Color(0xFF3659C9)),
      const SizedBox(height: 18),
      Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: emphasized ? Colors.white : const Color(0xFF1E2638))),
      const SizedBox(height: 5),
      Text(label, style: TextStyle(color: emphasized ? Colors.white70 : Colors.blueGrey)),
    ]),
  );
}

class ExpenseStatusChip extends StatelessWidget {
  const ExpenseStatusChip({super.key, required this.status});
  final ExpenseStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ExpenseStatus.pending => ('Pending', const Color(0xFFB7791F)),
      ExpenseStatus.approved => ('Approved · unpaid', const Color(0xFF287A53)),
      ExpenseStatus.rejected => ('Rejected', const Color(0xFFB33A3A)),
      ExpenseStatus.paid => ('Paid', const Color(0xFF3659C9)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(30)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
      if (trailing != null) trailing!,
    ]),
  );
}
