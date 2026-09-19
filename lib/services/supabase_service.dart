import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  // ===========================================================================
  // AUTHENTICATION
  // ===========================================================================

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      return await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
          'role': 'user',
          'is_active': false,
        },
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Supabase signUp error: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<AuthResponse> signIn(
    String email,
    String password,
  ) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Supabase signIn error: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (error, stackTrace) {
      debugPrint(
        'Supabase signOut error: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  static User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  static String? get currentUserId {
    return _supabase.auth.currentUser?.id;
  }

  static bool get isSignedIn {
    return _supabase.auth.currentSession != null;
  }

  // ===========================================================================
  // USER DATA
  // ===========================================================================

  static Future<Map<String, dynamic>?> getUserData(
    String userId,
  ) async {
    if (userId.trim().isEmpty) {
      return null;
    }

    try {
      final response =
          await _supabase.from('users').select().eq('id', userId).maybeSingle();

      if (response == null) {
        return null;
      }

      return Map<String, dynamic>.from(response);
    } catch (error, stackTrace) {
      debugPrint(
        'Get user data error: $error\n$stackTrace',
      );
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUserData() async {
    final userId = currentUserId;

    if (userId == null || userId.isEmpty) {
      return null;
    }

    return getUserData(userId);
  }

  static Future<List<Map<String, dynamic>>> fetchAllUsers() async {
    try {
      final response = await _supabase
          .from('users')
          .select(
            'id, name, email, phone, created_at, '
            'is_active, expiry_date, role',
          )
          .order(
            'created_at',
            ascending: false,
          );

      return List<Map<String, dynamic>>.from(response);
    } catch (error, stackTrace) {
      debugPrint(
        'Fetch all users error: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> updateUserActivation({
    required String userId,
    required bool isActive,
    DateTime? expiryDate,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError('User ID cannot be empty.');
    }

    try {
      await _supabase.from('users').update({
        'is_active': isActive,
        'expiry_date': expiryDate?.toIso8601String(),
      }).eq('id', userId);
    } catch (error, stackTrace) {
      debugPrint(
        'Update user activation error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<bool> isAdmin(String userId) async {
    if (userId.trim().isEmpty) {
      return false;
    }

    try {
      final response = await _supabase
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return false;
      }

      return response['role']?.toString().trim().toLowerCase() == 'admin';
    } catch (error, stackTrace) {
      debugPrint(
        'isAdmin error: $error\n$stackTrace',
      );
      return false;
    }
  }

  static Future<bool> isSubscriptionExpired(
    String userId,
  ) async {
    if (userId.trim().isEmpty) {
      return true;
    }

    try {
      final response = await _supabase
          .from('users')
          .select('expiry_date, is_active')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return true;
      }

      final isActive = response['is_active'] == true;

      if (!isActive) {
        return true;
      }

      final rawExpiry = response['expiry_date'];

      if (rawExpiry == null) {
        return true;
      }

      final expiryDate = DateTime.tryParse(
        rawExpiry.toString(),
      );

      if (expiryDate == null) {
        return true;
      }

      return !expiryDate.isAfter(DateTime.now());
    } catch (error, stackTrace) {
      debugPrint(
        'Subscription check error: '
        '$error\n$stackTrace',
      );
      return true;
    }
  }

  // ===========================================================================
  // GENERIC DATABASE OPERATIONS
  // ===========================================================================

  static Future<void> insert(
    String table,
    Map<String, dynamic> data,
  ) async {
    try {
      final cleanData = Map<String, dynamic>.from(data);

      await _supabase.from(table).insert(cleanData);
    } catch (error, stackTrace) {
      debugPrint(
        'Insert error [$table]: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> update(
    String table,
    Map<String, dynamic> data,
    String id,
  ) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }
    if (_supabase.auth.currentUser == null) {
      throw StateError('No Supabase Auth session exists.');
    }

    try {
      final cleanData = Map<String, dynamic>.from(data);

      await _supabase.from(table).update(cleanData).eq('id', id);
    } catch (error, stackTrace) {
      debugPrint(
        'Update error [$table/$id]: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> delete(
    String table,
    String id,
  ) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }
    if (_supabase.auth.currentUser == null) {
      throw StateError('No Supabase Auth session exists.');
    }

    try {
      await _supabase.from(table).delete().eq('id', id);
    } catch (error, stackTrace) {
      debugPrint(
        'Delete error [$table/$id]: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAll(
    String table,
  ) async {
    try {
      final response = await _supabase.from(table).select();

      return List<Map<String, dynamic>>.from(response);
    } catch (error, stackTrace) {
      debugPrint(
        'Fetch all error [$table]: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchFiltered(
    String table,
    String column,
    String value,
  ) async {
    if (value.trim().isEmpty) {
      return [];
    }

    try {
      final response = await _supabase.from(table).select().eq(column, value);

      return List<Map<String, dynamic>>.from(response);
    } catch (error, stackTrace) {
      debugPrint(
        'Fetch filtered error '
        '[$table/$column=$value]: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  // ===========================================================================
  // FILE / PHOTO STORAGE
  // ===========================================================================

  static Future<String> uploadPhoto(
    Uint8List bytes,
    String path,
  ) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Photo data cannot be empty.');
    }

    if (path.trim().isEmpty) {
      throw ArgumentError('Photo path cannot be empty.');
    }

    try {
      final storage = _supabase.storage.from('photos');

      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
        ),
      );

      return storage.getPublicUrl(path);
    } catch (error, stackTrace) {
      debugPrint(
        'Upload photo error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<String> uploadFile(
    Uint8List bytes,
    String path,
    String fileType,
  ) async {
    if (bytes.isEmpty) {
      throw ArgumentError('File data cannot be empty.');
    }

    if (path.trim().isEmpty) {
      throw ArgumentError('File path cannot be empty.');
    }

    try {
      final storage = _supabase.storage.from('documents');

      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: fileType,
        ),
      );

      return storage.getPublicUrl(path);
    } catch (error, stackTrace) {
      debugPrint(
        'Upload file error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<Uint8List?> downloadFile(
    String url,
  ) async {
    if (url.trim().isEmpty) {
      return null;
    }

    try {
      final uri = Uri.tryParse(url);

      if (uri == null) {
        return null;
      }

      final path = _extractStoragePath(uri);

      if (path == null || path.isEmpty) {
        return null;
      }

      try {
        return await _supabase.storage.from('photos').download(path);
      } catch (_) {
        try {
          return await _supabase.storage.from('documents').download(path);
        } catch (error, stackTrace) {
          debugPrint(
            'Storage download error: '
            '$error\n$stackTrace',
          );
          return null;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Download file error: '
        '$error\n$stackTrace',
      );
      return null;
    }
  }

  static String? _extractStoragePath(Uri uri) {
    final segments = uri.pathSegments;

    final objectIndex = segments.indexOf('object');

    if (objectIndex >= 0 && objectIndex + 2 < segments.length) {
      final remaining = segments.sublist(
        objectIndex + 2,
      );

      if (remaining.isNotEmpty) {
        return remaining.join('/');
      }
    }

    final publicIndex = segments.indexOf('public');

    if (publicIndex >= 0 && publicIndex + 2 < segments.length) {
      final remaining = segments.sublist(
        publicIndex + 2,
      );

      if (remaining.isNotEmpty) {
        return remaining.join('/');
      }
    }

    return null;
  }

  // ===========================================================================
  // ACTIVATION / EXPIRY NOTIFICATIONS
  // ===========================================================================

  static Future<void> sendActivationNotifications({
    required String userId,
    required String email,
    required String? phone,
    required DateTime expiryDate,
  }) async {
    try {
      final userName = await _getUserName(userId);

      final formattedDate = '${expiryDate.day.toString().padLeft(2, '0')}/'
          '${expiryDate.month.toString().padLeft(2, '0')}/'
          '${expiryDate.year}';

      const subject = 'SANA Account Activated';

      final body = '''
Dear $userName,

Your SANA account has been activated.

Subscription:
Status: Active
Expiry date: $formattedDate
Duration: 1 year

You can now use your SANA medical records
and medication reminder features.

SANA
''';

      await _sendEmail(
        email,
        subject,
        body,
      );

      if (phone != null && phone.trim().isNotEmpty) {
        await _sendSms(
          phone.trim(),
          'SANA: Your account is active until $formattedDate.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Activation notification error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<String> _getUserName(
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('users')
          .select('name')
          .eq('id', userId)
          .maybeSingle();

      return response?['name']?.toString() ?? 'User';
    } catch (_) {
      return 'User';
    }
  }

  static Future<void> _sendEmail(
    String to,
    String subject,
    String body,
  ) async {
    // Hook for Supabase Edge Function / email provider.
    debugPrint(
      'EMAIL -> $to | $subject\n$body',
    );
  }

  static Future<void> _sendSms(
    String phone,
    String message,
  ) async {
    // Hook for SMS provider.
    debugPrint(
      'SMS -> $phone | $message',
    );
  }

  // ===========================================================================
  // EXPIRY HELPERS
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> fetchUsersExpiringWithin(
    int days,
  ) async {
    if (days < 0) {
      throw ArgumentError(
        'Days cannot be negative.',
      );
    }

    try {
      final now = DateTime.now();

      final limit = now.add(
        Duration(days: days),
      );

      final response = await _supabase
          .from('users')
          .select(
            'id, name, email, phone, created_at, '
            'is_active, expiry_date, role',
          )
          .eq('is_active', true)
          .gte(
            'expiry_date',
            now.toIso8601String(),
          )
          .lte(
            'expiry_date',
            limit.toIso8601String(),
          )
          .order(
            'expiry_date',
            ascending: true,
          );

      return List<Map<String, dynamic>>.from(
        response,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Fetch expiring users error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchExpiredActiveUsers() async {
    try {
      final response = await _supabase
          .from('users')
          .select(
            'id, name, email, phone, created_at, '
            'is_active, expiry_date, role',
          )
          .eq('is_active', true)
          .lt(
            'expiry_date',
            DateTime.now().toIso8601String(),
          )
          .order(
            'expiry_date',
            ascending: true,
          );

      return List<Map<String, dynamic>>.from(
        response,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Fetch expired users error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> deactivateExpiredUsers() async {
    try {
      await _supabase
          .from('users')
          .update({
            'is_active': false,
          })
          .eq('is_active', true)
          .lt(
            'expiry_date',
            DateTime.now().toIso8601String(),
          );
    } catch (error, stackTrace) {
      debugPrint(
        'Deactivate expired users error: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  // ===========================================================================
  // RAW CLIENT ACCESS
  // ===========================================================================

  static SupabaseClient get client {
    return _supabase;
  }
}
