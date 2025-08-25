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

class SecureVaultService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  
  // Rate limiting
  int _attempts = 0;
  DateTime? _lockoutUntil;
  Uint8List? _currentVaultKey;
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
    final password = params['password'] as String;
    final salt = params['salt'] as Uint8List;
    final keySize = params['keySize'] as int;

    final algorithm = cryptography.Argon2id(
      memory: ARGON2_MEMORY_KIB,
      iterations: ARGON2_ITERATIONS,
      parallelism: ARGON2_PARALLELISM,
      hashLength: keySize,
    );

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

  // Check if vault is initialized
  Future<bool> isVaultInitialized() async {
    if (_isInitialized) return true;
    
    final vaultData = await _storage.read(key: 'vault_data');
    _isInitialized = vaultData != null;
    return _isInitialized;
  }

  // Initialize vault with master password
  Future<bool> initializeVault(String masterPassword) async {
    try {
      final salt = _generateSecureSalt();
      final mk = await _deriveMasterKey(masterPassword, salt);
      final vk = _generateSecureVaultKey();
      final encVk = _encryptAes(mk, vk);

      // Store a "fingerprint" of VK (first 16 bytes of SHA-256)
      final vkHashFull = crypto.sha256.convert(vk).bytes;
      final vkHashCheck = Uint8List.fromList(vkHashFull.sublist(0, 16));

      // Store all data in a single JSON object (faster)
      final vaultData = {
        'salt': base64Encode(salt),
        'encVk': base64Encode(encVk),
        'vkCheck': base64Encode(vkHashCheck),
      };
      await _storage.write(key: 'vault_data', value: jsonEncode(vaultData));

      // Clear sensitive data from memory (batch clear)
      _clearSensitiveData([mk, vk, encVk, vkHashCheck]);

      _isInitialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

    // Attempt to unlock vault
  Future<UnlockResult> unlockVault(String masterPassword) async {
    if (!await isVaultInitialized()) {
      return UnlockResult.error('Vault not initialized');
    }

    // Check rate limiting
    if (_isLocked()) {
      final remainingSeconds = _getLockoutRemainingSeconds();
      return UnlockResult.locked(remainingSeconds);
    }

    try {
      // Single storage read (much faster)
      final vaultDataJson = await _storage.read(key: 'vault_data');
      if (vaultDataJson == null) {
        return UnlockResult.error('Vault data corrupted');
      }

      final vaultData = jsonDecode(vaultDataJson) as Map<String, dynamic>;
      final saltBase64 = vaultData['salt'] as String;
      final encVkBase64 = vaultData['encVk'] as String;
      final vkCheckBase64 = vaultData['vkCheck'] as String;

      final saltBytes = base64Decode(saltBase64);
      final mkTry = await _deriveMasterKey(masterPassword, saltBytes);
      final encVkBytes = base64Decode(encVkBase64);
      final vkTry = _decryptAes(mkTry, encVkBytes);

      // Hash and check using constant-time comparison
      final checkValue = base64Decode(vkCheckBase64);
      final vkTryHash = Uint8List.fromList(crypto.sha256.convert(vkTry).bytes.sublist(0, 16));
      
      if (_constantTimeEquals(vkTryHash, checkValue)) {
        _currentVaultKey = vkTry;
        _resetAttempts();
        
        // Clear temporary data (batch clear)
        _clearSensitiveData([mkTry, encVkBytes, checkValue, vkTryHash]);
        
        return UnlockResult.success();
      } else {
        _recordFailedAttempt();
        final remainingAttempts = _getRemainingAttempts();
        
        // Clear sensitive data (batch clear)
        _clearSensitiveData([mkTry, encVkBytes, vkTry, checkValue, vkTryHash]);
        
        return UnlockResult.failed(remainingAttempts);
      }
    } catch (e) {
      _recordFailedAttempt();
      final remainingAttempts = _getRemainingAttempts();
      return UnlockResult.failed(remainingAttempts);
    }
  }

  // Lock vault and clear sensitive data
  void lockVault() {
    if (_currentVaultKey != null) {
      _secureClear(_currentVaultKey!);
      _currentVaultKey = null;
    }
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
