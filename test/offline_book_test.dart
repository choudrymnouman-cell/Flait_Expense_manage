import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flait_expense_manage/models/flat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:flait_expense_manage/offline/secure_book.dart';
import 'package:flait_expense_manage/offline/local_database.dart';
import 'package:flait_expense_manage/state/app_state.dart';

Future<FlaitState> device(String name) async {
  final db =
      await databaseFactoryMemory.openDatabase('test-$name-${randomCode()}');
  final state = FlaitState(LocalDatabase(db));
  await state.load();
  await state.prepareIdentity(name);
  return state;
}

Future<void> pair(FlaitState owner, FlaitState member) async {
  await owner.addMember(member.currentMemberId, member.identity!.name);
  await member.receivePacket(owner.sharedPacket());
}

void main() {
  test('owner can create, record and reload with no network clients', () async {
    final state = await device('Owner');
    await state.createFlat('Offline flat');
    await state.recordContribution(100.25, 'Funds',
        contributorId: state.currentMemberId, requestId: 'stable-id');
    await state.recordContribution(100.25, 'Funds',
        contributorId: state.currentMemberId, requestId: 'stable-id');
    expect(state.ledger, hasLength(1));
    expect(state.poolBalance, 100.25);
    final reload = FlaitState(state.storage);
    await reload.load();
    expect(reload.currentMemberId, state.currentMemberId);
    expect(reload.poolBalance, 100.25);
  });
  test('member drafts persist offline and merge exactly once with owner',
      () async {
    final owner = await device('Owner'), member = await device('Member');
    await owner.createFlat('Flat');
    await pair(owner, member);
    await member.submitExpense(
        title: 'Groceries',
        description: 'Milk',
        category: 'Groceries',
        amount: 55.25);
    expect(member.queuedCount, 1);
    expect(owner.expenses, isEmpty);
    final reloaded = FlaitState(member.storage);
    await reloaded.load();
    expect(reloaded.queuedCount, 1);
    await owner.receivePacket(reloaded.sharedPacket());
    await owner.receivePacket(reloaded.sharedPacket());
    expect(owner.expenses, hasLength(1));
    expect(owner.queuedCount, 0);
    await member.receivePacket(owner.sharedPacket());
    expect(member.queuedCount, 0);
    expect(member.expenses.single.amount, 55.25);
  });
  test(
      'self vote denied, quorum confirmed by owner, paid once with balance guard',
      () async {
    final owner = await device('Owner'), member = await device('Member');
    await owner.createFlat('Flat');
    await pair(owner, member);
    await member.submitExpense(
        title: 'Soap', description: '', category: 'Household', amount: 60);
    await owner.receivePacket(member.sharedPacket());
    await member.receivePacket(owner.sharedPacket());
    final id = owner.expenses.single.id;
    await expectLater(member.vote(id, true), throwsStateError);
    await owner.vote(id, true);
    await expectLater(owner.markPaid(id), throwsStateError);
    await owner.recordContribution(100, 'Funds',
        contributorId: member.currentMemberId, requestId: 'funds');
    await owner.markPaid(id);
    await expectLater(owner.markPaid(id), throwsStateError);
    expect(owner.poolBalance, 40);
    expect(owner.ledger.first.memberId, member.currentMemberId);
  });
  test('two queued treasurer payments cannot overdraft the owner journal',
      () async {
    final owner = await device('Owner'), member = await device('Member');
    await owner.createFlat('Flat');
    await pair(owner, member);
    await owner.setMemberRole(member.currentMemberId, MemberRole.treasurer);
    await owner.recordContribution(100, 'Funds',
        contributorId: member.currentMemberId, requestId: 'funds');
    await member.receivePacket(owner.sharedPacket());
    for (var i = 0; i < 2; i++) {
      await member.submitExpense(
          title: 'Expense $i', description: '', category: 'Other', amount: 70);
    }
    await owner.receivePacket(member.sharedPacket());
    for (final e in owner.expenses) {
      await owner.vote(e.id, true);
    }
    await member.receivePacket(owner.sharedPacket());
    for (final e in member.expenses) {
      await member.markPaid(e.id);
    }
    expect(member.poolBalance, 100);
    expect(member.queuedCount, 2);
    await owner.receivePacket(member.sharedPacket());
    expect(owner.poolBalance, 30);
    expect(owner.view!.rejected, hasLength(1));
  });
  test('tampering, forged membership and history forks are rejected', () async {
    final owner = await device('Owner');
    await owner.createFlat('Flat');
    await owner.recordContribution(1, 'Funds',
        contributorId: owner.currentMemberId, requestId: 'one');
    final json = asMap(jsonDecode(jsonEncode(owner.book!.toJson())));
    asMap(asMaps(json['records']).first['body']);
    final records = json['records'] as List;
    (records.first as Map)['sig'] = 'AAAA';
    await expectLater(SecureBook.fromJson(json), throwsFormatException);
    final outsider = await DeviceIdentity.create('Outsider');
    final forged = await makeProposal(outsider, owner.book!, 'contribution', {
      'cents': 100,
      'member': owner.currentMemberId,
      'description': 'Forged'
    });
    await expectLater(
        owner.book!.append(owner.identity!, forged), throwsStateError);
    final branch = SecureBook(owner.book!.manifest, []);
    final draft = await makeProposal(owner.identity!, branch, 'expense', {
      'cents': 100,
      'title': 'Fork',
      'description': '',
      'category': 'Other'
    });
    final fork = await branch.append(owner.identity!, draft);
    await expectLater(owner.book!.merge(fork), throwsStateError);
  });
  test('stale browser window cannot overwrite committed local data', () async {
    final a = await device('Owner');
    final b = FlaitState(a.storage);
    await b.load();
    await a.createFlat('Flat');
    await expectLater(b.createFlat('Other flat'), throwsStateError);
    await b.load();
    expect(b.flatId, a.flatId);
  });
  test('encrypted backups round-trip; wrong password fails without replacement',
      () async {
    final a = await device('Owner');
    await a.createFlat('Flat');
    final encrypted = await a.exportBackup('a long unique password');
    expect(encrypted, isNot(contains('Owner')));
    final fresh = await device('Fresh');
    await expectLater(fresh.restoreBackup(encrypted, 'wrong password'),
        throwsA(isA<SecretBoxAuthenticationError>()));
    expect(fresh.book, isNull);
    await fresh.restoreBackup(encrypted, 'a long unique password');
    expect(fresh.flatId, a.flatId);
    expect(fresh.currentMemberId, a.currentMemberId);
  });
}
