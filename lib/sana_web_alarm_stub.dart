// lib/sana_web_alarm_stub.dart
// Non-web stub for Android, iOS, Windows, macOS, and Linux builds.

class SanaWebAlarm {
  static Future<void> unlockAudio() async {}

  /// No-op on non-web. Present so main.dart can call it uniformly.
  static Future<void> rearmAfterVisibilityChange() async {}

  static Future<void> scheduleReminder(Map<String, dynamic> row) async {}

  static Future<void> cancelReminder(String reminderId) async {}

  static Future<void> cancelAllReminders() async {}

  static Future<void> startAlarmSound() async {}

  static Future<void> stopAlarmSound() async {}
}
