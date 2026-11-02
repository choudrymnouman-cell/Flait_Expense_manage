import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';

class AppPreferences extends InheritedNotifier<FlaitState> {
  const AppPreferences(
      {super.key, required FlaitState state, required super.child})
      : super(notifier: state);
  static FlaitState? of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AppPreferences>()?.notifier;
}

String tr(BuildContext c, String en, String ur) =>
    AppPreferences.of(c)?.preferences['language'] == 'ur' ? ur : en;

class PinSecurity {
  static Future<Map<String, dynamic>> create(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw ArgumentError('Use 6–12 digits.');
    }
    final salt = await AesGcm.with256bits().newSecretKey();
    final bytes = await salt.extractBytes();
    final hash = await _derive(pin, bytes);
    return {'salt': base64Encode(bytes), 'hash': base64Encode(hash)};
  }

  static Future<List<int>> _derive(String pin, List<int> salt) async =>
      (await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256)
              .deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt))
          .extractBytes();
  static Future<bool> check(String pin, Map<String, dynamic> record) async {
    final actual = await _derive(pin, base64Decode(record['salt'] as String));
    final expected = base64Decode(record['hash'] as String);
    var diff = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }
}

String localize(BuildContext context, String value) =>
    AppPreferences.of(context)?.preferences['language'] == 'ur'
        ? (_urdu[value] ?? value)
        : value;

class AppText extends StatelessWidget {
  const AppText(this.data,
      {super.key,
      this.style,
      this.textAlign,
      this.maxLines,
      this.overflow,
      this.softWrap});
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  @override
  Widget build(BuildContext context) => Text(localize(context, data),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap);
}

const _urdu = <String, String>{
  'Dashboard': 'خلاصہ',
  'New expense': 'نیا خرچہ',
  'Add': 'شامل کریں',
  'Approvals': 'منظوریاں',
  'Ledger': 'کھاتہ',
  'Settings': 'ترتیبات',
  'New expense request': 'نیا خرچہ',
  'Date and time are added automatically when you save.':
      'محفوظ کرتے وقت تاریخ اور وقت خود شامل ہوں گے۔',
  'Purchase details': 'خریداری کی تفصیل',
  'Category': 'قسم',
  'Description': 'تفصیل',
  'Submit for approval': 'منظوری کے لیے بھیجیں',
  'Saving…': 'محفوظ ہو رہا ہے…',
  'Save': 'محفوظ کریں',
  'Cancel': 'منسوخ کریں',
  'Close': 'بند کریں',
  'Confirm': 'تصدیق کریں',
  'Retry': 'دوبارہ کوشش کریں',
  'Local identity, sharing and backups.': 'مقامی شناخت، اشتراک اور بیک اپ۔',
  'Internet sharing & members': 'انٹرنیٹ اشتراک اور ارکان',
  'Flatmates': 'فلیٹ کے ارکان',
  'Member': 'رکن',
  'Treasurer': 'خزانچی',
  'Device backup': 'ڈیوائس بیک اپ',
  'Export encrypted backup': 'محفوظ بیک اپ بنائیں',
  'Open internet sync': 'انٹرنیٹ سنک کھولیں',
  'Waiting for owner confirmation': 'مالک کی تصدیق کا انتظار',
  'Owner review results': 'مالک کے جائزے کے نتائج',
  'Privacy': 'رازداری',
  'Available pool balance': 'دستیاب مشترکہ رقم',
  'Pending requests': 'زیرِ التوا درخواستیں',
  'Total contributions': 'کل جمع شدہ رقم',
  'Add expense': 'خرچہ شامل کریں',
  'Recent requests': 'حالیہ درخواستیں',
  'Needs your decision': 'آپ کے فیصلے کے منتظر',
  'Approved · awaiting payment': 'منظور شدہ، ادائیگی کا انتظار',
  'Record payment': 'ادائیگی درج کریں',
  'Approve': 'منظور کریں',
  'Reject': 'مسترد کریں',
  'No requests are waiting for a decision.':
      'کوئی درخواست فیصلے کی منتظر نہیں۔',
  'Expense & history': 'خرچہ اور سابقہ ریکارڈ',
  'Correct request': 'درخواست درست کریں',
  'Correct pending expense': 'زیرِ التوا خرچہ درست کریں',
  'Cancel with reason': 'وجہ کے ساتھ منسوخ کریں',
  'Cost allocation': 'اخراجات کی تقسیم',
  'Signed audit history': 'تصدیق شدہ سابقہ ریکارڈ',
  'Details, shares & corrections': 'تفصیل، حصے اور درستگی',
  'All members': 'تمام ارکان',
  'All categories': 'تمام اقسام',
  'All statuses': 'تمام حالتیں',
  'Clear filters': 'فلٹر ختم کریں',
  'This month': 'اس ماہ',
  'Date range': 'تاریخ منتخب کریں',
  'Export CSV': 'سی ایس وی برآمد کریں',
  'Export PDF': 'پی ڈی ایف برآمد کریں',
  'No matching expenses. Clear filters or add your first expense.':
      'کوئی خرچہ نہیں ملا۔ فلٹر ہٹائیں یا پہلا خرچہ شامل کریں۔',
  'Equal shares': 'برابر حصے',
  'Percentage (total 100%)': 'فیصد، کل ۱۰۰ فیصد',
  'Custom amounts': 'اپنی مقرر کردہ رقوم',
  'Share receipt with flatmates': 'رسید ارکان کے ساتھ شیئر کریں',
  'Replace receipt': 'رسید بدلیں',
  'Save correction': 'درستگی محفوظ کریں',
  'Monthly bill template': 'ماہانہ بل کا نمونہ',
  'Recurring monthly bills': 'بار بار آنے والے ماہانہ بل',
  'Add bill': 'بل شامل کریں',
  'Submit this month': 'اس ماہ کی درخواست بنائیں',
  'Remove local template': 'مقامی نمونہ ہٹائیں',
  'Monthly request saved.': 'ماہانہ درخواست محفوظ ہو گئی۔',
  'Add rent, electricity or internet as a monthly template.':
      'کرایہ، بجلی یا انٹرنیٹ کا ماہانہ بل شامل کریں۔',
  'Membership & owner recovery': 'رکنیت اور مالک کی ریکوری',
  'Owner transfer offered to': 'ملکیت کی منتقلی کی پیشکش',
  'Accept owner role': 'مالک کا کردار قبول کریں',
  'Cancel transfer offer': 'منتقلی کی پیشکش منسوخ کریں',
  'Moving to a new phone': 'نئے فون پر منتقل ہونا',
  'Revoke device': 'ڈیوائس کی رسائی بند کریں',
  'Reactivate device': 'ڈیوائس دوبارہ فعال کریں',
  'Offer owner transfer': 'ملکیت منتقل کرنے کی پیشکش',
  'App PIN lock': 'ایپ کا پن لاک',
  'Off': 'بند',
  'Fingerprint / device passcode': 'فنگر پرنٹ یا فون کا پاس کوڈ',
  'Local database encrypted': 'مقامی ڈیٹابیس محفوظ ہے',
  'Browser-local storage': 'براؤزر کا مقامی ریکارڈ',
  'Enable app lock': 'ایپ لاک فعال کریں',
  'Change / remove app lock': 'ایپ لاک بدلیں یا ہٹائیں',
  'Remove lock': 'لاک ہٹائیں',
  'Save PIN': 'پن محفوظ کریں',
  'Privacy policy & support': 'رازداری کی پالیسی اور مدد',
  'Sync status': 'سنک کی صورتحال',
  'Waiting operations': 'منتظر کارروائیاں',
  'No queued changes.': 'کوئی تبدیلی منتظر نہیں۔',
  'First pairing / manual recovery': 'پہلی جوڑی یا دستی ریکوری',
  'Your flat. Your devices. Works offline.':
      'آپ کا فلیٹ، آپ کی ڈیوائسز، آف لائن کام۔',
  'Create flat on this device': 'اس ڈیوائس پر فلیٹ بنائیں',
  'Join a flat using an internet sync code': 'انٹرنیٹ کوڈ سے فلیٹ میں شامل ہوں',
  'Restore encrypted backup': 'محفوظ بیک اپ بحال کریں',
  'Internet sync': 'انٹرنیٹ سنک',
  'Create a sync code': 'سنک کوڈ بنائیں',
  'Copy sync code': 'سنک کوڈ کاپی کریں',
  'Admit this flatmate & sync': 'اس رکن کو شامل کریں اور سنک کریں',
  'Encrypted local backup': 'محفوظ مقامی بیک اپ',
  'Restore device backup': 'ڈیوائس بیک اپ بحال کریں',
  'Choose backup & restore': 'بیک اپ منتخب کریں اور بحال کریں',
  'Save encrypted file': 'محفوظ فائل بنائیں',
  'Working…': 'کام ہو رہا ہے…',
  'Record completed payment': 'مکمل شدہ ادائیگی درج کریں',
  'Record': 'درج کریں',
  'Confirmed settlement history': 'تصدیق شدہ ادائیگیوں کا ریکارڈ',
  'Backup reminder: export a fresh backup':
      'بیک اپ یاددہانی: نیا بیک اپ بنائیں',
  'Backup reminder: up to date': 'بیک اپ تازہ ہے',
};
