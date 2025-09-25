import '../models/password_entry.dart';

class CsvExportService {
  /// Export a list of PasswordEntry as a plain text CSV string
  String exportPasswordsToCsv(List<PasswordEntry> passwords) {
    if (passwords.isEmpty) return '';

    final buffer = StringBuffer();
    // CSV header
    buffer.writeln('id,title,username,password,url,notes,tags');
    for (final entry in passwords) {
      final tags = entry.tags.join(',');
      // Escape double quotes in fields
      String escape(String? value) =>
          value == null ? '' : '"${value.replaceAll('"', '""')}"';
      buffer.writeln([
        escape(entry.id),
        escape(entry.title),
        escape(entry.username),
        escape(entry.password),
        escape(entry.url),
        escape(entry.notes),
        escape(tags)
      ].join(','));
    }
    return buffer.toString();
  }
}