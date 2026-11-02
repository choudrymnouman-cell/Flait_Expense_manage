import 'package:flutter_test/flutter_test.dart';
import 'package:flait_expense_manage/offline/auto_sync.dart';
import 'package:flait_expense_manage/offline/secure_book.dart';

void main() {
  test('paired identities derive same secret without transmitting it',
      () async {
    final a = await DeviceIdentity.create('Owner'),
        b = await DeviceIdentity.create('Member');
    final x = await AutoHandshake.create(a, 'flat', b.publicId),
        y = await AutoHandshake.create(b, 'flat', a.publicId);
    final mx = await x.announcement('a'), my = await y.announcement('b');
    expect(await x.accept(my), await y.accept(mx));
    final ticket = randomCode();
    expect(
        await x.accept(my, ticket: ticket), await y.accept(mx, ticket: ticket));
    expect(await x.accept(my, ticket: ticket),
        isNot(await x.accept(my, ticket: randomCode())));
    final outsider = await DeviceIdentity.create('Outsider');
    await expectLater(
        () async => x.accept(await outsider.sign(asMap(my['body']))),
        throwsFormatException);
  });
  test('wrong flat and changed signed key are rejected', () async {
    final a = await DeviceIdentity.create('Owner'),
        b = await DeviceIdentity.create('Member');
    final x = await AutoHandshake.create(a, 'flat', b.publicId),
        y = await AutoHandshake.create(b, 'other', a.publicId);
    await expectLater(
        () async => x.accept(await y.announcement('a')), throwsFormatException);
    final z = await AutoHandshake.create(b, 'flat', a.publicId);
    final m = await z.announcement('a');
    m['body']['key'] = randomCode();
    await expectLater(() => x.accept(m), throwsFormatException);
  });
}
