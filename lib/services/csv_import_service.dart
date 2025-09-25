import 'package:csv/csv.dart';

class CsvImportService {
  /// Generic CSV parser with delimiter detection (comma, semicolon, tab, pipe).
  /// Returns list of maps using normalized, lowercased header keys.
  List<Map<String, String>> parseAnyCsv(String csvContent) {
    if (csvContent.trim().isEmpty) return [];

    // Normalize newlines and trim BOM if present.
    String normalized = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.isNotEmpty && normalized.codeUnitAt(0) == 0xFEFF) {
      normalized = normalized.substring(1);
    }

    // Detect delimiter from header line by counting occurrences.
    final headerLine = normalized.split('\n').first;
    final candidates = [',', ';', '\t', '|'];
    String delimiter = ',';
    int bestCount = -1;
    for (final cand in candidates) {
      final count = headerLine.split(cand).length - 1;
      if (count > bestCount) {
        bestCount = count;
        delimiter = cand;
      }
    }

    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(normalized, fieldDelimiter: delimiter);

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
      // Skip completely empty rows
      final nonEmpty = m.values.any((v) => (v.trim().isNotEmpty));
      if (!nonEmpty) continue;
      result.add(m);
    }
    return result;
  }

  /// Heuristic mapping from arbitrary CSV headers to our normalized entry fields.
  /// Produces a map with keys: title, username, password, url, notes, tags
  Map<String, String> mapRowToEntryFields(Map<String, String> row) {
    String pickFirstMatching(Map<String, String> source, List<String> keys) {
      for (final k in keys) {
        final v = source[k];
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    // Common synonyms
    final title = pickFirstMatching(row, [
      'title', 'name', 'account', 'item', 'label', 'site', 'service'
    ]);
    final username = pickFirstMatching(row, [
      'username', 'user', 'login', 'user_name', 'user name', 'email', 'email address', 'account', 'id'
    ]);
    final password = pickFirstMatching(row, [
      'password', 'pass', 'pwd'
    ]);
    final url = pickFirstMatching(row, [
      'url', 'website', 'site', 'link'
    ]);
    final notes = pickFirstMatching(row, [
      'notes', 'note', 'remarks', 'comment', 'comments', 'description'
    ]);
    String tags = pickFirstMatching(row, [
      'tags', 'label', 'category', 'groups', 'folder'
    ]);

    // If username missing but email present under other header
    if (username.isEmpty) {
      final emailFallback = pickFirstMatching(row, ['email', 'e-mail']);
      if (emailFallback.isNotEmpty) {
        // ignore: unused_local_variable
        final _ = emailFallback; // already covered in list, kept for readability
      }
    }

    // Produce final map
    return {
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'tags': tags,
    };
  }

  // ---- Backward compatible Dashlane-specific methods (used by existing flows) ----

  List<Map<String, String>> parseDashlaneCsv(String csvContent) {
    return parseAnyCsv(csvContent);
  }

  Map<String, String> mapDashlaneRowToEntryFields(Map<String, String> row) {
    // Prefer Dashlane fields if present; otherwise fall back to generic mapping.
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
      row['username'],
      row['email'],
    ]);

    final note = [
      row['note']?.trim() ?? '',
      (row['category'] != null && row['category']!.trim().isNotEmpty)
          ? 'Category: ${row['category']!.trim()}'
          : '',
      (row['otp'] != null && row['otp']!.trim().isNotEmpty)
          ? 'OTP: ${row['otp']!.trim()}'
          : '',
    ].where((s) => s.isNotEmpty).join('\n');

    final tags = <String>[];
    if ((row['category'] ?? '').trim().isNotEmpty) {
      tags.add(row['category']!.trim());
    }

    final title = pickNonEmpty([
      row['title'],
      row['name'],
      row['site'],
      row['service'],
    ]);

    final url = pickNonEmpty([
      row['url'],
      row['website'],
      row['link'],
      row['site'],
    ]);

    final mapped = {
      'title': title,
      'username': username,
      'password': (row['password'] ?? '').trim(),
      'url': url,
      'notes': note,
      'tags': tags.join(','),
    };

    // If critical fields are still empty, fall back to generic mapping.
    if ((mapped['password'] ?? '').isEmpty && row.values.any((v) => v.isNotEmpty)) {
      return mapRowToEntryFields(row);
    }
    return mapped;
  }
}
