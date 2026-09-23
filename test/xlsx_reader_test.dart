import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:fatkatalog/xlsx/xlsx_reader.dart';
import 'package:fatkatalog/xlsx/xlsx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = XlsxHeaderStyle(fillArgb: 0xFF1A1A1A, fontArgb: 0xFFFFFFFF);

const _header = [
  'Proje No',
  'İş Emri No',
  'Erp Ürün No',
  'Seri No',
  'Üretim Yılı',
  'Poz No',
  'Palet No',
  'Okutma Zamanı',
];

List<int> _write(List<List<String>> rows, {String sheet = '8835'}) =>
    XlsxWriter.encode(
      sheetName: sheet,
      header: _header,
      rows: rows,
      headerStyle: _style,
    );

/// Excel'in kaydettiği bir dosyayı taklit eder: metinler `sharedStrings.xml`'e
/// taşınır, hücreler `t="s"` ile sıra numarası taşır, boş hücreler hiç yazılmaz.
List<int> _excelStyle(List<List<String>> rows) {
  final strings = <String>[];
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main"><sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final value = rows[r][c];
      if (value.isEmpty) continue; // Excel boş hücreyi yazmaz.
      var index = strings.indexOf(value);
      if (index < 0) {
        strings.add(value);
        index = strings.length - 1;
      }
      sheet.write('<c r="${XlsxWriter.columnName(c)}${r + 1}" t="s">'
          '<v>$index</v></c>');
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  final shared = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<sst xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main" count="${strings.length}">');
  for (final s in strings) {
    shared.write('<si><t>${XlsxWriter.escapeXml(s)}</t></si>');
  }
  shared.write('</sst>');

  final archive = Archive();
  void add(String name, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('xl/worksheets/sheet1.xml', sheet.toString());
  add('xl/sharedStrings.xml', shared.toString());
  return ZipEncoder().encode(archive);
}

void main() {
  final rows = [
    ['8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', 'P-01',
        'PLT-01', '22.09.2026 10:50:00'],
    ['8835', 'P2-00180701', '0601108000', 'DDM261063', '06/2026', '', '',
        '22.09.2026 10:51:00'],
  ];

  test('kendi yazdığımız dosya birebir geri okunur', () {
    final read = XlsxReader.decode(_write(rows));
    expect(read.first, _header);
    expect(read.skip(1), rows);
  });

  test('baştaki sıfır ve 06/2026 metin olarak korunur', () {
    final read = XlsxReader.decode(_write(rows));
    expect(read[2][2], '0601108000');
    expect(read[1][4], '06/2026');
  });

  test('özel karakterler geri çözülür', () {
    final tricky = [
      ['8835', 'A & B', '<test>', "DDM'1", '06/2026', '"tırnak"', 'ü/ş',
          '22.09.2026 10:50:00'],
    ];
    expect(XlsxReader.decode(_write(tricky)).skip(1), tricky);
  });

  test('Excel biçiminde kaydedilmiş dosya (sharedStrings) okunur', () {
    final read = XlsxReader.decode(_excelStyle([_header, ...rows]));
    expect(read.first, _header);
    // Boş hücreler yazılmasa da sütunlar kaymaz.
    expect(read[2][3], 'DDM261063');
    expect(read[2][7], '22.09.2026 10:51:00');
    expect(read[2][5], '');
  });

  test('kayıtsız dosyada yalnızca başlık döner', () {
    expect(XlsxReader.decode(_write([])), [_header]);
  });

  test('tüm projeler dosyası da aynı şekilde okunur', () {
    final all = [
      ['8835', 'P2-1', '601', 'DDM1', '06/2026', '', '', '22.09.2026 10:50:00'],
      ['8840', 'P2-2', '602', 'DDM2', '07/2026', '', '', '22.09.2026 10:51:00'],
    ];
    final read = XlsxReader.decode(_write(all, sheet: 'Tüm Projeler'));
    expect(read.skip(1).map((r) => r[0]), ['8835', '8840']);
  });

  test('zip olmayan dosya reddedilir', () {
    expect(() => XlsxReader.decode(utf8.encode('merhaba')),
        throwsA(isA<FormatException>()));
  });

  test('sayfası olmayan zip reddedilir', () {
    final archive = Archive();
    final bytes = utf8.encode('x');
    archive.addFile(ArchiveFile('bir.txt', bytes.length, bytes));
    expect(() => XlsxReader.decode(ZipEncoder().encode(archive)),
        throwsA(isA<FormatException>()));
  });
}
