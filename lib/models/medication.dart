class Medication {
  final String id;
  final String userId;
  final String guestId;
  final String name;
  final String dosage;
  final String? reminderTime;
  final String? photoBase64;
  final String? ringtonePath;

  const Medication({
    required this.id,
    required this.userId,
    required this.guestId,
    required this.name,
    required this.dosage,
    this.reminderTime,
    this.photoBase64,
    this.ringtonePath,
  });

  factory Medication.fromMap(Map<String, dynamic> map) {
    return Medication(
      id: map['id']?.toString().trim() ?? '',
      userId: map['user_id']?.toString().trim() ??
          map['userId']?.toString().trim() ??
          '',
      guestId: map['guest_id']?.toString().trim() ??
          map['guestId']?.toString().trim() ??
          '',
      name: map['name']?.toString().trim() ?? '',
      dosage: map['dosage']?.toString().trim() ?? '',
      reminderTime: _nullableString(
        map['reminder_time'] ?? map['reminderTime'],
      ),
      photoBase64: _nullableString(
        map['photo_base64'] ?? map['photoBase64'],
      ),
      ringtonePath: _nullableString(
        map['ringtone_path'] ?? map['ringtonePath'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId.isEmpty ? null : userId,
      'guest_id': guestId.isEmpty ? null : guestId,
      'name': name,
      'dosage': dosage,
      'reminder_time': reminderTime,
      'photo_base64': photoBase64,
      'ringtone_path': ringtonePath,
    };
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'user_id': userId.isEmpty ? null : userId,
      'guest_id': guestId.isEmpty ? null : guestId,
      'name': name,
      'dosage': dosage,
      'reminder_time': reminderTime,
      'photo_base64': photoBase64,
      'ringtone_path': ringtonePath,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  Medication copyWith({
    String? id,
    String? userId,
    String? guestId,
    String? name,
    String? dosage,
    String? reminderTime,
    String? photoBase64,
    String? ringtonePath,
  }) {
    return Medication(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      guestId: guestId ?? this.guestId,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      reminderTime: reminderTime ?? this.reminderTime,
      photoBase64: photoBase64 ?? this.photoBase64,
      ringtonePath: ringtonePath ?? this.ringtonePath,
    );
  }

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    return result.isEmpty ? null : result;
  }
}
