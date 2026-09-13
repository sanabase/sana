import 'package:supabase_flutter/supabase_flutter.dart';

import 'guest_identity_service.dart';

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

    if (user == null) {
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

    if (user != null) {
      return user.id;
    }

    return GuestIdentityService.getGuestId();
  }

  static Future<String?> guestId() async {
    if (!isGuest) {
      return null;
    }

    return GuestIdentityService.getGuestId();
  }

  static Future<Map<String, dynamic>> scope() async {
    final user = _db.auth.currentUser;

    if (user == null) {
      final guestId = await GuestIdentityService.getGuestId();

      return {
        'mode': DataScopeMode.guest.name,
        'user_id': null,
        'guest_id': guestId,
      };
    }

    return {
      'mode':
          isAdmin ? DataScopeMode.admin.name : DataScopeMode.activeUser.name,
      'user_id': user.id,
      'guest_id': null,
    };
  }

  static Future<void> reset() async {}
}
