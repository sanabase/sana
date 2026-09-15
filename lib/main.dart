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
import 'sana_web_push.dart';
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

  static const String _channelId = 'sana_medication_alarm_v2';

  static Map<String, dynamic>? _pendingNativeAlarm;

  static String? _lastNativeAlarmKey;

  static DateTime? _lastNativeAlarmAt;

  static Future<void> initialize() async {
    // On the web, medication reminders are delivered by
    // Supabase Cron + Web Push. No native initialization needed.
    if (kIsWeb) {
      return;
    }

    tz.initializeTimeZones();

    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();

    tz.setLocalLocation(
      tz.getLocation(currentTimeZone),
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

      if (!canExact) {
        await _alarmChannel.invokeMethod(
          'requestNativeAlarmPermission',
        );
      }

      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestFullScreenIntentPermission();
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

    _pendingNativeAlarm = Map<String, dynamic>.from(raw);

    _flushPendingNativeAlarm();

    return null;
  }

  static void _flushPendingNativeAlarm() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = _pendingNativeAlarm;

      if (data == null) {
        return;
      }

      final navigator = navigatorKey.currentState;

      if (navigator == null) {
        _flushPendingNativeAlarm();
        return;
      }

      final reminderId = data['reminderId']?.toString();

      if (reminderId == null || reminderId.isEmpty) {
        _pendingNativeAlarm = null;
        return;
      }

      final notificationId =
          int.tryParse(data['notificationId']?.toString() ?? '') ?? 0;

      final daily = data['daily'] == true;

      final key = '$reminderId:$notificationId';
      final now = DateTime.now();

      if (_lastNativeAlarmKey == key &&
          _lastNativeAlarmAt != null &&
          now.difference(_lastNativeAlarmAt!) < const Duration(seconds: 5)) {
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
          ),
        ),
      );
    });
  }

  static Future<void> scheduleNativeAlarm({
    required int notificationId,
    required String reminderId,
    required DateTime scheduledDate,
    required bool daily,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _alarmChannel.invokeMethod(
      'scheduleNativeAlarm',
      {
        'notificationId': notificationId,
        'reminderId': reminderId,
        'triggerAtMillis': scheduledDate.millisecondsSinceEpoch,
        'daily': daily,
      },
    );
  }

  static Future<void> cancelNativeAlarm(
    int notificationId,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _alarmChannel.invokeMethod(
      'cancelNativeAlarm',
      {
        'notificationId': notificationId,
      },
    );
  }

  static Future<void> _onNotificationResponse(
    NotificationResponse response,
  ) async {
    if (response.payload == null || response.payload!.trim().isEmpty) {
      return;
    }

    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;

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
      debugPrint('Alarm response error: $e');
    }
  }

  static Future<void> startAlarmSound() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _alarmChannel.invokeMethod('startAlarmSound');
    } catch (e) {
      debugPrint('Start alarm sound error: $e');
    }
  }

  static Future<void> stopAlarmSound({
    int? notificationId,
  }) async {
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
      debugPrint('Stop alarm sound error: $e');
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

  static List<String> parseTimes(dynamic value) {
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
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static DateTime? parseDateTime(
    String date,
    String time,
  ) {
    final dateParts = date.split('-');
    final timeParts = time.split(':');

    if (dateParts.length != 3 || timeParts.length < 2) {
      return null;
    }

    final year = int.tryParse(dateParts[0].trim());
    final month = int.tryParse(dateParts[1].trim());
    final day = int.tryParse(dateParts[2].trim());

    var hour = int.tryParse(timeParts[0].trim());

    final minute = int.tryParse(
      timeParts[1].replaceAll(
        RegExp(r'[^0-9]'),
        '',
      ),
    );

    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }

    final upper = time.toUpperCase();

    if (upper.contains('PM') && hour < 12) {
      hour += 12;
    } else if (upper.contains('AM') && hour == 12) {
      hour = 0;
    }

    return DateTime(
      year,
      month,
      day,
      hour,
      minute,
    );
  }

  static Future<void> scheduleReminder(
    Map<String, dynamic> row,
  ) async {
    final id = row['id']?.toString();

    if (id == null || id.isEmpty) {
      return;
    }

    final times = parseTimes(row['reminder_time']);

    if (times.isEmpty) {
      return;
    }

    if (kIsWeb) {
      // Web reminders are delivered by Supabase Cron + Web Push.
      // Nothing to schedule on the device.
      return;
    }

    final reminderDate = row['reminder_date']?.toString().trim().toLowerCase();

    final scheduleType = reminderDate == 'daily' ? 'daily' : 'calendar';

    for (var index = 0; index < times.length; index++) {
      final time = times[index];

      final timeParts = time.split(':');

      if (timeParts.length < 2) {
        continue;
      }

      var hour = int.tryParse(
        timeParts[0].trim(),
      );

      final minute = int.tryParse(
        timeParts[1].replaceAll(
          RegExp(r'[^0-9]'),
          '',
        ),
      );

      if (hour == null || minute == null) {
        continue;
      }

      final upper = time.toUpperCase();

      if (upper.contains('PM') && hour < 12) {
        hour += 12;
      } else if (upper.contains('AM') && hour == 12) {
        hour = 0;
      }

      final notificationId = SanaAlarmService.notificationId(
        id,
        index,
      );

      // ==========================================================
      // DAILY REMINDER
      // ==========================================================

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

        if (!scheduled.isAfter(now)) {
          scheduled = scheduled.add(
            const Duration(days: 1),
          );
        }

        if (defaultTargetPlatform == TargetPlatform.android) {
          await SanaAlarmService.scheduleNativeAlarm(
            notificationId: notificationId,
            reminderId: id,
            scheduledDate: scheduled,
            daily: true,
          );
        } else {
          await _notifications.zonedSchedule(
            id: notificationId,
            scheduledDate: scheduled,
            title: tr(
              languageNotifier.value,
              'alarm',
            ),
            body: row['name']?.toString() ?? '',
            payload: jsonEncode({
              'id': id,
              'daily': true,
            }),
            notificationDetails: _notificationDetails(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      }

      // ==========================================================
      // CALENDAR / ONE-TIME REMINDER
      // ==========================================================

      else {
        if (reminderDate == null || reminderDate.trim().isEmpty) {
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
          tz.TZDateTime.now(tz.local),
        )) {
          continue;
        }

        if (defaultTargetPlatform == TargetPlatform.android) {
          await SanaAlarmService.scheduleNativeAlarm(
            notificationId: notificationId,
            reminderId: id,
            scheduledDate: scheduled,
            daily: false,
          );
        } else {
          await _notifications.zonedSchedule(
            id: notificationId,
            scheduledDate: scheduled,
            title: tr(
              languageNotifier.value,
              'alarm',
            ),
            body: row['name']?.toString() ?? '',
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
    for (var index = 0; index < 20; index++) {
      final id = notificationId(reminderId, index);

      await _notifications.cancel(id: id);

      await cancelNativeAlarm(id);
    }
  }
}

const Map<String, String> _languageNames = {
  'en': 'English',
  'ar': 'Ø§Ù„Ø¹Ø±Ø¨ÙŠØ©',
  'es': 'EspaÃ±ol',
  'fr': 'FranÃ§ais',
  'de': 'Deutsch',
  'tr': 'TÃ¼rkÃ§e',
  'hi': 'à¤¹à¤¿à¤¨à¥à¤¦à¥€',
  'zh': 'ä¸­æ–‡',
};

const Map<String, Map<String, String>> _translations = {
  'en': {
    'add': 'Add',
    'save': 'Save',
    'delete': 'Delete',
    'view': 'View',
    'close': 'Close',
    'share': 'Share',
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
        '1. Securely manage your health records on the web, and access your data any time, anywhere and from any device.\n2. Add and track daily prescriptions and dosages in Medications.\n3. Keep your doctor contact info and specialty notes handy.\n4. Save your preferred pharmacies with phone and location.\n5. Set multi-time dosage reminders with alerts.\n6. Store medical documents and lab reports with photos.\n7. Keep front and back photos of your insurance cards.\n8. Select and share records with your doctors anytime.\n9. Install the application on your device to get all features and activate medication alarms.\n10. Get your own private, dedicated copy that is invisible to anyone else.\n11. To install SANA on your device, open the app in your phone browser: on Android Chrome, open the â‹® menu and choose "Install app" or "Add to Home screen"; on iPhone Safari, tap the Share button and choose "Add to Home Screen".',
    'taken': 'Taken',
    'alarm': 'Medication Alarm',
    'daily_reminders': 'Daily Reminders',
    'calendar_reminders': 'Scheduled Reminders',
  },
  'ar': {
    'add': 'Ø¥Ø¶Ø§ÙØ©',
    'save': 'Ø­ÙØ¸',
    'delete': 'Ø­Ø°Ù',
    'view': 'Ø¹Ø±Ø¶',
    'close': 'Ø¥ØºÙ„Ø§Ù‚',
    'share': 'Ù…Ø´Ø§Ø±ÙƒØ©',
    'install_app': 'ØªØ«Ø¨ÙŠØª Ø§Ù„ØªØ·Ø¨ÙŠÙ‚',
    'help': 'Ù…Ø³Ø§Ø¹Ø¯Ø©',
    'call': 'Ø§ØªØµØ§Ù„',
    'chat': 'Ù…Ø­Ø§Ø¯Ø«Ø©',
    'write_comment': 'Ø§ÙƒØªØ¨ ØªØ¹Ù„ÙŠÙ‚Ùƒ...',
    'send': 'Ø¥Ø±Ø³Ø§Ù„',
    'comment_sent': 'ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„ØªØ¹Ù„ÙŠÙ‚ Ø¨Ù†Ø¬Ø§Ø­',
    'chat_date': 'Ø§Ù„Ù…Ø­Ø§Ø¯Ø«Ø© / Ø§Ù„ØªØ§Ø±ÙŠØ®',
    'joining_date': 'ØªØ§Ø±ÙŠØ® Ø§Ù„Ø§Ù†Ø¶Ù…Ø§Ù…',
    'last_login': 'Ø¢Ø®Ø± ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„',
    'login': 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„',
    'logout': 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø®Ø±ÙˆØ¬',
    'admin': 'Ø§Ù„Ù…Ø³Ø¤ÙˆÙ„',
    'medications': 'Ø§Ù„Ø£Ø¯ÙˆÙŠØ©',
    'doctors': 'Ø§Ù„Ø£Ø·Ø¨Ø§Ø¡',
    'pharmacies': 'Ø§Ù„ØµÙŠØ¯Ù„ÙŠØ§Øª',
    'reminders': 'Ø§Ù„ØªØ°ÙƒÙŠØ±Ø§Øª',
    'documents': 'Ø§Ù„Ù…Ø³ØªÙ†Ø¯Ø§Øª',
    'insurance_cards': 'Ø¨Ø·Ø§Ù‚Ø§Øª Ø§Ù„ØªØ£Ù…ÙŠÙ†',
    'name': 'Ø§Ù„Ø§Ø³Ù…',
    'dosage': 'Ø§Ù„Ø¬Ø±Ø¹Ø©',
    'notes': 'Ù…Ù„Ø§Ø­Ø¸Ø§Øª',
    'quantity': 'Ø§Ù„Ù…Ø®Ø²ÙˆÙ†',
    'description': 'Ø§Ù„ÙˆØµÙ',
    'specialty': 'Ø§Ù„ØªØ®ØµØµ',
    'phone': 'Ø§Ù„Ù‡Ø§ØªÙ',
    'address': 'Ø§Ù„Ø¹Ù†ÙˆØ§Ù†',
    'email': 'Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ Ø£Ùˆ Ø§Ø³Ù… Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…',
    'show_password': 'Ø¥Ø¸Ù‡Ø§Ø± ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ±',
    'password': 'ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ±',
    'password_6_digit': '6 Ø£Ø±Ù‚Ø§Ù…',
    'sign_in': 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„',
    'new_user': 'Ù…Ø³ØªØ®Ø¯Ù… Ø¬Ø¯ÙŠØ¯',
    'register': 'ØªØ³Ø¬ÙŠÙ„',
    'create_account': 'Ø¥Ù†Ø´Ø§Ø¡ Ø­Ø³Ø§Ø¨',
    'already_account': 'Ù‡Ù„ Ù„Ø¯ÙŠÙƒ Ø­Ø³Ø§Ø¨ Ø¨Ø§Ù„ÙØ¹Ù„ØŸ',
    'location': 'Ø§Ù„Ù…ÙˆÙ‚Ø¹',
    'photo': 'ØµÙˆØ±Ø©',
    'front_photo': 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø£Ù…Ø§Ù…ÙŠØ©',
    'back_photo': 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø®Ù„ÙÙŠØ©',
    'reminder_time': 'ÙˆÙ‚Øª Ø§Ù„ØªØ°ÙƒÙŠØ±',
    'reminder_date': 'ØªØ§Ø±ÙŠØ® Ø§Ù„ØªØ°ÙƒÙŠØ±',
    'schedule_type': 'Ø§Ù„Ø¬Ø¯ÙˆÙ„',
    'daily': 'ÙŠÙˆÙ…ÙŠ',
    'calendar': 'Ø§Ù„ØªÙ‚ÙˆÙŠÙ…',
    'select_times': 'Ø§Ø®ØªØ± ÙˆÙ‚ØªÙ‹Ø§ ÙˆØ§Ø­Ø¯Ù‹Ø§ Ø£Ùˆ Ø£ÙƒØ«Ø±',
    'select_schedule': 'Ø§Ø®ØªØ± Ø§Ù„Ø¬Ø¯ÙˆÙ„',
    'record': 'Ø³Ø¬Ù„',
    'no_records': 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ø³Ø¬Ù„Ø§Øª',
    'guest_mode': 'ÙˆØ¶Ø¹ Ø§Ù„Ø¶ÙŠÙ',
    'get_copy': 'Ø§Ø­ØµÙ„ Ø¹Ù„Ù‰ Ù†Ø³Ø®ØªÙƒ',
    'create_copy': 'Ø£Ù†Ø´Ø¦ Ù†Ø³Ø®ØªÙƒ',
    'select_all': 'ØªØ­Ø¯ÙŠØ¯ Ø§Ù„ÙƒÙ„',
    'share_selected': 'Ù…Ø´Ø§Ø±ÙƒØ© Ø§Ù„Ù…Ø­Ø¯Ø¯',
    'no_selection': 'Ù„Ù… ÙŠØªÙ… ØªØ­Ø¯ÙŠØ¯ Ø£ÙŠ Ø¹Ù†Ø§ØµØ±',
    'admin_panel': 'Ù„ÙˆØ­Ø© Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©',
    'users': 'Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…ÙˆÙ†',
    'activate': 'ØªÙØ¹ÙŠÙ„',
    'deactivate': 'ØªØ¹Ø·ÙŠÙ„',
    'status': 'Ø§Ù„Ø­Ø§Ù„Ø©',
    'role': 'Ø§Ù„Ø¯ÙˆØ±',
    'active_user': 'Ù…Ø³ØªØ®Ø¯Ù… Ù†Ø´Ø·',
    'inactive_guest': 'Ù…Ø³ØªØ®Ø¯Ù… ØºÙŠØ± Ù†Ø´Ø·',
    'expired':
        'ÙŠØ±Ø¬Ù‰ Ø§Ù„Ø­ØµÙˆÙ„ Ø¹Ù„Ù‰ Ù†Ø³Ø®ØªÙƒ Ø§Ù„Ø®Ø§ØµØ©ØŒ ÙˆØ§Ù„Ø§Ù†ØªØ¸Ø§Ø± 48 Ø³Ø§Ø¹Ø© Ø­ØªÙ‰ ÙŠØªÙ… ØªÙØ¹ÙŠÙ„Ù‡Ø§.',
    'pending_activation':
        'ÙŠØ±Ø¬Ù‰ Ø§Ù„Ø­ØµÙˆÙ„ Ø¹Ù„Ù‰ Ù†Ø³Ø®ØªÙƒ Ø§Ù„Ø®Ø§ØµØ©ØŒ ÙˆØ§Ù„Ø§Ù†ØªØ¸Ø§Ø± 48 Ø³Ø§Ø¹Ø© Ø­ØªÙ‰ ÙŠØªÙ… ØªÙØ¹ÙŠÙ„Ù‡Ø§.',
    'paid': 'ØªÙ… Ø§Ù„Ø¯ÙØ¹',
    'expiry_date': 'ØªØ§Ø±ÙŠØ® Ø§Ù„Ø§Ù†ØªÙ‡Ø§Ø¡',
    'provider_name': 'Ø§Ø³Ù… Ù…Ù‚Ø¯Ù… Ø§Ù„Ø®Ø¯Ù…Ø©',
    'front_image': 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø£Ù…Ø§Ù…ÙŠØ©',
    'back_image': 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø®Ù„ÙÙŠØ©',
    'file_url': 'Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù„Ù',
    'category': 'Ø§Ù„ÙØ¦Ø©',
    'title': 'Ø§Ù„Ø¹Ù†ÙˆØ§Ù†',
    'policy': 'Ø±Ù‚Ù… Ø§Ù„ÙˆØ«ÙŠÙ‚Ø©',
    'policy_number': 'Ø±Ù‚Ù… Ø§Ù„ÙˆØ«ÙŠÙ‚Ø©',
    'provider': 'Ù…Ù‚Ø¯Ù… Ø§Ù„Ø®Ø¯Ù…Ø©',
    'expiry': 'ØªØ§Ø±ÙŠØ® Ø§Ù„Ø§Ù†ØªÙ‡Ø§Ø¡',
    'specialist': 'Ø§Ù„Ø£Ø®ØµØ§Ø¦ÙŠ',
    'guest': 'ÙˆØ¶Ø¹ Ø§Ù„Ø¶ÙŠÙ',
    'account': 'Ø§Ù„Ø­Ø³Ø§Ø¨',
    'guest_data': 'Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ø¶ÙŠÙ',
    'full_record': 'Ø§Ù„Ø³Ø¬Ù„ Ø§Ù„ÙƒØ§Ù…Ù„',
    'share_record': 'Ù…Ø´Ø§Ø±ÙƒØ© Ø§Ù„Ø³Ø¬Ù„',
    'sign_up': 'Ø¥Ù†Ø´Ø§Ø¡ Ø­Ø³Ø§Ø¨',
    'language': 'Ø§Ù„Ù„ØºØ©',
    'select_medication': 'Ø§Ø®ØªØ± Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'select_time': 'Ø§Ø®ØªØ± Ø§Ù„ÙˆÙ‚Øª',
    'select_date': 'Ø§Ø®ØªØ± Ø§Ù„ØªØ§Ø±ÙŠØ®',
    'required_field': 'Ù‡Ø°Ø§ Ø§Ù„Ø­Ù‚Ù„ Ù…Ø·Ù„ÙˆØ¨',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'ÙŠØ±Ø¬Ù‰ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„',
    'please_fill_all': 'ÙŠØ±Ø¬Ù‰ Ù…Ù„Ø¡ Ø¬Ù…ÙŠØ¹ Ø§Ù„Ø­Ù‚ÙˆÙ„',
    'login_failed': 'ÙØ´Ù„ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„',
    'signup_failed': 'ÙØ´Ù„ Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø­Ø³Ø§Ø¨',
    'delete_confirm_title': 'Ø­Ø°ÙØŸ',
    'delete_confirm_msg': 'Ù‡Ù„ Ø£Ù†Øª Ù…ØªØ£ÙƒØ¯ Ù…Ù† Ø­Ø°Ù Ù‡Ø°Ø§ Ø§Ù„Ø³Ø¬Ù„ØŸ',
    'cancel': 'Ø¥Ù„ØºØ§Ø¡',
    'please_sign_in': 'ÙŠØ±Ø¬Ù‰ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„',
    'account_created_success': 'ØªÙ… Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø­Ø³Ø§Ø¨ Ø¨Ù†Ø¬Ø§Ø­! ÙŠØ±Ø¬Ù‰ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„.',
    'operation_failed': 'ÙØ´Ù„Øª Ø§Ù„Ø¹Ù…Ù„ÙŠØ©',
    'select_front_image': 'Ø§Ø®ØªØ± Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø£Ù…Ø§Ù…ÙŠØ©',
    'select_back_image': 'Ø§Ø®ØªØ± Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø®Ù„ÙÙŠØ©',
    'upload_image': 'Ø±ÙØ¹ ØµÙˆØ±Ø©',
    'uploaded': 'ØªÙ… Ø§Ù„Ø±ÙØ¹',
    'insurance_company_name': 'Ø§Ø³Ù… Ø´Ø±ÙƒØ© Ø§Ù„ØªØ£Ù…ÙŠÙ†',
    'patient_id': 'Ø±Ù‚Ù… Ø§Ù„Ù…Ø±ÙŠØ¶',
    'insurance_card_front': 'Ø¨Ø·Ø§Ù‚Ø© Ø§Ù„ØªØ£Ù…ÙŠÙ† - Ø§Ù„Ø£Ù…Ø§Ù…',
    'insurance_card_back': 'Ø¨Ø·Ø§Ù‚Ø© Ø§Ù„ØªØ£Ù…ÙŠÙ† - Ø§Ù„Ø®Ù„Ù',
    'no_image_selected': 'Ù„Ù… ÙŠØªÙ… Ø§Ø®ØªÙŠØ§Ø± ØµÙˆØ±Ø©',
    'upload_front_card': 'Ø±ÙØ¹ Ø§Ù„Ø¨Ø·Ø§Ù‚Ø© Ø§Ù„Ø£Ù…Ø§Ù…ÙŠØ©',
    'upload_back_card': 'Ø±ÙØ¹ Ø§Ù„Ø¨Ø·Ø§Ù‚Ø© Ø§Ù„Ø®Ù„ÙÙŠØ©',
    'add_data': 'Ø¥Ø¶Ø§ÙØ© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª',
    'please_enter_insurance_company': 'ÙŠØ±Ø¬Ù‰ Ø¥Ø¯Ø®Ø§Ù„ Ø§Ø³Ù… Ø´Ø±ÙƒØ© Ø§Ù„ØªØ£Ù…ÙŠÙ†',
    'please_enter_patient_id': 'ÙŠØ±Ø¬Ù‰ Ø¥Ø¯Ø®Ø§Ù„ Ø±Ù‚Ù… Ø§Ù„Ù…Ø±ÙŠØ¶',
    'please_upload_both_cards': 'ÙŠØ±Ø¬Ù‰ Ø±ÙØ¹ Ø§Ù„Ø¨Ø·Ø§Ù‚ØªÙŠÙ†',
    'success': 'ØªÙ… Ø¨Ù†Ø¬Ø§Ø­',
    'upload_photo': 'Ø±ÙØ¹ ØµÙˆØ±Ø©',
    'select_photo': 'Ø§Ø®ØªÙŠØ§Ø± ØµÙˆØ±Ø©',
    'photo_uploaded': 'ØªÙ… Ø±ÙØ¹ Ø§Ù„ØµÙˆØ±Ø©',
    'please_upload_photo': 'ÙŠØ±Ø¬Ù‰ Ø±ÙØ¹ ØµÙˆØ±Ø©',
    'share_app': 'Ù…Ø´Ø§Ø±ÙƒØ© Ø§Ù„ØªØ·Ø¨ÙŠÙ‚',
    'share_app_message': 'SANA - ØªØ·Ø¨ÙŠÙ‚Ùƒ Ù„Ø¥Ø¯Ø§Ø±Ø© ØµØ­ØªÙƒ!',
    'opening_payment': 'Ø¬Ø§Ø±ÙŠ ÙØªØ­ ØµÙØ­Ø© Ø§Ù„Ø¯ÙØ¹...',
    'payment_error': 'Ø®Ø·Ø£ ÙÙŠ Ø§Ù„Ø¯ÙØ¹',
    'medicine_photo': 'ØµÙˆØ±Ø© Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'no_medicine_photo': 'Ù„Ù… ÙŠØªÙ… Ø§Ø®ØªÙŠØ§Ø± ØµÙˆØ±Ø© Ù„Ù„Ø¯ÙˆØ§Ø¡',
    'upload_medicine_photo': 'Ø±ÙØ¹ ØµÙˆØ±Ø© Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'change_medicine_photo': 'ØªØºÙŠÙŠØ± ØµÙˆØ±Ø© Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'select_reminder_times': 'Ø§Ø®ØªØ± Ø£ÙˆÙ‚Ø§Øª Ø§Ù„ØªØ°ÙƒÙŠØ±',
    'selected': 'ØªÙ… Ø§Ø®ØªÙŠØ§Ø±',
    'medication_schedule': 'Ø¬Ø¯ÙˆÙ„ Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'choose_schedule_repeat': 'Ø§Ø®ØªØ± Ù…ØªÙ‰ ÙŠØªÙƒØ±Ø± Ù‡Ø°Ø§ Ø§Ù„ØªØ°ÙƒÙŠØ±:',
    'repeat_daily_msg': 'Ø³ÙŠØªÙƒØ±Ø± Ø§Ù„ØªØ°ÙƒÙŠØ± ÙƒÙ„ ÙŠÙˆÙ….',
    'select_calendar_date': 'Ø§Ø®ØªØ± ØªØ§Ø±ÙŠØ® Ø§Ù„ØªÙ‚ÙˆÙŠÙ…',
    'date': 'Ø§Ù„ØªØ§Ø±ÙŠØ®',
    'share_documents': 'Ù…Ø´Ø§Ø±ÙƒØ© Ø§Ù„Ù…Ø³ØªÙ†Ø¯Ø§Øª',
    'manual_title': 'Ø¯Ù„ÙŠÙ„ Ø³Ø§Ù†Ø§ Ø§Ù„Ø·Ø¨ÙŠ Ù„Ù„Ø¬ÙŠØ¨',
    'manual_content':
        '1. Ø£Ø¯Ø± Ø³Ø¬Ù„Ø§ØªÙƒ Ø§Ù„ØµØ­ÙŠØ© Ø¨Ø£Ù…Ø§Ù† Ø¹Ø¨Ø± Ø§Ù„ÙˆÙŠØ¨ØŒ ÙˆØªÙ…ÙƒÙ‘Ù† Ù…Ù† Ø§Ù„ÙˆØµÙˆÙ„ Ø¥Ù„Ù‰ Ø¨ÙŠØ§Ù†Ø§ØªÙƒ ÙÙŠ Ø£ÙŠ ÙˆÙ‚Øª ÙˆÙ…Ù† Ø£ÙŠ Ù…ÙƒØ§Ù† ÙˆÙ…Ù† Ø£ÙŠ Ø¬Ù‡Ø§Ø².\n2. Ø¥Ø¶Ø§ÙØ© ÙˆØªØªØ¨Ø¹ Ø§Ù„Ø£Ø¯ÙˆÙŠØ© Ø§Ù„ÙŠÙˆÙ…ÙŠØ© ÙˆØ§Ù„Ø¬Ø±Ø¹Ø§Øª.\n3. Ø§Ù„Ø§Ø­ØªÙØ§Ø¸ Ø¨Ø£Ø±Ù‚Ø§Ù… Ø§Ù„Ø£Ø·Ø¨Ø§Ø¡ ÙˆØªØ®ØµØµØ§ØªÙ‡Ù….\n4. Ø­ÙØ¸ Ø§Ù„ØµÙŠØ¯Ù„ÙŠØ§Øª Ø§Ù„Ù…ÙØ¶Ù„Ø© Ù…Ø¹ Ø§Ù„Ø¹Ù†Ø§ÙˆÙŠÙ† ÙˆØ§Ù„Ù‡ÙˆØ§ØªÙ.\n5. ØªØ¹ÙŠÙŠÙ† ØªØ°ÙƒÙŠØ±Ø§Øª Ø¨Ù…ÙˆØ§Ø¹ÙŠØ¯ ØªÙ†Ø§ÙˆÙ„ Ø§Ù„Ø¯ÙˆØ§Ø¡ Ù…Ø¹ Ø§Ù„ØªÙ†Ø¨ÙŠÙ‡Ø§Øª.\n6. Ø­ÙØ¸ Ø§Ù„Ù…Ø³ØªÙ†Ø¯Ø§Øª ÙˆØ§Ù„ØªÙ‚Ø§Ø±ÙŠØ± Ø§Ù„Ø·Ø¨ÙŠØ© Ù…Ø¹ Ø§Ù„ØµÙˆØ±.\n7. Ø­ÙØ¸ ØµÙˆØ± Ø¨Ø·Ø§Ù‚Ø§Øª Ø§Ù„ØªØ£Ù…ÙŠÙ† Ù…Ù† Ø§Ù„Ø£Ù…Ø§Ù… ÙˆØ§Ù„Ø®Ù„Ù.\n8. ØªØ­Ø¯ÙŠØ¯ ÙˆÙ…Ø´Ø§Ø±ÙƒØ© Ø§Ù„Ø³Ø¬Ù„Ø§Øª Ù…Ø¹ Ø£Ø·Ø¨Ø§Ø¦Ùƒ ÙÙŠ Ø£ÙŠ ÙˆÙ‚Øª.\n9. Ø«Ø¨Ù‘Øª Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ø¹Ù„Ù‰ Ø¬Ù‡Ø§Ø²Ùƒ Ù„Ù„Ø­ØµÙˆÙ„ Ø¹Ù„Ù‰ Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…ÙŠØ²Ø§Øª ÙˆØªÙØ¹ÙŠÙ„ Ù…Ù†Ø¨Ù‡Ø§Øª Ø§Ù„Ø£Ø¯ÙˆÙŠØ©.\n10. Ø§Ø­ØµÙ„ Ø¹Ù„Ù‰ Ù†Ø³Ø®ØªÙƒ Ø§Ù„Ø®Ø§ØµØ© ÙˆØ§Ù„Ù…Ø®ØµØµØ©ØŒ ÙˆØ§Ù„ØªÙŠ Ù„Ø§ ÙŠÙ…ÙƒÙ† Ù„Ø£ÙŠ Ø´Ø®Øµ Ø¢Ø®Ø± Ø±Ø¤ÙŠØªÙ‡Ø§.\n11. Ù„ØªØ«Ø¨ÙŠØª SANA Ø¹Ù„Ù‰ Ø¬Ù‡Ø§Ø²ÙƒØŒ Ø§ÙØªØ­ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ ÙÙŠ Ù…ØªØµÙØ­ Ù‡Ø§ØªÙÙƒ: Ø¹Ù„Ù‰ Android ChromeØŒ Ø§ÙØªØ­ Ù‚Ø§Ø¦Ù…Ø© â‹® ÙˆØ§Ø®ØªØ± "ØªØ«Ø¨ÙŠØª Ø§Ù„ØªØ·Ø¨ÙŠÙ‚" Ø£Ùˆ "Ø¥Ø¶Ø§ÙØ© Ø¥Ù„Ù‰ Ø§Ù„Ø´Ø§Ø´Ø© Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠØ©"Ø› Ø¹Ù„Ù‰ iPhone SafariØŒ Ø§Ø¶ØºØ· Ø¹Ù„Ù‰ Ø²Ø± Ø§Ù„Ù…Ø´Ø§Ø±ÙƒØ© ÙˆØ§Ø®ØªØ± "Ø¥Ø¶Ø§ÙØ© Ø¥Ù„Ù‰ Ø§Ù„Ø´Ø§Ø´Ø© Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠØ©".',
    'taken': 'ØªÙ… ØªÙ†Ø§ÙˆÙ„ Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'alarm': 'Ù…Ù†Ø¨Ù‡ Ø§Ù„Ø¯ÙˆØ§Ø¡',
    'daily_reminders': 'Ø§Ù„ØªØ°ÙƒÙŠØ±Ø§Øª Ø§Ù„ÙŠÙˆÙ…ÙŠØ©',
    'calendar_reminders': 'Ø§Ù„ØªØ°ÙƒÙŠØ±Ø§Øª Ø§Ù„Ù…Ø¬Ø¯ÙˆÙ„Ø©',
  },
  'es': {
    'add': 'AÃ±adir',
    'save': 'Guardar',
    'delete': 'Eliminar',
    'view': 'Ver',
    'close': 'Cerrar',
    'share': 'Compartir',
    'install_app': 'Instalar aplicaciÃ³n',
    'help': 'Ayuda',
    'call': 'Llamar',
    'chat': 'Chat',
    'write_comment': 'Escribe tu comentario...',
    'send': 'Enviar',
    'comment_sent': 'Comentario enviado con Ã©xito',
    'chat_date': 'Chat / Fecha',
    'joining_date': 'Fecha de registro',
    'last_login': 'Ãšltimo inicio de sesiÃ³n',
    'login': 'Iniciar sesiÃ³n',
    'logout': 'Cerrar sesiÃ³n',
    'admin': 'Administrador',
    'medications': 'Medicamentos',
    'doctors': 'MÃ©dicos',
    'pharmacies': 'Farmacias',
    'reminders': 'Recordatorios',
    'documents': 'Documentos',
    'insurance_cards': 'Tarjetas de seguro',
    'name': 'Nombre',
    'dosage': 'Dosis',
    'notes': 'Notas',
    'quantity': 'Stock',
    'description': 'DescripciÃ³n',
    'specialty': 'Especialidad',
    'phone': 'TelÃ©fono',
    'address': 'DirecciÃ³n',
    'email': 'Correo electrÃ³nico o nombre de usuario',
    'show_password': 'Mostrar contraseÃ±a',
    'password': 'ContraseÃ±a',
    'password_6_digit': '6 dÃ­gitos',
    'sign_in': 'Iniciar sesiÃ³n',
    'new_user': 'Nuevo usuario',
    'register': 'Registrarse',
    'create_account': 'Crear cuenta',
    'already_account': 'Â¿Ya tienes una cuenta?',
    'location': 'UbicaciÃ³n',
    'photo': 'Foto',
    'front_photo': 'Foto frontal',
    'back_photo': 'Foto trasera',
    'reminder_time': 'Hora del recordatorio',
    'reminder_date': 'Fecha del recordatorio',
    'schedule_type': 'ProgramaciÃ³n',
    'daily': 'Diario',
    'calendar': 'Calendario',
    'select_times': 'Seleccione una o mÃ¡s horas',
    'select_schedule': 'Seleccionar programaciÃ³n',
    'record': 'Registro',
    'no_records': 'No hay registros',
    'guest_mode': 'Modo invitado',
    'get_copy': 'ObtÃ©n tu copia',
    'create_copy': 'Crea tu copia',
    'select_all': 'Seleccionar todo',
    'share_selected': 'Compartir seleccionados',
    'no_selection': 'No hay elementos seleccionados',
    'admin_panel': 'Panel de administraciÃ³n',
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
    'category': 'CategorÃ­a',
    'title': 'TÃ­tulo',
    'policy': 'PÃ³liza',
    'policy_number': 'NÃºmero de pÃ³liza',
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
    'please_login': 'Por favor inicia sesiÃ³n',
    'please_fill_all': 'Por favor completa todos los campos',
    'login_failed': 'Error al iniciar sesiÃ³n',
    'signup_failed': 'Error al registrarse',
    'delete_confirm_title': 'Â¿Eliminar?',
    'delete_confirm_msg': 'Â¿EstÃ¡s seguro de que deseas eliminar este registro?',
    'cancel': 'Cancelar',
    'please_sign_in': 'Por favor inicia sesiÃ³n',
    'account_created_success':
        'Â¡Cuenta creada correctamente! Por favor inicia sesiÃ³n.',
    'operation_failed': 'La operaciÃ³n fallÃ³',
    'select_front_image': 'Seleccionar imagen frontal',
    'select_back_image': 'Seleccionar imagen trasera',
    'upload_image': 'Subir imagen',
    'uploaded': 'Subido',
    'insurance_company_name': 'Nombre de la compaÃ±Ã­a de seguros',
    'patient_id': 'ID del paciente',
    'insurance_card_front': 'Tarjeta de seguro - frontal',
    'insurance_card_back': 'Tarjeta de seguro - trasera',
    'no_image_selected': 'No se ha seleccionado ninguna imagen',
    'upload_front_card': 'Subir tarjeta frontal',
    'upload_back_card': 'Subir tarjeta trasera',
    'add_data': 'AÃ±adir datos',
    'please_enter_insurance_company':
        'Por favor introduce el nombre de la compaÃ±Ã­a de seguros',
    'please_enter_patient_id': 'Por favor introduce el ID del paciente',
    'please_upload_both_cards': 'Por favor sube ambas tarjetas',
    'success': 'Ã‰xito',
    'upload_photo': 'Subir foto',
    'select_photo': 'Seleccionar foto',
    'photo_uploaded': 'Foto subida',
    'please_upload_photo': 'Por favor sube una foto',
    'share_app': 'Compartir aplicaciÃ³n',
    'share_app_message': 'SANA - Â¡tu aplicaciÃ³n para gestionar tu salud!',
    'opening_payment': 'Abriendo pÃ¡gina de pago...',
    'payment_error': 'Error de pago',
    'medicine_photo': 'Foto del medicamento',
    'no_medicine_photo': 'No se ha seleccionado foto',
    'upload_medicine_photo': 'Subir foto del medicamento',
    'change_medicine_photo': 'Cambiar foto del medicamento',
    'select_reminder_times': 'Seleccionar horas de recordatorio',
    'selected': 'Seleccionado',
    'medication_schedule': 'Horario de medicaciÃ³n',
    'choose_schedule_repeat': 'Elija cuÃ¡ndo repetir el recordatorio:',
    'repeat_daily_msg': 'El recordatorio se repetirÃ¡ todos los dÃ­as.',
    'select_calendar_date': 'Seleccionar fecha del calendario',
    'date': 'Fecha',
    'share_documents': 'Compartir documentos',
    'manual_title': 'GuÃ­a mÃ©dica de bolsillo SANA',
    'manual_content':
        '1. Gestione de forma segura sus registros de salud en la web y acceda a sus datos en cualquier momento, desde cualquier lugar y desde cualquier dispositivo.\n2. Registre medicamentos diarios y dosis exactas.\n3. Guarde contactos y especialidades de sus mÃ©dicos.\n4. Guarde farmacias con direcciÃ³n y telÃ©fono.\n5. Configure recordatorios con mÃºltiples horarios y alertas.\n6. Guarde documentos e informes mÃ©dicos con fotos.\n7. Guarde fotos del anverso y reverso de tarjetas de seguro.\n8. Seleccione y comparta sus registros con su mÃ©dico en cualquier momento.\n9. Instale la aplicaciÃ³n en su dispositivo para obtener todas las funciones y activar las alarmas de medicaciÃ³n.\n10. Obtenga su propia copia privada y dedicada, invisible para cualquier otra persona.\n11. Para instalar SANA en su dispositivo, abra la aplicaciÃ³n en el navegador de su telÃ©fono: en Android Chrome, abra el menÃº â‹® y elija "Instalar aplicaciÃ³n" o "AÃ±adir a pantalla de inicio"; en iPhone Safari, pulse Compartir y elija "AÃ±adir a pantalla de inicio".',
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
    'install_app': 'Installer l\'application',
    'help': 'Aide',
    'call': 'Appeler',
    'chat': 'Discussion',
    'write_comment': 'Ã‰crivez votre commentaire...',
    'send': 'Envoyer',
    'comment_sent': 'Commentaire envoyÃ© avec succÃ¨s',
    'chat_date': 'Discussion / Date',
    'joining_date': "Date d'inscription",
    'last_login': 'DerniÃ¨re connexion',
    'login': 'Connexion',
    'logout': 'DÃ©connexion',
    'admin': 'Administrateur',
    'medications': 'MÃ©dicaments',
    'doctors': 'MÃ©decins',
    'pharmacies': 'Pharmacies',
    'reminders': 'Rappels',
    'documents': 'Documents',
    'insurance_cards': 'Cartes dâ€™assurance',
    'name': 'Nom',
    'dosage': 'Dosage',
    'notes': 'Notes',
    'quantity': 'Stock',
    'description': 'Description',
    'specialty': 'SpÃ©cialitÃ©',
    'phone': 'TÃ©lÃ©phone',
    'address': 'Adresse',
    'email': 'E-mail ou nom dâ€™utilisateur',
    'show_password': 'Afficher le mot de passe',
    'password': 'Mot de passe',
    'password_6_digit': '6 chiffres',
    'sign_in': 'Se connecter',
    'new_user': 'Nouvel utilisateur',
    'register': 'Sâ€™inscrire',
    'create_account': 'CrÃ©er un compte',
    'already_account': 'Vous avez dÃ©jÃ  un compte ?',
    'location': 'Emplacement',
    'photo': 'Photo',
    'front_photo': 'Photo avant',
    'back_photo': 'Photo arriÃ¨re',
    'reminder_time': 'Heure du rappel',
    'reminder_date': 'Date du rappel',
    'schedule_type': 'Programme',
    'daily': 'Quotidien',
    'calendar': 'Calendrier',
    'select_times': 'SÃ©lectionnez une ou plusieurs heures',
    'select_schedule': 'SÃ©lectionner le programme',
    'record': 'Dossier',
    'no_records': 'Aucun enregistrement',
    'guest_mode': 'Mode invitÃ©',
    'get_copy': 'Obtenez votre copie',
    'create_copy': 'CrÃ©ez votre copie',
    'select_all': 'Tout sÃ©lectionner',
    'share_selected': 'Partager la sÃ©lection',
    'no_selection': 'Aucun Ã©lÃ©ment sÃ©lectionnÃ©',
    'admin_panel': 'Panneau dâ€™administration',
    'users': 'Utilisateurs',
    'activate': 'Activer',
    'deactivate': 'DÃ©sactiver',
    'status': 'Statut',
    'role': 'RÃ´le',
    'active_user': 'Utilisateur actif',
    'inactive_guest': 'Utilisateur inactif',
    'expired':
        'Veuillez obtenir votre propre copie et attendre 48 heures jusquâ€™Ã  son activation.',
    'pending_activation':
        'Veuillez obtenir votre propre copie et attendre 48 heures jusquâ€™Ã  son activation.',
    'paid': 'PayÃ©',
    'expiry_date': "Date d'expiration",
    'provider_name': 'Nom du fournisseur',
    'front_image': 'Image avant',
    'back_image': 'Image arriÃ¨re',
    'file_url': 'URL du fichier',
    'category': 'CatÃ©gorie',
    'title': 'Titre',
    'policy': 'Police',
    'policy_number': 'NumÃ©ro de police',
    'provider': 'Fournisseur',
    'expiry': 'Expiration',
    'specialist': 'SpÃ©cialiste',
    'guest': 'Mode invitÃ©',
    'account': 'Compte',
    'guest_data': 'DonnÃ©es invitÃ©',
    'full_record': 'Dossier complet',
    'share_record': 'Partager le dossier',
    'sign_up': 'Sâ€™inscrire',
    'language': 'Langue',
    'select_medication': 'SÃ©lectionner un mÃ©dicament',
    'select_time': 'SÃ©lectionner lâ€™heure',
    'select_date': 'SÃ©lectionner la date',
    'required_field': 'Ce champ est obligatoire',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Veuillez vous connecter',
    'please_fill_all': 'Veuillez remplir tous les champs',
    'login_failed': 'Ã‰chec de la connexion',
    'signup_failed': 'Ã‰chec de lâ€™inscription',
    'delete_confirm_title': 'Supprimer ?',
    'delete_confirm_msg':
        'ÃŠtes-vous sÃ»r de vouloir supprimer cet enregistrement ?',
    'cancel': 'Annuler',
    'please_sign_in': 'Veuillez vous connecter',
    'account_created_success':
        'Compte crÃ©Ã© avec succÃ¨s ! Veuillez vous connecter.',
    'operation_failed': 'Ã‰chec de lâ€™opÃ©ration',
    'select_front_image': 'SÃ©lectionner lâ€™image avant',
    'select_back_image': 'SÃ©lectionner lâ€™image arriÃ¨re',
    'upload_image': 'TÃ©lÃ©verser une image',
    'uploaded': 'TÃ©lÃ©versÃ©',
    'insurance_company_name': 'Nom de la compagnie dâ€™assurance',
    'patient_id': 'ID du patient',
    'insurance_card_front': 'Carte dâ€™assurance - avant',
    'insurance_card_back': 'Carte dâ€™assurance - arriÃ¨re',
    'no_image_selected': 'Aucune image sÃ©lectionnÃ©e',
    'upload_front_card': 'TÃ©lÃ©verser la carte avant',
    'upload_back_card': 'TÃ©lÃ©verser la carte arriÃ¨re',
    'add_data': 'Ajouter les donnÃ©es',
    'please_enter_insurance_company':
        'Veuillez saisir le nom de la compagnie dâ€™assurance',
    'please_enter_patient_id': 'Veuillez saisir lâ€™ID du patient',
    'please_upload_both_cards': 'Veuillez tÃ©lÃ©verser les deux cartes',
    'success': 'SuccÃ¨s',
    'upload_photo': 'TÃ©lÃ©verser une photo',
    'select_photo': 'SÃ©lectionner une photo',
    'photo_uploaded': 'Photo tÃ©lÃ©versÃ©e',
    'please_upload_photo': 'Veuillez tÃ©lÃ©verser une photo',
    'share_app': 'Partager lâ€™application',
    'share_app_message': 'SANA - votre application de gestion de santÃ© !',
    'opening_payment': 'Ouverture de la page de paiement...',
    'payment_error': 'Erreur de paiement',
    'medicine_photo': 'Photo du mÃ©dicament',
    'no_medicine_photo': 'Aucune photo sÃ©lectionnÃ©e',
    'upload_medicine_photo': 'TÃ©lÃ©verser la photo du mÃ©dicament',
    'change_medicine_photo': 'Modifier la photo du mÃ©dicament',
    'select_reminder_times': 'SÃ©lectionner les heures de rappel',
    'selected': 'SÃ©lectionnÃ©',
    'medication_schedule': 'Programme du mÃ©dicament',
    'choose_schedule_repeat': 'Choisissez quand rÃ©pÃ©ter ce rappel :',
    'repeat_daily_msg': 'Le rappel se rÃ©pÃ©tera tous les jours.',
    'select_calendar_date': 'SÃ©lectionner la date du calendrier',
    'date': 'Date',
    'share_documents': 'Partager les documents',
    'manual_title': 'Guide mÃ©dical de poche SANA',
    'manual_content':
        '1. GÃ©rez vos dossiers de santÃ© en toute sÃ©curitÃ© sur le web et accÃ©dez Ã  vos donnÃ©es Ã  tout moment, oÃ¹ que vous soyez et depuis n\'importe quel appareil.\n2. Ajoutez et suivez les mÃ©dicaments quotidiens et les dosages.\n3. Conservez les coordonnÃ©es et spÃ©cialitÃ©s de vos mÃ©decins.\n4. Enregistrez vos pharmacies prÃ©fÃ©rÃ©es avec adresses et tÃ©lÃ©phones.\n5. Configurez des rappels pour les heures de prise des mÃ©dicaments avec alertes.\n6. Conservez les documents et rapports mÃ©dicaux avec des photos.\n7. Conservez les photos recto et verso de vos cartes d\'assurance.\n8. SÃ©lectionnez et partagez facilement vos dossiers avec vos mÃ©decins Ã  tout moment.\n9. Installez l\'application sur votre appareil pour bÃ©nÃ©ficier de toutes les fonctionnalitÃ©s et activer les alarmes de mÃ©dicaments.\n10. Obtenez votre propre copie privÃ©e et dÃ©diÃ©e, invisible pour toute autre personne.\n11. Pour installer SANA sur votre appareil, ouvrez lâ€™application dans le navigateur de votre tÃ©lÃ©phone : sur Android Chrome, ouvrez le menu â‹® et choisissez Â« Installer lâ€™application Â» ou Â« Ajouter Ã  lâ€™Ã©cran dâ€™accueil Â» ; sur iPhone Safari, appuyez sur Partager et choisissez Â« Sur lâ€™Ã©cran dâ€™accueil Â».',
    'taken': 'Pris',
    'alarm': 'Alarme de mÃ©dicament',
    'daily_reminders': 'Rappels quotidiens',
    'calendar_reminders': 'Rappels programmÃ©s',
  },
  'de': {
    'add': 'HinzufÃ¼gen',
    'save': 'Speichern',
    'delete': 'LÃ¶schen',
    'view': 'Anzeigen',
    'close': 'SchlieÃŸen',
    'share': 'Teilen',
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
    'doctors': 'Ã„rzte',
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
    'back_photo': 'RÃ¼ckseite',
    'reminder_time': 'Erinnerungszeit',
    'reminder_date': 'Erinnerungsdatum',
    'schedule_type': 'Zeitplan',
    'daily': 'TÃ¤glich',
    'calendar': 'Kalender',
    'select_times': 'Eine oder mehrere Zeiten auswÃ¤hlen',
    'select_schedule': 'Zeitplan auswÃ¤hlen',
    'record': 'Datensatz',
    'no_records': 'Keine EintrÃ¤ge',
    'guest_mode': 'Gastmodus',
    'get_copy': 'Kopie erhalten',
    'create_copy': 'Kopie erstellen',
    'select_all': 'Alle auswÃ¤hlen',
    'share_selected': 'AusgewÃ¤hlte teilen',
    'no_selection': 'Keine Elemente ausgewÃ¤hlt',
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
    'back_image': 'RÃ¼ckseite',
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
    'full_record': 'VollstÃ¤ndiger Datensatz',
    'share_record': 'Datensatz teilen',
    'sign_up': 'Registrieren',
    'language': 'Sprache',
    'select_medication': 'Medikament auswÃ¤hlen',
    'select_time': 'Zeit auswÃ¤hlen',
    'select_date': 'Datum auswÃ¤hlen',
    'required_field': 'Dieses Feld ist erforderlich',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'Bitte anmelden',
    'please_fill_all': 'Bitte alle Felder ausfÃ¼llen',
    'login_failed': 'Anmeldung fehlgeschlagen',
    'signup_failed': 'Registrierung fehlgeschlagen',
    'delete_confirm_title': 'LÃ¶schen?',
    'delete_confirm_msg': 'MÃ¶chten Sie diesen Datensatz wirklich lÃ¶schen?',
    'cancel': 'Abbrechen',
    'please_sign_in': 'Bitte anmelden',
    'account_created_success': 'Konto erfolgreich erstellt! Bitte anmelden.',
    'operation_failed': 'Vorgang fehlgeschlagen',
    'select_front_image': 'Vorderes Bild auswÃ¤hlen',
    'select_back_image': 'Hinteres Bild auswÃ¤hlen',
    'upload_image': 'Bild hochladen',
    'uploaded': 'Hochgeladen',
    'insurance_company_name': 'Name der Versicherungsgesellschaft',
    'patient_id': 'Patienten-ID',
    'insurance_card_front': 'Versicherungskarte - Vorderseite',
    'insurance_card_back': 'Versicherungskarte - RÃ¼ckseite',
    'no_image_selected': 'Kein Bild ausgewÃ¤hlt',
    'upload_front_card': 'Vorderseite der Karte hochladen',
    'upload_back_card': 'RÃ¼ckseite der Karte hochladen',
    'add_data': 'Daten hinzufÃ¼gen',
    'please_enter_insurance_company':
        'Bitte Namen der Versicherungsgesellschaft eingeben',
    'please_enter_patient_id': 'Bitte Patienten-ID eingeben',
    'please_upload_both_cards': 'Bitte beide Karten hochladen',
    'success': 'Erfolg',
    'upload_photo': 'Foto hochladen',
    'select_photo': 'Foto auswÃ¤hlen',
    'photo_uploaded': 'Foto hochgeladen',
    'please_upload_photo': 'Bitte ein Foto hochladen',
    'share_app': 'App teilen',
    'share_app_message': 'SANA - Ihre App zur Gesundheitsverwaltung!',
    'opening_payment': 'Zahlungsseite wird geÃ¶ffnet...',
    'payment_error': 'Zahlungsfehler',
    'medicine_photo': 'Medikamentenfoto',
    'no_medicine_photo': 'Kein Foto ausgewÃ¤hlt',
    'upload_medicine_photo': 'Medikamentenfoto hochladen',
    'change_medicine_photo': 'Medikamentenfoto Ã¤ndern',
    'select_reminder_times': 'Erinnerungszeiten auswÃ¤hlen',
    'selected': 'AusgewÃ¤hlt',
    'medication_schedule': 'Medikamenten-Zeitplan',
    'choose_schedule_repeat':
        'WÃ¤hlen Sie, wann diese Erinnerung wiederholt werden soll:',
    'repeat_daily_msg': 'Die Erinnerung wird tÃ¤glich wiederholt.',
    'select_calendar_date': 'Kalenderdatum auswÃ¤hlen',
    'date': 'Datum',
    'share_documents': 'Dokumente teilen',
    'manual_title': 'SANA Medizinisches Taschenbuch',
    'manual_content':
        '1. Verwalten Sie Ihre Gesundheitsdaten sicher im Web und greifen Sie jederzeit, Ã¼berall und von jedem GerÃ¤t auf Ihre Daten zu.\n2. Verfolgen Sie tÃ¤gliche Medikamente und Dosierungen.\n3. Speichern Sie Kontaktdaten Ihrer Ã„rzte und Fachgebiete.\n4. Speichern Sie Apotheken mit Adresse und Telefonnummer.\n5. Stellen Sie Erinnerungen fÃ¼r die Medikamenteneinnahme mit Alarm ein.\n6. Speichern Sie medizinische Dokumente und Berichte mit Fotos.\n7. Speichern Sie Vorder- und RÃ¼ckseite Ihrer Versicherungskarten.\n8. WÃ¤hlen Sie DatensÃ¤tze aus und teilen Sie diese jederzeit mit Ihrem Arzt.\n9. Installieren Sie die App auf Ihrem GerÃ¤t, um alle Funktionen zu nutzen und Medikamentenalarme zu aktivieren.\n10. Erhalten Sie Ihre eigene private, persÃ¶nliche Kopie, die fÃ¼r niemand anderen sichtbar ist.\n11. Um SANA auf Ihrem GerÃ¤t zu installieren, Ã¶ffnen Sie die App im Browser Ihres Telefons: Ã–ffnen Sie unter Android Chrome das MenÃ¼ â‹® und wÃ¤hlen Sie â€žApp installierenâ€œ oder â€žZum Startbildschirm hinzufÃ¼genâ€œ; tippen Sie unter iPhone Safari auf Teilen und wÃ¤hlen Sie â€žZum Home-Bildschirmâ€œ.',
    'taken': 'Eingenommen',
    'alarm': 'Medikamenten-Alarm',
    'daily_reminders': 'TÃ¤gliche Erinnerungen',
    'calendar_reminders': 'Geplante Erinnerungen',
  },
  'tr': {
    'add': 'Ekle',
    'save': 'Kaydet',
    'delete': 'Sil',
    'view': 'GÃ¶rÃ¼ntÃ¼le',
    'close': 'Kapat',
    'share': 'PaylaÅŸ',
    'install_app': 'UygulamayÄ± yÃ¼kle',
    'help': 'YardÄ±m',
    'call': 'Ara',
    'chat': 'Sohbet',
    'write_comment': 'Yorumunuzu yazÄ±n...',
    'send': 'GÃ¶nder',
    'comment_sent': 'Yorum baÅŸarÄ±yla gÃ¶nderildi',
    'chat_date': 'Sohbet / Tarih',
    'joining_date': 'KatÄ±lÄ±m Tarihi',
    'last_login': 'Son GiriÅŸ',
    'login': 'GiriÅŸ Yap',
    'logout': 'Ã‡Ä±kÄ±ÅŸ Yap',
    'admin': 'YÃ¶netici',
    'medications': 'Ä°laÃ§lar',
    'doctors': 'Doktorlar',
    'pharmacies': 'Eczaneler',
    'reminders': 'HatÄ±rlatÄ±cÄ±lar',
    'documents': 'Belgeler',
    'insurance_cards': 'Sigorta KartlarÄ±',
    'name': 'Ad',
    'dosage': 'Doz',
    'notes': 'Notlar',
    'quantity': 'Stok',
    'description': 'AÃ§Ä±klama',
    'specialty': 'UzmanlÄ±k',
    'phone': 'Telefon',
    'address': 'Adres',
    'email': 'E-posta veya kullanÄ±cÄ± adÄ±',
    'show_password': 'Åžifreyi gÃ¶ster',
    'password': 'Åžifre',
    'password_6_digit': '6 hane',
    'sign_in': 'GiriÅŸ Yap',
    'new_user': 'Yeni KullanÄ±cÄ±',
    'register': 'KayÄ±t Ol',
    'create_account': 'Hesap OluÅŸtur',
    'already_account': 'Zaten hesabÄ±nÄ±z var mÄ±?',
    'location': 'Konum',
    'photo': 'FotoÄŸraf',
    'front_photo': 'Ã–n FotoÄŸraf',
    'back_photo': 'Arka FotoÄŸraf',
    'reminder_time': 'HatÄ±rlatma Saati',
    'reminder_date': 'HatÄ±rlatma Tarihi',
    'schedule_type': 'Program',
    'daily': 'GÃ¼nlÃ¼k',
    'calendar': 'Takvim',
    'select_times': 'Bir veya daha fazla saat seÃ§in',
    'select_schedule': 'Program seÃ§',
    'record': 'KayÄ±t',
    'no_records': 'KayÄ±t yok',
    'guest_mode': 'Misafir Modu',
    'get_copy': 'KopyanÄ± Al',
    'create_copy': 'KopyanÄ± OluÅŸtur',
    'select_all': 'TÃ¼mÃ¼nÃ¼ SeÃ§',
    'share_selected': 'SeÃ§ilenleri PaylaÅŸ',
    'no_selection': 'SeÃ§im yok',
    'admin_panel': 'YÃ¶netici Paneli',
    'users': 'KullanÄ±cÄ±lar',
    'activate': 'EtkinleÅŸtir',
    'deactivate': 'Devre DÄ±ÅŸÄ± BÄ±rak',
    'status': 'Durum',
    'role': 'Rol',
    'active_user': 'Aktif KullanÄ±cÄ±',
    'inactive_guest': 'Pasif KullanÄ±cÄ±',
    'expired':
        'LÃ¼tfen kendi kopyanÄ±zÄ± alÄ±n ve etkinleÅŸtirilene kadar 48 saat bekleyin.',
    'pending_activation':
        'LÃ¼tfen kendi kopyanÄ±zÄ± alÄ±n ve etkinleÅŸtirilene kadar 48 saat bekleyin.',
    'paid': 'Ã–dendi',
    'expiry_date': 'Son Kullanma Tarihi',
    'provider_name': 'SaÄŸlayÄ±cÄ± AdÄ±',
    'front_image': 'Ã–n GÃ¶rsel',
    'back_image': 'Arka GÃ¶rsel',
    'file_url': 'Dosya URLâ€™si',
    'category': 'Kategori',
    'title': 'BaÅŸlÄ±k',
    'policy': 'PoliÃ§e',
    'policy_number': 'PoliÃ§e NumarasÄ±',
    'provider': 'SaÄŸlayÄ±cÄ±',
    'expiry': 'Son Kullanma',
    'specialist': 'Uzman',
    'guest': 'Misafir Modu',
    'account': 'Hesap',
    'guest_data': 'Misafir Verileri',
    'full_record': 'Tam KayÄ±t',
    'share_record': 'KaydÄ± PaylaÅŸ',
    'sign_up': 'KayÄ±t Ol',
    'language': 'Dil',
    'select_medication': 'Ä°laÃ§ SeÃ§',
    'select_time': 'Saat SeÃ§',
    'select_date': 'Tarih SeÃ§',
    'required_field': 'Bu alan zorunludur',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'LÃ¼tfen giriÅŸ yapÄ±n',
    'please_fill_all': 'LÃ¼tfen tÃ¼m alanlarÄ± doldurun',
    'login_failed': 'GiriÅŸ baÅŸarÄ±sÄ±z',
    'signup_failed': 'KayÄ±t baÅŸarÄ±sÄ±z',
    'delete_confirm_title': 'Silinsin mi?',
    'delete_confirm_msg': 'Bu kaydÄ± silmek istediÄŸinizden emin misiniz?',
    'cancel': 'Ä°ptal',
    'please_sign_in': 'LÃ¼tfen giriÅŸ yapÄ±n',
    'account_created_success':
        'Hesap baÅŸarÄ±yla oluÅŸturuldu! LÃ¼tfen giriÅŸ yapÄ±n.',
    'operation_failed': 'Ä°ÅŸlem baÅŸarÄ±sÄ±z',
    'select_front_image': 'Ã–n gÃ¶rseli seÃ§',
    'select_back_image': 'Arka gÃ¶rseli seÃ§',
    'upload_image': 'GÃ¶rsel yÃ¼kle',
    'uploaded': 'YÃ¼klendi',
    'insurance_company_name': 'Sigorta ÅŸirketi adÄ±',
    'patient_id': 'Hasta kimliÄŸi',
    'insurance_card_front': 'Sigorta kartÄ± - Ã–n',
    'insurance_card_back': 'Sigorta kartÄ± - Arka',
    'no_image_selected': 'GÃ¶rsel seÃ§ilmedi',
    'upload_front_card': 'Ã–n kartÄ± yÃ¼kle',
    'upload_back_card': 'Arka kartÄ± yÃ¼kle',
    'add_data': 'Veri ekle',
    'please_enter_insurance_company': 'LÃ¼tfen sigorta ÅŸirketinin adÄ±nÄ± girin',
    'please_enter_patient_id': 'LÃ¼tfen hasta kimliÄŸini girin',
    'please_upload_both_cards': 'LÃ¼tfen her iki kartÄ± da yÃ¼kleyin',
    'success': 'BaÅŸarÄ±lÄ±',
    'upload_photo': 'FotoÄŸraf yÃ¼kle',
    'select_photo': 'FotoÄŸraf seÃ§',
    'photo_uploaded': 'FotoÄŸraf yÃ¼klendi',
    'please_upload_photo': 'LÃ¼tfen bir fotoÄŸraf yÃ¼kleyin',
    'share_app': 'UygulamayÄ± paylaÅŸ',
    'share_app_message': 'SANA - saÄŸlÄ±k yÃ¶netimi uygulamanÄ±z!',
    'opening_payment': 'Ã–deme sayfasÄ± aÃ§Ä±lÄ±yor...',
    'payment_error': 'Ã–deme hatasÄ±',
    'medicine_photo': 'Ä°laÃ§ fotoÄŸrafÄ±',
    'no_medicine_photo': 'Ä°laÃ§ fotoÄŸrafÄ± seÃ§ilmedi',
    'upload_medicine_photo': 'Ä°laÃ§ fotoÄŸrafÄ± yÃ¼kle',
    'change_medicine_photo': 'Ä°laÃ§ fotoÄŸrafÄ±nÄ± deÄŸiÅŸtir',
    'select_reminder_times': 'HatÄ±rlatma saatlerini seÃ§in',
    'selected': 'SeÃ§ilen',
    'medication_schedule': 'Ä°laÃ§ programÄ±',
    'choose_schedule_repeat':
        'Bu hatÄ±rlatmanÄ±n ne zaman tekrarlanacaÄŸÄ±nÄ± seÃ§in:',
    'repeat_daily_msg': 'HatÄ±rlatma her gÃ¼n tekrarlanacak.',
    'select_calendar_date': 'Takvim tarihini seÃ§in',
    'date': 'Tarih',
    'share_documents': 'Belgeleri PaylaÅŸ',
    'manual_title': 'SANA Cep SaÄŸlÄ±k Rehberi',
    'manual_content':
        '1. SaÄŸlÄ±k kayÄ±tlarÄ±nÄ±zÄ± web Ã¼zerinde gÃ¼venle yÃ¶netin ve verilerinize her zaman, her yerden ve herhangi bir cihazdan eriÅŸin.\n2. GÃ¼nlÃ¼k ilaÃ§larÄ±nÄ±zÄ± ve dozajlarÄ±nÄ±zÄ± takip edin.\n3. Doktor iletiÅŸim ve uzmanlÄ±k bilgilerini kaydedin.\n4. Eczaneleri telefon ve adres bilgileriyle saklayÄ±n.\n5. UyarÄ±larla birlikte Ã§oklu saat seÃ§enekleriyle ilaÃ§ hatÄ±rlatÄ±cÄ±larÄ± kurun.\n6. TÄ±bbi rapor ve belgelerinizi fotoÄŸraflarla kaydedin.\n7. Sigorta kartlarÄ±nÄ±zÄ±n Ã¶n ve arka fotoÄŸraflarÄ±nÄ± saklayÄ±n.\n8. KayÄ±tlarÄ±nÄ±zÄ± seÃ§erek dilediÄŸiniz zaman doktorunuzla paylaÅŸÄ±n.\n9. TÃ¼m Ã¶zellikleri kullanmak ve ilaÃ§ alarmlarÄ±nÄ± etkinleÅŸtirmek iÃ§in uygulamayÄ± cihazÄ±nÄ±za yÃ¼kleyin.\n10. BaÅŸka hiÃ§ kimsenin gÃ¶remeyeceÄŸi, size Ã¶zel ve baÄŸÄ±msÄ±z bir kopyanÄ±zÄ± edinin.\n11. SANAâ€™yÄ± cihazÄ±nÄ±za yÃ¼klemek iÃ§in uygulamayÄ± telefonunuzun tarayÄ±cÄ±sÄ±nda aÃ§Ä±n: Android Chromeâ€™da â‹® menÃ¼sÃ¼nÃ¼ aÃ§Ä±p â€œUygulamayÄ± yÃ¼kleâ€ veya â€œAna ekrana ekleâ€ seÃ§eneÄŸini seÃ§in; iPhone Safariâ€™de PaylaÅŸâ€™a dokunup â€œAna Ekrana Ekleâ€ seÃ§eneÄŸini seÃ§in.',
    'taken': 'AlÄ±ndÄ±',
    'alarm': 'Ä°laÃ§ AlarmÄ±',
    'daily_reminders': 'GÃ¼nlÃ¼k HatÄ±rlatÄ±cÄ±lar',
    'calendar_reminders': 'PlanlanmÄ±ÅŸ HatÄ±rlatÄ±cÄ±lar',
  },
  'hi': {
    'add': 'à¤œà¥‹à¤¡à¤¼à¥‡à¤‚',
    'save': 'à¤¸à¤¹à¥‡à¤œà¥‡à¤‚',
    'delete': 'à¤¹à¤Ÿà¤¾à¤à¤',
    'view': 'à¤¦à¥‡à¤–à¥‡à¤‚',
    'close': 'à¤¬à¤‚à¤¦ à¤•à¤°à¥‡à¤‚',
    'share': 'à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚',
    'install_app': 'à¤à¤ª à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
    'help': 'à¤®à¤¦à¤¦',
    'call': 'à¤•à¥‰à¤² à¤•à¤°à¥‡à¤‚',
    'chat': 'à¤šà¥ˆà¤Ÿ',
    'write_comment': 'à¤…à¤ªà¤¨à¥€ à¤Ÿà¤¿à¤ªà¥à¤ªà¤£à¥€ à¤²à¤¿à¤–à¥‡à¤‚...',
    'send': 'à¤­à¥‡à¤œà¥‡à¤‚',
    'comment_sent': 'à¤Ÿà¤¿à¤ªà¥à¤ªà¤£à¥€ à¤¸à¤«à¤²à¤¤à¤¾à¤ªà¥‚à¤°à¥à¤µà¤• à¤­à¥‡à¤œà¥€ à¤—à¤ˆ',
    'chat_date': 'à¤šà¥ˆà¤Ÿ / à¤¦à¤¿à¤¨à¤¾à¤‚à¤•',
    'joining_date': 'à¤¶à¤¾à¤®à¤¿à¤² à¤¹à¥‹à¤¨à¥‡ à¤•à¥€ à¤¤à¤¿à¤¥à¤¿',
    'last_login': 'à¤…à¤‚à¤¤à¤¿à¤® à¤²à¥‰à¤—à¤¿à¤¨',
    'login': 'à¤²à¥‰à¤— à¤‡à¤¨',
    'logout': 'à¤²à¥‰à¤— à¤†à¤‰à¤Ÿ',
    'admin': 'à¤µà¥à¤¯à¤µà¤¸à¥à¤¥à¤¾à¤ªà¤•',
    'medications': 'à¤¦à¤µà¤¾à¤‡à¤¯à¤¾à¤',
    'doctors': 'à¤¡à¥‰à¤•à¥à¤Ÿà¤°',
    'pharmacies': 'à¤«à¤¾à¤°à¥à¤®à¥‡à¤¸à¥€',
    'reminders': 'à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤°',
    'documents': 'à¤¦à¤¸à¥à¤¤à¤¾à¤µà¥‡à¤œà¤¼',
    'insurance_cards': 'à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡',
    'name': 'à¤¨à¤¾à¤®',
    'dosage': 'à¤–à¥à¤°à¤¾à¤•',
    'notes': 'à¤Ÿà¤¿à¤ªà¥à¤ªà¤£à¤¿à¤¯à¤¾à¤',
    'quantity': 'à¤¸à¥à¤Ÿà¥‰à¤•',
    'description': 'à¤µà¤¿à¤µà¤°à¤£',
    'specialty': 'à¤µà¤¿à¤¶à¥‡à¤·à¤¤à¤¾',
    'phone': 'à¤«à¤¼à¥‹à¤¨',
    'address': 'à¤ªà¤¤à¤¾',
    'email': 'à¤ˆà¤®à¥‡à¤² à¤¯à¤¾ à¤‰à¤ªà¤¯à¥‹à¤—à¤•à¤°à¥à¤¤à¤¾ à¤¨à¤¾à¤®',
    'show_password': 'à¤ªà¤¾à¤¸à¤µà¤°à¥à¤¡ à¤¦à¤¿à¤–à¤¾à¤à¤',
    'password': 'à¤ªà¤¾à¤¸à¤µà¤°à¥à¤¡',
    'password_6_digit': '6 à¤…à¤‚à¤•',
    'sign_in': 'à¤¸à¤¾à¤‡à¤¨ à¤‡à¤¨',
    'new_user': 'à¤¨à¤¯à¤¾ à¤‰à¤ªà¤¯à¥‹à¤—à¤•à¤°à¥à¤¤à¤¾',
    'register': 'à¤ªà¤‚à¤œà¥€à¤•à¤°à¤£',
    'create_account': 'à¤–à¤¾à¤¤à¤¾ à¤¬à¤¨à¤¾à¤à¤',
    'already_account': 'à¤•à¥à¤¯à¤¾ à¤†à¤ªà¤•à¥‡ à¤ªà¤¾à¤¸ à¤ªà¤¹à¤²à¥‡ à¤¸à¥‡ à¤–à¤¾à¤¤à¤¾ à¤¹à¥ˆ?',
    'location': 'à¤¸à¥à¤¥à¤¾à¤¨',
    'photo': 'à¤«à¤¼à¥‹à¤Ÿà¥‹',
    'front_photo': 'à¤¸à¤¾à¤®à¤¨à¥‡ à¤•à¥€ à¤«à¤¼à¥‹à¤Ÿà¥‹',
    'back_photo': 'à¤ªà¥€à¤›à¥‡ à¤•à¥€ à¤«à¤¼à¥‹à¤Ÿà¥‹',
    'reminder_time': 'à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤° à¤¸à¤®à¤¯',
    'reminder_date': 'à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤° à¤¤à¤¾à¤°à¥€à¤–',
    'schedule_type': 'à¤¸à¤®à¤¯-à¤¸à¤¾à¤°à¤£à¥€',
    'daily': 'à¤¦à¥ˆà¤¨à¤¿à¤•',
    'calendar': 'à¤•à¥ˆà¤²à¥‡à¤‚à¤¡à¤°',
    'select_times': 'à¤à¤• à¤¯à¤¾ à¤…à¤§à¤¿à¤• à¤¸à¤®à¤¯ à¤šà¥à¤¨à¥‡à¤‚',
    'select_schedule': 'à¤¸à¤®à¤¯-à¤¸à¤¾à¤°à¤£à¥€ à¤šà¥à¤¨à¥‡à¤‚',
    'record': 'à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡',
    'no_records': 'à¤•à¥‹à¤ˆ à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡ à¤¨à¤¹à¥€à¤‚',
    'guest_mode': 'à¤…à¤¤à¤¿à¤¥à¤¿ à¤®à¥‹à¤¡',
    'get_copy': 'à¤…à¤ªà¤¨à¥€ à¤•à¥‰à¤ªà¥€ à¤ªà¤¾à¤à¤',
    'create_copy': 'à¤…à¤ªà¤¨à¥€ à¤•à¥‰à¤ªà¥€ à¤¬à¤¨à¤¾à¤à¤',
    'select_all': 'à¤¸à¤­à¥€ à¤šà¥à¤¨à¥‡à¤‚',
    'share_selected': 'à¤šà¤¯à¤¨à¤¿à¤¤ à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚',
    'no_selection': 'à¤•à¥‹à¤ˆ à¤†à¤‡à¤Ÿà¤® à¤šà¤¯à¤¨à¤¿à¤¤ à¤¨à¤¹à¥€à¤‚',
    'admin_panel': 'à¤µà¥à¤¯à¤µà¤¸à¥à¤¥à¤¾à¤ªà¤• à¤ªà¥ˆà¤¨à¤²',
    'users': 'à¤‰à¤ªà¤¯à¥‹à¤—à¤•à¤°à¥à¤¤à¤¾',
    'activate': 'à¤¸à¤•à¥à¤°à¤¿à¤¯ à¤•à¤°à¥‡à¤‚',
    'deactivate': 'à¤¨à¤¿à¤·à¥à¤•à¥à¤°à¤¿à¤¯ à¤•à¤°à¥‡à¤‚',
    'status': 'à¤¸à¥à¤¥à¤¿à¤¤à¤¿',
    'role': 'à¤­à¥‚à¤®à¤¿à¤•à¤¾',
    'active_user': 'à¤¸à¤•à¥à¤°à¤¿à¤¯ à¤‰à¤ªà¤¯à¥‹à¤—à¤•à¤°à¥à¤¤à¤¾',
    'inactive_guest': 'à¤¨à¤¿à¤·à¥à¤•à¥à¤°à¤¿à¤¯ à¤‰à¤ªà¤¯à¥‹à¤—à¤•à¤°à¥à¤¤à¤¾',
    'expired':
        'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤…à¤ªà¤¨à¥€ à¤ªà¥à¤°à¤¤à¤¿ à¤ªà¥à¤°à¤¾à¤ªà¥à¤¤ à¤•à¤°à¥‡à¤‚ à¤”à¤° à¤¸à¤•à¥à¤°à¤¿à¤¯ à¤¹à¥‹à¤¨à¥‡ à¤¤à¤• 48 à¤˜à¤‚à¤Ÿà¥‡ à¤ªà¥à¤°à¤¤à¥€à¤•à¥à¤·à¤¾ à¤•à¤°à¥‡à¤‚à¥¤',
    'pending_activation':
        'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤…à¤ªà¤¨à¥€ à¤ªà¥à¤°à¤¤à¤¿ à¤ªà¥à¤°à¤¾à¤ªà¥à¤¤ à¤•à¤°à¥‡à¤‚ à¤”à¤° à¤¸à¤•à¥à¤°à¤¿à¤¯ à¤¹à¥‹à¤¨à¥‡ à¤¤à¤• 48 à¤˜à¤‚à¤Ÿà¥‡ à¤ªà¥à¤°à¤¤à¥€à¤•à¥à¤·à¤¾ à¤•à¤°à¥‡à¤‚à¥¤',
    'paid': 'à¤­à¥à¤—à¤¤à¤¾à¤¨ à¤•à¤¿à¤¯à¤¾ à¤—à¤¯à¤¾',
    'expiry_date': 'à¤¸à¤®à¤¾à¤ªà¥à¤¤à¤¿ à¤¤à¤¿à¤¥à¤¿',
    'provider_name': 'à¤ªà¥à¤°à¤¦à¤¾à¤¤à¤¾ à¤•à¤¾ à¤¨à¤¾à¤®',
    'front_image': 'à¤¸à¤¾à¤®à¤¨à¥‡ à¤•à¥€ à¤›à¤µà¤¿',
    'back_image': 'à¤ªà¥€à¤›à¥‡ à¤•à¥€ à¤›à¤µà¤¿',
    'file_url': 'à¤«à¤¼à¤¾à¤‡à¤² URL',
    'category': 'à¤¶à¥à¤°à¥‡à¤£à¥€',
    'title': 'à¤¶à¥€à¤°à¥à¤·à¤•',
    'policy': 'à¤ªà¥‰à¤²à¤¿à¤¸à¥€',
    'policy_number': 'à¤ªà¥‰à¤²à¤¿à¤¸à¥€ à¤¸à¤‚à¤–à¥à¤¯à¤¾',
    'provider': 'à¤ªà¥à¤°à¤¦à¤¾à¤¤à¤¾',
    'expiry': 'à¤¸à¤®à¤¾à¤ªà¥à¤¤à¤¿',
    'specialist': 'à¤µà¤¿à¤¶à¥‡à¤·à¤œà¥à¤ž',
    'guest': 'à¤…à¤¤à¤¿à¤¥à¤¿ à¤®à¥‹à¤¡',
    'account': 'à¤–à¤¾à¤¤à¤¾',
    'guest_data': 'à¤…à¤¤à¤¿à¤¥à¤¿ à¤¡à¥‡à¤Ÿà¤¾',
    'full_record': 'à¤ªà¥‚à¤°à¤¾ à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡',
    'share_record': 'à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡ à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚',
    'sign_up': 'à¤¸à¤¾à¤‡à¤¨ à¤…à¤ª',
    'language': 'à¤­à¤¾à¤·à¤¾',
    'select_medication': 'à¤¦à¤µà¤¾ à¤šà¥à¤¨à¥‡à¤‚',
    'select_time': 'à¤¸à¤®à¤¯ à¤šà¥à¤¨à¥‡à¤‚',
    'select_date': 'à¤¤à¤¾à¤°à¥€à¤– à¤šà¥à¤¨à¥‡à¤‚',
    'required_field': 'à¤¯à¤¹ à¤«à¤¼à¥€à¤²à¥à¤¡ à¤†à¤µà¤¶à¥à¤¯à¤• à¤¹à¥ˆ',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤²à¥‰à¤— à¤‡à¤¨ à¤•à¤°à¥‡à¤‚',
    'please_fill_all': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤¸à¤­à¥€ à¤«à¤¼à¥€à¤²à¥à¤¡ à¤­à¤°à¥‡à¤‚',
    'login_failed': 'à¤²à¥‰à¤— à¤‡à¤¨ à¤µà¤¿à¤«à¤²',
    'signup_failed': 'à¤¸à¤¾à¤‡à¤¨ à¤…à¤ª à¤µà¤¿à¤«à¤²',
    'delete_confirm_title': 'à¤¹à¤Ÿà¤¾à¤à¤?',
    'delete_confirm_msg': 'à¤•à¥à¤¯à¤¾ à¤†à¤ª à¤µà¤¾à¤•à¤ˆ à¤‡à¤¸ à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡ à¤•à¥‹ à¤¹à¤Ÿà¤¾à¤¨à¤¾ à¤šà¤¾à¤¹à¤¤à¥‡ à¤¹à¥ˆà¤‚?',
    'cancel': 'à¤°à¤¦à¥à¤¦ à¤•à¤°à¥‡à¤‚',
    'please_sign_in': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤¸à¤¾à¤‡à¤¨ à¤‡à¤¨ à¤•à¤°à¥‡à¤‚',
    'account_created_success':
        'à¤–à¤¾à¤¤à¤¾ à¤¸à¤«à¤²à¤¤à¤¾à¤ªà¥‚à¤°à¥à¤µà¤• à¤¬à¤¨à¤¾à¤¯à¤¾ à¤—à¤¯à¤¾! à¤•à¥ƒà¤ªà¤¯à¤¾ à¤¸à¤¾à¤‡à¤¨ à¤‡à¤¨ à¤•à¤°à¥‡à¤‚à¥¤',
    'operation_failed': 'à¤‘à¤ªà¤°à¥‡à¤¶à¤¨ à¤µà¤¿à¤«à¤²',
    'select_front_image': 'à¤¸à¤¾à¤®à¤¨à¥‡ à¤•à¥€ à¤›à¤µà¤¿ à¤šà¥à¤¨à¥‡à¤‚',
    'select_back_image': 'à¤ªà¥€à¤›à¥‡ à¤•à¥€ à¤›à¤µà¤¿ à¤šà¥à¤¨à¥‡à¤‚',
    'upload_image': 'à¤›à¤µà¤¿ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'uploaded': 'à¤…à¤ªà¤²à¥‹à¤¡ à¤¹à¥‹ à¤—à¤¯à¤¾',
    'insurance_company_name': 'à¤¬à¥€à¤®à¤¾ à¤•à¤‚à¤ªà¤¨à¥€ à¤•à¤¾ à¤¨à¤¾à¤®',
    'patient_id': 'à¤®à¤°à¥€à¤œà¤¼ ID',
    'insurance_card_front': 'à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡ - à¤¸à¤¾à¤®à¤¨à¥‡',
    'insurance_card_back': 'à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡ - à¤ªà¥€à¤›à¥‡',
    'no_image_selected': 'à¤•à¥‹à¤ˆ à¤›à¤µà¤¿ à¤šà¤¯à¤¨à¤¿à¤¤ à¤¨à¤¹à¥€à¤‚',
    'upload_front_card': 'à¤¸à¤¾à¤®à¤¨à¥‡ à¤•à¤¾ à¤•à¤¾à¤°à¥à¤¡ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'upload_back_card': 'à¤ªà¥€à¤›à¥‡ à¤•à¤¾ à¤•à¤¾à¤°à¥à¤¡ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'add_data': 'à¤¡à¥‡à¤Ÿà¤¾ à¤œà¥‹à¤¡à¤¼à¥‡à¤‚',
    'please_enter_insurance_company': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤¬à¥€à¤®à¤¾ à¤•à¤‚à¤ªà¤¨à¥€ à¤•à¤¾ à¤¨à¤¾à¤® à¤¦à¤°à¥à¤œ à¤•à¤°à¥‡à¤‚',
    'please_enter_patient_id': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤®à¤°à¥€à¤œà¤¼ ID à¤¦à¤°à¥à¤œ à¤•à¤°à¥‡à¤‚',
    'please_upload_both_cards': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤¦à¥‹à¤¨à¥‹à¤‚ à¤•à¤¾à¤°à¥à¤¡ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'success': 'à¤¸à¤«à¤²',
    'upload_photo': 'à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'select_photo': 'à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤šà¥à¤¨à¥‡à¤‚',
    'photo_uploaded': 'à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤…à¤ªà¤²à¥‹à¤¡ à¤¹à¥‹ à¤—à¤ˆ',
    'please_upload_photo': 'à¤•à¥ƒà¤ªà¤¯à¤¾ à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'share_app': 'à¤à¤ª à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚',
    'share_app_message': 'SANA - à¤†à¤ªà¤•à¤¾ à¤¸à¥à¤µà¤¾à¤¸à¥à¤¥à¥à¤¯ à¤ªà¥à¤°à¤¬à¤‚à¤§à¤¨ à¤à¤ª!',
    'opening_payment': 'à¤­à¥à¤—à¤¤à¤¾à¤¨ à¤ªà¥ƒà¤·à¥à¤  à¤–à¥‹à¤² à¤°à¤¹à¤¾ à¤¹à¥ˆ...',
    'payment_error': 'à¤­à¥à¤—à¤¤à¤¾à¤¨ à¤¤à¥à¤°à¥à¤Ÿà¤¿',
    'medicine_photo': 'à¤¦à¤µà¤¾ à¤•à¥€ à¤«à¤¼à¥‹à¤Ÿà¥‹',
    'no_medicine_photo': 'à¤•à¥‹à¤ˆ à¤¦à¤µà¤¾ à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤šà¤¯à¤¨à¤¿à¤¤ à¤¨à¤¹à¥€à¤‚',
    'upload_medicine_photo': 'à¤¦à¤µà¤¾ à¤•à¥€ à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤…à¤ªà¤²à¥‹à¤¡ à¤•à¤°à¥‡à¤‚',
    'change_medicine_photo': 'à¤¦à¤µà¤¾ à¤•à¥€ à¤«à¤¼à¥‹à¤Ÿà¥‹ à¤¬à¤¦à¤²à¥‡à¤‚',
    'select_reminder_times': 'à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤° à¤¸à¤®à¤¯ à¤šà¥à¤¨à¥‡à¤‚',
    'selected': 'à¤šà¤¯à¤¨à¤¿à¤¤',
    'medication_schedule': 'à¤¦à¤µà¤¾ à¤¸à¤®à¤¯-à¤¸à¤¾à¤°à¤£à¥€',
    'choose_schedule_repeat': 'à¤šà¥à¤¨à¥‡à¤‚ à¤•à¤¿ à¤¯à¤¹ à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤° à¤•à¤¬ à¤¦à¥‹à¤¹à¤°à¤¾à¤¯à¤¾ à¤œà¤¾à¤¨à¤¾ à¤šà¤¾à¤¹à¤¿à¤:',
    'repeat_daily_msg': 'à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤° à¤¹à¤° à¤¦à¤¿à¤¨ à¤¦à¥‹à¤¹à¤°à¤¾à¤¯à¤¾ à¤œà¤¾à¤à¤—à¤¾à¥¤',
    'select_calendar_date': 'à¤•à¥ˆà¤²à¥‡à¤‚à¤¡à¤° à¤¤à¤¾à¤°à¥€à¤– à¤šà¥à¤¨à¥‡à¤‚',
    'date': 'à¤¤à¤¾à¤°à¥€à¤–',
    'share_documents': 'à¤¦à¤¸à¥à¤¤à¤¾à¤µà¥‡à¤œà¤¼ à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚',
    'manual_title': 'à¤¸à¤¾à¤¨à¤¾ à¤®à¥‡à¤¡à¤¿à¤•à¤² à¤ªà¥‰à¤•à¥‡à¤Ÿ à¤¬à¥à¤•',
    'manual_content':
        '1. à¤µà¥‡à¤¬ à¤ªà¤° à¤…à¤ªà¤¨à¥‡ à¤¸à¥à¤µà¤¾à¤¸à¥à¤¥à¥à¤¯ à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡ à¤•à¥‹ à¤¸à¥à¤°à¤•à¥à¤·à¤¿à¤¤ à¤°à¥‚à¤ª à¤¸à¥‡ à¤ªà¥à¤°à¤¬à¤‚à¤§à¤¿à¤¤ à¤•à¤°à¥‡à¤‚ à¤”à¤° à¤•à¤¿à¤¸à¥€ à¤­à¥€ à¤¸à¤®à¤¯, à¤•à¤¹à¥€à¤‚ à¤¸à¥‡ à¤­à¥€ à¤”à¤° à¤•à¤¿à¤¸à¥€ à¤­à¥€ à¤¡à¤¿à¤µà¤¾à¤‡à¤¸ à¤¸à¥‡ à¤…à¤ªà¤¨à¥‡ à¤¡à¥‡à¤Ÿà¤¾ à¤¤à¤• à¤ªà¤¹à¥à¤à¤šà¥‡à¤‚à¥¤\n2. à¤¦à¥ˆà¤¨à¤¿à¤• à¤¦à¤µà¤¾à¤‡à¤¯à¤¾à¤ à¤”à¤° à¤‰à¤¨à¤•à¥€ à¤–à¥à¤°à¤¾à¤• à¤†à¤¸à¤¾à¤¨à¥€ à¤¸à¥‡ à¤Ÿà¥à¤°à¥ˆà¤• à¤•à¤°à¥‡à¤‚à¥¤\n3. à¤…à¤ªà¤¨à¥‡ à¤¡à¥‰à¤•à¥à¤Ÿà¤°à¥‹à¤‚ à¤•à¥‡ à¤¸à¤‚à¤ªà¤°à¥à¤• à¤”à¤° à¤µà¤¿à¤¶à¥‡à¤·à¤¤à¤¾ à¤¨à¥‹à¤Ÿ à¤°à¤–à¥‡à¤‚à¥¤\n4. à¤…à¤ªà¤¨à¥€ à¤ªà¤¸à¤‚à¤¦à¥€à¤¦à¤¾ à¤«à¤¾à¤°à¥à¤®à¥‡à¤¸à¥€ à¤•à¤¾ à¤ªà¤¤à¤¾ à¤”à¤° à¤«à¥‹à¤¨ à¤¸à¥‡à¤µ à¤•à¤°à¥‡à¤‚à¥¤\n5. à¤…à¤²à¤°à¥à¤Ÿ à¤•à¥‡ à¤¸à¤¾à¤¥ à¤¦à¤µà¤¾ à¤²à¥‡à¤¨à¥‡ à¤•à¥‡ à¤²à¤¿à¤ à¤•à¤ˆ à¤¸à¤®à¤¯ à¤•à¥‡ à¤°à¤¿à¤®à¤¾à¤‡à¤‚à¤¡à¤° à¤¸à¥‡à¤Ÿ à¤•à¤°à¥‡à¤‚à¥¤\n6. à¤®à¥‡à¤¡à¤¿à¤•à¤² à¤¦à¤¸à¥à¤¤à¤¾à¤µà¥‡à¤œà¤¼ à¤”à¤° à¤°à¤¿à¤ªà¥‹à¤°à¥à¤Ÿ à¤«à¥‹à¤Ÿà¥‹ à¤•à¥‡ à¤¸à¤¾à¤¥ à¤°à¤–à¥‡à¤‚à¥¤\n7. à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡ à¤•à¥€ à¤†à¤—à¥‡ à¤”à¤° à¤ªà¥€à¤›à¥‡ à¤•à¥€ à¤«à¥‹à¤Ÿà¥‹ à¤¸à¥à¤°à¤•à¥à¤·à¤¿à¤¤ à¤°à¤–à¥‡à¤‚à¥¤\n8. à¤¡à¥‰à¤•à¥à¤Ÿà¤° à¤•à¥‡ à¤¸à¤¾à¤¥ à¤•à¤­à¥€ à¤­à¥€ à¤œà¤°à¥‚à¤°à¥€ à¤°à¤¿à¤•à¥‰à¤°à¥à¤¡ à¤šà¥à¤¨à¥‡à¤‚ à¤”à¤° à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚à¥¤\n9. à¤¸à¤­à¥€ à¤¸à¥à¤µà¤¿à¤§à¤¾à¤à¤ à¤ªà¥à¤°à¤¾à¤ªà¥à¤¤ à¤•à¤°à¤¨à¥‡ à¤”à¤° à¤¦à¤µà¤¾ à¤•à¥‡ à¤…à¤²à¤¾à¤°à¥à¤® à¤¸à¤•à¥à¤°à¤¿à¤¯ à¤•à¤°à¤¨à¥‡ à¤•à¥‡ à¤²à¤¿à¤ à¤…à¤ªà¤¨à¥‡ à¤¡à¤¿à¤µà¤¾à¤‡à¤¸ à¤ªà¤° à¤à¤ª à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚à¥¤\n10. à¤…à¤ªà¤¨à¥€ à¤¨à¤¿à¤œà¥€ à¤”à¤° à¤¸à¤®à¤°à¥à¤ªà¤¿à¤¤ à¤ªà¥à¤°à¤¤à¤¿ à¤ªà¥à¤°à¤¾à¤ªà¥à¤¤ à¤•à¤°à¥‡à¤‚, à¤œà¤¿à¤¸à¥‡ à¤•à¥‹à¤ˆ à¤…à¤¨à¥à¤¯ à¤µà¥à¤¯à¤•à¥à¤¤à¤¿ à¤¨à¤¹à¥€à¤‚ à¤¦à¥‡à¤– à¤¸à¤•à¤¤à¤¾à¥¤\n11. SANA à¤•à¥‹ à¤…à¤ªà¤¨à¥‡ à¤¡à¤¿à¤µà¤¾à¤‡à¤¸ à¤ªà¤° à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¤¨à¥‡ à¤•à¥‡ à¤²à¤¿à¤ à¤à¤ª à¤•à¥‹ à¤…à¤ªà¤¨à¥‡ à¤«à¤¼à¥‹à¤¨ à¤•à¥‡ à¤¬à¥à¤°à¤¾à¤‰à¤œà¤¼à¤° à¤®à¥‡à¤‚ à¤–à¥‹à¤²à¥‡à¤‚: Android Chrome à¤®à¥‡à¤‚ â‹® à¤®à¥‡à¤¨à¥‚ à¤–à¥‹à¤²à¤•à¤° "à¤à¤ª à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚" à¤¯à¤¾ "à¤¹à¥‹à¤® à¤¸à¥à¤•à¥à¤°à¥€à¤¨ à¤®à¥‡à¤‚ à¤œà¥‹à¤¡à¤¼à¥‡à¤‚" à¤šà¥à¤¨à¥‡à¤‚; iPhone Safari à¤®à¥‡à¤‚ à¤¶à¥‡à¤¯à¤° à¤¬à¤Ÿà¤¨ à¤¦à¤¬à¤¾à¤•à¤° "à¤¹à¥‹à¤® à¤¸à¥à¤•à¥à¤°à¥€à¤¨ à¤®à¥‡à¤‚ à¤œà¥‹à¤¡à¤¼à¥‡à¤‚" à¤šà¥à¤¨à¥‡à¤‚à¥¤',
    'taken': 'à¤¦à¤µà¤¾ à¤²à¥‡ à¤²à¥€',
    'alarm': 'à¤¦à¤µà¤¾ à¤•à¤¾ à¤…à¤²à¤¾à¤°à¥à¤®',
    'daily_reminders': 'à¤¦à¥ˆà¤¨à¤¿à¤• à¤…à¤¨à¥à¤¸à¥à¤®à¤¾à¤°à¤•',
    'calendar_reminders': 'à¤¨à¤¿à¤°à¥à¤§à¤¾à¤°à¤¿à¤¤ à¤…à¤¨à¥à¤¸à¥à¤®à¤¾à¤°à¤•',
  },
  'zh': {
    'add': 'æ·»åŠ ',
    'save': 'ä¿å­˜',
    'delete': 'åˆ é™¤',
    'view': 'æŸ¥çœ‹',
    'close': 'å…³é—­',
    'share': 'åˆ†äº«',
    'install_app': 'å®‰è£…åº”ç”¨',
    'help': 'å¸®åŠ©',
    'call': 'å‘¼å«',
    'chat': 'èŠå¤©',
    'write_comment': 'è¾“å…¥æ‚¨çš„è¯„è®º...',
    'send': 'å‘é€',
    'comment_sent': 'è¯„è®ºå‘é€æˆåŠŸ',
    'chat_date': 'èŠå¤© / æ—¥æœŸ',
    'joining_date': 'åŠ å…¥æ—¥æœŸ',
    'last_login': 'ä¸Šæ¬¡ç™»å½•',
    'login': 'ç™»å½•',
    'logout': 'é€€å‡ºç™»å½•',
    'admin': 'ç®¡ç†å‘˜',
    'medications': 'è¯ç‰©',
    'doctors': 'åŒ»ç”Ÿ',
    'pharmacies': 'è¯æˆ¿',
    'reminders': 'æé†’',
    'documents': 'æ–‡æ¡£',
    'insurance_cards': 'ä¿é™©å¡',
    'name': 'å§“å',
    'dosage': 'å‰‚é‡',
    'notes': 'å¤‡æ³¨',
    'quantity': 'åº“å­˜',
    'description': 'æè¿°',
    'specialty': 'ä¸“ç§‘',
    'phone': 'ç”µè¯',
    'address': 'åœ°å€',
    'email': 'ç”µå­é‚®ä»¶æˆ–ç”¨æˆ·å',
    'show_password': 'æ˜¾ç¤ºå¯†ç ',
    'password': 'å¯†ç ',
    'password_6_digit': '6 ä½æ•°å­—',
    'sign_in': 'ç™»å½•',
    'new_user': 'æ–°ç”¨æˆ·',
    'register': 'æ³¨å†Œ',
    'create_account': 'åˆ›å»ºè´¦æˆ·',
    'already_account': 'å·²ç»æœ‰è´¦æˆ·ï¼Ÿ',
    'location': 'ä½ç½®',
    'photo': 'ç…§ç‰‡',
    'front_photo': 'æ­£é¢ç…§ç‰‡',
    'back_photo': 'èƒŒé¢ç…§ç‰‡',
    'reminder_time': 'æé†’æ—¶é—´',
    'reminder_date': 'æé†’æ—¥æœŸ',
    'schedule_type': 'è®¡åˆ’',
    'daily': 'æ¯å¤©',
    'calendar': 'æ—¥åŽ†',
    'select_times': 'é€‰æ‹©ä¸€ä¸ªæˆ–å¤šä¸ªæ—¶é—´',
    'select_schedule': 'é€‰æ‹©è®¡åˆ’',
    'record': 'è®°å½•',
    'no_records': 'æ²¡æœ‰è®°å½•',
    'guest_mode': 'è®¿å®¢æ¨¡å¼',
    'get_copy': 'èŽ·å–ä½ çš„å‰¯æœ¬',
    'create_copy': 'åˆ›å»ºä½ çš„å‰¯æœ¬',
    'select_all': 'å…¨é€‰',
    'share_selected': 'åˆ†äº«æ‰€é€‰å†…å®¹',
    'no_selection': 'æœªé€‰æ‹©ä»»ä½•é¡¹ç›®',
    'admin_panel': 'ç®¡ç†é¢æ¿',
    'users': 'ç”¨æˆ·',
    'activate': 'å¯ç”¨',
    'deactivate': 'åœç”¨',
    'status': 'çŠ¶æ€',
    'role': 'è§’è‰²',
    'active_user': 'æ´»è·ƒç”¨æˆ·',
    'inactive_guest': 'éžæ´»è·ƒç”¨æˆ·',
    'expired': 'è¯·èŽ·å–æ‚¨è‡ªå·±çš„å‰¯æœ¬ï¼Œå¹¶ç­‰å¾…48å°æ—¶ç›´åˆ°æ¿€æ´»ã€‚',
    'pending_activation': 'è¯·èŽ·å–æ‚¨è‡ªå·±çš„å‰¯æœ¬ï¼Œå¹¶ç­‰å¾…48å°æ—¶ç›´åˆ°æ¿€æ´»ã€‚',
    'paid': 'å·²ä»˜æ¬¾',
    'expiry_date': 'åˆ°æœŸæ—¥',
    'provider_name': 'æä¾›å•†åç§°',
    'front_image': 'æ­£é¢å›¾ç‰‡',
    'back_image': 'èƒŒé¢å›¾ç‰‡',
    'file_url': 'æ–‡ä»¶é“¾æŽ¥',
    'category': 'ç±»åˆ«',
    'title': 'æ ‡é¢˜',
    'policy': 'ä¿å•',
    'policy_number': 'ä¿å•å·ç ',
    'provider': 'æä¾›å•†',
    'expiry': 'åˆ°æœŸæ—¥',
    'specialist': 'ä¸“å®¶',
    'guest': 'è®¿å®¢æ¨¡å¼',
    'account': 'è´¦æˆ·',
    'guest_data': 'è®¿å®¢æ•°æ®',
    'full_record': 'å®Œæ•´è®°å½•',
    'share_record': 'åˆ†äº«è®°å½•',
    'sign_up': 'æ³¨å†Œ',
    'language': 'è¯­è¨€',
    'select_medication': 'é€‰æ‹©è¯ç‰©',
    'select_time': 'é€‰æ‹©æ—¶é—´',
    'select_date': 'é€‰æ‹©æ—¥æœŸ',
    'required_field': 'æ­¤å­—æ®µä¸ºå¿…å¡«é¡¹',
    'time_format_12h': 'hh:mm AM/PM',
    'please_login': 'è¯·ç™»å½•',
    'please_fill_all': 'è¯·å¡«å†™æ‰€æœ‰å­—æ®µ',
    'login_failed': 'ç™»å½•å¤±è´¥',
    'signup_failed': 'æ³¨å†Œå¤±è´¥',
    'delete_confirm_title': 'åˆ é™¤ï¼Ÿ',
    'delete_confirm_msg': 'ç¡®å®šè¦åˆ é™¤æ­¤è®°å½•å—ï¼Ÿ',
    'cancel': 'å–æ¶ˆ',
    'please_sign_in': 'è¯·ç™»å½•',
    'account_created_success': 'è´¦æˆ·åˆ›å»ºæˆåŠŸï¼è¯·ç™»å½•ã€‚',
    'operation_failed': 'æ“ä½œå¤±è´¥',
    'select_front_image': 'é€‰æ‹©æ­£é¢å›¾ç‰‡',
    'select_back_image': 'é€‰æ‹©èƒŒé¢å›¾ç‰‡',
    'upload_image': 'ä¸Šä¼ å›¾ç‰‡',
    'uploaded': 'å·²ä¸Šä¼ ',
    'insurance_company_name': 'ä¿é™©å…¬å¸åç§°',
    'patient_id': 'æ‚£è€… ID',
    'insurance_card_front': 'ä¿é™©å¡ - æ­£é¢',
    'insurance_card_back': 'ä¿é™©å¡ - èƒŒé¢',
    'no_image_selected': 'æœªé€‰æ‹©å›¾ç‰‡',
    'upload_front_card': 'ä¸Šä¼ æ­£é¢å¡ç‰‡',
    'upload_back_card': 'ä¸Šä¼ èƒŒé¢å¡ç‰‡',
    'add_data': 'æ·»åŠ æ•°æ®',
    'please_enter_insurance_company': 'è¯·è¾“å…¥ä¿é™©å…¬å¸åç§°',
    'please_enter_patient_id': 'è¯·è¾“å…¥æ‚£è€… ID',
    'please_upload_both_cards': 'è¯·ä¸Šä¼ ä¸¤å¼ å¡ç‰‡',
    'success': 'æˆåŠŸ',
    'upload_photo': 'ä¸Šä¼ ç…§ç‰‡',
    'select_photo': 'é€‰æ‹©ç…§ç‰‡',
    'photo_uploaded': 'ç…§ç‰‡å·²ä¸Šä¼ ',
    'please_upload_photo': 'è¯·ä¸Šä¼ ç…§ç‰‡',
    'share_app': 'åˆ†äº«åº”ç”¨',
    'share_app_message': 'SANA - æ‚¨çš„å¥åº·ç®¡ç†åº”ç”¨ï¼',
    'opening_payment': 'æ­£åœ¨æ‰“å¼€æ”¯ä»˜é¡µé¢...',
    'payment_error': 'æ”¯ä»˜é”™è¯¯',
    'medicine_photo': 'è¯ç‰©ç…§ç‰‡',
    'no_medicine_photo': 'æœªé€‰æ‹©è¯ç‰©ç…§ç‰‡',
    'upload_medicine_photo': 'ä¸Šä¼ è¯ç‰©ç…§ç‰‡',
    'change_medicine_photo': 'æ›´æ¢è¯ç‰©ç…§ç‰‡',
    'select_reminder_times': 'é€‰æ‹©æé†’æ—¶é—´',
    'selected': 'å·²é€‰',
    'medication_schedule': 'è¯ç‰©æœè¯è®¡åˆ’',
    'choose_schedule_repeat': 'é€‰æ‹©ä½•æ—¶é‡å¤æ­¤æé†’ï¼š',
    'repeat_daily_msg': 'æé†’å°†æ¯å¤©é‡å¤ã€‚',
    'select_calendar_date': 'é€‰æ‹©æ—¥åŽ†æ—¥æœŸ',
    'date': 'æ—¥æœŸ',
    'share_documents': 'åˆ†äº«æ–‡æ¡£',
    'manual_title': 'SANA éšèº«å¥åº·æ‰‹å†Œ',
    'manual_content':
        '1. åœ¨ç½‘é¡µç«¯å®‰å…¨ç®¡ç†æ‚¨çš„å¥åº·è®°å½•ï¼Œå¹¶éšæ—¶éšåœ°é€šè¿‡ä»»ä½•è®¾å¤‡è®¿é—®æ‚¨çš„æ•°æ®ã€‚\n2. è½»æ¾æ·»åŠ å¹¶è·Ÿè¸ªæ¯æ—¥è¯ç‰©ç”¨é‡å’Œé¢‘çŽ‡ã€‚\n3. ä¿å­˜åŒ»ç”Ÿä¸“ç§‘ä¿¡æ¯ä¸Žè”ç³»æ–¹å¼ã€‚\n4. ä¿å­˜å¸¸ç”¨è¯æˆ¿åœ°å€ä¸Žè”ç³»ç”µè¯ã€‚\n5. è®¾ç½®å¤šæ—¶é—´æ®µå¸¦æç¤ºçš„æœè¯æé†’ã€‚\n6. æ‹æ‘„å¹¶ä¿å­˜åŒ»ç–—æŠ¥å‘Šä¸Žæ£€æŸ¥å•ã€‚\n7. ä¿å­˜åŒ»ä¿å¡æ­£é¢å’Œåé¢ç…§ç‰‡ã€‚\n8. éšæ—¶å‹¾é€‰å¹¶å‘åŒ»ç”Ÿåˆ†äº«æ‚¨çš„å¥åº·æ¡£æ¡ˆã€‚\n9. å°†åº”ç”¨ç¨‹åºå®‰è£…åˆ°æ‚¨çš„è®¾å¤‡ä¸Šï¼Œä»¥èŽ·å¾—å…¨éƒ¨åŠŸèƒ½å¹¶å¯ç”¨æœè¯æé†’å’Œé—¹é’Ÿã€‚\n10. èŽ·å–å±žäºŽæ‚¨è‡ªå·±çš„ç§å¯†ä¸“å±žå‰¯æœ¬ï¼Œä»»ä½•å…¶ä»–äººéƒ½æ— æ³•çœ‹åˆ°ã€‚\n11. è¦åœ¨æ‚¨çš„è®¾å¤‡ä¸Šå®‰è£… SANAï¼Œè¯·åœ¨æ‰‹æœºæµè§ˆå™¨ä¸­æ‰“å¼€åº”ç”¨ï¼šåœ¨ Android Chrome ä¸­ï¼Œæ‰“å¼€ â‹® èœå•å¹¶é€‰æ‹©â€œå®‰è£…åº”ç”¨â€æˆ–â€œæ·»åŠ åˆ°ä¸»å±å¹•â€ï¼›åœ¨ iPhone Safari ä¸­ï¼Œç‚¹å‡»â€œåˆ†äº«â€å¹¶é€‰æ‹©â€œæ·»åŠ åˆ°ä¸»å±å¹•â€ã€‚',
    'taken': 'å·²æœè¯',
    'alarm': 'æœè¯æé†’',
    'daily_reminders': 'æ¯æ—¥æé†’',
    'calendar_reminders': 'è®¡åˆ’æé†’',
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

class GuestIdentityService {
  // No guest identity exists in this architecture.
  // Callers still invoke these methods, so they remain as no-ops.
  static Future<String> getGuestId() async {
    return '';
  }

  static void clearCache() {}
}

// ============================================
// MAIN
// ============================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SanaAlarmService.initialize();

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

class SanaApp extends StatelessWidget {
  final String? pendingReminderId;
  const SanaApp({super.key, this.pendingReminderId});
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
          child: (pendingReminderId != null && pendingReminderId!.isNotEmpty)
              ? SanaAlarmScreen(
                  reminderId: pendingReminderId!,
                  notificationId: 0,
                  daily: false,
                )
              : const HomeScreen(),
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _loadSession();
    });
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final guestId = await GuestIdentityService.getGuestId();
      final user = _client.auth.currentUser;
      final isRealUser = user != null && user.isAnonymous == false;

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
                .update({'timezone': tz})
                .eq('id', user.id);
          }
        }
      } catch (_) {}

      if (!isRealUser) {
        if (!mounted) return;
        setState(() {
          _profile = null;
          _guestId = guestId;
          _isGuest = true;
          _loading = false;
        });
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

      // ðŸ›‘ ADMIN IS PERMANENTLY EXEMPT FROM DEACTIVATION AND EXPIRY:
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
    } catch (_) {
      if (mounted) {
        final guestId = await GuestIdentityService.getGuestId();
        setState(() {
          _profile = null;
          _guestId = guestId;
          _isGuest = true;
          _loading = false;
        });
      }
    }
  }

  String? get _ownerId {
    final user = _client.auth.currentUser;
    if (user != null && user.isAnonymous == false) {
      return user.id;
    }
    return _guestId;
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
          autoOpenAdd: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  static const String _sanaApkUrl =
      'https://sanabase.github.io/sana/downloads/sana.apk';

  static const String _sanaIosUrl = 'https://sanabase.github.io/sana/';

  static const String _sanaWindowsUrl =
      'https://sanabase.github.io/sana/downloads/sana-windows.zip';

  static const String _sanaMacosUrl =
      'https://sanabase.github.io/sana/downloads/sana-macos.zip';

  static const String _sanaLinuxUrl =
      'https://sanabase.github.io/sana/downloads/sana-linux.tar.gz';

  Future<void> _launchDirect(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    }
  }

  void _showAdaptiveInstallDialog() {
    final language = languageNotifier.value;

    final bool isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final bool isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final bool isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final bool isMacos = defaultTargetPlatform == TargetPlatform.macOS;
    final bool isLinux = defaultTargetPlatform == TargetPlatform.linux;

    String title;
    String instructions;

    if (isAndroid) {
      title = switch (language) {
        'ar' => 'ØªØ«Ø¨ÙŠØª SANA Ø¹Ù„Ù‰ Android',
        'es' => 'Instalar SANA en Android',
        'fr' => 'Installer SANA sur Android',
        'de' => 'SANA auf Android installieren',
        'tr' => 'SANAâ€™yÄ± Androidâ€™e yÃ¼kle',
        'hi' => 'Android à¤ªà¤° SANA à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
        'zh' => 'åœ¨ Android ä¸Šå®‰è£… SANA',
        _ => 'Install SANA on Android',
      };

      instructions = switch (language) {
        'ar' =>
          'Ø³ÙŠØªÙ… ÙØªØ­ Ø±Ø§Ø¨Ø· ØªÙ†Ø²ÙŠÙ„ Ù…Ù„Ù APK Ø§Ù„Ø£ØµÙ„ÙŠ Ù„ØªØ·Ø¨ÙŠÙ‚ SANA. Ø¨Ø¹Ø¯ Ø§Ù„ØªÙ†Ø²ÙŠÙ„ØŒ Ø§Ø¶ØºØ· Ø¹Ù„Ù‰ Ø§Ù„Ù…Ù„Ù Ù„ØªØ«Ø¨ÙŠØªÙ‡.',
        'es' =>
          'Se abrirÃ¡ el enlace de descarga del APK nativo de SANA. Tras descargarlo, pulse el archivo para instalarlo.',
        'fr' =>
          'Le lien de tÃ©lÃ©chargement de lâ€™APK natif de SANA va sâ€™ouvrir. AprÃ¨s tÃ©lÃ©chargement, appuyez sur le fichier pour lâ€™installer.',
        'de' =>
          'Der Download-Link fÃ¼r die native SANA-APK wird geÃ¶ffnet. Nach dem Download tippen Sie auf die Datei, um sie zu installieren.',
        'tr' =>
          'SANA yerel APK indirme baÄŸlantÄ±sÄ± aÃ§Ä±lacak. Ä°ndirdikten sonra dosyaya dokunarak yÃ¼kleyin.',
        'hi' =>
          'SANA à¤•à¤¾ à¤®à¥‚à¤² APK à¤¡à¤¾à¤‰à¤¨à¤²à¥‹à¤¡ à¤²à¤¿à¤‚à¤• à¤–à¥à¤²à¥‡à¤—à¤¾à¥¤ à¤¡à¤¾à¤‰à¤¨à¤²à¥‹à¤¡ à¤•à¥‡ à¤¬à¤¾à¤¦ à¤«à¤¼à¤¾à¤‡à¤² à¤ªà¤° à¤Ÿà¥ˆà¤ª à¤•à¤°à¤•à¥‡ à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚à¥¤',
        'zh' => 'å°†æ‰“å¼€ SANA åŽŸç”Ÿ APK ä¸‹è½½é“¾æŽ¥ã€‚ä¸‹è½½åŽç‚¹å‡»æ–‡ä»¶è¿›è¡Œå®‰è£…ã€‚',
        _ =>
          'The native SANA APK download link will open. After downloading, tap the file to install it.',
      };
    } else if (isIos) {
      title = switch (language) {
        'ar' => 'ØªØ«Ø¨ÙŠØª SANA Ø¹Ù„Ù‰ iPhone / iPad',
        'es' => 'Instalar SANA en iPhone / iPad',
        'fr' => 'Installer SANA sur iPhone / iPad',
        'de' => 'SANA auf iPhone / iPad installieren',
        'tr' => 'SANAâ€™yÄ± iPhone / iPadâ€™e yÃ¼kle',
        'hi' => 'iPhone / iPad à¤ªà¤° SANA à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
        'zh' => 'åœ¨ iPhone / iPad ä¸Šå®‰è£… SANA',
        _ => 'Install SANA on iPhone / iPad',
      };

      instructions = switch (language) {
        'ar' =>
          'Ø³ÙŠØªÙ… ÙØªØ­ ØµÙØ­Ø© ØªØ«Ø¨ÙŠØª SANA Ù„Ù†Ø¸Ø§Ù… iOS. Ø§ØªØ¨Ø¹ Ø§Ù„ØªØ¹Ù„ÙŠÙ…Ø§Øª Ø¹Ù„Ù‰ Ø§Ù„Ø´Ø§Ø´Ø©.',
        'es' =>
          'Se abrirÃ¡ la pÃ¡gina de instalaciÃ³n de SANA para iOS. Siga las instrucciones en pantalla.',
        'fr' =>
          'La page dâ€™installation SANA pour iOS va sâ€™ouvrir. Suivez les instructions Ã  lâ€™Ã©cran.',
        'de' =>
          'Die SANA-Installationsseite fÃ¼r iOS wird geÃ¶ffnet. Folgen Sie den Anweisungen auf dem Bildschirm.',
        'tr' =>
          'SANA iOS yÃ¼kleme sayfasÄ± aÃ§Ä±lacak. Ekrandaki yÃ¶nergeleri izleyin.',
        'hi' =>
          'SANA à¤•à¤¾ iOS à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤²à¥‡à¤¶à¤¨ à¤ªà¥ƒà¤·à¥à¤  à¤–à¥à¤²à¥‡à¤—à¤¾à¥¤ à¤¸à¥à¤•à¥à¤°à¥€à¤¨ à¤ªà¤° à¤¦à¤¿à¤ à¤¨à¤¿à¤°à¥à¤¦à¥‡à¤¶à¥‹à¤‚ à¤•à¤¾ à¤ªà¤¾à¤²à¤¨ à¤•à¤°à¥‡à¤‚à¥¤',
        'zh' => 'å°†æ‰“å¼€ SANA çš„ iOS å®‰è£…é¡µé¢ã€‚è¯·æŒ‰å±å¹•æç¤ºæ“ä½œã€‚',
        _ =>
          'The SANA iOS installation page will open. Follow the on-screen instructions.',
      };
    } else if (isWindows) {
      title = switch (language) {
        'ar' => 'ØªØ«Ø¨ÙŠØª SANA Ø¹Ù„Ù‰ Windows',
        'es' => 'Instalar SANA en Windows',
        'fr' => 'Installer SANA sur Windows',
        'de' => 'SANA auf Windows installieren',
        'tr' => 'SANAâ€™yÄ± Windowsâ€™a yÃ¼kle',
        'hi' => 'Windows à¤ªà¤° SANA à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
        'zh' => 'åœ¨ Windows ä¸Šå®‰è£… SANA',
        _ => 'Install SANA on Windows',
      };

      instructions = switch (language) {
        'ar' =>
          'Ø³ÙŠØªÙ… ÙØªØ­ Ø±Ø§Ø¨Ø· ØªÙ†Ø²ÙŠÙ„ SANA Ù„Ù†Ø¸Ø§Ù… Windows. ÙÙƒ Ø§Ù„Ø¶ØºØ· Ø«Ù… Ø´ØºÙ‘Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚.',
        'es' =>
          'Se abrirÃ¡ el enlace de descarga de SANA para Windows. Descomprima y ejecute la aplicaciÃ³n.',
        'fr' =>
          'Le lien de tÃ©lÃ©chargement SANA pour Windows va sâ€™ouvrir. DÃ©compressez puis lancez lâ€™application.',
        'de' =>
          'Der SANA-Download-Link fÃ¼r Windows wird geÃ¶ffnet. Entpacken Sie das Archiv und starten Sie die App.',
        'tr' =>
          'SANA Windows indirme baÄŸlantÄ±sÄ± aÃ§Ä±lacak. ArÅŸivi aÃ§Ä±n ve uygulamayÄ± baÅŸlatÄ±n.',
        'hi' =>
          'SANA à¤•à¤¾ Windows à¤¡à¤¾à¤‰à¤¨à¤²à¥‹à¤¡ à¤²à¤¿à¤‚à¤• à¤–à¥à¤²à¥‡à¤—à¤¾à¥¤ à¤«à¤¼à¤¾à¤‡à¤² à¤¨à¤¿à¤•à¤¾à¤²à¥‡à¤‚ à¤”à¤° à¤à¤ª à¤šà¤²à¤¾à¤à¤à¥¤',
        'zh' => 'å°†æ‰“å¼€ SANA çš„ Windows ä¸‹è½½é“¾æŽ¥ã€‚è§£åŽ‹åŽè¿è¡Œåº”ç”¨ç¨‹åºã€‚',
        _ =>
          'The SANA Windows download link will open. Unzip and run the application.',
      };
    } else if (isMacos) {
      title = switch (language) {
        'ar' => 'ØªØ«Ø¨ÙŠØª SANA Ø¹Ù„Ù‰ macOS',
        'es' => 'Instalar SANA en macOS',
        'fr' => 'Installer SANA sur macOS',
        'de' => 'SANA auf macOS installieren',
        'tr' => 'SANAâ€™yÄ± macOSâ€™a yÃ¼kle',
        'hi' => 'macOS à¤ªà¤° SANA à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
        'zh' => 'åœ¨ macOS ä¸Šå®‰è£… SANA',
        _ => 'Install SANA on macOS',
      };

      instructions = switch (language) {
        'ar' =>
          'Ø³ÙŠØªÙ… ÙØªØ­ Ø±Ø§Ø¨Ø· ØªÙ†Ø²ÙŠÙ„ SANA Ù„Ù†Ø¸Ø§Ù… macOS. ÙÙƒ Ø§Ù„Ø¶ØºØ· Ø«Ù… Ø´ØºÙ‘Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚.',
        'es' =>
          'Se abrirÃ¡ el enlace de descarga de SANA para macOS. Descomprima y ejecute la aplicaciÃ³n.',
        'fr' =>
          'Le lien de tÃ©lÃ©chargement SANA pour macOS va sâ€™ouvrir. DÃ©compressez puis lancez lâ€™application.',
        'de' =>
          'Der SANA-Download-Link fÃ¼r macOS wird geÃ¶ffnet. Entpacken Sie das Archiv und starten Sie die App.',
        'tr' =>
          'SANA macOS indirme baÄŸlantÄ±sÄ± aÃ§Ä±lacak. ArÅŸivi aÃ§Ä±n ve uygulamayÄ± baÅŸlatÄ±n.',
        'hi' => 'SANA à¤•à¤¾ macOS à¤¡à¤¾à¤‰à¤¨à¤²à¥‹à¤¡ à¤²à¤¿à¤‚à¤• à¤–à¥à¤²à¥‡à¤—à¤¾à¥¤ à¤«à¤¼à¤¾à¤‡à¤² à¤¨à¤¿à¤•à¤¾à¤²à¥‡à¤‚ à¤”à¤° à¤à¤ª à¤šà¤²à¤¾à¤à¤à¥¤',
        'zh' => 'å°†æ‰“å¼€ SANA çš„ macOS ä¸‹è½½é“¾æŽ¥ã€‚è§£åŽ‹åŽè¿è¡Œåº”ç”¨ç¨‹åºã€‚',
        _ =>
          'The SANA macOS download link will open. Unzip and run the application.',
      };
    } else if (isLinux) {
      title = switch (language) {
        'ar' => 'ØªØ«Ø¨ÙŠØª SANA Ø¹Ù„Ù‰ Linux',
        'es' => 'Instalar SANA en Linux',
        'fr' => 'Installer SANA sur Linux',
        'de' => 'SANA auf Linux installieren',
        'tr' => 'SANAâ€™yÄ± Linuxâ€™a yÃ¼kle',
        'hi' => 'Linux à¤ªà¤° SANA à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
        'zh' => 'åœ¨ Linux ä¸Šå®‰è£… SANA',
        _ => 'Install SANA on Linux',
      };

      instructions = switch (language) {
        'ar' => 'Ø³ÙŠØªÙ… ÙØªØ­ Ø±Ø§Ø¨Ø· ØªÙ†Ø²ÙŠÙ„ SANA Ù„Ù†Ø¸Ø§Ù… Linux.',
        'es' => 'Se abrirÃ¡ el enlace de descarga de SANA para Linux.',
        'fr' => 'Le lien de tÃ©lÃ©chargement SANA pour Linux va sâ€™ouvrir.',
        'de' => 'Der SANA-Download-Link fÃ¼r Linux wird geÃ¶ffnet.',
        'tr' => 'SANA Linux indirme baÄŸlantÄ±sÄ± aÃ§Ä±lacak.',
        'hi' => 'SANA à¤•à¤¾ Linux à¤¡à¤¾à¤‰à¤¨à¤²à¥‹à¤¡ à¤²à¤¿à¤‚à¤• à¤–à¥à¤²à¥‡à¤—à¤¾à¥¤',
        'zh' => 'å°†æ‰“å¼€ SANA çš„ Linux ä¸‹è½½é“¾æŽ¥ã€‚',
        _ => 'The SANA Linux download link will open.',
      };
    } else {
      title = tr(language, 'install_app');

      instructions = switch (language) {
        'ar' => 'Ø³ÙŠØªÙ… ØªÙˆØ¬ÙŠÙ‡Ùƒ Ø¥Ù„Ù‰ Ø§Ù„ØªØ«Ø¨ÙŠØª Ø§Ù„Ù…Ù†Ø§Ø³Ø¨ Ù„Ø¬Ù‡Ø§Ø²Ùƒ.',
        'es' => 'Se le dirigirÃ¡ a la instalaciÃ³n adecuada para su dispositivo.',
        'fr' =>
          'Vous serez redirigÃ© vers lâ€™installation adaptÃ©e Ã  votre appareil.',
        'de' =>
          'Sie werden zur passenden Installation fÃ¼r Ihr GerÃ¤t weitergeleitet.',
        'tr' => 'CihazÄ±nÄ±za uygun kurulum sayfasÄ±na yÃ¶nlendirileceksiniz.',
        'hi' => 'à¤†à¤ªà¤•à¥‹ à¤†à¤ªà¤•à¥‡ à¤¡à¤¿à¤µà¤¾à¤‡à¤¸ à¤•à¥‡ à¤…à¤¨à¥à¤•à¥‚à¤² à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤²à¥‡à¤¶à¤¨ à¤ªà¤° à¤²à¥‡ à¤œà¤¾à¤¯à¤¾ à¤œà¤¾à¤à¤—à¤¾à¥¤',
        'zh' => 'å°†å¼•å¯¼æ‚¨è¿›å…¥é€‚åˆæ‚¨è®¾å¤‡çš„å®‰è£…é¡µé¢ã€‚',
        _ =>
          'You will be directed to the appropriate installation for your device.',
      };
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(instructions),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr(language, 'close')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download),
              onPressed: () {
                Navigator.of(dialogContext).pop();

                if (isAndroid) {
                  _launchDirect(_sanaApkUrl);
                } else if (isIos) {
                  _launchDirect(_sanaIosUrl);
                } else if (isWindows) {
                  _launchDirect(_sanaWindowsUrl);
                } else if (isMacos) {
                  _launchDirect(_sanaMacosUrl);
                } else if (isLinux) {
                  _launchDirect(_sanaLinuxUrl);
                } else {
                  _launchDirect(_sanaIosUrl);
                }
              },
              label: Text(
                switch (language) {
                  'ar' => 'Ø§Ø¨Ø¯Ø£ Ø§Ù„ØªØ«Ø¨ÙŠØª',
                  'es' => 'Instalar ahora',
                  'fr' => 'Installer maintenant',
                  'de' => 'Jetzt installieren',
                  'tr' => 'Åžimdi yÃ¼kle',
                  'hi' => 'à¤…à¤­à¥€ à¤‡à¤‚à¤¸à¥à¤Ÿà¥‰à¤² à¤•à¤°à¥‡à¤‚',
                  'zh' => 'ç«‹å³å®‰è£…',
                  _ => 'Install now',
                },
              ),
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
                                                    InkWell(
                                                      onTap: () async {
                                                        Navigator.of(ctx).pop();
                                                        if (kIsWeb) {
                                                          final result = await SanaWebPush.enableVerbose(
                                                            Supabase.instance.client,
                                                          );
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                duration: const Duration(seconds: 15),
                                                                content: Text(
                                                                  result == 'OK'
                                                                      ? tr(language, 'reminders_enabled')
                                                                      : 'SANA DEBUG: $result',
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        } else {
                                                          _showAdaptiveInstallDialog();
                                                        }
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          vertical: 12,
                                                          horizontal: 16,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.teal
                                                              .withValues(
                                                                  alpha: 0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                          border: Border.all(
                                                              color:
                                                                  Colors.teal),
                                                        ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const Icon(
                                                              Icons
                                                                  .notifications_active,
                                                              color:
                                                                  Colors.teal,
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            Flexible(
                                                              child: Text(
                                                                tr(
                                                                  language,
                                                                  'enable_reminders',
                                                                ),
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .teal,
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
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
        _shareCard(language),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_shared, size: 28, color: Colors.teal),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    tr(language, 'share_documents'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
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

    // IMPORTANT:
    // Storage ownership is based on auth.uid().
    final filePath = 'medications/${user.id}/$fileId.$extension';

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

class SignedImage extends StatefulWidget {
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
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(
    covariant SignedImage oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.path != widget.path) {
      _url = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path?.trim();

    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    final url = await StorageHelper.getSignedUrl(path);

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
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_url == null) {
      return Icon(
        Icons.medication,
        size: widget.height ?? 48,
        color: Colors.teal,
      );
    }

    return Image.network(
      _url!,
      height: widget.height,
      width: widget.width,
      fit: widget.fit,
      errorBuilder: (_, __, ___) {
        return Icon(
          Icons.medication,
          size: widget.height ?? 48,
          color: Colors.teal,
        );
      },
    );
  }
}

// ============================================
// ADD FORM DIALOG
// ============================================

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
        body: InteractiveViewer(
          minScale: 1.0,
          maxScale: 3.0,
          child: Form(
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
                                  final base64 = await ImagePickerHelper
                                      .pickImageAsBase64();
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
                                              ? tr(widget.language,
                                                  'upload_photo')
                                              : tr(
                                                  widget.language, 'uploaded')),
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

  const RecordListScreen({
    super.key,
    required this.type,
    required this.ownerId,
    required this.guestMode,
    this.autoOpenAdd = false,
  });

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _medicationsList = [];
  bool _loading = true;
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
          ? await query.isFilter('user_id', null)
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

    // ADD THESE 5 LINES FOR DEBUG
    //print('========== LOAD ==========');
    //print('Type: ${widget.type}');
    //print('Table: $_table');
    //print('Owner ID: ${widget.ownerId}');
    //print('Guest Mode: ${widget.guestMode}');

    try {
      final tableName = _table;
      final query = _client.from(tableName).select();
      final dynamic response = widget.guestMode
          ? await query.isFilter('user_id', null)
          : await query.eq('user_id', widget.ownerId);

      if (mounted) {
        final List<dynamic> list = response as List<dynamic>;
        var records =
            list.map((item) => Map<String, dynamic>.from(item as Map)).toList();

        // ADD THIS 1 LINE FOR DEBUG
        print('Records found: ${records.length}');

        setState(() {
          _rows = records;
          _loading = false;
        });

        if (_table == 'reminders') {
          for (final row in records) {
            try {
              await SanaAlarmService.scheduleReminder(row);
            } catch (e) {
              debugPrint(
                'Reminder alarm scheduling failed for ${row['id']}: $e',
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading: $e')));
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

    final cleanPayload = <String, dynamic>{
      'user_id': widget.guestMode ? null : widget.ownerId,
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

      // ------------------------------------------
      // Upload photo to private Storage.
      // Only the Storage path is saved in DB.
      // ------------------------------------------
      if (photo != null && photo.toString().trim().isNotEmpty) {
        try {
          final storagePath = await StorageHelper.uploadMedicationPhoto(
            base64Image: photo.toString(),
          );

          cleanPayload['photo_url'] = storagePath;
        } catch (e) {
          debugPrint(
            'Medication photo upload failed; continuing without photo: $e',
          );
        }
      }
    }

    try {
      print('Inserting into $_table: $cleanPayload');

      if (_table == 'reminders') {
        final inserted =
            await _client.from(_table).insert(cleanPayload).select().single();

        try {
          await SanaAlarmService.scheduleReminder(
            Map<String, dynamic>.from(inserted),
          );
        } catch (e) {
          debugPrint(
            'Reminder saved but alarm scheduling failed: $e',
          );
        }
      } else {
        await _client.from(_table).insert(cleanPayload);
      }

      await _load();
      // Show confirmation when reminder alarm is saved
      if (mounted && _table == 'reminders') {
        final reminderName = cleanPayload['name'] ?? '';
        final reminderTime = cleanPayload['reminder_time'] ?? '';
        final reminderDate =
            cleanPayload['reminder_date'] ?? tr(language, 'daily');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade700,
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.alarm_on, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    language == 'ar'
                        ? 'ØªÙ… ØªÙØ¹ÙŠÙ„ Ù…Ù†Ø¨Ù‡ "$reminderName" Ø¨Ù†Ø¬Ø§Ø­ Ù„Ù„Ù…ÙˆØ¹Ø¯: $reminderDate $reminderTime'
                        : 'Alarm for "$reminderName" activated for $reminderDate at $reminderTime',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      print('========== ERROR in _saveRecord ==========');
      print(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${tr(language, 'operation_failed')}: $e',
            ),
          ),
        );
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
    // ADD THIS FIRST LINE
    print('>>> _submitInsuranceCard() CALLED! <<<');
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

      cleanPayload['user_id'] = widget.guestMode ? null : widget.ownerId;

      await _client.from(_table).insert(cleanPayload);
      await _load();

      setState(() {
        _frontCardBase64 = null;
        _backCardBase64 = null;
        _insuranceCompanyController.clear();
        _patientIdController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${tr(language, 'add')} ${tr(language, 'insurance_cards')} ${tr(language, 'success')}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(language, 'operation_failed')}: $e')),
      );
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

      cleanPayload['user_id'] = widget.guestMode ? null : widget.ownerId;

      await _client.from(_table).insert(cleanPayload);
      await _load();

      setState(() {
        _documentPhotoBase64 = null;
        _titleController.clear();
        _categoryController.clear();
        _fileUrlController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${tr(language, 'add')} ${tr(language, 'documents')} ${tr(language, 'success')}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(language, 'operation_failed')}: $e')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;

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

    try {
      final photoPath = row['photo_url']?.toString();

      if (_table == 'reminders') {
        await SanaAlarmService.cancelReminder(
          id.toString(),
        );

        await SanaAlarmService.stopAlarmSound(
          notificationId: SanaAlarmService.notificationId(
            id.toString(),
            0,
          ),
        );

        await SanaAlarmService.cancelNativeAlarm(
          SanaAlarmService.notificationId(
            id.toString(),
            0,
          ),
        );
      }

      // 1. Delete database record first.
      final query = _client.from(_table).delete().eq('id', id);

      if (widget.guestMode) {
        await query.isFilter(
          'user_id',
          null,
        );
      } else {
        await query.eq(
          'user_id',
          widget.ownerId,
        );
      }

      // 2. Delete the corresponding Storage image.
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        await StorageHelper.deleteMedicationPhoto(
          photoPath,
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
          ),
        );
      }
    }
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
      return '${row['location'] ?? ''} ${row['phone'] ?? ''}';
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
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
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
                                              child: SignedImage(
                                                path: row['photo_url']
                                                    ?.toString(),
                                                height: 50,
                                                width: 50,
                                                fit: BoxFit.cover,
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
                                                    fontWeight: FontWeight.bold,
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
                                                    color: Colors.grey.shade700,
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
                                                  tooltip: tr(language, 'call'),
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

                                                    if (cleaned.isEmpty) return;

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
                                                      final telUri = Uri.parse(
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
                                                onPressed: () => _preview(row),
                                                icon: const Icon(
                                                  Icons.remove_red_eye_outlined,
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
                                                tooltip: tr(language, 'share'),
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
                                                tooltip: tr(language, 'delete'),
                                              ),
                                            ],
                                          ),
                                        ],
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
                                                padding: const EdgeInsets.only(
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
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ),
                                            if (times.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(
                                                  times.join(' â€¢ '),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
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
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade700,
                                                      ),
                                                    ),
                                                  if (times.isNotEmpty)
                                                    Text(
                                                      times.join(
                                                        ' â€¢ ',
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                                      overflow:
                                                          TextOverflow.ellipsis,
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

class SanaAlarmScreen extends StatefulWidget {
  final String reminderId;
  final int notificationId;
  final bool daily;

  const SanaAlarmScreen({
    super.key,
    required this.reminderId,
    required this.notificationId,
    required this.daily,
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
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    try {
      final result = await _client
          .from('reminders')
          .select('*')
          .eq('id', widget.reminderId)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _reminder = result == null ? null : Map<String, dynamic>.from(result);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Alarm reminder load error: $e');

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _markTaken() async {
    if (_taken) return;

    setState(() {
      _taken = true;
    });

    // Keep the existing alarm ring/voice implementation unchanged.
    await SanaAlarmService.stopAlarmSound(
      notificationId: widget.notificationId,
    );

    // Cancel the native alarm that is currently firing.
    await SanaAlarmService.cancelNativeAlarm(
      widget.notificationId,
    );

    // A one-time reminder must not fire again.
    if (!widget.daily) {
      await SanaAlarmService.cancelReminder(
        widget.reminderId,
      );
    }

    if (!mounted) return;

    // Return completely to the application's first/home route.
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil(
      (route) => route.isFirst,
    );
  }

  @override
  void dispose() {
    SanaAlarmService.stopAlarmSound();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tr(language, 'alarm'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (photo != null && photo.trim().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
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
                        const SizedBox(height: 24),
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
                          const SizedBox(height: 10),
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
                          const SizedBox(height: 10),
                          Text(
                            times.join(' â€¢ '),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 20,
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity,
                          height: 70,
                          child: FilledButton(
                            onPressed: _taken ? null : _markTaken,
                            child: Text(
                              tr(language, 'taken'),
                              style: const TextStyle(
                                fontSize: 24,
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
    if (!mounted) return;
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
        final query = _client.from(table).select();
        final dynamic response = widget.guestMode
            ? await query.isFilter('user_id', null)
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(language, 'no_selection'))));
      return;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      await WidgetsBinding.instance.endOfFrame;
      final List<XFile> files = [];

      for (final type in _allData.keys) {
        final selectedRows = _allData[type]!
            .where((row) => _selectedIds[type]!.contains(row['id'].toString()))
            .toList();

        for (final row in selectedRows) {
          final itemId = '${type}_${row['id']}';
          final itemKey = _itemShareKeys[itemId];
          if (itemKey == null) continue;

          final itemContext = itemKey.currentContext;
          if (itemContext == null) continue;

          final renderObject = itemContext.findRenderObject();
          if (renderObject is! RenderRepaintBoundary) continue;

          if (renderObject.debugNeedsPaint) {
            await Future.delayed(const Duration(milliseconds: 100));
            await WidgetsBinding.instance.endOfFrame;
          }

          final ui.Image image = await renderObject.toImage(pixelRatio: 2.0);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);

          if (byteData == null) {
            image.dispose();
            continue;
          }

          files.add(
            XFile.fromData(
              byteData.buffer.asUint8List(),
              name: 'SANA_${type}_${row['id']}.png',
              mimeType: 'image/png',
            ),
          );

          image.dispose();
        }
      }

      if (files.isEmpty) {
        throw Exception('No previews could be captured.');
      }

      await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: 'SANA Medical Records',
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Share preview error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr(language, 'operation_failed')}: $e'),
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
      return '${row['location'] ?? ''} ${row['phone'] ?? ''}';
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
                                                  'â€¢ ${e.key}: ${e.value}',
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
                                          (u['password_plain'] ?? 'â€”')
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
                                            ? const Text('â€”')
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
                                              return const Text('â€”');
                                            }
                                            if (u['is_paid'] != true) {
                                              return const Text('â€”');
                                            }
                                            final rawExp = u['expiry_date'] ??
                                                u['paid_at'];
                                            if (rawExp == null)
                                              return const Text('â€”');
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
                                              return const Text('â€”');
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
                                            ? const Text('â€”')
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
