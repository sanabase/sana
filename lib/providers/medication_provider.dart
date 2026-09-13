import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/medication.dart';
import '../models/medication_log.dart';

class MedicationProvider extends ChangeNotifier {
  static const String _medicationsStorageKey = 'saved_medications_v2';

  static const String _logsStorageKey = 'saved_medication_logs_v2';

  final List<Medication> _medications = [];
  final List<MedicationLog> _logs = [];

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<AuthState>? _authSubscription;

  List<Medication> get medications => List.unmodifiable(_medications);

  List<MedicationLog> get logs => List.unmodifiable(_logs);

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  User? get _currentUser => _supabase?.auth.currentUser;

  MedicationProvider() {
    _authSubscription = _supabase?.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'Medication auth listener error: '
          '$error\n$stackTrace',
        );
      },
    );

    loadMedications();
  }

  // ============================================================
  // AUTH
  // ============================================================

  Future<void> _handleAuthStateChange(
    AuthState authState,
  ) async {
    _medications.clear();
    _logs.clear();
    _errorMessage = null;

    notifyListeners();

    await loadMedications();
  }

  // ============================================================
  // LOAD MEDICATIONS
  // ============================================================

  Future<void> loadMedications() async {
    if (_isLoading) {
      return;
    }

    _setLoading(true);
    _errorMessage = null;

    _medications.clear();
    _logs.clear();

    try {
      final client = _supabase;

      if (client == null) {
        await _loadLocalMedications();
        await _loadLocalLogs();
        return;
      }

      final user = _currentUser;

      if (user == null) {
        // Guest:
        // Only public medications.
        final response = await client
            .from('medications')
            .select()
            .isFilter('user_id', null)
            .order(
              'name',
              ascending: true,
            );

        _addMedications(
          response,
          userId: null,
        );
      } else {
        // Authenticated:
        // Public medications + own private medications.
        final response = await client
            .from('medications')
            .select()
            .or(
              'user_id.is.null,user_id.eq.${user.id}',
            )
            .order(
              'name',
              ascending: true,
            );

        _addMedications(
          response,
          userId: user.id,
        );
      }

      await _saveMedicationsToLocal();

      await _loadMedicationHistoryInternal(
        client,
      );

      await _saveLogsToLocal();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to load medications: '
        '$error\n$stackTrace',
      );

      _errorMessage = 'Unable to load medications.';

      _medications.clear();
      _logs.clear();

      await _loadLocalMedications();
      await _loadLocalLogs();
    } finally {
      _setLoading(false);
    }
  }

  void _addMedications(
    dynamic response, {
    required String? userId,
  }) {
    if (response is! List) {
      return;
    }

    for (final item in response) {
      if (item is! Map) {
        continue;
      }

      try {
        final medication = Medication.fromMap(
          Map<String, dynamic>.from(item),
        );

        if (medication.id.isEmpty) {
          continue;
        }

        // Guest: public only.
        if (userId == null) {
          if (medication.userId.isNotEmpty) {
            continue;
          }
        }

        // Authenticated: public OR own private.
        if (userId != null) {
          if (medication.userId.isNotEmpty && medication.userId != userId) {
            continue;
          }
        }

        final exists = _medications.any(
          (item) => item.id == medication.id,
        );

        if (!exists) {
          _medications.add(medication);
        }
      } catch (error) {
        debugPrint(
          'Invalid medication: $error',
        );
      }
    }
  }

  // ============================================================
  // ADD
  // ============================================================

  Future<void> addMedication(
    Medication medication,
  ) async {
    final client = _supabase;

    if (client == null) {
      throw StateError(
        'Supabase is not initialized.',
      );
    }

    final user = _currentUser;

    late Medication medicationToSave;

    if (user == null) {
      // Guest creates public medication.
      medicationToSave = medication.copyWith(
        userId: '',
      );
    } else {
      // Prevent assigning another user's ID.
      if (medication.userId.isNotEmpty && medication.userId != user.id) {
        throw StateError(
          'This medication belongs to another user.',
        );
      }

      medicationToSave = medication.copyWith(
        userId: medication.userId.isEmpty ? '' : user.id,
      );
    }

    try {
      await client.from('medications').upsert(
            medicationToSave.toSupabaseMap(),
            onConflict: 'id',
          );

      final index = _medications.indexWhere(
        (item) => item.id == medicationToSave.id,
      );

      if (index >= 0) {
        _medications[index] = medicationToSave;
      } else {
        _medications.insert(
          0,
          medicationToSave,
        );
      }

      await _saveMedicationsToLocal();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to add medication: '
        '$error\n$stackTrace',
      );

      _setError(
        'Unable to save the medication.',
      );

      rethrow;
    }
  }

  // ============================================================
  // UPDATE
  // ============================================================

  Future<void> updateMedication(
    Medication medication,
  ) async {
    final client = _supabase;

    if (client == null) {
      throw StateError(
        'Supabase is not initialized.',
      );
    }

    final index = _medications.indexWhere(
      (item) => item.id == medication.id,
    );

    if (index < 0) {
      throw StateError(
        'Medication was not found.',
      );
    }

    final existing = _medications[index];
    final user = _currentUser;

    // Guest can only edit public medication.
    if (user == null) {
      if (existing.userId.isNotEmpty) {
        throw StateError(
          'Private medications cannot be edited in guest mode.',
        );
      }

      final updated = medication.copyWith(
        userId: '',
      );

      await _updateMedication(
        client,
        updated,
        publicRecord: true,
      );

      return;
    }

    // Cannot edit another user's private medication.
    if (existing.userId.isNotEmpty && existing.userId != user.id) {
      throw StateError(
        'You cannot edit another user\'s medication.',
      );
    }

    final updated = medication.copyWith(
      userId: existing.userId.isEmpty ? '' : user.id,
    );

    await _updateMedication(
      client,
      updated,
      publicRecord: existing.userId.isEmpty,
    );
  }

  Future<void> _updateMedication(
    SupabaseClient client,
    Medication medication, {
    required bool publicRecord,
  }) async {
    _errorMessage = null;

    try {
      var query = client
          .from('medications')
          .update(
            medication.toSupabaseMap(),
          )
          .eq(
            'id',
            medication.id,
          );

      if (publicRecord) {
        query = query.isFilter(
          'user_id',
          null,
        );
      } else {
        final user = _currentUser;

        if (user == null) {
          throw StateError(
            'Authentication required.',
          );
        }

        query = query.eq(
          'user_id',
          user.id,
        );
      }

      await query;

      final index = _medications.indexWhere(
        (item) => item.id == medication.id,
      );

      if (index >= 0) {
        _medications[index] = medication;
      } else {
        _medications.insert(
          0,
          medication,
        );
      }

      await _saveMedicationsToLocal();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to update medication: '
        '$error\n$stackTrace',
      );

      _setError(
        'Unable to update the medication.',
      );

      rethrow;
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> deleteMedication(
    String id,
  ) async {
    final client = _supabase;

    if (client == null) {
      throw StateError(
        'Supabase is not initialized.',
      );
    }

    final index = _medications.indexWhere(
      (item) => item.id == id,
    );

    if (index < 0) {
      return;
    }

    final medication = _medications[index];
    final user = _currentUser;

    try {
      var query = client.from('medications').delete().eq(
            'id',
            id,
          );

      // Guest.
      if (user == null) {
        if (medication.userId.isNotEmpty) {
          throw StateError(
            'Private medications cannot be deleted in guest mode.',
          );
        }

        query = query.isFilter(
          'user_id',
          null,
        );
      }

      // Authenticated.
      else {
        if (medication.userId.isNotEmpty && medication.userId != user.id) {
          throw StateError(
            'You cannot delete another user\'s medication.',
          );
        }

        if (medication.userId.isEmpty) {
          query = query.isFilter(
            'user_id',
            null,
          );
        } else {
          query = query.eq(
            'user_id',
            user.id,
          );
        }
      }

      await query;

      _medications.removeAt(index);

      await _saveMedicationsToLocal();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to delete medication: '
        '$error\n$stackTrace',
      );

      _setError(
        'Unable to delete the medication.',
      );

      rethrow;
    }
  }

  // ============================================================
  // MEDICATION HISTORY
  // ============================================================

  Future<void> loadMedicationHistory() async {
    final client = _supabase;

    if (client == null) {
      await _loadLocalLogs();
      notifyListeners();
      return;
    }

    try {
      await _loadMedicationHistoryInternal(
        client,
      );

      await _saveLogsToLocal();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to load medication history: '
        '$error\n$stackTrace',
      );

      await _loadLocalLogs();

      notifyListeners();
    }
  }

  Future<void> _loadMedicationHistoryInternal(
    SupabaseClient client,
  ) async {
    _logs.clear();

    final medicationIds = _medications
        .map((medication) => medication.id)
        .where((id) => id.isNotEmpty)
        .toList();

    if (medicationIds.isEmpty) {
      return;
    }

    final response = await client
        .from('medication_logs')
        .select()
        .inFilter(
          'medication_id',
          medicationIds,
        )
        .order(
          'taken_at',
          ascending: false,
        );

    for (final item in response) {
      try {
        final log = MedicationLog.fromMap(
          Map<String, dynamic>.from(item),
        );

        _logs.add(log);
      } catch (error) {
        debugPrint(
          'Invalid medication log: $error',
        );
      }
    }
  }

  // ============================================================
  // RECORD STATUS
  // ============================================================

  Future<void> recordMedicationStatus({
    required Medication medication,
    required String status,
    DateTime? takenAt,
  }) async {
    final client = _supabase;

    if (client == null) {
      throw StateError(
        'Supabase is not initialized.',
      );
    }

    final normalizedStatus = status.trim().toLowerCase();

    if (normalizedStatus != 'taken' && normalizedStatus != 'not_taken') {
      throw ArgumentError(
        'Status must be "taken" or "not_taken".',
      );
    }

    final user = _currentUser;

    // Guest can only record public medication.
    if (user == null) {
      if (medication.userId.isNotEmpty) {
        throw StateError(
          'Private medication history cannot be changed in guest mode.',
        );
      }
    }

    // Authenticated user can record public or own medication.
    else {
      if (medication.userId.isNotEmpty && medication.userId != user.id) {
        throw StateError(
          'This medication belongs to another user.',
        );
      }
    }

    final log = MedicationLog(
      medicationId: medication.id,
      medicationName: medication.name,
      dosage: medication.dosage,
      status: normalizedStatus,
      takenAt: takenAt ?? DateTime.now(),
    );

    try {
      final response = await client
          .from('medication_logs')
          .insert(
            log.toMap(),
          )
          .select()
          .single();

      final savedLog = MedicationLog.fromMap(
        Map<String, dynamic>.from(response),
      );

      _logs.insert(
        0,
        savedLog,
      );

      await _saveLogsToLocal();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to record medication status: '
        '$error\n$stackTrace',
      );

      rethrow;
    }
  }

  Future<void> markTaken(
    Medication medication, {
    DateTime? takenAt,
  }) async {
    await recordMedicationStatus(
      medication: medication,
      status: 'taken',
      takenAt: takenAt,
    );
  }

  Future<void> markNotTaken(
    Medication medication, {
    DateTime? takenAt,
  }) async {
    await recordMedicationStatus(
      medication: medication,
      status: 'not_taken',
      takenAt: takenAt,
    );
  }

  // ============================================================
  // LOCAL MEDICATIONS
  // ============================================================

  Future<void> _loadLocalMedications() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data = prefs.getString(
            _medicationsStorageKey,
          ) ??
          prefs.getString(
            'saved_medications',
          );

      if (data == null || data.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(data);

      if (decoded is! List) {
        return;
      }

      final user = _currentUser;

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        try {
          final medication = Medication.fromMap(
            Map<String, dynamic>.from(item),
          );

          if (medication.id.isEmpty) {
            continue;
          }

          // Guest.
          if (user == null) {
            if (medication.userId.isNotEmpty) {
              continue;
            }
          }

          // Authenticated.
          else {
            if (medication.userId.isNotEmpty && medication.userId != user.id) {
              continue;
            }
          }

          final exists = _medications.any(
            (existing) => existing.id == medication.id,
          );

          if (!exists) {
            _medications.add(medication);
          }
        } catch (error) {
          debugPrint(
            'Invalid cached medication: $error',
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to load local medications: '
        '$error\n$stackTrace',
      );
    }
  }

  // ============================================================
  // LOCAL LOGS
  // ============================================================

  Future<void> _loadLocalLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data = prefs.getString(
        _logsStorageKey,
      );

      if (data == null || data.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(data);

      if (decoded is! List) {
        return;
      }

      _logs.clear();

      final medicationIds =
          _medications.map((medication) => medication.id).toSet();

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        try {
          final log = MedicationLog.fromMap(
            Map<String, dynamic>.from(item),
          );

          if (medicationIds.isNotEmpty &&
              !medicationIds.contains(
                log.medicationId,
              )) {
            continue;
          }

          _logs.add(log);
        } catch (error) {
          debugPrint(
            'Invalid cached medication log: $error',
          );
        }
      }

      _logs.sort(
        (a, b) => b.takenAt.compareTo(a.takenAt),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to load local logs: '
        '$error\n$stackTrace',
      );
    }
  }

  // ============================================================
  // SAVE MEDICATIONS
  // ============================================================

  Future<void> _saveMedicationsToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data =
          _medications.map((medication) => medication.toMap()).toList();

      await prefs.setString(
        _medicationsStorageKey,
        jsonEncode(data),
      );
    } catch (error) {
      debugPrint(
        'Failed to cache medications: $error',
      );
    }
  }

  // ============================================================
  // SAVE LOGS
  // ============================================================

  Future<void> _saveLogsToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data = _logs.map((log) => log.toMap()).toList();

      await prefs.setString(
        _logsStorageKey,
        jsonEncode(data),
      );
    } catch (error) {
      debugPrint(
        'Failed to cache medication logs: $error',
      );
    }
  }

  // ============================================================
  // STATE
  // ============================================================

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  // ============================================================
  // CLEAR LOCAL DATA
  // ============================================================

  Future<void> clearLocalData() async {
    _medications.clear();
    _logs.clear();

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(
      _medicationsStorageKey,
    );

    await prefs.remove(
      _logsStorageKey,
    );

    await prefs.remove(
      'saved_medications',
    );

    notifyListeners();
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
