import 'package:flutter/foundation.dart';
import '../models/password_entry.dart';
import '../services/password_database_service.dart';
import '../services/secure_vault_service.dart';
import '../services/csv_import_service.dart';

// Sorting options for password list
enum SortMode { dateAddedDesc, alphabetical }

class PasswordProvider extends ChangeNotifier {
  final PasswordDatabaseService _databaseService = PasswordDatabaseService();
  final CsvImportService _csvImportService = CsvImportService();
  Uint8List? _currentVaultKey;
  Uint8List? _encryptionContext;
  
  // Sorting
  SortMode _sortMode = SortMode.dateAddedDesc;
  
  List<PasswordEntry> _passwords = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<PasswordEntry> get passwords => _passwords;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get passwordCount => _passwords.length;
  SortMode get sortMode => _sortMode;

  void setSortMode(SortMode mode) {
    if (_sortMode == mode) return;
    _sortMode = mode;
    _applySortInMemory();
    notifyListeners();
  }

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
      _applySortInMemory();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load passwords: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _applySortInMemory() {
    if (_sortMode == SortMode.alphabetical) {
      _passwords.sort((a, b) {
        final at = a.title.trim().isEmpty ? a.url.trim() : a.title.trim();
        final bt = b.title.trim().isEmpty ? b.url.trim() : b.title.trim();
        return at.toLowerCase().compareTo(bt.toLowerCase());
      });
    }
    // For dateAddedDesc, DB already returns created_at DESC; no action needed.
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

  // Import passwords from CSV content (Dashlane-specific mapping retained, but supports generic CSV).
  // Returns counts and a list of skipped details: [{title, username, url, reason}]
  Future<({int imported, int skipped, String? error, List<Map<String, String>> skippedDetails})> importDashlaneCsv(String csvContent) async {
    if (_currentVaultKey == null) {
      _setError('Vault must be unlocked to import passwords');
      return (imported: 0, skipped: 0, error: 'Vault locked', skippedDetails: const <Map<String, String>>[]);
    }

    _setLoading(true);
    _clearError();

    try {
      final rows = _csvImportService.parseDashlaneCsv(csvContent);
      int imported = 0;
      int skipped = 0;
      final List<Map<String, String>> skippedDetails = [];

      for (final row in rows) {
        try {
          final mapped = _csvImportService.mapDashlaneRowToEntryFields(row);

          // Validate minimal required fields
          final title = mapped['title']?.trim() ?? '';
          final username = mapped['username']?.trim() ?? '';
          final password = mapped['password']?.trim() ?? '';

          if (password.isEmpty) {
            skipped++;
            skippedDetails.add({
              'title': title.isNotEmpty ? title : (mapped['url']?.trim() ?? ''),
              'username': username,
              'url': mapped['url']?.trim() ?? '',
              'reason': 'Empty password',
            });
            continue;
          }

          final entry = PasswordEntry(
            id: generateId(),
            title: title.isNotEmpty
                ? title
                : (mapped['url']?.trim().isNotEmpty == true
                    ? mapped['url']!.trim()
                    : (username.isNotEmpty ? username : 'Imported Item')),
            username: username,
            password: password,
            url: mapped['url']?.trim() ?? '',
            notes: mapped['notes']?.trim() ?? '',
            tags: (mapped['tags']?.trim().isNotEmpty == true)
                ? mapped['tags']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                : const [],
          );

          final inserted = await _databaseService.savePasswordImport(entry, _currentVaultKey!);
          if (inserted) {
            imported++;
          } else {
            // duplicate skipped by UNIQUE fingerprint
            skipped++;
            skippedDetails.add({
              'title': entry.title,
              'username': entry.username,
              'url': entry.url,
              'reason': 'Duplicate entry',
            });
          }
        } catch (e) {
          skipped++;
          skippedDetails.add({
            'title': (row['title'] ?? row['name'] ?? row['url'] ?? 'Unknown').toString(),
            'username': (row['username'] ?? row['user'] ?? row['email'] ?? '').toString(),
            'url': (row['url'] ?? row['website'] ?? '').toString(),
            'reason': 'Parse/validation error',
          });
          continue;
        }
      }

      await loadPasswords();
      return (imported: imported, skipped: skipped, error: null, skippedDetails: skippedDetails);
    } catch (e) {
      final msg = 'Failed to import CSV: $e';
      _setError(msg);
      return (imported: 0, skipped: 0, error: msg, skippedDetails: const <Map<String, String>>[]);
    } finally {
      _setLoading(false);
    }
  }
}
