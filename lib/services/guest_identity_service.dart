import 'package:supabase_flutter/supabase_flutter.dart';

class GuestIdentityService {
  static const String sharedGuestId =
      '00000000-0000-0000-0000-000000000001';

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get isGuest => currentUser?.isAnonymous == true;

  static bool get isPermanentUser =>
      currentUser != null && currentUser!.isAnonymous == false;

  static Future<String?> get sharedGuestIdForCurrentUser async {
    final user = currentUser;

    if (user == null || !user.isAnonymous) {
      return null;
    }

    return sharedGuestId;
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

    return sharedGuestId;
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
