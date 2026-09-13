import 'dart:async';

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

      final response = user == null
          ? await _client
              .from('doctors')
              .select()
              .isFilter('user_id', null)
              .order(
                'name',
                ascending: true,
              )
          : await _client
              .from('doctors')
              .select()
              .or(
                'user_id.is.null,user_id.eq.${user.id}',
              )
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

    try {
      // ----------------------------------------------------------
      // Guest:
      // Save as public doctor.
      //
      // Authenticated:
      // Save as user's private doctor.
      // ----------------------------------------------------------

      final doctorToSave = user == null
          ? doctor.copyWith(
              userId: '',
            )
          : doctor.copyWith(
              userId: user.id,
            );

      final doctorMap = doctorToSave.toMap();

      // Supabase uses NULL for public records.
      if (user == null) {
        doctorMap['user_id'] = null;
      } else {
        doctorMap['user_id'] = user.id;
      }

      final response =
          await _client.from('doctors').insert(doctorMap).select().single();

      final newDoctor = Doctor.fromMap(
        Map<String, dynamic>.from(response),
      );

      _doctors.insert(
        0,
        newDoctor,
      );

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

    try {
      final index = _doctors.indexWhere(
        (item) => item.id == doctor.id,
      );

      if (index < 0) {
        return false;
      }

      final existing = _doctors[index];

      // Normalize nullable userId.
      final existingUserId = existing.userId ?? '';

      // ----------------------------------------------------------
      // PERMISSION CHECK
      // ----------------------------------------------------------

      if (user == null) {
        // Guest can only update public doctors.
        if (existingUserId.isNotEmpty) {
          return false;
        }
      } else {
        // Authenticated user can update:
        //   - public doctors
        //   - their own private doctors
        //
        // Cannot update another user's private doctor.
        if (existingUserId.isNotEmpty && existingUserId != user.id) {
          return false;
        }
      }

      // ----------------------------------------------------------
      // DETERMINE OWNER
      // ----------------------------------------------------------

      final String saveUserId;

      if (user == null) {
        // Guest update stays public.
        saveUserId = '';
      } else if (existingUserId.isEmpty) {
        // Existing doctor is public.
        // Keep it public when updating.
        saveUserId = '';
      } else {
        // Existing doctor belongs to current user.
        saveUserId = user.id;
      }

      final doctorToSave = doctor.copyWith(
        userId: saveUserId,
      );

      final doctorMap = doctorToSave.toMap();

      // Convert empty userId to NULL for Supabase.
      if (saveUserId.isEmpty) {
        doctorMap['user_id'] = null;
      } else {
        doctorMap['user_id'] = saveUserId;
      }

      // ----------------------------------------------------------
      // UPDATE DATABASE
      // ----------------------------------------------------------

      await _client.from('doctors').update(doctorMap).eq(
            'id',
            doctor.id,
          );

      // ----------------------------------------------------------
      // UPDATE LOCAL LIST
      // ----------------------------------------------------------

      _doctors[index] = doctorToSave;

      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Error updating doctor: '
        '$error\n$stackTrace',
      );

      return false;
    }
  }

  // ============================================================
  // DELETE DOCTOR
  // ============================================================

  Future<bool> deleteDoctor(
    String id,
  ) async {
    final user = _currentUser;

    try {
      final index = _doctors.indexWhere(
        (doctor) => doctor.id == id,
      );

      if (index < 0) {
        return false;
      }

      final doctor = _doctors[index];

      // Normalize nullable userId.
      final doctorUserId = doctor.userId ?? '';

      // ----------------------------------------------------------
      // GUEST
      // Only public doctors can be deleted.
      // ----------------------------------------------------------

      if (user == null) {
        if (doctorUserId.isNotEmpty) {
          return false;
        }

        await _client
            .from('doctors')
            .delete()
            .eq(
              'id',
              id,
            )
            .isFilter(
              'user_id',
              null,
            );
      }

      // ----------------------------------------------------------
      // AUTHENTICATED USER
      //
      // Can delete:
      //   - public doctors
      //   - own private doctors
      //
      // Cannot delete another user's private doctor.
      // ----------------------------------------------------------

      else {
        // Public doctor.
        if (doctorUserId.isEmpty) {
          await _client
              .from('doctors')
              .delete()
              .eq(
                'id',
                id,
              )
              .isFilter(
                'user_id',
                null,
              );
        }

        // Own private doctor.
        else if (doctorUserId == user.id) {
          await _client
              .from('doctors')
              .delete()
              .eq(
                'id',
                id,
              )
              .eq(
                'user_id',
                user.id,
              );
        }

        // Another user's private doctor.
        else {
          return false;
        }
      }

      // Remove from local list only after successful database delete.
      _doctors.removeAt(index);

      notifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Error deleting doctor: '
        '$error\n$stackTrace',
      );

      return false;
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    _authSubscription?.cancel();

    super.dispose();
  }
}
