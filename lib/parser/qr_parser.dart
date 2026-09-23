import '../model/label_record.dart';
import '../model/parse_result.dart';

/// Etiket QR içeriğini ayrıştırır.
///
/// Eski etiket (5 alan): `8835*P2-00180700*601107999*DDM261062*06/2026`
/// Yeni etiket (6 alan, sonda Poz No): `8835*P2-00180700*601107999*DDM261062*06/2026*<Poz No>`
///
/// Saf fonksiyon; Flutter bağımlılığı yoktur.
class QrParser {
  QrParser._();

  static final _projectNo = RegExp(r'^\d{4}$');
  static final _erpProductNo = RegExp(r'^\d+$');
  static final _productionDate = RegExp(r'^(\d{2})/\d{4}$');

  static ParseResult parse(String raw) {
    final fields = raw.split('*').map((f) => f.trim()).toList();
    if (fields.length != 5 && fields.length != 6) {
      return ParseError(
        'Geçersiz QR: 5 veya 6 alan bekleniyordu, '
        '${fields.length} alan bulundu',
      );
    }
    final [projectNo, workOrderNo, erpProductNo, serialNo, productionDate] =
        fields.sublist(0, 5);
    final positionNo = fields.length == 6 ? fields[5] : '';

    if (!_projectNo.hasMatch(projectNo)) {
      return _fieldError('Proje No', projectNo, '4 haneli sayı olmalı');
    }
    if (workOrderNo.isEmpty) {
      return _fieldError('İş Emri No', workOrderNo, 'boş olamaz');
    }
    if (!_erpProductNo.hasMatch(erpProductNo)) {
      return _fieldError(
          'Erp Ürün No', erpProductNo, 'yalnızca rakamlardan oluşmalı');
    }
    if (serialNo.isEmpty) {
      return _fieldError('Seri No', serialNo, 'boş olamaz');
    }
    final month =
        int.tryParse(_productionDate.firstMatch(productionDate)?.group(1) ?? '');
    if (month == null || month < 1 || month > 12) {
      return _fieldError(
          'Üretim Yılı', productionDate, 'AA/YYYY biçiminde olmalı');
    }

    return ParseSuccess(LabelRecord(
      projectNo: projectNo,
      workOrderNo: workOrderNo,
      erpProductNo: erpProductNo,
      serialNo: serialNo,
      productionDate: productionDate,
      positionNo: positionNo,
    ));
  }

  static ParseError _fieldError(String field, String value, String rule) {
    final shown = value.isEmpty ? '(boş)' : '"$value"';
    return ParseError('$field hatalı: $shown — $rule');
  }
}
