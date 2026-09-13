class InsuranceCard {
  final String? id;
  final String providerName;
  final String policyNumber;
  final String? frontImageUrl;
  final String? backImageUrl;
  final String? userId;
  final String? createdAt;

  const InsuranceCard({
    this.id,
    required this.providerName,
    required this.policyNumber,
    this.frontImageUrl,
    this.backImageUrl,
    this.userId,
    this.createdAt,
  });

  factory InsuranceCard.fromMap(Map<String, dynamic> map) {
    return InsuranceCard(
      id: _nullableString(map['id']),
      providerName: _stringValue(
        map['provider_name'] ??
            map['providerName'] ??
            map['provider'] ??
            map['name'] ??
            map['title'],
        fallback: 'Insurance Provider',
      ),
      policyNumber: _stringValue(
        map['policy_number'] ??
            map['policyNumber'] ??
            map['card_number'] ??
            map['cardNumber'] ??
            map['policyNo'],
        fallback: 'N/A',
      ),
      frontImageUrl: _nullableString(
        map['front_image_url'] ?? map['frontImageUrl'],
      ),
      backImageUrl: _nullableString(
        map['back_image_url'] ?? map['backImageUrl'],
      ),
      userId: _nullableString(
        map['user_id'] ?? map['userId'],
      ),
      createdAt: _nullableString(
        map['created_at'] ?? map['createdAt'],
      ),
    );
  }

  /// ONLY fields that actually belong to the Supabase
  /// insurance_cards table.
  Map<String, dynamic> toSupabaseMap({
    required String userId,
  }) {
    final map = <String, dynamic>{
      'provider_name': providerName,
      'policy_number': policyNumber,
      'front_image_url': frontImageUrl,
      'back_image_url': backImageUrl,
      'user_id': userId,
    };

    // Don't send id if Supabase generates it.
    if (id != null && id!.trim().isNotEmpty) {
      map['id'] = id;
    }

    if (createdAt != null && createdAt!.trim().isNotEmpty) {
      map['created_at'] = createdAt;
    }

    return map;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'provider_name': providerName,
      'policy_number': policyNumber,
      'front_image_url': frontImageUrl,
      'back_image_url': backImageUrl,
      'user_id': userId,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  InsuranceCard copyWith({
    String? id,
    String? providerName,
    String? policyNumber,
    String? frontImageUrl,
    String? backImageUrl,
    String? userId,
    String? createdAt,
  }) {
    return InsuranceCard(
      id: id ?? this.id,
      providerName: providerName ?? this.providerName,
      policyNumber: policyNumber ?? this.policyNumber,
      frontImageUrl: frontImageUrl ?? this.frontImageUrl,
      backImageUrl: backImageUrl ?? this.backImageUrl,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String _stringValue(
    dynamic value, {
    required String fallback,
  }) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      return fallback;
    }

    return result;
  }

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    return result.isEmpty ? null : result;
  }
}
