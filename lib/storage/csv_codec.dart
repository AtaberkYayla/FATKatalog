/// `;` ayırıcılı CSV (RFC 4180 kaçış kuralları). `;`, `"` veya satır sonu
/// içeren alanlar çift tırnak içine alınır, içteki `"` karakteri `""` olur.
class CsvCodec {
  CsvCodec._();

  static const separator = ';';
  static const _quote = '"';
  static const _lineEnd = '\r\n';
  static const _bom = '﻿';

  static String encode(List<List<String>> rows) {
    final sb = StringBuffer();
    for (final row in rows) {
      for (var i = 0; i < row.length; i++) {
        if (i > 0) sb.write(separator);
        sb.write(_encodeField(row[i]));
      }
      sb.write(_lineEnd);
    }
    return sb.toString();
  }

  static List<List<String>> decode(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var fieldStarted = false;
    var i = text.startsWith(_bom) ? 1 : 0;

    void endField() {
      row.add(field.toString());
      field.clear();
      fieldStarted = false;
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    while (i < text.length) {
      final c = text[i];
      if (inQuotes) {
        if (c == _quote) {
          if (i + 1 < text.length && text[i + 1] == _quote) {
            field.write(_quote);
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == separator) {
        endField();
      } else if (c == '\r') {
        endRow();
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
      } else if (c == '\n') {
        endRow();
      } else {
        if (c == _quote && field.isEmpty) {
          inQuotes = true;
        } else {
          field.write(c);
        }
        fieldStarted = true;
      }
      i++;
    }
    // Son satır satır sonu olmadan bitmişse onu da ekle.
    if (fieldStarted || field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  static String _encodeField(String field) {
    final needsQuotes = field.contains(separator) ||
        field.contains(_quote) ||
        field.contains('\n') ||
        field.contains('\r');
    if (!needsQuotes) return field;
    return '$_quote${field.replaceAll(_quote, '$_quote$_quote')}$_quote';
  }
}
