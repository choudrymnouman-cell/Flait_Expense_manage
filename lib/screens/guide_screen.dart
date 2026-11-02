import 'package:flutter/material.dart';
import '../services/app_preferences.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: AppText(
              tr(context, 'How Flait works', 'فلیٹ کیسے کام کرتا ہے؟'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.home_work_outlined, size: 64),
        AppText(
            tr(context, '1. Create or join your flat',
                '۱۔ اپنا فلیٹ بنائیں یا شامل ہوں'),
            style: Theme.of(context).textTheme.titleLarge),
        AppText(tr(
            context,
            'The owner creates a flat offline. New members pair once using a private code and explicit owner confirmation. No email account is required.',
            'مالک آف لائن فلیٹ بناتا ہے۔ نیا رکن ایک بار کوڈ سے شامل ہوتا ہے اور مالک تصدیق کرتا ہے۔ ای میل اکاؤنٹ ضروری نہیں۔')),
        const SizedBox(height: 20),
        AppText(
            tr(context, '2. Record and split expenses',
                '۲۔ خرچہ درج اور تقسیم کریں'),
            style: Theme.of(context).textTheme.titleLarge),
        AppText(tr(
            context,
            'Choose equal, percentage or custom shares. Requests and votes can wait offline; only owner-confirmed records affect shared balances. Reimbursement from the pool and personal settlements are separate records.',
            'برابر، فیصد یا اپنی رقوم کے حصے منتخب کریں۔ درخواستیں اور ووٹ آف لائن رہ سکتے ہیں۔ مشترکہ بیلنس میں مالک کے تصدیق شدہ ریکارڈ شامل ہوتے ہیں۔ مشترکہ فنڈ سے واپسی اور ذاتی ادائیگی الگ درج ہوتی ہیں۔')),
        const SizedBox(height: 20),
        AppText(
            tr(context, '3. Sync and protect your copy',
                '۳۔ سنک اور بیک اپ محفوظ کریں'),
            style: Theme.of(context).textTheme.titleLarge),
        AppText(tr(
            context,
            'Keep paired apps open online for automatic encrypted exchange. The owner must be available to confirm queued work. Export an encrypted backup weekly and before changing phones. There is no server recovery; use only one active owner device.',
            'خودکار محفوظ سنک کے لیے دونوں ایپس انٹرنیٹ پر کھلی رکھیں۔ منتظر تبدیلیاں مالک تصدیق کرے گا۔ ہفتہ وار اور فون بدلنے سے پہلے محفوظ بیک اپ بنائیں۔ سرور سے ریکوری نہیں ہوتی؛ مالک کی صرف ایک ڈیوائس فعال رکھیں۔')),
        const SizedBox(height: 20),
        const AppText(
            'Monthly bills are templates for review, not automatic payments. This app does not transfer bank funds. A receipt stays local unless you explicitly share it. Previously shared records cannot be erased from somebody else’s device.'),
      ]));
}
