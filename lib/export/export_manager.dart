import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../model/label_record.dart';
import '../platform/native_bridge.dart';
import '../storage/project_repository.dart';
import '../storage/timestamp.dart';

/// Proje Excel dosyasını indirme ve paylaşma.
class ExportManager {
  ExportManager(this._repository);

  static const xlsxMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  final ProjectRepository _repository;

  /// `8835_22-09-2026.xlsx`
  static String fileNameFor(String projectNo, DateTime date) =>
      '${projectNo}_${formatFileDate(date)}.xlsx';

  /// Download/FATKatalog/ altına kaydeder. Kaydedilen konumu, kullanıcı
  /// vazgeçerse `null` döndürür.
  Future<String?> download(String projectNo) async {
    final file = await _requireXlsx(projectNo);
    return NativeBridge.saveToDownloads(
      sourcePath: file.path,
      fileName: fileNameFor(projectNo, DateTime.now()),
      mimeType: xlsxMimeType,
    );
  }

  Future<void> share(String projectNo) async {
    final source = await _requireXlsx(projectNo);
    // Alıcının göreceği ad: proje no + tarih.
    await _shareFile(source, fileNameFor(projectNo, DateTime.now()),
        'FAT kataloğu – Proje $projectNo');
  }

  Future<void> _shareFile(File source, String fileName, String subject) async {
    final shareDir = Directory('${(await getTemporaryDirectory()).path}/share');
    if (await shareDir.exists()) await shareDir.delete(recursive: true);
    await shareDir.create(recursive: true);
    final copy = await source.copy('${shareDir.path}/$fileName');

    await SharePlus.instance.share(ShareParams(
      files: [XFile(copy.path, mimeType: xlsxMimeType)],
      subject: subject,
    ));
  }

  /// `8900_arsiv_13-10-2026_15-41.xlsx`
  static String archiveFileNameFor(ArchiveSummary archive) =>
      '${archive.projectNo}_arsiv_${formatFileDate(archive.archivedAt)}_'
      '${formatFileTime(archive.archivedAt).substring(0, 5)}.xlsx';

  /// Arşivdeki listeyi Download/FATKatalog/ altına kaydeder.
  Future<String?> downloadArchive(ArchiveSummary archive) async {
    final file = await _requireArchiveXlsx(archive);
    return NativeBridge.saveToDownloads(
      sourcePath: file.path,
      fileName: archiveFileNameFor(archive),
      mimeType: xlsxMimeType,
    );
  }

  Future<void> shareArchive(ArchiveSummary archive) async {
    final source = await _requireArchiveXlsx(archive);
    await _shareFile(
      source,
      archiveFileNameFor(archive),
      'FAT kataloğu – Proje ${archive.projectNo} '
      '(${formatArchiveLabel(archive.archivedAt)})',
    );
  }

  Future<File> _requireArchiveXlsx(ArchiveSummary archive) async {
    final file = await _repository.archivedXlsxFile(archive.id);
    if (file == null) throw StateError('Arşiv bulunamadı: ${archive.id}');
    return file;
  }

  Future<File> _requireXlsx(String projectNo) async {
    final file = await _repository.xlsxFile(projectNo);
    if (file == null) {
      throw StateError('$projectNo projesinde kayıt yok');
    }
    return file;
  }
}
