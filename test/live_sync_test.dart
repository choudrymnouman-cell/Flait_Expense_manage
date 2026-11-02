import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:flait_expense_manage/offline/secure_book.dart';
import 'package:flait_expense_manage/offline/local_database.dart';
import 'package:flait_expense_manage/offline/live_sync.dart';
import 'package:flait_expense_manage/offline/auto_sync.dart';
import 'package:flait_expense_manage/state/app_state.dart';
import 'offline_book_test.dart' as fixture show device, pair;

Future<void> until(bool Function() predicate, String Function() detail) async {
  for (var i = 0; i < 450; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Live exchange timed out: ${detail()}');
}

void main() {
  test('live encrypted relay admits a device and syncs queued offline claims',
      () async {
    Future<FlaitState> device(String name) async {
      final db =
          await databaseFactoryMemory.openDatabase('live-${randomCode()}');
      final state = FlaitState(LocalDatabase(db));
      await state.load();
      await state.prepareIdentity(name);
      return state;
    }

    final owner = await device('Test owner'),
        member = await device('Test member');
    await owner.createFlat('Ephemeral device test');
    Future<void> exchange({bool admit = false}) async {
      final host = SyncSession(owner), join = SyncSession(member, host: false);
      try {
        await host.start();
        await join.start(invite: host.code);
        if (admit) {
          await until(() => host.awaitingAdmission, () => host.status);
          await host.approveMember();
        }
        await until(() => host.completed && join.completed,
            () => 'host: ${host.status}; join: ${join.status}');
      } finally {
        await host.close();
        await join.close();
        host.dispose();
        join.dispose();
      }
    }

    await exchange(admit: true);
    expect(member.book!.id, owner.book!.id);
    expect(member.members, hasLength(2));
    // Both relay clients are now disposed. This write has no transport.
    await member.submitExpense(
        title: 'Offline test claim',
        description: 'Synthetic test only',
        category: 'Other',
        amount: 12.34);
    expect(member.queuedCount, 1);
    expect(owner.expenses, isEmpty);
    final at = member.expenses.single.createdAt;
    final ownerAuto = AutoSync(owner), memberAuto = AutoSync(member);
    try {
      await until(() => owner.expenses.isNotEmpty && member.queuedCount == 0,
          () => '${ownerAuto.status} / ${memberAuto.status}');
      expect(owner.expenses.single.createdAt, at);
      memberAuto.setActive(false);
      await member.submitExpense(
          title: 'While offline',
          description: 'Resume test',
          category: 'Other',
          amount: 4.56);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(member.queuedCount, 1);
      memberAuto.setActive(true);
      await until(() => owner.expenses.length == 2 && member.queuedCount == 0,
          () => '${ownerAuto.status} / ${memberAuto.status}');
    } finally {
      ownerAuto.dispose();
      memberAuto.dispose();
    }
    expect(owner.expenses.any((e) => e.amount == 12.34), true);
    expect(member.queuedCount, 0);
    expect(canonical(owner.book!.toJson()), canonical(member.book!.toJson()));
  },
      skip: !const bool.fromEnvironment('FLAIT_LIVE_TEST'),
      timeout: const Timeout(Duration(minutes: 3)));
  test('automatic owner handoff reaches a third member with stale authority',
      () async {
    final owner = await fixture.device('Live owner'),
        next = await fixture.device('Live successor'),
        third = await fixture.device('Live third');
    await owner.createFlat('Synthetic handoff test');
    await fixture.pair(owner, next);
    await fixture.pair(owner, third);
    await next.receivePacket(owner.sharedPacket());
    final routes = [AutoSync(owner), AutoSync(next), AutoSync(third)];
    try {
      await owner.offerOwnership(next.currentMemberId);
      await until(
          () => next.view!.transferOffer != null,
          () =>
              'owners: ${owner.book!.owner == next.currentMemberId}/${next.isOwner}/${third.book!.owner == next.currentMemberId}; expenses: ${owner.expenses.length}/${third.expenses.length}; ' +
              routes.map((r) => r.status).join(' / '));
      await next.acceptOwnership();
      await until(
          () =>
              owner.book!.owner == next.currentMemberId &&
              third.book!.owner == next.currentMemberId &&
              next.isOwner,
          () =>
              'owners: ${owner.book!.owner == next.currentMemberId}/${next.isOwner}/${third.book!.owner == next.currentMemberId}; expenses: ${owner.expenses.length}/${third.expenses.length}; ' +
              routes.map((r) => r.status).join(' / '));
      await next.submitExpense(
          title: 'After owner handoff',
          description: 'Synthetic only',
          category: 'Other',
          amount: 6);
      await until(
          () => third.expenses.isNotEmpty && owner.expenses.isNotEmpty,
          () =>
              'owners: ${owner.book!.owner == next.currentMemberId}/${next.isOwner}/${third.book!.owner == next.currentMemberId}; expenses: ${owner.expenses.length}/${third.expenses.length}; ' +
              routes.map((r) => r.status).join(' / '));
      expect((await third.book!.verify()).owner, next.currentMemberId);
    } finally {
      for (final r in routes) {
        r.dispose();
      }
    }
  },
      skip: !const bool.fromEnvironment('FLAIT_LIVE_TEST'),
      timeout: const Timeout(Duration(minutes: 3)));
}
