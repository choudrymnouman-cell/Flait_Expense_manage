import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../screens/lock_gate.dart';
import '../screens/pro_preferences_screen.dart';
import '../services/app_preferences.dart';
import 'entry_form.dart';
import 'group_screens.dart';
import 'monthly_state.dart';
import 'report.dart';

class ExpenseManageApp extends StatefulWidget {
  const ExpenseManageApp(this.state, {super.key});
  final MonthlyState state;

  @override
  State<ExpenseManageApp> createState() => _ExpenseManageAppState();
}

class _ExpenseManageAppState extends State<ExpenseManageApp>
    with WidgetsBindingObserver {
  bool unlocked = false;
  late final Timer clock;
  bool preparingReports = false;

  MonthlyState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      state.tick();
      unawaited(prepareReports());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.profile.identity != null) {
        unawaited(requestNotifications());
      }
    });
  }

  Future<void> prepareReports() async {
    if (!unlocked || preparingReports) return;
    preparingReports = true;
    try {
      await saveClosedReports(state);
    } catch (_) {
      // The next foreground tick retries an interrupted report write.
    } finally {
      preparingReports = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    state.setActive(lifecycle == AppLifecycleState.resumed && unlocked);
    if (lifecycle == AppLifecycleState.resumed) {
      state.tick();
      unawaited(prepareReports());
    }
  }

  @override
  void dispose() {
    clock.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPreferences(
        state: state.profile,
        child: MaterialApp(
          title: 'Expense Manage',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xff28665c)),
            scaffoldBackgroundColor: const Color(0xfff5f7f6),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          builder: (_, child) => LockGate(
            state: state.profile,
            onLock: (locked) {
              unlocked = !locked;
              state.setActive(
                unlocked &&
                    WidgetsBinding.instance.lifecycleState !=
                        AppLifecycleState.paused,
              );
              unawaited(prepareReports());
            },
            child: child!,
          ),
          home: AnimatedBuilder(
            animation: state,
            builder: (context, _) => state.profile.identity == null
                ? SignupScreen(state)
                : MonthlyHome(state),
          ),
        ),
      );
}

Future<void> requestNotifications() async {
  try {
    await MonthlyState.notifications.invokeMethod<void>('permission');
  } on MissingPluginException {
    // Platform notification integration is Android-only.
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen(this.state, {super.key});
  final MonthlyState state;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final name = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.state.profile.prepareIdentity(name.text);
      await requestNotifications();
    } catch (e) {
      if (mounted) setState(() => error = 'Enter your name and try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Expense Manage')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Your name',
                      errorText: error,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: saving ? null : submit,
                    child: const Text('Sign up'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class MonthlyHome extends StatelessWidget {
  const MonthlyHome(this.state, {super.key});
  final MonthlyState state;

  Future<void> editSalary(BuildContext context, String month) async {
    final result = await entryForm(context, 'Monthly salary', [
      EntryField(
        'salary',
        'Salary',
        money: true,
        initial: (state.salary(month) / 100).toStringAsFixed(2),
      ),
    ]);
    if (result == null || !context.mounted) return;
    await perform(
      context,
      () => state.saveValue(
        month,
        'salary',
        parseMoney(result['salary']!, zero: true),
      ),
    );
  }

  Future<void> report(BuildContext context) async {
    final sorted = state.reportMonths.toList()..sort((a, b) => b.compareTo(a));
    final input = await entryForm(context, 'Export monthly PDF', [
      EntryField(
        'month',
        'Month',
        options: {for (final month in sorted) month: month},
      ),
    ]);
    if (input == null || !context.mounted) return;
    await perform(context, () => exportMonth(state, input['month']!));
  }

  @override
  Widget build(BuildContext context) {
    final month = state.currentMonth;
    final salary = state.salary(month), spent = state.spent(month);
    void open(Widget child) =>
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => child));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Manage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'App lock',
            onPressed: () => open(ProtectionScreen(state)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${state.profile.identity!.name} · $month'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Monthly salary'),
                  subtitle: Text(rupees(salary)),
                  trailing: IconButton(
                    onPressed: () => editSalary(context, month),
                    tooltip: 'Edit salary',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
                ListTile(
                  title: const Text('Monthly expenses'),
                  trailing: Text(rupees(spent)),
                ),
                ListTile(
                  title: const Text('Remaining'),
                  trailing: Text(rupees(salary - spent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final item in [
            (
              'Home Grocery',
              Icons.shopping_basket_outlined,
              PersonalBudget(state, 'grocery'),
            ),
            (
              'Shopping',
              Icons.shopping_bag_outlined,
              PersonalBudget(state, 'shopping'),
            ),
            (
              'Meal With Friends',
              Icons.restaurant_outlined,
              GroupsScreen(state, 'meal'),
            ),
            ('Loan', Icons.payments_outlined, GroupsScreen(state, 'loan')),
            (
              'Flait Friends',
              Icons.apartment_outlined,
              GroupsScreen(state, 'flat'),
            ),
          ])
            Card(
              child: ListTile(
                leading: Icon(item.$2),
                title: Text(item.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(item.$3),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => report(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export monthly PDF'),
          ),
        ],
      ),
    );
  }
}

class PersonalBudget extends StatelessWidget {
  const PersonalBudget(this.state, this.section, {super.key});
  final MonthlyState state;
  final String section;

  Future<void> editBudget(BuildContext context, String key) async {
    final input = await entryForm(context, 'Monthly budget', [
      EntryField(
        'amount',
        'Budget',
        money: true,
        initial: (state.budget(key, section) / 100).toStringAsFixed(2),
      ),
    ]);
    if (input == null || !context.mounted) return;
    await perform(
      context,
      () => state.saveValue(
        key,
        '${section}Budget',
        parseMoney(input['amount']!, zero: true),
      ),
    );
  }

  Future<void> addItem(BuildContext context, String key) async {
    final input = await entryForm(context, 'Add item', const [
      EntryField('title', 'Item name'),
      EntryField('amount', 'Price', money: true),
    ]);
    if (input == null || !context.mounted) return;
    await perform(
      context,
      () => state.addItem(
        key,
        section,
        input['title']!.trim(),
        parseMoney(input['amount']!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final key = state.currentMonth;
          final rows = state.items(key, section);
          final total = rows.fold<int>(
            0,
            (sum, row) => sum + (row['cents'] as int),
          );
          final budget = state.budget(key, section);
          return Scaffold(
            appBar: AppBar(
              title: Text(section == 'grocery' ? 'Home Grocery' : 'Shopping'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(key),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Budget'),
                        subtitle: Text(rupees(budget)),
                        trailing: IconButton(
                          onPressed: () => editBudget(context, key),
                          tooltip: 'Set budget',
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                      ListTile(
                        title: const Text('Total expenses'),
                        trailing: Text(rupees(total)),
                      ),
                      ListTile(
                        title: const Text('Remaining budget'),
                        trailing: Text(rupees(budget - total)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => addItem(context, key),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
                for (final row in rows.reversed)
                  ListTile(
                    title: Text(row['title'] as String),
                    trailing: Text(rupees(row['cents'] as int)),
                  ),
              ],
            ),
          );
        },
      );
}

class ProtectionScreen extends StatelessWidget {
  const ProtectionScreen(this.state, {super.key});
  final MonthlyState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('App lock')),
          body: ListView(
            children: [
              ListTile(
                title: const Text('PIN'),
                trailing: Text(
                  state.profile.preferences['pin'] == null ? 'Off' : 'On',
                ),
                onTap: () => ProPreferencesScreen(state: state.profile)
                    .configurePin(context),
              ),
              SwitchListTile(
                title: const Text('Fingerprint'),
                value: state.profile.preferences['biometric'] == true,
                onChanged: state.profile.preferences['pin'] == null
                    ? null
                    : (enabled) => perform(context, () async {
                          if (enabled &&
                              !await LocalAuthentication().authenticate(
                                localizedReason: 'Confirm your fingerprint',
                                options: const AuthenticationOptions(
                                  biometricOnly: true,
                                ),
                              )) {
                            return;
                          }
                          await state.profile
                              .setPreference('biometric', enabled);
                        }),
              ),
            ],
          ),
        ),
      );
}
