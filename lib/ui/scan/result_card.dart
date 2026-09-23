import 'package:flutter/material.dart';

import '../../storage/timestamp.dart';
import '../theme/colors.dart';
import 'scan_controller.dart';

/// Son okutmanın sonucu: yeşil (eklendi), turuncu (tekrar), kırmızı (hata).
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.outcome});

  final ScanOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, details) = switch (outcome) {
      ScanSaved(:final entry) => (
          statusSuccess,
          Icons.check_circle,
          '${entry.record.projectNo} projesine eklendi · ${entry.record.serialNo}',
          [
            'İş Emri: ${entry.record.workOrderNo}'
                '${entry.record.positionNo.isEmpty ? '' : ' · Poz: ${entry.record.positionNo}'}',
            'Erp Ürün: ${entry.record.erpProductNo} · Üretim: ${entry.record.productionDate}',
            'Okutma: ${formatTimestamp(entry.scannedAt)}',
          ],
        ),
      ScanDuplicate(:final serialNo, :final projectNo) => (
          statusWarning,
          Icons.warning_amber_rounded,
          '$serialNo zaten $projectNo projesinde kayıtlı',
          ['Kayıt yapılmadı.'],
        ),
      ScanInvalid(:final reason, :final raw) => (
          statusError,
          Icons.error,
          'Geçersiz etiket',
          [reason, 'Okunan: $raw'],
        ),
      ScanFailed(:final message) => (
          statusError,
          Icons.error,
          'Kayıt yapılamadı',
          [message],
        ),
    };

    return Material(
      color: color,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onStatus, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: onStatus,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final line in details)
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: onStatus, fontSize: 15),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
