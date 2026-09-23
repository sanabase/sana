import 'guest_identity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DataScopeMode {
  guest,
  activeUser,
  admin,
}

class DataScopeService {
  DataScopeService._();

  static final SupabaseClient _db = Supabase.instance.client;

  static DataScopeMode get mode {
    final user = _db.auth.currentUser;

    if (user == null || user.isAnonymous) {
      return DataScopeMode.guest;
    }

    final role = user.userMetadata?['role']?.toString().trim().toLowerCase();

    if (role == 'admin') {
      return DataScopeMode.admin;
    }

    return DataScopeMode.activeUser;
  }

  static bool get isGuest => mode == DataScopeMode.guest;

  static bool get isActiveUser => mode == DataScopeMode.activeUser;

  static bool get isAdmin => mode == DataScopeMode.admin;

  static String? get userId => _db.auth.currentUser?.id;

  static Future<String> ownerId() async {
    final user = _db.auth.currentUser;

    if (user == null) {
      throw StateError('No Supabase Auth session exists.');
    }

    return user.isAnonymous
        ? GuestIdentityService.sharedGuestId
        : user.id;
  }

  static Future<String?> guestId() async {
    final user = _db.auth.currentUser;

    if (user == null || !user.isAnonymous) {
      return null;
    }

    return GuestIdentityService.sharedGuestId;
  }

  static Future<Map<String, dynamic>> scope() async {
    final user = _db.auth.currentUser;

    if (user == null) {
      throw StateError('No Supabase Auth session exists.');
    }

    return {
      'mode': user.isAnonymous
          ? DataScopeMode.guest.name
          : isAdmin
              ? DataScopeMode.admin.name
              : DataScopeMode.activeUser.name,
      'user_id': user.isAnonymous ? null : user.id,
      'guest_id':
          user.isAnonymous ? GuestIdentityService.sharedGuestId : null,
    };
  }

  static Future<void> reset() async {}
}
