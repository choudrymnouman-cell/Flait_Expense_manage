import 'package:flait_expense_manage/expense_manage/monthly_state.dart';
import 'package:flait_expense_manage/offline/local_database.dart';
import 'package:flait_expense_manage/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

Future<MonthlyState> account(String name) async {
  final db = await newDatabaseFactoryMemory().openDatabase(name);
  final profile = FlaitState(LocalDatabase(db));
  await profile.prepareIdentity(name);
  final app = MonthlyState(profile)..active = false;
  await app.load();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'personal budgets and salary remain independent across months',
    () async {
      final app = await account('Aisha');
      addTearDown(app.dispose);
      await Future.wait([
        app.saveValue('2026-11', 'salary', 100000),
        app.saveValue('2026-11', 'groceryBudget', 30000),
        app.addItem('2026-11', 'grocery', 'Rice', 2500),
        app.addItem('2026-11', 'shopping', 'Shoes', 4300),
      ]);
      expect(app.salary('2026-11') - app.spent('2026-11'), 93200);
      expect(app.budget('2026-11', 'grocery'), 30000);
      expect(app.spent('2026-12'), 0);
      expect(app.salary('2026-12'), 0);
    },
  );

  test(
    'meals charge only the personal share and payments must match total',
    () async {
      final app = await account('Ali');
      final friend = await account('Sara');
      addTearDown(app.dispose);
      addTearDown(friend.dispose);
      final meal = await app.newGroup('meal', name: 'Dinner group');
      await meal.addMember(friend.profile.currentMemberId, 'Sara');
      await expectLater(
        meal.operation('meal_entry', {
          'month': '2026-11',
          'title': 'Dinner',
          'cents': 10001,
          'paid': {meal.currentMemberId: 10000},
        }),
        throwsStateError,
      );
      await meal.operation('meal_entry', {
        'month': '2026-11',
        'title': 'Dinner',
        'cents': 10001,
        'paid': {meal.currentMemberId: 10001},
      });
      final row = meal.view!.monthly.values.single;
      expect(
        app.spent('2026-11'),
        (row['shares'] as Map)[meal.currentMemberId],
      );
      expect(
        (row['shares'] as Map).values.cast<int>().reduce((a, b) => a + b),
        10001,
      );
    },
  );

  test(
    'flat requires every other member and deducts the budget share only once',
    () async {
      final app = await account('Owner');
      final friend = await account('Friend');
      final third = await account('Third');
      addTearDown(app.dispose);
      addTearDown(friend.dispose);
      addTearDown(third.dispose);
      final flat = await app.newGroup('flat', name: 'Home');
      await flat.addMember(friend.profile.currentMemberId, 'Friend');
      await flat.addMember(third.profile.currentMemberId, 'Third');
      await flat.operation('flat_budget', {'month': '2026-11', 'cents': 90000});
      await flat.operation(
          'flat_item',
          {
            'month': '2026-11',
            'title': 'Supplies',
            'cents': 15000,
            'pay': 'individual',
          },
          operationId: 'item-1');
      for (final peer in [friend, third]) {
        final joining = await peer.newGroup('flat');
        await joining.receivePacket(flat.sharedPacket());
        await joining.operation('flat_approve', {
          'month': '2026-11',
          'target': 'item-1',
        });
        await flat.receivePacket(joining.sharedPacket());
        expect(flat.view!.monthly['item-1']!['approved'], peer == third);
      }
      expect(app.spent('2026-11'), 30000);
    },
  );

  test(
      'a private loan goes only to the intended member and importing is idempotent',
      () async {
    final lender = await account('Lender');
    final borrower = await account('Borrower');
    final unrelated = await account('Other');
    addTearDown(lender.dispose);
    addTearDown(borrower.dispose);
    addTearDown(unrelated.dispose);
    final loan = await lender.newGroup(
      'loan',
      name: 'Loan',
      invitee: borrower.profile.currentMemberId,
    );
    await loan.addMember(borrower.profile.currentMemberId, 'Borrower');
    await loan.operation(
        'loan_entry',
        {
          'month': '2026-11',
          'cents': 5000,
          'direction': 'given',
          'due': '2026-12-05',
        },
        operationId: 'loan-1');
    final direct = lender.directFor(borrower.profile.currentMemberId);
    expect(
      lender.directFor(unrelated.profile.currentMemberId)['loans'],
      isEmpty,
    );
    await unrelated.receiveDirect(lender.profile.currentMemberId, direct);
    expect(unrelated.groups, isEmpty);
    await borrower.receiveDirect(lender.profile.currentMemberId, direct);
    await borrower.receiveDirect(lender.profile.currentMemberId, direct);
    expect(borrower.ofKind('loan').length, 1);
    await lender.receiveDirect(
      borrower.profile.currentMemberId,
      borrower.directFor(lender.profile.currentMemberId),
    );
    expect(
      lender.directFor(borrower.profile.currentMemberId)['loans'],
      isEmpty,
    );
    expect(borrower.spent('2026-11'), 5000);
    await loan.operation('loan_return', {
      'month': '2026-12',
      'target': 'loan-1',
    });
    expect(lender.spent('2026-12'), -5000);
  });
}
