import 'package:flutter/material.dart';
import '../models/flat_models.dart';
import '../state/app_state.dart';
import '../widgets/flait_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});
  final FlaitState state;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 28), children: [
    const PageHeading(title: 'Settings', subtitle: 'Profile, flat information and demo role selection.'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Current demo profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(state.currentMember.name), subtitle: Text(switch (state.currentMember.role) { MemberRole.treasurer => 'Treasurer', MemberRole.admin => 'Flat admin', MemberRole.member => 'Flatmate' })),
      const Divider(),
      const Text('Switch active member', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final member in state.members)
        RadioListTile<String>(value: member.id, groupValue: state.currentMemberId, title: Text(member.name), subtitle: Text(switch (member.role) { MemberRole.treasurer => 'Treasurer', MemberRole.admin => 'Flat admin', MemberRole.member => 'Member' }), onChanged: (id) { if (id != null) state.switchMember(id); }),
    ])))),
    Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: const Padding(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Flat details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      SizedBox(height: 14),
      _InfoRow(label: 'Flat name', value: 'Flait Demo Flat'),
      _InfoRow(label: 'Currency', value: 'PKR · Pakistani Rupee'),
      _InfoRow(label: 'Approval rule', value: 'Strict majority of eligible flatmates'),
      _InfoRow(label: 'Data storage', value: 'Local in-memory demo'),
    ])))),
    const Padding(padding: EdgeInsets.fromLTRB(22, 18, 22, 0), child: Card(child: Padding(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Before production launch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      SizedBox(height: 10),
      Text('Connect authenticated cloud storage, enforce permissions on the server, protect receipt uploads, and add backups. Demo role switching is for testing only and is not authentication.'),
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
