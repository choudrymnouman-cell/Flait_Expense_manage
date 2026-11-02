import '../services/app_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';

Future<void> showBackupDialog(BuildContext context, FlaitState state,
        {bool restore = false}) =>
    showDialog<void>(
        context: context,
        builder: (_) => _BackupDialog(state: state, restore: restore));

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({required this.state, required this.restore});
  final FlaitState state;
  final bool restore;
  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final password = TextEditingController();
  bool busy = false;
  String? message;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> act() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (widget.restore) {
        final file = await FilePicker.platform.pickFiles(
            withData: true,
            type: FileType.custom,
            allowedExtensions: ['flait']);
        if (file == null) return;
        if (file.files.single.size > 20000000) {
          throw StateError('Backup exceeds 20 MB.');
        }
        await widget.state.restoreBackup(
            utf8.decode(file.files.single.bytes!), password.text);
        if (mounted) Navigator.pop(context);
      } else {
        final text = await widget.state.exportBackup(password.text);
        final path = await FilePicker.platform.saveFile(
            dialogTitle: 'Save encrypted backup',
            fileName: 'flait-backup.flait',
            type: FileType.custom,
            allowedExtensions: ['flait'],
            bytes: Uint8List.fromList(utf8.encode(text)));
        if (path != null) await widget.state.markBackup();
        if (mounted) {
          setState(() => message = path == null
              ? 'Save cancelled.'
              : 'Encrypted backup exported. Keep the password separately.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = widget.restore
            ? 'Could not restore. Check the password and backup file. Current data was not replaced.'
            : 'Could not export. Use a password of at least 12 characters and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: AppText(widget.restore
            ? 'Restore device backup'
            : 'Encrypted local backup'),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppText(widget.restore
                  ? 'Restore only on a fresh installation. An owner backup replaces the ORIGINAL owner device: never operate two copies of the owner identity.'
                  : 'The file contains your local records and device identity. It is password-encrypted on this device and is not uploaded. There is no server password recovery.'),
              const SizedBox(height: 16),
              TextField(
                  controller: password,
                  obscureText: true,
                  enabled: !busy,
                  decoration: const InputDecoration(
                      labelText: 'Backup password (12+ characters)')),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppText(message!)),
            ])),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const AppText('Close')),
          FilledButton(
              onPressed: busy ? null : act,
              child: AppText(busy
                  ? 'Working…'
                  : widget.restore
                      ? 'Choose backup & restore'
                      : 'Save encrypted file'))
        ],
      ));
}
