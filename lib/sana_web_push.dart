// lib/sana_web_push.dart
//
// SANA Web Push subsystem ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â one codebase, no native install.
// On non-web platforms, every method is a no-op.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

class SanaWebPush {
  static const String vapidPublicKey =
      'BJiPHnMa402Ih_cOgVJwvHriFGLCZPWsgktG-QNLooTZZTaqrHLjVJQ-ODA-CrVZ7PUj2VyEP2EPrP2GTotAgaU';

  static const String _table = 'push_subscriptions';

  static Future<bool> isSubscribed() async {
    if (!kIsWeb) return false;
    try {
      final reg = await web.window.navigator.serviceWorker.ready.toDart;
      final sub = await reg.pushManager.getSubscription().toDart;
      return sub != null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enable(SupabaseClient client) async {
    if (!kIsWeb) return false;
    try {
      if (web.Notification.permission != 'granted') {
        final r = await web.Notification.requestPermission().toDart;
        if (r.toDart != 'granted') return false;
      }

      final reg = await web.window.navigator.serviceWorker.ready.toDart;

      web.PushSubscription? sub =
          await reg.pushManager.getSubscription().toDart;
      sub ??= await reg.pushManager
          .subscribe(
            web.PushSubscriptionOptionsInit(
              userVisibleOnly: true,
              applicationServerKey: _urlB64ToUint8Array(vapidPublicKey),
            ),
          )
          .toDart;

      final jsonJS = sub.toJSON();
      final endpoint = jsonJS.endpoint;
      final keys = jsonJS.keys;
      final p256dh = (keys.getProperty('p256dh'.toJS) as JSString).toDart;
      final auth = (keys.getProperty('auth'.toJS) as JSString).toDart;

      final user = client.auth.currentUser;
      if (user == null || endpoint.isEmpty) return false;

      await client.from(_table).upsert({
        'user_id': user.id,
        'endpoint': endpoint,
        'p256dh': p256dh,
        'auth': auth,
        'user_agent': web.window.navigator.userAgent,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'endpoint');

      return true;
    } catch (e) {
      debugPrint('SanaWebPush enable error: $e');
      return false;
    }
  }

  static Future<void> disable(SupabaseClient client) async {
    if (!kIsWeb) return;
    try {
      final reg = await web.window.navigator.serviceWorker.ready.toDart;
      final sub = await reg.pushManager.getSubscription().toDart;
      if (sub == null) return;

      final jsonJS = sub.toJSON();
      final endpoint = jsonJS.endpoint;

      await sub.unsubscribe().toDart;

      if (endpoint.isNotEmpty) {
        await client.from(_table).delete().eq('endpoint', endpoint);
      }
    } catch (e) {
      debugPrint('SanaWebPush disable error: $e');
    }
  }

  static JSAny _urlB64ToUint8Array(String s) {
    final pad = '=' * ((4 - s.length % 4) % 4);
    final bytes = base64Decode(
      (s + pad).replaceAll('-', '+').replaceAll('_', '/'),
    );
    return bytes.toJS;
  }
}
