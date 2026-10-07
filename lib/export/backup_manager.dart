import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/native_bridge.dart';
import '../storage/csv_codec.dart';
import '../storage/project_repository.dart';
import '../storage/timestamp.dart';
import '../xlsx/xlsx_reader.dart';
import '../xlsx/xlsx_writer.dart';
import 'export_manager.dart';

/// Tüm projelerin kayıtlarını tek bir Excel dosyasına aktarır ve Excel
/// dosyalarından kayıt içeri alır.
///
/// Kullanıcı için ayrı bir "yedek dosyası" kavramı yok: her gün indirdiği
/// Excel dosyasının aynısı. İçe aktarma hem tek projenin Excel'ini
/// (`8835_23-09-2026.xlsx`) hem de tüm projeler dosyasını kabul eder; ikisi de
/// aynı sütunları taşır ve Proje No bir sütun olduğu için projeler dosyadan
/// ayrıştırılır.
class BackupManager {
  BackupManager(this._repository);

  /// Tüm projeler dosyasındaki sayfanın adı.
  static const allProjectsSheetName = 'Tüm Projeler';

  /// İçeri alınacak dosya için üst sınır; yanlışlıkla seçilen büyük bir dosya
  /// (video vb.) belleği doldurmasın.
  static const _maxImportBytes = 20 * 1024 * 1024;

  final ProjectRepository _repository;

  /// `FATKatalog_tum_projeler_23-09-2026.xlsx`
  static String fileNameFor(DateTime date) =>
      'FATKatalog_tum_projeler_${formatFileDate(date)}.xlsx';

  /// Tüm projeleri tek Excel dosyası olarak `Download/FATKatalog/` altına
  /// kaydeder. Kullanıcı vazgeçerse `null` döndürür.
  Future<ExportedAll?> saveToDownloads() async {
    final (:file, :count) = await _writeAll();
    final location = await NativeBridge.saveToDownloads(
      sourcePath: file.path,
      fileName: fileNameFor(DateTime.now()),
      mimeType: ExportManager.xlsxMimeType,
    );
    return location == null
        ? null
        : ExportedAll(location: location, count: count);
  }

  /// Tüm projeler dosyasını paylaşır (WhatsApp, e-posta vb.).
  Future<int> share() async {
    final (:file, :count) = await _writeAll();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: ExportManager.xlsxMimeType)],
      subject: 'FATKatalog – tüm projeler',
    ));
    return count;
  }

  /// Kullanıcıya bir dosya seçtirip kayıtları mevcut verilerle birleştirir.
  /// Kullanıcı vazgeçerse `null` döndürür.
  ///
  /// Dosya bir FATKatalog kayıt dosyası değilse [FormatException] atar.
  Future<ImportResult?> restore() async {
    final path = await NativeBridge.pickFile();
    if (path == null) return null;

    final file = File(path);
    if (await file.length() > _maxImportBytes) {
      throw const FormatException(
          'Seçilen dosya çok büyük; bir FATKatalog kayıt dosyası değil.');
    }
    return _repository.importRows(_parse(await file.readAsBytes()));
  }

  /// Excel mi CSV mi olduğunu içeriğine bakarak ayırır: dosya uzantısı
  /// paylaşım yoluyla gelince güvenilmez oluyor.
  static List<List<String>> _parse(List<int> bytes) {
    // Her zip dosyası "PK\u0003\u0004" ile başlar; .xlsx bir zip arşividir.
    final isZip = bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (isZip) return XlsxReader.decode(bytes);
    try {
      return CsvCodec.decode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      // Metin bile değilse (ör. yanlışlıkla seçilen bir resim).
      throw const FormatException(
          'Bu dosya bir FATKatalog kayıt dosyası değil.');
    }
  }

  /// Tüm projeleri tek sayfalı bir Excel dosyasına yazar. Dosya adı alıcıya da
  /// görünür; bu yüzden geçici klasöre doğru adla yazılır.
  Future<({File file, int count})> _writeAll() async {
    final all = await _repository.exportAll();
    final bytes = XlsxWriter.encode(
      sheetName: allProjectsSheetName,
      header: ProjectRepository.xlsxHeader,
      rows: all.rows,
      headerStyle: _repository.headerStyle,
    );
    final dir = Directory('${(await getTemporaryDirectory()).path}/backup');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/${fileNameFor(DateTime.now())}');
    await file.writeAsBytes(bytes, flush: true);
    return (file: file, count: all.count);
  }
}

class ExportedAll {
  const ExportedAll({required this.location, required this.count});

  /// Kullanıcıya gösterilecek konum, ör. `İndirilenler/FATKatalog/...`.
  final String location;

  /// Dosyaya yazılan kayıt sayısı.
  final int count;
}
