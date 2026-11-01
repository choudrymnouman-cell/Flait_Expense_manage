import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../offline/secure_book.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';
import 'backup_dialog.dart';
import 'sync_screen.dart';
import 'legacy_import_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});
  final FlaitState state;
  Widget card(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: Card(
          child: Padding(padding: const EdgeInsets.all(18), child: child)));
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        const PageHeading(
            title: 'Settings',
            subtitle: 'Local identity, sharing and backups.'),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(state.currentMember.name,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(
              '${state.flatName} · ${state.currency} · ${state.isOwner ? 'Flat owner' : state.currentMember.role.name}'),
          const SizedBox(height: 10),
          SelectableText('Device: ${state.currentMemberId.substring(0, 12)}…'),
          const Text(
              'This identity lives on this device. No email login is needed. Use only one active device for the owner identity.'),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Internet sharing & members',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
              'To add a member, the owner creates a sync code. The flatmate enters it on their device; the owner then confirms admission. Both stay online until Sync complete.'),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => SyncScreen(state: state))),
              icon: const Icon(Icons.sync),
              label: const Text('Open internet sync')),
          Text(
              '${state.queuedCount} changes waiting for owner confirmation. Last completed exchange: ${state.lastSync ?? 'never'}'),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Flatmates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          for (final member in state.members)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(member.name),
                subtitle: Text(member.id == state.book!.owner
                    ? 'Owner · finalizes shared records'
                    : member.role.name),
                trailing: state.isOwner && member.id != state.currentMemberId
                    ? DropdownButton<MemberRole>(
                        value: member.role,
                        items: const [
                          DropdownMenuItem(
                              value: MemberRole.member, child: Text('Member')),
                          DropdownMenuItem(
                              value: MemberRole.treasurer,
                              child: Text('Treasurer'))
                        ],
                        onChanged: (role) async {
                          if (role == null) return;
                          try {
                            await state.setMemberRole(member.id, role);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        })
                    : null),
          const Text(
              'Treasurers can queue money entries offline. The owner validates them before they change the confirmed shared balance.'),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Device backup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
              'Keep a password-encrypted backup outside this device. Uninstalling the app or clearing browser storage can erase the local copy. Local app storage itself relies on your device/browser protection.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () => showBackupDialog(context, state),
              icon: const Icon(Icons.save_alt),
              label: const Text('Export encrypted backup')),
        ])),
        if (state.proposals.isNotEmpty)
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Waiting for owner confirmation',
                style: TextStyle(fontWeight: FontWeight.w800)),
            for (final p in state.proposals)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${asMap(p['body'])['kind']} · ${state.memberName(asMap(p['body'])['author'] as String)}'),
                  subtitle: Text(
                      '${asMap(asMap(p['body'])['data'])['title'] ?? asMap(asMap(p['body'])['data'])['description'] ?? 'Saved locally; not yet confirmed'}')),
          ])),
        if (state.isOwner && state.view!.legacyArchive.isEmpty)
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Previous online version',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const Text(
                'Your old cloud data is separate. Import it before requesting cloud deletion.'),
            TextButton(
                onPressed: () => showLegacyImport(context, state),
                child: const Text('Import previous cloud records')),
          ])),
        if (state.view!.legacyArchive.isNotEmpty)
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Imported cloud archive · read-only',
                style: TextStyle(fontWeight: FontWeight.w800)),
            for (final row in state.view!.legacyArchive.where((r) =>
                ['expenses', 'ledger_entries'].contains(r['table']))) ...[
              const Divider(),
              Text(
                  '${row['table']}: ${asMap(row['record'])['title'] ?? asMap(row['record'])['description'] ?? ''}'),
              Text(
                  '${asMap(row['record'])['amount'] ?? ''} · ${asMap(row['record'])['status'] ?? asMap(row['record'])['entry_type'] ?? ''}'),
            ],
          ])),
        if (state.view!.rejected.isNotEmpty)
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Owner review results',
                style: TextStyle(fontWeight: FontWeight.w800)),
            for (final entry in state.view!.rejected.entries)
              Text('${entry.key.substring(0, 8)}: ${entry.value}'),
          ])),
        card(const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 10),
              Text(
                  'Normal use makes no database requests. Sharing starts only when you open sync; old cloud records are downloaded only when you explicitly import them. Live sharing uses encrypted client broadcasts without database storage or replay. The relay can still see connection metadata. This hosted web page also has its existing ChatGPT access gate.'),
            ])),
      ]);
}
