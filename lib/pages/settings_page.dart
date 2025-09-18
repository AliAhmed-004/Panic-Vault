import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/secure_vault_service.dart';
import '../providers/password_provider.dart';
import '../services/csv_import_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const int _tapsToReveal = 7;
  int _tapCount = 0;
  bool _revealed = false;
  bool _isProcessing = false;
  final String _version = '1.0.0';
  Timer? _tapResetTimer;
  static const Duration _tapResetAfter = Duration(seconds: 2);

  void _onVersionTapped() async {
    if (_revealed) return;
    // Reset inactivity timer on each tap
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(_tapResetAfter, () {
      if (mounted) {
        setState(() {
          _tapCount = 0;
        });
      } else {
        _tapCount = 0;
      }
    });

    setState(() {
      _tapCount++;
    });
    if (_tapCount >= _tapsToReveal) {
      _tapResetTimer?.cancel();
      setState(() {
        _revealed = true;
      });
      _showDecoySetupDialog();
    } else if (_tapCount >= _tapsToReveal - 3) {
      final remaining = _tapsToReveal - _tapCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$remaining more taps to unlock hidden settings'),
          duration: const Duration(milliseconds: 800),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _showDecoySetupDialog() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final vaultService = context.read<AuthProvider>().vaultService ?? SecureVaultService();

    bool decoyExists = await vaultService.vaultExists(VaultType.decoy);
    if (decoyExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Decoy vault already exists.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    // ignore: use_build_context_synchronously
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.grey[850],
              title: const Text('Set Decoy Vault Password', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Decoy Password',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          final pwd = passwordController.text.trim();
                          final conf = confirmController.text.trim();
                          if (pwd.length < 8) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password must be at least 8 characters'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          if (pwd != conf) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passwords do not match'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          // Prevent using same password as real vault
                          final sameAsOther = await vaultService.isPasswordSameAsOtherVault(VaultType.decoy, pwd);
                          if (sameAsOther) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Decoy password must be different from the real vault password'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setStateDialog(() {
                            _isProcessing = true;
                          });
                          final success = await vaultService.initializeVault(VaultType.decoy, pwd);
                          setStateDialog(() {
                            _isProcessing = false;
                          });
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                          if (success) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Decoy vault created. You can now unlock it.'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to create decoy vault. Try again.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: _isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      body: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[900]!,
              Colors.grey[800]!,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.grey[850],
              child: ListTile(
                title: const Text('App Version', style: TextStyle(color: Colors.white)),
                subtitle: Text(_version, style: TextStyle(color: Colors.grey[400])),
                onTap: _onVersionTapped,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.grey[850],
              child: ListTile(
                title: const Text('Import from Dashlane (CSV)', style: TextStyle(color: Colors.white)),
                subtitle: Text('Preview first 5 entries before importing', style: TextStyle(color: Colors.grey[400])),
                trailing: const Icon(Icons.upload_file, color: Colors.white),
                onTap: _onImportTapped,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _onImportTapped() async {
    final passwordProvider = context.read<PasswordProvider>();
    if (!passwordProvider.isVaultUnlocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unlock the vault before importing.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return; // cancelled

      final file = picked.files.first;
      String content;
      if (file.bytes != null) {
        try {
          content = utf8.decode(file.bytes!);
        } catch (_) {
          content = latin1.decode(file.bytes!);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read file bytes.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Parse and map rows for preview
      final csvService = CsvImportService();
      final rows = csvService.parseDashlaneCsv(content);
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV appears to be empty or invalid.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final mapped = rows.map(csvService.mapDashlaneRowToEntryFields).toList();
      final preview = mapped.take(5).toList();

      if (!mounted) return;
      _showImportPreviewDialog(preview, onConfirm: () async {
        final outcome = await passwordProvider.importDashlaneCsv(content);
        if (!mounted) return;
        Navigator.of(context).pop();
        if (outcome.error == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imported: ${outcome.imported}, Skipped: ${outcome.skipped}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: ${outcome.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImportPreviewDialog(List<Map<String, String>> preview, {required Future<void> Function() onConfirm}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: const [
              Icon(Icons.preview, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Review import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Previewing ${preview.length < 5 ? preview.length : 5} of ${preview.length} item(s).',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: preview.length > 5 ? 5 : preview.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final item = preview[index];
                      final title = (item['title']?.trim().isNotEmpty == true) ? item['title']!.trim() : 'Untitled';
                      final username = (item['username'] ?? '').trim();
                      final url = (item['url'] ?? '').trim();
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.blue[600],
                          child: Text(title[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (username.isNotEmpty)
                              Text(username, style: TextStyle(color: Colors.grey[400], fontSize: 12), overflow: TextOverflow.ellipsis),
                            if (url.isNotEmpty)
                              Text(url, style: TextStyle(color: Colors.grey[500], fontSize: 11), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await onConfirm();
              },
              icon: const Icon(Icons.file_download_done),
              label: const Text('Import All'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )
          ],
        );
      },
    );
  }
}
