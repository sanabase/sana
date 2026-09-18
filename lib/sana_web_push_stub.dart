// lib/sana_web_push_stub.dart
// Non-web stub for SanaWebPush.
// Used automatically on Android, iOS, Windows, macOS, Linux.

import 'package:supabase_flutter/supabase_flutter.dart';

class SanaWebPush {
  static Future<bool> isSubscribed() async => false;
  static Future<bool> enable(SupabaseClient client) async => false;
  static Future<String> enableVerbose(SupabaseClient client) async => 'NOT_WEB';
  static Future<void> disable(SupabaseClient client) async {}
  static void closeApp() {}

  static String? browserTimeZone() => null;
}
