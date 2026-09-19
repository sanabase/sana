import 'package:supabase_flutter/supabase_flutter.dart';

class GuestDataMigrationService {
  GuestDataMigrationService._();

  static final SupabaseClient _db = Supabase.instance.client;

  static const List<String> _tables = <String>[
    'medications',
    'doctors',
    'pharmacies',
    'documents',
    'insurance_cards',
  ];

  static Future<void> transfer({
    required String guestId,
    required String userId,
  }) async {
    if (guestId.isEmpty || userId.isEmpty || guestId == userId) {
      return;
    }

    for (final table in _tables) {
      try {
        await _db
            .from(table)
            .update({
              'user_id': userId,
              'guest_id': null,
            })
            .eq('guest_id', guestId);

        print('Guest transfer completed: $table');
      } catch (error) {
        print('Guest transfer skipped for $table: $error');
      }
    }
  }
}
