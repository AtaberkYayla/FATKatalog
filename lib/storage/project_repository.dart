import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/label_record.dart';
import '../xlsx/xlsx_writer.dart';
import 'csv_codec.dart';
import 'timestamp.dart';

sealed class AddResult {
  const AddResult();
}

final class Added extends AddResult {
  const Added(this.entry);

  final ScanEntry entry;
}

final class Duplicate extends AddResult {
  const Duplicate({required this.serialNo, required this.existingProjectNo});

  final String serialNo;
  final String existingProjectNo;
}

/// İçe aktarmanın sonucu. İçe aktarma **hiçbir kaydı silmez ve dolu bir alanın
/// üstüne yazmaz**; eksik kayıtları ekler, var olanların yalnızca boş alanlarını
/// dosyadan tamamlar.
final class ImportResult {
  const ImportResult({
    required this.added,
    required this.updated,
    required this.unchanged,
    required this.skipped,
  });

  /// Eklenen yeni kayıt sayısı.
  final int added;

  /// Zaten kayıtlı olup boş alanları dosyadan tamamlanan kayıt sayısı.
  final int updated;

  /// Zaten kayıtlı olan ve tamamlanacak boş alanı bulunmayan kayıt sayısı.
  final int unchanged;

  /// Okunamayan (bozuk ya da eksik) satır sayısı.
  final int skipped;
}

/// Proje kayıtlarının tek giriş noktası.
///
/// Her proje `projects/<projeNo>.csv` (kaynak) ve `projects/<projeNo>.xlsx`
/// (CSV'den türetilir) dosyalarında tutulur. Tüm işlemler sıralıdır (kilit) ve
/// her yazma atomiktir (geçici dosya + rename).
class ProjectRepository {
  ProjectRepository(
    this.projectsDir, {
    required this.headerStyle,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const projectNoColumn = 'Proje No';
  static const workOrderNoColumn = 'İş Emri No';
  static const erpProductNoColumn = 'Erp Ürün No';
  static const serialNoColumn = 'Seri No';
  static const productionDateColumn = 'Üretim Yılı';
  static const positionNoColumn = 'Poz No';
  static const palletNoColumn = 'Palet No';
  static const scannedAtColumn = 'Okutma Zamanı';
  static const palletSizeColumn = 'Palet Ölçüsü (mm)';

  /// CSV sütunları (kaynak veri). Yeni sütunlar yalnızca sona eklenir.
  static const header = [
    projectNoColumn,
    workOrderNoColumn,
    erpProductNoColumn,
    serialNoColumn,
    productionDateColumn,
    positionNoColumn,
    palletNoColumn,
    scannedAtColumn,
    palletSizeColumn,
  ];

  /// Excel sütunları: CSV ile aynı sütunlar, görünüm gereği Palet Ölçüsü Palet
  /// No'nun yanında. Excel her zaman CSV'den üretildiği için sıra serbest;
  /// geri okurken sütunlar başlık adından bulunur.
  static const xlsxHeader = [
    projectNoColumn,
    workOrderNoColumn,
    erpProductNoColumn,
    serialNoColumn,
    productionDateColumn,
    positionNoColumn,
    palletNoColumn,
    palletSizeColumn,
    scannedAtColumn,
  ];

  /// Başlık satırı tanınmadığında sütun sırasına göre çözmek için eski
  /// biçimlerin sütun sayıları: Palet No'suz (1.0.1 ve öncesi) ve Palet
  /// Ölçüsü'süz (1.2.0 ve öncesi).
  static const _noPalletColumnCount = 7;
  static const _noPalletSizeColumnCount = 8;

  static final _projectFileName = RegExp(r'^(\d{4})\.csv$');
  static final _projectNo = RegExp(r'^\d{4}$');
  static const _tmpSuffix = '.tmp';

  final Directory projectsDir;
  final XlsxHeaderStyle headerStyle;
  final DateTime Function() _clock;

  /// Proje no → kayıtlar (okutma sırasına göre). CSV'lerin bellekteki kopyası.
  final Map<String, List<ScanEntry>> _projects = {};

  /// Seri no → proje no; tüm projeler genelinde tekrar kontrolü için.
  final Map<String, String> _serialIndex = {};

  bool _loaded = false;
  Future<void> _tail = Future.value();
  final _changes = StreamController<void>.broadcast();

  /// Her ekleme, silme ve palet atamasından sonra tetiklenir.
  Stream<void> get changes => _changes.stream;

  Future<AddResult> add(LabelRecord record) => _locked(() async {
        final existing = _serialIndex[record.serialNo];
        if (existing != null) {
          return Duplicate(
              serialNo: record.serialNo, existingProjectNo: existing);
        }
        final entry = ScanEntry(record: record, scannedAt: _now());
        final updated = [...?_projects[record.projectNo], entry];
        await _writeProject(record.projectNo, updated);
        _projects[record.projectNo] = updated;
        _serialIndex[record.serialNo] = record.projectNo;
        _changes.add(null);
        return Added(entry);
      });

  /// Seri numaraları verilen kayıtları siler; silinen kayıt sayısını döndürür.
  /// Projenin tüm kayıtları silinirse proje dosyaları da silinir.
  Future<int> delete(String projectNo, Set<String> serialNos) =>
      _locked(() async {
        final entries = _projects[projectNo];
        if (entries == null) return 0;
        final updated = entries
            .where((e) => !serialNos.contains(e.record.serialNo))
            .toList();
        final removed = entries.length - updated.length;
        if (removed == 0) return 0;

        if (updated.isEmpty) {
          for (final f in [_csvFile(projectNo), _xlsxFile(projectNo)]) {
            if (await f.exists()) await f.delete();
          }
          _projects.remove(projectNo);
        } else {
          await _writeProject(projectNo, updated);
          _projects[projectNo] = updated;
        }
        for (final e in entries) {
          if (serialNos.contains(e.record.serialNo)) {
            _serialIndex.remove(e.record.serialNo);
          }
        }
        _changes.add(null);
        return removed;
      });

  /// Seçilen kayıtlara palet no ve ölçüsünü atar (boş palet no paleti ve
  /// ölçüsünü kaldırır); değişen kayıt sayısını döndürür.
  Future<int> assignPallet(
    String projectNo,
    Set<String> serialNos,
    String palletNo, {
    String palletSize = '',
  }) =>
      _locked(() async {
        final entries = _projects[projectNo];
        if (entries == null) return 0;
        final pallet = palletNo.trim();
        final size = pallet.isEmpty ? '' : palletSize.trim();
        var changed = 0;
        final updated = <ScanEntry>[];
        for (final e in entries) {
          if (serialNos.contains(e.record.serialNo) &&
              (e.palletNo != pallet || e.palletSize != size)) {
            updated.add(e.withPallet(pallet, palletSize: size));
            changed++;
          } else {
            updated.add(e);
          }
        }
        if (changed == 0) return 0;
        await _writeProject(projectNo, updated);
        _projects[projectNo] = updated;
        _changes.add(null);
        return changed;
      });

  /// Son okutma zamanına göre (yeniden eskiye) sıralı proje özetleri.
  Future<List<ProjectSummary>> listProjects() => _locked(() async {
        final summaries = [
          for (final MapEntry(key: projectNo, value: entries)
              in _projects.entries)
            ProjectSummary(
              projectNo: projectNo,
              itemCount: entries.length,
              lastScannedAt: entries
                  .map((e) => e.scannedAt)
                  .reduce((a, b) => a.isAfter(b) ? a : b),
            ),
        ];
        summaries.sort((a, b) => b.lastScannedAt.compareTo(a.lastScannedAt));
        return summaries;
      });

  /// Projenin kayıtları, okutma sırasına göre. Proje yoksa boş liste.
  Future<List<ScanEntry>> entries(String projectNo) =>
      _locked(() async => List.unmodifiable(_projects[projectNo] ?? const []));

  /// Projenin güncel .xlsx dosyası (dışa aktarmadan önce CSV'den yeniden üretilir).
  Future<File?> xlsxFile(String projectNo) => _locked(() async {
        final entries = _projects[projectNo];
        if (entries == null) return null;
        final file = _xlsxFile(projectNo);
        await _writeAtomic(file, _encodeXlsx(projectNo, entries));
        return file;
      });

  /// Tüm projelerin kayıtları, proje no ve okutma zamanına göre sıralı tek bir
  /// tablo halinde ([xlsxHeader] sütun sırasıyla, başlık hariç). Proje No zaten
  /// bir sütun olduğu için
  /// geri yüklerken projeler bu sütundan ayrıştırılır.
  Future<({List<List<String>> rows, int count})> exportAll() =>
      _locked(() async {
        final all = [for (final entries in _projects.values) ...entries]
          ..sort((a, b) {
            final byProject =
                a.record.projectNo.compareTo(b.record.projectNo);
            return byProject != 0
                ? byProject
                : a.scannedAt.compareTo(b.scannedAt);
          });
        return (
          rows: all.map((e) => _toRow(e, xlsxHeader)).toList(),
          count: all.length,
        );
      });

  /// Bir dosyadan okunan satırları (ilk satır başlık) mevcut kayıtlarla
  /// **birleştirir**: eksik olanlar eklenir, seri no zaten kayıtlıysa mevcut
  /// kayıt korunur. Hiçbir kayıt silinmez ve üzerine yazılmaz, bu yüzden iki
  /// telefonun verisini birleştirmek için de kullanılabilir.
  ///
  /// Kaynak Excel de olabilir CSV de; ikisi de aynı sütunları taşır.
  /// Başlık satırı tanınmazsa [FormatException] atar.
  Future<ImportResult> importRows(List<List<String>> rows) => _locked(() async {
        final decoded = _decodeRows(rows);
        // Başlık satırında Seri No yoksa seçilen dosya başka bir şey.
        if (!decoded.recognized) {
          throw const FormatException(
              'Bu dosya bir FATKatalog kayıt dosyası değil.');
        }

        var skipped = decoded.skipped;
        var added = 0;
        var updated = 0;
        var unchanged = 0;

        // Proje no → o projenin yazılacak yeni listesi.
        final pending = <String, List<ScanEntry>>{};
        final dirty = <String>{};
        // Bu dosyayla eklenen seri no → proje no; dosyanın kendi içindeki
        // tekrarları da yakalar.
        final incomingSerials = <String, String>{};

        List<ScanEntry> working(String projectNo) =>
            pending[projectNo] ??= [...?_projects[projectNo]];

        for (final entry in decoded.entries) {
          final projectNo = entry.record.projectNo.trim();
          if (!_projectNo.hasMatch(projectNo)) {
            skipped++;
            continue;
          }
          final serialNo = entry.record.serialNo;
          final existingProjectNo =
              _serialIndex[serialNo] ?? incomingSerials[serialNo];

          if (existingProjectNo == null) {
            working(projectNo).add(entry);
            incomingSerials[serialNo] = projectNo;
            dirty.add(projectNo);
            added++;
            continue;
          }

          // Kayıt zaten var. Seri no başka bir projede görünüyorsa dosya ile
          // telefon çelişiyor demektir; karışmasın diye dokunmuyoruz.
          if (existingProjectNo != projectNo) {
            unchanged++;
            continue;
          }
          // Yalnızca boş alanlar dosyadan tamamlanır; dolu alanın üstüne
          // asla yazılmaz.
          final list = working(projectNo);
          final index = list.indexWhere((e) => e.record.serialNo == serialNo);
          final filled = index < 0 ? null : list[index].filledFrom(entry);
          if (filled == null) {
            unchanged++;
            continue;
          }
          list[index] = filled;
          dirty.add(projectNo);
          updated++;
        }

        // Proje proje yazılır; biri hata verirse önceki projeler diskte ve
        // bellekte tutarlı kalır.
        for (final projectNo in dirty) {
          final entries = pending[projectNo]!
            ..sort((a, b) => a.scannedAt.compareTo(b.scannedAt));
          await _writeProject(projectNo, entries);
          _projects[projectNo] = entries;
          for (final entry in entries) {
            _serialIndex[entry.record.serialNo] = projectNo;
          }
        }
        if (dirty.isNotEmpty) _changes.add(null);
        return ImportResult(
          added: added,
          updated: updated,
          unchanged: unchanged,
          skipped: skipped,
        );
      });

  /// Yazmaları sıraya dizer; bir işlem hata verse de sonraki işlemler çalışır.
  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) async {
      await _ensureLoaded();
      return action();
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await projectsDir.create(recursive: true);
    await for (final entity in projectsDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith(_tmpSuffix)) {
        // Yarıda kalmış bir yazmadan artakalan geçici dosya.
        await entity.delete();
        continue;
      }
      final projectNo = _projectFileName.firstMatch(name)?.group(1);
      if (projectNo == null) continue;
      final entries = _decodeCsv(await entity.readAsString()).entries;
      if (entries.isEmpty) continue;
      _projects[projectNo] = entries;
      for (final e in entries) {
        _serialIndex[e.record.serialNo] = projectNo;
      }
    }
    _loaded = true;
  }

  Future<void> _writeProject(String projectNo, List<ScanEntry> entries) async {
    final rows = [header, ...entries.map((e) => _toRow(e, header))];
    await _writeAtomic(_csvFile(projectNo), utf8.encode(CsvCodec.encode(rows)));
    await _writeAtomic(_xlsxFile(projectNo), _encodeXlsx(projectNo, entries));
  }

  List<int> _encodeXlsx(String projectNo, List<ScanEntry> entries) =>
      XlsxWriter.encode(
        sheetName: projectNo,
        header: xlsxHeader,
        rows: entries.map((e) => _toRow(e, xlsxHeader)).toList(),
        headerStyle: headerStyle,
      );

  /// Önce geçici dosyaya yazar, sonra asıl dosyanın yerine taşır: yazma
  /// sırasında uygulama kapanırsa asıl dosya ya eski ya yeni haliyle kalır.
  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final tmp = File('${target.path}$_tmpSuffix');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  static _Decoded _decodeCsv(String text) => _decodeRows(CsvCodec.decode(text));

  /// Satırları (ilk satır başlık) **başlık adlarına göre** çözer.
  ///
  /// Sütun sırası değişse, araya yeni bir sütun girse ya da tanımadığımız bir
  /// sütun gelse de satır düşmez; yalnızca bildiğimiz sütunlar okunur, bilmediği
  /// sütunu olan satır atlanmaz. Böylece yeni sürümün yazdığı dosya eski
  /// sürümde de açılır — sütun eklemek eski kayıtları kaybettirmez.
  /// Başlık tanınmazsa (ör. elle bozulmuş dosya) sütun sırasına göre çözer.
  ///
  /// Kaynağı CSV de olabilir Excel de; ikisi de aynı sütunları taşır.
  static _Decoded _decodeRows(List<List<String>> rows) {
    if (rows.isEmpty) return const _Decoded([], 0, recognized: false);

    final columns = _columnIndex(rows.first);
    final entries = <ScanEntry>[];
    var skipped = 0;
    for (final row in rows.skip(1)) {
      // Dosya sonundaki boş satır hata sayılmaz.
      if (row.every((field) => field.trim().isEmpty)) continue;
      final entry = columns == null
          ? _entryFromPositions(row)
          : _entryFromColumns(row, columns);
      if (entry == null) {
        skipped++;
        continue;
      }
      entries.add(entry);
    }
    return _Decoded(entries, skipped, recognized: columns != null);
  }

  /// Başlık satırından "sütun adı → sıra no" haritası; Seri No sütunu yoksa
  /// (yani satır başlık değilse) `null`.
  static Map<String, int>? _columnIndex(List<String> headerRow) {
    final index = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final name = headerRow[i].trim();
      // Aynı ad iki kez geçerse ilki geçerli.
      if (name.isNotEmpty) index.putIfAbsent(name, () => i);
    }
    return index.containsKey(serialNoColumn) ? index : null;
  }

  static ScanEntry? _entryFromColumns(
    List<String> row,
    Map<String, int> columns,
  ) {
    String value(String column) {
      final i = columns[column];
      // Sütun bu dosyada yok (ör. Palet No'suz eski biçim) ya da satır kısa.
      return i != null && i < row.length ? row[i] : '';
    }

    return _entry(
      projectNo: value(projectNoColumn),
      workOrderNo: value(workOrderNoColumn),
      erpProductNo: value(erpProductNoColumn),
      serialNo: value(serialNoColumn),
      productionDate: value(productionDateColumn),
      positionNo: value(positionNoColumn),
      palletNo: value(palletNoColumn),
      palletSize: value(palletSizeColumn),
      scannedAt: value(scannedAtColumn),
    );
  }

  static ScanEntry? _entryFromPositions(List<String> row) {
    // CSV sütun sırası; eski biçimlerde sondaki sütunlar yok.
    if (row.length != _noPalletColumnCount &&
        row.length != _noPalletSizeColumnCount &&
        row.length != header.length) {
      return null;
    }
    final hasPallet = row.length > _noPalletColumnCount;
    final hasPalletSize = row.length > _noPalletSizeColumnCount;
    return _entry(
      projectNo: row[0],
      workOrderNo: row[1],
      erpProductNo: row[2],
      serialNo: row[3],
      productionDate: row[4],
      positionNo: row[5],
      palletNo: hasPallet ? row[6] : '',
      palletSize: hasPalletSize ? row[8] : '',
      scannedAt: hasPallet ? row[7] : row[6],
    );
  }

  static ScanEntry? _entry({
    required String projectNo,
    required String workOrderNo,
    required String erpProductNo,
    required String serialNo,
    required String productionDate,
    required String positionNo,
    required String palletNo,
    required String palletSize,
    required String scannedAt,
  }) {
    // Seri no kaydın kimliği; onsuz satır işe yaramaz.
    if (serialNo.trim().isEmpty) return null;
    return ScanEntry(
      record: LabelRecord(
        projectNo: projectNo,
        workOrderNo: workOrderNo,
        erpProductNo: erpProductNo,
        serialNo: serialNo,
        productionDate: productionDate,
        positionNo: positionNo,
      ),
      palletNo: palletNo,
      palletSize: palletSize,
      // Bozuk zaman damgası kaydı kaybettirmesin; en eskiye yerleşir.
      scannedAt: parseTimestamp(scannedAt) ?? DateTime(1970),
    );
  }

  /// Kaydın [columns] sırasındaki satırı (CSV için [header], Excel için
  /// [xlsxHeader]).
  static List<String> _toRow(ScanEntry e, List<String> columns) => [
        for (final column in columns)
          switch (column) {
            projectNoColumn => e.record.projectNo,
            workOrderNoColumn => e.record.workOrderNo,
            erpProductNoColumn => e.record.erpProductNo,
            serialNoColumn => e.record.serialNo,
            productionDateColumn => e.record.productionDate,
            positionNoColumn => e.record.positionNo,
            palletNoColumn => e.palletNo,
            palletSizeColumn => e.palletSize,
            scannedAtColumn => formatTimestamp(e.scannedAt),
            _ => '',
          },
      ];

  /// CSV saniye hassasiyetinde; bellekteki değer diskteki ile aynı kalsın.
  DateTime _now() {
    final t = _clock();
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  File _csvFile(String projectNo) =>
      File('${projectsDir.path}${Platform.pathSeparator}$projectNo.csv');

  File _xlsxFile(String projectNo) =>
      File('${projectsDir.path}${Platform.pathSeparator}$projectNo.xlsx');
}

/// [ProjectRepository._decodeCsv] çıktısı: okunan kayıtlar + okunamayan satır
/// sayısı (geri yükleme sonucunda kullanıcıya bildirilir).
class _Decoded {
  const _Decoded(this.entries, this.skipped, {required this.recognized});

  final List<ScanEntry> entries;
  final int skipped;

  /// Başlık satırı FATKatalog sütunlarını içeriyor mu; geri yüklerken yanlış
  /// dosyayı ayırt etmek için.
  final bool recognized;
}
