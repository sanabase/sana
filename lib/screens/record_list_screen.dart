import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================
// LANGUAGE NOTIFIER (shared)
// ============================================

final ValueNotifier<String> languageNotifier = ValueNotifier<String>('en');

String tr(String code, String key) {
  // This will be overridden by main.dart's translations
  return key;
}

// ============================================
// PAYLOAD SANITIZER
// ============================================

class RecordSanitizer {
  static const Set<String> validColumns = {
    'name',
    'dosage',
    'quantity',
    'reminder_time',
    'description',
    'specialty',
    'phone',
    'email',
    'address',
    'title',
    'category',
    'file_url',
    'file_type',
    'provider_name',
    'front_image_url',
    'back_image_url',
    'photo_url',
    'photo_base64',
    'is_active',
    'user_id',
    'guest_id',
  };

  static Map<String, dynamic> sanitize(Map<String, dynamic> rawInput) {
    final cleanPayload = <String, dynamic>{};
    for (final entry in rawInput.entries) {
      if (validColumns.contains(entry.key) && entry.value != null) {
        if (entry.value is String) {
          final trimmed = (entry.value as String).trim();
          if (trimmed.isNotEmpty) cleanPayload[entry.key] = trimmed;
        } else {
          cleanPayload[entry.key] = entry.value;
        }
      }
    }
    return cleanPayload;
  }
}

// ============================================
// SAFE BASE64 IMAGE
// ============================================

class SafeBase64Image extends StatefulWidget {
  final String base64String;
  final double? height;
  final double? width;

  const SafeBase64Image({
    super.key,
    required this.base64String,
    this.height,
    this.width,
  });

  @override
  State<SafeBase64Image> createState() => _SafeBase64ImageState();
}

class _SafeBase64ImageState extends State<SafeBase64Image> {
  Uint8List? _bytes;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(SafeBase64Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64String != widget.base64String) {
      _decode();
    }
  }

  void _decode() {
    if (widget.base64String.isEmpty) {
      setState(() => _hasError = true);
      return;
    }
    try {
      final sanitized = widget.base64String.contains(',')
          ? widget.base64String.split(',').last
          : widget.base64String;
      final decoded = base64Decode(sanitized.replaceAll(RegExp(r'\s+'), ''));
      setState(() {
        _bytes = decoded;
        _hasError = false;
      });
    } catch (_) {
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400);
    }
    if (_bytes == null) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Image.memory(
      _bytes!,
      height: widget.height,
      width: widget.width,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.broken_image, color: Colors.grey.shade400),
    );
  }
}

// ============================================
// RECORD LIST SCREEN
// ============================================

class RecordListScreen extends StatefulWidget {
  const RecordListScreen({
    super.key,
    required this.type,
    required this.ownerId,
    required this.guestMode,
  });

  final String type;
  final String ownerId;
  final bool guestMode;

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  String get _table => widget.type;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await _client.from(_table).select();

      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  List<String> _getFields() {
    switch (widget.type) {
      case 'medications':
        return ['name', 'dosage', 'quantity', 'reminder_time', 'description'];
      case 'doctors':
        return ['name', 'specialty', 'phone', 'email', 'address'];
      case 'pharmacies':
        return ['name', 'phone', 'address'];
      case 'reminders':
        return ['name', 'dosage', 'reminder_time'];
      case 'documents':
        return ['title', 'category', 'file_url'];
      case 'insurance_cards':
        return ['provider_name', 'front_image_url', 'back_image_url'];
      default:
        return ['name'];
    }
  }

  Future<void> _add() async {
    final fields = _getFields();
    final controllers = <String, TextEditingController>{};
    for (final field in fields) {
      controllers[field] = TextEditingController();
    }

    final language = languageNotifier.value;

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Add ${tr(language, widget.type)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fields.map((field) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controllers[field],
                    decoration: InputDecoration(
                      labelText: field,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final payload = {
                  for (final entry in controllers.entries)
                    entry.key: entry.value.text.trim()
                };
                Navigator.pop(dialogContext, payload);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }

    if (result == null) return;

    final cleanPayload = RecordSanitizer.sanitize(result);

    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('No Supabase Auth session exists.');
    }
    cleanPayload['user_id'] = user.isAnonymous ? null : user.id;
    cleanPayload['guest_id'] = user.isAnonymous ? user.id : null;

    if (_table == 'medications') {
      cleanPayload['quantity'] =
          int.tryParse(cleanPayload['quantity']?.toString() ?? '') ?? 1;
      cleanPayload['description'] ??= '';
      cleanPayload['file_type'] ??= 'image';
      cleanPayload['is_active'] ??= true;
    } else if (_table == 'doctors') {
      cleanPayload['is_active'] ??= true;
    } else if (_table == 'pharmacies') {
      cleanPayload['phone'] ??= '';
      cleanPayload['is_active'] ??= true;
    } else if (_table == 'documents') {
      cleanPayload['file_type'] ??= 'file';
    } else if (_table == 'insurance_cards') {
      cleanPayload['provider_name'] ??= 'Insurance Card';
    }

    try {
      await _client.from(_table).insert(cleanPayload);
      await _load();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation failed: $e')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${row['name'] ?? row['title'] ?? 'record'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (_client.auth.currentUser == null) {
        throw StateError('No Supabase Auth session exists.');
      }
      final user = _client.auth.currentUser!;
      var query = _client.from(_table).delete().eq('id', id);

      if (user.isAnonymous) {
        query = query.eq('guest_id', user.id);
      } else {
        query = query.eq('user_id', user.id);
      }

      await query;
      await _load();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting: $e')),
      );
    }
  }

  Future<void> _share(Map<String, dynamic> row) async {
    await SharePlus.instance.share(
      ShareParams(
          text: row.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
    );
  }

  Future<void> _preview(Map<String, dynamic> row) async {
    final photo = row['photo_url'] ?? row['front_image_url'];
    final base64Photo = row['photo_base64'];
    final url = row['file_url'];
    languageNotifier.value;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          (row['name'] ?? row['title'] ?? row['provider_name'] ?? 'Record')
              .toString(),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (base64Photo != null &&
                  base64Photo.toString().trim().isNotEmpty)
                SafeBase64Image(
                  base64String: base64Photo.toString(),
                  height: 160,
                ),
              if (photo != null && photo.toString().isNotEmpty)
                Image.network(
                  photo.toString(),
                  height: 160,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              if (url != null && url.toString().isNotEmpty) ...[
                ListTile(
                  title: Text(url.toString()),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () async {
                    final Uri uri = Uri.parse(url.toString());
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              ],
              ...row.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _subtitle(Map<String, dynamic> row) {
    if (widget.type == 'medications') {
      return '${row['dosage'] ?? ''} ${row['reminder_time'] ?? ''}';
    }
    if (widget.type == 'doctors') {
      return '${row['specialty'] ?? ''} ${row['phone'] ?? ''}';
    }
    if (widget.type == 'pharmacies') {
      return '${row['phone'] ?? ''} ${row['address'] ?? ''}';
    }
    if (widget.type == 'documents') {
      return '${row['category'] ?? ''} ${row['file_type'] ?? ''}';
    }
    if (widget.type == 'insurance_cards') {
      return '${row['provider_name'] ?? ''}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, language, _) {
        return Directionality(
          textDirection:
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(tr(language, widget.type)),
              actions: [
                IconButton(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(child: Text(tr(language, 'no_records')))
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.1,
                        ),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final title = (row['name'] ??
                                  row['title'] ??
                                  row['provider_name'] ??
                                  'Record')
                              .toString();

                          return Card(
                            elevation: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _preview(row),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => _share(row),
                                          icon:
                                              const Icon(Icons.share, size: 18),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Expanded(
                                      child: Text(
                                        _subtitle(row),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () => _preview(row),
                                          child: const Text('View',
                                              style: TextStyle(fontSize: 11)),
                                        ),
                                        IconButton(
                                          onPressed: () => _delete(row),
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        );
      },
    );
  }
}
