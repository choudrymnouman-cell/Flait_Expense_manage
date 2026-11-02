import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';

class MemberManagementScreen extends StatelessWidget {
  const MemberManagementScreen({super.key, required this.state});
  final FlaitState state;
  Future<void> change(BuildContext context, String title, String detail,
      Future<void> Function() action) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
                title: AppText(title),
                content: AppText(detail),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const AppText('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const AppText('Confirm'))
                ]));
    if (ok != true) return;
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: AppText('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const AppText('Membership & owner recovery')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            const AppText(
                'Revoking a device blocks future operations and future sync from that identity. It cannot remotely erase previously shared records. Resolve pending claims and settle a member’s balance before removal.'),
            if (!state.isOwner && state.currentMember.active)
              OutlinedButton(
                  onPressed: () => change(
                      context,
                      'Request to leave',
                      'The owner will review your request. Pending claims and balances must be resolved before access is revoked.',
                      state.requestLeave),
                  child: const AppText('Request to leave flat')),
            for (final m in state.members)
              Card(
                  child: ListTile(
                      title: AppText(m.name),
                      subtitle: AppText(
                          '${m.id == state.book!.owner ? 'Owner' : m.role.name} · ${m.active ? 'active' : 'revoked'}${state.view!.leaveRequests.contains(m.id) ? ' · leave requested' : ''}'),
                      trailing: state.isOwner && m.id != state.currentMemberId
                          ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'transfer') {
                                  change(
                                      context,
                                      'Offer owner transfer',
                                      '${m.name} must accept on their own device. Keep the current owner online until acceptance syncs. After transfer, only the new owner finalizes the journal.',
                                      () => state.offerOwnership(m.id));
                                } else {
                                  change(
                                      context,
                                      m.active
                                          ? 'Revoke member device'
                                          : 'Reactivate member device',
                                      'Existing copies cannot be erased. A replacement phone should restore its encrypted backup, or pair with a new identity.',
                                      () => state.setMemberActive(
                                          m.id, !m.active));
                                }
                              },
                              itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'active',
                                        child: AppText(m.active
                                            ? 'Revoke device'
                                            : 'Reactivate device')),
                                    if (m.active)
                                      const PopupMenuItem(
                                          value: 'transfer',
                                          child:
                                              AppText('Offer owner transfer'))
                                  ])
                          : null)),
            if (state.view!.transferOffer != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                                'Owner transfer offered to ${state.memberName(state.view!.transferTo!)}'),
                            if (state.view!.transferTo == state.currentMemberId)
                              FilledButton(
                                  onPressed: () => change(
                                      context,
                                      'Accept ownership',
                                      'You will be responsible for finalizing the flat journal after the current owner confirms this acceptance. Export a backup and use only one active owner device.',
                                      state.acceptOwnership),
                                  child: const AppText('Accept owner role')),
                            if (state.isOwner)
                              TextButton(
                                  onPressed: state.cancelTransfer,
                                  child: const AppText('Cancel transfer offer'))
                          ]))),
            const Divider(),
            const AppText('Moving to a new phone',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const AppText(
                '1. Sync with the owner and export an encrypted backup.\n2. Keep its password separately and verify you have the file.\n3. Restore on the new phone’s fresh installation.\n4. Stop using the original owner device.\n5. Sync again and export a fresh backup.\n\nIf a phone is lost without a backup, its device identity cannot be recovered by the server. A lost member can be replaced by a newly paired identity after the owner resolves old balances. A lost owner requires its backup; members cannot bypass the owner signature.'),
          ])));
}
