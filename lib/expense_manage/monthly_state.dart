import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/flat_models.dart';
import '../offline/auto_sync.dart';
import '../offline/secure_book.dart';
import '../state/app_state.dart';

String monthOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

String dateOf(DateTime date) =>
    '${monthOf(date)}-${date.day.toString().padLeft(2, '0')}';

String rupees(int cents) => 'Rs ${(cents / 100).toStringAsFixed(2)}';

int parseMoney(String value, {bool zero = false}) {
  final cleaned = value.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(cleaned)) {
    throw const FormatException('Enter a valid amount.');
  }
  final parts = cleaned.split('.');
  final result = int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
  if (result == 0 && !zero) {
    throw const FormatException('Enter an amount above zero.');
  }
  return result;
}

Map<String, int> mealBalances(Map<String, dynamic> meal) {
  final shares = asMap(meal['shares']);
  final paid = asMap(meal['paid']);
  return shares.map(
      (id, share) => MapEntry(id, (paid[id] as int? ?? 0) - (share as int)));
}

class MonthLine {
  const MonthLine(this.section, this.title, this.cents);
  final String section;
  final String title;
  final int cents;
}

class MonthlyState extends ChangeNotifier {
  MonthlyState(this.profile);
  final FlaitState profile;
  final groups = <String, FlaitState>{};
  final transports = <FlaitState, AutoSync>{};
  static const notifications = MethodChannel('expense_manage/notifications');
  bool active = true;
  bool _checking = false;
  Future<void> _delivery = Future.value();
  Future<void> _writes = Future.value();

  Future<void> write(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  String get currentMonth => monthOf(DateTime.now());
  Map<String, dynamic> get months =>
      asMap(profile.preferences['expenseMonths'] ?? {});
  Map<String, dynamic> month(String key) => asMap(months[key] ?? {});
  int salary(String key) => month(key)['salary'] as int? ?? 0;
  List<Map<String, dynamic>> items(String key, String section) =>
      asMaps(month(key)[section] ?? []);
  int budget(String key, String section) =>
      month(key)['${section}Budget'] as int? ?? 0;

  Future<void> load() async {
    if (profile.book != null) attach('device', profile);
    for (final id in (profile.preferences['expenseGroups'] as List? ?? [])
        .cast<String>()) {
      final group = FlaitState(profile.storage.scoped(id));
      await group.load();
      if (group.book != null) {
        attach(id, group);
      } else {
        group.dispose();
      }
    }
    profile.addListener(notifyListeners);
    await checkNotifications();
  }

  void attach(String id, FlaitState group) {
    groups[id] = group;
    if (group.view!.kind != 'loan') {
      group.directData = directFor;
      group.receiveDirect = receiveDirect;
    }
    final transport = AutoSync(group)..setActive(active);
    transports[group] = transport;
    group.addListener(groupChanged);
    notifyListeners();
  }

  void groupChanged() {
    for (final transport in transports.values) {
      transport.refresh();
    }
    notifyListeners();
    unawaited(checkNotifications());
  }

  void setActive(bool value) {
    active = value;
    for (final transport in transports.values) {
      transport.setActive(value);
    }
    if (value) unawaited(checkNotifications());
  }

  Future<FlaitState> newGroup(
    String kind, {
    String? name,
    String? invitee,
  }) async {
    final id = 'workspace-${const Uuid().v4()}';
    final group = FlaitState(profile.storage.scoped(id));
    await group.useIdentity(profile.identity!);
    if (name != null) {
      await group.createFlat(name, kind: kind, invitee: invitee);
    }
    await register(id);
    if (name == null) {
      group.addListener(() {
        if (group.book != null && !groups.containsKey(id)) attach(id, group);
      });
    } else {
      attach(id, group);
    }
    return group;
  }

  Future<void> register(String id) => write(() async {
        final ids = (profile.preferences['expenseGroups'] as List? ?? [])
            .cast<String>();
        if (!ids.contains(id)) {
          await profile.setPreference('expenseGroups', [...ids, id]);
        }
      });

  Map<String, dynamic> directFor(String peer) {
    final delivered =
        (profile.preferences['deliveredLoans'] as List? ?? []).cast<String>();
    return {
      'loans': [
        for (final loan in ofKind('loan')
            .where(
              (loan) =>
                  loan.isOwner &&
                  loan.book!.details['invitee'] == peer &&
                  loan.view!.monthly.isNotEmpty &&
                  !delivered.contains(loan.flatId),
            )
            .take(20))
          loan.sharedPacket(),
      ],
      'received': [
        for (final loan in ofKind('loan'))
          if (!loan.isOwner &&
              loan.book!.originOwner == peer &&
              loan.book!.details['invitee'] == profile.currentMemberId)
            loan.flatId,
      ],
    };
  }

  Future<void> receiveDirect(String peer, Map<String, dynamic> direct) {
    final result = _delivery.then((_) async {
      final delivered = <String>{
        ...(profile.preferences['deliveredLoans'] as List? ?? [])
            .cast<String>(),
      };
      final acknowledged =
          (direct['received'] as List? ?? []).whereType<String>().toSet();
      final size = delivered.length;
      for (final loan in ofKind('loan')) {
        if (loan.isOwner &&
            loan.book!.details['invitee'] == peer &&
            acknowledged.contains(loan.flatId)) {
          delivered.add(loan.flatId);
        }
      }
      if (delivered.length != size) {
        await profile.setPreference('deliveredLoans', delivered.toList());
      }

      for (final packet in asMaps(direct['loans'] ?? []).take(20)) {
        final book = await SecureBook.fromJson(asMap(packet['book']));
        if (book.originOwner != peer ||
            book.details['kind'] != 'loan' ||
            book.details['invitee'] != profile.currentMemberId ||
            groups.values.any((g) => g.flatId == book.id)) {
          continue;
        }
        final id = 'loan-${book.id}';
        final loan = FlaitState(profile.storage.scoped(id));
        await loan.load();
        if (loan.loadError != null) {
          throw StateError('Could not open saved loan.');
        }
        if (loan.identity == null) await loan.useIdentity(profile.identity!);
        await loan.receivePacket({
          'book': packet['book'],
          'proposals': <Map<String, dynamic>>[],
        });
        await register(id);
        attach(id, loan);
      }
      groupChanged();
    });
    _delivery = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Iterable<FlaitState> ofKind(String kind) => groups.values.where(
        (g) =>
            g.view?.kind == kind ||
            (kind == 'flat' && g.view?.kind == 'legacy'),
      );

  List<FlatMember> get contacts => {
        for (final g in groups.values)
          if (g.currentMember.active)
            for (final m in g.members)
              if (m.active && m.id != profile.currentMemberId) m.id: m,
      }.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> saveValue(String monthKey, String field, int value) => write(
        () => profile.setPreference('expenseMonths', {
          ...months,
          monthKey: {...month(monthKey), field: value},
        }),
      );

  Future<void> addItem(String key, String section, String name, int amount) =>
      write(
        () => profile.setPreference('expenseMonths', {
          ...months,
          key: {
            ...month(key),
            section: [
              ...items(key, section),
              {'title': name, 'cents': amount},
            ],
          },
        }),
      );

  List<MonthLine> lines(String key) {
    final rows = <MonthLine>[
      for (final pair in [
        ('grocery', 'Home Grocery'),
        ('shopping', 'Shopping'),
      ])
        for (final item in items(key, pair.$1))
          MonthLine(pair.$2, item['title'] as String, item['cents'] as int),
    ];
    for (final g in groups.values) {
      final me = g.currentMemberId;
      for (final row in g.view!.monthly.values) {
        if (row['month'] == key) {
          switch (row['type']) {
            case 'meal':
              final share = asMap(row['shares'])[me] as int? ?? 0;
              if (share > 0) {
                rows.add(
                  MonthLine('Meal With Friends', row['title'] as String, share),
                );
              }
            case 'budget':
              final share = asMap(row['shares'])[me] as int? ?? 0;
              if (share > 0) {
                rows.add(MonthLine('Flait Friends', g.flatName, share));
              }
            case 'loan':
              rows.add(
                MonthLine(
                  isLender(g, row) ? 'Loan given' : 'Loan reserve',
                  g.flatName,
                  row['cents'] as int,
                ),
              );
          }
        }
        if (row['type'] == 'loan' &&
            row['returnMonth'] == key &&
            isLender(g, row)) {
          final amount = row['cents'] as int;
          rows.add(MonthLine('Loan return', g.flatName, -amount));
        }
      }
    }
    return rows;
  }

  static bool isLender(FlaitState group, Map<String, dynamic> row) =>
      (row['creator'] == group.currentMemberId) ==
      (row['direction'] == 'given');

  Set<String> get reportMonths => {
        currentMonth,
        ...months.keys,
        for (final group in groups.values)
          for (final row in group.view!.monthly.values) ...[
            row['month'] as String,
            if (row['returnMonth'] case final String returned) returned,
          ],
      };

  void tick() => notifyListeners();

  int spent(String key) => lines(key).fold(0, (sum, row) => sum + row.cents);

  Future<void> checkNotifications() async {
    if (_checking || profile.identity == null) return;
    _checking = true;
    try {
      for (final g in groups.values.toList()) {
        for (final entry in g.view!.monthly.entries) {
          final row = entry.value;
          final key = '${g.flatId}:${entry.key}';
          String? title;
          String body = g.flatName;
          switch (row['type']) {
            case 'meal':
              final debts = g.settlement.suggestions(mealBalances(row));
              for (final debt
                  in debts.where((d) => d.from == g.currentMemberId)) {
                await notifications.invokeMethod<void>('show', {
                  'id': '$key:${debt.to}',
                  'title': 'Meal payment due',
                  'body': 'Pay ${g.memberName(debt.to)} ${rupees(debt.cents)}',
                });
              }
            case 'item':
              if (!(row['votes'] as List).contains(g.currentMemberId) &&
                  (row['eligible'] as List).contains(g.currentMemberId)) {
                title = 'Item approval requested';
              } else if (row['approved'] == true &&
                  row['author'] == g.currentMemberId) {
                title = 'Item approved';
              }
            case 'loan':
              if (row['creator'] != g.currentMemberId) title = 'Loan recorded';
              if (row['returned'] == true) {
                await notifications.invokeMethod<void>('cancel', {'id': key});
                await notifications.invokeMethod<void>('show', {
                  'id': 'returned:$key',
                  'title': 'Loan returned',
                  'body': g.flatName,
                });
                title = null;
              } else if (!isLender(g, row)) {
                title = 'Loan received';
                final due = DateTime.parse(row['due'] as String)
                    .add(const Duration(hours: 9));
                await notifications.invokeMethod<void>('schedule', {
                  'id': key,
                  'title': 'Loan return due',
                  'body': g.flatName,
                  'when': due.millisecondsSinceEpoch,
                });
              }
          }
          if (title != null) {
            await notifications.invokeMethod<void>('show', {
              'id': key,
              'title': title,
              'body': body,
            });
          }
        }
      }
    } on MissingPluginException {
      // Unit tests and non-Android platforms have no notification channel.
    } on PlatformException {
      // Device notification settings may prevent posting.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    profile.removeListener(notifyListeners);
    for (final g in groups.values) {
      g.removeListener(groupChanged);
      transports[g]?.dispose();
      if (g != profile) g.dispose();
    }
    super.dispose();
  }
}
