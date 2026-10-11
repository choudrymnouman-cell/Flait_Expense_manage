import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';

const supabaseUrl = 'https://rrkzsrotgxqvrllilzbj.supabase.co';
const supabasePublishableKey = 'sb_publishable_hEewjesFCyCW7IYAeJCo6A_WLizCGGQ';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const FlaitAuthApp());
}
