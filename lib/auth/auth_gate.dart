import '../widgets/flait_logo.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../screens/sync_screen.dart';
import '../screens/backup_dialog.dart';

class OfflineSetupScreen extends StatefulWidget {
  const OfflineSetupScreen({super.key, required this.state});
  final FlaitState state;
  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen> {
  final name = TextEditingController(), flat = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name.text = widget.state.identity?.name ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    flat.dispose();
    super.dispose();
  }

  Future<void> proceed(bool create) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.prepareIdentity(name.text);
      if (create) {
        await widget.state.createFlat(flat.text);
      } else if (mounted) {
        await Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => SyncScreen(state: widget.state, joinCode: '')));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const FlaitLogo(size: 52),
                              const SizedBox(height: 12),
                              const Text('Flait',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900)),
                              const Text(
                                  'Your flat. Your devices. Works offline.',
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 24),
                              TextField(
                                  controller: name,
                                  enabled: !busy,
                                  decoration: const InputDecoration(
                                      labelText: 'Your name')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: flat,
                                  enabled: !busy,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Flat name (to create a flat)')),
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(error!,
                                        style: const TextStyle(
                                            color: Colors.red))),
                              const SizedBox(height: 20),
                              FilledButton(
                                  onPressed: busy ? null : () => proceed(true),
                                  child:
                                      const Text('Create flat on this device')),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: busy ? null : () => proceed(false),
                                  child: const Text(
                                      'Join a flat using an internet sync code')),
                              TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => showBackupDialog(
                                          context, widget.state, restore: true),
                                  child:
                                      const Text('Restore encrypted backup')),
                              const SizedBox(height: 12),
                              const Text(
                                  'No email or cloud account required. Creating a flat works offline. To join, both devices must be online. Save a backup: clearing app/browser storage removes your local copy.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.blueGrey)),
                            ]))),
              ))));
}
