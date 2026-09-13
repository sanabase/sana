import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../providers/language_provider.dart';
import '../providers/medication_provider.dart';

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();

  DateTime _selectedDate = DateTime.now();

  String _repeatChoice = 'Daily';

  final List<String> _selectedTimes = ['8:00 AM'];

  Uint8List? _photoBytes;
  String? _photoName;

  bool _isSaving = false;

  static const List<String> _hourlyTimes = [
    '12:00 AM',
    '1:00 AM',
    '2:00 AM',
    '3:00 AM',
    '4:00 AM',
    '5:00 AM',
    '6:00 AM',
    '7:00 AM',
    '8:00 AM',
    '9:00 AM',
    '10:00 AM',
    '11:00 AM',
    '12:00 PM',
    '1:00 PM',
    '2:00 PM',
    '3:00 PM',
    '4:00 PM',
    '5:00 PM',
    '6:00 PM',
    '7:00 PM',
    '8:00 PM',
    '9:00 PM',
    '10:00 PM',
    '11:00 PM',
  ];

  // ============================================================
  // PHOTO
  // ============================================================

  Future<void> _pickPhoto() async {
    if (_isSaving) {
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty || !mounted) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        _showMessage(
          'The selected image could not be read.',
          isError: true,
        );
        return;
      }

      setState(() {
        _photoBytes = bytes;
        _photoName = file.name;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Could not pick medication photo: '
        '$error\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not select the medication photo.',
        isError: true,
      );
    }
  }

  // ============================================================
  // DATE
  // ============================================================

  Future<void> _pickDate() async {
    if (_isSaving) {
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _repeatChoice = 'Select Date';
    });
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _saveMedication() async {
    if (_isSaving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedTimes.isEmpty) {
      _showMessage(
        'Please select at least one reminder time.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // The current Medication model supports one String field
      // called reminderTime.
      //
      // Keep all selected times in that field separated by commas.
      final reminderTime = _selectedTimes.join(', ');

      // Convert selected image to Base64 because the current
      // Medication model uses photoBase64.
      String? photoBase64;

      if (_photoBytes != null && _photoBytes!.isNotEmpty) {
        photoBase64 = base64Encode(_photoBytes!);
      }

      final medication = Medication(
        id: DateTime.now().microsecondsSinceEpoch.toString(),

        // MedicationProvider can replace this with the
        // authenticated user's ID before saving.
        userId: '',

        // Empty guestId means the provider can handle it
        // according to the current authentication logic.
        guestId: '',

        name: _nameController.text.trim(),

        dosage: _dosageController.text.trim(),

        reminderTime: reminderTime,

        photoBase64: photoBase64,

        ringtonePath: null,
      );

      await context.read<MedicationProvider>().addMedication(medication);

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to save medication: '
        '$error\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to save medication. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  // ============================================================
  // PHOTO BUTTON TEXT
  // ============================================================

  String _photoButtonText(String fallback) {
    final name = _photoName;

    if (name == null || name.trim().isEmpty) {
      return fallback;
    }

    return name;
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>();

    final code = language.locale.languageCode;

    String title = 'Add Medication';
    String nameLabel = 'Medication Name *';
    String dosageLabel = 'Dosage (e.g. 500mg) *';
    String repeatLabel = 'Repeat Pattern';
    String dailyOpt = 'Daily';
    String dateOpt = 'Select Date';
    String timesLabel = 'Select Reminder Times';
    String photoBtn = 'Add Medicine Photo';
    String saveBtn = 'Save Medication';

    if (code == 'ar') {
      title = 'إضافة دواء';
      nameLabel = 'اسم الدواء *';
      dosageLabel = 'الجرعة (مثال 500 ملغ) *';
      repeatLabel = 'نمط التكرار';
      dailyOpt = 'يومياً';
      dateOpt = 'تحديد التاريخ';
      timesLabel = 'اختر أوقات التذكير';
      photoBtn = 'إضافة صورة الدواء';
      saveBtn = 'حفظ الدواء';
    } else if (code == 'es') {
      title = 'Añadir Medicamento';
      nameLabel = 'Nombre del Medicamento *';
      dosageLabel = 'Dosis (ej. 500mg) *';
      repeatLabel = 'Patrón de Repetición';
      dailyOpt = 'Diario';
      dateOpt = 'Seleccionar Fecha';
      timesLabel = 'Seleccionar Horarios';
      photoBtn = 'Añadir Foto del Medicamento';
      saveBtn = 'Guardar Medicamento';
    } else if (code == 'fr') {
      title = 'Ajouter un Médicament';
      nameLabel = 'Nom du Médicament *';
      dosageLabel = 'Dosage (ex. 500mg) *';
      repeatLabel = 'Répétition';
      dailyOpt = 'Quotidien';
      dateOpt = 'Sélectionner une Date';
      timesLabel = 'Horaires de Rappel';
      photoBtn = 'Ajouter Photo du Médicament';
      saveBtn = 'Enregistrer';
    } else if (code == 'de') {
      title = 'Medikament hinzufügen';
      nameLabel = 'Medikamentenname *';
      dosageLabel = 'Dosierung (z.B. 500mg) *';
      repeatLabel = 'Wiederholung';
      dailyOpt = 'Täglich';
      dateOpt = 'Datum Wählen';
      timesLabel = 'Erinnerungszeiten wählen';
      photoBtn = 'Medikamentenfoto hinzufügen';
      saveBtn = 'Speichern';
    } else if (code == 'tr') {
      title = 'İlaç Ekle';
      nameLabel = 'İlaç Adı *';
      dosageLabel = 'Doz (örn. 500mg) *';
      repeatLabel = 'Tekrar Düzeni';
      dailyOpt = 'Günlük';
      dateOpt = 'Tarih Seç';
      timesLabel = 'Hatırlatma Zamanlarını Seçin';
      photoBtn = 'İlaç Fotoğrafı Ekle';
      saveBtn = 'İlacı Kaydet';
    } else if (code == 'hi') {
      title = 'दवा जोड़ें';
      nameLabel = 'दवा का नाम *';
      dosageLabel = 'खुराक (जैसे 500mg) *';
      repeatLabel = 'दोहराव पैटर्न';
      dailyOpt = 'दैनिक';
      dateOpt = 'तिथि चुनें';
      timesLabel = 'रिमाइंडर समय चुनें';
      photoBtn = 'दवा की तस्वीर जोड़ें';
      saveBtn = 'दवा सहेजें';
    } else if (code == 'zh') {
      title = '添加药物';
      nameLabel = '药物名称 *';
      dosageLabel = '剂量（例如 500mg）*';
      repeatLabel = '重复模式';
      dailyOpt = '每天';
      dateOpt = '选择日期';
      timesLabel = '选择提醒时间';
      photoBtn = '添加药物照片';
      saveBtn = '保存药物';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --------------------------------------------------
              // NAME
              // --------------------------------------------------

              TextFormField(
                controller: _nameController,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: nameLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.medication,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Required';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 12),

              // --------------------------------------------------
              // DOSAGE
              // --------------------------------------------------

              TextFormField(
                controller: _dosageController,
                enabled: !_isSaving,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: dosageLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.straighten,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Required';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 16),

              // --------------------------------------------------
              // PHOTO
              // --------------------------------------------------

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _pickPhoto,
                      icon: const Icon(
                        Icons.camera_alt,
                        color: Colors.teal,
                      ),
                      label: Text(
                        _photoButtonText(photoBtn),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_photoBytes != null) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        _photoBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // --------------------------------------------------
              // REPEAT
              // --------------------------------------------------

              Text(
                repeatLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Center(
                        child: Text(dailyOpt),
                      ),
                      selected: _repeatChoice == 'Daily',
                      selectedColor: Colors.teal.shade100,
                      onSelected: _isSaving
                          ? null
                          : (selected) {
                              if (!selected) {
                                return;
                              }

                              setState(() {
                                _repeatChoice = 'Daily';
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: Center(
                        child: Text(
                          _repeatChoice == 'Select Date'
                              ? '${_selectedDate.day}/'
                                  '${_selectedDate.month}/'
                                  '${_selectedDate.year}'
                              : dateOpt,
                        ),
                      ),
                      selected: _repeatChoice == 'Select Date',
                      selectedColor: Colors.teal.shade100,
                      onSelected: _isSaving
                          ? null
                          : (_) {
                              _pickDate();
                            },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // --------------------------------------------------
              // REMINDER TIMES
              // --------------------------------------------------

              Text(
                timesLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _hourlyTimes.map(
                  (time) {
                    final selected = _selectedTimes.contains(time);

                    return FilterChip(
                      label: Text(time),
                      selected: selected,
                      selectedColor: Colors.teal.shade100,
                      checkmarkColor: Colors.teal,
                      onSelected: _isSaving
                          ? null
                          : (value) {
                              setState(() {
                                if (value) {
                                  if (!_selectedTimes.contains(time)) {
                                    _selectedTimes.add(time);
                                  }
                                } else {
                                  _selectedTimes.remove(time);
                                }
                              });
                            },
                    );
                  },
                ).toList(),
              ),

              const SizedBox(height: 24),

              // --------------------------------------------------
              // SAVE
              // --------------------------------------------------

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveMedication,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          saveBtn,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();

    super.dispose();
  }
}
