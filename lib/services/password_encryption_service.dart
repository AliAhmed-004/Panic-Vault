import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

class PasswordEncryptionService {
  // Encrypt a string field using AES-GCM
  String encryptField(String plaintext, Uint8List vaultKey, {Uint8List? aad}) {
    if (plaintext.isEmpty) return '';
    
    final plaintextBytes = utf8.encode(plaintext);
    final iv = Uint8List.fromList(List.generate(12, (_) => Random.secure().nextInt(256)));
    
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(vaultKey), 128, iv, aad ?? Uint8List(0)));

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
  String decryptField(String encryptedText, Uint8List vaultKey, {Uint8List? aad}) {
    if (encryptedText.isEmpty) return '';
    
    final data = base64Decode(encryptedText);
    final iv = data.sublist(0, 12);
    final tag = data.sublist(12, 28);
    final ciphertext = data.sublist(28);

    final ciphertextWithTag = Uint8List(ciphertext.length + tag.length);
    ciphertextWithTag.setAll(0, ciphertext);
    ciphertextWithTag.setAll(ciphertext.length, tag);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(vaultKey), 128, iv, aad ?? Uint8List(0)));

    final decryptedBytes = cipher.process(ciphertextWithTag);
    return utf8.decode(decryptedBytes);
  }

  // Encrypt a PasswordEntry (all sensitive fields)
  Map<String, dynamic> encryptPasswordEntry(Map<String, dynamic> entry, Uint8List vaultKey, {Uint8List? aad}) {
    return {
      'id': entry['id'], // Keep ID unencrypted for database operations
      'encrypted_title': encryptField(entry['title'], vaultKey, aad: aad),
      'encrypted_username': encryptField(entry['username'], vaultKey, aad: aad),
      'encrypted_password': encryptField(entry['password'], vaultKey, aad: aad),
      'encrypted_url': encryptField(entry['url'], vaultKey, aad: aad),
      'encrypted_notes': encryptField(entry['notes'], vaultKey, aad: aad),
      'encrypted_tags': encryptField(entry['tags'], vaultKey, aad: aad),
      'created_at': entry['created_at'], // Keep timestamps unencrypted
      'updated_at': entry['updated_at'],
    };
  }

  // Decrypt a PasswordEntry (all sensitive fields)
  Map<String, dynamic> decryptPasswordEntry(Map<String, dynamic> encryptedEntry, Uint8List vaultKey, {Uint8List? aad}) {
    return {
      'id': encryptedEntry['id'],
      'title': decryptField(encryptedEntry['encrypted_title'], vaultKey, aad: aad),
      'username': decryptField(encryptedEntry['encrypted_username'], vaultKey, aad: aad),
      'password': decryptField(encryptedEntry['encrypted_password'], vaultKey, aad: aad),
      'url': decryptField(encryptedEntry['encrypted_url'], vaultKey, aad: aad),
      'notes': decryptField(encryptedEntry['encrypted_notes'], vaultKey, aad: aad),
      'tags': decryptField(encryptedEntry['encrypted_tags'], vaultKey, aad: aad),
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
