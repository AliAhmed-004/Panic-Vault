import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/secure_vault_service.dart';
import '../providers/auth_provider.dart';
import 'home_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _secureVaultService = SecureVaultService();
  
  bool _isInitializing = false;
  bool _isUnlocking = false;
  bool _isVaultInitialized = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _checkVaultStatus();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultStatus() async {
    final isInitialized = await _secureVaultService.isVaultInitialized();
    setState(() {
      _isVaultInitialized = isInitialized;
    });
  }

  Future<void> _initializeVault() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Show progress message
      setState(() {
        _successMessage = 'Initializing vault... This may take a moment for security.';
      });
      
      final success = await _secureVaultService.initializeVault(_passwordController.text);
      
      if (success) {
        setState(() {
          _successMessage = 'Vault initialized successfully! You can now unlock it.';
          _isVaultInitialized = true;
        });
        _passwordController.clear();
        _confirmPasswordController.clear();
      } else {
        setState(() {
          _errorMessage = 'Failed to initialize vault. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred during initialization.';
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _unlockVault() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Show progress message
      setState(() {
        _successMessage = 'Unlocking vault...';
      });
      
      final result = await _secureVaultService.unlockVault(_passwordController.text);
      
      if (result.success) {
        // Set the vault as unlocked in the provider
        context.read<AuthProvider>().unlockVault(_secureVaultService);
        
        // Navigate to home page
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } else if (result.locked) {
        setState(() {
          _errorMessage = 'Too many failed attempts. Try again in ${result.lockoutSeconds} seconds (${result.lockoutSeconds! / 60} minutes).';
        });
      } else if (result.error != null) {
        setState(() {
          _errorMessage = result.error;
        });
      } else {
        setState(() {
          _errorMessage = 'Incorrect password. ${result.remainingAttempts} attempts remaining.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred during authentication.';
      });
    } finally {
      setState(() {
        _isUnlocking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panic Vault'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      body: Container(
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              color: Colors.grey[850],
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // App Icon/Logo
                      Icon(
                        Icons.lock_outline,
                        size: 64,
                        color: Colors.blue[400],
                      ),
                      const SizedBox(height: 16),
                      
                      // Title
                      Text(
                        _isVaultInitialized ? 'Unlock Vault' : 'Initialize Vault',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Subtitle
                      Text(
                        _isVaultInitialized 
                          ? 'Enter your master password to access your passwords'
                          : 'Create a master password to secure your vault',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      
                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Master Password',
                          labelStyle: TextStyle(color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[600]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.blue[400]!),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: Colors.grey[400],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Confirm Password Field (only for initialization)
                      if (!_isVaultInitialized) ...[
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Confirm Master Password',
                            labelStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[600]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blue[400]!),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                                color: Colors.grey[400],
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword = !_obscureConfirmPassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Error Message
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[900],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red[100]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red[100]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Success Message
                      if (_successMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[900],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green[100]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: TextStyle(color: Colors.green[100]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (_isInitializing || _isUnlocking) 
                            ? null 
                            : (_isVaultInitialized ? _unlockVault : _initializeVault),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[600],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isInitializing || _isUnlocking
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _isInitializing ? 'Initializing...' : 'Unlocking...',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              )
                            : Text(
                                _isVaultInitialized ? 'Unlock Vault' : 'Initialize Vault',
                                style: const TextStyle(fontSize: 16),
                              ),
                        ),
                      ),
                      
                      // Security Info
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, color: Colors.blue[400], size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Security Features',
                                  style: TextStyle(
                                    color: Colors.blue[400],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                                                         Text(
                               '• 100,000 PBKDF2 iterations\n'
                               '• AES-GCM encryption\n'
                               '• Rate limiting protection\n'
                               '• Memory clearing\n'
                               '• Background processing',
                               style: TextStyle(
                                 color: Colors.grey[400],
                                 fontSize: 12,
                               ),
                             ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
