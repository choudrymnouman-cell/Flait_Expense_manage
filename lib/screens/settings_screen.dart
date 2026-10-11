import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      const Text('Your permissions come from the flat membership stored in Supabase.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () async {
        await Supabase.instance.client.auth.signOut();
      }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
    ])))),
    Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Flat details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 14),
      _InfoRow(label: 'Flat name', value: state.flatName),
      _InfoRow(label: 'Currency', value: state.currency),
      const _InfoRow(label: 'Approval rule', value: 'Strict majority of eligible flatmates'),
      const _InfoRow(label: 'Data storage', value: 'Supabase cloud database'),
      const _InfoRow(label: 'Authentication', value: 'Supabase Auth'),
    ])))),
    if (state.currentMember.role == MemberRole.admin)
      Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Flatmate roles', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        const Text('As flat admin, assign the treasurer role to a trusted flatmate.'),
        const SizedBox(height: 8),
        for (final member in state.members.where((m) => m.id != state.currentMemberId))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(member.name),
            subtitle: Text(member.id),
            trailing: DropdownButton<MemberRole>(
              value: member.role == MemberRole.admin ? MemberRole.member : member.role,
              items: const [
                DropdownMenuItem(value: MemberRole.member, child: Text('Member')),
                DropdownMenuItem(value: MemberRole.treasurer, child: Text('Treasurer')),
              ],
              onChanged: (role) async {
                if (role == null) return;
                try {
                  await state.setMemberRole(member.id, role);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))));
                }
              },
            ),
          ),
      ])))),
    Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Invite a flatmate', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 8),
      const Text('Create a one-time invitation code. It expires after 7 days and can be used by one signed-in roommate.'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: state.currentMember.role == MemberRole.admin || state.currentMember.role == MemberRole.treasurer
          ? () => _createInvite(context) : null,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Create invitation code'),
      ),
    ])))),
    const Padding(padding: EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Privacy and access', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      SizedBox(height: 10),
      Text('Flat data is protected by database row-level security. Only active flat members can read that flat’s expenses and ledger. Votes are tied to the signed-in account.'),
    ])))),
  ]);

  Future<void> _createInvite(BuildContext context) async {
    try {
      final code = await state.createInvite();
      await Clipboard.setData(ClipboardData(text: code));
      if (!context.mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Invitation created'),
        content: SelectableText('Share this code with one flatmate. It expires in 7 days and has been copied to your clipboard:\n\n$code'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))));
    }
  }
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
