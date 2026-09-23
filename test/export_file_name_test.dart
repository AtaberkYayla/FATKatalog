import 'package:fatkatalog/export/export_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dosya adı proje no + gün-ay-yıl', () {
    expect(ExportManager.fileNameFor('8835', DateTime(2026, 9, 22, 10, 50)),
        '8835_22-09-2026.xlsx');
    expect(ExportManager.fileNameFor('8840', DateTime(2027, 1, 5)),
        '8840_05-01-2027.xlsx');
  });
}
