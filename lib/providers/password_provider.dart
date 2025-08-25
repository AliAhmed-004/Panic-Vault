import 'package:flutter/foundation.dart';
import '../models/password_entry.dart';
import '../services/password_database_service.dart';
import '../services/secure_vault_service.dart';

class PasswordProvider extends ChangeNotifier {
  final PasswordDatabaseService _databaseService = PasswordDatabaseService();
  Uint8List? _currentVaultKey;
  Uint8List? _encryptionContext;
  
  List<PasswordEntry> _passwords = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<PasswordEntry> get passwords => _passwords;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get passwordCount => _passwords.length;

  // Set vault key (called when vault is unlocked)
  void setVaultKey(Uint8List vaultKey, {VaultType? type, Uint8List? encryptionContext}) {
    _currentVaultKey = vaultKey;
    _encryptionContext = encryptionContext;
    // configure DB
    final dbType = (type == VaultType.decoy) ? ActiveVaultDb.decoy : ActiveVaultDb.real;
    _databaseService.setActiveVault(dbType, aad: _encryptionContext);
  }

  // Clear vault key (called when vault is locked)
  void clearVaultKey() {
    _currentVaultKey = null;
    _encryptionContext = null;
    _passwords.clear();
    notifyListeners();
  }

  // Check if vault key is available
  bool get isVaultUnlocked => _currentVaultKey != null;

  // Load all passwords
  Future<void> loadPasswords() async {
    if (_currentVaultKey == null) {
      _setError('Vault must be unlocked to access passwords');
      return;
    }

    _setLoading(true);
    _clearError();

    try {
      _passwords = await _databaseService.getAllPasswords(_currentVaultKey!);
      notifyListeners();
    } catch (e) {
      _setError('Failed to load passwords: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Add new password
  Future<bool> addPassword(PasswordEntry password) async {
    if (_currentVaultKey == null) {
      _setError('Vault must be unlocked to access passwords');
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await _databaseService.savePassword(password, _currentVaultKey!);
      await loadPasswords(); // Reload the list
      return true;
    } catch (e) {
      _setError('Failed to add password: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Update existing password
  Future<bool> updatePassword(PasswordEntry password) async {
    if (_currentVaultKey == null) {
      _setError('Vault must be unlocked to access passwords');
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await _databaseService.savePassword(password, _currentVaultKey!);
      await loadPasswords(); // Reload the list
      return true;
    } catch (e) {
      _setError('Failed to update password: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Delete password
  Future<bool> deletePassword(String id) async {
    _setLoading(true);
    _clearError();

    try {
      final success = await _databaseService.deletePassword(id);
      if (success) {
        await loadPasswords(); // Reload the list
      }
      return success;
    } catch (e) {
      _setError('Failed to delete password: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Search passwords
  Future<List<PasswordEntry>> searchPasswords(String query) async {
    if (_currentVaultKey == null) {
      _setError('Vault must be unlocked to access passwords');
      return [];
    }

    if (query.isEmpty) {
      return _passwords;
    }

    try {
      return await _databaseService.searchPasswords(query, _currentVaultKey!);
    } catch (e) {
      _setError('Failed to search passwords: $e');
      return [];
    }
  }

  // Get password by ID
  Future<PasswordEntry?> getPassword(String id) async {
    if (_currentVaultKey == null) {
      _setError('Vault must be unlocked to access passwords');
      return null;
    }

    try {
      return await _databaseService.getPassword(id, _currentVaultKey!);
    } catch (e) {
      _setError('Failed to get password: $e');
      return null;
    }
  }

  // Get password count
  Future<int> getPasswordCount() async {
    try {
      return await _databaseService.getPasswordCount();
    } catch (e) {
      _setError('Failed to get password count: $e');
      return 0;
    }
  }

  // Clear all passwords (for testing)
  Future<void> clearAllPasswords() async {
    _setLoading(true);
    _clearError();

    try {
      await _databaseService.clearAllPasswords();
      _passwords.clear();
      notifyListeners();
    } catch (e) {
      _setError('Failed to clear passwords: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Generate unique ID for new password
  String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  // Clear error manually
  void clearError() {
    _clearError();
  }

  // Refresh passwords
  Future<void> refresh() async {
    await loadPasswords();
  }
}
