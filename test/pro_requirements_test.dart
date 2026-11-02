import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:flait_expense_manage/offline/local_database.dart';
import 'package:flait_expense_manage/offline/secure_book.dart';
import 'package:flait_expense_manage/services/app_preferences.dart';
import 'package:flait_expense_manage/services/report_export.dart';
import 'package:flait_expense_manage/services/settlement_service.dart';
import 'package:flait_expense_manage/state/app_state.dart';
import 'offline_book_test.dart' show device, pair;

void main() {
  test('equal/weighted/custom allocation conserves every cent', () {
    for (var n = 1; n < 350; n++) {
      final r = allocateShares(n, {'c': 1, 'a': 1, 'b': 1});
      expect(r.values.fold(0, (a, b) => a + b), n);
      expect(
          r.values.reduce((a, b) => a > b ? a : b) -
              r.values.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1));
    }
    expect(allocateShares(1001, {'a': 25, 'b': 75}), {'a': 250, 'b': 751});
    expect(() => allocateShares(100, {'a': 40, 'b': 50}, exact: true),
        throwsArgumentError);
  });
  test(
      'dues account for costs, pool contributions, reimbursements and direct settlements once',
      () async {
    final o = await device('Owner'), m = await device('Member');
    await o.createFlat('Flat');
    await pair(o, m);
    await o.submitExpense(
        title: 'Shared groceries',
        description: '',
        category: 'Groceries',
        amount: 100);
    await m.receivePacket(o.sharedPacket());
    await m.vote(o.expenses.single.id, true);
    await o.receivePacket(m.sharedPacket());
    expect(o.dues[o.currentMemberId], 5000);
    expect(o.dues[m.currentMemberId], -5000);
    await o.recordContribution(100, 'Funds',
        contributorId: m.currentMemberId, requestId: 'pool');
    expect(o.dues[m.currentMemberId], 5000);
    await o.markPaid(o.expenses.single.id);
    expect(o.dues[o.currentMemberId], -5000);
    expect(o.poolBalance, 0);
    await o.recordSettlement(o.currentMemberId, m.currentMemberId, 50);
    expect(o.dues.values.every((v) => v == 0), isTrue);
    await expectLater(
        o.recordSettlement(o.currentMemberId, m.currentMemberId, 1),
        throwsStateError);
  });
  test(
      'correction clears votes, keeps history, and rejects a stale revision vote',
      () async {
    final o = await device('Owner'),
        b = await device('Bob'),
        c = await device('Carol');
    await o.createFlat('Flat');
    await pair(o, b);
    await pair(o, c);
    await o.submitExpense(
        title: 'Groceries',
        description: 'old',
        category: 'Groceries',
        amount: 30);
    await b.receivePacket(o.sharedPacket());
    await c.receivePacket(o.sharedPacket());
    await b.vote(o.expenses.single.id, true);
    await o.receivePacket(b.sharedPacket());
    final old = o.expenses.single;
    await o.amendExpense(old,
        title: 'Corrected groceries',
        description: 'new',
        category: 'Groceries',
        amount: 60,
        shares: allocateShares(6000, {for (final m in o.members) m.id: 1}),
        reason: 'Correct receipt total');
    await c.vote(old.id, true);
    await o.receivePacket(c.sharedPacket());
    expect(o.expenses.single.votes, isEmpty);
    expect(o.expenses.single.revision, 1);
    expect(o.view!.history[old.id], hasLength(2));
    expect(o.view!.rejected, isNotEmpty);
    await o.cancelExpense(old.id, 'Entered twice');
    expect(o.expenses.single.cancelled, isTrue);
    expect(o.view!.history[old.id], hasLength(3));
  });
  test('revoked device cannot contribute a later accepted operation', () async {
    final o = await device('Owner'), m = await device('Member');
    await o.createFlat('Flat');
    await pair(o, m);
    await m.submitExpense(
        title: 'Offline claim', description: '', category: 'Other', amount: 5);
    await o.setMemberActive(m.currentMemberId, false);
    await o.receivePacket(m.sharedPacket());
    expect(o.expenses, isEmpty);
    expect(o.view!.rejected, isNotEmpty);
    expect(o.members.last.active, isFalse);
  });
  test(
      'owner transfer requires recipient signature and then changes journal authority',
      () async {
    final o = await device('Owner'), m = await device('Member');
    await o.createFlat('Flat');
    await pair(o, m);
    await o.offerOwnership(m.currentMemberId);
    await m.receivePacket(o.sharedPacket());
    await expectLater(
        o.operation('transfer_accept', {'offer': o.view!.transferOffer}),
        throwsStateError);
    await m.acceptOwnership();
    await o.receivePacket(m.sharedPacket());
    await m.receivePacket(o.sharedPacket());
    expect(m.isOwner, isTrue);
    expect(o.isOwner, isFalse);
    await m.recordContribution(20, 'New owner funds',
        contributorId: m.currentMemberId, requestId: 'new-owner');
    await o.receivePacket(m.sharedPacket());
    expect(o.poolBalance, 20);
    expect((await o.book!.verify()).owner, m.currentMemberId);
  });
  test('recurring monthly submissions are idempotent before and after sync',
      () async {
    final o = await device('Owner'), m = await device('Member');
    await o.createFlat('Flat');
    await pair(o, m);
    final bill = {
      'id': 'rent',
      'title': 'Rent',
      'cents': 10000,
      'category': 'Rent',
      'day': 1
    };
    await m.submitRecurring(bill, DateTime(2026, 11));
    await expectLater(
        m.submitRecurring(bill, DateTime(2026, 11)), throwsStateError);
    await o.receivePacket(m.sharedPacket());
    await m.receivePacket(o.sharedPacket());
    await expectLater(
        m.submitRecurring(bill, DateTime(2026, 11)), throwsStateError);
    await m.submitRecurring(bill, DateTime(2026, 12));
    expect(m.queuedCount, 1);
  });
  test('encrypted local document has no plain identity and rejects wrong key',
      () async {
    final db = await databaseFactoryMemory.openDatabase('encrypted-test');
    final key = await AesGcm.with256bits().newSecretKey();
    final storage = LocalDatabase(db, encryptionKey: key),
        s = FlaitState(LocalDatabase(db, encryptionKey: key));
    await s.load();
    await s.prepareIdentity('Private Name');
    await s.createFlat('Private Flat');
    final raw =
        await stringMapStoreFactory.store('flait_v2').record('device').get(db);
    expect(jsonEncode(raw).contains('Private'), isFalse);
    expect(raw!['encrypted'], true);
    expect((await storage.read())!['identity'], isNotNull);
    await expectLater(
        LocalDatabase(db,
                encryptionKey: await AesGcm.with256bits().newSecretKey())
            .read(),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });
  test('local-only receipt and PIN never enter sync; restore excludes app lock',
      () async {
    final o = await device('Owner');
    await o.createFlat('Flat');
    const receipt =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aX8AAAAASUVORK5CYII=';
    await o.saveLocalReceipt('local-receipt', receipt);
    final pin = await PinSecurity.create('123456');
    await o.setPreference('pin', pin);
    expect(await PinSecurity.check('123456', pin), true);
    expect(await PinSecurity.check('654321', pin), false);
    final shared = canonical(o.sharedPacket());
    expect(shared.contains(receipt), false);
    expect(shared.contains(pin['hash'] as String), false);
    final text = await o.exportBackup('backup password long');
    final target = await device('Replacement');
    await target.restoreBackup(text, 'backup password long');
    expect(target.localReceipts['local-receipt'], receipt);
    expect(target.preferences['pin'], isNull);
  });
  test('lost-device revocation preserves balances without requiring write-off',
      () async {
    final o = await device('Owner'), m = await device('Member');
    await o.createFlat('Flat');
    await pair(o, m);
    await o.recordContribution(50, 'Member deposit',
        contributorId: m.currentMemberId, requestId: 'lost-deposit');
    await expectLater(
        o.setMemberActive(m.currentMemberId, false), throwsStateError);
    await o.revokeDevice(m.currentMemberId);
    expect(o.view!.members[m.currentMemberId]!.active, false);
    expect(o.dues[m.currentMemberId], 5000);
    expect(o.poolBalance, 50);
  });
  test('CSV export prevents spreadsheet formula injection and quotes commas',
      () {
    expect(csvCell('=CMD()'), '"\'=CMD()"');
    expect(csvCell('hello, "world"'), '"hello, ""world"""');
  });
}
