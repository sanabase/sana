import 'package:supabase_flutter/supabase_flutter.dart';

class GuestIdentityService {
  /// Shared guest ID used by DataScopeService.
  /// With the new architecture, guest identity is the Supabase
  /// anonymous user's UUID. There is no local guest ID anymore.
  static Future<String?> get sharedGuestId async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return null;
    }

    return user.id;
  }

  /// Returns the Supabase guest UUID.
  static Future<String> getGuestId() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      throw StateError('No Supabase session exists for guest user');
    }

    return user.id;
  }

  /// Compatibility alias.
  static Future<String> getGuestUserId() async {
    return getGuestId();
  }

  /// Compatibility alias.
  static Future<String> ensureGuestUserId() async {
    return getGuestId();
  }

  /// Compatibility alias.
  static Future<String> getUserId() async {
    return getGuestId();
  }

  /// Compatibility alias.
  static Future<String> currentUserId() async {
    return getGuestId();
  }

  /// Compatibility alias.
  static Future<String> getIdentity() async {
    return getGuestId();
  }

  /// No local state exists to clear under the new architecture.
  /// Signing out of Supabase Auth is what invalidates a guest.
  static Future<void> clear() async {
    await Supabase.instance.client.auth.signOut();
  }
}
