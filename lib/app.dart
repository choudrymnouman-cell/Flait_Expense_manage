import 'package:flutter/material.dart';

import 'screens/approvals_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expense_entry_screen.dart';
import 'screens/ledger_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_status_screen.dart';
import 'services/app_preferences.dart';
import 'state/app_state.dart';
import 'offline/auto_sync.dart';
import 'widgets/flait_logo.dart';

class FlaitApp extends StatefulWidget {
  const FlaitApp({super.key, required this.state, this.auto});
  final FlaitState state;
  final AutoSync? auto;

  @override
  State<FlaitApp> createState() => _FlaitAppState();
}

class _FlaitAppState extends State<FlaitApp> {
  FlaitState get state => widget.state;
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation:
            Listenable.merge([state, if (widget.auto != null) widget.auto!]),
        builder: (context, _) {
          if (state.loading && state.members.isEmpty) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (state.loadError != null && state.members.isEmpty) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppText('Could not load flat data.'),
                      const SizedBox(height: 8),
                      AppText(state.loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: state.load,
                        child: const AppText('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              Material(
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const FlaitLogo(size: 32),
                      IconButton(
                          tooltip: 'Internet sync',
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => SyncStatusScreen(
                                      state: state, auto: widget.auto))),
                          icon: const Icon(Icons.sync)),
                      Expanded(
                        child: AppText(
                          state.loadError == null
                              ? '${widget.auto?.status ?? 'Saved on this device'} · ${state.queuedCount} queued'
                              : 'Local load failed. Showing last loaded data.',
                          style: TextStyle(
                            color: state.loadError == null
                                ? Colors.blueGrey
                                : Colors.red,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reload local data',
                        onPressed: state.loading ? null : state.load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _buildShell(context)),
            ],
          );
        },
      );

  Widget _buildShell(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          final pages = [
            DashboardScreen(
              state: state,
              onAddExpense: () => setState(() => selectedIndex = 1),
            ),
            ExpenseEntryScreen(
              state: state,
              onSubmitted: () => setState(() => selectedIndex = 0),
            ),
            ApprovalsScreen(state: state),
            LedgerScreen(state: state),
            SettingsScreen(state: state, auto: widget.auto),
          ];
          final labels = [
            'Dashboard',
            'New expense',
            'Approvals',
            'Ledger',
            'Settings',
          ];
          final icons = [
            Icons.dashboard_outlined,
            Icons.add_card_outlined,
            Icons.fact_check_outlined,
            Icons.receipt_long_outlined,
            Icons.settings_outlined,
          ];
          if (wide) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    extended: constraints.maxWidth >= 1100,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (i) =>
                        setState(() => selectedIndex = i),
                    leading: const Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 28),
                      child: FlaitLogo(size: 40),
                    ),
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: AppText(localize(context, labels[i])),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: SafeArea(child: pages[selectedIndex])),
                ],
              ),
            );
          }
          return Scaffold(
            body: SafeArea(child: pages[selectedIndex]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => setState(() => selectedIndex = i),
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(
                    icon: Icon(icons[i]),
                    label: localize(context,
                        labels[i] == 'New expense' ? 'Add' : labels[i]),
                  ),
              ],
            ),
          );
        },
      );
}
