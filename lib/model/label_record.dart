/// Etiketteki QR kodundan okunan alanlar (QR'daki sırayla).
class LabelRecord {
  const LabelRecord({
    required this.projectNo,
    required this.workOrderNo,
    required this.erpProductNo,
    required this.serialNo,
    required this.productionDate,
    this.positionNo = '',
  });

  /// Proje No, ör. `8835`.
  final String projectNo;

  /// İş Emri No, ör. `P2-00180700`.
  final String workOrderNo;

  /// Erp Ürün No, ör. `601107999`.
  final String erpProductNo;

  /// Seri No, ör. `DDM261062`.
  final String serialNo;

  /// Üretim Yılı, `AA/YYYY` biçiminde, ör. `06/2026`.
  final String productionDate;

  /// Poz No; yalnızca yeni etiketlerde var, eski etiketlerde boş.
  final String positionNo;

  /// [other]'daki dolu alanları, bu kayıtta **boş** olan alanlara yazar; dolu
  /// bir alanın üstüne asla yazmaz. Proje No ve Seri No kaydın kimliğidir,
  /// değiştirilmez.
  LabelRecord fillEmptyFrom(LabelRecord other) => LabelRecord(
        projectNo: projectNo,
        workOrderNo: _fill(workOrderNo, other.workOrderNo),
        erpProductNo: _fill(erpProductNo, other.erpProductNo),
        serialNo: serialNo,
        productionDate: _fill(productionDate, other.productionDate),
        positionNo: _fill(positionNo, other.positionNo),
      );

  static String _fill(String current, String incoming) =>
      current.trim().isEmpty ? incoming : current;

  @override
  bool operator ==(Object other) =>
      other is LabelRecord &&
      other.projectNo == projectNo &&
      other.workOrderNo == workOrderNo &&
      other.erpProductNo == erpProductNo &&
      other.serialNo == serialNo &&
      other.productionDate == productionDate &&
      other.positionNo == positionNo;

  @override
  int get hashCode => Object.hash(
      projectNo, workOrderNo, erpProductNo, serialNo, productionDate, positionNo);

  @override
  String toString() => 'LabelRecord($projectNo, $workOrderNo, $erpProductNo, '
      '$serialNo, $productionDate, $positionNo)';
}

/// Kaydedilmiş bir okutma: QR verisi + okutma zamanı + sonradan atanan palet.
class ScanEntry {
  const ScanEntry({
    required this.record,
    required this.scannedAt,
    this.palletNo = '',
  });

  final LabelRecord record;
  final DateTime scannedAt;

  /// Palet No; okutmadan sonra kullanıcı tarafından atanır, atanmamışsa boş.
  final String palletNo;

  ScanEntry withPallet(String palletNo) =>
      ScanEntry(record: record, scannedAt: scannedAt, palletNo: palletNo);

  /// Boş alanları [other]'dan tamamlanmış kopya; doldurulacak bir şey yoksa
  /// `null`. Okutma zamanı kaydın kendi zamanıdır, dosyadan alınmaz.
  ScanEntry? filledFrom(ScanEntry other) {
    final filled = ScanEntry(
      record: record.fillEmptyFrom(other.record),
      scannedAt: scannedAt,
      palletNo: palletNo.trim().isEmpty ? other.palletNo : palletNo,
    );
    return filled == this ? null : filled;
  }

  @override
  bool operator ==(Object other) =>
      other is ScanEntry &&
      other.record == record &&
      other.scannedAt == scannedAt &&
      other.palletNo == palletNo;

  @override
  int get hashCode => Object.hash(record, scannedAt, palletNo);
}

class ProjectSummary {
  const ProjectSummary({
    required this.projectNo,
    required this.itemCount,
    required this.lastScannedAt,
  });

  final String projectNo;
  final int itemCount;
  final DateTime lastScannedAt;
}
