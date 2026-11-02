import '../services/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../offline/live_sync.dart';
import '../state/app_state.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.state, this.joinCode});
  final FlaitState state;
  final String? joinCode;
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final code = TextEditingController();
  SyncSession? session;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    code.text = widget.joinCode ?? '';
  }

  @override
  void dispose() {
    code.dispose();
    session?.dispose();
    super.dispose();
  }

  Future<void> start(bool host) async {
    setState(() {
      busy = true;
      error = null;
    });
    final next = SyncSession(widget.state, host: host);
    setState(() => session = next);
    try {
      await next.start(invite: host ? null : code.text);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const AppText('Internet sync')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.devices_rounded,
                            size: 48, color: Color(0xFF3659C9)),
                        const SizedBox(height: 16),
                        AppText(
                            widget.state.book == null
                                ? 'Join your flat'
                                : 'Share changes, keep data on your devices',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        const AppText(
                            'Both people must keep this screen open and stay online. Messages are encrypted on your device and passed through a live relay; this app does not save them in a server database. Close this screen to disconnect.'),
                        const SizedBox(height: 20),
                        if (session == null) ...[
                          if (widget.state.book != null)
                            FilledButton.icon(
                                onPressed: busy ? null : () => start(true),
                                icon: const Icon(Icons.add_link),
                                label: const AppText('Create a sync code')),
                          const SizedBox(height: 16),
                          TextField(
                              controller: code,
                              minLines: 2,
                              maxLines: 3,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                  labelText: 'Code from the other device',
                                  hintText: 'FLAIT2-…')),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: busy ? null : () => start(false),
                              child: const AppText('Connect with code')),
                        ] else
                          AnimatedBuilder(
                              animation: session!,
                              builder: (context, _) {
                                final s = session!;
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (s.host && s.connected) ...[
                                        const AppText(
                                            'Share this private code with ONE flatmate. It lasts 10 minutes.'),
                                        const SizedBox(height: 12),
                                        SelectableText(s.code,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        TextButton.icon(
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                  ClipboardData(text: s.code));
                                            },
                                            icon: const Icon(Icons.copy),
                                            label: const AppText(
                                                'Copy sync code')),
                                      ],
                                      const SizedBox(height: 12),
                                      Card(
                                          child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: AppText(s.status,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)))),
                                      if (s.awaitingAdmission) ...[
                                        const SizedBox(height: 12),
                                        AppText(
                                            'New member: ${s.peerName}\nDevice: ${s.peerId?.substring(0, 12)}…'),
                                        const AppText(
                                            'Confirm that this is your flatmate. Admitting this device gives it a copy of the flat history.'),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                            onPressed: busy
                                                ? null
                                                : () async {
                                                    setState(() => busy = true);
                                                    try {
                                                      await s.approveMember();
                                                    } catch (e) {
                                                      if (mounted) {
                                                        setState(() => error =
                                                            e.toString());
                                                      }
                                                    } finally {
                                                      if (mounted) {
                                                        setState(
                                                            () => busy = false);
                                                      }
                                                    }
                                                  },
                                            child: const AppText(
                                                'Admit this flatmate & sync')),
                                      ],
                                      const SizedBox(height: 12),
                                      OutlinedButton(
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  await s.close();
                                                  if (!context.mounted) return;
                                                  Navigator.pop(context);
                                                },
                                          child: const AppText(
                                              'Close & disconnect')),
                                    ]);
                              }),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: AppText(error!,
                                  style: const TextStyle(color: Colors.red))),
                        const SizedBox(height: 24),
                        const AppText(
                            'Codes are only needed for first pairing or manual recovery. Paired devices sync automatically while both apps are open online. Requests, votes and treasurer entries become shared records after the owner confirms them. The relay may see connection metadata, never your plaintext ledger.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blueGrey)),
                      ]),
                ))),
      );
}
