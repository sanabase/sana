import 'package:shared_preferences/shared_preferences.dart';

class GuestIdentityService {
  GuestIdentityService._();

  static const String _key = 'sana_guest_id';

  static Future<String> getGuestId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);

    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final guestId = 'guest-${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_key, guestId);
    return guestId;
  }
}
