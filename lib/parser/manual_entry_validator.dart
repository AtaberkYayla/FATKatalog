import '../model/label_record.dart';
import '../model/parse_result.dart';

/// Etiketsiz malzemeler için elle girilen alanları doğrular.
///
/// QR etiketindeki kurallarla aynıdır ([QrParser]) ama etiket olmadığı için
/// yalnızca kimlik alanları Proje No ve Seri No zorunludur; diğer alanlar boş
/// bırakılabilir, doluysa biçimi doğrulanır.
///
/// Saf fonksiyon; Flutter bağımlılığı yoktur.
class ManualEntryValidator {
  ManualEntryValidator._();

  static final _projectNo = RegExp(r'^\d{4}$');
  static final _erpProductNo = RegExp(r'^\d+$');
  static final _productionDate = RegExp(r'^(\d{2})/\d{4}$');

  static ParseResult validate({
    required String projectNo,
    String workOrderNo = '',
    String erpProductNo = '',
    String serialNo = '',
    String productionDate = '',
    String positionNo = '',
  }) {
    projectNo = projectNo.trim();
    workOrderNo = workOrderNo.trim();
    erpProductNo = erpProductNo.trim();
    serialNo = serialNo.trim();
    productionDate = productionDate.trim();
    positionNo = positionNo.trim();

    if (!_projectNo.hasMatch(projectNo)) {
      return const ParseError('Proje No hatalı — 4 haneli sayı olmalı');
    }
    // Seri No kaydın kimliği (tekrar kontrolü, içe aktarma); boşsa kayıt
    // oluşturulmaz.
    if (serialNo.isEmpty) {
      return const ParseError('Seri No hatalı — boş olamaz');
    }
    if (erpProductNo.isNotEmpty && !_erpProductNo.hasMatch(erpProductNo)) {
      return const ParseError('Erp Ürün No hatalı — yalnızca rakamlardan oluşmalı');
    }
    if (productionDate.isNotEmpty) {
      final month = int.tryParse(
          _productionDate.firstMatch(productionDate)?.group(1) ?? '');
      if (month == null || month < 1 || month > 12) {
        return const ParseError('Üretim Yılı hatalı — AA/YYYY biçiminde olmalı');
      }
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
}
