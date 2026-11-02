import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/app_state.dart';

Future<void> showLegacyImport(BuildContext context, FlaitState state) =>
    showDialog<void>(
        context: context, builder: (_) => _LegacyImport(state: state));

class _LegacyImport extends StatefulWidget {
  const _LegacyImport({required this.state});
  final FlaitState state;
  @override
  State<_LegacyImport> createState() => _LegacyImportState();
}

class _LegacyImportState extends State<_LegacyImport> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> import() async {
    setState(() {
      busy = true;
      message = null;
    });
    final client = SupabaseClient('https://rrkzsrotgxqvrllilzbj.supabase.co',
        'sb_publishable_hEewjesFCyCW7IYAeJCo6A_WLizCGGQ');
    try {
      final user = (await client.auth.signInWithPassword(
              email: email.text.trim(), password: password.text))
          .user;
      if (user == null) throw StateError('Sign in failed.');
      final memberships = await client
          .from('flat_members')
          .select()
          .eq('user_id', user.id)
          .eq('role', 'admin')
          .eq('active', true);
      if (memberships.length != 1) {
        throw StateError(
            'This importer requires exactly one flat that you administer.');
      }
      final flatId = memberships.first['flat_id'] as String;
      final rows = <Map<String, dynamic>>[];
      var opening = 0;
      for (final table in [
        'flats',
        'flat_members',
        'expenses',
        'expense_votes',
        'ledger_entries'
      ]) {
        final data = await client
            .from(table)
            .select()
            .eq(table == 'flats' ? 'id' : 'flat_id', flatId)
            .limit(10001);
        if (data.length > 10000) {
          throw StateError('Archive is too large for this importer.');
        }
        for (final row in data) {
          rows.add({'table': table, 'record': row});
          if (table == 'ledger_entries') {
            final cents = ((row['amount'] as num) * 100).round();
            opening += ['contribution', 'repayment'].contains(row['entry_type'])
                ? cents
                : -cents;
          }
        }
      }
      await widget.state
          .operation('legacy', {'rows': rows, 'openingCents': opening});
      if (mounted) {
        setState(() => message =
            'Archive saved locally. Old requests remain read-only; any positive pool balance was carried forward. Export an encrypted backup next. The original cloud records have not been deleted.');
      }
    } catch (e) {
      if (mounted) setState(() => message = 'Import failed: $e');
    } finally {
      try {
        await client.auth.signOut();
      } catch (_) {}
      await client.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const AppText('Import previous cloud records'),
        content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppText(
                  'Optional, one-time online import using your OLD Flait account. This downloads the flat you administer to this device. It does not upload local expenses or delete the source. Old history stays a read-only archive.'),
              const SizedBox(height: 12),
              TextField(
                  controller: email,
                  enabled: !busy,
                  decoration:
                      const InputDecoration(labelText: 'Old Flait email')),
              const SizedBox(height: 12),
              TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Old Flait password')),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppText(message!)),
            ]))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const AppText('Close')),
          FilledButton(
              onPressed: busy ? null : import,
              child: AppText(busy ? 'Importing…' : 'Download to this device'))
        ],
      ));
}
