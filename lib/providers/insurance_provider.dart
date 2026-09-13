import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/insurance_card.dart';

class InsuranceProvider extends ChangeNotifier {
  final List<InsuranceCard> _cards = [];

  bool _isLoading = false;
  String? _userId;

  StreamSubscription<AuthState>? _authSubscription;

  int _loadGeneration = 0;

  List<InsuranceCard> get cards => List.unmodifiable(_cards);

  bool get isLoading => _isLoading;

  String? get userId => _userId;

  SupabaseClient get _client => Supabase.instance.client;

  InsuranceProvider() {
    _userId = _client.auth.currentUser?.id;

    _authSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          'Insurance auth listener error: '
          '$error\n$stackTrace',
        );
      },
    );

    if (_userId != null) {
      loadCards();
    }
  }

  // ============================================================
  // AUTH
  // ============================================================

  void _handleAuthStateChange(
    AuthState authState,
  ) {
    final newUserId = authState.session?.user.id;

    if (_userId == newUserId) {
      return;
    }

    _loadGeneration++;

    _userId = newUserId;

    _cards.clear();

    notifyListeners();

    if (newUserId != null) {
      loadCards();
    }
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> loadCards() async {
    final currentGeneration = _loadGeneration;

    final user = _client.auth.currentUser;

    // ------------------------------------------------------------
    // Guest mode
    // ------------------------------------------------------------
    //
    // IMPORTANT:
    // The current insurance_cards table has no guest_id column.
    // Therefore guest cards cannot safely be loaded from Supabase
    // yet.
    //
    // We intentionally do NOT query all rows here.
    // That would risk exposing another user's records.
    //
    if (user == null) {
      _cards.clear();

      _isLoading = false;

      notifyListeners();

      return;
    }

    _isLoading = true;

    notifyListeners();

    try {
      final response = await _client
          .from('insurance_cards')
          .select(
            'id,'
            'user_id,'
            'provider_name,'
            'policy_number,'
            'front_image_url,'
            'back_image_url,'
            'created_at',
          )
          .eq(
            'user_id',
            user.id,
          )
          .order(
            'created_at',
            ascending: false,
          );

      if (currentGeneration != _loadGeneration) {
        return;
      }

      _cards.clear();

      for (final item in response) {
        try {
          final map = Map<String, dynamic>.from(
            item as Map,
          );

          _cards.add(
            InsuranceCard.fromMap(map),
          );
        } catch (error, stackTrace) {
          debugPrint(
            'Error parsing insurance card: '
            '$error\n$stackTrace',
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Error loading insurance cards: '
        '$error\n$stackTrace',
      );
    } finally {
      if (currentGeneration == _loadGeneration) {
        _isLoading = false;

        notifyListeners();
      }
    }
  }

  // ============================================================
  // ADD
  // ============================================================

  Future<bool> addCard(
    InsuranceCard card,
  ) async {
    final user = _client.auth.currentUser;

    // ------------------------------------------------------------
    // Guest mode
    // ------------------------------------------------------------
    //
    // Guest support is intentionally blocked here until the
    // database has a real guest_id ownership column and matching
    // RLS policy.
    //
    if (user == null) {
      debugPrint(
        'Cannot save insurance card: '
        'guest ownership is not configured in Supabase yet.',
      );

      return false;
    }

    try {
      // ----------------------------------------------------------
      // IMPORTANT:
      // Do NOT use card.toMap() here.
      //
      // toMap() contains UI/model compatibility keys such as:
      // providerName
      // policyNumber
      // frontImageUrl
      // backImageUrl
      //
      // Those are NOT database columns.
      //
      // Build the exact database payload instead.
      // ----------------------------------------------------------

      final cardId =
          card.id ?? DateTime.now().millisecondsSinceEpoch.toString();

      final createdAt = card.createdAt ?? DateTime.now().toIso8601String();

      final cardMap = <String, dynamic>{
        'id': cardId,
        'user_id': user.id,
        'provider_name': card.providerName,
        'policy_number': card.policyNumber,
        'front_image_url': card.frontImageUrl,
        'back_image_url': card.backImageUrl,
        'created_at': createdAt,
      };

      final response = await _client
          .from('insurance_cards')
          .insert(cardMap)
          .select(
            'id,'
            'user_id,'
            'provider_name,'
            'policy_number,'
            'front_image_url,'
            'back_image_url,'
            'created_at',
          )
          .single();

      final newCard = InsuranceCard.fromMap(
        Map<String, dynamic>.from(
          response,
        ),
      );

      _cards.insert(
        0,
        newCard,
      );

      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Error adding insurance card: '
        '$error\n$stackTrace',
      );

      return false;
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<bool> deleteCard(
    String id,
  ) async {
    final user = _client.auth.currentUser;

    // Guest records are not supported until
    // guest_id + guest RLS are implemented.
    if (user == null) {
      debugPrint(
        'Cannot delete insurance card: '
        'guest ownership is not configured.',
      );

      return false;
    }

    final trimmedId = id.trim();

    if (trimmedId.isEmpty) {
      return false;
    }

    try {
      await _client
          .from('insurance_cards')
          .delete()
          .eq(
            'id',
            trimmedId,
          )
          .eq(
            'user_id',
            user.id,
          );

      _cards.removeWhere(
        (card) => card.id == trimmedId,
      );

      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Error deleting insurance card: '
        '$error\n$stackTrace',
      );

      return false;
    }
  }

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> refreshCards() async {
    await loadCards();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;

    super.dispose();
  }
}
