import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/secure_vault_service.dart';
import '../providers/password_provider.dart';
import '../services/csv_import_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/csv_export_service.dart';
import '../services/encrypted_export_service.dart';
import 'package:pointycastle/api.dart' show InvalidCipherTextException;
import '../ui/toast.dart';

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
      Toast.show(context, '$remaining more taps to unlock hidden settings', background: Colors.blue[700]!, icon: Icons.info_outline);
    }
  }

  Future<String?> _promptForPassphrase({
    required bool confirm,
    required String title,
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure = true;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Make sure to remember your passphrase! It will be required to import the encrypted CSV file."),
                  SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Passphrase',
                      labelStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  if (confirm) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: obscure,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final p1 = controller.text.trim();
                    final p2 = confirm ? confirmController.text.trim() : p1;
                    if (p1.length < 8) {
                      Toast.show(context, 'Passphrase must be at least 8 characters', background: Colors.red[700]!, icon: Icons.error_outline);
                      return;
                    }
                    if (p1 != p2) {
                      Toast.show(context, 'Passphrases do not match', background: Colors.red[700]!, icon: Icons.error_outline);
                      return;
                    }
                    Navigator.of(context).pop(p1);
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Inline validation dialog: ask for passphrase and decrypt encrypted CSV.
  // Returns decrypted entries on success, or null on cancel.
  Future<List<Map<String, dynamic>>?> _promptForPassphraseAndDecrypt({
    required String content,
  }) async {
    final passController = TextEditingController();
    bool obscure = true;
    String? errorText;
    bool working = false;

    return showDialog<List<Map<String, dynamic>>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          Future<void> handleContinue() async {
            final pass = passController.text.trim();
            if (pass.length < 8) {
              setState(() => errorText = 'Passphrase must be at least 8 characters');
              return;
            }
            setState(() {
              errorText = null;
              working = true;
            });
            try {
              final encService = EncryptedExportService();
              final entries = await encService.decryptEncryptedCsv(content: content, passphrase: pass);
              if (mounted) Navigator.of(context).pop(entries);
            } on InvalidCipherTextException {
              setState(() {
                errorText = 'Incorrect passphrase. Please try again.';
                working = false;
              });
            } catch (e) {
              setState(() {
                errorText = 'Decryption failed. ${e.toString()}';
                working = false;
              });
            }
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Enter export passphrase', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: passController,
                  obscureText: obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    labelStyle: const TextStyle(color: Colors.grey),
                    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    errorText: errorText,
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Make sure you enter the passphrase you chose when exporting.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: working ? null : () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: working ? null : handleContinue,
                child: working
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _showDecoySetupDialog() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final vaultService =
        context.read<AuthProvider>().vaultService ?? SecureVaultService();

    bool decoyExists = await vaultService.vaultExists(VaultType.decoy);
    if (decoyExists) {
      Toast.show(context, 'Decoy vault already exists.', background: Colors.green[700]!, icon: Icons.info_outline);
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
              title: const Text(
                'Set Decoy Vault Password',
                style: TextStyle(color: Colors.white),
              ),
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
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
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
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
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
                            Toast.show(context, 'Password must be at least 8 characters', background: Colors.red[700]!, icon: Icons.error_outline);
                            return;
                          }
                          if (pwd != conf) {
                            Toast.show(context, 'Passwords do not match', background: Colors.red[700]!, icon: Icons.error_outline);
                            return;
                          }
                          // Prevent using same password as real vault
                          final sameAsOther = await vaultService
                              .isPasswordSameAsOtherVault(VaultType.decoy, pwd);
                          if (sameAsOther) {
                            Toast.show(context, 'Decoy password must be different from the real vault password', background: Colors.red[700]!, icon: Icons.error_outline);
                            return;
                          }
                          setStateDialog(() {
                            _isProcessing = true;
                          });
                          final success = await vaultService.initializeVault(
                            VaultType.decoy,
                            pwd,
                          );
                          setStateDialog(() {
                            _isProcessing = false;
                          });
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                          if (success) {
                            if (mounted) {
                              Toast.show(context, 'Decoy vault created. You can now unlock it.', background: Colors.green[700]!, icon: Icons.check_circle_outline);
                            }
                          } else {
                            if (mounted) {
                              Toast.show(context, 'Failed to create decoy vault. Try again.', background: Colors.red[700]!, icon: Icons.error_outline);
                            }
                          }
                        },
                  child: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showImportResultDialog({
    required int imported,
    required int skipped,
    required List<Map<String, String>> skippedDetails,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: const [
              Icon(Icons.assignment_turned_in, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Import results',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Imported: $imported, Skipped: $skipped',
                  style: TextStyle(color: Colors.grey[300]),
                ),
                const SizedBox(height: 12),
                if (skippedDetails.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: skippedDetails.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (context, index) {
                        final item = skippedDetails[index];
                        final title = (item['title'] ?? '').trim();
                        final username = (item['username'] ?? '').trim();
                        final url = (item['url'] ?? '').trim();
                        final reason = (item['reason'] ?? 'Skipped').trim();
                        final displayTitle = title.isNotEmpty
                            ? title
                            : (url.isNotEmpty
                                  ? url
                                  : (username.isNotEmpty
                                        ? username
                                        : 'Untitled'));
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.red[700],
                            child: const Icon(
                              Icons.block,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          title: Text(
                            displayTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (username.isNotEmpty)
                                Text(
                                  'User: $username',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (url.isNotEmpty)
                                Text(
                                  url,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                'Reason: $reason',
                                style: TextStyle(
                                  color: Colors.red[200],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  )
                else
                  Text(
                    'No skipped items.',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onExportTapped() async {
    final passwordProvider = context.read<PasswordProvider>();
    if (!passwordProvider.isVaultUnlocked) {
      if (mounted) {
        Toast.show(context, 'Unlock the vault before exporting.', background: Colors.red[700]!, icon: Icons.lock_outline);
      }
      return;
    }

    try {
      // Ask user for location to save file
      // On Android/iOS, FilePicker.saveFile requires bytes. On desktop, it returns a path
      // and we write the file ourselves.
      final csvService = CsvExportService();
      final csv = csvService.exportPasswordsToCsv(passwordProvider.passwords);
      // Normalize newlines to CRLF for better compatibility with mobile Office/Excel
      final normalizedLf = csv.replaceAll('\r\n', '\n');
      final normalized = normalizedLf.replaceAll('\n', '\r\n');
      final baseBytes = utf8.encode(normalized);
      // Prepend UTF-8 BOM on mobile to help some apps (Excel/Office) detect encoding
      final needsBom = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final csvBytes = Uint8List.fromList(
        needsBom ? [0xEF, 0xBB, 0xBF, ...baseBytes] : baseBytes,
      );

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Passwords as CSV',
        fileName: 'passwords_export.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        // Required on Android/iOS. Safe to provide on desktop too; plugin may still
        // return a path and expect us to write the file manually.
        bytes: csvBytes,
      );
      if (result == null) return; // cancelled

      // On desktop platforms, write the file to the returned path.
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final file = File(result);
        await file.writeAsBytes(csvBytes, flush: true);
      }

      if (mounted) {
        Toast.show(context, 'Passwords exported successfully.', background: Colors.green[700]!, icon: Icons.check_circle_outline);
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, 'Export error: $e', background: Colors.red[700]!, icon: Icons.error_outline);
      }
    }
  }

  // Export encrypted CSV using a user-provided passphrase
  Future<void> _onExportEncryptedTapped() async {
    final passwordProvider = context.read<PasswordProvider>();
    if (!passwordProvider.isVaultUnlocked) {
      if (mounted) {

        Toast.show(context, 'Unlock the vault before exporting.', background: Colors.red[700]!, icon: Icons.lock_outline);
      }

      return;
    }

    try {
      final passphrase = await _promptForPassphrase(
        confirm: true,
        title: 'Set export passphrase',
      );
      if (passphrase == null) return;

      final entries = passwordProvider.passwords
          .map(
            (e) => {
              'title': e.title,
              'username': e.username,
              'password': e.password,
              'url': e.url,
              'notes': e.notes,
              'tags': e.tags,
              'created_at': e.createdAt.toIso8601String(),
              'updated_at': e.updatedAt.toIso8601String(),
            },
          )
          .toList();

      final encService = EncryptedExportService();
      final csvBytes = await encService.exportEncryptedCsv(
        entries: entries,
        passphrase: passphrase,
      );

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Passwords (Encrypted)',
        fileName: 'passwords_export.pvenc.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: csvBytes,
      );
      if (result == null) return;

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final file = File(result);
        await file.writeAsBytes(csvBytes, flush: true);
      }

      if (mounted) {
        Toast.show(context, 'Encrypted export saved.', background: Colors.green[700]!, icon: Icons.check_circle_outline);
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, 'Encrypted export error: $e', background: Colors.red[700]!, icon: Icons.error_outline);
      }
    }
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
            colors: [Colors.grey[900]!, Colors.grey[800]!],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.grey[850],
              child: ListTile(
                title: const Text(
                  'App Version',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _version,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                onTap: _onVersionTapped,
              ),
            ),
            const SizedBox(height: 12),
            // Sort Order
            Consumer<PasswordProvider>(
              builder: (context, provider, _) {
                return Card(
                  color: Colors.grey[850],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          title: Text(
                            'Sort Order',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Choose how passwords are ordered on the Home screen',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        RadioListTile<SortMode>(
                          value: SortMode.dateAddedDesc,
                          groupValue: provider.sortMode,
                          onChanged: (val) {
                            if (val != null) provider.setSortMode(val);
                          },
                          activeColor: Colors.blue,
                          title: const Text(
                            'Date added (newest first)',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        RadioListTile<SortMode>(
                          value: SortMode.alphabetical,
                          groupValue: provider.sortMode,
                          onChanged: (val) {
                            if (val != null) provider.setSortMode(val);
                          },
                          activeColor: Colors.blue,
                          title: const Text(
                            'Alphabetical (A–Z)',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.grey[850],
              child: ListTile(
                title: const Text(
                  'Import Passwords (CSV)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Preview first 5 entries before importing',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                trailing: const Icon(Icons.upload_file, color: Colors.white),
                onTap: _onImportTapped,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.grey[850],
              child: ListTile(
                title: const Text(
                  'Export Passwords (.csv)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Plain-Text CSV file, less secure',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                trailing: const Icon(Icons.download, color: Colors.white),
                onTap: _onExportTapped,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.grey[850],
              child: ListTile(
                title: const Text(
                  'Export Passwords (Encrypted)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Protected with a passphrase (.pvenc.csv)',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                trailing: const Icon(Icons.lock, color: Colors.white),
                onTap: _onExportEncryptedTapped,
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
        Toast.show(context, 'Unlock the vault before importing.', background: Colors.red[700]!, icon: Icons.lock_outline);
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
          Toast.show(context, 'Could not read file bytes.', background: Colors.red[700]!, icon: Icons.error_outline);
        }
        return;
      }

      // Detect encrypted export vs plain CSV
      final encService = EncryptedExportService();
      if (encService.isEncryptedCsv(content)) {
        // Prompt for passphrase in a dialog that validates inline
        final decrypted = await _promptForPassphraseAndDecrypt(content: content);
        if (decrypted == null) return; // cancelled or failed
        final outcome = await context.read<PasswordProvider>().importDecryptedEntries(decrypted);
        if (!mounted) return;
        await _showImportResultDialog(
          imported: outcome.imported,
          skipped: outcome.skipped,
          skippedDetails: outcome.skippedDetails,
        );
        return;
      }

      // Plain CSV: Parse and map rows for preview
      final csvService = CsvImportService();
      final rows = csvService.parseDashlaneCsv(content);
      if (rows.isEmpty) {
        if (mounted) {
          Toast.show(context, 'CSV appears to be empty or invalid.', background: Colors.red[700]!, icon: Icons.error_outline);
        }
        return;
      }
      final mapped = rows.map(csvService.mapDashlaneRowToEntryFields).toList();
      final preview = mapped.take(5).toList();

      if (!mounted) return;
      _showImportPreviewDialog(
        preview,
        onConfirm: () async {
          final outcome = await passwordProvider.importDashlaneCsv(content);
          if (!mounted) return;
          Navigator.of(context).pop();
          if (outcome.error == null) {
            await _showImportResultDialog(
              imported: outcome.imported,
              skipped: outcome.skipped,
              skippedDetails: outcome.skippedDetails,
            );
          } else {
            Toast.show(context, 'Import failed: ${outcome.error}', background: Colors.red[700]!, icon: Icons.error_outline);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        Toast.show(context, 'Import error: $e', background: Colors.red[700]!, icon: Icons.error_outline);
      }
    }
  }

  void _showImportPreviewDialog(
    List<Map<String, String>> preview, {
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: const [
              Icon(Icons.preview, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Review import',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final item = preview[index];
                      final title = (item['title']?.trim().isNotEmpty == true)
                          ? item['title']!.trim()
                          : 'Untitled';
                      final username = (item['username'] ?? '').trim();
                      final url = (item['url'] ?? '').trim();
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.blue[600],
                          child: Text(
                            title[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (username.isNotEmpty)
                              Text(
                                username,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (url.isNotEmpty)
                              Text(
                                url,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
