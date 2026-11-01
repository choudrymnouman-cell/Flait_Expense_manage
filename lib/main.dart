import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app.dart';
import 'auth/auth_gate.dart';
import 'offline/local_database.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final state = FlaitState(await LocalDatabase.open());
    await state.load();
    runApp(OfflineFlaitApp(state: state));
  } catch (_) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Local storage could not be opened. Use a normal browser window with storage enabled, or reopen the app. Existing data has not been reset.'))))));
  }
}

class OfflineFlaitApp extends StatefulWidget {
  const OfflineFlaitApp({super.key, required this.state});
  final FlaitState state;
  @override
  State<OfflineFlaitApp> createState() => _OfflineFlaitAppState();
}

class _OfflineFlaitAppState extends State<OfflineFlaitApp> {
  late final SemanticsHandle semantics;
  FlaitState get state => widget.state;
  @override
  void initState() {
    super.initState();
    semantics = SemanticsBinding.instance.ensureSemantics();
  }

  @override
  void dispose() {
    semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flait — Offline Flat Expenses',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF3659C9)),
            scaffoldBackgroundColor: const Color(0xFFF6F7FB),
            inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)))),
        home: AnimatedBuilder(
            animation: state,
            builder: (context, _) {
              if (state.loadError != null) {
                return Scaffold(
                    body: Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                      'Could not read local data. No records were reset.'),
                                  Text(state.loadError!),
                                  FilledButton(
                                      onPressed: state.load,
                                      child: const Text('Retry local load')),
                                ]))));
              }
              return state.book == null
                  ? OfflineSetupScreen(state: state)
                  : FlaitApp(state: state);
            }),
      );
}
