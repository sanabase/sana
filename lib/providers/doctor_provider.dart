import 'dart:async';
import '../services/guest_identity_service.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/doctor.dart';

class DoctorProvider extends ChangeNotifier {
  final List<Doctor> _doctors = [];

  bool _isLoading = false;
  String? _userId;

  StreamSubscription<AuthState>? _authSubscription;

  int _loadGeneration = 0;

  // ============================================================
  // GETTERS
  // ============================================================

  List<Doctor> get doctors => List.unmodifiable(_doctors);

  bool get isLoading => _isLoading;

  String? get userId => _userId;

  SupabaseClient get _client => Supabase.instance.client;

  User? get _currentUser => _client.auth.currentUser;

  // ============================================================
  // CONSTRUCTOR
  // ============================================================

  DoctorProvider() {
    _userId = _currentUser?.id;

    _authSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'Doctor auth listener error: '
          '$error\n$stackTrace',
        );
      },
    );

    loadDoctors();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  // ============================================================
  // AUTH STATE
  // ============================================================

  void _handleAuthStateChange(AuthState authState) {
    final newUserId = authState.session?.user.id;

    if (_userId == newUserId) {
      return;
    }

    // Invalidate any previous load operation.
    _loadGeneration++;

    _userId = newUserId;

    _doctors.clear();

    notifyListeners();

    loadDoctors();
  }

  // ============================================================
  // LOAD DOCTORS
  // ============================================================

  Future<void> loadDoctors() async {
    final currentGeneration = _loadGeneration;

    _isLoading = true;
    notifyListeners();

    try {
      final user = _currentUser;

      final response = await _client
          .from('doctors')
          .select()
          .order(
            'name',
            ascending: true,
          );

      // Ignore an old request if auth state changed while loading.
      if (currentGeneration != _loadGeneration) {
        return;
      }

      _doctors.clear();

      for (final item in response) {
        try {
          final doctor = Doctor.fromMap(
            Map<String, dynamic>.from(item),
          );

          // Ignore invalid records.
          if (doctor.id.isEmpty) {
            continue;
          }

          // Normalize nullable userId.
          final doctorUserId = doctor.userId ?? '';

          // ------------------------------------------------------
          // Guest
          // Only public doctors are allowed.
          // ------------------------------------------------------

          if (user == null) {
            if (doctorUserId.isNotEmpty) {
              continue;
            }
          }

          // ------------------------------------------------------
          // Authenticated user
          // Allow:
          //   - public doctors
          //   - this user's private doctors
          //
          // Reject another user's private doctor.
          // ------------------------------------------------------

          else {
            if (doctorUserId.isNotEmpty && doctorUserId != user.id) {
              continue;
            }
          }

          _doctors.add(doctor);
        } catch (error, stackTrace) {
          debugPrint(
            'Error parsing doctor: '
            '$error\n$stackTrace',
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Error loading doctors: '
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
  // ADD DOCTOR
  // ============================================================

  Future<bool> addDoctor(
    Doctor doctor,
  ) async {
    final user = _currentUser;

    if (user == null) {
      return false;
    }

    try {
      final doctorMap = doctor.toMap();

      if (user.isAnonymous) {
        doctorMap['user_id'] = null;
        doctorMap['guest_id'] = GuestIdentityService.sharedGuestId;
      } else {
        doctorMap['user_id'] = user.id;
        doctorMap['guest_id'] = null;
      }

      final response =
          await _client.from('doctors').insert(doctorMap).select().single();

      final newDoctor = Doctor.fromMap(
        Map<String, dynamic>.from(response),
      );

      _doctors.insert(0, newDoctor);
      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Error adding doctor: '
        '$error\n$stackTrace',
      );

      return false;
    }
  }
  // ============================================================
  // UPDATE DOCTOR
  // ============================================================

  Future<bool> updateDoctor(
    Doctor doctor,
  ) async {
    final user = _currentUser;

    if (user == null) {
      return false;
    }

    try {
      final doctorMap = doctor.toMap();

      if (user.isAnonymous) {
        doctorMap['user_id'] = null;
        doctorMap['guest_id'] = GuestIdentityService.sharedGuestId;
      } else {
        doctorMap['user_id'] = user.id;
        doctorMap['guest_id'] = null;
      }

      await _client
          .from('doctors')
          .update(doctorMap)
          .eq(
            'id',
            doctor.id,
          );

      final index = _doctors.indexWhere(
        (item) => item.id == doctor.id,
      );

      if (index >= 0) {
        _doctors[index] = doctor.copyWith(
          userId: user.isAnonymous ? null : user.id,
          guestId: user.isAnonymous ? user.id : '',
        );
      }

      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to update doctor: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }
  Future<bool> deleteDoctor(
    String id,
  ) async {
    final user = _currentUser;

    if (user == null) {
      return false;
    }

    try {
      await _client
          .from('doctors')
          .delete()
          .eq(
            'id',
            id,
          );

      _doctors.removeWhere(
        (doctor) => doctor.id == id,
      );

      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to delete doctor: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }



}


