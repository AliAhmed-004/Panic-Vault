import 'dart:convert';
import 'package:csv/csv.dart';

class CsvImportService {
  /// Parses Dashlane-exported CSV content and returns a list of row maps.
  /// Handles both comma- and tab-delimited variants.
  /// Expected headers include:
  /// user_name, user_name_2, user_name_3, title, password, note, url, category, otp
  List<Map<String, String>> parseDashlaneCsv(String csvContent) {
    if (csvContent.trim().isEmpty) return [];

    // Normalize newlines
    final normalized = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final firstLine = normalized.split('\n').first;
    final delimiter = firstLine.contains('\t') ? '\t' : ',';

    final rows = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(normalized);

    if (rows.isEmpty) return [];

    // Build headers
    final headers = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList(growable: false);

    final List<Map<String, String>> result = [];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final Map<String, String> m = {};
      for (int j = 0; j < headers.length && j < row.length; j++) {
        m[headers[j]] = row[j]?.toString() ?? '';
      }
      // Skip completely empty rows (no title and password)
      final title = (m['title'] ?? '').trim();
      final password = (m['password'] ?? '').trim();
      if (title.isEmpty && password.isEmpty) continue;
      result.add(m);
    }
    return result;
  }

  /// Maps a parsed Dashlane row map to a normalized map understood by PasswordEntry.
  Map<String, String> mapDashlaneRowToEntryFields(Map<String, String> row) {
    String pickNonEmpty(List<String?> values) {
      for (final v in values) {
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final username = pickNonEmpty([
      row['user_name'],
      row['user_name_2'],
      row['user_name_3'],
    ]);

    // Compose notes: include original note plus category/otp if present
    final note = [
      row['note']?.trim() ?? '',
      (row['category'] != null && row['category']!.trim().isNotEmpty)
          ? 'Category: ${row['category']!.trim()}'
          : '',
      (row['otp'] != null && row['otp']!.trim().isNotEmpty)
          ? 'OTP: ${row['otp']!.trim()}'
          : '',
    ].where((s) => s.isNotEmpty).join('\n');

    // Optionally turn category into a tag
    final tags = <String>[];
    if ((row['category'] ?? '').trim().isNotEmpty) {
      tags.add(row['category']!.trim());
    }

    return {
      'title': (row['title'] ?? '').trim(),
      'username': username,
      'password': (row['password'] ?? '').trim(),
      'url': (row['url'] ?? '').trim(),
      'notes': note,
      'tags': tags.join(','),
    };
  }
}
