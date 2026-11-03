import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../state/app_state.dart';
import '../offline/secure_book.dart';
import '../services/app_preferences.dart';
import 'backup_dialog.dart';
import 'privacy_screen.dart';

class ProPreferencesScreen extends StatelessWidget {
  const ProPreferencesScreen({super.key, required this.state});
  final FlaitState state;
  Future<void> configurePin(BuildContext context) async {
    final old = TextEditingController(),
        first = TextEditingController(),
        second = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (d) => StatefulBuilder(
            builder: (d, set) => AlertDialog(
                    title: AppText(state.preferences['pin'] == null
                        ? 'Enable app lock'
                        : 'Change / remove app lock'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (state.preferences['pin'] != null)
                        TextField(
                            controller: old,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Current PIN')),
                      TextField(
                          controller: first,
                          obscureText: true,
                          maxLength: 12,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'New PIN (6–12 digits)')),
                      TextField(
                          controller: second,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Confirm new PIN')),
                      if (error != null) AppText(error!),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: busy ? null : () => Navigator.pop(d),
                          child: const AppText('Cancel')),
                      if (state.preferences['pin'] != null)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    set(() => busy = true);
                                    try {
                                      if (!await PinSecurity.check(old.text,
                                          asMap(state.preferences['pin']))) {
                                        throw StateError(
                                            'Current PIN is incorrect.');
                                      }
                                      await state.setPreference(
                                          'biometric', false);
                                      await state.setPreference('pin', null);
                                      if (d.mounted) Navigator.pop(d);
                                    } catch (e) {
                                      set(() {
                                        busy = false;
                                        error = '$e';
                                      });
                                    }
                                  },
                            child: const AppText('Remove lock')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  set(() => busy = true);
                                  try {
                                    if (state.preferences['pin'] != null &&
                                        !await PinSecurity.check(old.text,
                                            asMap(state.preferences['pin']))) {
                                      throw StateError(
                                          'Current PIN is incorrect.');
                                    }
                                    if (first.text != second.text) {
                                      throw StateError('New PINs must match.');
                                    }
                                    final verifier =
                                        await PinSecurity.create(first.text);
                                    await state.setPreference('pin', verifier);
                                    if (d.mounted) Navigator.pop(d);
                                  } catch (e) {
                                    set(() {
                                      busy = false;
                                      error = '$e';
                                    });
                                  }
                                },
                          child: const AppText('Save PIN')),
                    ])));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => Scaffold(
          appBar: AppBar(
              title: AppText(
                  tr(context, 'Preferences & protection', 'ترجیحات اور تحفظ'))),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            SwitchListTile(
                title: AppText(tr(context, 'Dark mode', 'ڈارک موڈ')),
                value: state.preferences['dark'] == true,
                onChanged: (v) => state.setPreference('dark', v)),
            ListTile(
                title: AppText(tr(context, 'Language', 'زبان')),
                trailing: DropdownButton<String>(
                    value: state.preferences['language'] as String? ?? 'en',
                    items: const [
                      DropdownMenuItem(value: 'en', child: AppText('English')),
                      DropdownMenuItem(value: 'ur', child: AppText('اردو'))
                    ],
                    onChanged: (v) => state.setPreference('language', v))),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const AppText('App PIN lock'),
                subtitle: AppText(state.preferences['pin'] == null
                    ? 'Off'
                    : 'On · locks when the app goes into the background'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configurePin(context)),
            if (!kIsWeb)
              SwitchListTile(
                  title: const AppText('Fingerprint / device passcode'),
                  subtitle: const AppText(
                      'Requires an app PIN and device authentication. Biometric data stays with Android.'),
                  value: state.preferences['biometric'] == true,
                  onChanged: state.preferences['pin'] == null
                      ? null
                      : (v) async {
                          try {
                            final auth = LocalAuthentication();
                            if (!await auth.authenticate(
                                localizedReason:
                                    'Confirm Flait lock preference',
                                options: const AuthenticationOptions(
                                    biometricOnly: false, stickyAuth: true))) {
                              return;
                            }
                            await state.setPreference('biometric', v);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: AppText(
                                          'Set up a device screen lock or biometric authentication first.')));
                            }
                          }
                        }),
            ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: AppText(state.storage.encryptedAtRest
                    ? 'Local database encrypted'
                    : 'Browser-local storage'),
                subtitle: AppText(state.storage.encryptedAtRest
                    ? 'AES-256-GCM; random device key protected by Android secure storage. App lock protects access through this app.'
                    : 'Browser storage relies on browser/device protection. An app PIN is an interface lock; use encrypted exports and a protected device.')),
            const Divider(),
            ListTile(
                leading: Icon(state.backupDue
                    ? Icons.warning_amber
                    : Icons.backup_outlined),
                title: AppText(state.backupDue
                    ? 'Backup reminder: export a fresh backup'
                    : 'Backup reminder: up to date'),
                subtitle: AppText(
                    'Last exported: ${state.preferences['backupAt'] ?? 'never'}\nA weekly reminder appears in the app. No automatic cloud upload.'),
                onTap: () => showBackupDialog(context, state)),
            FilledButton.icon(
                onPressed: () => showBackupDialog(context, state),
                icon: const Icon(Icons.save_alt),
                label: const AppText('Export encrypted backup')),
            const Divider(),
            ListTile(
                title: const AppText('Privacy policy & support'),
                leading: const Icon(Icons.policy_outlined),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const PrivacyScreen()))),
            const ListTile(
                title: AppText('Flait 3.0.0'),
                subtitle: AppText(
                    'Offline shared expenses · No advertising SDK · No bank transfers')),
          ])));
}
