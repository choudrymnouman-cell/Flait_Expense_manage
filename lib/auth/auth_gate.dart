import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app.dart';

class FlaitAuthApp extends StatelessWidget {
  const FlaitAuthApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Flait — Flat Expenses',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3659C9)),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE1E5EF))),
      ),
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool signUp = false;
  bool busy = false;
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final flatName = TextEditingController();
  String? error;
  String? notice;

  @override
  void dispose() {
    email.dispose(); password.dispose(); name.dispose(); flatName.dispose();
    super.dispose();
  }

  Future<void> submitAuth() async {
    setState(() { busy = true; error = null; notice = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (signUp) {
        await auth.signUp(email: email.text.trim(), password: password.text,
          data: {'display_name': name.text.trim()});
        if (auth.currentSession == null) {
          setState(() => notice = 'Account created. Check your email to confirm, then sign in.');
        }
      } else {
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = 'Could not connect. Check your internet and Supabase settings.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createFlat() async {
    if (flatName.text.trim().length < 2 || name.text.trim().isEmpty) {
      setState(() => error = 'Enter your name and a flat name (at least 2 characters).');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final db = Supabase.instance.client;
      final user = db.auth.currentUser!;
      final flat = await db.from('flats').insert({
        'name': flatName.text.trim(), 'created_by': user.id,
      }).select('id').single();
      await db.from('flat_members').insert({
        'flat_id': flat['id'], 'user_id': user.id,
        'display_name': name.text.trim(), 'role': 'admin', 'active': true,
      });
    } catch (e) {
      setState(() => error = 'Could not create flat: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return _authForm();
      return FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(user.id),
        future: Supabase.instance.client.from('flat_members').select('flat_id, display_name, flats(name,currency)').eq('user_id', user.id).eq('active', true),
        builder: (context, memberships) {
          if (memberships.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (memberships.hasError) return Scaffold(body: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Could not load your flat membership.'),
              const SizedBox(height: 8), Text('${memberships.error}', textAlign: TextAlign.center),
              const SizedBox(height: 12), FilledButton(onPressed: () => setState(() {}), child: const Text('Retry')),
              TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Sign out')),
            ]),
          )));
          final rows = memberships.data ?? [];
          if (rows.isEmpty) return _createFlatForm();
          return FlaitApp(flatId: rows.first['flat_id'] as String);
        },
      );
    },
  );

  Widget _authForm() => Scaffold(
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.home_work_rounded, size: 54, color: Color(0xFF3659C9)),
        const SizedBox(height: 12),
        const Text('Flait', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const Text('Shared flat expenses, clearly managed', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        if (signUp) TextField(controller: name, decoration: const InputDecoration(labelText: 'Your name')),
        if (signUp) const SizedBox(height: 12),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (at least 6 characters)')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(notice!, style: const TextStyle(color: Colors.green))),
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : submitAuth, child: Text(busy ? 'Please wait…' : signUp ? 'Create account' : 'Sign in')),
        TextButton(onPressed: busy ? null : () => setState(() { signUp = !signUp; error = null; notice = null; }), child: Text(signUp ? 'Already have an account? Sign in' : 'New here? Create account')),
      ])),
    ))),
  );

  Widget _createFlatForm() => Scaffold(
    appBar: AppBar(actions: [TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Sign out'))]),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.home_work_rounded, size: 48, color: Color(0xFF3659C9)),
        const SizedBox(height: 12),
        const Text('Set up your flat', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const Text('You will become the first flat admin. You can invite flatmates in a later release.'),
        const SizedBox(height: 20),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Your name'), textInputAction: TextInputAction.next),
        const SizedBox(height: 12),
        TextField(controller: flatName, decoration: const InputDecoration(labelText: 'Flat name', hintText: 'e.g. Satellite Town Flat')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : createFlat, child: Text(busy ? 'Creating…' : 'Create flat')),
      ])),
    ))),
  );
}
