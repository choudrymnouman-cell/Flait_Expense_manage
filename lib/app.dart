import 'package:flutter/material.dart';
import 'screens/approvals_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expense_entry_screen.dart';
import 'screens/ledger_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';

class FlaitApp extends StatefulWidget {
  const FlaitApp({super.key, required this.flatId});
  final String flatId;

  @override
  State<FlaitApp> createState() => _FlaitAppState();
}

class _FlaitAppState extends State<FlaitApp> {
  late final FlaitState state;
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    state = FlaitState(flatId: widget.flatId);
    state.load();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      if (state.loading && state.members.isEmpty) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (state.loadError != null && state.members.isEmpty) {
        return Scaffold(body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Could not load flat data.'),
            const SizedBox(height: 8), Text(state.loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12), FilledButton(onPressed: state.load, child: const Text('Retry')),
          ]),
        )));
      }
      return _buildShell(context);
    },
  );

  Widget _buildShell(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth >= 850;
    final pages = [
      DashboardScreen(state: state, onAddExpense: () => setState(() => selectedIndex = 1)),
      ExpenseEntryScreen(state: state, onSubmitted: () => setState(() => selectedIndex = 0)),
      ApprovalsScreen(state: state),
      LedgerScreen(state: state),
      SettingsScreen(state: state),
    ];
    final labels = ['Dashboard', 'New expense', 'Approvals', 'Ledger', 'Settings'];
    final icons = [Icons.dashboard_outlined, Icons.add_card_outlined, Icons.fact_check_outlined, Icons.receipt_long_outlined, Icons.settings_outlined];
    if (wide) {
      return Scaffold(body: Row(children: [
        NavigationRail(
          extended: constraints.maxWidth >= 1100,
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => setState(() => selectedIndex = i),
          leading: const Padding(padding: EdgeInsets.fromLTRB(16, 24, 16, 28), child: Icon(Icons.home_work_rounded, size: 34, color: Color(0xFF3659C9))),
          destinations: [for (var i = 0; i < labels.length; i++) NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i]))],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: SafeArea(child: pages[selectedIndex])),
      ]));
    }
    return Scaffold(
      body: SafeArea(child: pages[selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => setState(() => selectedIndex = i),
        destinations: [for (var i = 0; i < labels.length; i++) NavigationDestination(icon: Icon(icons[i]), label: labels[i] == 'New expense' ? 'Add' : labels[i])],
      ),
    );
  });
}
