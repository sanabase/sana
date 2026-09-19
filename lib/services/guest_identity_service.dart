import 'package:supabase_flutter/supabase_flutter.dart';

class GuestIdentityService {
  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get isGuest => currentUser?.isAnonymous == true;

  static bool get isPermanentUser =>
      currentUser != null && currentUser!.isAnonymous == false;

  static Future<String?> get sharedGuestId async {
    final user = currentUser;

    if (user == null || !user.isAnonymous) {
      return null;
    }

    return user.id;
  }

  static Future<String> getGuestId() async {
    final user = currentUser;

    if (user == null) {
      throw StateError('No Supabase Auth session exists.');
    }

    if (!user.isAnonymous) {
      throw StateError(
        'Current Supabase user is permanent, not anonymous.',
      );
    }

    return user.id;
  }

  static Future<String> getGuestUserId() => getGuestId();

  static Future<String> ensureGuestUserId() => getGuestId();

  static Future<String> getUserId() => getGuestId();

  static Future<String> currentUserId() => getGuestId();

  static Future<String> getIdentity() => getGuestId();

  static Future<void> clear() async {
    await _client.auth.signOut();
  }
}
