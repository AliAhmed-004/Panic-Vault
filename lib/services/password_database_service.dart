import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/password_entry.dart';
import 'password_encryption_service.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert';

enum ActiveVaultDb { real, decoy }

class PasswordDatabaseService {
  static final Map<ActiveVaultDb, Database> _dbByVault = {};
  ActiveVaultDb _activeVault = ActiveVaultDb.real;
  final PasswordEncryptionService _encryptionService = PasswordEncryptionService();
  Uint8List? _aad;

  // Get database instance
  Future<Database> get database async {
    final current = _dbByVault[_activeVault];
    if (current != null) return current;
    final db = await _initDatabase();
    _dbByVault[_activeVault] = db;
    return db;
  }

  // Initialize database
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final suffix = _activeVault == ActiveVaultDb.real ? 'real' : 'decoy';
    final path = join(databasePath, 'panic_vault_passwords_' + suffix + '.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  // Set the active vault DB and AAD (must be called after unlock)
  void setActiveVault(ActiveVaultDb vault, {Uint8List? aad}) {
    _activeVault = vault;
    _aad = aad;
  }

  // Create database tables
  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE passwords (
        id TEXT PRIMARY KEY,
        encrypted_title TEXT NOT NULL,
        encrypted_username TEXT NOT NULL,
        encrypted_password TEXT NOT NULL,
        encrypted_url TEXT NOT NULL,
        encrypted_notes TEXT NOT NULL,
        encrypted_tags TEXT NOT NULL,
        fingerprint TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  // Save password entry
  Future<void> savePassword(PasswordEntry entry, Uint8List vaultKey) async {
    final db = await database;

    try {
      // Convert to map and encrypt
      final entryMap = entry.toMap();
      final encryptedEntry = _encryptionService.encryptPasswordEntry(entryMap, vaultKey, aad: _aad);

      // Compute fingerprint from plaintext fields (normalized)
      final fingerprint = _computeFingerprint(
        title: entry.title,
        username: entry.username,
        url: entry.url,
        vaultKey: vaultKey,
      );

      // Insert or update in database
      await db.insert(
        'passwords',
        {
          ...encryptedEntry,
          'fingerprint': fingerprint,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } finally {
      // Clear sensitive data from memory
      _encryptionService.clearSensitiveData([
        entry.title,
        entry.username,
        entry.password,
        entry.url,
        entry.notes,
        entry.tags.join(','),
      ]);
    }
  }

  // Save password entry for imports: ignore on duplicate fingerprint
  Future<bool> savePasswordImport(PasswordEntry entry, Uint8List vaultKey) async {
    final db = await database;

    try {
      final entryMap = entry.toMap();
      final encryptedEntry = _encryptionService.encryptPasswordEntry(entryMap, vaultKey, aad: _aad);

      final fingerprint = _computeFingerprint(
        title: entry.title,
        username: entry.username,
        url: entry.url,
        vaultKey: vaultKey,
      );

      final row = {
        ...encryptedEntry,
        'fingerprint': fingerprint,
      };

      final id = await db.insert(
        'passwords',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return id != 0; // id == 0 when ignored in sqflite
    } finally {
      _encryptionService.clearSensitiveData([
        entry.title,
        entry.username,
        entry.password,
        entry.url,
        entry.notes,
        entry.tags.join(','),
      ]);
    }
  }

  // Compute deterministic, per-vault fingerprint for duplicate detection
  String _computeFingerprint({
    required String title,
    required String username,
    required String url,
    required Uint8List vaultKey,
  }) {
    String normalize(String s) => s.trim().toLowerCase();
    final data = '${normalize(title)}|${normalize(username)}|${normalize(url)}';
    final hmac = crypto.Hmac(crypto.sha256, vaultKey);
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString();
  }

  // Get password entry by ID
  Future<PasswordEntry?> getPassword(String id, Uint8List vaultKey) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> results = await db.query(
        'passwords',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (results.isEmpty) return null;

      // Decrypt the entry
      final decryptedEntry = _encryptionService.decryptPasswordEntry(results.first, vaultKey, aad: _aad);
      return PasswordEntry.fromMap(decryptedEntry);
    } catch (e) {
      print('Error retrieving password: $e');
      return null;
    }
  }

  // Get all passwords
  Future<List<PasswordEntry>> getAllPasswords(Uint8List vaultKey) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> results = await db.query(
        'passwords',
        orderBy: 'updated_at DESC',
      );

      final List<PasswordEntry> passwords = [];
      for (final encryptedEntry in results) {
        try {
          final decryptedEntry = _encryptionService.decryptPasswordEntry(encryptedEntry, vaultKey, aad: _aad);
          passwords.add(PasswordEntry.fromMap(decryptedEntry));
        } catch (e) {
          print('Error decrypting password entry: $e');
          // Skip corrupted entries
          continue;
        }
      }

      return passwords;
    } catch (e) {
      print('Error retrieving all passwords: $e');
      return [];
    }
  }

  // Search passwords
  Future<List<PasswordEntry>> searchPasswords(String query, Uint8List vaultKey) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> results = await db.query(
        'passwords',
        orderBy: 'updated_at DESC',
      );

      final List<PasswordEntry> matchingPasswords = [];
      for (final encryptedEntry in results) {
        try {
          final decryptedEntry = _encryptionService.decryptPasswordEntry(encryptedEntry, vaultKey, aad: _aad);
          final title = decryptedEntry['title'] as String;
          final username = decryptedEntry['username'] as String;
          final url = decryptedEntry['url'] as String;

          // Search in title, username, and URL
          if (title.toLowerCase().contains(query.toLowerCase()) ||
              username.toLowerCase().contains(query.toLowerCase()) ||
              url.toLowerCase().contains(query.toLowerCase())) {
            matchingPasswords.add(PasswordEntry.fromMap(decryptedEntry));
          }
        } catch (e) {
          print('Error decrypting password entry during search: $e');
          continue;
        }
      }

      return matchingPasswords;
    } catch (e) {
      print('Error searching passwords: $e');
      return [];
    }
  }

  // Delete password entry
  Future<bool> deletePassword(String id) async {
    final db = await database;

    try {
      final int count = await db.delete(
        'passwords',
        where: 'id = ?',
        whereArgs: [id],
      );
      return count > 0;
    } catch (e) {
      print('Error deleting password: $e');
      return false;
    }
  }

  // Get password count
  Future<int> getPasswordCount() async {
    final db = await database;

    try {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM passwords');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print('Error getting password count: $e');
      return 0;
    }
  }

  // Clear all passwords (for testing or reset)
  Future<void> clearAllPasswords() async {
    final db = await database;

    try {
      await db.delete('passwords');
    } catch (e) {
      print('Error clearing passwords: $e');
    }
  }

  // Close database
  Future<void> close() async {
    for (final db in _dbByVault.values) {
      await db.close();
    }
    _dbByVault.clear();
  }
}
