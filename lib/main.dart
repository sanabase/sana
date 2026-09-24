// 24==========================================
// SANA - COMPLETE WORKING CODE v20.10 (FIXED ONLY)
// FIXED: Tap payment, guest_id removed, Namespace, reminder_date
// YOUR ORIGINAL CODE PRESERVED
// ============================================
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'services/guest_identity_service.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as package_http;
import 'package:uuid/uuid.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'sana_web_events_stub.dart'
    if (dart.library.js_interop) 'sana_web_events_web.dart';
import 'sana_web_push_stub.dart'
    if (dart.library.js_interop) 'sana_web_push_web.dart';
import 'sana_pwa_install_stub.dart'
    if (dart.library.js_interop) 'sana_pwa_install_web.dart';
import 'sana_web_alarm_stub.dart'
    if (dart.library.js_interop) 'sana_web_alarm_web.dart';
// ============================================
// CONFIGURATION
// ============================================

const String _supabaseUrl = 'https://emvadnooxyspfsfnzlmb.supabase.co';
const String _supabaseKey = 'sb_publishable_3f7AQFQw-Kx0_Qvir4nFXQ_XZmUMpzm';
const String _sanaShareUrl = 'https://sanabase.github.io/sana/';

// ============================================
// 8 LANGUAGES - FULL TRANSLATIONS
// ============================================
const List<String> _supportedLangCodes = <String>[
  'en',
  'ar',
  'es',
  'fr',
  'de',
  'tr',
  'hi',
  'zh',
];

String _detectStartupLanguage() {
  try {
    final deviceLanguage =
        ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();

    if (_supportedLangCodes.contains(deviceLanguage)) {
      return deviceLanguage;
    }
  } catch (_) {
    // Fall back to English if the platform language cannot be read.
  }

  return 'en';
}

final ValueNotifier<String> languageNotifier =
    ValueNotifier<String>(_detectStartupLanguage());

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SanaAlarmService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final MethodChannel _alarmChannel = MethodChannel('sana/alarm');

  /*
   * KEEP THIS EXISTING FLUTTER CHANNEL ID.
   */
  static const String _channelId = 'sana_medication_alarm_v2';

  static Map<String, dynamic>? _pendingNativeAlarm;

  static String? _lastNativeAlarmKey;

  static DateTime? _lastNativeAlarmAt;

  static Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    tz.initializeTimeZones();

    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();

    tz.setLocalLocation(
      tz.getLocation(
        currentTimeZone,
      ),
    );

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      _alarmChannel.setMethodCallHandler(
        _handleNativeAlarmCall,
      );

      await _alarmChannel.invokeMethod(
        'nativeAlarmReady',
      );

      final canExact = await _alarmChannel.invokeMethod<bool>(
            'canScheduleNativeAlarm',
          ) ??
          false;

      /*
       * Keep the existing permission request behavior.
       *
       * Even if the user does not grant it, native scheduling
       * now falls back to setAndAllowWhileIdle().
       */
      if (!canExact) {
        await _alarmChannel.invokeMethod(
          'requestNativeAlarmPermission',
        );
      }

      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.requestNotificationsPermission();

      final fullScreenPermission =
          await androidPlugin?.requestFullScreenIntentPermission();

      debugPrint(
        'SANA FULL SCREEN INTENT PERMISSION: $fullScreenPermission',
      );
    }
  }

  static Future<dynamic> _handleNativeAlarmCall(
    MethodCall call,
  ) async {
    if (call.method != 'nativeAlarmTriggered') {
      return null;
    }

    final raw = call.arguments;

    if (raw is! Map) {
      return null;
    }

    _pendingNativeAlarm = Map<String, dynamic>.from(
      raw,
    );

    _flushPendingNativeAlarm();

    return null;
  }

  static void _flushPendingNativeAlarm() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        final data = _pendingNativeAlarm;

        if (data == null) {
          return;
        }

        final navigator = navigatorKey.currentState;

        if (navigator == null) {
          Future<void>.delayed(
            const Duration(
              milliseconds: 100,
            ),
            _flushPendingNativeAlarm,
          );
          return;
        }

        final reminderId = data['reminderId']?.toString();

        if (reminderId == null || reminderId.isEmpty) {
          _pendingNativeAlarm = null;

          return;
        }

        final notificationId = int.tryParse(
              data['notificationId']?.toString() ?? '',
            ) ??
            0;

        final daily = data['daily'] == true;

        final name = data['name']?.toString() ?? '';

        final dosage = data['dosage']?.toString() ?? '';

        final reminderTime = data['reminderTime']?.toString() ?? '';

        final reminderDate = data['reminderDate']?.toString() ?? '';

        final photoBase64 = data['photoBase64']?.toString() ?? '';

        final key = '$reminderId:$notificationId';

        final now = DateTime.now();

        if (_lastNativeAlarmKey == key &&
            _lastNativeAlarmAt != null &&
            now.difference(
                  _lastNativeAlarmAt!,
                ) <
                const Duration(
                  seconds: 5,
                )) {
          _pendingNativeAlarm = null;

          return;
        }

        _lastNativeAlarmKey = key;

        _lastNativeAlarmAt = now;

        _pendingNativeAlarm = null;

        await startAlarmSound();

        navigator.push(
          MaterialPageRoute(
            builder: (_) => SanaAlarmScreen(
              reminderId: reminderId,
              notificationId: notificationId,
              daily: daily,
              name: name,
              dosage: dosage,
              reminderTime: reminderTime,
              reminderDate: reminderDate,
              photoBase64: photoBase64,
            ),
          ),
        );
      },
    );
  }

  static Future<String?> scheduleNativeAlarm({
    required int notificationId,
    required String reminderId,
    required DateTime scheduledDate,
    required bool daily,
    required String name,
    required String dosage,
    required String reminderTime,
    required String reminderDate,
    String? photoBase64,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    final status = await _alarmChannel.invokeMethod<String>(
      'scheduleNativeAlarm',
      {
        'notificationId': notificationId,
        'reminderId': reminderId,
        'triggerAtMillis': scheduledDate.millisecondsSinceEpoch,
        'daily': daily,
        'name': name,
        'dosage': dosage,
        'reminderTime': reminderTime,
        'reminderDate': reminderDate,
        'photoBase64': photoBase64,
      },
    );

    return status;
  }

  static Future<void> cancelNativeAlarm(
    int notificationId,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _alarmChannel.invokeMethod(
      'cancelNativeAlarm',
      {
        'notificationId': notificationId,
      },
    );
  }

  static Future<void> cancelNativeReminder(
    String reminderId,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _alarmChannel.invokeMethod(
      'cancelNativeReminder',
      {
        'reminderId': reminderId,
      },
    );
  }

  static Future<void> clearAllNativeAlarms() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _alarmChannel.invokeMethod(
        'clearAllNativeAlarms',
      );
    } catch (e) {
      debugPrint(
        'Clear all native alarms error: $e',
      );
    }
  }

  static Future<void> dismissNativeAlarmNotification(
    int notificationId,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _alarmChannel.invokeMethod(
        'dismissNativeAlarmNotification',
        {
          'notificationId': notificationId,
        },
      );
    } catch (e) {
      debugPrint(
        'Dismiss alarm notification error: $e',
      );
    }
  }

  static Future<void> _onNotificationResponse(
    NotificationResponse response,
  ) async {
    if (response.payload == null || response.payload!.trim().isEmpty) {
      return;
    }

    try {
      final data = jsonDecode(
        response.payload!,
      ) as Map<String, dynamic>;

      final id = data['id']?.toString();

      if (id == null || id.isEmpty) {
        return;
      }

      final daily = data['daily'] == true;

      await startAlarmSound();

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SanaAlarmScreen(
            reminderId: id,
            notificationId: response.id ?? 0,
            daily: daily,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Alarm response error: $e',
      );
    }
  }

  static Future<void> startAlarmSound() async {
    if (kIsWeb) {
      await SanaWebAlarm.startAlarmSound();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _alarmChannel.invokeMethod(
        'startAlarmSound',
      );
    } catch (e) {
      debugPrint(
        'Start alarm sound error: $e',
      );
    }
  }

  static Future<void> stopAlarmSound({
    int? notificationId,
  }) async {
    if (kIsWeb) {
      await SanaWebAlarm.stopAlarmSound();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _alarmChannel.invokeMethod(
        'stopAlarmSound',
        {
          'notificationId': notificationId,
        },
      );
    } catch (e) {
      debugPrint(
        'Stop alarm sound error: $e',
      );
    }
  }

  static int notificationId(
    String reminderId,
    int index,
  ) {
    final source = '$reminderId:$index';

    var hash = 0;

    for (final codeUnit in source.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }

    return hash == 0 ? index + 1 : hash;
  }

  static List<String> parseTimes(
    dynamic value,
  ) {
    if (value == null) {
      return [];
    }

    final raw = value.toString().trim();

    if (raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded
            .map(
              (e) => e.toString().trim(),
            )
            .where(
              (e) => e.isNotEmpty,
            )
            .toList();
      }
    } catch (_) {}

    return raw
        .split(',')
        .map(
          (e) => e.trim(),
        )
        .where(
          (e) => e.isNotEmpty,
        )
        .toList();
  }

  static int? parseTimeToMinutes(
    String value,
  ) {
    final text = value.trim();

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(text);

    if (match == null) {
      return null;
    }

    var hour = int.tryParse(
      match.group(1)!,
    );

    final minute = int.tryParse(
      match.group(2)!,
    );

    if (hour == null || minute == null) {
      return null;
    }

    if (minute < 0 || minute > 59) {
      return null;
    }

    final meridiem = match.group(3)?.toUpperCase();

    if (meridiem == 'AM') {
      if (hour < 1 || hour > 12) {
        return null;
      }

      if (hour == 12) {
        hour = 0;
      }
    } else if (meridiem == 'PM') {
      if (hour < 1 || hour > 12) {
        return null;
      }

      if (hour != 12) {
        hour += 12;
      }
    } else {
      if (hour < 0 || hour > 23) {
        return null;
      }
    }

    return (hour * 60 + minute);
  }

  static DateTime? parseDateTime(
    String date,
    String time,
  ) {
    final dateMatch = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(
      date.trim(),
    );

    if (dateMatch == null) {
      return null;
    }

    final year = int.tryParse(
      dateMatch.group(1)!,
    );

    final month = int.tryParse(
      dateMatch.group(2)!,
    );

    final day = int.tryParse(
      dateMatch.group(3)!,
    );

    final minutes = parseTimeToMinutes(
      time,
    );

    if (year == null || month == null || day == null || minutes == null) {
      return null;
    }

    final hour = minutes ~/ 60;

    final minute = minutes % 60;

    final result = DateTime(
      year,
      month,
      day,
      hour,
      minute,
    );

    if (result.year != year ||
        result.month != month ||
        result.day != day ||
        result.hour != hour ||
        result.minute != minute) {
      return null;
    }

    return result;
  }

  static Future<void> scheduleReminder(
    Map<String, dynamic> row,
  ) async {
    final id = row['id']?.toString();

    if (id == null || id.isEmpty) {
      return;
    }

    final times = parseTimes(
      row['reminder_time'],
    );

    if (times.isEmpty) {
      return;
    }

    if (kIsWeb) {
      await SanaWebAlarm.scheduleReminder(row);
      return;
    }

    final reminderDate = row['reminder_date']?.toString().trim();

    final normalizedReminderDate = reminderDate?.toLowerCase() ?? '';

    final scheduleType =
        normalizedReminderDate == 'daily' ? 'daily' : 'calendar';

    final name = row['name']?.toString().trim() ?? '';

    final dosage = row['dosage']?.toString().trim() ?? '';

    final reminderTime = row['reminder_time']?.toString().trim() ?? '';

    final reminderDateForCache = reminderDate ?? '';

    final rawPhoto = row['photo_base64'] ?? row['photo'];

    final photoBase64 = rawPhoto?.toString().trim();

    for (var index = 0; index < times.length; index++) {
      final time = times[index];

      final minutes = parseTimeToMinutes(
        time,
      );

      if (minutes == null) {
        continue;
      }

      final hour = minutes ~/ 60;

      final minute = minutes % 60;

      final notificationId = SanaAlarmService.notificationId(
        id,
        index,
      );

      if (scheduleType == 'daily') {
        var scheduled = tz.TZDateTime(
          tz.local,
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          hour,
          minute,
        );

        final now = tz.TZDateTime.now(
          tz.local,
        );

        if (!scheduled.isAfter(
          now,
        )) {
          scheduled = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day + 1,
            hour,
            minute,
          );
        }

        if (defaultTargetPlatform == TargetPlatform.android) {
          final status = await SanaAlarmService.scheduleNativeAlarm(
            notificationId: notificationId,
            reminderId: id,
            scheduledDate: scheduled,
            daily: true,
            name: name,
            dosage: dosage,
            reminderTime: reminderTime,
            reminderDate: reminderDateForCache,
            photoBase64: photoBase64,
          );

          if (status == 'FAILED' || status == 'INVALID') {
            throw StateError(
              'Native alarm scheduling failed for $id',
            );
          }
        } else {
          await _notifications.zonedSchedule(
            id: notificationId,
            scheduledDate: scheduled,
            title: tr(
              languageNotifier.value,
              'alarm',
            ),
            body: name,
            payload: jsonEncode({
              'id': id,
              'daily': true,
            }),
            notificationDetails: _notificationDetails(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      } else {
        if (reminderDate == null || reminderDate.isEmpty) {
          continue;
        }

        final dateTime = parseDateTime(
          reminderDate,
          time,
        );

        if (dateTime == null) {
          continue;
        }

        final scheduled = tz.TZDateTime.from(
          dateTime,
          tz.local,
        );

        if (!scheduled.isAfter(
          tz.TZDateTime.now(
            tz.local,
          ),
        )) {
          continue;
        }

        if (defaultTargetPlatform == TargetPlatform.android) {
          final status = await SanaAlarmService.scheduleNativeAlarm(
            notificationId: notificationId,
            reminderId: id,
            scheduledDate: scheduled,
            daily: false,
            name: name,
            dosage: dosage,
            reminderTime: reminderTime,
            reminderDate: reminderDateForCache,
            photoBase64: photoBase64,
          );

          if (status == 'FAILED' || status == 'INVALID') {
            throw StateError(
              'Native alarm scheduling failed for $id',
            );
          }
        } else {
          await _notifications.zonedSchedule(
            id: notificationId,
            scheduledDate: scheduled,
            title: tr(
              languageNotifier.value,
              'alarm',
            ),
            body: name,
            payload: jsonEncode({
              'id': id,
              'daily': false,
            }),
            notificationDetails: _notificationDetails(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        }
      }
    }
  }

  static NotificationDetails _notificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'SANA Medication Alarms',
        channelDescription: 'SANA medication reminder alarms',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        ongoing: true,
        playSound: true,
        enableVibration: false,
        fullScreenIntent: true,
        autoCancel: false,
        actions: [
          AndroidNotificationAction(
            'taken',
            tr(
              languageNotifier.value,
              'taken',
            ),
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'sana_alarm.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  static Future<void> cancelReminder(
    String reminderId,
  ) async {
    if (kIsWeb) {
      await SanaWebAlarm.cancelReminder(reminderId);
      return;
    }

    /*
     * Android native alarms are cancelled by the cache itself.
     * This avoids the old arbitrary 0..20 native-alarm loop.
     */
    if (defaultTargetPlatform == TargetPlatform.android) {
      await cancelNativeReminder(
        reminderId,
      );

      /*
       * Also cancel any legacy flutter_local_notifications
       * alarms that may have been created by an older version.
       */
      for (var index = 0; index < 20; index++) {
        final id = notificationId(
          reminderId,
          index,
        );

        await _notifications.cancel(
          id: id,
        );
      }

      return;
    }

    /*
     * Preserve the existing iOS cleanup behavior.
     */
    for (var index = 0; index < 20; index++) {
      final id = notificationId(
        reminderId,
        index,
      );

      await _notifications.cancel(
        id: id,
      );
    }
  }
}

const Map<String, String> _languageNames = {
  'en': 'English',
  'ar': 'العربية',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'tr': 'Türkçe',
  'hi': 'हिन्दी',
  'zh': '中文',
};

const Map<String, Map<String, String>> _translations = {
  'en': {
    'add': 'Add',
    'save': 'Save',
    'delete': 'Delete',
    'view': 'View',
    'close': 'Close',
    'share': 'Share',
    'reminders_enabled': 'Reminders enabled',
    'disable_reminders': 'Disable reminders',
    'enable_reminders': 'Enable reminders',
    'saved_successfully': 'Saved successfully',
    'reminder_saved_successfully':
        'Reminder "{name}" saved successfully for {date} at {time}.',
    'delete_success': 'Deleted successfully',
    'delete_failed': 'Delete failed.',
    'reminder_setting_failed': 'Reminder setting failed.',
    'error_loading': 'Error loading data.',
    'loading': 'Loading...',
    'pwa_install_hint': 'Install SANA on your phone for reliable reminders.',
    'pwa_step_1': 'Tap the Share button at the bottom of Safari.',
    'pwa_step_2': 'Scroll and tap "Add to Home Screen".',
    'pwa_step_3': 'Tap "Add" at the top right.',
    'install_app': 'Install App',
    'help': 'Help',
    'call': 'Call',
    'chat': 'Chat',
    'write_comment': 'Write your comment...',
    'send': 'Send',
    'comment_sent': 'Comment sent successfully',
    'chat_date': 'Chat / Date',
    'joining_date': 'Joining Date',
    'last_login': 'Last Login',
    'login': 'Login',
    'logout': 'Logout',
    'admin': 'Admin',
    'medications': 'Medications',
    'doctors': 'Doctors',
    'pharmacies': 'Pharmacies',
    'reminders': 'Reminders',
    'documents': 'Documents',
    'insurance_cards': 'Insurance Cards',
    'name': 'Name',
    'dosage': 'Dosage',
    'notes': 'Notes',
    'quantity': 'Stock',
    'description': 'Description',
    'specialty': 'Specialty',
    'phone': 'Phone',
    'address': 'Address',
    'email': 'Email or username',
    'show_password': 'Show password',
    'password': 'Password',
    'password_6_digit': '6 digits',
    'sign_in': 'Sign In',
    'new_user': 'New User',
    'register': 'Register',
    'create_account': 'Create Account',
    'already_account': 'Already have an account?',
    'location': 'Location',
    'photo': 'Photo',
    'front_photo': 'Front Photo',
    'back_photo': 'Back Photo',
    'reminder_time': 'Reminder Time',
    'reminder_date': 'Reminder Date',
    'schedule_type': 'Schedule',
    'daily': 'Daily',
    'calendar': 'Calendar',
    'select_times': 'Select one or more times',
    'select_schedule': 'Select schedule',
    'record': 'Record',
    'no_records': 'No records',
    'guest_mode': 'Guest Mode',
    'get_copy': 'Get Your Copy',
    'create_copy': 'Create Your Copy',
    'select_all': 'Select All',
    'share_selected': 'Share Selected',
    'no_selection': 'No items selected',
    'admin_panel': 'Admin Panel',
    'users': 'Users',
    'activate': 'Activate',
    'deactivate': 'Deactivate',
    'status': 'Status',
    'role': 'Role',
    'active_user': 'Active User',
    'inactive_guest': 'Inactive User',
    'expired': 'Please get your own copy, and wait 48 hours until activated.',
    'pending_activation':
        'Please get your own copy, and wait 48 hours until activated.',
    'paid': 'Paid',
    'expiry_date': 'Expiry Date',
    'provider_name': 'Provider Name',
    'front_image': 'Front Image',
    'back_image': 'Back Image',
    'file_url': 'File URL',
    'category': 'Category',
    'title': 'Title',
    'policy': 'Policy',
    'policy_number': 'Policy Number',
    'provider': 'Provider',
    'expiry': 'Expiry',
    'specialist': 'Specialist',
    'guest': 'Guest Mode',
    'account': 'Account',
    'guest_data': 'Guest Data',
    'full_record': 'Full Record',
    'share_record': 'Share Record',
    'sign_up': 'Sign Up',
    'language': 'Language',
    'select_medication': 'Select Medication',
    'select_time': 'Select Time',
    'select_date': 'Select Date',
    'required_field': 'This field is required',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Please login',
    'please_fill_all': 'Please fill all fields',
    'login_failed': 'Login failed',
    'signup_failed': 'Sign up failed',
    'delete_confirm_title': 'Delete?',
    'delete_confirm_msg': 'Are you sure you want to delete this record?',
    'cancel': 'Cancel',
    'please_sign_in': 'Please Sign In',
    'account_created_success': 'Account created successfully! Please Sign In.',
    'operation_failed': 'Operation failed',
    'select_front_image': 'Select Front Image',
    'select_back_image': 'Select Back Image',
    'upload_image': 'Upload Image',
    'uploaded': 'Uploaded',
    'insurance_company_name': 'Insurance Company Name',
    'patient_id': 'Patient ID',
    'insurance_card_front': 'Insurance Card - Front',
    'insurance_card_back': 'Insurance Card - Back',
    'no_image_selected': 'No image selected',
    'upload_front_card': 'Upload Front Card',
    'upload_back_card': 'Upload Back Card',
    'add_data': 'Add Data',
    'please_enter_insurance_company': 'Please enter insurance company name',
    'please_enter_patient_id': 'Please enter patient ID',
    'please_upload_both_cards': 'Please upload both front and back cards',
    'success': 'successfully',
    'upload_photo': 'Upload Photo',
    'select_photo': 'Select Photo',
    'photo_uploaded': 'Photo uploaded',
    'please_upload_photo': 'Please upload a photo',
    'share_app': 'Share App',
    'share_app_message': 'Check out SANA - Your Health Management App!',
    'opening_payment': 'Opening payment page...',
    'payment_error': 'Payment error',
    'medicine_photo': 'Medicine photo',
    'no_medicine_photo': 'No medicine photo selected',
    'upload_medicine_photo': 'Upload medicine photo',
    'change_medicine_photo': 'Change medicine photo',
    'select_reminder_times': 'Select reminder times',
    'selected': 'Selected',
    'medication_schedule': 'Medication schedule',
    'choose_schedule_repeat': 'Choose when this reminder should repeat:',
    'repeat_daily_msg': 'The reminder will repeat every day.',
    'select_calendar_date': 'Select calendar date',
    'date': 'Date',
    'share_documents': 'Share Documents',
    'manual_title': 'SANA Medical Pocket Book',
    'manual_content':
        '1. Securely manage your health records on the web, and access your data any time, anywhere and from any device.\n2. Add and track daily prescriptions and dosages in Medications.\n3. Keep your doctor contact info and specialty notes handy.\n4. Save your preferred pharmacies with phone and location.\n5. Set multi-time dosage reminders with alerts.\n6. Store medical documents and lab reports with photos.\n7. Keep front and back photos of your insurance cards.\n8. Select and share records with your doctors anytime.\n9. Install the application on your device to get all features and activate medication alarms.\n10. Get your own private, dedicated copy that is invisible to anyone else.',
    'install_sana': 'Install SANA',
    'taken': 'Taken',
    'alarm': 'Medication Alarm',
    'daily_reminders': 'Daily Reminders',
    'calendar_reminders': 'Scheduled Reminders',
  },
  'ar': {
    'add': 'إضافة',
    'save': 'حفظ',
    'delete': 'حذف',
    'view': 'عرض',
    'close': 'إغلاق',
    'share': 'مشاركة',
    'reminders_enabled': 'تم تمكين التذكيرات',
    'install_app': 'تثبيت التطبيق',
    'help': 'مساعدة',
    'call': 'اتصال',
    'chat': 'محادثة',
    'write_comment': 'اكتب تعليقك...',
    'send': 'إرسال',
    'comment_sent': 'تم إرسال التعليق بنجاح',
    'chat_date': 'المحادثة / التاريخ',
    'joining_date': 'تاريخ الانضمام',
    'last_login': 'آخر تسجيل دخول',
    'login': 'تسجيل الدخول',
    'logout': 'تسجيل الخروج',
    'admin': 'المسؤول',
    'medications': 'الأدوية',
    'doctors': 'الأطباء',
    'pharmacies': 'الصيدليات',
    'reminders': 'التذكيرات',
    'documents': 'المستندات',
    'insurance_cards': 'بطاقات التأمين',
    'name': 'الاسم',
    'dosage': 'الجرعة',
    'notes': 'ملاحظات',
    'quantity': 'المخزون',
    'description': 'الوصف',
    'specialty': 'التخصص',
    'phone': 'الهاتف',
    'address': 'العنوان',
    'email': 'البريد الإلكتروني أو اسم المستخدم',
    'show_password': 'إظهار كلمة المرور',
    'password': 'كلمة المرور',
    'password_6_digit': '6 أرقام',
    'sign_in': 'تسجيل الدخول',
    'new_user': 'مستخدم جديد',
    'register': 'تسجيل',
    'create_account': 'إنشاء حساب',
    'already_account': 'هل لديك حساب بالفعل؟',
    'location': 'الموقع',
    'photo': 'صورة',
    'front_photo': 'الصورة الأمامية',
    'back_photo': 'الصورة الخلفية',
    'reminder_time': 'وقت التذكير',
    'reminder_date': 'تاريخ التذكير',
    'schedule_type': 'الجدول',
    'daily': 'يومي',
    'calendar': 'التقويم',
    'select_times': 'اختر وقتًا واحدًا أو أكثر',
    'select_schedule': 'اختر الجدول',
    'record': 'سجل',
    'no_records': 'لا توجد سجلات',
    'guest_mode': 'وضع الضيف',
    'get_copy': 'احصل على نسختك',
    'create_copy': 'أنشئ نسختك',
    'select_all': 'تحديد الكل',
    'share_selected': 'مشاركة المحدد',
    'no_selection': 'لم يتم تحديد أي عناصر',
    'admin_panel': 'لوحة الإدارة',
    'users': 'المستخدمون',
    'activate': 'تفعيل',
    'deactivate': 'تعطيل',
    'status': 'الحالة',
    'role': 'الدور',
    'active_user': 'مستخدم نشط',
    'inactive_guest': 'مستخدم غير نشط',
    'expired':
        'يرجى الحصول على نسختك الخاصة، والانتظار 48 ساعة حتى يتم تفعيلها.',
    'pending_activation':
        'يرجى الحصول على نسختك الخاصة، والانتظار 48 ساعة حتى يتم تفعيلها.',
    'paid': 'تم الدفع',
    'expiry_date': 'تاريخ الانتهاء',
    'provider_name': 'اسم مقدم الخدمة',
    'front_image': 'الصورة الأمامية',
    'back_image': 'الصورة الخلفية',
    'file_url': 'رابط الملف',
    'category': 'الفئة',
    'title': 'العنوان',
    'policy': 'رقم الوثيقة',
    'policy_number': 'رقم الوثيقة',
    'provider': 'مقدم الخدمة',
    'expiry': 'تاريخ الانتهاء',
    'specialist': 'الأخصائي',
    'guest': 'وضع الضيف',
    'account': 'الحساب',
    'guest_data': 'بيانات الضيف',
    'full_record': 'السجل الكامل',
    'share_record': 'مشاركة السجل',
    'sign_up': 'إنشاء حساب',
    'language': 'اللغة',
    'select_medication': 'اختر الدواء',
    'select_time': 'اختر الوقت',
    'select_date': 'اختر التاريخ',
    'required_field': 'هذا الحقل مطلوب',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'يرجى تسجيل الدخول',
    'please_fill_all': 'يرجى ملء جميع الحقول',
    'login_failed': 'فشل تسجيل الدخول',
    'signup_failed': 'فشل إنشاء الحساب',
    'delete_confirm_title': 'حذف؟',
    'delete_confirm_msg': 'هل أنت متأكد من حذف هذا السجل؟',
    'cancel': 'إلغاء',
    'please_sign_in': 'يرجى تسجيل الدخول',
    'account_created_success': 'تم إنشاء الحساب بنجاح! يرجى تسجيل الدخول.',
    'operation_failed': 'فشلت العملية',
    'select_front_image': 'اختر الصورة الأمامية',
    'select_back_image': 'اختر الصورة الخلفية',
    'upload_image': 'رفع صورة',
    'uploaded': 'تم الرفع',
    'insurance_company_name': 'اسم شركة التأمين',
    'patient_id': 'رقم المريض',
    'insurance_card_front': 'بطاقة التأمين - الأمام',
    'insurance_card_back': 'بطاقة التأمين - الخلف',
    'no_image_selected': 'لم يتم اختيار صورة',
    'upload_front_card': 'رفع البطاقة الأمامية',
    'upload_back_card': 'رفع البطاقة الخلفية',
    'add_data': 'إضافة البيانات',
    'please_enter_insurance_company': 'يرجى إدخال اسم شركة التأمين',
    'please_enter_patient_id': 'يرجى إدخال رقم المريض',
    'please_upload_both_cards': 'يرجى رفع البطاقتين',
    'success': 'تم بنجاح',
    'upload_photo': 'رفع صورة',
    'select_photo': 'اختيار صورة',
    'photo_uploaded': 'تم رفع الصورة',
    'please_upload_photo': 'يرجى رفع صورة',
    'share_app': 'مشاركة التطبيق',
    'share_app_message': 'SANA - تطبيقك لإدارة صحتك!',
    'opening_payment': 'جاري فتح صفحة الدفع...',
    'payment_error': 'خطأ في الدفع',
    'medicine_photo': 'صورة الدواء',
    'no_medicine_photo': 'لم يتم اختيار صورة للدواء',
    'upload_medicine_photo': 'رفع صورة الدواء',
    'change_medicine_photo': 'تغيير صورة الدواء',
    'select_reminder_times': 'اختر أوقات التذكير',
    'selected': 'تم اختيار',
    'medication_schedule': 'جدول الدواء',
    'choose_schedule_repeat': 'اختر متى يتكرر هذا التذكير:',
    'repeat_daily_msg': 'سيتكرر التذكير كل يوم.',
    'select_calendar_date': 'اختر تاريخ التقويم',
    'date': 'التاريخ',
    'share_documents': 'مشاركة المستندات',
    'manual_title': 'دليل سانا الطبي للجيب',
    'manual_content':
        '1. أدر سجلاتك الصحية بأمان عبر الويب، وتمكّن من الوصول إلى بياناتك في أي وقت ومن أي مكان ومن أي جهاز.\n2. إضافة وتتبع الأدوية اليومية والجرعات.\n3. الاحتفاظ بأرقام الأطباء وتخصصاتهم.\n4. حفظ الصيدليات المفضلة مع العناوين والهواتف.\n5. تعيين تذكيرات بمواعيد تناول الدواء مع التنبيهات.\n6. حفظ المستندات والتقارير الطبية مع الصور.\n7. حفظ صور بطاقات التأمين من الأمام والخلف.\n8. تحديد ومشاركة السجلات مع أطبائك في أي وقت.\n9. ثبّت التطبيق على جهازك للحصول على جميع الميزات وتفعيل منبهات الأدوية.\n10. احصل على نسختك الخاصة والمخصصة، والتي لا يمكن لأي شخص آخر رؤيتها.',
    'install_sana': 'تثبيت SANA',
    'taken': 'تم تناول الدواء',
    'alarm': 'منبه الدواء',
    'daily_reminders': 'التذكيرات اليومية',
    'calendar_reminders': 'التذكيرات المجدولة',
  },
  'es': {
    'add': 'Añadir',
    'save': 'Guardar',
    'delete': 'Eliminar',
    'view': 'Ver',
    'close': 'Cerrar',
    'share': 'Compartir',
    'reminders_enabled': 'Recordatorios activados',
    'install_app': 'Instalar aplicación',
    'help': 'Ayuda',
    'call': 'Llamar',
    'chat': 'Chat',
    'write_comment': 'Escribe tu comentario...',
    'send': 'Enviar',
    'comment_sent': 'Comentario enviado con éxito',
    'chat_date': 'Chat / Fecha',
    'joining_date': 'Fecha de registro',
    'last_login': 'Último inicio de sesión',
    'login': 'Iniciar sesión',
    'logout': 'Cerrar sesión',
    'admin': 'Administrador',
    'medications': 'Medicamentos',
    'doctors': 'Médicos',
    'pharmacies': 'Farmacias',
    'reminders': 'Recordatorios',
    'documents': 'Documentos',
    'insurance_cards': 'Tarjetas de seguro',
    'name': 'Nombre',
    'dosage': 'Dosis',
    'notes': 'Notas',
    'quantity': 'Stock',
    'description': 'Descripción',
    'specialty': 'Especialidad',
    'phone': 'Teléfono',
    'address': 'Dirección',
    'email': 'Correo electrónico o nombre de usuario',
    'show_password': 'Mostrar contraseña',
    'password': 'Contraseña',
    'password_6_digit': '6 dígitos',
    'sign_in': 'Iniciar sesión',
    'new_user': 'Nuevo usuario',
    'register': 'Registrarse',
    'create_account': 'Crear cuenta',
    'already_account': '¿Ya tienes una cuenta?',
    'location': 'Ubicación',
    'photo': 'Foto',
    'front_photo': 'Foto frontal',
    'back_photo': 'Foto trasera',
    'reminder_time': 'Hora del recordatorio',
    'reminder_date': 'Fecha del recordatorio',
    'schedule_type': 'Programación',
    'daily': 'Diario',
    'calendar': 'Calendario',
    'select_times': 'Seleccione una o más horas',
    'select_schedule': 'Seleccionar programación',
    'record': 'Registro',
    'no_records': 'No hay registros',
    'guest_mode': 'Modo invitado',
    'get_copy': 'Obtén tu copia',
    'create_copy': 'Crea tu copia',
    'select_all': 'Seleccionar todo',
    'share_selected': 'Compartir seleccionados',
    'no_selection': 'No hay elementos seleccionados',
    'admin_panel': 'Panel de administración',
    'users': 'Usuarios',
    'activate': 'Activar',
    'deactivate': 'Desactivar',
    'status': 'Estado',
    'role': 'Rol',
    'active_user': 'Usuario activo',
    'inactive_guest': 'Usuario inactivo',
    'expired':
        'Obtenga su propia copia y espere 48 horas hasta que sea activada.',
    'pending_activation':
        'Obtenga su propia copia y espere 48 horas hasta que sea activada.',
    'paid': 'Pagado',
    'expiry_date': 'Fecha de vencimiento',
    'provider_name': 'Nombre del proveedor',
    'front_image': 'Imagen frontal',
    'back_image': 'Imagen trasera',
    'file_url': 'URL del archivo',
    'category': 'Categoría',
    'title': 'Título',
    'policy': 'Póliza',
    'policy_number': 'Número de póliza',
    'provider': 'Proveedor',
    'expiry': 'Vencimiento',
    'specialist': 'Especialista',
    'guest': 'Modo invitado',
    'account': 'Cuenta',
    'guest_data': 'Datos del invitado',
    'full_record': 'Registro completo',
    'share_record': 'Compartir registro',
    'sign_up': 'Registrarse',
    'language': 'Idioma',
    'select_medication': 'Seleccionar medicamento',
    'select_time': 'Seleccionar hora',
    'select_date': 'Seleccionar fecha',
    'required_field': 'Este campo es obligatorio',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Por favor inicia sesión',
    'please_fill_all': 'Por favor completa todos los campos',
    'login_failed': 'Error al iniciar sesión',
    'signup_failed': 'Error al registrarse',
    'delete_confirm_title': '¿Eliminar?',
    'delete_confirm_msg': '¿Estás seguro de que deseas eliminar este registro?',
    'cancel': 'Cancelar',
    'please_sign_in': 'Por favor inicia sesión',
    'account_created_success':
        '¡Cuenta creada correctamente! Por favor inicia sesión.',
    'operation_failed': 'La operación falló',
    'select_front_image': 'Seleccionar imagen frontal',
    'select_back_image': 'Seleccionar imagen trasera',
    'upload_image': 'Subir imagen',
    'uploaded': 'Subido',
    'insurance_company_name': 'Nombre de la compañía de seguros',
    'patient_id': 'ID del paciente',
    'insurance_card_front': 'Tarjeta de seguro - frontal',
    'insurance_card_back': 'Tarjeta de seguro - trasera',
    'no_image_selected': 'No se ha seleccionado ninguna imagen',
    'upload_front_card': 'Subir tarjeta frontal',
    'upload_back_card': 'Subir tarjeta trasera',
    'add_data': 'Añadir datos',
    'please_enter_insurance_company':
        'Por favor introduce el nombre de la compañía de seguros',
    'please_enter_patient_id': 'Por favor introduce el ID del paciente',
    'please_upload_both_cards': 'Por favor sube ambas tarjetas',
    'success': 'Éxito',
    'upload_photo': 'Subir foto',
    'select_photo': 'Seleccionar foto',
    'photo_uploaded': 'Foto subida',
    'please_upload_photo': 'Por favor sube una foto',
    'share_app': 'Compartir aplicación',
    'share_app_message': 'SANA - ¡tu aplicación para gestionar tu salud!',
    'opening_payment': 'Abriendo página de pago...',
    'payment_error': 'Error de pago',
    'medicine_photo': 'Foto del medicamento',
    'no_medicine_photo': 'No se ha seleccionado foto',
    'upload_medicine_photo': 'Subir foto del medicamento',
    'change_medicine_photo': 'Cambiar foto del medicamento',
    'select_reminder_times': 'Seleccionar horas de recordatorio',
    'selected': 'Seleccionado',
    'medication_schedule': 'Horario de medicación',
    'choose_schedule_repeat': 'Elija cuándo repetir el recordatorio:',
    'repeat_daily_msg': 'El recordatorio se repetirá todos los días.',
    'select_calendar_date': 'Seleccionar fecha del calendario',
    'date': 'Fecha',
    'share_documents': 'Compartir documentos',
    'manual_title': 'Guía médica de bolsillo SANA',
    'manual_content':
        '1. Gestione de forma segura sus registros de salud en la web y acceda a sus datos en cualquier momento, desde cualquier lugar y desde cualquier dispositivo.\n2. Registre medicamentos diarios y dosis exactas.\n3. Guarde contactos y especialidades de sus médicos.\n4. Guarde farmacias con dirección y teléfono.\n5. Configure recordatorios con múltiples horarios y alertas.\n6. Guarde documentos e informes médicos con fotos.\n7. Guarde fotos del anverso y reverso de tarjetas de seguro.\n8. Seleccione y comparta sus registros con su médico en cualquier momento.\n9. Instale la aplicación en su dispositivo para obtener todas las funciones y activar las alarmas de medicación.\n10. Obtenga su propia copia privada y dedicada, invisible para cualquier otra persona.',
    'install_sana': 'Instalar SANA',
    'taken': 'Tomado',
    'alarm': 'Alarma de medicamento',
    'daily_reminders': 'Recordatorios diarios',
    'calendar_reminders': 'Recordatorios programados',
  },
  'fr': {
    'add': 'Ajouter',
    'save': 'Enregistrer',
    'delete': 'Supprimer',
    'view': 'Voir',
    'close': 'Fermer',
    'share': 'Partager',
    'reminders_enabled': 'Rappels activés',
    'install_app': 'Installer l\'application',
    'help': 'Aide',
    'call': 'Appeler',
    'chat': 'Discussion',
    'write_comment': 'Écrivez votre commentaire...',
    'send': 'Envoyer',
    'comment_sent': 'Commentaire envoyé avec succès',
    'chat_date': 'Discussion / Date',
    'joining_date': "Date d'inscription",
    'last_login': 'Dernière connexion',
    'login': 'Connexion',
    'logout': 'Déconnexion',
    'admin': 'Administrateur',
    'medications': 'Médicaments',
    'doctors': 'Médecins',
    'pharmacies': 'Pharmacies',
    'reminders': 'Rappels',
    'documents': 'Documents',
    'insurance_cards': 'Cartes d’assurance',
    'name': 'Nom',
    'dosage': 'Dosage',
    'notes': 'Notes',
    'quantity': 'Stock',
    'description': 'Description',
    'specialty': 'Spécialité',
    'phone': 'Téléphone',
    'address': 'Adresse',
    'email': 'E-mail ou nom d’utilisateur',
    'show_password': 'Afficher le mot de passe',
    'password': 'Mot de passe',
    'password_6_digit': '6 chiffres',
    'sign_in': 'Se connecter',
    'new_user': 'Nouvel utilisateur',
    'register': 'S’inscrire',
    'create_account': 'Créer un compte',
    'already_account': 'Vous avez déjà un compte ?',
    'location': 'Emplacement',
    'photo': 'Photo',
    'front_photo': 'Photo avant',
    'back_photo': 'Photo arrière',
    'reminder_time': 'Heure du rappel',
    'reminder_date': 'Date du rappel',
    'schedule_type': 'Programme',
    'daily': 'Quotidien',
    'calendar': 'Calendrier',
    'select_times': 'Sélectionnez une ou plusieurs heures',
    'select_schedule': 'Sélectionner le programme',
    'record': 'Dossier',
    'no_records': 'Aucun enregistrement',
    'guest_mode': 'Mode invité',
    'get_copy': 'Obtenez votre copie',
    'create_copy': 'Créez votre copie',
    'select_all': 'Tout sélectionner',
    'share_selected': 'Partager la sélection',
    'no_selection': 'Aucun élément sélectionné',
    'admin_panel': 'Panneau d’administration',
    'users': 'Utilisateurs',
    'activate': 'Activer',
    'deactivate': 'Désactiver',
    'status': 'Statut',
    'role': 'Rôle',
    'active_user': 'Utilisateur actif',
    'inactive_guest': 'Utilisateur inactif',
    'expired':
        'Veuillez obtenir votre propre copie et attendre 48 heures jusqu’à son activation.',
    'pending_activation':
        'Veuillez obtenir votre propre copie et attendre 48 heures jusqu’à son activation.',
    'paid': 'Payé',
    'expiry_date': "Date d'expiration",
    'provider_name': 'Nom du fournisseur',
    'front_image': 'Image avant',
    'back_image': 'Image arrière',
    'file_url': 'URL du fichier',
    'category': 'Catégorie',
    'title': 'Titre',
    'policy': 'Police',
    'policy_number': 'Numéro de police',
    'provider': 'Fournisseur',
    'expiry': 'Expiration',
    'specialist': 'Spécialiste',
    'guest': 'Mode invité',
    'account': 'Compte',
    'guest_data': 'Données invité',
    'full_record': 'Dossier complet',
    'share_record': 'Partager le dossier',
    'sign_up': 'S’inscrire',
    'language': 'Langue',
    'select_medication': 'Sélectionner un médicament',
    'select_time': 'Sélectionner l’heure',
    'select_date': 'Sélectionner la date',
    'required_field': 'Ce champ est obligatoire',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Veuillez vous connecter',
    'please_fill_all': 'Veuillez remplir tous les champs',
    'login_failed': 'Échec de la connexion',
    'signup_failed': 'Échec de l’inscription',
    'delete_confirm_title': 'Supprimer ?',
    'delete_confirm_msg':
        'Êtes-vous sûr de vouloir supprimer cet enregistrement ?',
    'cancel': 'Annuler',
    'please_sign_in': 'Veuillez vous connecter',
    'account_created_success':
        'Compte créé avec succès ! Veuillez vous connecter.',
    'operation_failed': 'Échec de l’opération',
    'select_front_image': 'Sélectionner l’image avant',
    'select_back_image': 'Sélectionner l’image arrière',
    'upload_image': 'Téléverser une image',
    'uploaded': 'Téléversé',
    'insurance_company_name': 'Nom de la compagnie d’assurance',
    'patient_id': 'ID du patient',
    'insurance_card_front': 'Carte d’assurance - avant',
    'insurance_card_back': 'Carte d’assurance - arrière',
    'no_image_selected': 'Aucune image sélectionnée',
    'upload_front_card': 'Téléverser la carte avant',
    'upload_back_card': 'Téléverser la carte arrière',
    'add_data': 'Ajouter les données',
    'please_enter_insurance_company':
        'Veuillez saisir le nom de la compagnie d’assurance',
    'please_enter_patient_id': 'Veuillez saisir l’ID du patient',
    'please_upload_both_cards': 'Veuillez téléverser les deux cartes',
    'success': 'Succès',
    'upload_photo': 'Téléverser une photo',
    'select_photo': 'Sélectionner une photo',
    'photo_uploaded': 'Photo téléversée',
    'please_upload_photo': 'Veuillez téléverser une photo',
    'share_app': 'Partager l’application',
    'share_app_message': 'SANA - votre application de gestion de santé !',
    'opening_payment': 'Ouverture de la page de paiement...',
    'payment_error': 'Erreur de paiement',
    'medicine_photo': 'Photo du médicament',
    'no_medicine_photo': 'Aucune photo sélectionnée',
    'upload_medicine_photo': 'Téléverser la photo du médicament',
    'change_medicine_photo': 'Modifier la photo du médicament',
    'select_reminder_times': 'Sélectionner les heures de rappel',
    'selected': 'Sélectionné',
    'medication_schedule': 'Programme du médicament',
    'choose_schedule_repeat': 'Choisissez quand répéter ce rappel :',
    'repeat_daily_msg': 'Le rappel se répétera tous les jours.',
    'select_calendar_date': 'Sélectionner la date du calendrier',
    'date': 'Date',
    'share_documents': 'Partager les documents',
    'manual_title': 'Guide médical de poche SANA',
    'manual_content':
        '1. Gérez vos dossiers de santé en toute sécurité sur le web et accédez à vos données à tout moment, où que vous soyez et depuis n\'importe quel appareil.\n2. Ajoutez et suivez les médicaments quotidiens et les dosages.\n3. Conservez les coordonnées et spécialités de vos médecins.\n4. Enregistrez vos pharmacies préférées avec adresses et téléphones.\n5. Configurez des rappels pour les heures de prise des médicaments avec alertes.\n6. Conservez les documents et rapports médicaux avec des photos.\n7. Conservez les photos recto et verso de vos cartes d\'assurance.\n8. Sélectionnez et partagez facilement vos dossiers avec vos médecins à tout moment.\n9. Installez l\'application sur votre appareil pour bénéficier de toutes les fonctionnalités et activer les alarmes de médicaments.\n10. Obtenez votre propre copie privée et dédiée, invisible pour toute autre personne.',
    'install_sana': 'Installer SANA',
    'taken': 'Pris',
    'alarm': 'Alarme de médicament',
    'daily_reminders': 'Rappels quotidiens',
    'calendar_reminders': 'Rappels programmés',
  },
  'de': {
    'add': 'Hinzufügen',
    'save': 'Speichern',
    'delete': 'Löschen',
    'view': 'Anzeigen',
    'close': 'Schließen',
    'share': 'Teilen',
    'reminders_enabled': 'Erinnerungen aktiviert',
    'install_app': 'App installieren',
    'help': 'Hilfe',
    'call': 'Anrufen',
    'chat': 'Chat',
    'write_comment': 'Schreiben Sie Ihren Kommentar...',
    'send': 'Senden',
    'comment_sent': 'Kommentar erfolgreich gesendet',
    'chat_date': 'Chat / Datum',
    'joining_date': 'Beitrittsdatum',
    'last_login': 'Letzte Anmeldung',
    'login': 'Anmelden',
    'logout': 'Abmelden',
    'admin': 'Administrator',
    'medications': 'Medikamente',
    'doctors': 'Ärzte',
    'pharmacies': 'Apotheken',
    'reminders': 'Erinnerungen',
    'documents': 'Dokumente',
    'insurance_cards': 'Versicherungskarten',
    'name': 'Name',
    'dosage': 'Dosierung',
    'notes': 'Notizen',
    'quantity': 'Bestand',
    'description': 'Beschreibung',
    'specialty': 'Fachgebiet',
    'phone': 'Telefon',
    'address': 'Adresse',
    'email': 'E-Mail oder Benutzername',
    'show_password': 'Passwort anzeigen',
    'password': 'Passwort',
    'password_6_digit': '6 Ziffern',
    'sign_in': 'Anmelden',
    'new_user': 'Neuer Benutzer',
    'register': 'Registrieren',
    'create_account': 'Konto erstellen',
    'already_account': 'Bereits ein Konto?',
    'location': 'Standort',
    'photo': 'Foto',
    'front_photo': 'Vorderseite',
    'back_photo': 'Rückseite',
    'reminder_time': 'Erinnerungszeit',
    'reminder_date': 'Erinnerungsdatum',
    'schedule_type': 'Zeitplan',
    'daily': 'Täglich',
    'calendar': 'Kalender',
    'select_times': 'Eine oder mehrere Zeiten auswählen',
    'select_schedule': 'Zeitplan auswählen',
    'record': 'Datensatz',
    'no_records': 'Keine Einträge',
    'guest_mode': 'Gastmodus',
    'get_copy': 'Kopie erhalten',
    'create_copy': 'Kopie erstellen',
    'select_all': 'Alle auswählen',
    'share_selected': 'Ausgewählte teilen',
    'no_selection': 'Keine Elemente ausgewählt',
    'admin_panel': 'Admin-Panel',
    'users': 'Benutzer',
    'activate': 'Aktivieren',
    'deactivate': 'Deaktivieren',
    'status': 'Status',
    'role': 'Rolle',
    'active_user': 'Aktiver Benutzer',
    'inactive_guest': 'Inaktiver Benutzer',
    'expired':
        'Bitte holen Sie sich Ihre eigene Kopie und warten Sie 48 Stunden, bis sie aktiviert wird.',
    'pending_activation':
        'Bitte holen Sie sich Ihre eigene Kopie und warten Sie 48 Stunden, bis sie aktiviert wird.',
    'paid': 'Bezahlt',
    'expiry_date': 'Ablaufdatum',
    'provider_name': 'Anbietername',
    'front_image': 'Vorderseite',
    'back_image': 'Rückseite',
    'file_url': 'Datei-URL',
    'category': 'Kategorie',
    'title': 'Titel',
    'policy': 'Versicherung',
    'policy_number': 'Policennummer',
    'provider': 'Anbieter',
    'expiry': 'Ablaufdatum',
    'specialist': 'Spezialist',
    'guest': 'Gastmodus',
    'account': 'Konto',
    'guest_data': 'Gastdaten',
    'full_record': 'Vollständiger Datensatz',
    'share_record': 'Datensatz teilen',
    'sign_up': 'Registrieren',
    'language': 'Sprache',
    'select_medication': 'Medikament auswählen',
    'select_time': 'Zeit auswählen',
    'select_date': 'Datum auswählen',
    'required_field': 'Dieses Feld ist erforderlich',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Bitte anmelden',
    'please_fill_all': 'Bitte alle Felder ausfüllen',
    'login_failed': 'Anmeldung fehlgeschlagen',
    'signup_failed': 'Registrierung fehlgeschlagen',
    'delete_confirm_title': 'Löschen?',
    'delete_confirm_msg': 'Möchten Sie diesen Datensatz wirklich löschen?',
    'cancel': 'Abbrechen',
    'please_sign_in': 'Bitte anmelden',
    'account_created_success': 'Konto erfolgreich erstellt! Bitte anmelden.',
    'operation_failed': 'Vorgang fehlgeschlagen',
    'select_front_image': 'Vorderes Bild auswählen',
    'select_back_image': 'Hinteres Bild auswählen',
    'upload_image': 'Bild hochladen',
    'uploaded': 'Hochgeladen',
    'insurance_company_name': 'Name der Versicherungsgesellschaft',
    'patient_id': 'Patienten-ID',
    'insurance_card_front': 'Versicherungskarte - Vorderseite',
    'insurance_card_back': 'Versicherungskarte - Rückseite',
    'no_image_selected': 'Kein Bild ausgewählt',
    'upload_front_card': 'Vorderseite der Karte hochladen',
    'upload_back_card': 'Rückseite der Karte hochladen',
    'add_data': 'Daten hinzufügen',
    'please_enter_insurance_company':
        'Bitte Namen der Versicherungsgesellschaft eingeben',
    'please_enter_patient_id': 'Bitte Patienten-ID eingeben',
    'please_upload_both_cards': 'Bitte beide Karten hochladen',
    'success': 'Erfolg',
    'upload_photo': 'Foto hochladen',
    'select_photo': 'Foto auswählen',
    'photo_uploaded': 'Foto hochgeladen',
    'please_upload_photo': 'Bitte ein Foto hochladen',
    'share_app': 'App teilen',
    'share_app_message': 'SANA - Ihre App zur Gesundheitsverwaltung!',
    'opening_payment': 'Zahlungsseite wird geöffnet...',
    'payment_error': 'Zahlungsfehler',
    'medicine_photo': 'Medikamentenfoto',
    'no_medicine_photo': 'Kein Foto ausgewählt',
    'upload_medicine_photo': 'Medikamentenfoto hochladen',
    'change_medicine_photo': 'Medikamentenfoto ändern',
    'select_reminder_times': 'Erinnerungszeiten auswählen',
    'selected': 'Ausgewählt',
    'medication_schedule': 'Medikamenten-Zeitplan',
    'choose_schedule_repeat':
        'Wählen Sie, wann diese Erinnerung wiederholt werden soll:',
    'repeat_daily_msg': 'Die Erinnerung wird täglich wiederholt.',
    'select_calendar_date': 'Kalenderdatum auswählen',
    'date': 'Datum',
    'share_documents': 'Dokumente teilen',
    'manual_title': 'SANA Medizinisches Taschenbuch',
    'manual_content':
        '1. Verwalten Sie Ihre Gesundheitsdaten sicher im Web und greifen Sie jederzeit, überall und von jedem Gerät auf Ihre Daten zu.\n2. Verfolgen Sie tägliche Medikamente und Dosierungen.\n3. Speichern Sie Kontaktdaten Ihrer Ärzte und Fachgebiete.\n4. Speichern Sie Apotheken mit Adresse und Telefonnummer.\n5. Stellen Sie Erinnerungen für die Medikamenteneinnahme mit Alarm ein.\n6. Speichern Sie medizinische Dokumente und Berichte mit Fotos.\n7. Speichern Sie Vorder- und Rückseite Ihrer Versicherungskarten.\n8. Wählen Sie Datensätze aus und teilen Sie diese jederzeit mit Ihrem Arzt.\n9. Installieren Sie die App auf Ihrem Gerät, um alle Funktionen zu nutzen und Medikamentenalarme zu aktivieren.\n10. Erhalten Sie Ihre eigene private, persönliche Kopie, die für niemand anderen sichtbar ist.',
    'install_sana': 'SANA installieren',
    'taken': 'Eingenommen',
    'alarm': 'Medikamenten-Alarm',
    'daily_reminders': 'Tägliche Erinnerungen',
    'calendar_reminders': 'Geplante Erinnerungen',
  },
  'tr': {
    'add': 'Ekle',
    'save': 'Kaydet',
    'delete': 'Sil',
    'view': 'Görüntüle',
    'close': 'Kapat',
    'share': 'Paylaş',
    'reminders_enabled': 'Hatırlatıcılar etkinleştirildi',
    'install_app': 'Uygulamayı yükle',
    'help': 'Yardım',
    'call': 'Ara',
    'chat': 'Sohbet',
    'write_comment': 'Yorumunuzu yazın...',
    'send': 'Gönder',
    'comment_sent': 'Yorum başarıyla gönderildi',
    'chat_date': 'Sohbet / Tarih',
    'joining_date': 'Katılım Tarihi',
    'last_login': 'Son Giriş',
    'login': 'Giriş Yap',
    'logout': 'Çıkış Yap',
    'admin': 'Yönetici',
    'medications': 'İlaçlar',
    'doctors': 'Doktorlar',
    'pharmacies': 'Eczaneler',
    'reminders': 'Hatırlatıcılar',
    'documents': 'Belgeler',
    'insurance_cards': 'Sigorta Kartları',
    'name': 'Ad',
    'dosage': 'Doz',
    'notes': 'Notlar',
    'quantity': 'Stok',
    'description': 'Açıklama',
    'specialty': 'Uzmanlık',
    'phone': 'Telefon',
    'address': 'Adres',
    'email': 'E-posta veya kullanıcı adı',
    'show_password': 'Şifreyi göster',
    'password': 'Şifre',
    'password_6_digit': '6 hane',
    'sign_in': 'Giriş Yap',
    'new_user': 'Yeni Kullanıcı',
    'register': 'Kayıt Ol',
    'create_account': 'Hesap Oluştur',
    'already_account': 'Zaten hesabınız var mı?',
    'location': 'Konum',
    'photo': 'Fotoğraf',
    'front_photo': 'Ön Fotoğraf',
    'back_photo': 'Arka Fotoğraf',
    'reminder_time': 'Hatırlatma Saati',
    'reminder_date': 'Hatırlatma Tarihi',
    'schedule_type': 'Program',
    'daily': 'Günlük',
    'calendar': 'Takvim',
    'select_times': 'Bir veya daha fazla saat seçin',
    'select_schedule': 'Program seç',
    'record': 'Kayıt',
    'no_records': 'Kayıt yok',
    'guest_mode': 'Misafir Modu',
    'get_copy': 'Kopyanı Al',
    'create_copy': 'Kopyanı Oluştur',
    'select_all': 'Tümünü Seç',
    'share_selected': 'Seçilenleri Paylaş',
    'no_selection': 'Seçim yok',
    'admin_panel': 'Yönetici Paneli',
    'users': 'Kullanıcılar',
    'activate': 'Etkinleştir',
    'deactivate': 'Devre Dışı Bırak',
    'status': 'Durum',
    'role': 'Rol',
    'active_user': 'Aktif Kullanıcı',
    'inactive_guest': 'Pasif Kullanıcı',
    'expired':
        'Lütfen kendi kopyanızı alın ve etkinleştirilene kadar 48 saat bekleyin.',
    'pending_activation':
        'Lütfen kendi kopyanızı alın ve etkinleştirilene kadar 48 saat bekleyin.',
    'paid': 'Ödendi',
    'expiry_date': 'Son Kullanma Tarihi',
    'provider_name': 'Sağlayıcı Adı',
    'front_image': 'Ön Görsel',
    'back_image': 'Arka Görsel',
    'file_url': 'Dosya URL’si',
    'category': 'Kategori',
    'title': 'Başlık',
    'policy': 'Poliçe',
    'policy_number': 'Poliçe Numarası',
    'provider': 'Sağlayıcı',
    'expiry': 'Son Kullanma',
    'specialist': 'Uzman',
    'guest': 'Misafir Modu',
    'account': 'Hesap',
    'guest_data': 'Misafir Verileri',
    'full_record': 'Tam Kayıt',
    'share_record': 'Kaydı Paylaş',
    'sign_up': 'Kayıt Ol',
    'language': 'Dil',
    'select_medication': 'İlaç Seç',
    'select_time': 'Saat Seç',
    'select_date': 'Tarih Seç',
    'required_field': 'Bu alan zorunludur',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Lütfen giriş yapın',
    'please_fill_all': 'Lütfen tüm alanları doldurun',
    'login_failed': 'Giriş başarısız',
    'signup_failed': 'Kayıt başarısız',
    'delete_confirm_title': 'Silinsin mi?',
    'delete_confirm_msg': 'Bu kaydı silmek istediğinizden emin misiniz?',
    'cancel': 'İptal',
    'please_sign_in': 'Lütfen giriş yapın',
    'account_created_success':
        'Hesap başarıyla oluşturuldu! Lütfen giriş yapın.',
    'operation_failed': 'İşlem başarısız',
    'select_front_image': 'Ön görseli seç',
    'select_back_image': 'Arka görseli seç',
    'upload_image': 'Görsel yükle',
    'uploaded': 'Yüklendi',
    'insurance_company_name': 'Sigorta şirketi adı',
    'patient_id': 'Hasta kimliği',
    'insurance_card_front': 'Sigorta kartı - Ön',
    'insurance_card_back': 'Sigorta kartı - Arka',
    'no_image_selected': 'Görsel seçilmedi',
    'upload_front_card': 'Ön kartı yükle',
    'upload_back_card': 'Arka kartı yükle',
    'add_data': 'Veri ekle',
    'please_enter_insurance_company': 'Lütfen sigorta şirketinin adını girin',
    'please_enter_patient_id': 'Lütfen hasta kimliğini girin',
    'please_upload_both_cards': 'Lütfen her iki kartı da yükleyin',
    'success': 'Başarılı',
    'upload_photo': 'Fotoğraf yükle',
    'select_photo': 'Fotoğraf seç',
    'photo_uploaded': 'Fotoğraf yüklendi',
    'please_upload_photo': 'Lütfen bir fotoğraf yükleyin',
    'share_app': 'Uygulamayı paylaş',
    'share_app_message': 'SANA - sağlık yönetimi uygulamanız!',
    'opening_payment': 'Ödeme sayfası açılıyor...',
    'payment_error': 'Ödeme hatası',
    'medicine_photo': 'İlaç fotoğrafı',
    'no_medicine_photo': 'İlaç fotoğrafı seçilmedi',
    'upload_medicine_photo': 'İlaç fotoğrafı yükle',
    'change_medicine_photo': 'İlaç fotoğrafını değiştir',
    'select_reminder_times': 'Hatırlatma saatlerini seçin',
    'selected': 'Seçilen',
    'medication_schedule': 'İlaç programı',
    'choose_schedule_repeat':
        'Bu hatırlatmanın ne zaman tekrarlanacağını seçin:',
    'repeat_daily_msg': 'Hatırlatma her gün tekrarlanacak.',
    'select_calendar_date': 'Takvim tarihini seçin',
    'date': 'Tarih',
    'share_documents': 'Belgeleri Paylaş',
    'manual_title': 'SANA Cep Sağlık Rehberi',
    'manual_content':
        '1. Sağlık kayıtlarınızı web üzerinde güvenle yönetin ve verilerinize her zaman, her yerden ve herhangi bir cihazdan erişin.\n2. Günlük ilaçlarınızı ve dozajlarınızı takip edin.\n3. Doktor iletişim ve uzmanlık bilgilerini kaydedin.\n4. Eczaneleri telefon ve adres bilgileriyle saklayın.\n5. Uyarılarla birlikte çoklu saat seçenekleriyle ilaç hatırlatıcıları kurun.\n6. Tıbbi rapor ve belgelerinizi fotoğraflarla kaydedin.\n7. Sigorta kartlarınızın ön ve arka fotoğraflarını saklayın.\n8. Kayıtlarınızı seçerek dilediğiniz zaman doktorunuzla paylaşın.\n9. Tüm özellikleri kullanmak ve ilaç alarmlarını etkinleştirmek için uygulamayı cihazınıza yükleyin.\n10. Başka hiç kimsenin göremeyeceği, size özel ve bağımsız bir kopyanızı edinin.',
    'install_sana': 'SANA\'yı yükle',
    'taken': 'Alındı',
    'alarm': 'İlaç Alarmı',
    'daily_reminders': 'Günlük Hatırlatıcılar',
    'calendar_reminders': 'Planlanmış Hatırlatıcılar',
  },
  'hi': {
    'add': 'जोड़ें',
    'save': 'सहेजें',
    'delete': 'हटाएँ',
    'view': 'देखें',
    'close': 'बंद करें',
    'share': 'साझा करें',
    'reminders_enabled': 'अनुस्मारक सक्षम किए गए',
    'install_app': 'ऐप इंस्टॉल करें',
    'help': 'मदद',
    'call': 'कॉल करें',
    'chat': 'चैट',
    'write_comment': 'अपनी टिप्पणी लिखें...',
    'send': 'भेजें',
    'comment_sent': 'टिप्पणी सफलतापूर्वक भेजी गई',
    'chat_date': 'चैट / दिनांक',
    'joining_date': 'शामिल होने की तिथि',
    'last_login': 'अंतिम लॉगिन',
    'login': 'लॉग इन',
    'logout': 'लॉग आउट',
    'admin': 'व्यवस्थापक',
    'medications': 'दवाइयाँ',
    'doctors': 'डॉक्टर',
    'pharmacies': 'फार्मेसी',
    'reminders': 'रिमाइंडर',
    'documents': 'दस्तावेज़',
    'insurance_cards': 'बीमा कार्ड',
    'name': 'नाम',
    'dosage': 'खुराक',
    'notes': 'टिप्पणियाँ',
    'quantity': 'स्टॉक',
    'description': 'विवरण',
    'specialty': 'विशेषता',
    'phone': 'फ़ोन',
    'address': 'पता',
    'email': 'ईमेल या उपयोगकर्ता नाम',
    'show_password': 'पासवर्ड दिखाएँ',
    'password': 'पासवर्ड',
    'password_6_digit': '6 अंक',
    'sign_in': 'साइन इन',
    'new_user': 'नया उपयोगकर्ता',
    'register': 'पंजीकरण',
    'create_account': 'खाता बनाएँ',
    'already_account': 'क्या आपके पास पहले से खाता है?',
    'location': 'स्थान',
    'photo': 'फ़ोटो',
    'front_photo': 'सामने की फ़ोटो',
    'back_photo': 'पीछे की फ़ोटो',
    'reminder_time': 'रिमाइंडर समय',
    'reminder_date': 'रिमाइंडर तारीख',
    'schedule_type': 'समय-सारणी',
    'daily': 'दैनिक',
    'calendar': 'कैलेंडर',
    'select_times': 'एक या अधिक समय चुनें',
    'select_schedule': 'समय-सारणी चुनें',
    'record': 'रिकॉर्ड',
    'no_records': 'कोई रिकॉर्ड नहीं',
    'guest_mode': 'अतिथि मोड',
    'get_copy': 'अपनी कॉपी पाएँ',
    'create_copy': 'अपनी कॉपी बनाएँ',
    'select_all': 'सभी चुनें',
    'share_selected': 'चयनित साझा करें',
    'no_selection': 'कोई आइटम चयनित नहीं',
    'admin_panel': 'व्यवस्थापक पैनल',
    'users': 'उपयोगकर्ता',
    'activate': 'सक्रिय करें',
    'deactivate': 'निष्क्रिय करें',
    'status': 'स्थिति',
    'role': 'भूमिका',
    'active_user': 'सक्रिय उपयोगकर्ता',
    'inactive_guest': 'निष्क्रिय उपयोगकर्ता',
    'expired':
        'कृपया अपनी प्रति प्राप्त करें और सक्रिय होने तक 48 घंटे प्रतीक्षा करें।',
    'pending_activation':
        'कृपया अपनी प्रति प्राप्त करें और सक्रिय होने तक 48 घंटे प्रतीक्षा करें।',
    'paid': 'भुगतान किया गया',
    'expiry_date': 'समाप्ति तिथि',
    'provider_name': 'प्रदाता का नाम',
    'front_image': 'सामने की छवि',
    'back_image': 'पीछे की छवि',
    'file_url': 'फ़ाइल URL',
    'category': 'श्रेणी',
    'title': 'शीर्षक',
    'policy': 'पॉलिसी',
    'policy_number': 'पॉलिसी संख्या',
    'provider': 'प्रदाता',
    'expiry': 'समाप्ति',
    'specialist': 'विशेषज्ञ',
    'guest': 'अतिथि मोड',
    'account': 'खाता',
    'guest_data': 'अतिथि डेटा',
    'full_record': 'पूरा रिकॉर्ड',
    'share_record': 'रिकॉर्ड साझा करें',
    'sign_up': 'साइन अप',
    'language': 'भाषा',
    'select_medication': 'दवा चुनें',
    'select_time': 'समय चुनें',
    'select_date': 'तारीख चुनें',
    'required_field': 'यह फ़ील्ड आवश्यक है',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'कृपया लॉग इन करें',
    'please_fill_all': 'कृपया सभी फ़ील्ड भरें',
    'login_failed': 'लॉग इन विफल',
    'signup_failed': 'साइन अप विफल',
    'delete_confirm_title': 'हटाएँ?',
    'delete_confirm_msg': 'क्या आप वाकई इस रिकॉर्ड को हटाना चाहते हैं?',
    'cancel': 'रद्द करें',
    'please_sign_in': 'कृपया साइन इन करें',
    'account_created_success':
        'खाता सफलतापूर्वक बनाया गया! कृपया साइन इन करें।',
    'operation_failed': 'ऑपरेशन विफल',
    'select_front_image': 'सामने की छवि चुनें',
    'select_back_image': 'पीछे की छवि चुनें',
    'upload_image': 'छवि अपलोड करें',
    'uploaded': 'अपलोड हो गया',
    'insurance_company_name': 'बीमा कंपनी का नाम',
    'patient_id': 'मरीज़ ID',
    'insurance_card_front': 'बीमा कार्ड - सामने',
    'insurance_card_back': 'बीमा कार्ड - पीछे',
    'no_image_selected': 'कोई छवि चयनित नहीं',
    'upload_front_card': 'सामने का कार्ड अपलोड करें',
    'upload_back_card': 'पीछे का कार्ड अपलोड करें',
    'add_data': 'डेटा जोड़ें',
    'please_enter_insurance_company': 'कृपया बीमा कंपनी का नाम दर्ज करें',
    'please_enter_patient_id': 'कृपया मरीज़ ID दर्ज करें',
    'please_upload_both_cards': 'कृपया दोनों कार्ड अपलोड करें',
    'success': 'सफल',
    'upload_photo': 'फ़ोटो अपलोड करें',
    'select_photo': 'फ़ोटो चुनें',
    'photo_uploaded': 'फ़ोटो अपलोड हो गई',
    'please_upload_photo': 'कृपया फ़ोटो अपलोड करें',
    'share_app': 'ऐप साझा करें',
    'share_app_message': 'SANA - आपका स्वास्थ्य प्रबंधन ऐप!',
    'opening_payment': 'भुगतान पृष्ठ खोल रहा है...',
    'payment_error': 'भुगतान त्रुटि',
    'medicine_photo': 'दवा की फ़ोटो',
    'no_medicine_photo': 'कोई दवा फ़ोटो चयनित नहीं',
    'upload_medicine_photo': 'दवा की फ़ोटो अपलोड करें',
    'change_medicine_photo': 'दवा की फ़ोटो बदलें',
    'select_reminder_times': 'रिमाइंडर समय चुनें',
    'selected': 'चयनित',
    'medication_schedule': 'दवा समय-सारणी',
    'choose_schedule_repeat': 'चुनें कि यह रिमाइंडर कब दोहराया जाना चाहिए:',
    'repeat_daily_msg': 'रिमाइंडर हर दिन दोहराया जाएगा।',
    'select_calendar_date': 'कैलेंडर तारीख चुनें',
    'date': 'तारीख',
    'share_documents': 'दस्तावेज़ साझा करें',
    'manual_title': 'साना मेडिकल पॉकेट बुक',
    'manual_content':
        '1. वेब पर अपने स्वास्थ्य रिकॉर्ड को सुरक्षित रूप से प्रबंधित करें और किसी भी समय, कहीं से भी और किसी भी डिवाइस से अपने डेटा तक पहुँचें।\n2. दैनिक दवाइयाँ और उनकी खुराक आसानी से ट्रैक करें।\n3. अपने डॉक्टरों के संपर्क और विशेषता नोट रखें।\n4. अपनी पसंदीदा फार्मेसी का पता और फोन सेव करें।\n5. अलर्ट के साथ दवा लेने के लिए कई समय के रिमाइंडर सेट करें।\n6. मेडिकल दस्तावेज़ और रिपोर्ट फोटो के साथ रखें।\n7. बीमा कार्ड की आगे और पीछे की फोटो सुरक्षित रखें।\n8. डॉक्टर के साथ कभी भी जरूरी रिकॉर्ड चुनें और साझा करें।\n9. सभी सुविधाएँ प्राप्त करने और दवा के अलार्म सक्रिय करने के लिए अपने डिवाइस पर ऐप इंस्टॉल करें।\n10. अपनी निजी और समर्पित प्रति प्राप्त करें, जिसे कोई अन्य व्यक्ति नहीं देख सकता।',
    'install_sana': 'SANA इंस्टॉल करें',
    'taken': 'दवा ले ली',
    'alarm': 'दवा का अलार्म',
    'daily_reminders': 'दैनिक अनुस्मारक',
    'calendar_reminders': 'निर्धारित अनुस्मारक',
  },
  'zh': {
    'add': '添加',
    'save': '保存',
    'delete': '删除',
    'view': '查看',
    'close': '关闭',
    'share': '分享',
    'reminders_enabled': '提醒已启用',
    'install_app': '安装应用',
    'help': '帮助',
    'call': '呼叫',
    'chat': '聊天',
    'write_comment': '输入您的评论...',
    'send': '发送',
    'comment_sent': '评论发送成功',
    'chat_date': '聊天 / 日期',
    'joining_date': '加入日期',
    'last_login': '上次登录',
    'login': '登录',
    'logout': '退出登录',
    'admin': '管理员',
    'medications': '药物',
    'doctors': '医生',
    'pharmacies': '药房',
    'reminders': '提醒',
    'documents': '文档',
    'insurance_cards': '保险卡',
    'name': '姓名',
    'dosage': '剂量',
    'notes': '备注',
    'quantity': '库存',
    'description': '描述',
    'specialty': '专科',
    'phone': '电话',
    'address': '地址',
    'email': '电子邮件或用户名',
    'show_password': '显示密码',
    'password': '密码',
    'password_6_digit': '6 位数字',
    'sign_in': '登录',
    'new_user': '新用户',
    'register': '注册',
    'create_account': '创建账户',
    'already_account': '已经有账户？',
    'location': '位置',
    'photo': '照片',
    'front_photo': '正面照片',
    'back_photo': '背面照片',
    'reminder_time': '提醒时间',
    'reminder_date': '提醒日期',
    'schedule_type': '计划',
    'daily': '每天',
    'calendar': '日历',
    'select_times': '选择一个或多个时间',
    'select_schedule': '选择计划',
    'record': '记录',
    'no_records': '没有记录',
    'guest_mode': '访客模式',
    'get_copy': '获取你的副本',
    'create_copy': '创建你的副本',
    'select_all': '全选',
    'share_selected': '分享所选内容',
    'no_selection': '未选择任何项目',
    'admin_panel': '管理面板',
    'users': '用户',
    'activate': '启用',
    'deactivate': '停用',
    'status': '状态',
    'role': '角色',
    'active_user': '活跃用户',
    'inactive_guest': '非活跃用户',
    'expired': '请获取您自己的副本，并等待48小时直到激活。',
    'pending_activation': '请获取您自己的副本，并等待48小时直到激活。',
    'paid': '已付款',
    'expiry_date': '到期日',
    'provider_name': '提供商名称',
    'front_image': '正面图片',
    'back_image': '背面图片',
    'file_url': '文件链接',
    'category': '类别',
    'title': '标题',
    'policy': '保单',
    'policy_number': '保单号码',
    'provider': '提供商',
    'expiry': '到期日',
    'specialist': '专家',
    'guest': '访客模式',
    'account': '账户',
    'guest_data': '访客数据',
    'full_record': '完整记录',
    'share_record': '分享记录',
    'sign_up': '注册',
    'language': '语言',
    'select_medication': '选择药物',
    'select_time': '选择时间',
    'select_date': '选择日期',
    'required_field': '此字段为必填项',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': '请登录',
    'please_fill_all': '请填写所有字段',
    'login_failed': '登录失败',
    'signup_failed': '注册失败',
    'delete_confirm_title': '删除？',
    'delete_confirm_msg': '确定要删除此记录吗？',
    'cancel': '取消',
    'please_sign_in': '请登录',
    'account_created_success': '账户创建成功！请登录。',
    'operation_failed': '操作失败',
    'select_front_image': '选择正面图片',
    'select_back_image': '选择背面图片',
    'upload_image': '上传图片',
    'uploaded': '已上传',
    'insurance_company_name': '保险公司名称',
    'patient_id': '患者 ID',
    'insurance_card_front': '保险卡 - 正面',
    'insurance_card_back': '保险卡 - 背面',
    'no_image_selected': '未选择图片',
    'upload_front_card': '上传正面卡片',
    'upload_back_card': '上传背面卡片',
    'add_data': '添加数据',
    'please_enter_insurance_company': '请输入保险公司名称',
    'please_enter_patient_id': '请输入患者 ID',
    'please_upload_both_cards': '请上传两张卡片',
    'success': '成功',
    'upload_photo': '上传照片',
    'select_photo': '选择照片',
    'photo_uploaded': '照片已上传',
    'please_upload_photo': '请上传照片',
    'share_app': '分享应用',
    'share_app_message': 'SANA - 您的健康管理应用！',
    'opening_payment': '正在打开支付页面...',
    'payment_error': '支付错误',
    'medicine_photo': '药物照片',
    'no_medicine_photo': '未选择药物照片',
    'upload_medicine_photo': '上传药物照片',
    'change_medicine_photo': '更换药物照片',
    'select_reminder_times': '选择提醒时间',
    'selected': '已选',
    'medication_schedule': '药物服药计划',
    'choose_schedule_repeat': '选择何时重复此提醒：',
    'repeat_daily_msg': '提醒将每天重复。',
    'select_calendar_date': '选择日历日期',
    'date': '日期',
    'share_documents': '分享文档',
    'manual_title': 'SANA 随身健康手册',
    'manual_content':
        '1. 在网页端安全管理您的健康记录，并随时随地通过任何设备访问您的数据。\n2. 轻松添加并跟踪每日药物用量和频率。\n3. 保存医生专科信息与联系方式。\n4. 保存常用药房地址与联系电话。\n5. 设置多时间段带提示的服药提醒。\n6. 拍摄并保存医疗报告与检查单。\n7. 保存医保卡正面和反面照片。\n8. 随时勾选并向医生分享您的健康档案。\n9. 将应用程序安装到您的设备上，以获得全部功能并启用服药提醒和闹钟。\n10. 获取属于您自己的私密专属副本，任何其他人都无法看到。',
    'install_sana': '安装 SANA',
    'taken': '已服药',
    'alarm': '服药提醒',
    'daily_reminders': '每日提醒',
    'calendar_reminders': '计划提醒',
  },
};

String tr(String code, String key) =>
    _translations[code]?[key] ?? _translations['en']![key] ?? key;

// ============================================
// LANGUAGE BUTTONS
// ============================================

class LanguageButtons extends StatelessWidget {
  const LanguageButtons({super.key});

  static const Map<String, Color> _langColors = {
    'en': Color(0xFF00897B), // Teal
    'ar': Color(0xFFE65100), // Orange
    'es': Color(0xFFC2185B), // Pink/Magenta
    'fr': Color(0xFF1E88E5), // Blue
    'de': Color(0xFF6D4C41), // Brown
    'tr': Color(0xFFE53935), // Red
    'hi': Color(0xFFF57C00), // Amber
    'zh': Color(0xFF5E35B1), // Purple
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, currentLang, _) {
        return SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _languageNames.entries.map((entry) {
              final selected = currentLang == entry.key;
              final color = _langColors[entry.key] ?? Colors.teal;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.0),
                  child: FilledButton(
                    onPressed: () => languageNotifier.value = entry.key,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          selected ? color : color.withValues(alpha: 0.15),
                      foregroundColor: selected ? Colors.white : color,
                      minimumSize: const Size(0, 28),
                      maximumSize: const Size(double.infinity, 28),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ============================================
// GUEST IDENTITY
// ============================================

// ============================================
// GUEST IDENTITY - WITH CACHING
// ============================================

// ============================================
// MAIN
// ============================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await SanaAlarmService.initialize();
  }

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseKey,
  );

  final client = Supabase.instance.client;

  if (client.auth.currentUser == null) {
    await client.auth.signInAnonymously();
  }

  // Explicit deep-link: ?reminder=<id> opens the alarm screen.
  String? pendingReminderId;
  if (kIsWeb) {
    pendingReminderId = Uri.base.queryParameters['reminder'];
  }

  runApp(SanaApp(pendingReminderId: pendingReminderId));
}

// SANA DIAG PANEL
final sanaDiag = ValueNotifier<String>('diag: start');

class SanaDiagOverlay extends StatelessWidget {
  const SanaDiagOverlay({super.key});
  @override
  Widget build(BuildContext c) => Positioned(
        top: 0,
        left: 0,
        child: Container(
          color: const Color(0xCC000000),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(maxWidth: 260),
          child: ValueListenableBuilder<String>(
            valueListenable: sanaDiag,
            builder: (c, v, _) => Text(v,
                style: const TextStyle(color: Color(0xFFFFEB3B), fontSize: 10)),
          ),
        ),
      );
}

class SanaInstallBanner extends StatefulWidget {
  final String language;
  const SanaInstallBanner({super.key, required this.language});

  @override
  State<SanaInstallBanner> createState() => _SanaInstallBannerState();
}

class _SanaInstallBannerState extends State<SanaInstallBanner> {
  bool _loading = true;
  String _mode = 'none';

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final installed = await SanaPwaInstall.isInstalled();
    if (installed) {
      if (!mounted) return;
      setState(() {
        _mode = 'installed';
        _loading = false;
      });
      return;
    }
    final android = await SanaPwaInstall.isAndroidChrome();
    if (android) {
      if (!mounted) return;
      setState(() {
        _mode = 'android';
        _loading = false;
      });
      return;
    }
    final ios = await SanaPwaInstall.isIosSafari();
    if (ios) {
      if (!mounted) return;
      setState(() {
        _mode = 'ios';
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _mode = 'none';
      _loading = false;
    });
  }

  String _t(String key) => tr(widget.language, key);

  Future<void> _tapAndroid() async {
    final result = await SanaPwaInstall.triggerInstall();
    if (!mounted) return;
    if (result != 'OK') {
      _showChromeManualGuide();
    }
  }

  void _showChromeManualGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('install_app')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('1. Tap the ? menu at the top right of Chrome.'),
              SizedBox(height: 8),
              Text('2. Tap "Add to Home screen" or "Install app".'),
              SizedBox(height: 8),
              Text('3. Tap "Install" to confirm.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }

  void _showIosGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('install_app')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. ${_t('pwa_step_1')}'),
              const SizedBox(height: 8),
              Text('2. ${_t('pwa_step_2')}'),
              const SizedBox(height: 8),
              Text('3. ${_t('pwa_step_3')}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_mode == 'installed') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        border: Border.all(color: Colors.teal.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.install_mobile, color: Colors.teal, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('install_sana'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _t('pwa_install_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _mode == 'android' ? _tapAndroid : _showIosGuide,
            child: Text(_t('install_app')),
          ),
        ],
      ),
    );
  }
}

class SanaApp extends StatefulWidget {
  final String? pendingReminderId;
  const SanaApp({super.key, this.pendingReminderId});

  @override
  State<SanaApp> createState() => _SanaAppState();
}

class _SanaAppState extends State<SanaApp> {
  String? _reminderId;

  @override
  void initState() {
    super.initState();
    _reminderId = widget.pendingReminderId;

    if (kIsWeb) {
      SanaWebEvents.installPopStateListener((id) {
        if (!mounted) return;
        if (id != null && id.isNotEmpty) {
          final nav = navigatorKey.currentState;
          if (nav != null) {
            nav.push(
              MaterialPageRoute(
                builder: (_) => SanaAlarmScreen(
                  reminderId: id,
                  notificationId: 0,
                  daily: false,
                ),
              ),
            );
          }
        }
      });

      if (_reminderId != null && _reminderId!.isNotEmpty) {
        final id = _reminderId!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = navigatorKey.currentState;
          if (nav != null) {
            nav.push(
              MaterialPageRoute(
                builder: (_) => SanaAlarmScreen(
                  reminderId: id,
                  notificationId: 0,
                  daily: false,
                ),
              ),
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'SANA',
        debugShowCheckedModeBanner: false,
        locale: Locale(language),
        supportedLocales: _languageNames.keys.map(Locale.new).toList(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.light,
        ),
        home: Directionality(
          textDirection:
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: const HomeScreen(),
        ),
      ),
    );
  }
}
// ============================================
// CHAT SCREEN
// ============================================

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _client.rpc('save_user_chat', params: {'p_comment': text});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(languageNotifier.value, 'comment_sent'))),
      );
      Navigator.of(context).pop(); // Returns directly to HomeScreen
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = languageNotifier.value;
    return Directionality(
      textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(tr(language, 'chat'))),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: tr(language, 'write_comment'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _sending ? null : _sendComment,
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr(language, 'send')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// HOME SCREEN
// ============================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _loading = true, _isGuest = true;
  String? _guestId;
  String? _lastNativeAlarmOwnerKey;
  bool _guestRemindersEnabled = true;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _loadSession();
    });
    _loadSession();

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _reconcileAllReminderAlarms();
        } catch (e) {
          debugPrint('Web reminder startup reconciliation failed: $e');
        }
      });

      SanaWebEvents.installServiceWorkerMessageListener((map) {
        try {
          final type = map['type']?.toString() ?? '';
          final rid = map['reminder_id']?.toString() ?? '';

          if (type == 'sana-taken') {
            SanaAlarmService.stopAlarmSound();
            return;
          }

          if (type == 'sana-open-reminder' && rid.isNotEmpty) {
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            SanaAlarmService.stopAlarmSound();
            nav.push(
              MaterialPageRoute(
                builder: (_) => SanaAlarmScreen(
                  reminderId: rid,
                  notificationId: 0,
                  daily: false,
                ),
              ),
            );
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _loadSession() async {
    try {
      final user = _client.auth.currentUser;
      final isRealUser = user != null && user.isAnonymous == false;

      final guestId =
          user?.isAnonymous == true ? GuestIdentityService.sharedGuestId : null;

      final ownerKey = user == null
          ? 'none'
          : user.isAnonymous
              ? 'guest:${user.id}'
              : 'user:${user.id}';

      if (_lastNativeAlarmOwnerKey != ownerKey) {
        await SanaAlarmService.clearAllNativeAlarms();
        _lastNativeAlarmOwnerKey = ownerKey;
      }

      if (mounted) {
        setState(() {
          _guestId = guestId;
          _isGuest = !isRealUser;
          _loading = false;
        });
      }

      try {
        if (user != null) {
          String? tz;
          if (kIsWeb) {
            tz = SanaWebPush.browserTimeZone();
          } else {
            tz = await FlutterTimezone.getLocalTimezone();
          }
          if (tz != null && tz.isNotEmpty) {
            await _client
                .from('users')
                .update({'timezone': tz}).eq('id', user.id);
          }
        }
      } catch (_) {}

      if (!isRealUser) {
        final guestPrefs = await SharedPreferences.getInstance();
        final guestRemindersEnabled =
            guestPrefs.getBool('sana_guest_reminders_enabled') ?? true;
        if (!mounted) return;
        setState(() {
          _profile = null;
          _guestId = guestId;
          _isGuest = true;
          _guestRemindersEnabled = guestRemindersEnabled;
          _loading = false;
        });

        unawaited(
          _warmDataCache(
            guestMode: true,
            ownerId: null,
          ),
        );

        if (_guestRemindersEnabled) {
          unawaited(
            _reconcileAllReminderAlarms(),
          );
        }

        return;
      }

      Map<String, dynamic>? data;
      try {
        data = await _client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (_) {
        data = null;
      }

      // ??? ADMIN IS PERMANENTLY EXEMPT FROM DEACTIVATION AND EXPIRY:
      final userEmail = (user.email ?? '').trim().toLowerCase();
      final role = (data?['role'] ?? '').toString().toLowerCase();

      // The authenticated Admin email and the server-side Admin role
      // both identify the existing Admin account.
      bool isAdmin = userEmail == 'malazjanbeih@gmail.com' || role == 'admin';

      // Use the server-side RPC as an additional Admin confirmation.
      // If the RPC is temporarily unavailable, DO NOT kick out an Admin
      // who is already identified by the authenticated email or role.
      if (!isAdmin) {
        try {
          final rpcIsAdmin = await _client.rpc('sana_is_admin');
          if (rpcIsAdmin == true) {
            isAdmin = true;
          }
        } catch (e) {
          debugPrint('sana_is_admin notice: $e');
        }
      }

      final isActive = data?['is_active'];

      // ONLY NON-ADMIN USERS CAN BE BLOCKED BY is_active == false.
      if (!isAdmin && isActive == false) {
        await _client.auth.signOut();
        StorageHelper.clearCache();

        if (!mounted) return;

        setState(() {
          _profile = null;
          _guestId = guestId;
          _isGuest = true;
          _loading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              tr(languageNotifier.value, 'expired'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            duration: const Duration(seconds: 5),
          ),
        );

        return;
      }

      if (!mounted) return;
      setState(() {
        _profile = data;
        _guestId = guestId;
        _isGuest = false;
        _loading = false;
      });

      if (data?['reminders_enabled'] != false) {
        unawaited(
          _reconcileAllReminderAlarms(),
        );
      }

      unawaited(
        _warmDataCache(
          guestMode: false,
          ownerId: user.id,
        ),
      );
    } catch (_) {
      if (mounted) {
        final fallbackUser = _client.auth.currentUser;
        final guestId = fallbackUser?.isAnonymous == true
            ? GuestIdentityService.sharedGuestId
            : null;
        setState(() {
          _profile = null;
          _guestId = guestId;
          _isGuest = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _warmDataCache({
    required bool guestMode,
    required String? ownerId,
  }) async {
    Future<void> warmTable(
      String table,
      String columns,
    ) async {
      try {
        final query = _client.from(table).select(columns);

        final dynamic response = guestMode || ownerId == null
            ? await query.eq('guest_id', GuestIdentityService.sharedGuestId)
            : await query.eq('user_id', ownerId);

        final List<dynamic> list = response as List<dynamic>;

        final serverRows = list
            .map(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList();

        SanaStore.instance.reconcile(
          table,
          serverRows,
        );
      } catch (e) {
        debugPrint(
          'Background cache warm failed for $table: $e',
        );
      }
    }

    await warmTable(
      'medications',
      'id, user_id, guest_id, name, dosage, reminder_time, '
          'reminder_date, reminder_schedule_type, photo_url, '
          'ringtone_path, notes',
    );

    await warmTable(
      'reminders',
      'id, user_id, guest_id, medication_id, name, dosage, '
          'reminder_time, reminder_date, description, is_active, '
          'notes, created_at, updated_at, photo_url, photo_base64',
    );

    await warmTable(
      'documents',
      'id, user_id, guest_id, title, category, file_url, '
          'file_type, photo_url, photo, photo_base64',
    );

    await warmTable(
      'insurance_cards',
      'id, user_id, guest_id, provider_name, policy_number, '
          'front_image_url, back_image_url, created_at, photo_url',
    );

    await warmTable(
      'doctors',
      'id, user_id, guest_id, name, specialty, phone, address',
    );

    await warmTable(
      'pharmacies',
      'id, user_id, guest_id, name, address, phone',
    );
  }

  String? get _ownerId {
    final user = _client.auth.currentUser;
    if (user != null && user.isAnonymous == false) {
      return user.id;
    }
    return _guestId;
  }

  Future<void> _setRemindersEnabled(bool value) async {
    // Save previous value for rollback if backend fails
    final previousValue = _isGuest
        ? _guestRemindersEnabled
        : _profile?['reminders_enabled'] == true;

    // (1) IMMEDIATE UI UPDATE (Instant response on screen)
    if (mounted) {
      setState(() {
        if (_isGuest) {
          _guestRemindersEnabled = value;
        } else {
          _profile?['reminders_enabled'] = value;
        }
      });
    }

    final user = _client.auth.currentUser;

    // (2) Background operations (Network / SharedPreferences / Alarms)
    try {
      if (kIsWeb) {
        if (value) {
          await SanaWebAlarm.unlockAudio();

          final result = await SanaWebPush.enableVerbose(_client);
          if (result != 'OK') {
            throw Exception('Web Push: $result');
          }

          await _reconcileAllReminderAlarms();
        } else {
          await SanaWebPush.disable(_client);
          await SanaWebAlarm.cancelAllReminders();
        }
      }

      if (_isGuest) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sana_guest_reminders_enabled', value);
        return;
      }

      if (user != null) {
        await _client
            .from('users')
            .update({'reminders_enabled': value}).eq('id', user.id);

        if (!kIsWeb) {
          if (value) {
            await _reconcileAllReminderAlarms();
          } else {
            await _cancelAllReminderAlarms();
          }
        }
      }
    } catch (e) {
      debugPrint('Reminder enable/disable failed: $e');
      // Rollback immediately on failure
      if (mounted) {
        setState(() {
          if (_isGuest) {
            _guestRemindersEnabled = previousValue;
          } else {
            _profile?['reminders_enabled'] = previousValue;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                languageNotifier.value,
                'reminder_setting_failed',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _setGuestRemindersEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sana_guest_reminders_enabled', value);
    if (!mounted) return;
    setState(() => _guestRemindersEnabled = value);
  }

  Future<void> _reconcileAllReminderAlarms() async {
    try {
      final ownerId = _ownerId;
      if (ownerId == null) return;

      final query = _client.from('reminders').select();
      final dynamic response = _isGuest
          ? await query.eq('guest_id', GuestIdentityService.sharedGuestId)
          : await query.eq('user_id', ownerId);

      final List<dynamic> list = response as List<dynamic>;

      for (final item in list) {
        final row = Map<String, dynamic>.from(item as Map);
        try {
          await SanaAlarmService.scheduleReminder(row);
        } catch (e) {
          debugPrint('Reconcile reminder failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Reconcile alarms error: $e');
    }
  }

  Future<void> _cancelAllReminderAlarms() async {
    try {
      final ownerId = _ownerId;
      if (ownerId == null) return;

      final query = _client.from('reminders').select('id');
      final dynamic response = _isGuest
          ? await query.eq('guest_id', GuestIdentityService.sharedGuestId)
          : await query.eq('user_id', ownerId);

      final List<dynamic> list = response as List<dynamic>;

      for (final item in list) {
        final id = (item as Map)['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          await SanaAlarmService.cancelReminder(id);
        } catch (e) {
          debugPrint('Cancel reminder failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Cancel alarms error: $e');
    }
  }

  Future<void> _openCard(String type) async {
    final ownerId = _ownerId ?? await GuestIdentityService.getGuestId();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordListScreen(
          type: type,
          ownerId: ownerId,
          guestMode: _isGuest,
          remindersEnabled: _isGuest
              ? _guestRemindersEnabled
              : _profile?['reminders_enabled'] != false,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openAddDialogDirectly(String type) async {
    final ownerId = _ownerId ?? await GuestIdentityService.getGuestId();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordListScreen(
          type: type,
          ownerId: ownerId,
          guestMode: _isGuest,
          remindersEnabled: _isGuest
              ? _guestRemindersEnabled
              : _profile?['reminders_enabled'] != false,
          autoOpenAdd: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _showAdaptiveInstallDialog() {
    final language = languageNotifier.value;

    final bool isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final bool isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final bool isMacos =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final bool isLinux =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

    String title;
    List<String> steps;

    if (isAndroid) {
      title = switch (language) {
        'ar' => '????? SANA ??? Android',
        'es' => 'Instalar SANA en Android',
        'fr' => 'Installer SANA sur Android',
        'de' => 'SANA auf Android installieren',
        'tr' => "SANA'yi Android'e y�kle",
        'hi' => 'Android ?? SANA ??????? ????',
        'zh' => '? Android ??? SANA',
        _ => 'Install SANA on Android',
      };
      steps = switch (language) {
        'ar' => [
            '???? SANA ?? ????? Chrome.',
            '???? ??? ????? ??????? (?) ???? ??????.',
            '???? "????? ???????" ?? "????? ??? ?????? ????????".',
            '???? ???????.',
          ],
        'es' => [
            'Abra SANA en el navegador Chrome.',
            'Toque el men� (?) en la esquina superior derecha.',
            'Elija "Instalar aplicaci�n" o "A�adir a pantalla de inicio".',
            'Confirme la instalaci�n.',
          ],
        'fr' => [
            'Ouvrez SANA dans le navigateur Chrome.',
            'Appuyez sur le menu (?) en haut � droite.',
            "Choisissez \"Installer l'application\" ou \"Ajouter � l'�cran d'accueil\".",
            "Confirmez l'installation.",
          ],
        'de' => [
            '�ffnen Sie SANA im Chrome-Browser.',
            'Tippen Sie auf das Men� (?) oben rechts.',
            'W�hlen Sie "App installieren" oder "Zum Startbildschirm hinzuf�gen".',
            'Best�tigen Sie die Installation.',
          ],
        'tr' => [
            "SANA'yi Chrome tarayicisinda a�in.",
            'Sag �stteki men�ye (?) dokunun.',
            '"Uygulamayi y�kle" veya "Ana ekrana ekle" se�enegini se�in.',
            'Kurulumu onaylayin.',
          ],
        'hi' => [
            'SANA ?? Chrome ???????? ??? ??????',
            '??? ???? ?? ???? (?) ?? ??? ?????',
            '"?? ??????? ????" ?? "??? ??????? ?? ??????" ??????',
            '?????????? ?? ?????? ?????',
          ],
        'zh' => [
            '? Chrome ?????? SANA?',
            '???????? (?)?',
            '??"????"?"??????"?',
            '?????',
          ],
        _ => [
            'Open SANA in Chrome.',
            'Tap the browser menu (?) at the top right.',
            'Choose "Install app" or "Add to Home screen".',
            'Confirm the installation.',
          ],
      };
    } else if (isIos) {
      title = switch (language) {
        'ar' => '????? SANA ??? iPhone / iPad',
        'es' => 'Instalar SANA en iPhone / iPad',
        'fr' => 'Installer SANA sur iPhone / iPad',
        'de' => 'SANA auf iPhone / iPad installieren',
        'tr' => "SANA'yi iPhone / iPad'e y�kle",
        'hi' => 'iPhone / iPad ?? SANA ??????? ????',
        'zh' => '? iPhone / iPad ??? SANA',
        _ => 'Install SANA on iPhone / iPad',
      };
      steps = switch (language) {
        'ar' => [
            '???? SANA ?? ????? Safari.',
            '???? ??? ?? ????????.',
            '???? ?????? ????? "????? ??? ?????? ????????".',
            '???? ???????.',
          ],
        'es' => [
            'Abra SANA en Safari.',
            'Toque el bot�n Compartir.',
            'Desplace y elija "A�adir a pantalla de inicio".',
            'Confirme.',
          ],
        'fr' => [
            'Ouvrez SANA dans Safari.',
            'Appuyez sur le bouton Partager.',
            "Faites d�filer et choisissez \"Ajouter � l'�cran d'accueil\".",
            'Confirmez.',
          ],
        'de' => [
            '�ffnen Sie SANA in Safari.',
            'Tippen Sie auf die Teilen-Schaltfl�che.',
            'W�hlen Sie "Zum Startbildschirm hinzuf�gen".',
            'Best�tigen Sie.',
          ],
        'tr' => [
            "SANA'yi Safari'de a�in.",
            'Paylas d�gmesine dokunun.',
            '"Ana ekrana ekle" se�enegini se�in.',
            'Onaylayin.',
          ],
        'hi' => [
            'SANA ?? Safari ??? ??????',
            '???? ??? ?? ??? ?????',
            '"??? ??????? ?? ??????" ??????',
            '?????? ?????',
          ],
        'zh' => [
            '? Safari ??? SANA?',
            '???????',
            '??"??????"?',
            '???',
          ],
        _ => [
            'Open SANA in Safari.',
            'Tap the Share button.',
            'Choose "Add to Home Screen".',
            'Confirm.',
          ],
      };
    } else if (isWindows) {
      title = switch (language) {
        'ar' => '????? SANA ??? Windows',
        'es' => 'Instalar SANA en Windows',
        'fr' => 'Installer SANA sur Windows',
        'de' => 'SANA auf Windows installieren',
        'tr' => "SANA'yi Windows'a y�kle",
        'hi' => 'Windows ?? SANA ??????? ????',
        'zh' => '? Windows ??? SANA',
        _ => 'Install SANA on Windows',
      };
      steps = switch (language) {
        'ar' => [
            '???? SANA ?? ????? Edge.',
            '???? ??? ??????? (�) ???? ??????.',
            '???? "?????????" ?? "????? ??? ?????? ??????".',
            '???? ???????.',
          ],
        'es' => [
            'Abra SANA en Microsoft Edge.',
            'Haga clic en el men� (�) arriba a la derecha.',
            'Elija "Aplicaciones" y luego "Instalar este sitio como aplicaci�n".',
            'Confirme.',
          ],
        'fr' => [
            'Ouvrez SANA dans Microsoft Edge.',
            'Cliquez sur le menu (�) en haut � droite.',
            "Choisissez \"Applications\" puis \"Installer ce site en tant qu'application\".",
            'Confirmez.',
          ],
        'de' => [
            '�ffnen Sie SANA in Microsoft Edge.',
            'Klicken Sie auf das Men� (�) oben rechts.',
            'W�hlen Sie "Apps" und dann "Diese Website als App installieren".',
            'Best�tigen Sie.',
          ],
        'tr' => [
            "SANA'yi Microsoft Edge'de a�in.",
            'Sag �stteki men�ye (�) tiklayin.',
            '"Uygulamalar" ve ardindan "Bu siteyi uygulama olarak y�kle" se�enegini se�in.',
            'Onaylayin.',
          ],
        'hi' => [
            'SANA ?? Microsoft Edge ??? ??????',
            '??? ???? ?? ???? (�) ?? ????? ?????',
            '"????" ?? ??? "?? ???? ?? ?? ?? ??? ??? ??????? ????" ??????',
            '?????? ?????',
          ],
        'zh' => [
            '? Microsoft Edge ??? SANA?',
            '???????? (�)?',
            '??"??",????"??????????"?',
            '???',
          ],
        _ => [
            'Open SANA in Microsoft Edge.',
            'Click the menu (�) at the top right.',
            'Choose "Apps" then "Install this site as an app".',
            'Confirm.',
          ],
      };
    } else if (isMacos) {
      title = switch (language) {
        'ar' => '????? SANA ??? macOS',
        'es' => 'Instalar SANA en macOS',
        'fr' => 'Installer SANA sur macOS',
        'de' => 'SANA auf macOS installieren',
        'tr' => "SANA'yi macOS'a y�kle",
        'hi' => 'macOS ?? SANA ??????? ????',
        'zh' => '? macOS ??? SANA',
        _ => 'Install SANA on macOS',
      };
      steps = switch (language) {
        'ar' => [
            '???? SANA ?? Safari.',
            '?? ????? "???" ???? "????? ??? Dock".',
            '???? ???????.',
          ],
        'es' => [
            'Abra SANA en Safari.',
            'Desde el men� "Archivo" elija "A�adir al Dock".',
            'Confirme.',
          ],
        'fr' => [
            'Ouvrez SANA dans Safari.',
            'Dans le menu "Fichier", choisissez "Ajouter au Dock".',
            'Confirmez.',
          ],
        'de' => [
            '�ffnen Sie SANA in Safari.',
            'W�hlen Sie im Men� "Ablage" die Option "Zum Dock hinzuf�gen".',
            'Best�tigen Sie.',
          ],
        'tr' => [
            "SANA'yi Safari'de a�in.",
            '"Dosya" men�s�nden "Dock\'a Ekle" se�enegini se�in.',
            'Onaylayin.',
          ],
        'hi' => [
            'SANA ?? Safari ??? ??????',
            '"?????" ???? ?? "Dock ??? ??????" ??????',
            '?????? ?????',
          ],
        'zh' => [
            '? Safari ??? SANA?',
            '?"??"?????"??? Dock"?',
            '???',
          ],
        _ => [
            'Open SANA in Safari.',
            'From the "File" menu choose "Add to Dock".',
            'Confirm.',
          ],
      };
    } else {
      title = switch (language) {
        'ar' => '????? SANA ??? Linux',
        'es' => 'Instalar SANA en Linux',
        'fr' => 'Installer SANA sur Linux',
        'de' => 'SANA auf Linux installieren',
        'tr' => "SANA'yi Linux'a y�kle",
        'hi' => 'Linux ?? SANA ??????? ????',
        'zh' => '? Linux ??? SANA',
        _ => 'Install SANA on Linux',
      };
      steps = switch (language) {
        'ar' => [
            '???? SANA ?? ???????.',
            '?? ????? ??????? ???? "????? ???????" ?? "????? ??? ?????? ????????".',
            '???? ???????.',
          ],
        'es' => [
            'Abra SANA en el navegador.',
            'Elija "Instalar aplicaci�n" o "A�adir a pantalla de inicio".',
            'Confirme.',
          ],
        'fr' => [
            'Ouvrez SANA dans le navigateur.',
            "Choisissez \"Installer l'application\" ou \"Ajouter � l'�cran d'accueil\".",
            'Confirmez.',
          ],
        'de' => [
            '�ffnen Sie SANA im Browser.',
            'W�hlen Sie "App installieren" oder "Zum Startbildschirm hinzuf�gen".',
            'Best�tigen Sie.',
          ],
        'tr' => [
            "SANA'yi tarayicida a�in.",
            '"Uygulamayi y�kle" veya "Ana ekrana ekle" se�enegini se�in.',
            'Onaylayin.',
          ],
        'hi' => [
            'SANA ?? ???????? ??? ??????',
            '"?? ??????? ????" ?? "??? ??????? ?? ??????" ??????',
            '?????? ?????',
          ],
        'zh' => [
            '??????? SANA?',
            '??"????"?"??????"?',
            '???',
          ],
        _ => [
            'Open SANA in your browser.',
            'Choose "Install app" or "Add to Home screen".',
            'Confirm.',
          ],
      };
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${i + 1}. ${steps[i]}'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr(language, 'close')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareApp() async {
    final language = languageNotifier.value;
    final message = '${tr(language, 'share_app_message')}\n\n$_sanaShareUrl';
    await SharePlus.instance.share(
      ShareParams(
        text: message,
      ),
    );
  }

  // FIXED: "Get Your Own Copy" opens Tap payment link

  // FIXED: "Get Your Own Copy" opens Tap payment link safely

  Future<void> _getOwnCopy() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'create-tap-charge',
        body: {
          'first_name': 'Customer',
          'email': 'customer@example.com',
        },
      );

      dynamic rawData = response.data;

      if (rawData is String) {
        rawData = jsonDecode(rawData);
      }

      if (rawData is! Map) {
        throw Exception(
          'Invalid response from create-tap-charge',
        );
      }

      final data = Map<String, dynamic>.from(rawData);

      if (data['error'] != null) {
        throw Exception(
          data['error'].toString(),
        );
      }

      final transaction = data['transaction'];

      if (transaction is! Map) {
        throw Exception(
          'Tap payment transaction information is missing.',
        );
      }

      final checkoutUrl = transaction['url'];

      if (checkoutUrl is! String || checkoutUrl.trim().isEmpty) {
        throw Exception(
          'Tap checkout URL is missing.',
        );
      }

      final uri = Uri.tryParse(checkoutUrl);

      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw Exception(
          'Invalid Tap checkout URL.',
        );
      }

      // Open the Tap checkout page.
      // Keep your existing URL-launching method here if
      // your project already has one.

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw Exception(
          'Could not open Tap payment page.',
        );
      }
    } catch (e) {
      debugPrint(
        'create-tap-charge error: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open payment page: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final isAdmin =
        (_profile?['role'] ?? '').toString().toLowerCase() == 'admin';

    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth =
                  constraints.maxWidth > 450 ? 450.0 : constraints.maxWidth;
              return Center(
                child: SizedBox(
                  width: maxWidth,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const LanguageButtons(),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.health_and_safety,
                                      color: Colors.teal, size: 36),
                                  tooltip: tr(language, 'manual_title'),
                                  onPressed: () {
                                    showDialog<void>(
                                      context: context,
                                      builder: (ctx) => Dialog.fullscreen(
                                        child: Scaffold(
                                          appBar: AppBar(
                                            title: Text(
                                              tr(
                                                language,
                                                'manual_title',
                                              ),
                                            ),
                                            leading: IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () =>
                                                  Navigator.pop(ctx),
                                            ),
                                          ),
                                          body: InteractiveViewer(
                                            constrained: false,
                                            minScale: 1.0,
                                            maxScale: 4.0,
                                            panEnabled: true,
                                            scaleEnabled: true,
                                            boundaryMargin:
                                                const EdgeInsets.all(300),
                                            clipBehavior: Clip.none,
                                            child: SingleChildScrollView(
                                              padding: const EdgeInsets.all(16),
                                              child: SizedBox(
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    48,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Text(
                                                      tr(
                                                        language,
                                                        'manual_content',
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 16),
                                                    _SanaInstallHelp(
                                                      language: language,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Text(
                                  tr(language, 'help'),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'SANA',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4),
                            ),
                            InkWell(
                              onTap: _shareApp,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      tr(language, 'share'),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.share,
                                      size: 26,
                                      color: Colors.teal,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        // STATUS BADGE: Visual indicator for Guest vs User vs Admin
                        Builder(
                          builder: (context) {
                            final user = _client.auth.currentUser;
                            final isRealUser = !_isGuest &&
                                user != null &&
                                user.isAnonymous == false;
                            final role = (_profile?['role'] ?? '')
                                .toString()
                                .toLowerCase();
                            final email = user?.email ?? '';
                            final nameValue = (_profile?['name'] ??
                                    _profile?['username'] ??
                                    '')
                                .toString()
                                .trim();
                            final displayName =
                                nameValue.isNotEmpty ? nameValue : email;

                            if (isRealUser && role == 'admin') {
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: Colors.purple.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.shield,
                                        size: 16, color: Colors.purple),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'ADMIN: $displayName',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            } else if (isRealUser) {
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: Colors.blue.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.person,
                                        size: 16, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'USER: $displayName',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: Colors.green.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.lock_open,
                                        size: 16, color: Colors.green),
                                    const SizedBox(width: 6),
                                    Text(
                                      tr(language, 'guest_mode').toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildMainGrid(language),
                        const SizedBox(height: 16),
                        _buildBottomArea(language, isAdmin),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCardCustomIcon(String type) {
    switch (type) {
      case 'medications':
        // Custom multi-colored capsules & round pill matching your screenshot 1
        return SizedBox(
          height: 38,
          width: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 2,
                top: 4,
                child: Transform.rotate(
                  angle: -0.4,
                  child: Container(
                    width: 14,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFFFB300)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 2,
                          offset: const Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Transform.rotate(
                  angle: 0.5,
                  child: Container(
                    width: 14,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0288D1), Color(0xFF4FC3F7)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 2,
                          offset: const Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade400, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

      case 'doctors':
        // Doctor silhouette with stethoscope and supportive hands matching your screenshot 2
        return SizedBox(
          height: 38,
          width: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned(
                top: 0,
                child: Icon(
                  Icons.person_pin,
                  size: 30,
                  color: Color(0xFF0288D1),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.flip(
                      flipX: true,
                      child: const Icon(
                        Icons.front_hand,
                        size: 14,
                        color: Color(0xFF29B6F6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.front_hand,
                      size: 14,
                      color: Color(0xFF29B6F6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'pharmacies':
        // Green circular emblem with white cross matching your screenshot 3
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFF2E7D32),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.add,
              color: Colors.white,
              size: 26,
            ),
          ),
        );

      case 'reminders':
        return const Icon(
          Icons.alarm_on,
          size: 34,
          color: Color(0xFFE65100),
        );

      case 'documents':
        return const Icon(
          Icons.folder_shared,
          size: 34,
          color: Color(0xFF6A1B9A),
        );

      case 'insurance_cards':
        return const Icon(
          Icons.badge,
          size: 34,
          color: Color(0xFFC2185B),
        );

      default:
        return const Icon(Icons.circle, size: 34);
    }
  }

  Widget _buildMainGrid(String language) {
    final cards = [
      _recordCard('medications', Colors.teal.shade50),
      _recordCard('doctors', Colors.blue.shade50),
      _recordCard('pharmacies', Colors.green.shade50),
      _recordCard('reminders', Colors.orange.shade50),
      _recordCard('documents', Colors.purple.shade50),
      _recordCard('insurance_cards', Colors.pink.shade50),
    ];

    return Column(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: cards,
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _shareCard(language)),
              const SizedBox(width: 10),
              Expanded(child: _reminderToggleCard(language)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recordCard(String type, Color color) {
    final language = languageNotifier.value;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCard(type),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: Colors.teal, size: 22),
                    tooltip: tr(language, 'add'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _openAddDialogDirectly(type),
                  ),
                ],
              ),
              _buildCardCustomIcon(type),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    tr(language, type),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reminderToggleCard(String language) {
    final value = _isGuest
        ? _guestRemindersEnabled
        : _profile?['reminders_enabled'] == true;

    final label = value
        ? tr(language, 'disable_reminders')
        : tr(language, 'enable_reminders');

    final baseFontSize = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16;

    return SizedBox(
      width: double.infinity,
      height: 90,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: double.infinity,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (baseFontSize / 2) * 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Checkbox(
                value: value,
                onChanged: (val) {
                  if (val != null) {
                    _setRemindersEnabled(val);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareCard(String language) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.amber.shade100,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final ownerId = _ownerId ?? 'guest';
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShareScreen(
                  ownerId: ownerId,
                  guestMode: _isGuest,
                ),
              ),
            );
          },
          child: SizedBox(
            height: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_shared, size: 34, color: Colors.teal),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(
                      tr(language, 'share_documents'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Widget _buildBottomArea(String language, bool isAdmin) {
    final user = _client.auth.currentUser;
    final isLoggedIn = !_isGuest && user != null && user.isAnonymous == false;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await SanaStore.instance.flush(_client);
                  } catch (_) {}
                  SanaStore.instance.reset();
                  if (isLoggedIn) {
                    await _client.auth.signOut();
                    StorageHelper.clearCache();
                    await _loadSession();
                  } else {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                    if (result == true) await _loadSession();
                  }
                },
                icon: Icon(isLoggedIn ? Icons.logout : Icons.login, size: 18),
                label: Text(
                  tr(language, isLoggedIn ? 'logout' : 'login'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: isLoggedIn
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChatScreen()),
                        )
                    : _getOwnCopy,
                icon: Icon(
                  isLoggedIn ? Icons.chat : Icons.copy,
                  size: 18,
                ),
                label: Text(
                  tr(language, isLoggedIn ? 'chat' : 'get_copy'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        if (isLoggedIn && isAdmin) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            ),
            icon: const Icon(Icons.admin_panel_settings),
            label: Text(tr(language, 'admin')),
          ),
        ],
      ],
    );
  }
}

/// Converts any username or email into a guaranteed valid internal email for Supabase GoTrue.
String usernameToAuthEmail(String rawInput) {
  final clean = rawInput
      .replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF\u00A0]'), '')
      .trim()
      .toLowerCase();

  if (clean.isEmpty) return '';

  // Admin username aliases map to the existing Supabase Admin Auth account.
  if (clean == 'admin' || clean == 'malaz' || clean == 'malazjanbeih') {
    return 'malazjanbeih@gmail.com';
  }

  if (clean.contains('@') && clean.contains('.')) return clean;

  // 32-hex SHA-256 hash guarantees the internal email is ALWAYS valid and fixed-length
  final hash = sha256.convert(utf8.encode(clean)).toString().substring(0, 32);
  return 'u_$hash@sana.local';
}

/// Allows ANY password length and automatically trims trailing spaces/invisible characters.
String formatAuthPassword(String rawPassword) {
  final clean = rawPassword
      .replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF\u00A0]'), '')
      .trim();

  if (clean.length >= 6) {
    return clean;
  }

  return sha256.convert(utf8.encode(clean)).toString();
}

// ============================================
// LOGIN SCREEN
// ============================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final rawInput = _email.text.trim();
    final password = _password.text.trim();
    final language = languageNotifier.value;

    if (rawInput.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(language, 'please_fill_all')),
        ),
      );
      return;
    }

    final authEmail = usernameToAuthEmail(rawInput);
    final authPassword = formatAuthPassword(password);

    setState(() => _busy = true);

    try {
      // LOGIN ONLY:
      // This call authenticates an account that already exists.
      // It NEVER creates a new account.
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: authEmail,
        password: authPassword,
      );

      if (res.user == null) {
        throw Exception('User null');
      }

      // EXISTING ADMIN ACCOUNT:
      // Successful authentication is sufficient.
      // Admin is never restricted by active/expiry/paid status.
      if (authEmail.toLowerCase() == 'malazjanbeih@gmail.com') {
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      Map<String, dynamic>? profile;

      try {
        profile = await Supabase.instance.client
            .from('users')
            .select('is_active, role')
            .eq('id', res.user!.id)
            .maybeSingle();
      } catch (pe) {
        debugPrint('Error fetching user profile: $pe');

        // A login is valid only when the corresponding SANA
        // user profile can also be found.
        await Supabase.instance.client.auth.signOut();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(language, 'login_failed'),
            ),
          ),
        );
        return;
      }

      // IMPORTANT:
      // Authentication alone is not enough for a normal SANA user.
      // The user must have an existing public.users profile.
      if (profile == null) {
        await Supabase.instance.client.auth.signOut();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(language, 'login_failed'),
            ),
          ),
        );
        return;
      }

      final role = (profile['role'] ?? 'user').toString().toLowerCase();

      // ADMIN IS NEVER RESTRICTED.
      if (role == 'admin') {
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final isActive = profile['is_active'];

      // ONLY A USER EXPLICITLY DEACTIVATED BY ADMIN IS BLOCKED.
      if (isActive == false) {
        await Supabase.instance.client.auth.signOut();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              tr(language, 'expired'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            duration: const Duration(seconds: 5),
          ),
        );

        return;
      }

      // EXISTING ACTIVE USER:
      // Allow entry immediately.
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Login exception: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(language, 'login_failed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _navigateToSignUp() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) => Directionality(
        textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LanguageButtons(),
                    const SizedBox(height: 20),
                    const Icon(Icons.health_and_safety,
                        size: 52, color: Colors.teal),
                    const SizedBox(height: 4),
                    const Text(
                      'SANA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      tr(language, 'sign_in'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: tr(language, 'email'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText:
                            '${tr(language, 'password')} (${tr(language, 'password_6_digit')})',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () =>
                          setState(() => _showPassword = !_showPassword),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _showPassword,
                            onChanged: (val) =>
                                setState(() => _showPassword = val ?? false),
                          ),
                          Text(
                            tr(language, 'show_password'),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _login,
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(tr(language, 'sign_in')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                        onPressed: _navigateToSignUp,
                        child: Text(tr(language, 'new_user'))),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr(language, 'close'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// SIGN UP SCREEN
// ============================================

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final rawUsername = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final language = languageNotifier.value;

    if (name.isEmpty ||
        rawUsername.isEmpty ||
        phone.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(language, 'please_fill_all'))),
      );
      return;
    }

    // Converts any username and short passwords to deterministic Auth credentials
    final authEmail = usernameToAuthEmail(rawUsername);
    final authPassword = formatAuthPassword(password);

    setState(() => _busy = true);
    try {
      final client = Supabase.instance.client;
      final response = await client.auth.signUp(
        email: authEmail,
        password: authPassword,
        data: {
          'name': name,
          'username': rawUsername,
          'phone': phone,
          'role': 'user',
          'is_active': true,
        },
      );

      if (response.user == null) {
        throw Exception(tr(language, 'signup_failed'));
      }

      // Ensure every new user is ACTIVE immediately.
      // Only use columns required by the existing users profile flow.
      try {
        await client.from('users').upsert({
          'id': response.user!.id,
          'name': name,
          'username': rawUsername,
          'phone': phone,
          'role': 'user',
          'is_active': true,
          'has_password': true,
          'password_plain': password, // <-- ADD THIS LINE
        });
      } catch (e) {
        debugPrint('Error creating active user profile: $e');
        rethrow;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade700,
          content: Text(
            tr(language, 'account_created_success'),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${tr(language, 'signup_failed')}: ${e.toString().replaceAll('Exception: ', '')}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) => Directionality(
        textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(title: Text(tr(language, 'create_account'))),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.person_add, size: 64, color: Colors.teal),
                    const SizedBox(height: 16),
                    Text(
                      tr(language, 'create_account'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: tr(language, 'name'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: tr(language, 'email'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: tr(language, 'phone'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText:
                            '${tr(language, 'password')} (${tr(language, 'password_6_digit')})',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () =>
                          setState(() => _showPassword = !_showPassword),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _showPassword,
                            onChanged: (val) =>
                                setState(() => _showPassword = val ?? false),
                          ),
                          Text(
                            tr(language, 'show_password'),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _signUp,
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(tr(language, 'register')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr(language, 'already_account')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// RECORD SANITIZER - REMOVED guest_id
// ============================================

class RecordSanitizer {
  static const Set<String> validColumns = {
    'name',
    'dosage',
    'quantity',
    'notes',
    'reminder_time',
    // 'reminder_date' - REMOVED - does not exist in medications table
    'specialty',
    'phone',
    'address',
    'location',
    'title',
    'category',
    'file_url',
    'file_type',
    'provider_name',
    'front_image_url',
    'back_image_url',
    'photo_url',
    'photo_base64',
    'user_id',
    'guest_id',
    'photo',
    'front_photo',
    'back_photo',
    'provider',
    'policy_number',
    'medication_name',
    'medication_id',
  };

  static Map<String, dynamic> sanitize(Map<String, dynamic> rawInput) {
    final cleanPayload = <String, dynamic>{};
    for (final entry in rawInput.entries) {
      if (validColumns.contains(entry.key) && entry.value != null) {
        if (entry.value is String) {
          final trimmed = (entry.value as String).trim();
          if (trimmed.isNotEmpty) cleanPayload[entry.key] = trimmed;
        } else {
          cleanPayload[entry.key] = entry.value;
        }
      }
    }
    return cleanPayload;
  }
}

// ============================================
// SAFE BASE64 IMAGE
// ============================================

class SafeBase64Image extends StatefulWidget {
  final String base64String;
  final double? height;
  final double? width;
  const SafeBase64Image(
      {super.key, required this.base64String, this.height, this.width});

  @override
  State<SafeBase64Image> createState() => _SafeBase64ImageState();
}

class _SafeBase64ImageState extends State<SafeBase64Image> {
  Uint8List? _bytes;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(SafeBase64Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64String != widget.base64String) _decode();
  }

  void _decode() {
    if (widget.base64String.isEmpty) {
      setState(() => _hasError = true);
      return;
    }
    try {
      final sanitized = widget.base64String.contains(',')
          ? widget.base64String.split(',').last
          : widget.base64String;
      final value = sanitized.trim();
      final encoded = value.contains(',') ? value.split(',').last : value;

      final decoded = base64Decode(
        encoded.replaceAll(RegExp(r'\s+'), ''),
      );
      setState(() {
        _bytes = decoded;
        _hasError = false;
      });
    } catch (_) {
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError)
      return Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400);
    if (_bytes == null) {
      return const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Image.memory(
      _bytes!,
      height: widget.height,
      width: widget.width,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.broken_image, color: Colors.grey.shade400),
    );
  }
}

// ============================================
// SAFE NETWORK IMAGE
// ============================================

class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(imageUrl);
    final isValidUrl = uri != null &&
        uri.hasAbsolutePath &&
        (uri.scheme == 'http' || uri.scheme == 'https');

    if (!isValidUrl) {
      return const Icon(Icons.broken_image, size: 48, color: Colors.grey);
    }

    return Image.network(
      imageUrl,
      height: height,
      width: width,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          height: height ?? 100,
          width: width ?? 100,
          child: const Center(
            child: CircularProgressIndicator.adaptive(),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.broken_image, size: 48, color: Colors.grey);
      },
    );
  }
}

// ============================================
// IMAGE PICKER HELPER
// ============================================

class ImagePickerHelper {
  static Future<String?> pickImageAsBase64() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (image == null) return null;
      final bytes = await image.readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }
}

// ============================================
// SUPABASE STORAGE HELPER
// ============================================

class StorageHelper {
  static final SupabaseClient _client = Supabase.instance.client;

  static const String _bucket = 'medication_photos';

  static const Uuid _uuid = Uuid();

  static final Map<String, _CachedSignedUrl> _urlCache = {};

  static Future<String> uploadMedicationPhoto({
    required String base64Image,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated Supabase user');
    }

    var clean = base64Image.trim();

    if (clean.isEmpty) {
      throw const FormatException('Empty image data');
    }

    String mimeType = 'image/jpeg';

    // Detect MIME type when Base64 contains a data URI.
    if (clean.startsWith('data:')) {
      final commaIndex = clean.indexOf(',');

      if (commaIndex == -1) {
        throw const FormatException('Invalid image data');
      }

      final header = clean.substring(0, commaIndex);

      if (header.contains('image/png')) {
        mimeType = 'image/png';
      } else if (header.contains('image/webp')) {
        mimeType = 'image/webp';
      } else if (header.contains('image/gif')) {
        mimeType = 'image/gif';
      }

      clean = clean.substring(commaIndex + 1);
    } else if (clean.contains(',')) {
      clean = clean.split(',').last;
    }

    clean = clean.replaceAll(RegExp(r'\s+'), '');

    final bytes = base64Decode(clean);

    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };

    final fileId = _uuid.v4();

    // Storage ownership: registered users use their own uuid;
    // guests share the fixed guest folder so every device can read.
    final storageOwner =
        user.isAnonymous ? GuestIdentityService.sharedGuestId : user.id;
    final filePath = 'medications/$storageOwner/$fileId.$extension';
    await _client.storage.from(_bucket).uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            cacheControl: '31536000',
            upsert: false,
          ),
        );

    return filePath;
  }

  static Future<String?> getSignedUrl(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    final cleanPath = path.trim();

    final cached = _urlCache[cleanPath];

    if (cached != null && !cached.isExpired) {
      return cached.url;
    }

    try {
      final url = await _client.storage.from(_bucket).createSignedUrl(
            cleanPath,
            3600,
          );

      _urlCache[cleanPath] = _CachedSignedUrl(
        url: url,
        // Expire our cache slightly before the actual signed URL.
        expiresAt: DateTime.now().add(
          const Duration(minutes: 55),
        ),
      );

      return url;
    } catch (e) {
      debugPrint('Signed URL error: $e');
      return null;
    }
  }

  static Future<void> deleteMedicationPhoto(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return;
    }

    final cleanPath = path.trim();

    try {
      await _client.storage.from(_bucket).remove([cleanPath]);

      _urlCache.remove(cleanPath);
    } catch (e) {
      debugPrint('Storage delete error: $e');
    }
  }

  static String? getCachedSignedUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final c = _urlCache[path.trim()];
    if (c != null && !c.isExpired) return c.url;
    return null;
  }

  static void clearCache() {
    _urlCache.clear();
  }
}

class _CachedSignedUrl {
  final String url;
  final DateTime expiresAt;

  const _CachedSignedUrl({
    required this.url,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ============================================
// DISPLAY IMAGE
// ============================================

class DisplayImage extends StatelessWidget {
  final Uint8List? bytes;
  final String? base64String;
  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;

  const DisplayImage({
    super.key,
    this.bytes,
    this.base64String,
    this.url,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (bytes != null && bytes!.isNotEmpty) {
      return Image.memory(
        bytes!,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
            size: height ?? 48, color: Colors.grey.shade400),
      );
    }

    final raw = (base64String != null && base64String!.trim().isNotEmpty)
        ? base64String!.trim()
        : (url != null && url!.trim().isNotEmpty ? url!.trim() : null);

    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        return Image.network(
          raw,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
              size: height ?? 48, color: Colors.grey.shade400),
        );
      }

      try {
        var clean = raw;
        if (clean.contains(',')) {
          clean = clean.split(',').last;
        }
        clean = clean.replaceAll(RegExp(r'\s+'), '');
        clean = base64.normalize(clean);

        final decoded = base64Decode(clean);
        return Image.memory(
          decoded,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
              size: height ?? 48, color: Colors.grey.shade400),
        );
      } catch (e) {
        debugPrint('DisplayImage error: $e');
      }
    }

    return Icon(Icons.broken_image,
        size: height ?? 48, color: Colors.grey.shade400);
  }
}

// ============================================
// SIGNED IMAGE WIDGET
// ============================================

class SignedImage extends StatelessWidget {
  final String? path;
  final double? height;
  final double? width;
  final BoxFit fit;

  const SignedImage({
    super.key,
    this.path,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final p = path?.trim();
    if (p == null || p.isEmpty) {
      return Icon(Icons.medication, size: height ?? 48, color: Colors.teal);
    }
    final cached = StorageHelper.getCachedSignedUrl(p);
    if (cached != null) {
      return Image.network(cached,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.medication, size: height ?? 48, color: Colors.teal));
    }
    return _SignedImageAsync(path: p, height: height, width: width, fit: fit);
  }
}

class _SignedImageAsync extends StatefulWidget {
  final String path;
  final double? height;
  final double? width;
  final BoxFit fit;
  const _SignedImageAsync(
      {required this.path, this.height, this.width, this.fit = BoxFit.contain});
  @override
  State<_SignedImageAsync> createState() => _SignedImageAsyncState();
}

class _SignedImageAsyncState extends State<_SignedImageAsync> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await StorageHelper.getSignedUrl(widget.path);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
          height: widget.height ?? 100,
          width: widget.width,
          child:
              const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_url == null) {
      return Icon(Icons.medication,
          size: widget.height ?? 48, color: Colors.teal);
    }
    return Image.network(_url!,
        height: widget.height,
        width: widget.width,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => Icon(Icons.medication,
            size: widget.height ?? 48, color: Colors.teal));
  }
}

class AddFormDialog extends StatefulWidget {
  final String type;
  final String language;
  final List<Map<String, dynamic>> medicationsList;
  final List<String> fields;
  final List<String> requiredFields;
  final Future<void> Function(Map<String, dynamic> payload) onSave;

  const AddFormDialog({
    super.key,
    required this.type,
    required this.language,
    required this.medicationsList,
    required this.fields,
    required this.requiredFields,
    required this.onSave,
  });

  @override
  State<AddFormDialog> createState() => _AddFormDialogState();
}

class _AddFormDialogState extends State<AddFormDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _selectedValues = {};
  final List<TimeOfDay> _selectedMedicationTimes = [];

  String _medicationScheduleType = 'daily';
  DateTime? _medicationCalendarDate;

  // Medicine photo stored as Base64.
  String? _medicinePhotoBase64;
  String? _frontPhotoBase64;
  String? _backPhotoBase64;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    for (final field in widget.fields) {
      _controllers[field] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'name':
        return 'name';
      case 'dosage':
        return 'dosage';
      case 'quantity':
        return 'quantity';
      case 'notes':
        return 'notes';
      case 'reminder_time':
        return 'reminder_time';
      case 'reminder_date':
        return 'reminder_date';
      case 'description':
        return 'description';
      case 'specialty':
        return 'specialty';
      case 'phone':
        return 'phone';
      case 'address':
        return 'address';
      case 'title':
        return 'title';
      case 'category':
        return 'category';
      case 'file_url':
        return 'file_url';
      case 'provider_name':
        return 'provider_name';
      case 'front_photo':
        return 'front_photo';
      case 'back_photo':
        return 'back_photo';
      case 'location':
        return 'location';
      case 'photo':
        return 'photo';
      case 'medication_name':
        return 'name';
      default:
        return field;
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';

    return '$hour:$minute $period';
  }

  List<TimeOfDay> _timeChoices() {
    return List<TimeOfDay>.generate(
      24,
      (i) => TimeOfDay(hour: i, minute: 0),
    );
  }

  Future<DateTime?> _selectDate(BuildContext context) async {
    return showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Future<void> _pickMedicinePhoto() async {
    final base64 = await ImagePickerHelper.pickImageAsBase64();

    if (base64 != null && mounted) {
      setState(() {
        _medicinePhotoBase64 = base64;
      });
    }
  }

  Widget _buildMedicinePhotoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(widget.language, 'medicine_photo'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          if (_medicinePhotoBase64 != null)
            Center(
              child: DisplayImage(
                base64String: _medicinePhotoBase64,
                height: 140,
                width: 140,
                fit: BoxFit.cover,
              ),
            )
          else
            Text(
              tr(widget.language, 'no_medicine_photo'),
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickMedicinePhoto,
              icon: const Icon(Icons.photo_camera),
              label: Text(
                _medicinePhotoBase64 == null
                    ? tr(widget.language, 'upload_medicine_photo')
                    : tr(widget.language, 'change_medicine_photo'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderTimes() {
    return FormField<List<TimeOfDay>>(
      initialValue: List<TimeOfDay>.from(_selectedMedicationTimes),
      validator: (value) {
        if (widget.requiredFields.contains('reminder_time') &&
            _selectedMedicationTimes.isEmpty) {
          return tr(widget.language, 'required_field');
        }

        return null;
      },
      builder: (fieldState) {
        return InputDecorator(
          decoration: InputDecoration(
            labelText: tr(widget.language, 'reminder_time'),
            border: const OutlineInputBorder(),
            errorText: fieldState.errorText,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(widget.language, 'select_reminder_times'),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 190,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _timeChoices().map((time) {
                      final selected = _selectedMedicationTimes.any(
                        (t) => t.hour == time.hour && t.minute == time.minute,
                      );

                      return FilterChip(
                        label: Text(_formatTimeOfDay(time)),
                        selected: selected,
                        onSelected: (on) {
                          setState(() {
                            if (on) {
                              if (!_selectedMedicationTimes.any(
                                (t) =>
                                    t.hour == time.hour &&
                                    t.minute == time.minute,
                              )) {
                                _selectedMedicationTimes.add(time);
                              }

                              _selectedMedicationTimes.sort(
                                (a, b) => (a.hour * 60 + a.minute)
                                    .compareTo(b.hour * 60 + b.minute),
                              );
                            } else {
                              _selectedMedicationTimes.removeWhere(
                                (t) =>
                                    t.hour == time.hour &&
                                    t.minute == time.minute,
                              );
                            }

                            fieldState.didChange(
                              List<TimeOfDay>.from(
                                _selectedMedicationTimes,
                              ),
                            );
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_selectedMedicationTimes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${tr(widget.language, 'selected')}: ${_selectedMedicationTimes.map(_formatTimeOfDay).join(', ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMedicationSchedule() {
    return FormField<DateTime>(
      initialValue: _medicationCalendarDate,
      validator: (value) {
        if (!widget.requiredFields.contains('reminder_date')) {
          return null;
        }

        if (_medicationScheduleType == 'calendar' &&
            _medicationCalendarDate == null) {
          return tr(widget.language, 'required_field');
        }

        return null;
      },
      builder: (fieldState) {
        return InputDecorator(
          decoration: InputDecoration(
            labelText: tr(widget.language, 'medication_schedule'),
            border: const OutlineInputBorder(),
            errorText: fieldState.errorText,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(widget.language, 'choose_schedule_repeat'),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'daily',
                      icon: const Icon(Icons.today),
                      label: Text(tr(widget.language, 'daily')),
                    ),
                    ButtonSegment<String>(
                      value: 'calendar',
                      icon: const Icon(Icons.calendar_month),
                      label: Text(tr(widget.language, 'calendar')),
                    ),
                  ],
                  selected: {_medicationScheduleType},
                  onSelectionChanged: (values) {
                    setState(() {
                      _medicationScheduleType = values.first;

                      if (_medicationScheduleType == 'daily') {
                        _medicationCalendarDate = null;
                        fieldState.didChange(null);
                      }
                    });
                  },
                ),
              ),
              if (_medicationScheduleType == 'daily') ...[
                const SizedBox(height: 10),
                Text(
                  tr(widget.language, 'repeat_daily_msg'),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              if (_medicationScheduleType == 'calendar') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await _selectDate(context);

                      if (date != null && mounted) {
                        setState(() {
                          _medicationCalendarDate = date;
                        });

                        fieldState.didChange(date);
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _medicationCalendarDate == null
                          ? tr(widget.language, 'select_calendar_date')
                          : '${tr(widget.language, 'date')}: ${_medicationCalendarDate!.year}-'
                              '${_medicationCalendarDate!.month.toString().padLeft(2, '0')}-'
                              '${_medicationCalendarDate!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMedicationDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: tr(widget.language, 'select_medication'),
          border: const OutlineInputBorder(),
        ),
        hint: Text(tr(widget.language, 'select_medication')),
        isExpanded: true,
        items: widget.medicationsList.map((med) {
          final nameStr = med['name']?.toString() ?? '';
          final idStr = med['id']?.toString() ?? '';

          return DropdownMenuItem<String>(
            value: idStr,
            child: Text(
              nameStr,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            final selectedMed = widget.medicationsList.firstWhere(
              (med) => med['id']?.toString() == value,
              orElse: () => {},
            );

            _selectedValues['medication_id'] = value;

            _selectedValues['medication_name'] =
                selectedMed['name']?.toString() ?? '';

            _controllers['medication_name']?.text =
                selectedMed['name']?.toString() ?? '';

            _controllers['name']?.text = selectedMed['name']?.toString() ?? '';
          });
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return tr(widget.language, 'required_field');
          }

          return null;
        },
      ),
    );
  }

  Widget _buildTextField(String field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _controllers[field],
        decoration: InputDecoration(
          labelText: tr(widget.language, _fieldLabel(field)),
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (widget.requiredFields.contains(field)) {
            if (value == null || value.trim().isEmpty) {
              return tr(widget.language, 'required_field');
            }
          }

          return null;
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final payload = <String, dynamic>{};

    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();

      if (value.isNotEmpty) {
        payload[entry.key] = value;
      }
    }

    // Medication reminder times.
    if (_selectedMedicationTimes.isNotEmpty) {
      payload['reminder_time'] = jsonEncode(
        _selectedMedicationTimes.map(_formatTimeOfDay).toList(),
      );
    }

    // Medication schedule.
    if (widget.type == 'medications' || widget.type == 'reminders') {
      if (_medicationScheduleType == 'daily') {
        payload['reminder_date'] = 'daily';
      } else {
        payload['reminder_date'] = _medicationCalendarDate == null
            ? null
            : _medicationCalendarDate!.toIso8601String().split('T')[0];
      }

      if (_medicinePhotoBase64 != null && _medicinePhotoBase64!.isNotEmpty) {
        payload['photo_base64'] = _medicinePhotoBase64;
      }
    } else {
      if (_medicationScheduleType == 'daily') {
        payload['reminder_date'] = 'daily';
      } else if (_medicationCalendarDate != null) {
        payload['reminder_date'] =
            _medicationCalendarDate!.toIso8601String().split('T')[0];
      }
    }

    if (_selectedValues['medication_id'] != null) {
      payload['medication_id'] = _selectedValues['medication_id'];
    }

    if (_selectedValues['medication_name'] != null) {
      payload['medication_name'] = _selectedValues['medication_name'];

      payload['name'] = _selectedValues['medication_name'];
    }

    if (widget.type == 'documents') {
      if (_medicinePhotoBase64 != null && _medicinePhotoBase64!.isNotEmpty) {
        payload['photo'] = _medicinePhotoBase64;
      }
    }

    if (widget.type == 'insurance_cards') {
      payload['front_photo'] = _frontPhotoBase64;
      payload['back_photo'] = _backPhotoBase64;
    }

    await widget.onSave(payload);

    if (context.mounted) {
      Navigator.pop(context, payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMedication = widget.type == 'medications';

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${tr(widget.language, 'add')} '
            '${tr(widget.language, widget.type)}',
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, null),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                tr(widget.language, 'cancel'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              child: FilledButton(
                onPressed: _save,
                child: Text(
                  tr(widget.language, 'save'),
                ),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Medicine photo appears for medications and reminders.
                if (isMedication || widget.type == 'reminders')
                  _buildMedicinePhotoSection(),

                ...widget.fields.map((field) {
                  if (field == 'reminder_time') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildReminderTimes(),
                    );
                  }

                  if (field == 'reminder_date') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildMedicationSchedule(),
                    );
                  }

                  if (field == 'medication_name') {
                    return const SizedBox.shrink();
                  }

                  // PHOTO UPLOAD BLOCK - For Documents and Insurance Cards
                  if (field == 'photo' ||
                      field == 'front_photo' ||
                      field == 'back_photo') {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            field == 'front_photo'
                                ? tr(widget.language, 'front_photo')
                                : field == 'back_photo'
                                    ? tr(widget.language, 'back_photo')
                                    : tr(widget.language, 'photo'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Image preview thumbnail
                          if (_frontPhotoBase64 != null &&
                              field == 'front_photo') ...[
                            Center(
                              child: DisplayImage(
                                base64String: _frontPhotoBase64,
                                height: 120,
                                width: 200,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (_backPhotoBase64 != null &&
                              field == 'back_photo') ...[
                            Center(
                              child: DisplayImage(
                                base64String: _backPhotoBase64,
                                height: 120,
                                width: 200,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (_medicinePhotoBase64 != null &&
                              field == 'photo') ...[
                            Center(
                              child: DisplayImage(
                                base64String: _medicinePhotoBase64,
                                height: 120,
                                width: 200,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                tr(widget.language, 'no_image_selected'),
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),

                          // Full-width upload button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final base64 =
                                    await ImagePickerHelper.pickImageAsBase64();
                                if (base64 != null) {
                                  setState(() {
                                    if (field == 'front_photo') {
                                      _frontPhotoBase64 = base64;
                                    } else if (field == 'back_photo') {
                                      _backPhotoBase64 = base64;
                                    } else {
                                      _medicinePhotoBase64 = base64;
                                    }
                                  });
                                }
                              },
                              icon: const Icon(Icons.photo_camera),
                              label: Text(
                                field == 'front_photo'
                                    ? (_frontPhotoBase64 == null
                                        ? tr(widget.language,
                                            'upload_front_card')
                                        : tr(widget.language, 'uploaded'))
                                    : field == 'back_photo'
                                        ? (_backPhotoBase64 == null
                                            ? tr(widget.language,
                                                'upload_back_card')
                                            : tr(widget.language, 'uploaded'))
                                        : (_medicinePhotoBase64 == null
                                            ? tr(
                                                widget.language, 'upload_photo')
                                            : tr(widget.language, 'uploaded')),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return _buildTextField(field);
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// RECORD LIST SCREEN - PRESERVED ORIGINAL
// ============================================

class RecordListScreen extends StatefulWidget {
  final String type;
  final String ownerId;
  final bool guestMode;
  final bool autoOpenAdd;
  final bool remindersEnabled;

  const RecordListScreen({
    super.key,
    required this.type,
    required this.ownerId,
    required this.guestMode,
    this.autoOpenAdd = false,
    this.remindersEnabled = true,
  });

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _medicationsList = [];
  bool _loading = true;
  Future<void>? _reminderSaveInFlight;
  final _formKey = GlobalKey<FormState>();

  // Insurance card variables - using base64 only (no File for web)
  String? _frontCardBase64;
  String? _backCardBase64;
  final TextEditingController _insuranceCompanyController =
      TextEditingController();
  final TextEditingController _patientIdController = TextEditingController();

  // Document variables - using base64 only (no File for web)
  String? _documentPhotoBase64;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _fileUrlController = TextEditingController();

  String get _table => widget.type;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.autoOpenAdd && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _add());
    }
  }

  @override
  void dispose() {
    _insuranceCompanyController.dispose();
    _patientIdController.dispose();
    _titleController.dispose();
    _categoryController.dispose();
    _fileUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadMedications() async {
    if (!mounted) return;
    try {
      final query = _client.from('medications').select();
      final dynamic response = widget.guestMode
          ? await query.eq('guest_id', GuestIdentityService.sharedGuestId)
          : await query.eq('user_id', widget.ownerId);

      final List<dynamic> list = response as List<dynamic>;
      final List<Map<String, dynamic>> records =
          list.map((item) => Map<String, dynamic>.from(item as Map)).toList();

      if (mounted) {
        setState(() {
          _medicationsList = records;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _medicationsList = [];
        });
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;

    // Reminder-only: wait for a save that is still uploading/inserting.
    // This prevents an immediate refresh from querying Supabase before
    // the Reminder insert has completed.
    if (_table == 'reminders') {
      final pendingSave = _reminderSaveInFlight;
      if (pendingSave != null) {
        try {
          await pendingSave;
        } catch (_) {}
      }
      if (!mounted) return;
    }

    // (1) Show SanaStore cache immediately if present.
    final cached = SanaStore.instance.rows(_table);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _rows = List<Map<String, dynamic>>.from(cached);
        _loading = false;
      });
    }

    // (2) Background fetch from Supabase.
    try {
      final String cols;
      switch (_table) {
        case 'medications':
          cols = 'id, user_id, guest_id, name, dosage, reminder_time, '
              'reminder_date, reminder_schedule_type, photo_url, '
              'photo_base64, ringtone_path, notes';
          break;
        case 'reminders':
          cols = 'id, user_id, guest_id, medication_id, name, dosage, '
              'reminder_time, reminder_date, description, is_active, '
              'notes, created_at, updated_at, photo_url, photo_base64';
          break;
        case 'documents':
          cols = 'id, user_id, guest_id, title, category, file_url, '
              'file_type, photo_url, photo, photo_base64';
          break;
        case 'insurance_cards':
          cols = 'id, user_id, guest_id, provider_name, policy_number, '
              'front_image_url, back_image_url, created_at, photo_url';
          break;
        case 'doctors':
          cols = 'id, user_id, guest_id, name, specialty, phone, address';
          break;
        case 'pharmacies':
          cols = 'id, user_id, guest_id, name, address, phone';
          break;
        default:
          cols = '*';
      }

      final query = _client.from(_table).select(cols);
      final dynamic response = widget.guestMode
          ? await query.eq('guest_id', GuestIdentityService.sharedGuestId)
          : await query.eq('user_id', widget.ownerId);

      if (!mounted) return;

      final List<dynamic> list = response as List<dynamic>;
      final serverRecords =
          list.map((item) => Map<String, dynamic>.from(item as Map)).toList();

      // (3) Reconcile: server + dirty wins, deleted removed.
      final merged = SanaStore.instance.reconcile(_table, serverRecords);

      setState(() {
        _rows = merged;
        _loading = false;
      });

      if (_table == 'reminders' && widget.remindersEnabled) {
        unawaited(
          Future(() async {
            for (final row in merged) {
              try {
                await SanaAlarmService.scheduleReminder(row);
              } catch (e) {
                debugPrint(
                  'Reminder alarm scheduling failed for ${row['id']}: $e',
                );
              }
            }
          }),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (_rows.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  languageNotifier.value,
                  'error_loading',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'name':
        return 'name';
      case 'dosage':
        return 'dosage';
      case 'quantity':
        return 'quantity';
      case 'notes':
        return 'notes';
      case 'reminder_time':
        return 'reminder_time';
      case 'reminder_date':
        return 'reminder_date';
      case 'description':
        return 'description';
      case 'specialty':
        return 'specialty';
      case 'phone':
        return 'phone';
      case 'address':
        return 'address';
      case 'title':
        return 'title';
      case 'category':
        return 'category';
      case 'file_url':
        return 'file_url';
      case 'provider_name':
        return 'provider_name';
      case 'front_photo':
        return 'front_photo';
      case 'back_photo':
        return 'back_photo';
      case 'location':
        return 'location';
      case 'photo':
        return 'photo';
      case 'medication_name':
        return 'name';
      default:
        return field;
    }
  }

  List<String> _getRequiredFields() {
    switch (widget.type) {
      case 'medications':
        return ['name', 'dosage'];
      case 'doctors':
        return ['name'];
      case 'pharmacies':
        return ['name'];
      case 'reminders':
        return ['name', 'reminder_time', 'reminder_date'];
      case 'documents':
        return ['title'];
      case 'insurance_cards':
        return ['provider_name', 'front_photo', 'back_photo'];
      default:
        return ['name'];
    }
  }

  List<String> _getFields() {
    switch (widget.type) {
      case 'medications':
        return [
          'name',
          'dosage',
          'quantity',
          'notes',
          //'photo',
          'reminder_time',
          'reminder_date',
        ];
      case 'doctors':
        return ['name', 'specialty', 'phone', 'address'];
      case 'pharmacies':
        return ['name', 'phone', 'address'];
      case 'reminders':
        return [
          'name',
          'dosage',
          'reminder_time',
          'reminder_date',
          'notes',
          //'description'
        ];
      case 'documents':
        return ['title', 'category', 'photo'];
      case 'insurance_cards':
        return ['provider_name', 'front_photo', 'back_photo', 'policy_number'];
      default:
        return ['name'];
    }
  }

  Future<void> _add() async {
    final language = languageNotifier.value;
    final fields = _getFields();
    final requiredFields = _getRequiredFields();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AddFormDialog(
        type: widget.type,
        language: language,
        medicationsList: _medicationsList,
        fields: fields,
        requiredFields: requiredFields,
        onSave: (payload) async {},
      ),
    );

    if (!mounted) return;

    if (result != null) {
      await _saveRecord(result);
    }
  }

  // FIXED: Removed guest_id, removed reminder_date for medications
  Future<void> _saveRecord(Map<String, dynamic> result) async {
    final language = languageNotifier.value;

    //print('========== _saveRecord CALLED ==========');
    //print('Table: $_table');
    //print('Result: $result');

    final currentUser = _client.auth.currentUser;
    final cleanPayload = <String, dynamic>{
      'user_id': widget.guestMode ? null : widget.ownerId,
      'guest_id': widget.guestMode ? GuestIdentityService.sharedGuestId : null,
    };

    // Helper to extract photos across forms
    String? extractPhoto() {
      if (result['photo_base64'] != null &&
          result['photo_base64'].toString().trim().isNotEmpty) {
        return result['photo_base64'].toString().trim();
      }
      if (result['photo'] != null &&
          result['photo'].toString().trim().isNotEmpty) {
        return result['photo'].toString().trim();
      }
      return null;
    }

    final photo = extractPhoto();

    if (_table == 'documents') {
      cleanPayload['title'] = result['title'] ?? result['name'] ?? 'Document';

      if (result['category'] != null) {
        cleanPayload['category'] = result['category'];
      }

      // Fix: Save photo properly
      if (photo != null && photo.toString().isNotEmpty) {
        cleanPayload['photo'] = photo.toString();
      }

      // Save URL if present
      final url = result['file_url'] ?? result['url'];
      if (url != null && url.toString().isNotEmpty) {
        cleanPayload['file_url'] = url.toString();
      }
    } else if (_table == 'insurance_cards') {
      cleanPayload['provider_name'] =
          result['provider_name'] ?? result['name'] ?? 'Insurance Card';

      cleanPayload['policy_number'] = result['policy_number'] ?? '';

      final front = result['front_photo'] ?? result['front_image_url'] ?? photo;
      if (front != null && front.toString().trim().isNotEmpty) {
        cleanPayload['front_image_url'] = front.toString().trim();
      }

      final back = result['back_photo'] ?? result['back_image_url'];
      if (back != null && back.toString().trim().isNotEmpty) {
        cleanPayload['back_image_url'] = back.toString().trim();
      }
    } else if (_table == 'reminders') {
      cleanPayload['name'] = result['name']?.toString().trim() ?? '';

      cleanPayload['dosage'] = result['dosage']?.toString().trim() ?? '';

      cleanPayload['reminder_time'] = result['reminder_time'];

      cleanPayload['reminder_date'] = result['reminder_date'];

      if (result['notes'] != null &&
          result['notes'].toString().trim().isNotEmpty) {
        cleanPayload['notes'] = result['notes'].toString().trim();
      }

      if (photo != null && photo.toString().trim().isNotEmpty) {
        cleanPayload['photo_base64'] = photo.toString().trim();
      }
    } else if (_table == 'pharmacies') {
      cleanPayload['name'] = result['name'] ?? '';
      cleanPayload['phone'] = result['phone'] ?? '';
      cleanPayload['address'] = result['address'] ?? '';
    } else if (_table == 'doctors') {
      cleanPayload['name'] = result['name'] ?? '';
      cleanPayload['specialty'] = result['specialty'] ?? '';
      cleanPayload['phone'] = result['phone'] ?? '';
      cleanPayload['address'] = result['address'] ?? '';
    } else if (_table == 'medications') {
      cleanPayload['name'] = result['name']?.toString().trim() ?? '';

      if (result['dosage'] != null &&
          result['dosage'].toString().trim().isNotEmpty) {
        cleanPayload['dosage'] = result['dosage'].toString().trim();
      }

      if (result['notes'] != null &&
          result['notes'].toString().trim().isNotEmpty) {
        cleanPayload['notes'] = result['notes'].toString().trim();
      }

      if (result['reminder_time'] != null) {
        cleanPayload['reminder_time'] = result['reminder_time'];
      }

      if (result['reminder_date'] != null &&
          result['reminder_date'].toString().trim().isNotEmpty) {
        cleanPayload['reminder_date'] =
            result['reminder_date'].toString().trim();
      }

      // Keep the original image data in the row so the medication thumbnail
      // works across the shared guest pool and across devices. Storage is
      // still uploaded as an additional copy for existing behavior.
      if (photo != null && photo.toString().trim().isNotEmpty) {
        cleanPayload['photo_base64'] = photo.toString().trim();
      }
    }

    // (1) Optimistic local row so the UI updates immediately.
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticRow = <String, dynamic>{
      'id': tempId,
      ...cleanPayload,
    };

    if (mounted) {
      setState(() {
        _rows.add(optimisticRow);
      });
    }

    // (2) Fire the Supabase write (and any photo upload) in the background.
    //     _saveRecord returns immediately after the setState above.
    final saveFuture = Future(() async {
      // Track the uploaded Storage path OUTSIDE the try so the catch can
      // delete an orphaned file if the Supabase insert fails after upload.
      String? uploadedPhotoPath;

      try {
        // For medications and reminders, upload the photo here so the
        // Save button is not blocked on Storage upload.
        if ((_table == 'medications' || _table == 'reminders') &&
            photo != null &&
            photo.toString().trim().isNotEmpty) {
          try {
            uploadedPhotoPath = await StorageHelper.uploadMedicationPhoto(
              base64Image: photo.toString(),
            );
            cleanPayload['photo_url'] = uploadedPhotoPath;
          } catch (e) {
            debugPrint(
              'Medication photo upload failed; continuing without photo: $e',
            );
          }
        }

        final inserted =
            await _client.from(_table).insert(cleanPayload).select().single();

        final insertedRow = Map<String, dynamic>.from(inserted as Map);

        // Replace the temp row with the real server row.
        // Remove by id first (both temp and real), then add once.
        if (mounted) {
          setState(() {
            final realId = insertedRow['id']?.toString() ?? '';
            _rows.removeWhere(
              (r) => r['id']?.toString() == tempId,
            );
            if (realId.isNotEmpty) {
              _rows.removeWhere(
                (r) => r['id']?.toString() == realId,
              );
            }
            _rows.add(insertedRow);
          });
        }

        // Alarm scheduling for reminders (background).
        if (_table == 'reminders' && widget.remindersEnabled) {
          try {
            await SanaAlarmService.scheduleReminder(insertedRow);
          } catch (e) {
            debugPrint('Reminder saved but alarm scheduling failed: $e');
          }
        }

        if (!mounted) return;

        if (_table == 'reminders') {
          final reminderName = cleanPayload['name']?.toString() ?? '';
          final reminderTime = cleanPayload['reminder_time']?.toString() ?? '';
          final reminderDate = cleanPayload['reminder_date']?.toString() ??
              tr(language, 'daily');

          final message = tr(
            language,
            'reminder_saved_successfully',
          )
              .replaceAll('{name}', reminderName)
              .replaceAll('{date}', reminderDate)
              .replaceAll('{time}', reminderTime);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.teal.shade700,
              duration: const Duration(seconds: 4),
              content: Row(
                children: [
                  const Icon(
                    Icons.alarm_on,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
              content: Text(
                tr(language, 'saved_successfully'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('========== ERROR in _saveRecord ==========');
        debugPrint('$e');

        // Orphan-photo cleanup: if the upload succeeded but the insert
        // (or anything after) failed, delete the uploaded Storage file.
        if (uploadedPhotoPath != null && uploadedPhotoPath.trim().isNotEmpty) {
          try {
            await StorageHelper.deleteMedicationPhoto(uploadedPhotoPath);
          } catch (_) {}
        }

        // Rollback: remove the optimistic row.
        if (mounted) {
          setState(() {
            _rows.removeWhere(
              (r) => r['id']?.toString() == tempId,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 6),
              content: Text(
                '${tr(language, 'operation_failed')}: $e',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    });

    // Wait for every record save to finish before leaving this screen.
    // The previous detached write could still be uploading/inserting when
    // the user refreshed or navigated away, so the next load saw no row.
    if (_table == 'reminders') {
      _reminderSaveInFlight = saveFuture;
    }

    try {
      await saveFuture;
    } finally {
      if (_table == 'reminders' &&
          identical(_reminderSaveInFlight, saveFuture)) {
        _reminderSaveInFlight = null;
      }
    }
  }

  // FIXED: Document photo upload - uses base64 only (no File for web)
  Future<void> _pickDocumentPhoto() async {
    final base64 = await ImagePickerHelper.pickImageAsBase64();
    if (base64 != null) {
      setState(() {
        _documentPhotoBase64 = base64;
      });
    }
  }

  // FIXED: Insurance card front photo - uses base64 only (no File for web)
  Future<void> _pickFrontCard() async {
    final base64 = await ImagePickerHelper.pickImageAsBase64();
    if (base64 != null) {
      setState(() {
        _frontCardBase64 = base64;
      });
    }
  }

  // FIXED: Insurance card back photo - uses base64 only (no File for web)
  Future<void> _pickBackCard() async {
    final base64 = await ImagePickerHelper.pickImageAsBase64();
    if (base64 != null) {
      setState(() {
        _backCardBase64 = base64;
      });
    }
  }

  // FIXED: Insurance card submit - uses base64 only

  Future<void> _submitInsuranceCard() async {
    final language = languageNotifier.value;

    if (!_formKey.currentState!.validate()) return;

    if (_frontCardBase64 == null || _backCardBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(language, 'please_upload_both_cards'))),
      );
      return;
    }

    try {
      final payload = {
        'name': _insuranceCompanyController.text.trim(),
        'provider_name': _insuranceCompanyController.text.trim(),
        'patient_id': _patientIdController.text.trim(),
        'front_image_url': _frontCardBase64,
        'back_image_url': _backCardBase64,
      };

      final cleanPayload = RecordSanitizer.sanitize(payload);

      final currentUser = _client.auth.currentUser;

      if (widget.guestMode) {
        cleanPayload['user_id'] = null;
        cleanPayload['guest_id'] =
            widget.guestMode ? GuestIdentityService.sharedGuestId : null;
      } else {
        cleanPayload['user_id'] = widget.ownerId;
        cleanPayload['guest_id'] = null;
      }

      if (cleanPayload['user_id'] == null) {
        cleanPayload.remove('user_id');
      }
      if (cleanPayload['guest_id'] == null) {
        cleanPayload.remove('guest_id');
      }

      final inserted =
          await _client.from(_table).insert(cleanPayload).select().single();

      final insertedRow = Map<String, dynamic>.from(inserted as Map);

      try {
        SanaStore.instance.upsert(_table, insertedRow);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _frontCardBase64 = null;
          _backCardBase64 = null;
          _insuranceCompanyController.clear();
          _patientIdController.clear();
        });
      }

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
            content: Text(
              '${tr(language, 'add')} ${tr(language, 'insurance_cards')} ${tr(language, 'success')}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
            content: Text(
              '${tr(language, 'operation_failed')}: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  // FIXED: Document submit - uses base64 only
  Future<void> _submitDocument() async {
    final language = languageNotifier.value;

    if (!_formKey.currentState!.validate()) return;

    if (_documentPhotoBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(language, 'please_upload_photo'))),
      );
      return;
    }

    try {
      final payload = {
        'title': _titleController.text.trim(),
        'category': _categoryController.text.trim(),
        'photo': _documentPhotoBase64,
        'file_url': _fileUrlController.text.trim(),
        'file_type': 'image',
      };

      final cleanPayload = RecordSanitizer.sanitize(payload);

      final currentUser = _client.auth.currentUser;

      if (widget.guestMode) {
        cleanPayload['user_id'] = null;
        cleanPayload['guest_id'] =
            widget.guestMode ? GuestIdentityService.sharedGuestId : null;
      } else {
        cleanPayload['user_id'] = widget.ownerId;
        cleanPayload['guest_id'] = null;
      }

      if (cleanPayload['user_id'] == null) {
        cleanPayload.remove('user_id');
      }
      if (cleanPayload['guest_id'] == null) {
        cleanPayload.remove('guest_id');
      }

      final inserted =
          await _client.from(_table).insert(cleanPayload).select().single();

      final insertedRow = Map<String, dynamic>.from(inserted as Map);

      try {
        SanaStore.instance.upsert(_table, insertedRow);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _documentPhotoBase64 = null;
          _titleController.clear();
          _categoryController.clear();
          _fileUrlController.clear();
        });
      }

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
            content: Text(
              '${tr(language, 'add')} ${tr(language, 'documents')} ${tr(language, 'success')}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
            content: Text(
              '${tr(language, 'operation_failed')}: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    if (id.toString().startsWith('local_')) return;

    final language = languageNotifier.value;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          tr(language, 'delete_confirm_title'),
        ),
        content: Text(
          tr(language, 'delete_confirm_msg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              tr(language, 'cancel'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              tr(language, 'delete'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Declare rollback data BEFORE try so catch can use it.
    final String idStr = id.toString();
    final Map<String, dynamic> originalRow = Map<String, dynamic>.from(row);
    final int originalIndex =
        _rows.indexWhere((r) => r['id']?.toString() == idStr);
    final String? photoPath = row['photo_url']?.toString();

    // (1) Remove from UI immediately.
    if (mounted) {
      setState(() {
        _rows.removeWhere((r) => r['id']?.toString() == idStr);
      });
    }

    // Remove from SanaStore and remember whether the row was dirty
    // (had an unsynced local edit) so the rollback can restore that state.
    bool wasDirty = false;
    try {
      wasDirty = SanaStore.instance.remove(_table, idStr);
    } catch (_) {}

    // (2) Everything else runs detached so _delete returns immediately.
    unawaited(Future(() async {
      try {
        // Alarm cleanup.
        if (_table == 'reminders') {
          await SanaAlarmService.cancelReminder(idStr);
          await SanaAlarmService.stopAlarmSound(
            notificationId: SanaAlarmService.notificationId(idStr, 0),
          );
        }

        // Supabase delete with existing filters.
        final query = _client.from(_table).delete().eq('id', idStr);
        if (widget.guestMode) {
          await query.eq('guest_id', GuestIdentityService.sharedGuestId);
        } else {
          await query.eq('user_id', widget.ownerId);
        }
      } catch (e) {
        // Rollback: restore the row in _rows at its original index and
        // restore it in SanaStore with its previous dirty state so a
        // later reconcile() cannot overwrite the user's local edit.
        if (mounted) {
          setState(() {
            if (originalIndex >= 0 && originalIndex <= _rows.length) {
              _rows.insert(originalIndex, originalRow);
            } else {
              _rows.add(originalRow);
            }
          });
        }
        try {
          SanaStore.instance.restore(
            _table,
            originalRow,
            wasDirty: wasDirty,
          );
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text(
                tr(language, 'delete_failed'),
              ),
            ),
          );
        }
        return;
      }

      // (3) Storage cleanup is best-effort. A Storage failure must NOT
      // roll back a successful database delete.
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        try {
          await StorageHelper.deleteMedicationPhoto(photoPath);
        } catch (e) {
          debugPrint('Storage photo cleanup failed: $e');
        }
      }

      // ==========================================
      // >>> PUT IT RIGHT HERE <<<
      // At the very end of the Future, right before }));
      // ==========================================
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              tr(language, 'delete_success'),
            ),
          ),
        );
      }
    }));
  }

  String _formatPreviewValue(String language, String key, dynamic value) {
    if (value == null ||
        value.toString().trim().isEmpty ||
        value.toString().trim() == 'null') {
      return '';
    }
    final raw = value.toString().trim();
    if (raw == 'daily') {
      return tr(language, 'daily');
    }
    if (raw.startsWith('[') && raw.endsWith(']')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.join(', ');
        }
      } catch (_) {}
    }
    return raw;
  }

  Map<String, String> _getCleanDisplayEntries(
      String language, Map<String, dynamic> row) {
    final Map<String, String> clean = {};
    const ignoredKeys = {
      'id',
      'user_id',
      'guest_id',
      'created_at',
      'updated_at',
      'is_active',
      'photo',
      'photo_base64',
      'photo_url',
      'front_photo',
      'front_image',
      'front_image_url',
      'front_card_base64',
      'back_photo',
      'back_image',
      'back_image_url',
      'back_card_base64',
      'ringtone_path',
      'reminder_schedule_type',
      'file_type',
      'file_url',
      'medication_id',
    };

    for (final entry in row.entries) {
      if (ignoredKeys.contains(entry.key)) continue;
      final valStr = _formatPreviewValue(language, entry.key, entry.value);
      if (valStr.isNotEmpty) {
        clean[tr(language, entry.key)] = valStr;
      }
    }
    return clean;
  }

  Future<void> _shareRecord(Map<String, dynamic> row) async {
    final language = languageNotifier.value;
    final title = (row['name'] ??
            row['title'] ??
            row['provider_name'] ??
            tr(language, 'record'))
        .toString();

    final cleanEntries = _getCleanDisplayEntries(language, row);
    final textBuffer = StringBuffer();
    textBuffer.writeln('=== $title ===');
    for (final entry in cleanEntries.entries) {
      textBuffer.writeln('${entry.key}: ${entry.value}');
    }

    final List<XFile> filesToShare = [];

    // 1. Check for Medication private Storage Photo
    final photoPath = row['photo_url']?.toString();
    if (photoPath != null && photoPath.isNotEmpty) {
      final signedUrl = await StorageHelper.getSignedUrl(photoPath);
      if (signedUrl != null) {
        try {
          final response = await package_http.get(Uri.parse(signedUrl));
          if (response.statusCode == 200) {
            filesToShare.add(XFile.fromData(
              response.bodyBytes,
              name: 'medication_photo.jpg',
              mimeType: 'image/jpeg',
            ));
          }
        } catch (_) {}
      }
    }

    // 2. Helper to add Base64 images to share
    void addBase64File(String? raw, String filename) {
      if (raw == null || raw.trim().isEmpty) return;
      try {
        var clean = raw.trim();
        if (clean.contains(',')) clean = clean.split(',').last;
        clean = clean.replaceAll(RegExp(r'\s+'), '');
        clean = base64.normalize(clean);
        final bytes = base64Decode(clean);
        filesToShare.add(XFile.fromData(
          Uint8List.fromList(bytes),
          name: filename,
          mimeType: 'image/jpeg',
        ));
      } catch (_) {}
    }

    // Add Base64 photos (Documents, Insurance Cards, Legacy meds)
    addBase64File(row['photo']?.toString() ?? row['photo_base64']?.toString(),
        'document_photo.jpg');
    addBase64File(
        row['front_image_url']?.toString() ?? row['front_photo']?.toString(),
        'insurance_front.jpg');
    addBase64File(
        row['back_image_url']?.toString() ?? row['back_photo']?.toString(),
        'insurance_back.jpg');

    if (filesToShare.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          text: textBuffer.toString(),
          files: filesToShare,
        ),
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(
          text: textBuffer.toString(),
        ),
      );
    }
  }

  Future<void> _preview(Map<String, dynamic> row) async {
    final language = languageNotifier.value;
    final title = (row['name'] ??
            row['title'] ??
            row['provider_name'] ??
            tr(language, 'record'))
        .toString();

    String? photoBase64;
    final photoField = row['photo'] ?? row['photo_base64'];
    if (photoField != null && photoField.toString().isNotEmpty) {
      photoBase64 = photoField.toString().trim();
    }

    final photoPath = row['photo_url']?.toString();
    final frontImageUrl =
        (row['front_image_url'] ?? row['front_photo'])?.toString().trim();
    final backImageUrl =
        (row['back_image_url'] ?? row['back_photo'])?.toString().trim();
    final fileUrl = row['file_url']?.toString();
    final cleanEntries = _getCleanDisplayEntries(language, row);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
          body: InteractiveViewer(
            constrained: false,
            minScale: 1.0,
            maxScale: 4.0,
            panEnabled: true,
            scaleEnabled: true,
            boundaryMargin: const EdgeInsets.all(300),
            clipBehavior: Clip.none,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (photoBase64 != null && photoBase64.isNotEmpty)
                    DisplayImage(
                      base64String: photoBase64,
                      height: 250,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                  if (photoPath != null && photoPath.isNotEmpty)
                    SignedImage(
                      path: photoPath,
                      height: 250,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                  if (frontImageUrl != null && frontImageUrl.isNotEmpty) ...[
                    Text(tr(language, 'front_photo'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    DisplayImage(
                      base64String: frontImageUrl,
                      height: 200,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (backImageUrl != null && backImageUrl.isNotEmpty) ...[
                    Text(tr(language, 'back_photo'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    DisplayImage(
                      base64String: backImageUrl,
                      height: 200,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (fileUrl != null && fileUrl.isNotEmpty)
                    ListTile(
                      title: Text(fileUrl),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        final uri = Uri.tryParse(fileUrl);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                  const Divider(),
                  ...cleanEntries.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(Map<String, dynamic> row) {
    if (widget.type == 'medications')
      return '${row['dosage'] ?? ''} ${row['reminder_time'] ?? ''}';
    if (widget.type == 'doctors')
      return '${row['specialty'] ?? ''} ${row['phone'] ?? ''}';
    if (widget.type == 'pharmacies')
      return '${row['address'] ?? ''} ${row['phone'] ?? ''}';
    if (widget.type == 'documents')
      return '${row['category'] ?? ''} ${row['file_type'] ?? ''}';
    if (widget.type == 'insurance_cards')
      return '${row['provider_name'] ?? ''}';
    if (widget.type == 'reminders')
      return '${row['dosage'] ?? ''} ${row['reminder_time'] ?? ''} ${row['reminder_date'] ?? ''}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final language = languageNotifier.value;

    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) => Directionality(
        textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(tr(language, widget.type)),
          ),
          body: Column(
            children: [
              Expanded(
                child: _loading && _rows.isEmpty
                    ? Center(
                        child: Text(
                          tr(language, 'loading'),
                        ),
                      )
                    : _rows.isEmpty
                        ? Center(child: Text(tr(language, 'no_records')))
                        : widget.type != 'reminders'
                            ? ListView.builder(
                                key: ValueKey('list_${widget.type}'),
                                padding: const EdgeInsets.all(12),
                                itemCount: _rows.length,
                                itemBuilder: (context, index) {
                                  final row = _rows[index];
                                  final title = (row['name'] ??
                                          row['title'] ??
                                          row['provider_name'] ??
                                          tr(language, 'record'))
                                      .toString();

                                  return Card(
                                    key: ValueKey('card_${row['id']}_$index'),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    elevation: 2,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => _preview(row),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            if (widget.type == 'medications')
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 12),
                                                child: (() {
                                                  final base64Photo =
                                                      row['photo_base64']
                                                          ?.toString()
                                                          .trim();
                                                  final photoPath =
                                                      row['photo_url']
                                                          ?.toString()
                                                          .trim();

                                                  if (base64Photo != null &&
                                                      base64Photo.isNotEmpty) {
                                                    return ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      child: DisplayImage(
                                                        base64String:
                                                            base64Photo,
                                                        height: 50,
                                                        width: 50,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    );
                                                  }

                                                  if (photoPath != null &&
                                                      photoPath.isNotEmpty) {
                                                    return ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      child: SignedImage(
                                                        path: photoPath,
                                                        height: 50,
                                                        width: 50,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    );
                                                  }

                                                  return const Icon(
                                                    Icons.medication,
                                                    size: 42,
                                                    color: Colors.teal,
                                                  );
                                                })(),
                                              ),
                                            if (widget.type == 'documents')
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 12),
                                                child: SizedBox(
                                                  height: 50,
                                                  width: 50,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    child: (() {
                                                      final b64 = (row[
                                                                  'photo'] ??
                                                              row['photo_base64'])
                                                          ?.toString()
                                                          .trim();
                                                      final path =
                                                          row['photo_url']
                                                              ?.toString()
                                                              .trim();
                                                      if (b64 != null &&
                                                          b64.isNotEmpty) {
                                                        return DisplayImage(
                                                          base64String: b64,
                                                          height: 50,
                                                          width: 50,
                                                          fit: BoxFit.cover,
                                                        );
                                                      }
                                                      if (path != null &&
                                                          path.isNotEmpty) {
                                                        return SignedImage(
                                                          path: path,
                                                          height: 50,
                                                          width: 50,
                                                          fit: BoxFit.cover,
                                                        );
                                                      }
                                                      return Container(
                                                        color: Colors
                                                            .grey.shade200,
                                                        child: const Icon(
                                                          Icons.description,
                                                          color: Colors.grey,
                                                        ),
                                                      );
                                                    })(),
                                                  ),
                                                ),
                                              ),
                                            if (widget.type ==
                                                'insurance_cards')
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 12),
                                                child: SizedBox(
                                                  height: 50,
                                                  width: 50,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    child: (() {
                                                      final front = (row[
                                                                  'front_image_url'] ??
                                                              row['front_photo'])
                                                          ?.toString()
                                                          .trim();
                                                      final path =
                                                          row['photo_url']
                                                              ?.toString()
                                                              .trim();
                                                      if (front != null &&
                                                          front.isNotEmpty) {
                                                        return DisplayImage(
                                                          base64String: front,
                                                          height: 50,
                                                          width: 50,
                                                          fit: BoxFit.cover,
                                                        );
                                                      }
                                                      if (path != null &&
                                                          path.isNotEmpty) {
                                                        return SignedImage(
                                                          path: path,
                                                          height: 50,
                                                          width: 50,
                                                          fit: BoxFit.cover,
                                                        );
                                                      }
                                                      return Container(
                                                        color: Colors
                                                            .grey.shade200,
                                                        child: const Icon(
                                                          Icons.badge,
                                                          color: Colors.grey,
                                                        ),
                                                      );
                                                    })(),
                                                  ),
                                                ),
                                              ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _subtitle(row),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (widget.type == 'doctors' ||
                                                    widget.type == 'pharmacies')
                                                  IconButton(
                                                    key: ValueKey(
                                                        'call_${row['id']}'),
                                                    icon: const Icon(
                                                      Icons.phone,
                                                      size: 20,
                                                      color: Colors.green,
                                                    ),
                                                    tooltip:
                                                        tr(language, 'call'),
                                                    onPressed: () async {
                                                      final rawPhone =
                                                          (row['phone'] ?? '')
                                                              .toString()
                                                              .trim();

                                                      if (rawPhone.isEmpty)
                                                        return;

                                                      String cleaned =
                                                          rawPhone.replaceAll(
                                                        RegExp(r'[^0-9+]'),
                                                        '',
                                                      );

                                                      if (cleaned.isEmpty)
                                                        return;

                                                      if (cleaned
                                                          .startsWith('00')) {
                                                        cleaned =
                                                            '+${cleaned.substring(2)}';
                                                      }

                                                      final waNumber = cleaned
                                                              .startsWith('+')
                                                          ? cleaned.substring(1)
                                                          : cleaned;

                                                      final waUri = Uri.parse(
                                                          'https://wa.me/$waNumber');

                                                      if (await canLaunchUrl(
                                                          waUri)) {
                                                        await launchUrl(
                                                          waUri,
                                                          mode: LaunchMode
                                                              .externalApplication,
                                                        );
                                                      } else {
                                                        final telUri =
                                                            Uri.parse(
                                                                'tel:$cleaned');

                                                        if (await canLaunchUrl(
                                                            telUri)) {
                                                          await launchUrl(
                                                            telUri,
                                                            mode: LaunchMode
                                                                .externalApplication,
                                                          );
                                                        }
                                                      }
                                                    },
                                                  ),
                                                IconButton(
                                                  key: ValueKey(
                                                      'view_${row['id']}'),
                                                  onPressed: () =>
                                                      _preview(row),
                                                  icon: const Icon(
                                                    Icons
                                                        .remove_red_eye_outlined,
                                                    size: 20,
                                                    color: Colors.teal,
                                                  ),
                                                  tooltip: tr(language, 'view'),
                                                ),
                                                IconButton(
                                                  key: ValueKey(
                                                      'share_${row['id']}'),
                                                  onPressed: () =>
                                                      _shareRecord(row),
                                                  icon: const Icon(
                                                    Icons.share,
                                                    size: 20,
                                                    color: Colors.teal,
                                                  ),
                                                  tooltip:
                                                      tr(language, 'share'),
                                                ),
                                                IconButton(
                                                  key: ValueKey(
                                                      'delete_${row['id']}'),
                                                  onPressed: () => _delete(row),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 20,
                                                    color: Colors.redAccent,
                                                  ),
                                                  tooltip:
                                                      tr(language, 'delete'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Builder(
                                builder: (context) {
                                  bool isDaily(Map<String, dynamic> row) {
                                    final date = row['reminder_date']
                                        ?.toString()
                                        .trim()
                                        .toLowerCase();

                                    return date == 'daily';
                                  }

                                  int reminderTimeMinutes(
                                    Map<String, dynamic> row,
                                  ) {
                                    final times = SanaAlarmService.parseTimes(
                                      row['reminder_time'],
                                    );

                                    if (times.isEmpty) {
                                      return 24 * 60;
                                    }

                                    var earliest = 24 * 60;

                                    for (final time in times) {
                                      final parts = time.split(':');

                                      if (parts.length < 2) {
                                        continue;
                                      }

                                      final hour = int.tryParse(parts[0]);
                                      final minute = int.tryParse(parts[1]);

                                      if (hour == null || minute == null) {
                                        continue;
                                      }

                                      final totalMinutes = hour * 60 + minute;

                                      if (totalMinutes < earliest) {
                                        earliest = totalMinutes;
                                      }
                                    }

                                    return earliest;
                                  }

                                  final dailyRows =
                                      _rows.where(isDaily).toList()
                                        ..sort(
                                          (a, b) =>
                                              reminderTimeMinutes(a).compareTo(
                                            reminderTimeMinutes(b),
                                          ),
                                        );

                                  final calendarRows = _rows
                                      .where((row) => !isDaily(row))
                                      .toList()
                                    ..sort(
                                      (a, b) =>
                                          reminderTimeMinutes(a).compareTo(
                                        reminderTimeMinutes(b),
                                      ),
                                    );

                                  if (_rows.isEmpty) {
                                    return Center(
                                      child: Text(
                                        tr(language, 'no_records'),
                                      ),
                                    );
                                  }

                                  Widget actionButtons(
                                    Map<String, dynamic> row,
                                  ) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          key: ValueKey(
                                            'view_${row['id']}',
                                          ),
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                          onPressed: () => _preview(row),
                                          icon: const Icon(
                                            Icons.remove_red_eye_outlined,
                                            size: 19,
                                            color: Colors.teal,
                                          ),
                                          tooltip: tr(language, 'view'),
                                        ),
                                        IconButton(
                                          key: ValueKey(
                                            'share_${row['id']}',
                                          ),
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                          onPressed: () => _shareRecord(row),
                                          icon: const Icon(
                                            Icons.share,
                                            size: 19,
                                            color: Colors.teal,
                                          ),
                                          tooltip: tr(language, 'share'),
                                        ),
                                        IconButton(
                                          key: ValueKey(
                                            'delete_${row['id']}',
                                          ),
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                          onPressed: () => _delete(row),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                            color: Colors.redAccent,
                                          ),
                                          tooltip: tr(language, 'delete'),
                                        ),
                                      ],
                                    );
                                  }

                                  Widget reminderImage(
                                    Map<String, dynamic> row,
                                    double size,
                                  ) {
                                    final raw =
                                        (row['photo_base64'] ?? row['photo'])
                                            ?.toString()
                                            .trim();

                                    if (raw != null && raw.isNotEmpty) {
                                      return GestureDetector(
                                        onTap: () => _preview(row),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: DisplayImage(
                                            base64String: raw,
                                            height: size,
                                            width: size,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      );
                                    }

                                    return Container(
                                      height: size,
                                      width: size,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.medication,
                                        size: size * .45,
                                        color: Colors.teal,
                                      ),
                                    );
                                  }

                                  Widget dailyCard(
                                    Map<String, dynamic> row,
                                  ) {
                                    final name =
                                        (row['name'] ?? '').toString().trim();

                                    final dosage =
                                        (row['dosage'] ?? '').toString().trim();

                                    final times = SanaAlarmService.parseTimes(
                                      row['reminder_time'],
                                    );

                                    return Card(
                                      key: ValueKey(
                                        'daily_reminder_${row['id']}',
                                      ),
                                      margin: EdgeInsets.zero,
                                      elevation: 3,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _preview(row),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              reminderImage(row, 76),
                                              const SizedBox(height: 6),
                                              Text(
                                                name.isEmpty
                                                    ? tr(
                                                        language,
                                                        'record',
                                                      )
                                                    : name,
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              if (dosage.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2,
                                                  ),
                                                  child: Text(
                                                    dosage,
                                                    textAlign: TextAlign.center,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ),
                                              if (times.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2,
                                                  ),
                                                  child: Text(
                                                    times.join(' - '),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              const Spacer(),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: actionButtons(row),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  Widget calendarCard(
                                    Map<String, dynamic> row,
                                  ) {
                                    final name =
                                        (row['name'] ?? '').toString().trim();

                                    final dosage =
                                        (row['dosage'] ?? '').toString().trim();

                                    final times = SanaAlarmService.parseTimes(
                                      row['reminder_time'],
                                    );

                                    final date = (row['reminder_date'] ?? '')
                                        .toString()
                                        .trim();

                                    return Card(
                                      key: ValueKey(
                                        'calendar_reminder_${row['id']}',
                                      ),
                                      margin: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      elevation: 2,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _preview(row),
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              reminderImage(row, 64),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name.isEmpty
                                                          ? tr(
                                                              language,
                                                              'record',
                                                            )
                                                          : name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    if (dosage.isNotEmpty)
                                                      Text(
                                                        dosage,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade700,
                                                        ),
                                                      ),
                                                    if (times.isNotEmpty)
                                                      Text(
                                                        times.join(
                                                          ' - ',
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    if (date.isNotEmpty &&
                                                        date.toLowerCase() !=
                                                            'daily')
                                                      Text(
                                                        date,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade600,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: actionButtons(row),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  return ListView(
                                    key: const ValueKey(
                                      'reminders_scroll_view',
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    children: [
                                      if (dailyRows.isNotEmpty) ...[
                                        Text(
                                          tr(
                                            language,
                                            'daily_reminders',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        GridView.builder(
                                          key: const ValueKey(
                                            'daily_reminders_grid',
                                          ),
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: dailyRows.length,
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            crossAxisSpacing: 10,
                                            mainAxisSpacing: 10,
                                            childAspectRatio: 0.82,
                                          ),
                                          itemBuilder: (context, index) {
                                            return dailyCard(
                                              dailyRows[index],
                                            );
                                          },
                                        ),
                                      ],
                                      if (dailyRows.isNotEmpty &&
                                          calendarRows.isNotEmpty)
                                        const SizedBox(height: 24),
                                      if (calendarRows.isNotEmpty) ...[
                                        Text(
                                          tr(
                                            language,
                                            'calendar_reminders',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...calendarRows.map(
                                          calendarCard,
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    key: const ValueKey('add_button'),
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 24),
                    label: Text(
                      tr(language, 'add'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// SANA ALARM SCREEN
// ============================================

class SanaStore {
  SanaStore._();
  static final SanaStore instance = SanaStore._();

  final Map<String, List<Map<String, dynamic>>> _cache = {};
  final Map<String, Set<String>> _dirty = {};
  final Map<String, Set<String>> _deleted = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Map<String, dynamic>> rows(String t) => _cache[t] ?? [];

  void setAll(String t, List<Map<String, dynamic>> r) {
    _cache[t] = r;
    _dirty[t] = {};
    _deleted[t] = {};
    _loaded = true;
  }

  void upsert(String t, Map<String, dynamic> row) {
    final list = _cache.putIfAbsent(t, () => []);
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    final i = list.indexWhere((r) => r['id']?.toString() == id);
    if (i >= 0) {
      list[i] = row;
    } else {
      list.add(row);
    }
    _dirty.putIfAbsent(t, () => {}).add(id);
    _deleted.putIfAbsent(t, () => {}).remove(id);
  }

  /// Remove a row optimistically. Returns whether the row was dirty
  /// (had an unsynced local edit) so the caller can restore that state
  /// if the backend delete fails.
  bool remove(String t, String id) {
    final wasDirty = _dirty[t]?.contains(id) ?? false;
    _cache[t]?.removeWhere((r) => r['id']?.toString() == id);
    _deleted.putIfAbsent(t, () => {}).add(id);
    _dirty.putIfAbsent(t, () => {}).remove(id);
    return wasDirty;
  }

  /// Restore a row whose optimistic delete failed. Clears the id from
  /// _deleted, re-adds the row, and re-marks it dirty if it had an
  /// unsynced local edit before the delete attempt.
  void restore(
    String t,
    Map<String, dynamic> row, {
    bool wasDirty = false,
  }) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    _deleted.putIfAbsent(t, () => {}).remove(id);
    final list = _cache.putIfAbsent(t, () => []);
    final i = list.indexWhere((r) => r['id']?.toString() == id);
    if (i >= 0) {
      list[i] = row;
    } else {
      list.add(row);
    }
    if (wasDirty) {
      _dirty.putIfAbsent(t, () => {}).add(id);
    }
  }

  /// Merge server rows with local pending state.
  /// - Local dirty rows override server rows (unsynced edits).
  /// - Locally deleted ids are removed so a refresh cannot resurrect them.
  /// Does NOT clear _dirty / _deleted. Use flush() to clear them.
  List<Map<String, dynamic>> reconcile(
    String t,
    List<Map<String, dynamic>> serverRows,
  ) {
    final merged = <String, Map<String, dynamic>>{};

    for (final r in serverRows) {
      final id = r['id']?.toString();
      if (id == null || id.isEmpty) continue;
      merged[id] = r;
    }

    final cached = _cache[t] ?? const <Map<String, dynamic>>[];
    final dirty = _dirty[t] ?? const <String>{};
    for (final r in cached) {
      final id = r['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (dirty.contains(id)) merged[id] = r;
    }

    final gone = _deleted[t] ?? const <String>{};
    for (final id in gone) {
      merged.remove(id);
    }

    final result = merged.values.toList();
    _cache[t] = result;
    _loaded = true;
    return result;
  }

  Future<void> flush(SupabaseClient c) async {
    for (final t in _cache.keys.toList()) {
      final dirty = _dirty[t] ?? {};
      final gone = _deleted[t] ?? {};
      if (dirty.isEmpty && gone.isEmpty) continue;
      for (final id in gone) {
        try {
          await c.from(t).delete().eq('id', id);
        } catch (_) {}
      }
      final rows = _cache[t] ?? [];
      for (final id in dirty) {
        final row =
            rows.firstWhere((r) => r['id']?.toString() == id, orElse: () => {});
        if (row.isEmpty) continue;
        try {
          await c.from(t).upsert(row);
        } catch (_) {}
      }
      _dirty[t] = {};
      _deleted[t] = {};
    }
  }

  void reset() {
    _cache.clear();
    _dirty.clear();
    _deleted.clear();
    _loaded = false;
  }
}

class SanaAlarmScreen extends StatefulWidget {
  final String reminderId;
  final int notificationId;
  final bool daily;

  /*
   * Native Android supplies these fields directly from
   * SanaAlarmCache.
   *
   * They are optional because iOS / older notification
   * paths may not provide them.
   */
  final String name;
  final String dosage;
  final String reminderTime;
  final String reminderDate;
  final String photoBase64;

  const SanaAlarmScreen({
    super.key,
    required this.reminderId,
    required this.notificationId,
    required this.daily,
    this.name = '',
    this.dosage = '',
    this.reminderTime = '',
    this.reminderDate = '',
    this.photoBase64 = '',
  });

  @override
  State<SanaAlarmScreen> createState() => _SanaAlarmScreenState();
}

class _SanaAlarmScreenState extends State<SanaAlarmScreen> {
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _reminder;

  bool _loading = true;

  bool _taken = false;

  @override
  void initState() {
    super.initState();

    /*
     * Put the native cached payload into the screen FIRST.
     *
     * This means the alarm screen has usable data even when
     * Supabase is unreachable.
     */
    final cached = <String, dynamic>{};

    if (widget.name.trim().isNotEmpty) {
      cached['name'] = widget.name.trim();
    }

    if (widget.dosage.trim().isNotEmpty) {
      cached['dosage'] = widget.dosage.trim();
    }

    if (widget.reminderTime.trim().isNotEmpty) {
      cached['reminder_time'] = widget.reminderTime.trim();
    }

    if (widget.reminderDate.trim().isNotEmpty) {
      cached['reminder_date'] = widget.reminderDate.trim();
    }

    if (widget.photoBase64.trim().isNotEmpty) {
      cached['photo_base64'] = widget.photoBase64.trim();
    }

    if (cached.isNotEmpty) {
      _reminder = cached;
    }

    _loadReminder();
  }

  Future<void> _loadReminder() async {
    try {
      /*
       * Supabase is only an enhancement here.
       *
       * The screen already has its native offline payload.
       */
      final result = await _client
          .from('reminders')
          .select('*')
          .eq(
            'id',
            widget.reminderId,
          )
          .maybeSingle();

      if (!mounted) {
        return;
      }

      if (result != null) {
        final server = Map<String, dynamic>.from(
          result,
        );

        final existing = _reminder ?? <String, dynamic>{};

        final merged = <String, dynamic>{
          ...existing,
          ...server,
        };

        /*
         * If the server row does not contain the offline
         * photo, preserve the cached photo.
         */
        final serverPhoto = server['photo_base64']?.toString().trim();

        if ((serverPhoto == null || serverPhoto.isEmpty) &&
            existing['photo_base64']?.toString().trim().isNotEmpty == true) {
          merged['photo_base64'] = existing['photo_base64'];
        }

        setState(() {
          _reminder = merged;

          _loading = false;
        });
      } else {
        /*
         * No server record.
         *
         * Keep the native cached record.
         */
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint(
        'Alarm reminder load error: $e',
      );

      if (mounted) {
        /*
         * IMPORTANT:
         * Do NOT clear _reminder here.
         *
         * The native cached payload is the offline fallback.
         */
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _markTaken() async {
    if (_taken) {
      return;
    }

    setState(() {
      _taken = true;
    });

    if (widget.daily) {
      /*
       * DAILY:
       *
       * Stop today's ringing.
       * Dismiss today's notification.
       *
       * DO NOT call cancelNativeAlarm().
       *
       * SanaAlarmReceiver has already scheduled tomorrow's
       * daily occurrence.
       */
      await SanaAlarmService.stopAlarmSound(
        notificationId: widget.notificationId,
      );

      await SanaAlarmService.dismissNativeAlarmNotification(
        widget.notificationId,
      );
    } else {
      /*
       * ONE-TIME:
       *
       * Stop the current alarm.
       * Cancel its native alarm.
       * Cancel all remaining native alarms for this reminder.
       */
      await SanaAlarmService.stopAlarmSound(
        notificationId: widget.notificationId,
      );

      await SanaAlarmService.cancelNativeAlarm(
        widget.notificationId,
      );

      await SanaAlarmService.cancelReminder(
        widget.reminderId,
      );
    }

    if (!mounted) {
      return;
    }

    final nav = Navigator.of(
      context,
      rootNavigator: true,
    );

    if (nav.canPop()) {
      nav.pop();
      return;
    }

    nav.pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _closeAlarmScreen() async {
    await SanaAlarmService.stopAlarmSound(
      notificationId: widget.notificationId,
    );

    if (!mounted) {
      return;
    }

    final nav = Navigator.of(
      context,
      rootNavigator: true,
    );

    if (nav.canPop()) {
      nav.pop();
      return;
    }

    nav.pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    /*
     * Preserve the existing safety behavior.
     */
    SanaAlarmService.stopAlarmSound();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final language = languageNotifier.value;

    final reminder = _reminder;

    final name = reminder?['name']?.toString() ?? '';

    final dosage = reminder?['dosage']?.toString() ?? '';

    final times = SanaAlarmService.parseTimes(
      reminder?['reminder_time'],
    );

    final photo = reminder?['photo_base64']?.toString();

    return Directionality(
      textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(
                      24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tr(
                            language,
                            'alarm',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 24,
                        ),
                        if (photo != null && photo.trim().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              20,
                            ),
                            child: DisplayImage(
                              base64String: photo,
                              height: 260,
                              width: 260,
                              fit: BoxFit.contain,
                            ),
                          )
                        else
                          const Icon(
                            Icons.medication,
                            color: Colors.white,
                            size: 180,
                          ),
                        const SizedBox(
                          height: 24,
                        ),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (dosage.isNotEmpty) ...[
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            dosage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 22,
                            ),
                          ),
                        ],
                        if (times.isNotEmpty) ...[
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            times.join(
                              ' - ',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 20,
                            ),
                          ),
                        ],
                        const SizedBox(
                          height: 40,
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 70,
                          child: FilledButton(
                            onPressed: _taken ? null : _markTaken,
                            child: Text(
                              tr(language, 'taken'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 70,
                          child: OutlinedButton(
                            onPressed: _taken ? null : _closeAlarmScreen,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              tr(language, 'close'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ============================================
// SHARE SCREEN
// ============================================

class ShareScreen extends StatefulWidget {
  final String ownerId;
  final bool guestMode;
  const ShareScreen(
      {super.key, required this.ownerId, required this.guestMode});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _client = Supabase.instance.client;
  final Map<String, List<Map<String, dynamic>>> _allData = {};
  final Map<String, Set<String>> _selectedIds = {};
  bool _loading = true;
  final Map<String, GlobalKey> _itemShareKeys = {};
  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final types = [
      'medications',
      'doctors',
      'pharmacies',
      'documents',
      'insurance_cards'
    ];
    for (final type in types) {
      final table = type == 'reminders' ? 'reminders' : type;
      try {
        final String cols;
        switch (table) {
          case 'medications':
            cols = 'id, user_id, guest_id, name, dosage, reminder_time, '
                'reminder_date, photo_url, notes';
            break;
          case 'doctors':
            cols = 'id, user_id, guest_id, name, specialty, phone, address';
            break;
          case 'pharmacies':
            cols = 'id, user_id, guest_id, name, address, phone';
            break;
          case 'documents':
            cols = 'id, user_id, guest_id, title, category, file_url';
            break;
          case 'insurance_cards':
            cols = 'id, user_id, guest_id, provider_name, policy_number';
            break;
          default:
            cols = '*';
        }
        final query = _client.from(table).select(cols);
        final dynamic response = widget.guestMode
            ? await query.eq('guest_id', GuestIdentityService.sharedGuestId)
            : await query.eq('user_id', widget.ownerId);

        final List<dynamic> list = response as List<dynamic>;
        var rows =
            list.map((item) => Map<String, dynamic>.from(item as Map)).toList();

        if (type == 'reminders') {
          rows = rows
              .where((r) => (r['reminder_time'] ?? '').toString().isNotEmpty)
              .toList();
        }
        if (mounted) {
          setState(() {
            _allData[type] = rows;
            _selectedIds[type] = {};
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _allData[type] = [];
            _selectedIds[type] = {};
          });
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toggleSelection(String type, String id) {
    setState(() {
      if (_selectedIds[type]!.contains(id)) {
        _selectedIds[type]!.remove(id);
      } else {
        _selectedIds[type]!.add(id);
      }
    });
  }

  void _toggleAll(String type) {
    setState(() {
      final ids = _allData[type]!.map((row) => row['id'].toString()).toSet();
      if (_selectedIds[type]!.length == ids.length) {
        _selectedIds[type]!.clear();
      } else {
        _selectedIds[type] = ids;
      }
    });
  }

  int _getTotalSelected() {
    int count = 0;
    for (final ids in _selectedIds.values) {
      count += ids.length;
    }
    return count;
  }

  Future<void> _shareSelected() async {
    final language = languageNotifier.value;

    if (_getTotalSelected() == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(language, 'no_selection'))),
      );
      return;
    }

    try {
      final textBuffer = StringBuffer();
      final List<XFile> files = [];

      textBuffer.writeln('SANA - ${tr(language, 'share_documents')}');
      textBuffer.writeln('');

      for (final type in _allData.keys) {
        final selectedRows = _allData[type]!
            .where((row) => _selectedIds[type]!.contains(row['id'].toString()))
            .toList();

        for (final row in selectedRows) {
          final title = (row['name'] ??
                  row['title'] ??
                  row['provider_name'] ??
                  tr(language, 'record'))
              .toString();

          textBuffer.writeln('------------------------');
          textBuffer.writeln('${tr(language, type).toUpperCase()}: $title');
          textBuffer.writeln('------------------------');

          final cleanEntries = _getCleanDisplayEntries(language, row);
          for (final e in cleanEntries.entries) {
            textBuffer.writeln('• ${e.key}: ${e.value}');
          }
          textBuffer.writeln('');

          // 1. Private Supabase Storage photo (medications)
          final photoPath = row['photo_url']?.toString();
          if (photoPath != null && photoPath.isNotEmpty) {
            try {
              final signedUrl = await StorageHelper.getSignedUrl(photoPath);
              if (signedUrl != null) {
                final resp = await package_http.get(Uri.parse(signedUrl));
                if (resp.statusCode == 200) {
                  files.add(XFile.fromData(
                    resp.bodyBytes,
                    name: 'SANA_${type}_${row['id']}.jpg',
                    mimeType: 'image/jpeg',
                  ));
                }
              }
            } catch (_) {}
          }

          // 2. Base64 photos (documents, insurance, legacy meds)
          void addBase64File(String? raw, String filename) {
            if (raw == null || raw.trim().isEmpty) return;
            try {
              var clean = raw.trim();
              if (clean.contains(',')) clean = clean.split(',').last;
              clean = clean.replaceAll(RegExp(r'\s+'), '');
              clean = base64.normalize(clean);
              final bytes = base64Decode(clean);
              files.add(XFile.fromData(
                Uint8List.fromList(bytes),
                name: filename,
                mimeType: 'image/jpeg',
              ));
            } catch (_) {}
          }

          addBase64File(
            row['photo']?.toString() ?? row['photo_base64']?.toString(),
            'SANA_${type}_${row['id']}_photo.jpg',
          );
          addBase64File(
            row['front_image_url']?.toString() ??
                row['front_photo']?.toString(),
            'SANA_${type}_${row['id']}_front.jpg',
          );
          addBase64File(
            row['back_image_url']?.toString() ?? row['back_photo']?.toString(),
            'SANA_${type}_${row['id']}_back.jpg',
          );
        }
      }

      final shareText = textBuffer.toString().trim();

      if (files.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            text: shareText,
            files: files,
            subject: 'SANA Medical Records',
          ),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: shareText,
            subject: 'SANA Medical Records',
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Share selected error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          content: Text(
            '${tr(language, 'operation_failed')}: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  String _getSubtitle(String type, Map<String, dynamic> row) {
    if (type == 'medications')
      return '${row['dosage'] ?? ''} ${row['reminder_time'] ?? ''}';
    if (type == 'doctors')
      return '${row['specialty'] ?? ''} ${row['phone'] ?? ''}';
    if (type == 'pharmacies')
      return '${row['address'] ?? ''} ${row['phone'] ?? ''}';
    if (type == 'documents')
      return '${row['category'] ?? ''} ${row['file_type'] ?? ''}';
    if (type == 'insurance_cards') return '${row['provider_name'] ?? ''}';
    if (type == 'reminders')
      return '${row['reminder_time'] ?? ''} ${row['reminder_date'] ?? ''}';
    return '';
  }

  String _formatPreviewValue(String language, String key, dynamic value) {
    if (value == null ||
        value.toString().trim().isEmpty ||
        value.toString().trim() == 'null') {
      return '';
    }
    final raw = value.toString().trim();
    if (raw == 'daily') {
      return tr(language, 'daily');
    }
    if (raw.startsWith('[') && raw.endsWith(']')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.join(', ');
        }
      } catch (_) {}
    }
    return raw;
  }

  Map<String, String> _getCleanDisplayEntries(
      String language, Map<String, dynamic> row) {
    final Map<String, String> clean = {};
    const ignoredKeys = {
      'id',
      'user_id',
      'guest_id',
      'created_at',
      'photo',
      'photo_base64',
      'photo_url',
      'front_photo',
      'front_image',
      'front_image_url',
      'front_card_base64',
      'back_photo',
      'back_image',
      'back_image_url',
      'back_card_base64',
      'ringtone_path',
      'reminder_schedule_type',
      'file_type',
      'file_url',
      'medication_id',
      'updated_at',
      'is_active',
    };

    for (final entry in row.entries) {
      if (ignoredKeys.contains(entry.key)) continue;
      final valStr = _formatPreviewValue(language, entry.key, entry.value);
      if (valStr.isNotEmpty) {
        clean[tr(language, entry.key)] = valStr;
      }
    }
    return clean;
  }

  Future<void> _previewRecord(
    String type,
    Map<String, dynamic> row,
  ) async {
    final language = languageNotifier.value;

    final title = (row['name'] ??
            row['title'] ??
            row['provider_name'] ??
            tr(language, 'record'))
        .toString();

    String? photoBase64;
    final photoField = row['photo'] ?? row['photo_base64'];

    if (photoField != null && photoField.toString().isNotEmpty) {
      photoBase64 = photoField.toString().trim();
    }

    final photoPath = row['photo_url']?.toString();

    final frontImageUrl =
        (row['front_image_url'] ?? row['front_photo'])?.toString().trim();

    final backImageUrl =
        (row['back_image_url'] ?? row['back_photo'])?.toString().trim();

    final fileUrl = row['file_url']?.toString();

    final cleanEntries = _getCleanDisplayEntries(language, row);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
          body: InteractiveViewer(
            constrained: false,
            minScale: 1.0,
            maxScale: 4.0,
            panEnabled: true,
            scaleEnabled: true,
            boundaryMargin: const EdgeInsets.all(300),
            clipBehavior: Clip.none,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Base64 Photo (Medications/Documents)
                  if (photoBase64 != null && photoBase64.isNotEmpty)
                    DisplayImage(
                      base64String: photoBase64,
                      height: 250,
                      width: 250,
                      fit: BoxFit.contain,
                    ),

                  // 2. Private Supabase Storage Photo
                  if (photoPath != null && photoPath.isNotEmpty)
                    SignedImage(
                      path: photoPath,
                      height: 250,
                      width: 250,
                      fit: BoxFit.contain,
                    ),

                  // 3. Insurance Card Front Photo
                  if (frontImageUrl != null && frontImageUrl.isNotEmpty) ...[
                    Text(
                      tr(language, 'front_photo'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DisplayImage(
                      base64String: frontImageUrl,
                      height: 200,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 4. Insurance Card Back Photo
                  if (backImageUrl != null && backImageUrl.isNotEmpty) ...[
                    Text(
                      tr(language, 'back_photo'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DisplayImage(
                      base64String: backImageUrl,
                      height: 200,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 5. File URL Link
                  if (fileUrl != null && fileUrl.isNotEmpty)
                    ListTile(
                      title: Text(fileUrl),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        final uri = Uri.tryParse(fileUrl);

                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),

                  const Divider(),

                  // 6. Clean Translated Metadata List
                  ...cleanEntries.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = languageNotifier.value;

    return Directionality(
      textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(language, 'share')),
          actions: [
            TextButton.icon(
              onPressed: _shareSelected,
              icon: const Icon(Icons.share),
              label: Text(
                '${_getTotalSelected()} ${tr(language, 'share_selected')}',
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(12),
                    children: _allData.keys.map((type) {
                      final rows = _allData[type]!;
                      final selected = _selectedIds[type]!;
                      final allSelected =
                          selected.length == rows.length && rows.isNotEmpty;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          title: Text(
                            '${tr(language, type)} (${rows.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: allSelected,
                                onChanged: (_) => _toggleAll(type),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${selected.length}/${rows.length}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          children: rows.isEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      tr(language, 'no_records'),
                                    ),
                                  ),
                                ]
                              : rows.map((row) {
                                  final id = row['id'].toString();

                                  final title = (row['name'] ??
                                          row['title'] ??
                                          row['provider_name'] ??
                                          tr(language, 'record'))
                                      .toString();

                                  return CheckboxListTile(
                                    value: selected.contains(id),
                                    onChanged: (_) =>
                                        _toggleSelection(type, id),
                                    title: Text(title),
                                    subtitle: Text(
                                      _getSubtitle(type, row),
                                    ),
                                    secondary: IconButton(
                                      icon: const Icon(
                                        Icons.remove_red_eye_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _previewRecord(type, row),
                                    ),
                                  );
                                }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                  Positioned(
                    left: -9999,
                    top: 0,
                    child: UnconstrainedBox(
                      alignment: Alignment.topLeft,
                      constrainedAxis: Axis.horizontal,
                      child: Container(
                        width: 480,
                        padding: const EdgeInsets.all(20),
                        color: Colors.white,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.health_and_safety,
                                  color: Colors.teal,
                                  size: 28,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'SANA - ${tr(language, 'share_documents')}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            for (final type in _allData.keys)
                              for (final row in _allData[type]!.where(
                                (row) => _selectedIds[type]!.contains(
                                  row['id'].toString(),
                                ),
                              ))
                                Builder(
                                  builder: (context) {
                                    final title = (row['name'] ??
                                            row['title'] ??
                                            row['provider_name'] ??
                                            tr(language, 'record'))
                                        .toString();

                                    final cleanEntries =
                                        _getCleanDisplayEntries(language, row);

                                    final photoPath =
                                        row['photo_url']?.toString();

                                    final base64Photo =
                                        row['photo']?.toString() ??
                                            row['photo_base64']?.toString();

                                    final frontPhoto =
                                        row['front_image_url']?.toString() ??
                                            row['front_photo']?.toString();

                                    final backPhoto =
                                        row['back_image_url']?.toString() ??
                                            row['back_photo']?.toString();

                                    final itemId = '${type}_${row['id']}';

                                    final itemKey = _itemShareKeys.putIfAbsent(
                                      itemId,
                                      () => GlobalKey(),
                                    );

                                    return RepaintBoundary(
                                      key: itemKey,
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.teal.shade300,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          color: Colors.white,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${tr(language, type).toUpperCase()}: $title',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal,
                                              ),
                                            ),
                                            const Divider(height: 12),
                                            ...cleanEntries.entries.map(
                                              (e) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 2,
                                                ),
                                                child: Text(
                                                  '• ${e.key}: ${e.value}',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            if (photoPath != null &&
                                                photoPath.isNotEmpty)
                                              Container(
                                                width: double.infinity,
                                                margin: const EdgeInsets.only(
                                                    top: 8),
                                                color: Colors.white,
                                                alignment: Alignment.center,
                                                child: SignedImage(
                                                  path: photoPath,
                                                  width: double.infinity,
                                                  fit: BoxFit.fitWidth,
                                                ),
                                              ),
                                            if (base64Photo != null &&
                                                base64Photo.isNotEmpty)
                                              Container(
                                                width: double.infinity,
                                                margin: const EdgeInsets.only(
                                                    top: 8),
                                                color: Colors.white,
                                                alignment: Alignment.center,
                                                child: DisplayImage(
                                                  base64String: base64Photo,
                                                  width: double.infinity,
                                                  fit: BoxFit.fitWidth,
                                                ),
                                              ),
                                            if (frontPhoto != null &&
                                                frontPhoto.isNotEmpty)
                                              Container(
                                                width: double.infinity,
                                                margin: const EdgeInsets.only(
                                                    top: 8),
                                                color: Colors.white,
                                                alignment: Alignment.center,
                                                child: DisplayImage(
                                                  base64String: frontPhoto,
                                                  width: double.infinity,
                                                  fit: BoxFit.fitWidth,
                                                ),
                                              ),
                                            if (backPhoto != null &&
                                                backPhoto.isNotEmpty)
                                              Container(
                                                width: double.infinity,
                                                margin: const EdgeInsets.only(
                                                    top: 8),
                                                color: Colors.white,
                                                alignment: Alignment.center,
                                                child: DisplayImage(
                                                  base64String: backPhoto,
                                                  width: double.infinity,
                                                  fit: BoxFit.fitWidth,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
// ============================================
// ADMIN SCREEN
// ============================================

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _client = Supabase.instance.client;
  final ScrollController _horizontalController = ScrollController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      await _client.rpc(
        'admin_repair_missing_user_profiles',
      );

      final dynamic result = await _client.rpc(
        'admin_list_registered_users',
      );

      final List<dynamic> list = result is List ? result : <dynamic>[];

      final List<Map<String, dynamic>> users = list
          .map(
            (item) => Map<String, dynamic>.from(
              item as Map,
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      debugPrint(
        'admin registered users load failed: $e',
      );

      if (!mounted) return;

      setState(() {
        _users = [];
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              languageNotifier.value,
              'operation_failed',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _setPaid(Map<String, dynamic> user, bool isPaid) async {
    final id = user['id'];
    if (id == null) return;

    // Admin itself is never subject to Paid/Expiry.
    final role = (user['role'] ?? 'user').toString().toLowerCase();
    if (role == 'admin') return;

    try {
      final now = DateTime.now();

      final expiryDate = isPaid
          ? DateTime(
              now.year + 1,
              now.month,
              now.day,
            ).toIso8601String()
          : null;

      // public.users uses expiry_date for the subscription state.
      // Do NOT write is_paid or paid_at because those columns are not
      // available in the current users table.
      await _client.from('users').update({
        'expiry_date': expiryDate,
      }).eq('id', id);

      if (mounted) {
        setState(() {
          user['is_paid'] = isPaid;
          user['expiry_date'] = expiryDate;
        });
      }
    } catch (e) {
      debugPrint('Error updating paid/expiry: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating paid/expiry: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _setActive(Map<String, dynamic> user, bool active) async {
    final id = user['id'];
    if (id == null) return;

    // Admin itself must never be deactivated.
    final role = (user['role'] ?? 'user').toString().toLowerCase();
    if (role == 'admin') return;

    try {
      await _client.rpc(
        'admin_set_user_active',
        params: {
          'target_user': id,
          'activate': active,
        },
      );

      if (mounted) {
        setState(() {
          user['is_active'] = active;
        });
      }

      await _loadUsers();
    } catch (e) {
      debugPrint('Error setting active state: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating user: $e'),
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final id = user['id'];
    final name = (user['name'] ?? user['email'] ?? 'User').toString();
    final language = languageNotifier.value;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(language, 'delete_confirm_title')),
        content: Text('${tr(language, 'delete_confirm_msg')}\n\n$name'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(language, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(language, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _client.rpc('admin_delete_user', params: {'target_user': id});
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade700,
            content: Text('$name ${tr(language, 'success')}'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Error deleting user: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) => Directionality(
        textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(tr(language, 'admin_panel')),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                tooltip: tr(language, 'logout'),
                onPressed: () async {
                  await _client.auth.signOut();
                  StorageHelper.clearCache();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
          body: _loading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      height: constraints.maxHeight,
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                          },
                        ),
                        child: Scrollbar(
                          controller: _horizontalController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          scrollbarOrientation: ScrollbarOrientation.bottom,
                          child: SingleChildScrollView(
                            controller: _horizontalController,
                            scrollDirection: Axis.horizontal,
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: DataTable(
                                columns: [
                                  DataColumn(label: Text(tr(language, 'name'))),
                                  DataColumn(label: Text('Password')),
                                  DataColumn(
                                      label: Text(tr(language, 'email'))),
                                  DataColumn(
                                      label: Text(tr(language, 'phone'))),
                                  DataColumn(label: Text(tr(language, 'role'))),
                                  DataColumn(
                                      label:
                                          Text(tr(language, 'joining_date'))),
                                  DataColumn(label: Text(tr(language, 'paid'))),
                                  DataColumn(
                                      label: Text(tr(language, 'expiry_date'))),
                                  DataColumn(
                                      label: Text(tr(language, 'last_login'))),
                                  DataColumn(
                                      label: Text(tr(language, 'chat_date'))),
                                  DataColumn(
                                      label: Text(tr(language, 'status'))),
                                  DataColumn(
                                      label: Text(tr(language, 'activate'))),
                                  DataColumn(
                                      label: Text(tr(language, 'delete'))),
                                ],
                                rows: _users.map((u) {
                                  final active = u['is_active'] == true;

                                  final role = (u['role'] ?? 'user').toString();

                                  final isAdmin = role.toLowerCase() == 'admin';

                                  final nameValue =
                                      u['name']?.toString().trim() ?? '';
                                  final usernameValue =
                                      u['username']?.toString().trim() ?? '';
                                  final displayName = nameValue.isNotEmpty
                                      ? nameValue
                                      : usernameValue.isNotEmpty
                                          ? usernameValue
                                          : tr(
                                              language,
                                              'guest',
                                            );

                                  String formatDate(dynamic value) {
                                    if (value == null) return 'N/A';

                                    return value
                                        .toString()
                                        .split('.')
                                        .first
                                        .replaceFirst('T', ' ');
                                  }

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(displayName),
                                      ),
                                      DataCell(
                                        Text(
                                          (u['password_plain'] ?? '�')
                                              .toString(),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          (u['email'] ?? '').toString(),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          (u['phone'] ?? 'N/A').toString(),
                                        ),
                                      ),
                                      DataCell(
                                        Text(role),
                                      ),
                                      DataCell(
                                        Text(
                                          formatDate(
                                            u['joining_date'],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        isAdmin
                                            ? const Text('�')
                                            : Checkbox(
                                                value: u['is_paid'] == true,
                                                onChanged: (v) {
                                                  if (v == null) return;
                                                  _setPaid(u, v);
                                                },
                                              ),
                                      ),
                                      DataCell(
                                        Builder(
                                          builder: (_) {
                                            if (isAdmin) {
                                              return const Text('�');
                                            }
                                            if (u['is_paid'] != true) {
                                              return const Text('�');
                                            }
                                            final rawExp = u['expiry_date'] ??
                                                u['paid_at'];
                                            if (rawExp == null)
                                              return const Text('�');
                                            try {
                                              DateTime expDate;
                                              if (u['expiry_date'] != null) {
                                                expDate = DateTime.parse(
                                                    u['expiry_date']
                                                        .toString());
                                              } else {
                                                final p = DateTime.parse(
                                                    u['paid_at'].toString());
                                                expDate = DateTime(
                                                    p.year + 1, p.month, p.day);
                                              }
                                              final isExp = DateTime.now()
                                                  .isAfter(expDate);
                                              final f =
                                                  '${expDate.year}-${expDate.month.toString().padLeft(2, '0')}-${expDate.day.toString().padLeft(2, '0')}';
                                              return Text(
                                                f,
                                                style: TextStyle(
                                                  color: isExp
                                                      ? Colors.red
                                                      : Colors.green.shade800,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              );
                                            } catch (_) {
                                              return const Text('�');
                                            }
                                          },
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          formatDate(
                                            u['last_login_at'],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        (u['chat'] ?? '')
                                                .toString()
                                                .trim()
                                                .isEmpty
                                            ? const Text('�')
                                            : InkWell(
                                                onTap: () {
                                                  showDialog<void>(
                                                    context: context,
                                                    builder: (ctx) =>
                                                        Dialog.fullscreen(
                                                      child: Scaffold(
                                                        appBar: AppBar(
                                                          title: Text(
                                                            '${tr(language, 'chat')} - $displayName',
                                                          ),
                                                          leading: IconButton(
                                                            icon: const Icon(
                                                                Icons.close),
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    ctx),
                                                          ),
                                                        ),
                                                        body: InteractiveViewer(
                                                          constrained: false,
                                                          minScale: 1.0,
                                                          maxScale: 4.0,
                                                          panEnabled: true,
                                                          scaleEnabled: true,
                                                          boundaryMargin:
                                                              const EdgeInsets
                                                                  .all(300),
                                                          clipBehavior:
                                                              Clip.none,
                                                          child:
                                                              SingleChildScrollView(
                                                            child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  u['chat']
                                                                      .toString(),
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          15),
                                                                ),
                                                                const SizedBox(
                                                                    height: 12),
                                                                Text(
                                                                  formatDate(u[
                                                                      'chat_date']),
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color: Colors
                                                                          .grey
                                                                          .shade600),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: SizedBox(
                                                  width: 130,
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        u['chat'].toString(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500),
                                                      ),
                                                      Text(
                                                        formatDate(
                                                            u['chat_date']),
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey.shade600),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                      ),
                                      DataCell(
                                        Text(
                                          active
                                              ? tr(
                                                  language,
                                                  'active_user',
                                                )
                                              : tr(
                                                  language,
                                                  'inactive_guest',
                                                ),
                                        ),
                                      ),
                                      DataCell(
                                        ElevatedButton(
                                          onPressed: isAdmin
                                              ? null
                                              : () => _setActive(
                                                    u,
                                                    !active,
                                                  ),
                                          child: Text(
                                            active
                                                ? tr(
                                                    language,
                                                    'deactivate',
                                                  )
                                                : tr(
                                                    language,
                                                    'activate',
                                                  ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        isAdmin
                                            ? const SizedBox.shrink()
                                            : IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent,
                                                  size: 22,
                                                ),
                                                tooltip: tr(
                                                  language,
                                                  'delete',
                                                ),
                                                onPressed: () => _deleteUser(u),
                                              ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _SanaInstallHelp extends StatelessWidget {
  final String language;
  const _SanaInstallHelp({required this.language});

  String _t(String key) {
    const map = <String, Map<String, String>>{
      'en': {
        'android_title': 'Install SANA on Android',
        'android_1': 'Tap the Ã¢â€¹Â® menu at the top right of Chrome.',
        'android_2': 'Tap "Install app" or "Add to Home screen".',
        'android_3': 'Tap "Install" to confirm.',
        'ios_title': 'Install SANA on iPhone / iPad',
        'ios_1': 'Open SANA in Safari.',
        'ios_2': 'Tap the Share button.',
        'ios_3': 'Tap "Add to Home Screen".',
        'ios_4': 'Tap "Add".',
      },
      'ar': {
        'android_title': 'Ã˜ÂªÃ˜Â«Ã˜Â¨Ã™Å Ã˜Âª SANA Ã˜Â¹Ã™â€žÃ™â€° Android',
        'android_1':
            'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· Ã˜Â¹Ã™â€žÃ™â€° Ã™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã¢â€¹Â® Ã™ÂÃ™Å  Ã˜Â£Ã˜Â¹Ã™â€žÃ™â€° Ã™Å Ã™â€¦Ã™Å Ã™â€  Chrome.',
        'android_2':
            'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· "Ã˜ÂªÃ˜Â«Ã˜Â¨Ã™Å Ã˜Âª Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š" Ã˜Â£Ã™Ë† "Ã˜Â¥Ã˜Â¶Ã˜Â§Ã™ÂÃ˜Â© Ã˜Â¥Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â§Ã˜Â´Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â¦Ã™Å Ã˜Â³Ã™Å Ã˜Â©".',
        'android_3':
            'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· "Ã˜ÂªÃ˜Â«Ã˜Â¨Ã™Å Ã˜Âª" Ã™â€žÃ™â€žÃ˜ÂªÃ˜Â£Ã™Æ’Ã™Å Ã˜Â¯.',
        'ios_title': 'Ã˜ÂªÃ˜Â«Ã˜Â¨Ã™Å Ã˜Âª SANA Ã˜Â¹Ã™â€žÃ™â€° iPhone / iPad',
        'ios_1': 'Ã˜Â§Ã™ÂÃ˜ÂªÃ˜Â­ SANA Ã™ÂÃ™Å  Safari.',
        'ios_2':
            'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â²Ã˜Â± Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜Â§Ã˜Â±Ã™Æ’Ã˜Â©.',
        'ios_3':
            'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· "Ã˜Â¥Ã˜Â¶Ã˜Â§Ã™ÂÃ˜Â© Ã˜Â¥Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â§Ã˜Â´Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â¦Ã™Å Ã˜Â³Ã™Å Ã˜Â©".',
        'ios_4': 'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· "Ã˜Â¥Ã˜Â¶Ã˜Â§Ã™ÂÃ˜Â©".',
      },
      'es': {
        'android_title': 'Instalar SANA en Android',
        'android_1': 'Toca el menÃƒÂº Ã¢â€¹Â® arriba a la derecha de Chrome.',
        'android_2':
            'Toca "Instalar aplicaciÃƒÂ³n" o "AÃƒÂ±adir a pantalla de inicio".',
        'android_3': 'Toca "Instalar" para confirmar.',
        'ios_title': 'Instalar SANA en iPhone / iPad',
        'ios_1': 'Abre SANA en Safari.',
        'ios_2': 'Toca el botÃƒÂ³n Compartir.',
        'ios_3': 'Toca "AÃƒÂ±adir a pantalla de inicio".',
        'ios_4': 'Toca "AÃƒÂ±adir".',
      },
      'fr': {
        'android_title': 'Installer SANA sur Android',
        'android_1':
            'Appuyez sur le menu Ã¢â€¹Â® en haut ÃƒÂ  droite de Chrome.',
        'android_2':
            'Appuyez sur "Installer lÃ¢â‚¬â„¢application" ou "Ajouter ÃƒÂ  lÃ¢â‚¬â„¢ÃƒÂ©cran dÃ¢â‚¬â„¢accueil".',
        'android_3': 'Appuyez sur "Installer" pour confirmer.',
        'ios_title': 'Installer SANA sur iPhone / iPad',
        'ios_1': 'Ouvrez SANA dans Safari.',
        'ios_2': 'Appuyez sur le bouton Partager.',
        'ios_3': 'Appuyez sur "Sur lÃ¢â‚¬â„¢ÃƒÂ©cran dÃ¢â‚¬â„¢accueil".',
        'ios_4': 'Appuyez sur "Ajouter".',
      },
      'de': {
        'android_title': 'SANA auf Android installieren',
        'android_1':
            'Tippen Sie oben rechts in Chrome auf das Ã¢â€¹Â® MenÃƒÂ¼.',
        'android_2':
            'Tippen Sie auf "App installieren" oder "Zum Startbildschirm hinzufÃƒÂ¼gen".',
        'android_3': 'Tippen Sie auf "Installieren".',
        'ios_title': 'SANA auf iPhone / iPad installieren',
        'ios_1': 'Ãƒâ€“ffnen Sie SANA in Safari.',
        'ios_2': 'Tippen Sie auf Teilen.',
        'ios_3': 'Tippen Sie auf "Zum Home-Bildschirm".',
        'ios_4': 'Tippen Sie auf "HinzufÃƒÂ¼gen".',
      },
      'tr': {
        'android_title': 'SANAÃ¢â‚¬â„¢yÃ„Â± AndroidÃ¢â‚¬â„¢e yÃƒÂ¼kle',
        'android_1':
            'ChromeÃ¢â‚¬â„¢un saÃ„Å¸ ÃƒÂ¼stÃƒÂ¼ndeki Ã¢â€¹Â® menÃƒÂ¼sÃƒÂ¼ne dokunun.',
        'android_2':
            '"UygulamayÃ„Â± yÃƒÂ¼kle" veya "Ana ekrana ekle" seÃƒÂ§eneÃ„Å¸ine dokunun.',
        'android_3': 'Onaylamak iÃƒÂ§in "YÃƒÂ¼kle" dÃƒÂ¼Ã„Å¸mesine dokunun.',
        'ios_title': 'SANAÃ¢â‚¬â„¢yÃ„Â± iPhone / iPadÃ¢â‚¬â„¢e yÃƒÂ¼kle',
        'ios_1': 'SANAÃ¢â‚¬â„¢yÃ„Â± SafariÃ¢â‚¬â„¢de aÃƒÂ§Ã„Â±n.',
        'ios_2': 'PaylaÃ…Å¸ dÃƒÂ¼Ã„Å¸mesine dokunun.',
        'ios_3': '"Ana Ekrana Ekle" seÃƒÂ§eneÃ„Å¸ine dokunun.',
        'ios_4': '"Ekle" dÃƒÂ¼Ã„Å¸mesine dokunun.',
      },
      'hi': {
        'android_title':
            'Android Ã Â¤ÂªÃ Â¤Â° SANA Ã Â¤â€¡Ã Â¤â€šÃ Â¤Â¸Ã Â¥ÂÃ Â¤Å¸Ã Â¥â€°Ã Â¤Â² Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€š',
        'android_1':
            'Chrome Ã Â¤â€¢Ã Â¥â€¡ Ã Â¤Å Ã Â¤ÂªÃ Â¤Â° Ã Â¤Â¦Ã Â¤Â¾Ã Â¤Ë†Ã Â¤â€š Ã Â¤â€œÃ Â¤Â° Ã¢â€¹Â® Ã Â¤Â®Ã Â¥â€¡Ã Â¤Â¨Ã Â¥â€š Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å¸Ã Â¥Ë†Ã Â¤Âª Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
        'android_2':
            '"Ã Â¤ÂÃ Â¤Âª Ã Â¤â€¡Ã Â¤â€šÃ Â¤Â¸Ã Â¥ÂÃ Â¤Å¸Ã Â¥â€°Ã Â¤Â² Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€š" Ã Â¤Â¯Ã Â¤Â¾ "Ã Â¤Â¹Ã Â¥â€¹Ã Â¤Â® Ã Â¤Â¸Ã Â¥ÂÃ Â¤â€¢Ã Â¥ÂÃ Â¤Â°Ã Â¥â‚¬Ã Â¤Â¨ Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å“Ã Â¥â€¹Ã Â¤Â¡Ã Â¤Â¼Ã Â¥â€¡Ã Â¤â€š" Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å¸Ã Â¥Ë†Ã Â¤Âª Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
        'android_3':
            'Ã Â¤ÂªÃ Â¥ÂÃ Â¤Â·Ã Â¥ÂÃ Â¤Å¸Ã Â¤Â¿ Ã Â¤â€¢Ã Â¥â€¡ Ã Â¤Â²Ã Â¤Â¿Ã Â¤Â "Ã Â¤â€¡Ã Â¤â€šÃ Â¤Â¸Ã Â¥ÂÃ Â¤Å¸Ã Â¥â€°Ã Â¤Â²" Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å¸Ã Â¥Ë†Ã Â¤Âª Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
        'ios_title':
            'iPhone / iPad Ã Â¤ÂªÃ Â¤Â° SANA Ã Â¤â€¡Ã Â¤â€šÃ Â¤Â¸Ã Â¥ÂÃ Â¤Å¸Ã Â¥â€°Ã Â¤Â² Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€š',
        'ios_1':
            'Safari Ã Â¤Â®Ã Â¥â€¡Ã Â¤â€š SANA Ã Â¤â€“Ã Â¥â€¹Ã Â¤Â²Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
        'ios_2':
            'Ã Â¤Â¶Ã Â¥â€¡Ã Â¤Â¯Ã Â¤Â° Ã Â¤Â¬Ã Â¤Å¸Ã Â¤Â¨ Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å¸Ã Â¥Ë†Ã Â¤Âª Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
        'ios_3':
            '"Ã Â¤Â¹Ã Â¥â€¹Ã Â¤Â® Ã Â¤Â¸Ã Â¥ÂÃ Â¤â€¢Ã Â¥ÂÃ Â¤Â°Ã Â¥â‚¬Ã Â¤Â¨ Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å“Ã Â¥â€¹Ã Â¤Â¡Ã Â¤Â¼Ã Â¥â€¡Ã Â¤â€š" Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å¸Ã Â¥Ë†Ã Â¤Âª Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
        'ios_4':
            '"Ã Â¤Å“Ã Â¥â€¹Ã Â¤Â¡Ã Â¤Â¼Ã Â¥â€¡Ã Â¤â€š" Ã Â¤ÂªÃ Â¤Â° Ã Â¤Å¸Ã Â¥Ë†Ã Â¤Âª Ã Â¤â€¢Ã Â¤Â°Ã Â¥â€¡Ã Â¤â€šÃ Â¥Â¤',
      },
      'zh': {
        'android_title': 'Ã¥Å“Â¨ Android Ã¤Â¸Å Ã¥Â®â€°Ã¨Â£â€¦ SANA',
        'android_1':
            'Ã§â€šÂ¹Ã¥â€¡Â» Chrome Ã¥ÂÂ³Ã¤Â¸Å Ã¨Â§â€™Ã§Å¡â€ž Ã¢â€¹Â® Ã¨ÂÅ“Ã¥Ââ€¢Ã£â‚¬â€š',
        'android_2':
            'Ã§â€šÂ¹Ã¥â€¡Â»"Ã¥Â®â€°Ã¨Â£â€¦Ã¥Âºâ€Ã§â€Â¨"Ã¦Ë†â€“"Ã¦Â·Â»Ã¥Å Â Ã¥Ë†Â°Ã¤Â¸Â»Ã¥Â±ÂÃ¥Â¹â€¢"Ã£â‚¬â€š',
        'android_3': 'Ã§â€šÂ¹Ã¥â€¡Â»"Ã¥Â®â€°Ã¨Â£â€¦"Ã¤Â»Â¥Ã§Â¡Â®Ã¨Â®Â¤Ã£â‚¬â€š',
        'ios_title': 'Ã¥Å“Â¨ iPhone / iPad Ã¤Â¸Å Ã¥Â®â€°Ã¨Â£â€¦ SANA',
        'ios_1': 'Ã¥Å“Â¨ Safari Ã¤Â¸Â­Ã¦â€°â€œÃ¥Â¼â‚¬ SANAÃ£â‚¬â€š',
        'ios_2': 'Ã§â€šÂ¹Ã¥â€¡Â»Ã¥Ë†â€ Ã¤ÂºÂ«Ã¦Å’â€°Ã©â€™Â®Ã£â‚¬â€š',
        'ios_3':
            'Ã§â€šÂ¹Ã¥â€¡Â»"Ã¦Â·Â»Ã¥Å Â Ã¥Ë†Â°Ã¤Â¸Â»Ã¥Â±ÂÃ¥Â¹â€¢"Ã£â‚¬â€š',
        'ios_4': 'Ã§â€šÂ¹Ã¥â€¡Â»"Ã¦Â·Â»Ã¥Å Â "Ã£â‚¬â€š',
      },
    };
    return map[language]?[key] ?? map['en']![key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final title = isIos ? _t('ios_title') : _t('android_title');
    final steps = isIos
        ? [_t('ios_1'), _t('ios_2'), _t('ios_3'), _t('ios_4')]
        : [_t('android_1'), _t('android_2'), _t('android_3')];

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        border: Border.all(color: Colors.teal.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.install_mobile, color: Colors.teal, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${i + 1}. ${steps[i]}'),
            ),
        ],
      ),
    );
  }
}
