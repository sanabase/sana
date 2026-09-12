.\fix_batch1_remaining.ps1# ============================================================
# SANA - Batch 1 fix-up: overwrite the 3 files that failed to
# patch due to line-ending differences. Direct write, no diff.
# Run from the root of your local sana repo (has pubspec.yaml).
# ============================================================
if (-not (Test-Path ".\pubspec.yaml")) {
  Write-Host "ERROR: run this from the root of your sana repo." -ForegroundColor Red
  exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- lib/app.dart ---
$appDart = @'
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_routes.dart';
import 'providers/settings_provider.dart';
import 'providers/language_provider.dart';

class sanaApp extends StatefulWidget {
  const sanaApp({super.key});

  @override
  State<sanaApp> createState() => _sanaAppState();
}

class _sanaAppState extends State<sanaApp> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, LanguageProvider>(
      builder: (context, settings, language, child) {
        return MaterialApp(
          title: 'SANA',
          debugShowCheckedModeBanner: false,
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue, brightness: Brightness.light),
            scaffoldBackgroundColor: Colors.white,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blueGrey, brightness: Brightness.dark),
            scaffoldBackgroundColor: Colors.black,
            useMaterial3: true,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: language.locale,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('fr'),
            Locale('es'),
            Locale('de'),
            Locale('tr'),
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return supportedLocales.first;
            for (final supported in supportedLocales) {
              if (supported.languageCode == locale.languageCode) {
                return supported;
              }
            }
            return supportedLocales.first;
          },
          initialRoute: AppRoutes.splash,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        );
      },
    );
  }
}
'@
[System.IO.File]::WriteAllText((Resolve-Path ".\lib\app.dart"), $appDart, $utf8NoBom)
Write-Host "app.dart written" -ForegroundColor Green

# --- lib/screens/home_screen.dart ---
$homeScreen = @'
﻿import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/language_provider.dart';
import '../providers/medication_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/document_provider.dart';
import '../providers/insurance_provider.dart';
import '../models/medication.dart';
import '../models/doctor.dart';
import '../models/pharmacy.dart';

import 'add_medication_screen.dart';
import 'medication_detail_screen.dart';
import 'documents_screen.dart';
import 'insurance_screen.dart';
import 'sharing_screen.dart';
import '../core/routes/app_routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  int _getInsuranceCount(BuildContext context) {
    try {
      final insProvider = Provider.of<InsuranceProvider>(context);
      return insProvider.cards.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openGetCopyLink(BuildContext context) async {
    const url =
        'https://link.payoneer.com/Token?t=CA1D522054524AC081ACCB17B5D8571B&src=pl';
    try {
      final uri = Uri.parse(url);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showCopyModal(context);
      }
    } catch (_) {
      if (context.mounted) {
        _showCopyModal(context);
      }
    }
  }

  void _showCopyModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Get Your Own Copy'),
        content: const Text(
          'Unlock the full source code and personal license for SANA.\n\nContact support or complete payment to receive your standalone copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildLangChip(
      BuildContext context, String langCode, String label, String activeCode) {
    final isSelected = langCode == activeCode;
    return Expanded(
      child: InkWell(
        onTap: () {
          Provider.of<LanguageProvider>(context, listen: false)
              .setLanguage(langCode);
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.teal.shade700,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.amber.shade700 : Colors.white38,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.teal.shade900 : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = Provider.of<LanguageProvider>(context);
    final code = language.locale.languageCode;

    final medProvider = Provider.of<MedicationProvider>(context);
    final docProvider = Provider.of<DoctorProvider>(context);
    final pharmProvider = Provider.of<PharmacyProvider>(context);
    final docuProvider = Provider.of<DocumentProvider>(context);
    final insuranceCount = _getInsuranceCount(context);

    String medLabel = 'Medications';
    String docLabel = 'Doctors';
    String pharmLabel = 'Pharmacies';
    String reminderLabel = 'Reminders';
    String docsLabel = 'Documents';
    String insuranceLabel = 'Insurance Cards';
    String shareLabel = 'Share Records';
    String activeText = 'Active';
    String selectText = 'Select';
    String subHeader = 'Your smart health';

    if (code == 'ar') {
      medLabel = 'الأدوية';
      docLabel = 'الأطباء';
      pharmLabel = 'الصيدليات';
      reminderLabel = 'التذكيرات';
      docsLabel = 'المستندات';
      insuranceLabel = 'بطاقات التأمين';
      shareLabel = 'مشاركة السجلات';
      activeText = 'نشط';
      selectText = 'تحديد';
      subHeader = 'صحتك الذكية';
    } else if (code == 'es') {
      medLabel = 'Medicamentos';
      docLabel = 'Médicos';
      pharmLabel = 'Farmacias';
      reminderLabel = 'Recordatorios';
      docsLabel = 'Documentos';
      insuranceLabel = 'Tarjetas de Seguro';
      shareLabel = 'Compartir';
      activeText = 'Activo';
      selectText = 'Seleccionar';
      subHeader = 'Tu salud inteligente';
    } else if (code == 'fr') {
      medLabel = 'Médicaments';
      docLabel = 'Médecins';
      pharmLabel = 'Pharmacies';
      reminderLabel = 'Rappels';
      docsLabel = 'Documents';
      insuranceLabel = 'Cartes d\'Assurance';
      shareLabel = 'Partager';
      activeText = 'Actif';
      selectText = 'Sélectionner';
      subHeader = 'Votre santé intelligente';
    } else if (code == 'de') {
      medLabel = 'Medikamente';
      docLabel = 'Ärzte';
      pharmLabel = 'Apotheken';
      reminderLabel = 'Erinnerungen';
      docsLabel = 'Dokumente';
      insuranceLabel = 'Versicherungskarten';
      shareLabel = 'Teilen';
      activeText = 'Aktiv';
      selectText = 'Auswählen';
      subHeader = 'Ihre intelligente Gesundheit';
    } else if (code == 'tr') {
      medLabel = 'İlaçlar';
      docLabel = 'Doktorlar';
      pharmLabel = 'Eczaneler';
      reminderLabel = 'Hatırlatıcılar';
      docsLabel = 'Belgeler';
      insuranceLabel = 'Sigorta Kartları';
      shareLabel = 'Paylaş';
      activeText = 'Aktif';
      selectText = 'Seç';
      subHeader = 'Akıllı sağlığınız';
    } else if (code == 'hi') {
      medLabel = 'दवाएं';
      docLabel = 'डॉक्टर';
      pharmLabel = 'फार्मेसी';
      reminderLabel = 'अनुस्मारक';
      docsLabel = 'दस्तावेज़';
      insuranceLabel = 'बीमा कार्ड';
      shareLabel = 'रिकॉर्ड साझा करें';
      activeText = 'सक्रिय';
      selectText = 'चुनें';
      subHeader = 'आपका स्मार्ट स्वास्थ्य';
    } else if (code == 'zh') {
      medLabel = '药物';
      docLabel = '医生';
      pharmLabel = '药房';
      reminderLabel = '提醒';
      docsLabel = '文档';
      insuranceLabel = '保险卡';
      shareLabel = '共享记录';
      activeText = '活动';
      selectText = '选择';
      subHeader = '您的智能健康';
    }

    String buttonText = '🔓 Get your own copy';
    if (code == 'ar') {
      buttonText = '🔓 احصل على نسختك الخاصة';
    } else if (code == 'de') {
      buttonText = '🔓 Holen Sie sich Ihre eigene Kopie';
    } else if (code == 'tr') {
      buttonText = '🔓 Kendi kopyanızı alın';
    } else if (code == 'hi') {
      buttonText = '🔓 अपनी खुद की प्रति प्राप्त करें';
    } else if (code == 'zh') {
      buttonText = '🔓 获取您自己的副本';
    } else if (code == 'es') {
      buttonText = '🔓 Obtén tu propia copia';
    } else if (code == 'fr') {
      buttonText = '🔓 Obtenez votre propre copie';
    }

    final items = [
      {
        'icon': Icons.medication,
        'label': medLabel,
        'count': medProvider.medications.length.toString(),
        'color': Colors.blue,
      },
      {
        'icon': Icons.person,
        'label': docLabel,
        'count': docProvider.doctors.length.toString(),
        'color': Colors.green,
      },
      {
        'icon': Icons.local_pharmacy,
        'label': pharmLabel,
        'count': pharmProvider.pharmacies.length.toString(),
        'color': Colors.orange,
      },
      {
        'icon': Icons.notifications_active,
        'label': reminderLabel,
        'count': activeText,
        'color': Colors.red,
      },
      {
        'icon': Icons.folder,
        'label': docsLabel,
        'count': docuProvider.documents.length.toString(),
        'color': Colors.purple,
      },
      {
        'icon': Icons.credit_card,
        'label': insuranceLabel,
        'count': insuranceCount.toString(),
        'color': Colors.indigo,
      },
      {
        'icon': Icons.share,
        'label': shareLabel,
        'count': selectText,
        'color': Colors.teal,
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        toolbarHeight: 52,
        automaticallyImplyLeading: false,
        titleSpacing: 2,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Row(
            children: [
              _buildLangChip(context, 'en', 'English', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'ar', 'العربية', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'es', 'Español', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'fr', 'Français', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'de', 'Deutsch', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'tr', 'Türkçe', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'hi', 'हिन्दी', code),
              const SizedBox(width: 2),
              _buildLangChip(context, 'zh', '中文', code),
            ],
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE0F2FE),
              Color(0xFFE0F7FA),
              Color(0xFFFFF8E1),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                    minWidth: constraints.maxWidth,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Health logo — far left of the header.
                              Icon(
                                Icons.health_and_safety_rounded,
                                size: 28,
                                color: Colors.teal.shade700,
                              ),
                              const SizedBox(width: 6),
                              // SANA badge, clickable link to the SANA site.
                              Expanded(
                                child: Center(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () async {
                                      final uri = Uri.parse(
                                          'https://malazhub.github.io/sana/');
                                      await launchUrl(uri,
                                          mode:
                                              LaunchMode.externalApplication);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                            color: Colors.amber.shade700,
                                            width: 1),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.amber.shade700
                                                .withValues(alpha: 0.15),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'SANA',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Icon(Icons.open_in_new,
                                              size: 13,
                                              color: Colors.amber.shade900),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.share,
                                    size: 22, color: Colors.teal.shade900),
                                tooltip: 'Share SANA',
                                onPressed: () {
                                  Share.share(
                                      'https://malazhub.github.io/sana/');
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.admin_panel_settings_outlined,
                                    size: 22, color: Colors.teal.shade900),
                                tooltip: 'Admin',
                                onPressed: () {
                                  Navigator.pushNamed(
                                      context, AppRoutes.admin);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Center(
                            child: Text(
                              subHeader,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: _buildHomeRow(
                                      context, items[0], items[1]),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _buildHomeRow(
                                      context, items[2], items[3]),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _buildHomeRow(
                                      context, items[4], items[5]),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _buildHomeCard(context, items[6]),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: () => _openGetCopyLink(context),
                              icon: const Icon(Icons.lock_open, size: 16),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  buttonText,
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHomeRow(
    BuildContext context,
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    return Row(
      children: [
        Expanded(child: _buildHomeCard(context, left)),
        const SizedBox(width: 8),
        Expanded(child: _buildHomeCard(context, right)),
      ],
    );
  }

  Widget _buildHomeCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final color = item['color'] as Color;
    final icon = item['icon'] as IconData;
    final label = item['label'] as String;
    final count = item['count'] as String;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (icon == Icons.medication) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MedicationListScreen()),
            );
          } else if (icon == Icons.person) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DoctorListScreen()),
            );
          } else if (icon == Icons.local_pharmacy) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PharmacyListScreen()),
            );
          } else if (icon == Icons.notifications_active) {
            _showReminderDialog(context);
          } else if (icon == Icons.folder) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DocumentsScreen()),
            );
          } else if (icon == Icons.credit_card) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InsuranceScreen()),
            );
          } else if (icon == Icons.share) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SharingScreen()),
            );
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReminderDialog(BuildContext context) {
    final medProvider = Provider.of<MedicationProvider>(context, listen: false);
    final language = Provider.of<LanguageProvider>(context, listen: false);
    final code = language.locale.languageCode;

    String title = 'Active Reminders';
    String noData = 'No active reminders.';
    String close = 'Close';

    if (code == 'ar') {
      title = 'التذكيرات النشطة';
      noData = 'لا توجد تذكيرات نشطة.';
      close = 'إغلاق';
    } else if (code == 'es') {
      title = 'Recordatorios Activos';
      noData = 'No hay recordatorios activos.';
      close = 'Cerrar';
    } else if (code == 'fr') {
      title = 'Rappels Actifs';
      noData = 'Aucun rappel actif.';
      close = 'Fermer';
    } else if (code == 'de') {
      title = 'Aktive Erinnerungen';
      noData = 'Keine aktiven Erinnerungen.';
      close = 'Schließen';
    } else if (code == 'tr') {
      title = 'Aktif Hatırlatıcılar';
      noData = 'Aktif hatırlatıcı yok.';
      close = 'Kapat';
    } else if (code == 'hi') {
      title = 'सक्रिय अनुस्मारक';
      noData = 'कोई सक्रिय अनुस्मारक नहीं।';
      close = 'बंद करें';
    } else if (code == 'zh') {
      title = '活动提醒';
      noData = '暂无活动提醒。';
      close = '关闭';
    }

    final alarms = <Map<String, dynamic>>[];
    for (final med in medProvider.medications) {
      for (final timeStr in med.reminderTimes) {
        alarms.add({'med': med, 'time': timeStr});
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: alarms.isEmpty
                ? Center(child: Text(noData))
                : ListView.builder(
                    itemCount: alarms.length,
                    itemBuilder: (context, index) {
                      final item = alarms[index];
                      final med = item['med'] as Medication;
                      final timeDisplay = item['time'] as String;

                      Widget leadAvatar;
                      if (med.photoUrl != null &&
                          med.photoUrl!.startsWith('data:image')) {
                        try {
                          final data = Uri.parse(med.photoUrl!).data;
                          if (data != null) {
                            leadAvatar = ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.memory(data.contentAsBytes(),
                                  width: 40, height: 40, fit: BoxFit.cover),
                            );
                          } else {
                            leadAvatar = const CircleAvatar(
                                backgroundColor: Colors.teal,
                                child: Icon(Icons.alarm, color: Colors.white));
                          }
                        } catch (_) {
                          leadAvatar = const CircleAvatar(
                              backgroundColor: Colors.teal,
                              child: Icon(Icons.alarm, color: Colors.white));
                        }
                      } else {
                        leadAvatar = const CircleAvatar(
                            backgroundColor: Colors.teal,
                            child: Icon(Icons.alarm, color: Colors.white));
                      }

                      return ListTile(
                        leading: leadAvatar,
                        title: Text(med.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$timeDisplay - Dosage: ${med.dosage}'),
                        trailing: IconButton(
                          tooltip: 'Enlarge / Inspect',
                          icon:
                              const Icon(Icons.visibility, color: Colors.teal),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MedicationDetailScreen(medication: med),
                              ),
                            );
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  MedicationDetailScreen(medication: med),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(close),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// MEDICATIONS LIST SCREEN
// ============================================================================

class MedicationListScreen extends StatelessWidget {
  const MedicationListScreen({super.key});

  String _formatRepeatType(String repeat, String code) {
    if (repeat == 'Daily') {
      if (code == 'ar') return 'يومياً';
      if (code == 'es') return 'Diario';
      if (code == 'fr') return 'Quotidien';
      if (code == 'de') return 'Täglich';
      if (code == 'tr') return 'Günlük';
      if (code == 'hi') return 'दैनिक';
      if (code == 'zh') return '每天';
    }
    return repeat;
  }

  @override
  Widget build(BuildContext context) {
    final medProvider = Provider.of<MedicationProvider>(context);
    final language = Provider.of<LanguageProvider>(context);
    final code = language.locale.languageCode;

    String title = 'Medications';
    String addBtn = '+ Add Medication';
    String emptyText = 'No medications added yet.';
    String dosageLbl = 'Dosage';
    String remindersLbl = 'Reminders';
    String repeatLbl = 'Repeat';

    if (code == 'ar') {
      title = 'الأدوية';
      addBtn = '+ إضافة دواء';
      emptyText = 'لم يتم إضافة أدوية بعد.';
      dosageLbl = 'الجرعة';
      remindersLbl = 'التذكيرات';
      repeatLbl = 'التكرار';
    } else if (code == 'es') {
      title = 'Medicamentos';
      addBtn = '+ Añadir Medicamento';
      emptyText = 'Aún no se han añadido medicamentos.';
      dosageLbl = 'Dosis';
      remindersLbl = 'Recordatorios';
      repeatLbl = 'Repetir';
    } else if (code == 'fr') {
      title = 'Médicaments';
      addBtn = '+ Ajouter un Médicament';
      emptyText = 'Aucun médicament ajouté pour le moment.';
      dosageLbl = 'Dosage';
      remindersLbl = 'Rappels';
      repeatLbl = 'Répétition';
    } else if (code == 'de') {
      title = 'Medikamente';
      addBtn = '+ Medikament hinzufügen';
      emptyText = 'Noch keine Medikamente hinzugefügt.';
      dosageLbl = 'Dosierung';
      remindersLbl = 'Erinnerungen';
      repeatLbl = 'Wiederholung';
    } else if (code == 'tr') {
      title = 'İlaçlar';
      addBtn = '+ İlaç Ekle';
      emptyText = 'Henüz ilaç eklenmedi.';
      dosageLbl = 'Doz';
      remindersLbl = 'Hatırlatıcılar';
      repeatLbl = 'Tekrar';
    } else if (code == 'hi') {
      title = 'दवाएं';
      addBtn = '+ दवा जोड़ें';
      emptyText = 'अभी तक कोई दवा नहीं जोड़ी गई है।';
      dosageLbl = 'खुराक';
      remindersLbl = 'अनुस्मारक';
      repeatLbl = 'दोहराना';
    } else if (code == 'zh') {
      title = '药物';
      addBtn = '+ 添加药物';
      emptyText = '尚未添加药物。';
      dosageLbl = '剂量';
      remindersLbl = '提醒';
      repeatLbl = '重复';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(addBtn),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddMedicationScreen(),
            ),
          );
        },
      ),
      body: medProvider.medications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medication, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    emptyText,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: medProvider.medications.length,
              itemBuilder: (context, index) {
                final med = medProvider.medications[index];
                final repeatText = _formatRepeatType(med.repeatType, code);

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: const Icon(Icons.medication, color: Colors.blue),
                    ),
                    title: Text(
                      med.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('$dosageLbl: ${med.dosage}'),
                        if (med.reminderTimes.isNotEmpty)
                          Text(
                              '$remindersLbl: ${med.reminderTimes.join(", ")}'),
                        Text('$repeatLbl: $repeatText'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Enlarge / Inspect',
                          icon:
                              const Icon(Icons.visibility, color: Colors.teal),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MedicationDetailScreen(medication: med),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            medProvider.deleteMedication(med.id);
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MedicationDetailScreen(medication: med),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// DOCTORS LIST SCREEN
// ============================================================================

class DoctorListScreen extends StatelessWidget {
  const DoctorListScreen({super.key});

  void _showEnlargedDoctor(BuildContext context, Doctor doc, String code) {
    String specLbl = 'Specialty';
    String phoneLbl = 'Phone Number';
    String callBtn = 'Call Doctor';
    String closeBtn = 'Close';

    if (code == 'ar') {
      specLbl = 'التخصص';
      phoneLbl = 'رقم الهاتف';
      callBtn = 'اتصال بالطبيب';
      closeBtn = 'إغلاق';
    } else if (code == 'es') {
      specLbl = 'Especialidad';
      phoneLbl = 'Teléfono';
      callBtn = 'Llamar al Médico';
      closeBtn = 'Cerrar';
    } else if (code == 'fr') {
      specLbl = 'Spécialité';
      phoneLbl = 'Téléphone';
      callBtn = 'Appeler le Médecin';
      closeBtn = 'Fermer';
    } else if (code == 'de') {
      specLbl = 'Fachgebiet';
      phoneLbl = 'Telefonnummer';
      callBtn = 'Arzt Anrufen';
      closeBtn = 'Schließen';
    } else if (code == 'tr') {
      specLbl = 'Uzmanlık';
      phoneLbl = 'Telefon Numarası';
      callBtn = 'Doktoru Ara';
      closeBtn = 'Kapat';
    } else if (code == 'hi') {
      specLbl = 'विशेषता';
      phoneLbl = 'फ़ोन नंबर';
      callBtn = 'डॉक्टर को कॉल करें';
      closeBtn = 'बंद करें';
    } else if (code == 'zh') {
      specLbl = '专业';
      phoneLbl = '电话号码';
      callBtn = '呼叫医生';
      closeBtn = '关闭';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.teal,
              child: Icon(Icons.person, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                doc.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 20),
            if (doc.specialty != null && doc.specialty!.isNotEmpty) ...[
              Text(specLbl,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(doc.specialty!,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
            ],
            if (doc.phone != null && doc.phone!.isNotEmpty) ...[
              Text(phoneLbl,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('${doc.phone}',
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.teal,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
            ],
          ],
        ),
        actions: [
          if (doc.phone != null && doc.phone!.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.phone),
              label: Text(callBtn),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () async {
                final uri = Uri.parse('tel:${doc.phone}');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(closeBtn),
          ),
        ],
      ),
    );
  }

  void _showAddDoctorDialog(BuildContext context, String code) {
    final nameCtrl = TextEditingController();
    final specCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    String dialogTitle = 'Add Doctor';
    String nameLabel = 'Doctor Name *';
    String specLabel = 'Specialty';
    String phoneLabel = 'Phone Number';
    String cancelLabel = 'Cancel';
    String saveLabel = 'Save';

    if (code == 'ar') {
      dialogTitle = 'إضافة طبيب';
      nameLabel = 'اسم الطبيب *';
      specLabel = 'التخصص';
      phoneLabel = 'رقم الهاتف';
      cancelLabel = 'إلغاء';
      saveLabel = 'حفظ';
    } else if (code == 'es') {
      dialogTitle = 'Añadir Médico';
      nameLabel = 'Nombre del Médico *';
      specLabel = 'Especialidad';
      phoneLabel = 'Teléfono';
      cancelLabel = 'Cancelar';
      saveLabel = 'Guardar';
    } else if (code == 'fr') {
      dialogTitle = 'Ajouter un Médecin';
      nameLabel = 'Nom du Médecin *';
      specLabel = 'Spécialité';
      phoneLabel = 'Téléphone';
      cancelLabel = 'Annuler';
      saveLabel = 'Enregistrer';
    } else if (code == 'de') {
      dialogTitle = 'Arzt hinzufügen';
      nameLabel = 'Name des Arztes *';
      specLabel = 'Fachgebiet';
      phoneLabel = 'Telefonnummer';
      cancelLabel = 'Abbrechen';
      saveLabel = 'Speichern';
    } else if (code == 'tr') {
      dialogTitle = 'Doktor Ekle';
      nameLabel = 'Doktor Adı *';
      specLabel = 'Uzmanlık';
      phoneLabel = 'Telefon Numarası';
      cancelLabel = 'İptal';
      saveLabel = 'Kaydet';
    } else if (code == 'hi') {
      dialogTitle = 'डॉक्टर जोड़ें';
      nameLabel = 'डॉक्टर का नाम *';
      specLabel = 'विशेषता';
      phoneLabel = 'फ़ोन नंबर';
      cancelLabel = 'रद्द करें';
      saveLabel = 'सहेजें';
    } else if (code == 'zh') {
      dialogTitle = '添加医生';
      nameLabel = '医生姓名 *';
      specLabel = '专业';
      phoneLabel = '电话号码';
      cancelLabel = '取消';
      saveLabel = '保存';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dialogTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: nameLabel),
              ),
              TextField(
                controller: specCtrl,
                decoration: InputDecoration(labelText: specLabel),
              ),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(labelText: phoneLabel),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                final newDoc = Doctor(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  specialty: specCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                );
                Provider.of<DoctorProvider>(context, listen: false)
                    .addDoctor(newDoc);
                Navigator.pop(ctx);
              }
            },
            child: Text(saveLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = Provider.of<DoctorProvider>(context);
    final language = Provider.of<LanguageProvider>(context);
    final code = language.locale.languageCode;

    String title = 'Doctors';
    String addBtn = '+ Add Doctor';
    String emptyText = 'No doctors added yet.';
    String specLbl = 'Specialty';

    if (code == 'ar') {
      title = 'الأطباء';
      addBtn = '+ إضافة طبيب';
      emptyText = 'لم يتم إضافة أطباء بعد.';
      specLbl = 'التخصص';
    } else if (code == 'es') {
      title = 'Médicos';
      addBtn = '+ Añadir Médico';
      emptyText = 'Aún no se han añadido médicos.';
      specLbl = 'Especialidad';
    } else if (code == 'fr') {
      title = 'Médecins';
      addBtn = '+ Ajouter un Médecin';
      emptyText = 'Aucun médecin ajouté pour le moment.';
      specLbl = 'Spécialité';
    } else if (code == 'de') {
      title = 'Ärzte';
      addBtn = '+ Arzt hinzufügen';
      emptyText = 'Noch keine Ärzte hinzugefügt.';
      specLbl = 'Fachgebiet';
    } else if (code == 'tr') {
      title = 'Doktorlar';
      addBtn = '+ Doktor Ekle';
      emptyText = 'Henüz doktor eklenmedi.';
      specLbl = 'Uzmanlık';
    } else if (code == 'hi') {
      title = 'डॉक्टर';
      addBtn = '+ डॉक्टर जोड़ें';
      emptyText = 'अभी तक कोई डॉक्टर नहीं जोड़ा गया है।';
      specLbl = 'विशेषता';
    } else if (code == 'zh') {
      title = '医生';
      addBtn = '+ 添加医生';
      emptyText = '尚未添加医生。';
      specLbl = '专业';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(addBtn),
        onPressed: () => _showAddDoctorDialog(context, code),
      ),
      body: docProvider.doctors.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    emptyText,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docProvider.doctors.length,
              itemBuilder: (context, index) {
                final doc = docProvider.doctors[index];
                final spec = doc.specialty;
                final phone = doc.phone;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: const Icon(Icons.person, color: Colors.green),
                    ),
                    title: Text(
                      doc.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (spec != null && spec.isNotEmpty)
                          Text('$specLbl: $spec'),
                        if (phone != null && phone.isNotEmpty) Text('$phone'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Call Doctor',
                          icon: const Icon(Icons.phone, color: Colors.green),
                          onPressed: () async {
                            if (phone != null && phone.isNotEmpty) {
                              final uri = Uri.parse('tel:$phone');
                              if (await canLaunchUrl(uri)) await launchUrl(uri);
                            } else {
                              _showEnlargedDoctor(context, doc, code);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            docProvider.deleteDoctor(doc.id);
                          },
                        ),
                      ],
                    ),
                    onTap: () => _showEnlargedDoctor(context, doc, code),
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// PHARMACIES LIST SCREEN
// ============================================================================

class PharmacyListScreen extends StatelessWidget {
  const PharmacyListScreen({super.key});

  void _showEnlargedPharmacy(
      BuildContext context, Pharmacy pharm, String code) {
    String addrLbl = 'Address';
    String phoneLbl = 'Phone Number';
    String callBtn = 'Call Pharmacy';
    String closeBtn = 'Close';

    if (code == 'ar') {
      addrLbl = 'العنوان';
      phoneLbl = 'رقم الهاتف';
      callBtn = 'اتصال بالصيدلية';
      closeBtn = 'إغلاق';
    } else if (code == 'es') {
      addrLbl = 'Dirección';
      phoneLbl = 'Teléfono';
      callBtn = 'Llamar a la Farmacia';
      closeBtn = 'Cerrar';
    } else if (code == 'fr') {
      addrLbl = 'Adresse';
      phoneLbl = 'Téléphone';
      callBtn = 'Appeler la Pharmacie';
      closeBtn = 'Fermer';
    } else if (code == 'de') {
      addrLbl = 'Adresse';
      phoneLbl = 'Telefonnummer';
      callBtn = 'Apotheke Anrufen';
      closeBtn = 'Schließen';
    } else if (code == 'tr') {
      addrLbl = 'Adres';
      phoneLbl = 'Telefon Numarası';
      callBtn = 'Eczaneyi Ara';
      closeBtn = 'Kapat';
    } else if (code == 'hi') {
      addrLbl = 'पता';
      phoneLbl = 'फ़ोन नंबर';
      callBtn = 'फार्मेसी को कॉल करें';
      closeBtn = 'बंद करें';
    } else if (code == 'zh') {
      addrLbl = '地址';
      phoneLbl = '电话号码';
      callBtn = '呼叫药房';
      closeBtn = '关闭';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.orange,
              child: Icon(Icons.local_pharmacy, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pharm.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 20),
            if (pharm.address != null && pharm.address!.isNotEmpty) ...[
              Text(addrLbl,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('${pharm.address!}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
            ],
            if (pharm.phone != null && pharm.phone!.isNotEmpty) ...[
              Text(phoneLbl,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('${pharm.phone!}',
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.teal,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
            ],
          ],
        ),
        actions: [
          if (pharm.phone != null && pharm.phone!.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.phone),
              label: Text(callBtn),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () async {
                final uri = Uri.parse('tel:${pharm.phone}');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(closeBtn),
          ),
        ],
      ),
    );
  }

  void _showAddPharmacyDialog(BuildContext context, String code) {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    String dialogTitle = 'Add Pharmacy';
    String nameLabel = 'Pharmacy Name *';
    String addrLabel = 'Address';
    String phoneLabel = 'Phone Number';
    String cancelLabel = 'Cancel';
    String saveLabel = 'Save';

    if (code == 'ar') {
      dialogTitle = 'إضافة صيدلية';
      nameLabel = 'اسم الصيدلية *';
      addrLabel = 'العنوان';
      phoneLabel = 'رقم الهاتف';
      cancelLabel = 'إلغاء';
      saveLabel = 'حفظ';
    } else if (code == 'es') {
      dialogTitle = 'Añadir Farmacia';
      nameLabel = 'Nombre de la Farmacia *';
      addrLabel = 'Dirección';
      phoneLabel = 'Teléfono';
      cancelLabel = 'Cancelar';
      saveLabel = 'Guardar';
    } else if (code == 'fr') {
      dialogTitle = 'Ajouter une Pharmacie';
      nameLabel = 'Nom de la Pharmacie *';
      addrLabel = 'Adresse';
      phoneLabel = 'Téléphone';
      cancelLabel = 'Annuler';
      saveLabel = 'Enregistrer';
    } else if (code == 'de') {
      dialogTitle = 'Apotheke hinzufügen';
      nameLabel = 'Name der Apotheke *';
      addrLabel = 'Adresse';
      phoneLabel = 'Telefonnummer';
      cancelLabel = 'Abbrechen';
      saveLabel = 'Speichern';
    } else if (code == 'tr') {
      dialogTitle = 'Eczane Ekle';
      nameLabel = 'Eczane Adı *';
      addrLabel = 'Adres';
      phoneLabel = 'Telefon Numarası';
      cancelLabel = 'İptal';
      saveLabel = 'Kaydet';
    } else if (code == 'hi') {
      dialogTitle = 'फार्मेसी जोड़ें';
      nameLabel = 'फार्मेसी का नाम *';
      addrLabel = 'पता';
      phoneLabel = 'फ़ोन नंबर';
      cancelLabel = 'रद्द करें';
      saveLabel = 'सहेजें';
    } else if (code == 'zh') {
      dialogTitle = '添加药房';
      nameLabel = '药房名称 *';
      addrLabel = '地址';
      phoneLabel = '电话号码';
      cancelLabel = '取消';
      saveLabel = '保存';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dialogTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: nameLabel),
              ),
              TextField(
                controller: addrCtrl,
                decoration: InputDecoration(labelText: addrLabel),
              ),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(labelText: phoneLabel),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                final newPharm = Pharmacy(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  address: addrCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                );
                Provider.of<PharmacyProvider>(context, listen: false)
                    .addPharmacy(newPharm);
                Navigator.pop(ctx);
              }
            },
            child: Text(saveLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pharmProvider = Provider.of<PharmacyProvider>(context);
    final language = Provider.of<LanguageProvider>(context);
    final code = language.locale.languageCode;

    String title = 'Pharmacies';
    String addBtn = '+ Add Pharmacy';
    String emptyText = 'No pharmacies added yet.';

    if (code == 'ar') {
      title = 'الصيدليات';
      addBtn = '+ إضافة صيدلية';
      emptyText = 'لم يتم إضافة صيدليات بعد.';
    } else if (code == 'es') {
      title = 'Farmacias';
      addBtn = '+ Añadir Farmacia';
      emptyText = 'Aún no se han añadido farmacias.';
    } else if (code == 'fr') {
      title = 'Pharmacies';
      addBtn = '+ Ajouter une Pharmacie';
      emptyText = 'Aucune pharmacie ajoutée pour le moment.';
    } else if (code == 'de') {
      title = 'Apotheken';
      addBtn = '+ Apotheke hinzufügen';
      emptyText = 'Noch keine Apotheken hinzugefügt.';
    } else if (code == 'tr') {
      title = 'Eczaneler';
      addBtn = '+ Eczane Ekle';
      emptyText = 'Henüz eczane eklenmedi.';
    } else if (code == 'hi') {
      title = 'फार्मेसी';
      addBtn = '+ फार्मेसी जोड़ें';
      emptyText = 'अभी तक कोई फार्मेसी नहीं जोड़ी गई है।';
    } else if (code == 'zh') {
      title = '药房';
      addBtn = '+ 添加药房';
      emptyText = '尚未添加药房。';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(addBtn),
        onPressed: () => _showAddPharmacyDialog(context, code),
      ),
      body: pharmProvider.pharmacies.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_pharmacy, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    emptyText,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: pharmProvider.pharmacies.length,
              itemBuilder: (context, index) {
                final pharm = pharmProvider.pharmacies[index];
                final address = pharm.address;
                final phone = pharm.phone;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: const Icon(Icons.local_pharmacy,
                          color: Colors.orange),
                    ),
                    title: Text(
                      pharm.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (address != null && address.isNotEmpty)
                          Text('$address'),
                        if (phone != null && phone.isNotEmpty) Text('$phone'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Call Pharmacy',
                          icon: const Icon(Icons.phone, color: Colors.green),
                          onPressed: () async {
                            if (phone != null && phone.isNotEmpty) {
                              final uri = Uri.parse('tel:$phone');
                              if (await canLaunchUrl(uri)) await launchUrl(uri);
                            } else {
                              _showEnlargedPharmacy(context, pharm, code);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            pharmProvider.deletePharmacy(pharm.id);
                          },
                        ),
                      ],
                    ),
                    onTap: () => _showEnlargedPharmacy(context, pharm, code),
                  ),
                );
              },
            ),
    );
  }
}
'@
[System.IO.File]::WriteAllText((Resolve-Path ".\lib\screens\home_screen.dart"), $homeScreen, $utf8NoBom)
Write-Host "home_screen.dart written" -ForegroundColor Green

# --- lib/screens/share_screen.dart ---
$shareScreen = @'
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareScreen extends StatefulWidget {
  final String token;
  const ShareScreen({super.key, required this.token});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShare();
  }

  Future<void> _loadShare() async {
    try {
      final response = await supabase.rpc('get_share_package', params: {
        'p_token': widget.token,
      });

      if (response == null || response.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'Invalid or expired share link.';
        });
        return;
      }

      setState(() {
        _documents = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load shared files.';
      });
    }
  }

  Future<void> _openDocument(String storagePath) async {
    try {
      final signedUrl = await supabase.storage
          .from('documents')
          .createSignedUrl(storagePath, 3600);

      final uri = Uri.parse(signedUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open document')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('📁 SANA Share'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secure Medical Documents',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('${_documents.length} files available',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _documents.length,
              itemBuilder: (context, index) {
                final doc = _documents[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      doc['file_type'] == 'pdf'
                          ? Icons.picture_as_pdf
                          : Icons.image,
                      color: Colors.teal,
                    ),
                    title: Text(doc['document_name'] ?? 'Unnamed'),
                    subtitle: Text(doc['storage_path']),
                    trailing: const Icon(Icons.open_in_browser),
                    onTap: () => _openDocument(doc['storage_path']),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText((Resolve-Path ".\lib\screens\share_screen.dart"), $shareScreen, $utf8NoBom)
Write-Host "share_screen.dart written" -ForegroundColor Green

Write-Host "All 3 files fixed. Run: git status  /  git diff to review." -ForegroundColor Cyan
