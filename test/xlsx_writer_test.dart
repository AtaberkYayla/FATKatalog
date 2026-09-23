import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:fatkatalog/xlsx/xlsx_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _style = XlsxHeaderStyle(fillArgb: 0xFF1A1A1A, fontArgb: 0xFFFFFFFF);

const _header = [
  'Proje No',
  'İş Emri No',
  'Erp Ürün No',
  'Seri No',
  'Üretim Yılı',
  'Poz No',
  'Okutma Zamanı',
];

Map<String, String> _unzip(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in archive.files)
      if (f.isFile) f.name: utf8.decode(f.content as List<int>),
  };
}

Map<String, String> _build(List<List<String>> rows, {String sheet = '8835'}) =>
    _unzip(XlsxWriter.encode(
      sheetName: sheet,
      header: _header,
      rows: rows,
      headerStyle: _style,
    ));

void main() {
  final rows = [
    ['8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', 'P-01', '22.09.2026 10:50:00'],
    ['8835', 'P2-00180701', '0601108000', 'DDM261063', '06/2026', '', '22.09.2026 10:51:00'],
  ];

  test('beklenen tüm girdiler var', () {
    expect(
      _build(rows).keys,
      unorderedEquals([
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
      ]),
    );
  });

  test('tüm XML dosyaları parse edilebilir', () {
    for (final MapEntry(key: name, value: xml) in _build(rows).entries) {
      expect(() => XmlDocument.parse(xml), returnsNormally, reason: name);
    }
  });

  test('sayfa adı proje no', () {
    final wb = XmlDocument.parse(_build(rows)['xl/workbook.xml']!);
    expect(wb.findAllElements('sheet').single.getAttribute('name'), '8835');
  });

  test('tüm hücreler inlineStr metin; 06/2026 ve baştaki sıfır korunur', () {
    final sheet = XmlDocument.parse(_build(rows)['xl/worksheets/sheet1.xml']!);
    final cells = sheet.findAllElements('c').toList();
    expect(cells, hasLength(21));
    for (final c in cells) {
      expect(c.getAttribute('t'), 'inlineStr');
      expect(c.findElements('v'), isEmpty);
    }
    String text(String ref) => cells
        .firstWhere((c) => c.getAttribute('r') == ref)
        .findAllElements('t')
        .single
        .innerText;
    expect(text('A1'), 'Proje No');
    expect(text('E2'), '06/2026');
    expect(text('C3'), '0601108000');
    expect(text('F2'), 'P-01');
    expect(text('G3'), '22.09.2026 10:51:00');
  });

  test('başlık kalın stil, satırlar metin biçimi (@)', () {
    final files = _build(rows);
    final sheet = XmlDocument.parse(files['xl/worksheets/sheet1.xml']!);
    final styles = XmlDocument.parse(files['xl/styles.xml']!);
    final xfs = styles.findAllElements('cellXfs').single.findElements('xf').toList();
    final fonts = styles.findAllElements('fonts').single.findElements('font').toList();

    for (final c in sheet.findAllElements('c')) {
      final xf = xfs[int.parse(c.getAttribute('s')!)];
      expect(xf.getAttribute('numFmtId'), '49');
      final font = fonts[int.parse(xf.getAttribute('fontId')!)];
      final isHeader = c.getAttribute('r')!.endsWith('1') &&
          c.getAttribute('r')!.length == 2;
      expect(font.findElements('b').isNotEmpty, isHeader);
    }
    expect(styles.toXmlString(), contains('FF1A1A1A'));
  });

  test('başlık dondurulmuş ve autoFilter var', () {
    final sheet = XmlDocument.parse(_build(rows)['xl/worksheets/sheet1.xml']!);
    final pane = sheet.findAllElements('pane').single;
    expect(pane.getAttribute('ySplit'), '1');
    expect(pane.getAttribute('state'), 'frozen');
    expect(sheet.findAllElements('autoFilter').single.getAttribute('ref'), 'A1:G3');
    expect(sheet.findAllElements('col'), hasLength(7));
  });

  test('XML özel karakterleri kaçışlanır', () {
    const tricky = 'A&B <x> "q" \'s\'';
    final files = _build([
      ['8835', tricky, '1', 'S\u0001N', '06/2026', ''],
    ], sheet: "Tom's");
    final sheet = XmlDocument.parse(files['xl/worksheets/sheet1.xml']!);
    final texts = sheet.findAllElements('t').map((t) => t.innerText).toList();
    expect(texts, contains(tricky));
    expect(texts, contains('SN')); // geçersiz kontrol karakteri atıldı
    expect(files['xl/worksheets/sheet1.xml'], contains('A&amp;B &lt;x&gt;'));
    final wb = XmlDocument.parse(files['xl/workbook.xml']!);
    expect(wb.findAllElements('sheet').single.getAttribute('name'), "Tom's");
  });

  test('boş proje de geçerli dosya üretir', () {
    final files = _build([]);
    final sheet = XmlDocument.parse(files['xl/worksheets/sheet1.xml']!);
    expect(sheet.findAllElements('row'), hasLength(1));
  });

  test('sütun adları', () {
    expect(XlsxWriter.columnName(0), 'A');
    expect(XlsxWriter.columnName(25), 'Z');
    expect(XlsxWriter.columnName(26), 'AA');
    expect(XlsxWriter.columnName(701), 'ZZ');
    expect(XlsxWriter.columnName(702), 'AAA');
  });

  test('sayfa adı temizlenir', () {
    expect(XlsxWriter.sanitizeSheetName('a/b:c'), 'a_b_c');
    expect(XlsxWriter.sanitizeSheetName(''), 'Sayfa1');
    expect(XlsxWriter.sanitizeSheetName('x' * 40), hasLength(31));
  });
}
