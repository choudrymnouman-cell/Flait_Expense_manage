import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});
  final FlaitState state;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 28), children: [
    PageHeading(title: 'Settings', subtitle: 'Your account, flat details and access.'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Signed-in profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(state.currentMember.name), subtitle: Text(Supabase.instance.client.auth.currentUser?.email ?? 'Authenticated account')),
      const Divider(),
      Text('Role: ${switch (state.currentMember.role) { MemberRole.treasurer => 'Treasurer', MemberRole.admin => 'Flat admin', MemberRole.member => 'Flatmate' }}'),
      const SizedBox(height: 10),
      const Text('Your role is controlled by the flat membership record, not by a demo switch.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          await Supabase.instance.client.auth.signOut();
        },
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ])))),
    Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Flat details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 14),
      _InfoRow(label: 'Flat name', value: state.flatName),
      _InfoRow(label: 'Currency', value: '${state.currency}'),
      const _InfoRow(label: 'Approval rule', value: 'Strict majority of eligible flatmates'),
      const _InfoRow(label: 'Data storage', value: 'Supabase cloud database'),
      const _InfoRow(label: 'Authentication', value: 'Supabase Auth'),
    ])))),
    const Padding(padding: EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Privacy and access', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      SizedBox(height: 10),
      Text('Flat data is protected by database row-level security. Only active flat members can read that flat’s expenses and ledger. Votes are tied to the signed-in account.'),
    ])))),
  ]);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 125, child: Text(label, style: const TextStyle(color: Colors.blueGrey))),
    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
  ]));
}
