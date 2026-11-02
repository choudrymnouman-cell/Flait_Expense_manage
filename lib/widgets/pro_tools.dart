import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../offline/auto_sync.dart';
import '../services/app_preferences.dart';
import '../screens/reports_screen.dart';
import '../screens/dues_screen.dart';
import '../screens/recurring_screen.dart';
import '../screens/member_management_screen.dart';
import '../screens/pro_preferences_screen.dart';
import '../screens/sync_status_screen.dart';
import '../screens/backup_dialog.dart';
import '../screens/guide_screen.dart';

class ProTools extends StatelessWidget {
  const ProTools({super.key, required this.state, this.auto});
  final FlaitState state;
  final AutoSync? auto;
  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    return Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (state.backupDue)
            Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: Text(tr(
                        context,
                        'Protect your records: export a backup',
                        'اپنے ریکارڈ کا بیک اپ محفوظ کریں')),
                    subtitle: Text(tr(
                        context,
                        'No cloud recovery. Keep the backup password separately.',
                        'کلاؤڈ ریکوری موجود نہیں۔ پاس ورڈ الگ محفوظ رکھیں۔')),
                    onTap: () => showBackupDialog(context, state))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => open(const GuideScreen()),
                icon: const Icon(Icons.help_outline),
                label: AppText(
                    tr(context, 'How Flait works', 'فلیٹ کیسے کام کرتا ہے؟'))),
            OutlinedButton.icon(
                onPressed: () => open(ReportsScreen(state: state)),
                icon: const Icon(Icons.analytics_outlined),
                label:
                    Text(tr(context, 'Reports & search', 'رپورٹس اور تلاش'))),
            OutlinedButton.icon(
                onPressed: () => open(DuesScreen(state: state)),
                icon: const Icon(Icons.balance),
                label: Text(tr(context, 'Member dues', 'ارکان کے بقایاجات'))),
            OutlinedButton.icon(
                onPressed: () => open(RecurringScreen(state: state)),
                icon: const Icon(Icons.event_repeat),
                label: Text(tr(context, 'Monthly bills', 'ماہانہ بل'))),
            OutlinedButton.icon(
                onPressed: () => open(MemberManagementScreen(state: state)),
                icon: const Icon(Icons.groups_outlined),
                label: Text(
                    tr(context, 'Members & recovery', 'ارکان اور ریکوری'))),
            OutlinedButton.icon(
                onPressed: () =>
                    open(SyncStatusScreen(state: state, auto: auto)),
                icon: const Icon(Icons.sync),
                label: Text(tr(context, 'Sync status', 'سنک کی صورتحال'))),
            OutlinedButton.icon(
                onPressed: () => open(ProPreferencesScreen(state: state)),
                icon: const Icon(Icons.tune),
                label: Text(tr(
                    context, 'Preferences & protection', 'ترجیحات اور تحفظ'))),
          ]),
        ]));
  }
}
