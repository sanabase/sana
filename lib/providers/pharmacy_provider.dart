import 'dart:async';
import '../services/guest_identity_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pharmacy.dart';

class PharmacyProvider extends ChangeNotifier {
  final List<Pharmacy> _pharmacies = [];
  bool _isLoading = false;
  String? _userId;
  StreamSubscription<AuthState>? _authSubscription;
  int _loadGeneration = 0;

  List<Pharmacy> get pharmacies => List.unmodifiable(_pharmacies);
  bool get isLoading => _isLoading;
  String? get userId => _userId;
  SupabaseClient get _client => Supabase.instance.client;

  PharmacyProvider() {
    _userId = _client.auth.currentUser?.id;
    _authSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Pharmacy auth listener error: $error\n$stackTrace');
      },
    );
    if (_userId != null) {
      loadPharmacies();
    }
  }

  void _handleAuthStateChange(AuthState authState) {
    final newUserId = authState.session?.user.id;
    if (_userId == newUserId) return;

    _loadGeneration++;
    _userId = newUserId;
    _pharmacies.clear();
    notifyListeners();

    if (newUserId != null) {
      loadPharmacies();
    }
  }

  Future<void> loadPharmacies() async {
    final currentGen = _loadGeneration;
    final user = _client.auth.currentUser;
    if (user == null) {
      _pharmacies.clear();
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _client
          .from('pharmacies')
          .select()

          .order('name', ascending: true);

      if (currentGen != _loadGeneration) return;

      _pharmacies.clear();
      for (final item in response) {
        try {
          _pharmacies.add(Pharmacy.fromMap(Map<String, dynamic>.from(item)));
        } catch (e) {
          debugPrint('Error parsing pharmacy: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading pharmacies: $e');
    } finally {
      if (currentGen == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> addPharmacy(Pharmacy pharmacy) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final pharmMap = pharmacy.toMap();

      if (user.isAnonymous) {
        pharmMap['user_id'] = null;
        pharmMap['guest_id'] = GuestIdentityService.sharedGuestId;
      } else {
        pharmMap['user_id'] = user.id;
        pharmMap['guest_id'] = null;
      }

      final response =
          await _client.from('pharmacies').insert(pharmMap).select().single();
      final newPharmacy = Pharmacy.fromMap(Map<String, dynamic>.from(response));
      _pharmacies.insert(0, newPharmacy);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error adding pharmacy: $e');
      return false;
    }
  }

  Future<bool> deletePharmacy(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      await _client
          .from('pharmacies')
          .delete()
          .eq('id', id);
      _pharmacies.removeWhere((p) => p.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting pharmacy: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}


