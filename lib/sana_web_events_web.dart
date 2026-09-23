import 'dart:js_interop';
import 'package:web/web.dart' as web;

class SanaWebEvents {
  static void installPopStateListener(
    void Function(String?) onReminder,
  ) {
    try {
      web.window.addEventListener(
        'popstate',
        (web.Event _) {
          onReminder(Uri.base.queryParameters['reminder']);
        }.toJS,
      );
    } catch (_) {}
  }

  static void installServiceWorkerMessageListener(
    void Function(Map<dynamic, dynamic>) onMessage,
  ) {
    try {
      web.window.navigator.serviceWorker.addEventListener(
        'message',
        (web.Event event) {
          try {
            final msg = event as web.MessageEvent;
            final data = msg.data;
            if (data == null) return;
            final map = data.dartify();
            if (map is Map) {
              onMessage(map);
            }
          } catch (_) {}
        }.toJS,
      );
    } catch (_) {}
  }
}
