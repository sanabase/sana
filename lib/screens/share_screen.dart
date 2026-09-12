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
        title: const Text('ðŸ“ sana Share'),
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
