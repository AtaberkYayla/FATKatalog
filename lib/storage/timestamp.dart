/// `dd.MM.yyyy HH:mm:ss` (cihaz saat dilimi) biçimi; CSV, Excel ve arayüzde ortak.
String formatTimestamp(DateTime t) =>
    '${_pad2(t.day)}.${_pad2(t.month)}.${t.year} '
    '${_pad2(t.hour)}:${_pad2(t.minute)}:${_pad2(t.second)}';

/// `dd.MM.yyyy HH:mm` — listelerde kısa gösterim.
String formatTimestampShort(DateTime t) =>
    '${_pad2(t.day)}.${_pad2(t.month)}.${t.year} ${_pad2(t.hour)}:${_pad2(t.minute)}';

/// `dd-MM-yyyy` — dışa aktarılan dosya adlarında.
String formatFileDate(DateTime t) =>
    '${_pad2(t.day)}-${_pad2(t.month)}-${t.year}';

final _pattern = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})$');

/// [formatTimestamp] çıktısını geri çözer; biçim uymazsa `null`.
DateTime? parseTimestamp(String s) {
  final m = _pattern.firstMatch(s.trim());
  if (m == null) return null;
  final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime(v[2], v[1], v[0], v[3], v[4], v[5]);
}

String _pad2(int n) => n.toString().padLeft(2, '0');
