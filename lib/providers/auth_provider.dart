import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/subscription_service.dart';
import '../services/guest_data_migration_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<AuthState>? _authSubscription;

  User? _currentUser;

  Map<String, dynamic>? _profile;

  Map<String, dynamic>? _subscription;

  bool _isLoading = false;
  bool _isInitialized = false;

  String? _errorMessage;

  User? get currentUser => _currentUser;

  User? get user => _currentUser;

  Map<String, dynamic>? get profile => _profile;

  Map<String, dynamic>? get subscription => _subscription;

  bool get isLoading => _isLoading;

  bool get isInitialized => _isInitialized;

  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _currentUser != null;

  bool get isGuest => !isAuthenticated || !isActive;

  bool get isLoggedIn => isAuthenticated;

  String get userId => _currentUser?.id ?? '';

  String get email => _currentUser?.email ?? '';

  String get name => _profile?['name']?.toString() ?? '';

  String get phone => _profile?['phone']?.toString() ?? '';

  String get role {
    final value = _profile?['role']?.toString().trim().toLowerCase();

    if (value == null || value.isEmpty) {
      return 'user';
    }

    return value;
  }

  bool get isAdmin => isAuthenticated && role == 'admin';

  bool get isActive {
    if (!isAuthenticated) {
      return false;
    }

    if (isAdmin) {
      return true;
    }

    return hasValidSubscription;
  }

  bool get hasValidSubscription {
    if (!isAuthenticated) {
      return false;
    }

    if (isAdmin) {
      return true;
    }

    final profileActive = _profile?['is_active'] == true;

    if (!profileActive) {
      return false;
    }

    return subscriptionStatus == 'active';
  }

  bool get subscriptionExpired {
    if (!isAuthenticated || isAdmin) {
      return false;
    }

    final expiry = expiryDate;

    if (expiry == null) {
      return false;
    }

    return !expiry.isAfter(
      DateTime.now().toUtc(),
    );
  }

  DateTime? get expiryDate {
    return _parseDate(
      _subscription?['expires_at'] ?? _profile?['expiry_date'],
    );
  }

  String get subscriptionStatus {
    if (isAdmin) {
      return 'admin';
    }

    final status = _subscription?['status']?.toString().trim().toLowerCase();

    final expiry = expiryDate;

    if (status == 'active') {
      if (expiry == null) {
        return 'pending';
      }

      if (expiry.isAfter(
        DateTime.now().toUtc(),
      )) {
        return 'active';
      }

      return 'expired';
    }

    if (expiry != null &&
        !expiry.isAfter(
          DateTime.now().toUtc(),
        )) {
      return 'expired';
    }

    return status == null || status.isEmpty ? 'pending' : status;
  }

  int? get daysRemaining {
    if (isAdmin) {
      return null;
    }

    final expiry = expiryDate;

    if (expiry == null) {
      return null;
    }

    final now = DateTime.now().toUtc();

    if (!expiry.isAfter(now)) {
      return 0;
    }

    return expiry.difference(now).inDays;
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _setLoading(true);
    _clearError();

    try {
      _currentUser = _supabase.auth.currentUser;

      _authSubscription ??= _supabase.auth.onAuthStateChange.listen(
        (AuthState state) {
          unawaited(
            _handleAuthStateChange(state),
          );
        },
        onError: (Object error) {
          debugPrint(
            'Auth state listener error: $error',
          );
        },
      );

      if (_currentUser != null) {
        await _loadAuthenticatedState();
      } else {
        _clearUserState();
      }

      _isInitialized = true;
    } catch (error, stackTrace) {
      debugPrint(
        'Auth initialization failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to initialize authentication.',
        ),
      );
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> _handleAuthStateChange(
    AuthState state,
  ) async {
    try {
      _currentUser = state.session?.user;

      if (_currentUser == null) {
        _clearUserState();
        notifyListeners();
        return;
      }

      await _loadAuthenticatedState();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Auth state handling failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to refresh account state.',
        ),
      );

      notifyListeners();
    }
  }

  Future<void> _loadAuthenticatedState() async {
    await loadProfile();
    await loadSubscription();
  }

  Future<bool> loadProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      _clearUserState();
      return false;
    }

    try {
      final response = await _supabase
          .from('users')
          .select(
            'id,'
            'name,'
            'email,'
            'phone,'
            'created_at,'
            'is_active,'
            'expiry_date,'
            'role',
          )
          .eq('id', user.id)
          .maybeSingle();

      _currentUser = user;

      if (response == null) {
        _profile = null;
        return false;
      }

      _profile = Map<String, dynamic>.from(
        response,
      );

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Load user profile failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to load user profile.',
        ),
      );

      return false;
    }
  }

  Future<bool> loadSubscription() async {
    if (!isAuthenticated) {
      _subscription = null;
      return false;
    }

    if (isAdmin) {
      _subscription = null;
      return true;
    }

    try {
      final result = await SubscriptionService.getCurrentSubscription();

      if (result == null) {
        _subscription = null;
        return false;
      }

      _subscription = Map<String, dynamic>.from(
        result,
      );

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Load subscription failed:\n'
        '$error\n$stackTrace',
      );

      _subscription = null;

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to load subscription.',
        ),
      );

      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty) {
      _setError('Email is required.');
      notifyListeners();
      return false;
    }

    if (password.isEmpty) {
      _setError('Password is required.');
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      // Capture anonymous identity before permanent login replaces it.
      final previousUser = _supabase.auth.currentUser;
      final previousGuestId =
          previousUser != null && previousUser.isAnonymous
              ? previousUser.id
              : null;

      final response = await _supabase.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      _currentUser = response.user;

      // Move guest records to the permanent account.
      if (previousGuestId != null && _currentUser != null) {
        await GuestDataMigrationService.transfer(
          guestId: previousGuestId,
          userId: _currentUser!.id,
        );
      }

      if (_currentUser == null) {
        _setError('Unable to sign in.');
        return false;
      }

      await _loadAuthenticatedState();

      return true;
    } on AuthException catch (error) {
      _setError(
        error.message.isNotEmpty ? error.message : 'Unable to sign in.',
      );

      return false;
    } catch (error, stackTrace) {
      debugPrint(
        'Sign in failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to sign in.',
        ),
      );

      return false;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    String name = '',
    String phone = '',
  }) async {
    final cleanEmail = email.trim();

    final cleanName = name.trim();

    final cleanPhone = phone.trim();

    if (cleanEmail.isEmpty) {
      _setError('Email is required.');
      notifyListeners();
      return false;
    }

    if (password.length < 6) {
      _setError(
        'Password must contain at least 6 characters.',
      );
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      final response = await _supabase.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {
          'name': cleanName,
          'phone': cleanPhone,
        },
      );

      _currentUser = response.user;

      if (_currentUser != null && response.session != null) {
        await _ensureUserProfile(
          user: _currentUser!,
          name: cleanName,
          phone: cleanPhone,
        );

        await _loadAuthenticatedState();
      }

      return true;
    } on AuthException catch (error) {
      _setError(
        error.message.isNotEmpty ? error.message : 'Unable to create account.',
      );

      return false;
    } catch (error, stackTrace) {
      debugPrint(
        'Sign up failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to create account.',
        ),
      );

      return false;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> _ensureUserProfile({
    required User user,
    required String name,
    required String phone,
  }) async {
    final existing = await _supabase
        .from('users')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      return;
    }

    await _supabase.from('users').insert({
      'id': user.id,
      'name': name,
      'email': user.email ?? '',
      'phone': phone,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_active': false,
      'expiry_date': null,
      'role': 'user',
    });
  }

  Future<void> signOut() async {
    _setLoading(true);
    _clearError();

    try {
      await _supabase.auth.signOut();
      _clearUserState();
    } on AuthException catch (error) {
      _setError(
        error.message.isNotEmpty ? error.message : 'Unable to sign out.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Sign out failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to sign out.',
        ),
      );
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<bool> refresh() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      _clearUserState();
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      _currentUser = user;

      await _loadAuthenticatedState();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Auth refresh failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to refresh account status.',
        ),
      );

      return false;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<bool> refreshAdminStatus() async {
    if (!isAuthenticated) {
      return false;
    }

    final loaded = await loadProfile();

    notifyListeners();

    return loaded && isAdmin;
  }

  Future<bool> resetPassword(
    String email,
  ) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty) {
      _setError('Email is required.');
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await _supabase.auth.resetPasswordForEmail(
        cleanEmail,
      );

      return true;
    } on AuthException catch (error) {
      _setError(
        error.message.isNotEmpty
            ? error.message
            : 'Unable to send password reset email.',
      );

      return false;
    } catch (error, stackTrace) {
      debugPrint(
        'Password reset failed:\n'
        '$error\n$stackTrace',
      );

      _setError(
        _cleanErrorMessage(
          error,
          fallback: 'Unable to send password reset email.',
        ),
      );

      return false;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  void _clearUserState() {
    _currentUser = null;
    _profile = null;
    _subscription = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  void _setError(String message) {
    _errorMessage = message;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _cleanErrorMessage(
    Object error, {
    required String fallback,
  }) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return fallback;
    }

    if (message.startsWith(
      'Exception: ',
    )) {
      return message.substring(
        'Exception: '.length,
      );
    }

    return message;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text)?.toUtc();
  }

  void reset() {
    _clearUserState();

    _isLoading = false;
    _isInitialized = false;
    _errorMessage = null;

    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;

    super.dispose();
  }
}

