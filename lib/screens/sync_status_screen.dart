import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../offline/auto_sync.dart';
import '../offline/secure_book.dart';
import 'sync_screen.dart';

class SyncStatusScreen extends StatelessWidget {
  const SyncStatusScreen({super.key, required this.state, this.auto});
  final FlaitState state;
  final AutoSync? auto;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([state, if (auto != null) auto!]),
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const AppText('Sync status')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            ListTile(
                leading: const Icon(Icons.sync),
                title: AppText(auto?.status ?? 'Saved locally'),
                subtitle: AppText(
                    'Last completed exchange: ${state.lastSync ?? 'never'}\n${state.queuedCount} changes waiting for owner confirmation')),
            const AppText(
                'Keep both apps open online. Only the current owner device finalizes proposals. No server queue exists: changes wait safely on devices when the owner or a flatmate is offline. A green relay connection alone does not mean another device is online.'),
            for (final m in state.members
                .where((m) => m.active && m.id != state.currentMemberId))
              ListTile(
                  title: AppText(m.name),
                  subtitle: AppText(
                      'Last completed sync with this device: ${asMap(state.preferences['peerSync'] ?? {})[m.id] ?? 'not yet'}${auto?.peerSeen[m.id] != null ? '\nLast seen online: ${auto!.peerSeen[m.id]!.toLocal()}' : ''}')),
            const Divider(),
            const AppText('Waiting operations',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (state.proposals.isEmpty) const AppText('No queued changes.'),
            for (final p in state.proposals)
              ListTile(
                  title: AppText(
                      '${asMap(p['body'])['kind']} · ${state.memberName(asMap(p['body'])['author'] as String)}'),
                  subtitle:
                      AppText('${asMap(p['body'])['at']} · waiting for owner')),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => SyncScreen(state: state))),
                icon: const Icon(Icons.person_add_alt),
                label: const AppText('First pairing / manual recovery')),
          ])));
}
