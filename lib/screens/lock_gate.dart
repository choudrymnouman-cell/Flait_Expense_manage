import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../services/app_preferences.dart';
import '../offline/secure_book.dart';
import '../state/app_state.dart';

class LockGate extends StatefulWidget {
  const LockGate(
      {super.key,
      required this.state,
      required this.child,
      required this.onLock});
  final FlaitState state;
  final Widget child;
  final ValueChanged<bool> onLock;
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final pin = TextEditingController();
  bool unlocked = false, busy = false, hadPin = false;
  int failures = 0;
  DateTime? blocked;
  String? error;
  @override
  void initState() {
    super.initState();
    hadPin = widget.state.preferences['pin'] != null;
    final attempts = asMap(widget.state.preferences['pinAttempts'] ?? {});
    failures = attempts['failures'] as int? ?? 0;
    blocked = DateTime.tryParse(attempts['blocked'] as String? ?? '');
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onLock(widget.state.preferences['pin'] != null);
    });
  }

  @override
  void didUpdateWidget(covariant LockGate old) {
    super.didUpdateWidget(old);
    final has = widget.state.preferences['pin'] != null;
    if (has != hadPin) {
      hadPin = has;
      unlocked = !has;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLock(has);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        widget.state.preferences['pin'] != null) {
      setState(() => unlocked = false);
      widget.onLock(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pin.dispose();
    super.dispose();
  }

  Future<void> success() async {
    await widget.state.setPreference('pinAttempts', {});
    if (!mounted) return;
    setState(() {
      unlocked = true;
      error = null;
      pin.clear();
      failures = 0;
      blocked = null;
    });
    widget.onLock(false);
  }

  Future<void> unlock({bool biometric = false}) async {
    if (busy) return;
    if (blocked != null && DateTime.now().isBefore(blocked!)) {
      setState(() => error = 'Too many attempts. Wait 30 seconds.');
      return;
    }
    setState(() => busy = true);
    try {
      final ok = biometric
          ? await LocalAuthentication().authenticate(
              localizedReason: 'Unlock your Flait records',
              options: const AuthenticationOptions(
                  biometricOnly: false, stickyAuth: true))
          : await PinSecurity.check(
              pin.text, asMap(widget.state.preferences['pin']));
      if (ok) {
        await success();
      } else {
        failures++;
        if (failures >= 5) {
          blocked = DateTime.now().add(const Duration(seconds: 30));
        }
        await widget.state.setPreference('pinAttempts', {
          'failures': failures,
          'blocked': blocked?.toUtc().toIso8601String()
        });
        if (mounted) {
          setState(() => error = 'Could not unlock. Check your PIN.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Device authentication unavailable. Use your app PIN.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.preferences['pin'] == null || unlocked) {
      return widget.child;
    }
    return Scaffold(
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_outline, size: 48),
                      AppText(tr(context, 'Unlock Flait', 'فلیٹ کھولیں'),
                          style: Theme.of(context).textTheme.headlineSmall),
                      TextField(
                          controller: pin,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          maxLength: 12,
                          decoration:
                              const InputDecoration(labelText: 'App PIN'),
                          onSubmitted: (_) => unlock()),
                      if (error != null) AppText(error!),
                      FilledButton(
                          onPressed: busy ? null : unlock,
                          child: AppText(tr(context, 'Unlock', 'کھولیں'))),
                      if (!kIsWeb &&
                          widget.state.preferences['biometric'] == true)
                        TextButton.icon(
                            onPressed:
                                busy ? null : () => unlock(biometric: true),
                            icon: const Icon(Icons.fingerprint),
                            label:
                                const AppText('Fingerprint / device passcode')),
                      const AppText(
                          'Forgot PIN? Restore your encrypted backup on a fresh installation. There is no server recovery.'),
                    ])))));
  }
}
