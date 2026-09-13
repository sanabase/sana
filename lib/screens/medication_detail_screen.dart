import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/medication.dart';
import '../providers/language_provider.dart';
import '../providers/medication_provider.dart';

class MedicationDetailScreen extends StatelessWidget {
  final Medication medication;

  const MedicationDetailScreen({
    super.key,
    required this.medication,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>();
    final code = language.locale.languageCode;

    String title = 'Medication Details';
    String dosageLabel = 'Dosage';
    String reminderLabel = 'Reminder Time';
    String photoLabel = 'Medication Photo';
    String deleteButton = 'Delete Medication';
    String shareButton = 'Share Details';
    String noReminder = 'No reminder set';
    String noPhoto = 'No medication photo';
    String guestLabel = 'Public / Guest';
    String privateLabel = 'Private Medication';

    if (code == 'ar') {
      title = 'تفاصيل الدواء';
      dosageLabel = 'الجرعة';
      reminderLabel = 'وقت التذكير';
      photoLabel = 'صورة الدواء';
      deleteButton = 'حذف الدواء';
      shareButton = 'مشاركة التفاصيل';
      noReminder = 'لا يوجد تذكير';
      noPhoto = 'لا توجد صورة للدواء';
      guestLabel = 'عام / ضيف';
      privateLabel = 'دواء خاص';
    } else if (code == 'es') {
      title = 'Detalles del Medicamento';
      dosageLabel = 'Dosis';
      reminderLabel = 'Hora del Recordatorio';
      photoLabel = 'Foto del Medicamento';
      deleteButton = 'Eliminar Medicamento';
      shareButton = 'Compartir Detalles';
      noReminder = 'No hay recordatorio';
      noPhoto = 'No hay foto del medicamento';
      guestLabel = 'Público / Invitado';
      privateLabel = 'Medicamento Privado';
    } else if (code == 'fr') {
      title = 'Détails du Médicament';
      dosageLabel = 'Dosage';
      reminderLabel = 'Heure du Rappel';
      photoLabel = 'Photo du Médicament';
      deleteButton = 'Supprimer le Médicament';
      shareButton = 'Partager les Détails';
      noReminder = 'Aucun rappel défini';
      noPhoto = 'Aucune photo du médicament';
      guestLabel = 'Public / Invité';
      privateLabel = 'Médicament Privé';
    } else if (code == 'de') {
      title = 'Medikamentendetails';
      dosageLabel = 'Dosierung';
      reminderLabel = 'Erinnerungszeit';
      photoLabel = 'Medikamentenfoto';
      deleteButton = 'Medikament löschen';
      shareButton = 'Details teilen';
      noReminder = 'Keine Erinnerung festgelegt';
      noPhoto = 'Kein Medikamentenfoto';
      guestLabel = 'Öffentlich / Gast';
      privateLabel = 'Privates Medikament';
    } else if (code == 'tr') {
      title = 'İlaç Detayları';
      dosageLabel = 'Doz';
      reminderLabel = 'Hatırlatma Zamanı';
      photoLabel = 'İlaç Fotoğrafı';
      deleteButton = 'İlacı Sil';
      shareButton = 'Detayları Paylaş';
      noReminder = 'Hatırlatma ayarlanmadı';
      noPhoto = 'İlaç fotoğrafı yok';
      guestLabel = 'Genel / Misafir';
      privateLabel = 'Özel İlaç';
    } else if (code == 'hi') {
      title = 'दवा का विवरण';
      dosageLabel = 'खुराक';
      reminderLabel = 'रिमाइंडर समय';
      photoLabel = 'दवा की तस्वीर';
      deleteButton = 'दवा हटाएँ';
      shareButton = 'विवरण साझा करें';
      noReminder = 'कोई रिमाइंडर सेट नहीं है';
      noPhoto = 'दवा की कोई तस्वीर नहीं';
      guestLabel = 'सार्वजनिक / अतिथि';
      privateLabel = 'निजी दवा';
    } else if (code == 'zh') {
      title = '药物详情';
      dosageLabel = '剂量';
      reminderLabel = '提醒时间';
      photoLabel = '药物照片';
      deleteButton = '删除药物';
      shareButton = '分享详情';
      noReminder = '未设置提醒';
      noPhoto = '没有药物照片';
      guestLabel = '公开 / 访客';
      privateLabel = '私人药物';
    }

    final imageWidget = Semantics(
      label: photoLabel,
      child: _buildMedicationImage(
        context,
        noPhoto,
      ),
    );
    final reminderText = medication.reminderTime?.trim().isNotEmpty == true
        ? medication.reminderTime!.trim()
        : noReminder;

    final ownerText =
        medication.userId.trim().isEmpty ? guestLabel : privateLabel;

    final shareText = _buildShareText(
      reminderText: reminderText,
      ownerText: ownerText,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageWidget,
            const SizedBox(height: 20),
            Text(
              medication.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ownerText,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Divider(height: 30),
            _buildDetailTile(
              icon: Icons.medical_information,
              label: dosageLabel,
              value: medication.dosage.isEmpty ? 'N/A' : medication.dosage,
            ),
            _buildDetailTile(
              icon: Icons.access_time,
              label: reminderLabel,
              value: reminderText,
            ),
            if (medication.ringtonePath != null &&
                medication.ringtonePath!.trim().isNotEmpty)
              _buildDetailTile(
                icon: Icons.music_note,
                label: 'Ringtone',
                value: medication.ringtonePath!.trim(),
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.share),
                label: Text(
                  shareButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () async {
                  try {
                    await SharePlus.instance.share(
                      ShareParams(
                        text: shareText,
                      ),
                    );
                  } catch (error, stackTrace) {
                    debugPrint(
                      'Failed to share medication: '
                      '$error\n$stackTrace',
                    );

                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Unable to share medication details.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.delete),
                label: Text(
                  deleteButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  _confirmDelete(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MEDICATION IMAGE
  // ============================================================

  Widget _buildMedicationImage(
    BuildContext context,
    String noPhotoText,
  ) {
    final photoBase64 = medication.photoBase64?.trim();

    if (photoBase64 == null || photoBase64.isEmpty) {
      return _buildPlaceholder(
        noPhotoText,
      );
    }

    try {
      String base64Data = photoBase64;

      // Supports:
      // data:image/png;base64,....
      // data:image/jpeg;base64,....
      // or plain base64 strings.
      if (base64Data.contains(',')) {
        base64Data = base64Data.split(',').last;
      }

      final bytes = base64Decode(base64Data);

      if (bytes.isEmpty) {
        return _buildPlaceholder(
          noPhotoText,
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (
            context,
            error,
            stackTrace,
          ) {
            return _buildPlaceholder(
              noPhotoText,
            );
          },
        ),
      );
    } catch (error) {
      debugPrint(
        'Failed to decode medication photo: $error',
      );

      return _buildPlaceholder(
        noPhotoText,
      );
    }
  }

  // ============================================================
  // IMAGE PLACEHOLDER
  // ============================================================

  Widget _buildPlaceholder(
    String text,
  ) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.medication,
            size: 70,
            color: Colors.teal.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: Colors.teal.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DETAIL TILE
  // ============================================================

  Widget _buildDetailTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.teal,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHARE TEXT
  // ============================================================

  String _buildShareText({
    required String reminderText,
    required String ownerText,
  }) {
    return '''
SANA Medical Record

Medication: ${medication.name}
Dosage: ${medication.dosage.isEmpty ? 'N/A' : medication.dosage}
Reminder: $reminderText
Type: $ownerText
''';
  }

  // ============================================================
  // DELETE CONFIRMATION
  // ============================================================

  Future<void> _confirmDelete(
    BuildContext context,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete Medication?',
          ),
          content: Text(
            'Are you sure you want to delete '
            '"${medication.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await context.read<MedicationProvider>().deleteMedication(
            medication.id,
          );

      if (!context.mounted) {
        return;
      }

      Navigator.pop(
        context,
        true,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to delete medication: '
        '$error\n$stackTrace',
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to delete medication.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
