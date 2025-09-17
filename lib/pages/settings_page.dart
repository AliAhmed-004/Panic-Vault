import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/secure_vault_service.dart';

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
}
