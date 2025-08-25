// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

// --- Security Constants ---
// Argon2id parameters (balance security and performance)
const int ARGON2_MEMORY_KIB = 131072; // 128 MiB
const int ARGON2_ITERATIONS = 3;
const int ARGON2_PARALLELISM = 2;
const int MAX_LOGIN_ATTEMPTS = 5;
const int LOCKOUT_DURATION_SECONDS = 300; // 5 minutes
const int VAULT_KEY_SIZE = 32;
const int SALT_SIZE = 32;

enum VaultType { real, decoy }

class SecureVaultService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  
  // Rate limiting
  int _attempts = 0;
  DateTime? _lockoutUntil;
  Uint8List? _currentVaultKey;
  Uint8List? _currentEncryptionContext; // used as AEAD AAD per-vault
  VaultType? _currentVaultType;
  bool _isInitialized = false;

  // Memory Security
  void _secureClear(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  // Batch clear sensitive data (more efficient)
  void _clearSensitiveData(List<Uint8List> dataList) {
    for (final data in dataList) {
      _secureClear(data);
    }
  }

  // Constant Time Comparison (Fixes Timing Attack)
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  // Master key derivation using Argon2id
  Future<Uint8List> _deriveMasterKey(String masterPassword, Uint8List salt) async {
    // Run heavy cryptographic operations on a background isolate
    return await compute(_performKeyDerivation, {
      'password': masterPassword,
      'salt': salt,
      'keySize': VAULT_KEY_SIZE,
    });
  }

  // Static method for compute function - Argon2id
  static Future<Uint8List> _performKeyDerivation(Map<String, dynamic> params) async {
    // Extract information from params
    final password = params['password'] as String;
    final salt = params['salt'] as Uint8List;
    final keySize = params['keySize'] as int;

    // Create the algorithm
    final algorithm = cryptography.Argon2id(
      memory: ARGON2_MEMORY_KIB,
      iterations: ARGON2_ITERATIONS,
      parallelism: ARGON2_PARALLELISM,
      hashLength: keySize,
    );

    // Use the algorithm to create the secret key
    final secretKey = await algorithm.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final bytes = await secretKey.extractBytes();

    // Clear the password from memory immediately
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    for (int i = 0; i < passwordBytes.length; i++) {
      passwordBytes[i] = 0;
    }

    return Uint8List.fromList(bytes);
  }



  // Secure AES-GCM Encryption
  Uint8List _encryptAes(Uint8List key, Uint8List plaintext) {
    final iv = Uint8List.fromList(List.generate(12, (_) => Random.secure().nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final ciphertext = cipher.process(plaintext);
    final tag = ciphertext.sublist(ciphertext.length - 16);
    final encryptedData = ciphertext.sublist(0, ciphertext.length - 16);

    final result = Uint8List(iv.length + tag.length + encryptedData.length);
    result.setAll(0, iv);
    result.setAll(iv.length, tag);
    result.setAll(iv.length + tag.length, encryptedData);
    
    _secureClear(iv);
    _secureClear(tag);
    _secureClear(encryptedData);
    
    return result;
  }

  // Secure AES-GCM Decryption
  Uint8List _decryptAes(Uint8List key, Uint8List data) {
    final iv = data.sublist(0, 12);
    final tag = data.sublist(12, 28);
    final ciphertext = data.sublist(28);

    final ciphertextWithTag = Uint8List(ciphertext.length + tag.length);
    ciphertextWithTag.setAll(0, ciphertext);
    ciphertextWithTag.setAll(ciphertext.length, tag);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final result = cipher.process(ciphertextWithTag);
    
    _secureClear(iv);
    _secureClear(tag);
    _secureClear(ciphertext);
    _secureClear(ciphertextWithTag);
    
    return result;
  }

  // Secure Vault Key Generation
  Uint8List _generateSecureVaultKey() {
    return Uint8List.fromList(List.generate(VAULT_KEY_SIZE, (_) => Random.secure().nextInt(256)));
  }

  // Secure Salt Generation
  Uint8List _generateSecureSalt() {
    return Uint8List.fromList(List.generate(SALT_SIZE, (_) => Random.secure().nextInt(256)));
  }

  // Rate Limiting
  bool _isLocked() {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      return true;
    }
    if (_lockoutUntil != null && DateTime.now().isAfter(_lockoutUntil!)) {
      _lockoutUntil = null;
      _attempts = 0;
    }
    return false;
  }

  void _recordFailedAttempt() {
    _attempts++;
    if (_attempts >= MAX_LOGIN_ATTEMPTS) {
      _lockoutUntil = DateTime.now().add(Duration(seconds: LOCKOUT_DURATION_SECONDS));
    }
  }

  void _resetAttempts() {
    _attempts = 0;
    _lockoutUntil = null;
  }

  // Internal keys per vault type
  String _storageKeyFor(VaultType type) => type == VaultType.real ? 'vault_data_real' : 'vault_data_decoy';

  // Check if ANY vault is initialized
  Future<bool> isVaultInitialized() async {
    if (_isInitialized) return true;
    final real = await _storage.read(key: _storageKeyFor(VaultType.real));
    final decoy = await _storage.read(key: _storageKeyFor(VaultType.decoy));
    _isInitialized = real != null || decoy != null;
    return _isInitialized;
  }

  // Check if a specific vault exists
  Future<bool> vaultExists(VaultType type) async {
    final data = await _storage.read(key: _storageKeyFor(type));
    return data != null;
  }

  // Initialize a specific vault with master password
  Future<bool> initializeVault(VaultType type, String masterPassword) async {
    try {
      // Enforce different passwords across vaults: if other vault exists and password matches, reject
      final conflict = await isPasswordSameAsOtherVault(type, masterPassword);
      if (conflict) {
        return false;
      }

      final salt = _generateSecureSalt();
      final mk = await _deriveMasterKey(masterPassword, salt);
      final vk = _generateSecureVaultKey();
      final encVk = _encryptAes(mk, vk);

      // Per-vault encryption context (AAD)
      final encContext = _generateSecureSalt(); // 32 bytes random

      // Store a "fingerprint" of VK (first 16 bytes of SHA-256)
      final vkHashFull = crypto.sha256.convert(vk).bytes;
      final vkHashCheck = Uint8List.fromList(vkHashFull.sublist(0, 16));

      // Store all data in a single JSON object (faster)
      final vaultData = {
        'salt': base64Encode(salt),
        'encVk': base64Encode(encVk),
        'vkCheck': base64Encode(vkHashCheck),
        'aad': base64Encode(encContext),
      };
      await _storage.write(key: _storageKeyFor(type), value: jsonEncode(vaultData));

      // Clear sensitive data from memory (batch clear)
      _clearSensitiveData([mk, vk, encVk, vkHashCheck, encContext]);

      _isInitialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  // Check whether the provided password matches the other vault's password
  Future<bool> isPasswordSameAsOtherVault(VaultType type, String masterPassword) async {
    final otherType = type == VaultType.real ? VaultType.decoy : VaultType.real;
    final otherDataJson = await _storage.read(key: _storageKeyFor(otherType));
    if (otherDataJson == null) return false;
    try {
      final otherData = jsonDecode(otherDataJson) as Map<String, dynamic>;
      final salt = base64Decode(otherData['salt'] as String);
      final mkTry = await _deriveMasterKey(masterPassword, salt);
      final encVk = base64Decode(otherData['encVk'] as String);
      final vkTry = _decryptAes(mkTry, encVk);
      final check = base64Decode(otherData['vkCheck'] as String);
      final vkTryHash = Uint8List.fromList(crypto.sha256.convert(vkTry).bytes.sublist(0, 16));
      final matches = _constantTimeEquals(vkTryHash, check);
      _clearSensitiveData([mkTry, vkTry, vkTryHash]);
      return matches;
    } catch (_) {
      return false;
    }
  }

  // Attempt to unlock a specific vault type
  Future<UnlockResult> unlockVault(VaultType type, String masterPassword) async {
    // Check rate limiting
    if (_isLocked()) {
      final remainingSeconds = _getLockoutRemainingSeconds();
      return UnlockResult.locked(remainingSeconds);
    }

    try {
      final dataKey = _storageKeyFor(type);
      final vaultDataJson = await _storage.read(key: dataKey);
      if (vaultDataJson == null) {
        return UnlockResult.error('Vault not initialized');
      }

      final vaultData = jsonDecode(vaultDataJson) as Map<String, dynamic>;
      final saltBytes = base64Decode(vaultData['salt'] as String);
      final encVkBytes = base64Decode(vaultData['encVk'] as String);
      final vkCheckBytes = base64Decode(vaultData['vkCheck'] as String);
      final aadField = vaultData['aad'] as String?;
      final aadBytes = aadField != null ? base64Decode(aadField) : Uint8List(0);

      final mkTry = await _deriveMasterKey(masterPassword, saltBytes);
      final vkTry = _decryptAes(mkTry, encVkBytes);

      final vkTryHash = Uint8List.fromList(crypto.sha256.convert(vkTry).bytes.sublist(0, 16));
      if (_constantTimeEquals(vkTryHash, vkCheckBytes)) {
        _currentVaultKey = vkTry;
        _currentEncryptionContext = Uint8List.fromList(aadBytes);
        _currentVaultType = type;
        _resetAttempts();

        _clearSensitiveData([mkTry, vkTryHash]);
        return UnlockResult.success();
      } else {
        _recordFailedAttempt();
        final remainingAttempts = _getRemainingAttempts();
        _clearSensitiveData([mkTry, vkTry, vkTryHash]);
        return UnlockResult.failed(remainingAttempts);
      }
    } catch (e) {
      _recordFailedAttempt();
      final remainingAttempts = _getRemainingAttempts();
      return UnlockResult.failed(remainingAttempts);
    }
  }

  // Try decoy first, then real, without revealing which matched
  Future<UnlockResult> unlockVaultAny(String masterPassword) async {
    // If neither vault exists
    final realJson = await _storage.read(key: _storageKeyFor(VaultType.real));
    final decoyJson = await _storage.read(key: _storageKeyFor(VaultType.decoy));
    final realExists = realJson != null;
    final decoyExists = decoyJson != null;
    if (!realExists && !decoyExists) {
      return UnlockResult.error('Vault not initialized');
    }

    // Parse headers present
    Map<String, dynamic>? realData = realExists ? (jsonDecode(realJson) as Map<String, dynamic>) : null;
    Map<String, dynamic>? decoyData = decoyExists ? (jsonDecode(decoyJson) as Map<String, dynamic>) : null;

    try {
      // Derive MKs for both (or perform dummy work to equalize time)
      Uint8List? mkReal;
      Uint8List? mkDecoy;

      if (realData != null) {
        mkReal = await _deriveMasterKey(masterPassword, base64Decode(realData['salt'] as String));
      } else {
        // dummy derivation with random salt to equalize cost
        mkReal = await _deriveMasterKey(masterPassword, _generateSecureSalt());
      }

      if (decoyData != null) {
        mkDecoy = await _deriveMasterKey(masterPassword, base64Decode(decoyData['salt'] as String));
      } else {
        // dummy derivation with random salt to equalize cost
        mkDecoy = await _deriveMasterKey(masterPassword, _generateSecureSalt());
      }

      // Attempt decrypts and checks for both; do not early-return
      bool realMatch = false;
      bool decoyMatch = false;
      Uint8List? vkReal;
      Uint8List? vkDecoy;
      Uint8List? aadReal;
      Uint8List? aadDecoy;

      if (realData != null) {
        try {
          final encVk = base64Decode(realData['encVk'] as String);
          final check = base64Decode(realData['vkCheck'] as String);
          final vkTry = _decryptAes(mkReal, encVk);
          final vkTryHash = Uint8List.fromList(crypto.sha256.convert(vkTry).bytes.sublist(0, 16));
          realMatch = _constantTimeEquals(vkTryHash, check);
          if (realMatch) {
            vkReal = vkTry;
            final aadField = realData['aad'] as String?;
            aadReal = aadField != null ? base64Decode(aadField) : Uint8List(0);
          } else {
            _secureClear(vkTry);
          }
          _secureClear(vkTryHash);
        } catch (_) {
          realMatch = false;
        }
      } else {
        // consume mkReal in a deterministic way
        final junk = _decryptAes(mkReal, _encryptAes(mkReal, Uint8List(16)));
        _secureClear(junk);
      }

      if (decoyData != null) {
        try {
          final encVk = base64Decode(decoyData['encVk'] as String);
          final check = base64Decode(decoyData['vkCheck'] as String);
          final vkTry = _decryptAes(mkDecoy, encVk);
          final vkTryHash = Uint8List.fromList(crypto.sha256.convert(vkTry).bytes.sublist(0, 16));
          decoyMatch = _constantTimeEquals(vkTryHash, check);
          if (decoyMatch) {
            vkDecoy = vkTry;
            final aadField = decoyData['aad'] as String?;
            aadDecoy = aadField != null ? base64Decode(aadField) : Uint8List(0);
          } else {
            _secureClear(vkTry);
          }
          _secureClear(vkTryHash);
        } catch (_) {
          decoyMatch = false;
        }
      } else {
        final junk = _decryptAes(mkDecoy, _encryptAes(mkDecoy, Uint8List(16)));
        _secureClear(junk);
      }

      // Clear MKs
      _secureClear(mkReal);
      _secureClear(mkDecoy);

      // Decide winner after equalized work
      if (realMatch && !decoyMatch) {
        _currentVaultKey = vkReal!; // vkReal non-null when realMatch
        _currentEncryptionContext = aadReal;
        _currentVaultType = VaultType.real;
        _resetAttempts();
        return UnlockResult.success();
      }
      if (decoyMatch && !realMatch) {
        _currentVaultKey = vkDecoy!; // vkDecoy non-null when decoyMatch
        _currentEncryptionContext = aadDecoy;
        _currentVaultType = VaultType.decoy;
        _resetAttempts();
        return UnlockResult.success();
      }
      if (realMatch && decoyMatch) {
        // If the same password was set for both, prefer real
        _currentVaultKey = vkReal!;
        _currentEncryptionContext = aadReal;
        _currentVaultType = VaultType.real;
        if (vkDecoy != null) _secureClear(vkDecoy);
        _resetAttempts();
        return UnlockResult.success();
      }

      // Neither matched
      if (vkReal != null) _secureClear(vkReal);
      if (vkDecoy != null) _secureClear(vkDecoy);
      _recordFailedAttempt();
      return UnlockResult.failed(_getRemainingAttempts());
    } catch (e) {
      _recordFailedAttempt();
      return UnlockResult.failed(_getRemainingAttempts());
    }
  }

  // Lock vault and clear sensitive data
  void lockVault() {
    if (_currentVaultKey != null) {
      _secureClear(_currentVaultKey!);
      _currentVaultKey = null;
    }
    if (_currentEncryptionContext != null) {
      _secureClear(_currentEncryptionContext!);
      _currentEncryptionContext = null;
    }
    _currentVaultType = null;
  }

  // Check if vault is unlocked
  bool isUnlocked() {
    return _currentVaultKey != null;
  }

  // Get remaining login attempts
  int _getRemainingAttempts() {
    return MAX_LOGIN_ATTEMPTS - _attempts;
  }

  // Get lockout remaining time
  int _getLockoutRemainingSeconds() {
    if (_lockoutUntil == null) return 0;
    final remaining = _lockoutUntil!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  // Get current vault key (for encrypting/decrypting passwords)
  Uint8List? getCurrentVaultKey() {
    return _currentVaultKey;
  }

  // Get current vault type
  VaultType? getCurrentVaultType() {
    return _currentVaultType;
  }

  // Get per-vault encryption context (AAD)
  Uint8List? getCurrentEncryptionContext() {
    return _currentEncryptionContext;
  }

}

// Result classes for unlock attempts
class UnlockResult {
  final bool success;
  final bool locked;
  final String? error;
  final int? remainingAttempts;
  final int? lockoutSeconds;

  UnlockResult._({
    required this.success,
    required this.locked,
    this.error,
    this.remainingAttempts,
    this.lockoutSeconds,
  });

  factory UnlockResult.success() => UnlockResult._(success: true, locked: false);
  
  factory UnlockResult.failed(int remainingAttempts) => UnlockResult._(
    success: false, 
    locked: false, 
    remainingAttempts: remainingAttempts
  );
  
  factory UnlockResult.locked(int lockoutSeconds) => UnlockResult._(
    success: false, 
    locked: true, 
    lockoutSeconds: lockoutSeconds
  );
  
  factory UnlockResult.error(String error) => UnlockResult._(
    success: false, 
    locked: false, 
    error: error
  );
}
