import 'package:fatkatalog/storage/csv_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('düz alanlar tırnaksız yazılır', () {
    expect(CsvCodec.encode([
      ['8835', 'P2-00180700', '06/2026'],
    ]), '8835;P2-00180700;06/2026\r\n');
  });

  test('; " ve satır sonu içeren alanlar kaçışlanır', () {
    expect(CsvCodec.encode([
      ['a;b', 'say "hi"', 'x\ny'],
    ]), '"a;b";"say ""hi""";"x\ny"\r\n');
  });

  test('özel karakterlerle gidiş-dönüş', () {
    final rows = [
      ['Proje No', 'Parça Kodu', 'Açıklama'],
      ['8835', 'P2;001', 'içinde "tırnak" var'],
      ['8840', '', 'çok\r\nsatırlı\nalan'],
      ['8841', '"', ';'],
      ['', '', ''],
    ];
    expect(CsvCodec.decode(CsvCodec.encode(rows)), rows);
  });

  test('BOM ve LF satır sonları okunur', () {
    expect(CsvCodec.decode('﻿a;b\nc;d\n'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('son satırda satır sonu olmasa da okunur', () {
    expect(CsvCodec.decode('a;b\r\nc;'), [
      ['a', 'b'],
      ['c', ''],
    ]);
  });

  test('boş metin boş liste verir', () {
    expect(CsvCodec.decode(''), isEmpty);
  });
}
