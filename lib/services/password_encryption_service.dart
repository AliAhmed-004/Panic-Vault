import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes_fast.dart';
import 'package:pointycastle/block/modes/gcm.dart';

class PasswordEncryptionService {
  // Encrypt a string field using AES-GCM
  String encryptField(String plaintext, Uint8List vaultKey) {
    if (plaintext.isEmpty) return '';
    
    final plaintextBytes = utf8.encode(plaintext);
    final iv = Uint8List.fromList(List.generate(12, (_) => Random.secure().nextInt(256)));
    
    final cipher = GCMBlockCipher(AESFastEngine())
      ..init(true, AEADParameters(KeyParameter(vaultKey), 128, iv, Uint8List(0)));

    final ciphertext = cipher.process(Uint8List.fromList(plaintextBytes));
    final tag = ciphertext.sublist(ciphertext.length - 16);
    final encryptedData = ciphertext.sublist(0, ciphertext.length - 16);

    // Concatenate: IV (12 bytes) + Tag (16 bytes) + Ciphertext
    final result = Uint8List(iv.length + tag.length + encryptedData.length);
    result.setAll(0, iv);
    result.setAll(iv.length, tag);
    result.setAll(iv.length + tag.length, encryptedData);
    
    return base64Encode(result);
  }

  // Decrypt a string field using AES-GCM
  String decryptField(String encryptedText, Uint8List vaultKey) {
    if (encryptedText.isEmpty) return '';
    
    final data = base64Decode(encryptedText);
    final iv = data.sublist(0, 12);
    final tag = data.sublist(12, 28);
    final ciphertext = data.sublist(28);

    final ciphertextWithTag = Uint8List(ciphertext.length + tag.length);
    ciphertextWithTag.setAll(0, ciphertext);
    ciphertextWithTag.setAll(ciphertext.length, tag);

    final cipher = GCMBlockCipher(AESFastEngine())
      ..init(false, AEADParameters(KeyParameter(vaultKey), 128, iv, Uint8List(0)));

    final decryptedBytes = cipher.process(ciphertextWithTag);
    return utf8.decode(decryptedBytes);
  }

  // Encrypt a PasswordEntry (all sensitive fields)
  Map<String, dynamic> encryptPasswordEntry(Map<String, dynamic> entry, Uint8List vaultKey) {
    return {
      'id': entry['id'], // Keep ID unencrypted for database operations
      'encrypted_title': encryptField(entry['title'], vaultKey),
      'encrypted_username': encryptField(entry['username'], vaultKey),
      'encrypted_password': encryptField(entry['password'], vaultKey),
      'encrypted_url': encryptField(entry['url'], vaultKey),
      'encrypted_notes': encryptField(entry['notes'], vaultKey),
      'encrypted_tags': encryptField(entry['tags'], vaultKey),
      'created_at': entry['created_at'], // Keep timestamps unencrypted
      'updated_at': entry['updated_at'],
    };
  }

  // Decrypt a PasswordEntry (all sensitive fields)
  Map<String, dynamic> decryptPasswordEntry(Map<String, dynamic> encryptedEntry, Uint8List vaultKey) {
    return {
      'id': encryptedEntry['id'],
      'title': decryptField(encryptedEntry['encrypted_title'], vaultKey),
      'username': decryptField(encryptedEntry['encrypted_username'], vaultKey),
      'password': decryptField(encryptedEntry['encrypted_password'], vaultKey),
      'url': decryptField(encryptedEntry['encrypted_url'], vaultKey),
      'notes': decryptField(encryptedEntry['encrypted_notes'], vaultKey),
      'tags': decryptField(encryptedEntry['encrypted_tags'], vaultKey),
      'created_at': encryptedEntry['created_at'],
      'updated_at': encryptedEntry['updated_at'],
    };
  }

  // Clear sensitive data from memory
  void clearSensitiveData(List<String> sensitiveData) {
    for (final data in sensitiveData) {
      final bytes = utf8.encode(data);
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = 0;
      }
    }
  }
}
