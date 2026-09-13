//cat > lib/models/medical_document.dart <<'EOF'
class MedicalDocument {
  final String? id;
  final String? userId;
  final String? guestId;
  final String name;
  final String storagePath;
  final String fileUrl;
  final String fileType;
  final DateTime date;
  final DateTime createdAt;
  final bool isPublic;

  const MedicalDocument({
    this.id,
    this.userId,
    this.guestId,
    required this.name,
    required this.storagePath,
    required this.fileUrl,
    required this.fileType,
    required this.date,
    required this.createdAt,
    required this.isPublic,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'guest_id': guestId,
      'name': name,
      'storage_path': storagePath,
      'file_url': fileUrl,
      'file_type': fileType,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'is_public': isPublic,
    };
  }

  factory MedicalDocument.fromMap(Map<String, dynamic> map) {
    return MedicalDocument(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString(),
      guestId: map['guest_id']?.toString(),
      name: map['name']?.toString() ?? '',
      storagePath: map['storage_path']?.toString() ?? '',
      fileUrl: map['file_url']?.toString() ?? '',
      fileType: map['file_type']?.toString() ?? '',
      date: DateTime.tryParse(
            map['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      createdAt: DateTime.tryParse(
            map['created_at']?.toString() ?? '',
          ) ??
          DateTime.now(),
      isPublic: map['is_public'] == true,
    );
  }
}
