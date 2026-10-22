import 'package:fatkatalog/model/parse_result.dart';
import 'package:fatkatalog/parser/manual_entry_validator.dart';
import 'package:flutter_test/flutter_test.dart';

String? _error(ParseResult r) => r is ParseError ? r.reason : null;

void main() {
  group('ManualEntryValidator', () {
    test('proje no ve seri no yeter, alanlar trim edilir', () {
      final r = ManualEntryValidator.validate(
          projectNo: ' 8835 ', serialNo: ' ABC1 ', positionNo: ' P1 ');
      expect((r as ParseSuccess).record.projectNo, '8835');
      expect(r.record.serialNo, 'ABC1');
      expect(r.record.positionNo, 'P1');
      expect(r.record.workOrderNo, '');
    });

    test('hatalı proje no reddedilir', () {
      for (final p in ['', '883', '88350', 'abcd']) {
        expect(
            _error(ManualEntryValidator.validate(
                projectNo: p, serialNo: 'ABC1')),
            contains('Proje No'));
      }
    });

    test('seri no boşsa kayıt oluşturulmaz', () {
      for (final s in ['', '   ']) {
        expect(
            _error(ManualEntryValidator.validate(
                projectNo: '8835', serialNo: s, positionNo: 'P1')),
            contains('Seri No'));
      }
    });

    test('dolu alanlar etiketle aynı kurallara tabi', () {
      expect(
          _error(ManualEntryValidator.validate(
              projectNo: '8835', serialNo: 'A', erpProductNo: '12ab')),
          contains('Erp Ürün No'));
      expect(
          _error(ManualEntryValidator.validate(
              projectNo: '8835', serialNo: 'A', productionDate: '13/2026')),
          contains('Üretim Yılı'));
      expect(
          ManualEntryValidator.validate(
              projectNo: '8835', serialNo: 'A', productionDate: '06/2026'),
          isA<ParseSuccess>());
    });
  });
}
