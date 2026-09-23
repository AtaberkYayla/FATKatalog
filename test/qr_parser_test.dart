import 'package:fatkatalog/model/label_record.dart';
import 'package:fatkatalog/model/parse_result.dart';
import 'package:fatkatalog/parser/qr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String errorOf(String raw) {
  final result = QrParser.parse(raw);
  expect(result, isA<ParseError>(), reason: 'beklenen hata: $raw');
  return (result as ParseError).reason;
}

void main() {
  test('geçerli örnek', () {
    final result =
        QrParser.parse('8835*P2-00180700*601107999*DDM261062*06/2026');
    expect(result, isA<ParseSuccess>());
    expect(
      (result as ParseSuccess).record,
      const LabelRecord(
        projectNo: '8835',
        workOrderNo: 'P2-00180700',
        erpProductNo: '601107999',
        serialNo: 'DDM261062',
        productionDate: '06/2026',
      ),
    );
  });

  test('eski etikette (5 alan) Poz No boş', () {
    final result =
        QrParser.parse('8835*P2-00180700*601107999*DDM261062*06/2026');
    expect((result as ParseSuccess).record.positionNo, '');
  });

  test('yeni etiket (6 alan) Poz No okunur', () {
    final result =
        QrParser.parse('8835*P2-00180700*601107999*DDM261062*06/2026* P-12 ');
    expect(result, isA<ParseSuccess>());
    final r = (result as ParseSuccess).record;
    expect(r.positionNo, 'P-12');
    expect(r.serialNo, 'DDM261062');
  });

  test('yeni etikette Poz No boş olabilir', () {
    final result =
        QrParser.parse('8835*P2-00180700*601107999*DDM261062*06/2026*');
    expect((result as ParseSuccess).record.positionNo, '');
  });

  test('boşluklu girdi kırpılır', () {
    final result = QrParser.parse(
        '  8835 * P2-00180700 *601107999 * DDM261062*06/2026 \n');
    expect(result, isA<ParseSuccess>());
    final r = (result as ParseSuccess).record;
    expect(r.projectNo, '8835');
    expect(r.workOrderNo, 'P2-00180700');
    expect(r.serialNo, 'DDM261062');
    expect(r.productionDate, '06/2026');
  });

  test('eksik alan', () {
    expect(errorOf('8835*P2-00180700*601107999*DDM261062'),
        contains('4 alan bulundu'));
  });

  test('fazla alan', () {
    expect(errorOf('8835*P2-00180700*601107999*DDM261062*06/2026*P1*X'),
        contains('7 alan bulundu'));
  });

  test('boş girdi', () {
    expect(errorOf(''), contains('1 alan bulundu'));
  });

  test('3 haneli proje no', () {
    expect(errorOf('883*P2-00180700*601107999*DDM261062*06/2026'),
        startsWith('Proje No'));
  });

  test('5 haneli proje no', () {
    expect(errorOf('88350*P2-00180700*601107999*DDM261062*06/2026'),
        startsWith('Proje No'));
  });

  test('harfli proje no', () {
    expect(errorOf('88A5*P2-00180700*601107999*DDM261062*06/2026'),
        startsWith('Proje No'));
  });

  test('boş iş emri no', () {
    expect(errorOf('8835* *601107999*DDM261062*06/2026'),
        startsWith('İş Emri No'));
  });

  test('harfli Erp ürün no', () {
    expect(errorOf('8835*P2-00180700*6011O7999*DDM261062*06/2026'),
        startsWith('Erp Ürün No'));
  });

  test('boş seri no', () {
    expect(errorOf('8835*P2-00180700*601107999**06/2026'),
        startsWith('Seri No'));
  });

  group('hatalı üretim yılı', () {
    for (final date in ['6/2026', '06-2026', '06/26', '13/2026', '00/2026', '']) {
      test('"$date"', () {
        expect(errorOf('8835*P2-00180700*601107999*DDM261062*$date'),
            startsWith('Üretim Yılı'));
      });
    }
  });
}
