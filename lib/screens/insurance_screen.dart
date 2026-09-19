import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insurance_card.dart';
import '../providers/insurance_provider.dart';
import '../providers/language_provider.dart';
import '../services/sharing_service.dart';

class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  final _nameController = TextEditingController();
  final _policyController = TextEditingController();
  Uint8List? _frontImageBytes;
  Uint8List? _backImageBytes;

  Future<void> _pickImage(bool isFront) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final bytes = result.files.single.bytes;
        if (bytes != null) {
          setState(() {
            if (isFront) {
              _frontImageBytes = bytes;
            } else {
              _backImageBytes = bytes;
            }
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick image: $e')),
      );
    }
  }

  void _saveCard() {
    final name = _nameController.text.trim();
    final policy = _policyController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter an insurance provider name.')),
      );
      return;
    }

    final String frontDataUrl = _frontImageBytes != null
        ? Uri.dataFromBytes(_frontImageBytes!, mimeType: 'image/png').toString()
        : '';
    final String backDataUrl = _backImageBytes != null
        ? Uri.dataFromBytes(_backImageBytes!, mimeType: 'image/png').toString()
        : '';

    final String nowIso = DateTime.now().toIso8601String();
    final String cardId = DateTime.now().millisecondsSinceEpoch.toString();
    final String polStr = policy.isNotEmpty ? policy : 'N/A';

    final Map<String, dynamic> newCardMap = {
      'id': cardId,
      'name': name,
      'providerName': name,
      'provider_name': name,
      'provider': name,
      'title': name,
      'policyNumber': polStr,
      'policy_number': polStr,
      'cardNumber': polStr,
      'card_number': polStr,
      'policyNo': polStr,
      'frontImageUrl': frontDataUrl,
      'front_image_url': frontDataUrl,
      'backImageUrl': backDataUrl,
      'back_image_url': backDataUrl,
      'createdAt': nowIso,
      'created_at': nowIso,
    };

    try {
      final newCard = InsuranceCard.fromMap(newCardMap);
      Provider.of<InsuranceProvider>(context, listen: false).addCard(newCard);

      _nameController.clear();
      _policyController.clear();
      setState(() {
        _frontImageBytes = null;
        _backImageBytes = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insurance card saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Error creating InsuranceCard object: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save card: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getCardTitle(InsuranceCard card) {
    try {
      final dyn = card as dynamic;
      return dyn.providerName?.toString() ??
          dyn.name?.toString() ??
          dyn.provider?.toString() ??
          dyn.title?.toString() ??
          'Insurance Card';
    } catch (_) {
      return 'Insurance Card';
    }
  }

  String _getCardPolicy(InsuranceCard card) {
    try {
      final dyn = card as dynamic;
      return dyn.policyNumber?.toString() ??
          dyn.cardNumber?.toString() ??
          dyn.policyNo?.toString() ??
          'N/A';
    } catch (_) {
      return 'N/A';
    }
  }

  String _getCardProp(InsuranceCard card, String prop) {
    try {
      final dyn = card as dynamic;
      final map = dyn.toMap() ?? dyn.toJson();
      return map[prop]?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // FIXED: Now correctly uses shareRecord and attaches the image bytes
  Future<void> _shareInsuranceCard(InsuranceCard card) async {
    final title = _getCardTitle(card);
    final policy = _getCardPolicy(card);

    String frontUrl = card.frontImageUrl ?? '';
    if (frontUrl.isEmpty) {
      frontUrl = _getCardProp(card, 'front_image_url');
    }

    String backUrl = card.backImageUrl ?? '';
    if (backUrl.isEmpty) {
      backUrl = _getCardProp(card, 'back_image_url');
    }

    final cardMap = {
      'providerName': title,
      'provider_name': title,
      'policyNumber': policy,
      'policy_number': policy,
      'frontImageUrl': frontUrl,
      'front_image_url': frontUrl,
      'backImageUrl': backUrl,
      'back_image_url': backUrl,
    };

    try {
      await SharingService.shareRecord(
        name: title,
        medications: [],
        doctors: [],
        pharmacies: [],
        documents: [],
        insuranceCards: [cardMap],
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error sharing card: $e'),
              backgroundColor: Colors.red),
        );
    }
  }

  Widget _buildCardSidePreview(String imgUrl, String label) {
    if (imgUrl.trim().isNotEmpty) {
      if (imgUrl.startsWith('data:image')) {
        try {
          final data = Uri.parse(imgUrl).data;
          if (data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                data.contentAsBytes(),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, size: 50),
              ),
            );
          }
        } catch (_) {}
      }

      if (imgUrl.startsWith('http://') || imgUrl.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            imgUrl,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
          ),
        );
      }

      try {
        final bytes = base64Decode(imgUrl);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
          ),
        );
      } catch (_) {}
    }

    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade200, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_card, size: 48, color: Colors.indigo.shade400),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ],
      ),
    );
  }

  void _showEnlargedCard(InsuranceCard card, String code) {
    final title = _getCardTitle(card);
    final policy = _getCardPolicy(card);

    String frontUrl = card.frontImageUrl ?? '';
    if (frontUrl.isEmpty) {
      frontUrl = _getCardProp(card, 'front_image_url');
    }

    String backUrl = card.backImageUrl ?? '';
    if (backUrl.isEmpty) {
      backUrl = _getCardProp(card, 'back_image_url');
    }

    String policyLbl = 'Policy / Card Number:';
    String viewLbl = 'Card Inspection View:';
    String frontLbl = 'FRONT SIDE';
    String backLbl = 'BACK SIDE';
    String shareBtn = 'Share Card';
    String closeBtn = 'Close Inspection';

    if (code == 'ar') {
      policyLbl = 'Ø±Ù‚Ù… Ø§Ù„Ø¨ÙˆÙ„ÙŠØµØ© / Ø§Ù„Ø¨Ø·Ø§Ù‚Ø©:';
      viewLbl = 'Ù…Ø¹Ø§ÙŠÙ†Ø© Ø§Ù„Ø¨Ø·Ø§Ù‚Ø© Ø¨Ø§Ù„ØªÙƒØ¨ÙŠØ±:';
      frontLbl = 'Ø§Ù„ÙˆØ¬Ù‡ Ø§Ù„Ø£Ù…Ø§Ù…ÙŠ';
      backLbl = 'Ø§Ù„ÙˆØ¬Ù‡ Ø§Ù„Ø®Ù„ÙÙŠ';
      shareBtn = 'Ù…Ø´Ø§Ø±ÙƒØ© Ø§Ù„Ø¨Ø·Ø§Ù‚Ø©';
      closeBtn = 'Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ù…Ø¹Ø§ÙŠÙ†Ø©';
    } else if (code == 'es') {
      policyLbl = 'NÃºmero de PÃ³liza / Tarjeta:';
      viewLbl = 'Vista de InspecciÃ³n:';
      frontLbl = 'FRENTE';
      backLbl = 'REVERSO';
      shareBtn = 'Compartir Tarjeta';
      closeBtn = 'Cerrar';
    } else if (code == 'fr') {
      policyLbl = 'NumÃ©ro de Police / Carte :';
      viewLbl = 'Vue Agrandie :';
      frontLbl = 'RECTO';
      backLbl = 'VERSO';
      shareBtn = 'Partager la Carte';
      closeBtn = 'Fermer';
    } else if (code == 'de') {
      policyLbl = 'Police / Kartennummer:';
      viewLbl = 'Kartenansicht:';
      frontLbl = 'VORDERSEITE';
      backLbl = 'RÃœCKSEITE';
      shareBtn = 'Karte Teilen';
      closeBtn = 'SchlieÃŸen';
    } else if (code == 'tr') {
      policyLbl = 'PoliÃ§e / Kart NumarasÄ±:';
      viewLbl = 'Kart Ä°nceleme GÃ¶rÃ¼nÃ¼mÃ¼:';
      frontLbl = 'Ã–N YÃœZ';
      backLbl = 'ARKA YÃœZ';
      shareBtn = 'KartÄ± PaylaÅŸ';
      closeBtn = 'Kapat';
    } else if (code == 'hi') {
      policyLbl = 'à¤ªà¥‰à¤²à¤¿à¤¸à¥€ / à¤•à¤¾à¤°à¥à¤¡ à¤¨à¤‚à¤¬à¤°:';
      viewLbl = 'à¤•à¤¾à¤°à¥à¤¡ à¤¦à¥ƒà¤¶à¥à¤¯:';
      frontLbl = 'à¤¸à¤¾à¤®à¤¨à¥‡ à¤•à¤¾ à¤­à¤¾à¤—';
      backLbl = 'à¤ªà¥€à¤›à¥‡ à¤•à¤¾ à¤­à¤¾à¤—';
      shareBtn = 'à¤•à¤¾à¤°à¥à¤¡ à¤¸à¤¾à¤à¤¾ à¤•à¤°à¥‡à¤‚';
      closeBtn = 'à¤¬à¤‚à¤¦ à¤•à¤°à¥‡à¤‚';
    } else if (code == 'zh') {
      policyLbl = 'ä¿å• / å¡å·:';
      viewLbl = 'æ”¾å¤§å¡ç‰‡è§†å›¾:';
      frontLbl = 'æ­£é¢';
      backLbl = 'èƒŒé¢';
      shareBtn = 'åˆ†äº«å¡ç‰‡';
      closeBtn = 'å…³é—­';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.indigo,
              child: Icon(Icons.credit_card, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 20),
                Text(
                  policyLbl,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  policy,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
                const SizedBox(height: 16),
                Text(
                  viewLbl,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildCardSidePreview(frontUrl, frontLbl)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildCardSidePreview(backUrl, backLbl)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: Text(shareBtn),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, // FIXED: Changed color to Orange
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx); // FIXED: Close dialog before sharing
              _shareInsuranceCard(card);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              closeBtn,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<InsuranceProvider>(context);
    final language = Provider.of<LanguageProvider>(context);
    final code = language.locale.languageCode;

    String title = 'Insurance Cards';
    String addTitle = 'Add New Insurance Card';
    String nameLabel = 'Provider Name *';
    String policyLabel = 'Policy / Card Number';
    String frontBtn = 'Front Image';
    String backBtn = 'Back Image';
    String saveBtn = 'Save Card';
    String emptyText = 'No insurance cards added yet.';

    if (code == 'ar') {
      title = 'Ø¨Ø·Ø§Ù‚Ø§Øª Ø§Ù„ØªØ£Ù…ÙŠÙ†';
      addTitle = 'Ø¥Ø¶Ø§ÙØ© Ø¨Ø·Ø§Ù‚Ø© ØªØ£Ù…ÙŠÙ† Ø¬Ø¯ÙŠØ¯Ø©';
      nameLabel = 'Ø§Ø³Ù… Ø´Ø±ÙƒØ© Ø§Ù„ØªØ£Ù…ÙŠÙ† *';
      policyLabel = 'Ø±Ù‚Ù… Ø§Ù„Ø¨ÙˆÙ„ÙŠØµØ© / Ø§Ù„Ø¨Ø·Ø§Ù‚Ø©';
      frontBtn = 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø£Ù…Ø§Ù…ÙŠØ©';
      backBtn = 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø®Ù„ÙÙŠØ©';
      saveBtn = 'Ø­ÙØ¸ Ø§Ù„Ø¨Ø·Ø§Ù‚Ø©';
      emptyText = 'Ù„Ù… ÙŠØªÙ… Ø¥Ø¶Ø§ÙØ© Ø¨Ø·Ø§Ù‚Ø§Øª ØªØ£Ù…ÙŠÙ† Ø¨Ø¹Ø¯.';
    } else if (code == 'es') {
      title = 'Tarjetas de Seguro';
      addTitle = 'AÃ±adir Nueva Tarjeta de Seguro';
      nameLabel = 'Nombre de la Aseguradora *';
      policyLabel = 'NÃºmero de PÃ³liza / Tarjeta';
      frontBtn = 'Imagen Frontal';
      backBtn = 'Imagen Trasera';
      saveBtn = 'Guardar Tarjeta';
      emptyText = 'AÃºn no se han aÃ±adido tarjetas de seguro.';
    } else if (code == 'fr') {
      title = 'Cartes d\'Assurance';
      addTitle = 'Ajouter une Carte d\'Assurance';
      nameLabel = 'Nom de l\'Assureur *';
      policyLabel = 'NumÃ©ro de Police / Carte';
      frontBtn = 'Image Recto';
      backBtn = 'Image Verso';
      saveBtn = 'Enregistrer la Carte';
      emptyText = 'Aucune carte d\'assurance ajoutÃ©e.';
    } else if (code == 'de') {
      title = 'Versicherungskarten';
      addTitle = 'Versicherungskarte hinzufÃ¼gen';
      nameLabel = 'Name der Versicherung *';
      policyLabel = 'Policen- / Kartennummer';
      frontBtn = 'Vorderseite';
      backBtn = 'RÃ¼ckseite';
      saveBtn = 'Karte Speichern';
      emptyText = 'Noch keine Versicherungskarten hinzugefÃ¼gt.';
    } else if (code == 'tr') {
      title = 'Sigorta KartlarÄ±';
      addTitle = 'Yeni Sigorta KartÄ± Ekle';
      nameLabel = 'Sigorta Åžirketi AdÄ± *';
      policyLabel = 'PoliÃ§e / Kart NumarasÄ±';
      frontBtn = 'Ã–n YÃ¼z Resmi';
      backBtn = 'Arka YÃ¼z Resmi';
      saveBtn = 'KartÄ± Kaydet';
      emptyText = 'HenÃ¼z sigorta kartÄ± eklenmedi.';
    } else if (code == 'hi') {
      title = 'à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡';
      addTitle = 'à¤¨à¤¯à¤¾ à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡ à¤œà¥‹à¤¡à¤¼à¥‡à¤‚';
      nameLabel = 'à¤¬à¥€à¤®à¤¾ à¤ªà¥à¤°à¤¦à¤¾à¤¤à¤¾ à¤¨à¤¾à¤® *';
      policyLabel = 'à¤ªà¥‰à¤²à¤¿à¤¸à¥€ / à¤•à¤¾à¤°à¥à¤¡ à¤¨à¤‚à¤¬à¤°';
      frontBtn = 'à¤¸à¤¾à¤®à¤¨à¥‡ à¤•à¥€ à¤¤à¤¸à¥à¤µà¥€à¤°';
      backBtn = 'à¤ªà¥€à¤›à¥‡ à¤•à¥€ à¤¤à¤¸à¥à¤µà¥€à¤°';
      saveBtn = 'à¤•à¤¾à¤°à¥à¤¡ à¤¸à¤¹à¥‡à¤œà¥‡à¤‚';
      emptyText =
          'à¤…à¤­à¥€ à¤•à¥‹à¤ˆ à¤¬à¥€à¤®à¤¾ à¤•à¤¾à¤°à¥à¤¡ à¤¨à¤¹à¥€à¤‚ à¤œà¥‹à¤¡à¤¼à¤¾ à¤—à¤¯à¤¾à¥¤';
    } else if (code == 'zh') {
      title = 'ä¿é™©å¡';
      addTitle = 'æ·»åŠ æ–°ä¿é™©å¡';
      nameLabel = 'ä¿é™©å…¬å¸åç§° *';
      policyLabel = 'ä¿å• / å¡å·';
      frontBtn = 'æ­£é¢ç…§ç‰‡';
      backBtn = 'èƒŒé¢ç…§ç‰‡';
      saveBtn = 'ä¿å­˜å¡ç‰‡';
      emptyText = 'å°šæœªæ·»åŠ ä¿é™©å¡ã€‚';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        labelText: nameLabel,
                        labelStyle: const TextStyle(fontSize: 16),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.business, size: 28),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _policyController,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        labelText: policyLabel,
                        labelStyle: const TextStyle(fontSize: 16),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.credit_card, size: 28),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => _pickImage(true),
                            icon: Icon(
                              _frontImageBytes != null
                                  ? Icons.check_circle
                                  : Icons.camera_alt,
                              color: _frontImageBytes != null
                                  ? Colors.green
                                  : Colors.teal,
                              size: 24,
                            ),
                            label: Text(
                              frontBtn,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => _pickImage(false),
                            icon: Icon(
                              _backImageBytes != null
                                  ? Icons.check_circle
                                  : Icons.camera_alt,
                              color: _backImageBytes != null
                                  ? Colors.green
                                  : Colors.teal,
                              size: 24,
                            ),
                            label: Text(
                              backBtn,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _saveCard,
                        icon: const Icon(Icons.save, size: 26),
                        label: Text(
                          saveBtn,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.cards.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              Icon(Icons.credit_card,
                                  size: 72, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                emptyText,
                                style: TextStyle(
                                    fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: provider.cards.length,
                        itemBuilder: (context, index) {
                          final card = provider.cards[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: const CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.indigoAccent,
                                child: Icon(Icons.credit_card,
                                    color: Colors.white, size: 28),
                              ),
                              title: Text(
                                _getCardTitle(card),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Policy: ${_getCardPolicy(card)}',
                                style: const TextStyle(fontSize: 20),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Share Card',
                                    icon: const Icon(Icons.share,
                                        color: Colors.orange,
                                        size: 28), // FIXED: Orange color
                                    onPressed: () => _shareInsuranceCard(card),
                                  ),
                                  IconButton(
                                    tooltip: 'Enlarge / Inspect',
                                    icon: const Icon(Icons.visibility,
                                        color: Colors.teal, size: 28),
                                    onPressed: () =>
                                        _showEnlargedCard(card, code),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red, size: 28),
                                    onPressed: () {
                                      if (card.id != null) {
                                        provider.deleteCard(card.id!);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => _showEnlargedCard(card, code),
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _policyController.dispose();
    super.dispose();
  }
}
