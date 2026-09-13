class Doctor {
  final String id;
  final String name;
  final String? specialty;
  final String? phone;
  final String? address;
  final String? userId;
  final String? guestId;

  const Doctor({
    required this.id,
    required this.name,
    this.specialty,
    this.phone,
    this.address,
    this.userId,
    this.guestId,
  });

  factory Doctor.fromMap(Map<String, dynamic> map) {
    return Doctor(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      specialty: _nullableString(
        map['specialty'] ?? map['speciality'],
      ),
      phone: _nullableString(
        map['phone'] ?? map['phoneNumber'],
      ),
      address: _nullableString(
        map['address'],
      ),
      userId: _nullableString(
        map['user_id'] ?? map['userId'],
      ),
      guestId: _nullableString(
        map['guest_id'] ?? map['guestId'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'specialty': specialty ?? '',
      'phone': phone ?? '',
      'address': address ?? '',
      'user_id': userId,
      'guest_id': guestId,
    };
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'name': name,
      'specialty': specialty,
      'phone': phone,
      'address': address,
      'user_id': userId,
      'guest_id': guestId,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  Doctor copyWith({
    String? id,
    String? name,
    String? specialty,
    String? phone,
    String? address,
    String? userId,
    String? guestId,
  }) {
    return Doctor(
      id: id ?? this.id,
      name: name ?? this.name,
      specialty: specialty ?? this.specialty,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      userId: userId ?? this.userId,
      guestId: guestId ?? this.guestId,
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
