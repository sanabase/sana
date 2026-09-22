// lib/sana_web_alarm_web.dart
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class SanaWebAlarm {
  static final Map<String, List<Timer>> _reminderTimers =
      <String, List<Timer>>{};
  static final Map<String, Map<String, dynamic>> _storedRows = {};
  static web.HTMLAudioElement? _audio;
  static bool _audioUnlocked = false;
  static bool _visibilityHooked = false;
  static const String _unlockKey = 'sana_audio_unlocked_v1';

  // Embedded 880Hz WAV beep — 100% offline, zero internet or asset file dependency.
  static const String _alarmWavBase64 =
      'UklGRvQHAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YdAHAAB/ss7FnGY7MEh6rszHoWs+L0V1qsvJpnBBL0FwpsnLqnVFLz5rocfMrnpIMDtmnMXOsn9MMDlimMPOtoRQMjddk8DPuYlUMzVYjr3PvY5YNTNUibnPwJNdNzJQhLbOw5hiOTBMf7LOxZxmOzBIeq7Mx6FrPi9FdarLyaZwQS9BcKbJy6p1RS8+a6HHzK56SDA7ZpzFzrJ/TDA5YpjDzraEUDI3XZPAz7mJVDM1WI69z72OWDUzVIm5z8CTXTcyUIS2zsOYYjkwTH+yzsWcZjswSHquzMehaz4vRXWqy8mmcEEvQXCmycuqdUUvPmuhx8yuekgwO2acxc6yf0wwOWKYw862hFAyN12TwM+5iVQzNViOvc+9jlg1M1SJuc/Ak103MlCEts7DmGI5MEx/ss7FnGY7MEh6rszHoWs+L0V1qsvJpnBBL0FwpsnLqnVFLz5rocfMrnpIMDtmnMXOsn9MMDlimMPOtoRQMjddk8DPuYlUMzVYjr3PvY5YNTNUibnPwJNdNzJQhLbOw5hiOTBMf7LOxZxmOzBIeq7Mx6FrPi9FdarLyaZwQS9BcKbJy6p1RS8+a6HHzK56SDA7ZpzFzrJ/TDA5YpjDzraEUDI3XZPAz7mJVDM1WI69z72OWDUzVIm5z8CTXTcyUIS2zsOYYjkwTH+yzsWcZjswSHquzMehaz4vRXWqy8mmcEEvQXCmycuqdUUvPmuhx8yuekgwO2acxc6yf0wwOWKYw862hFAyN12TwM+5iVQzNViOvc+9jlg1M1SJuc/Ak103MlCEts7DmGI5MEx/ss7FnGY7MEh6rszHoWs+L0V1qsvJpnBBL0FwpsnLqnVFLz5rocfMrnpIMDtmnMXOsn9MMDlimMPOtoRQMjddk8DPuYlUMzVYjr3PvY5YNTNUibnPwJNdNzJQhLbOw5hiOTBMf7LOxZxmOzBIeq7Mx6FrPi9FdarLyaZwQS9BcKbJy6p1RS8+a6HHzK56SDA7ZpzFzrJ/TDA5YpjDzraEUDI3XZPAz7mJVDM1WI69z72OWDUzVIm5z8CTXTcyUIS2zsOYYjkwTH+yzsWcZjswSHquzMehaz4vRXWqy8mmcEEvQXCmycuqdUUvPmuhx8yuekgwO2acxc6yf0wwOWKYw862hFAyN12TwM+5iVQzNViOvc+9jlg1M1SJuc/Ak103MlCEts7DmGI5MEx/ss7FnGY7MEh6rszHoWs+L0V1qsvJpnBBL0FwpsnLqnVFLz5rocfMrnpIMDtmnMXOsn9MMDlimMPOtoRQMjddk8DPuYlUMzVYjr3PvY5YNTNUibnPwJNdNzJQhLbOw5hiOTBMf7LOxZxmOzBIeq7Mx6FrPi9FdarLyaZwQS9BcKbJy6p1RS8+a6HHzK56SDA7ZpzFzrJ/TDA5YpjDzraEUDI3XZPAz7mJVDM1WI69z72OWDUzVIm5z8CTXTcyUIS2zsOYYjkwTH+yzsWcZjswSHquzMehaz4vRXWqy8mmcEEvQXCmycuqdUUvPmuhx8yuekgwO2acxc6yf0wwOWKYw862hFAyN12TwM+5iVQzNViOvc+9jlg1M1SJuc/Ak103MlCEts7DmGI5MEx/ss7FnGY7MEh6rszHoWs+L0V1qsvJpnBBL0FwpsnLqnVFLz5rocfMrnpIMDtmnMXOsn9MMDlimMPOtoRQMjddk8DPuYlUMzVYjr3PvY5YNTNUibnPwJNdNzJQhLbOw5hiOTBMf7LOxZxmOzBIeq7Mx6FrPi9FdarLyaZwQS9BcKbJy6p1RS8+a6HHzK56SDA7ZpzFzrJ/TDA5YpjDzraEUDI3XZPAz7mJVDM1WI69z72OWDUzVIm5z8CTXTcyUIS2zsOYYjkwTA==';

  static String get _audioDataUrl => 'data:audio/wav;base64,$_alarmWavBase64';

  static web.HTMLAudioElement _getAudio() {
    return _audio ??= web.HTMLAudioElement()
      ..src = _audioDataUrl
      ..loop = true
      ..preload = 'auto';
  }

  // ---- Persistence (application state only, NOT autoplay permission) -------

  static void _persistUnlock() {
    try {
      web.window.localStorage.setItem(_unlockKey, '1');
    } catch (_) {}
  }

  /// Indicates the user previously enabled reminders.
  /// This is only persisted application state. It does NOT grant
  /// browser autoplay permission after a reload.
  static bool _wasUnlockedPreviously() {
    try {
      return web.window.localStorage.getItem(_unlockKey) == '1';
    } catch (_) {
      return false;
    }
  }

  // ---- Visibility hook ------------------------------------------------------

  static void _hookVisibility() {
    if (_visibilityHooked) return;
    _visibilityHooked = true;

    web.document.addEventListener(
      'visibilitychange',
      (web.Event _) {
        if (web.document.visibilityState == 'visible') {
          rearmAfterVisibilityChange();
        }
      }.toJS,
    );
  }

  /// Re-arms all reminders currently held in memory after the tab returns
  /// to the foreground.
  ///
  /// Browser background execution may be throttled or suspended. This
  /// reconciliation improves recovery after the page becomes visible again,
  /// but it does NOT guarantee that a Timer executes at the exact scheduled
  /// time while the page remains hidden. This is the honest best-effort
  /// boundary for Scenario 1.
  static Future<void> rearmAfterVisibilityChange() async {
    if (!kIsWeb) return;
    _hookVisibility();

    try {
      final snapshot = Map<String, Map<String, dynamic>>.from(_storedRows);
      for (final entry in snapshot.entries) {
        await cancelReminder(entry.key);
        await scheduleReminder(entry.value);
      }
    } catch (e) {
      debugPrint('Visibility re-arm error: $e');
    }
  }

  /// Unlocks audio during the user's explicit tap on "Enable Reminders".
  static Future<void> unlockAudio() async {
    final audio = _getAudio();
    try {
      audio.currentTime = 0;
      final result = audio.play();
      result.toDart.catchError((Object e) {
        debugPrint('Web audio unlock play error: $e');
        return null;
      });
      audio.pause();
      audio.currentTime = 0;
      _audioUnlocked = true;

      // Remember that the user enabled reminders.
      // This does NOT guarantee autoplay permission after reload.
      _persistUnlock();
      _hookVisibility();
    } catch (e) {
      debugPrint('Web audio unlock failed: $e');
    }
  }

  /// Schedules a best-effort browser reminder.
  ///
  /// When the page is foregrounded, the Timer executes normally.
  /// When the browser backgrounds or suspends the page, execution timing
  /// is controlled by the browser/OS and is not guaranteed at exact time.
  static Future<void> scheduleReminder(Map<String, dynamic> row) async {
    final reminderId = row['id']?.toString();
    if (reminderId == null || reminderId.isEmpty) return;

    _storedRows[reminderId] = Map<String, dynamic>.from(row);
    await cancelReminder(reminderId);

    final rawTimes = row['reminder_time'];
    if (rawTimes == null) return;

    final times = _parseTimes(rawTimes);
    if (times.isEmpty) return;

    final reminderDate = row['reminder_date']?.toString().trim() ?? '';
    final daily = reminderDate.toLowerCase() == 'daily';
    final name = row['name']?.toString() ?? 'Medication';
    final dosage = row['dosage']?.toString() ?? '';

    final timers = <Timer>[];

    for (final time in times) {
      final scheduledAt = daily
          ? _nextDailyOccurrence(time)
          : _parseSpecificDateOccurrence(reminderDate, time);
      if (scheduledAt == null) continue;

      final delay = scheduledAt.difference(DateTime.now());
      if (delay.isNegative) continue;

      timers.add(
        Timer(delay, () async {
          await startAlarmSound();
          await _showNotification(
            id: reminderId,
            name: name,
            dosage: dosage,
            time: time,
          );
          if (daily) {
            final nextRow = Map<String, dynamic>.from(row);
            await scheduleReminder(nextRow);
          }
        }),
      );
    }

    _reminderTimers[reminderId] = timers;
  }

  static Future<void> _showNotification({
    required String id,
    required String name,
    required String dosage,
    required String time,
  }) async {
    if (!kIsWeb) return;
    try {
      if (web.Notification.permission != 'granted') return;
      final bodyText = dosage.trim().isNotEmpty
          ? '$dosage ($time) — Time to take your medication!'
          : 'Time to take your medication ($time)!';

      try {
        final reg = await web.window.navigator.serviceWorker.ready.toDart;
        final svcReg = reg;
        await svcReg
            .showNotification(
              'SANA Reminder: $name',
              web.NotificationOptions(
                body: bodyText,
                icon: '/sana/icons/Icon-192.png',
                badge: '/sana/icons/Icon-192.png',
                tag: 'sana-$id-$time',
                renotify: true,
                requireInteraction: true,
              ),
            )
            .toDart;
        return;
      } catch (_) {}

      web.Notification(
        'SANA Reminder: $name',
        web.NotificationOptions(
          body: bodyText,
          icon: '/sana/icons/Icon-192.png',
          badge: '/sana/icons/Icon-192.png',
          tag: 'sana-$id-$time',
          requireInteraction: true,
        ),
      );
    } catch (e) {
      debugPrint('Web notification error: $e');
    }
  }

  static Future<void> cancelReminder(String reminderId) async {
    _storedRows.remove(reminderId);
    final timers = _reminderTimers.remove(reminderId);
    if (timers == null) return;
    for (final timer in timers) {
      timer.cancel();
    }
  }

  static Future<void> cancelAllReminders() async {
    _storedRows.clear();
    for (final timers in _reminderTimers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    _reminderTimers.clear();
  }

  /// Starts sound only (does NOT cancel any timers).
  ///
  /// The browser gets the final say. If autoplay is permitted, audio plays.
  /// If the browser rejects it, SANA does not pretend localStorage solved it.
  static Future<void> startAlarmSound() async {
    final audio = _getAudio();
    try {
      audio.currentTime = 0;
      final result = audio.play();
      result.toDart.catchError((Object e) {
        debugPrint('Web audio playback error: $e');
        return null;
      });
    } catch (e) {
      debugPrint('Web audio playback error: $e');
    }
  }

  /// Stops audio only (does NOT cancel any scheduled reminders).
  static Future<void> stopAlarmSound() async {
    final audio = _audio;
    if (audio == null) return;
    audio.pause();
    audio.currentTime = 0;
  }

  static List<String> _parseTimes(dynamic value) {
    if (value == null) return <String>[];
    final raw = value.toString().trim();
    if (raw.isEmpty) return <String>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((v) => v.toString().trim())
            .where((v) => v.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    return raw
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
  }

  static int? _parseMinutes(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());

    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || minute < 0 || minute > 59)
      return null;

    final meridiem = match.group(3)?.toUpperCase();
    if (meridiem == 'AM') {
      if (hour < 1 || hour > 12) return null;
      if (hour == 12) hour = 0;
    } else if (meridiem == 'PM') {
      if (hour < 1 || hour > 12) return null;
      if (hour != 12) hour += 12;
    } else {
      if (hour < 0 || hour > 23) return null;
    }

    return hour * 60 + minute;
  }

  static DateTime? _nextDailyOccurrence(String time) {
    final minutes = _parseMinutes(time);
    if (minutes == null) return null;

    final now = DateTime.now();
    var result =
        DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    if (!result.isAfter(now)) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  static DateTime? _parseSpecificDateOccurrence(String date, String time) {
    final minutes = _parseMinutes(time);
    if (minutes == null) return null;

    final match =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(date.trim());
    if (match == null) return null;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;

    final result = DateTime(year, month, day, minutes ~/ 60, minutes % 60);
    if (result.year != year ||
        result.month != month ||
        result.day != day ||
        result.hour != minutes ~/ 60 ||
        result.minute != minutes % 60) {
      return null;
    }
    return result;
  }
}
