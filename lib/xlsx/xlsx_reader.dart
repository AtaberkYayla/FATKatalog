import 'dart:convert';

import 'package:archive/archive.dart';

/// Bir .xlsx dosyasının ilk sayfasını satır listesine çevirir. Excel
/// kütüphanesi kullanmaz; [XlsxWriter] gibi yalnızca zip için `archive`
/// paketine dayanır.
///
/// Uygulamanın kendi ürettiği dosyaları (proje Excel'i ve tüm projeler dosyası)
/// okumak için yazıldı, ama dosya Excel'de açılıp kaydedilmişse de çalışır:
/// satır içi metin (`inlineStr`), paylaşılan metin (`sharedStrings`) ve düz
/// sayı hücrelerinin üçünü de okur.
///
/// Tüm hücreler **metin** olarak döndürülür; biçimlendirme (renk, kalınlık)
/// yok sayılır.
class XlsxReader {
  XlsxReader._();

  /// Dosyanın ilk sayfasındaki satırlar. Boş hücreler `''`, satır sonundaki
  /// boş hücreler kırpılır.
  ///
  /// Dosya zip değilse ya da içinde sayfa yoksa [FormatException] atar.
  static List<List<String>> decode(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Dosya bir Excel (.xlsx) dosyası değil.');
    }

    String? part(String name) {
      final file = archive.files.where((f) => f.isFile && f.name == name);
      if (file.isEmpty) return null;
      return utf8.decode(file.first.content as List<int>, allowMalformed: true);
    }

    final sheetPath = _firstSheetPath(archive, part);
    final sheet = sheetPath == null ? null : part(sheetPath);
    if (sheet == null) {
      throw const FormatException('Excel dosyasında sayfa bulunamadı.');
    }
    return _rows(sheet, _sharedStrings(part('xl/sharedStrings.xml')));
  }

  /// Çalışma kitabındaki **ilk** sayfanın yolu.
  ///
  /// Sayfa sırası workbook.xml'de, dosya adı ise workbook.xml.rels'de durur;
  /// ikisi eşleşmezse (ya da dosya elle üretilmişse) worksheets klasöründeki
  /// ilk dosyaya düşülür.
  static String? _firstSheetPath(
      Archive archive, String? Function(String) part) {
    final workbook = part('xl/workbook.xml');
    final rels = part('xl/_rels/workbook.xml.rels');
    if (workbook != null && rels != null) {
      final sheet = RegExp(r'<sheet\b([^>]*)>').firstMatch(workbook);
      final id = sheet == null ? null : _attribute(sheet.group(1)!, 'r:id');
      if (id != null) {
        for (final rel in RegExp(r'<Relationship\b([^>]*)>').allMatches(rels)) {
          final attrs = rel.group(1)!;
          if (_attribute(attrs, 'Id') != id) continue;
          final target = _attribute(attrs, 'Target');
          if (target == null) break;
          // Hedef xl/ klasörüne göredir: "worksheets/sheet1.xml".
          final path = target.startsWith('/')
              ? target.substring(1)
              : 'xl/${target.replaceAll('../', '')}';
          if (archive.files.any((f) => f.isFile && f.name == path)) return path;
          break;
        }
      }
    }
    final sheets = archive.files
        .where((f) =>
            f.isFile &&
            f.name.startsWith('xl/worksheets/') &&
            f.name.endsWith('.xml'))
        .map((f) => f.name)
        .toList()
      ..sort();
    return sheets.isEmpty ? null : sheets.first;
  }

  /// `sharedStrings.xml` → sıra numarasına göre metinler. Biçimli metinler
  /// (rich text) birden çok `<t>` parçasına bölünür; parçalar birleştirilir.
  static List<String> _sharedStrings(String? xml) {
    if (xml == null) return const [];
    return [
      for (final si in RegExp(r'<si\b[^>]*>(.*?)</si\s*>', dotAll: true)
          .allMatches(xml))
        _texts(si.group(1)!),
    ];
  }

  static List<List<String>> _rows(String sheet, List<String> shared) {
    final rows = <List<String>>[];
    for (final match in _rowPattern.allMatches(sheet)) {
      final inner = match.group(2);
      final cells = <String>[];
      if (inner != null) {
        for (final cell in _cellPattern.allMatches(inner)) {
          final attrs = cell.group(1)!;
          final value = _cellValue(attrs, cell.group(2) ?? '', shared);
          // Atlanmış (boş) hücreler dosyada hiç yazılmaz; sütun harfinden
          // gerçek konumu bulup araları doldururuz, yoksa sütunlar kayar.
          final column = _columnOf(_attribute(attrs, 'r'));
          if (column == null) {
            cells.add(value);
          } else {
            while (cells.length < column) {
              cells.add('');
            }
            if (cells.length == column) {
              cells.add(value);
            } else {
              cells[column] = value;
            }
          }
        }
      }
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      rows.add(cells);
    }
    return rows;
  }

  static String _cellValue(String attrs, String inner, List<String> shared) {
    switch (_attribute(attrs, 't')) {
      // Bizim yazdığımız biçim.
      case 'inlineStr':
        return _texts(inner);
      // Excel kaydedince metinler buraya taşınır.
      case 's':
        final index = int.tryParse(_firstTag(inner, 'v').trim());
        return index != null && index >= 0 && index < shared.length
            ? shared[index]
            : '';
      // Formül sonucu metin.
      case 'str':
        return _firstTag(inner, 'v');
      // Sayı, tarih ya da belirtilmemiş: ham değeri metin olarak veriyoruz.
      default:
        return _firstTag(inner, 'v');
    }
  }

  /// İçindeki tüm `<t>` düğümlerinin metni (`<is>` ve `<si>` için).
  static String _texts(String xml) {
    final sb = StringBuffer();
    for (final t
        in RegExp(r'<t\b[^>]*>(.*?)</t\s*>', dotAll: true).allMatches(xml)) {
      sb.write(unescapeXml(t.group(1)!));
    }
    return sb.toString();
  }

  static String _firstTag(String xml, String tag) {
    final match =
        RegExp('<$tag\\b[^>]*>(.*?)</$tag\\s*>', dotAll: true).firstMatch(xml);
    return match == null ? '' : unescapeXml(match.group(1)!);
  }

  /// `C4` → 2 (sıfır tabanlı sütun); okunamazsa `null`.
  static int? _columnOf(String? reference) {
    if (reference == null) return null;
    var column = 0;
    var digits = 0;
    for (final rune in reference.runes) {
      if (rune >= 0x41 && rune <= 0x5A) {
        column = column * 26 + (rune - 0x40);
        digits++;
      } else if (rune >= 0x61 && rune <= 0x7A) {
        column = column * 26 + (rune - 0x60);
        digits++;
      } else {
        break;
      }
    }
    return digits == 0 ? null : column - 1;
  }

  static String? _attribute(String attributes, String name) {
    final match = RegExp('''\\b${RegExp.escape(name)}\\s*=\\s*("([^"]*)"|'([^']*)')''')
        .firstMatch(attributes);
    if (match == null) return null;
    return unescapeXml(match.group(2) ?? match.group(3) ?? '');
  }

  static String unescapeXml(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|\w+);'), (m) {
      final entity = m.group(1)!;
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        final code = int.tryParse(entity.substring(2), radix: 16);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      }
      if (entity.startsWith('#')) {
        final code = int.tryParse(entity.substring(1));
        return code == null ? m.group(0)! : String.fromCharCode(code);
      }
      return switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ => m.group(0)!,
      };
    });
  }

  static final _rowPattern =
      RegExp(r'<row\b([^>]*)(?:/>|>(.*?)</row\s*>)', dotAll: true);
  static final _cellPattern =
      RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c\s*>)', dotAll: true);
}
