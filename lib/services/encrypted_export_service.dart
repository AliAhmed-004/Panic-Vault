import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

/// Service to export/import encrypted CSV backups.
///
/// Format (CSV):
///   Headers: type,version,meta,data
///   Row:
///     type:    "encrypted"
///     version: "1"
///     meta:    base64(JSON) -> { "format":"panic-vault-export","schema":"entries-v1",
///                                "kdf":"argon2id","memory_kib":65536,"iterations":3,"parallelism":2,
///                                "salt":"...","iv":"...","created_at":"ISO-8601" }
///     data:    base64(ciphertextWithTag) where AES-GCM(IV, plaintext-json)
class EncryptedExportService {
  // Argon2id params (align with SecureVaultService)
  static const int _memoryKiB = 65536; // 64 MiB
  static const int _iterations = 3;
  static const int _parallelism = 2;
  static const int _keySize = 32; // 256-bit

  // Derive key using Argon2id
  static Future<Uint8List> _deriveKey(String passphrase, Uint8List salt) async {
    final algo = cryptography.Argon2id(
      memory: _memoryKiB,
      iterations: _iterations,
      parallelism: _parallelism,
      hashLength: _keySize,
    );
    final secretKey = await algo.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  // AES-GCM encrypt returning ciphertext||tag (without IV)
  static Uint8List _encryptAesGcm(Uint8List key, Uint8List iv, Uint8List plaintext) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final ct = cipher.process(plaintext); // contains ciphertext||tag
    return ct;
  }

  // AES-GCM decrypt from ciphertext||tag (IV provided separately)
  static Uint8List _decryptAesGcm(Uint8List key, Uint8List iv, Uint8List ciphertextWithTag) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final pt = cipher.process(ciphertextWithTag);
    return pt;
  }

  // Export: returns CSV bytes
  Future<Uint8List> exportEncryptedCsv({
    required List<Map<String, dynamic>> entries,
    required String passphrase,
  }) async {
    // Build plaintext JSON
    final payload = jsonEncode({
      'format': 'panic-vault-export',
      'schema': 'entries-v1',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'entries': entries,
    });

    // Derive key
    final salt = Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)));
    final iv = Uint8List.fromList(List.generate(12, (_) => Random.secure().nextInt(256)));
    final key = await _deriveKey(passphrase, salt);

    final ciphertextWithTag = _encryptAesGcm(key, iv, Uint8List.fromList(utf8.encode(payload)));

    // Build meta JSON
    final meta = {
      'format': 'panic-vault-export',
      'schema': 'entries-v1',
      'kdf': 'argon2id',
      'memory_kib': _memoryKiB,
      'iterations': _iterations,
      'parallelism': _parallelism,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'version': 1,
    };

    final rows = [
      ['type', 'version', 'meta', 'data'],
      [
        'encrypted',
        '1',
        base64Encode(utf8.encode(jsonEncode(meta))),
        base64Encode(ciphertextWithTag),
      ]
    ];

    final csv = const ListToCsvConverter().convert(rows);
    return Uint8List.fromList(utf8.encode(csv));
  }

  bool isEncryptedCsv(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    if (lines.length < 2) return false;
    final headers = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(lines.take(1).join('\n'))
        .first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();
    if (headers.length < 4) return false;
    if (!(headers[0] == 'type' && headers[1] == 'version' && headers[2] == 'meta' && headers[3] == 'data')) {
      return false;
    }
    final row = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(lines.take(2).join('\n'));
    if (row.length < 2) return false;
    final firstRow = row[1];
    if (firstRow.isEmpty) return false;
    final typeVal = firstRow[0].toString().trim().toLowerCase();
    return typeVal == 'encrypted';
  }

  Future<List<Map<String, dynamic>>> decryptEncryptedCsv({
    required String content,
    required String passphrase,
  }) async {
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    );
    if (rows.length < 2) {
      throw Exception('Invalid encrypted CSV: missing data');
    }
    final dataRow = rows[1];
    if (dataRow.length < 4) {
      throw Exception('Invalid encrypted CSV: incomplete row');
    }
    final metaB64 = dataRow[2].toString();
    final dataB64 = dataRow[3].toString();
    final metaJson = utf8.decode(base64Decode(metaB64));
    final meta = jsonDecode(metaJson) as Map<String, dynamic>;

    final salt = base64Decode(meta['salt'] as String);
    final iv = base64Decode(meta['iv'] as String);

    final key = await _deriveKey(passphrase, Uint8List.fromList(salt));
    final ciphertextWithTag = Uint8List.fromList(base64Decode(dataB64));

    final plaintext = _decryptAesGcm(key, Uint8List.fromList(iv), ciphertextWithTag);
    final payload = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    if (payload['entries'] is List) {
      final list = (payload['entries'] as List).cast<Map<String, dynamic>>();
      return list;
    } else {
      throw Exception('Invalid payload format');
    }
  }
}
