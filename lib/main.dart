import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app.dart';
import 'expense_manage/expense_app.dart';
import 'expense_manage/monthly_state.dart';
import 'services/app_preferences.dart';
import 'screens/lock_gate.dart';
import 'offline/auto_sync.dart';
import 'auth/auth_gate.dart';
import 'offline/local_database.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final state = FlaitState(await LocalDatabase.open());
    await state.load();
    if (state.loadError != null) throw StateError('Local storage unavailable.');
    final app = MonthlyState(state)..active = false;
    await app.load();
    runApp(ExpenseManageApp(app));
  } catch (_) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Could not open local storage. Reopen Expense Manage.'))))));
  }
}

class OfflineFlaitApp extends StatefulWidget {
  const OfflineFlaitApp({super.key, required this.state});
  final FlaitState state;
  @override
  State<OfflineFlaitApp> createState() => _OfflineFlaitAppState();
}

class _OfflineFlaitAppState extends State<OfflineFlaitApp>
    with WidgetsBindingObserver {
  late final AutoSync auto;
  bool locked = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    auto.setActive(lifecycle == AppLifecycleState.resumed && !locked);
  }

  late final SemanticsHandle semantics;
  FlaitState get state => widget.state;
  @override
  void initState() {
    super.initState();
    semantics = SemanticsBinding.instance.ensureSemantics();
    WidgetsBinding.instance.addObserver(this);
    auto = AutoSync(state);
    locked = state.preferences['pin'] != null;
    auto.setActive(!locked);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auto.dispose();
    semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPreferences(
      state: state,
      child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => MaterialApp(
                title: 'Flait — Offline Flat Expenses',
                builder: (context, child) => Directionality(
                    textDirection: state.preferences['language'] == 'ur'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: LockGate(
                        state: state,
                        onLock: (value) {
                          locked = value;
                          auto.setActive(!locked);
                        },
                        child: child!)),
                debugShowCheckedModeBanner: false,
                themeMode: state.preferences['dark'] == true
                    ? ThemeMode.dark
                    : ThemeMode.light,
                darkTheme: ThemeData(
                    useMaterial3: true,
                    fontFamily: 'NotoSans',
                    fontFamilyFallback: const ['NotoNaskhArabic'],
                    brightness: Brightness.dark,
                    colorSchemeSeed: const Color(0xFF91A9FF)),
                theme: ThemeData(
                    useMaterial3: true,
                    fontFamily: 'NotoSans',
                    fontFamilyFallback: const ['NotoNaskhArabic'],
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFF3659C9)),
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
                                              child: const Text(
                                                  'Retry local load')),
                                        ]))));
                      }
                      return state.book == null
                          ? OfflineSetupScreen(state: state)
                          : FlaitApp(state: state, auto: auto);
                    }),
              )));
}
