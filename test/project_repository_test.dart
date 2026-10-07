import 'dart:io';

import 'package:fatkatalog/model/parse_result.dart';
import 'package:fatkatalog/parser/qr_parser.dart';
import 'package:fatkatalog/model/label_record.dart';
import 'package:fatkatalog/storage/csv_codec.dart';
import 'package:fatkatalog/storage/project_repository.dart';
import 'package:fatkatalog/xlsx/xlsx_reader.dart';
import 'package:fatkatalog/xlsx/xlsx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = XlsxHeaderStyle(fillArgb: 0xFF1A1A1A, fontArgb: 0xFFFFFFFF);

LabelRecord _label(String raw) => (QrParser.parse(raw) as ParseSuccess).record;

final _a = _label('8835*P2-00180700*601107999*DDM261062*06/2026');
final _b = _label('8835*P2-00180701*601108000*DDM261063*06/2026');
final _c = _label('8840*P2-00190100*601109500*DDM261101*07/2026');

void main() {
  late Directory dir;
  late DateTime now;
  final temps = <Directory>[];

  ProjectRepository repoIn(Directory d) =>
      ProjectRepository(d, headerStyle: _style, clock: () => now);
  ProjectRepository newRepo() => repoIn(dir);

  /// Başka bir cihazı temsil eden ikinci bir boş klasör.
  Future<Directory> newTempDir() async {
    final d = await Directory.systemTemp.createTemp('fatkatalog_test');
    temps.add(d);
    return d;
  }

  /// Dışa aktarılan tablo, başlık satırıyla birlikte (dosyaya yazılacak hali).
  Future<List<List<String>>> exportRows(ProjectRepository repo) async =>
      [ProjectRepository.xlsxHeader, ...(await repo.exportAll()).rows];

  setUp(() async {
    dir = await newTempDir();
    now = DateTime(2026, 9, 22, 10, 50, 0, 123);
  });

  tearDown(() async {
    for (final d in temps) {
      if (await d.exists()) await d.delete(recursive: true);
    }
    temps.clear();
  });

  File file(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  test('ekleme CSV ve xlsx yazar', () async {
    final repo = newRepo();
    final result = await repo.add(_a);
    expect(result, isA<Added>());
    expect((result as Added).entry.scannedAt, DateTime(2026, 9, 22, 10, 50));

    final rows = CsvCodec.decode(await file('8835.csv').readAsString());
    expect(rows, [
      ProjectRepository.header,
      ['8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', '', '', '22.09.2026 10:50:00', ''],
    ]);
    expect(await file('8835.xlsx').exists(), isTrue);
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('Poz No CSV ye yazılır ve geri okunur', () async {
    final withPos =
        _label('8850*P2-00200000*601200000*DDM270001*01/2027*P-07');
    await newRepo().add(withPos);
    final rows = CsvCodec.decode(await file('8850.csv').readAsString());
    expect(rows[1][5], 'P-07');
    final reopened = newRepo();
    expect((await reopened.entries('8850')).single.record, withPos);
  });

  test('aynı seri no tüm projelerde reddedilir', () async {
    final repo = newRepo();
    await repo.add(_a);
    final dup = await repo.add(LabelRecord(
      projectNo: '8840',
      workOrderNo: 'X',
      erpProductNo: '1',
      serialNo: _a.serialNo,
      productionDate: '01/2026',
    ));
    expect(dup, isA<Duplicate>());
    expect((dup as Duplicate).existingProjectNo, '8835');
    expect(await file('8840.csv').exists(), isFalse);
    expect(await repo.entries('8835'), hasLength(1));
  });

  test('tekrar kontrolü yeniden açılışta diskten yüklenir', () async {
    await newRepo().add(_a);
    final reopened = newRepo();
    expect(await reopened.add(_a), isA<Duplicate>());
    expect(await reopened.entries('8835'), hasLength(1));
  });

  test('projelere göre gruplama ve son okutmaya göre sıralama', () async {
    final repo = newRepo();
    await repo.add(_a);
    now = now.add(const Duration(minutes: 1));
    await repo.add(_c);
    now = now.add(const Duration(minutes: 1));
    await repo.add(_b);

    final projects = await repo.listProjects();
    expect(projects.map((p) => p.projectNo), ['8835', '8840']);
    expect(projects.map((p) => p.itemCount), [2, 1]);
    expect(projects.first.lastScannedAt, DateTime(2026, 9, 22, 10, 52));

    final serials =
        (await repo.entries('8835')).map((e) => e.record.serialNo).toList();
    expect(serials, ['DDM261062', 'DDM261063']);
  });

  test('silme CSV yi yeniden yazar ve seri no tekrar okutulabilir', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_b);

    expect(await repo.delete('8835', {'DDM261062'}), 1);
    expect(await repo.delete('8835', {'DDM261062'}), 0);

    final rows = CsvCodec.decode(await file('8835.csv').readAsString());
    expect(rows.skip(1).map((r) => r[3]), ['DDM261063']);
    expect(await repo.add(_a), isA<Added>());
  });

  test('projenin son kaydı silinince dosyaları da silinir', () async {
    final repo = newRepo();
    await repo.add(_c);
    expect(await repo.delete('8840', {'DDM261101'}), 1);
    expect(await file('8840.csv').exists(), isFalse);
    expect(await file('8840.xlsx').exists(), isFalse);
    expect(await repo.listProjects(), isEmpty);
  });

  test('eşzamanlı eklemeler sıralı işlenir', () async {
    final repo = newRepo();
    final results = await Future.wait([
      repo.add(_a),
      repo.add(_a),
      repo.add(_b),
      repo.add(_c),
    ]);
    expect(results.whereType<Added>(), hasLength(3));
    expect(results.whereType<Duplicate>(), hasLength(1));
    final reopened = newRepo();
    expect(await reopened.entries('8835'), hasLength(2));
  });

  test('yarım kalmış geçici dosya açılışta temizlenir', () async {
    await newRepo().add(_a);
    await file('8835.csv.tmp').writeAsString('yarım');
    final reopened = newRepo();
    expect(await reopened.entries('8835'), hasLength(1));
    expect(await file('8835.csv.tmp').exists(), isFalse);
  });

  test('seçilen kayıtlara palet atanır, CSV ye yazılır ve geri okunur',
      () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_b);

    expect(
        await repo.assignPallet('8835', {'DDM261062', 'DDM261063'}, ' PLT-01 '),
        2);
    // Aynı palet tekrar atanırsa değişiklik yok.
    expect(await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01'), 0);

    final rows = CsvCodec.decode(await file('8835.csv').readAsString());
    expect(rows[0][6], 'Palet No');
    expect(rows.skip(1).map((r) => r[6]), ['PLT-01', 'PLT-01']);

    final reopened = newRepo();
    expect((await reopened.entries('8835')).map((e) => e.palletNo),
        ['PLT-01', 'PLT-01']);
  });

  test('boş palet no paleti kaldırır', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01');
    expect(await repo.assignPallet('8835', {'DDM261062'}, ''), 1);
    expect((await repo.entries('8835')).single.palletNo, '');
  });

  test('palet ataması okutma zamanını ve sırayı korur', () async {
    final repo = newRepo();
    await repo.add(_a);
    now = now.add(const Duration(minutes: 5));
    await repo.add(_b);
    await repo.assignPallet('8835', {'DDM261063'}, 'PLT-02');
    final entries = await repo.entries('8835');
    expect(entries.map((e) => e.record.serialNo), ['DDM261062', 'DDM261063']);
    expect(entries.last.scannedAt, DateTime(2026, 9, 22, 10, 55));
  });

  test('çoklu silme', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_b);
    await repo.add(_c);
    expect(await repo.delete('8835', {'DDM261062', 'DDM261063', 'YOK'}), 2);
    expect(await file('8835.csv').exists(), isFalse);
    expect((await repo.listProjects()).map((p) => p.projectNo), ['8840']);
  });

  test('Palet No sütunu olmayan eski CSV okunur ve ilk yazmada taşınır',
      () async {
    await dir.create(recursive: true);
    await file('8835.csv').writeAsString(CsvCodec.encode([
      [
        'Proje No', 'İş Emri No', 'Erp Ürün No', 'Seri No', 'Üretim Yılı',
        'Poz No', 'Okutma Zamanı',
      ],
      ['8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', 'P-1',
          '22.09.2026 09:00:00'],
    ]));

    final repo = newRepo();
    final old = (await repo.entries('8835')).single;
    expect(old.palletNo, '');
    expect(old.record.positionNo, 'P-1');
    expect(old.scannedAt, DateTime(2026, 9, 22, 9));
    expect(await repo.add(_a), isA<Duplicate>());

    await repo.assignPallet('8835', {'DDM261062'}, 'PLT-09');
    final rows = CsvCodec.decode(await file('8835.csv').readAsString());
    expect(rows[0], ProjectRepository.header);
    expect(rows[1], [
      '8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', 'P-1',
      'PLT-09', '22.09.2026 09:00:00', '',
    ]);
  });

  test('bilinmeyen sütunu olan CSV okunur, satır düşmez', () async {
    // İleride eklenecek bir sütunu olan (yani daha yeni bir sürümün yazdığı)
    // dosya: tanımadığımız sütun yok sayılır, kayıt kaybolmaz.
    await dir.create(recursive: true);
    await file('8835.csv').writeAsString(CsvCodec.encode([
      [...ProjectRepository.header, 'FAT Sonucu'],
      [
        '8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', 'P-1',
        'PLT-09', '22.09.2026 09:00:00', '800 x 1200', 'Geçti',
      ],
    ]));

    final entry = (await newRepo().entries('8835')).single;
    expect(entry.record.serialNo, 'DDM261062');
    expect(entry.palletNo, 'PLT-09');
    expect(entry.palletSize, '800 x 1200');
    expect(entry.scannedAt, DateTime(2026, 9, 22, 9));
  });

  test('sütun sırası değişmiş CSV başlığa göre okunur', () async {
    await dir.create(recursive: true);
    await file('8835.csv').writeAsString(CsvCodec.encode([
      ['Okutma Zamanı', 'Seri No', 'Proje No', 'Palet No'],
      ['22.09.2026 09:00:00', 'DDM261062', '8835', 'PLT-09'],
    ]));

    final entry = (await newRepo().entries('8835')).single;
    expect(entry.record.serialNo, 'DDM261062');
    expect(entry.palletNo, 'PLT-09');
    // Dosyada olmayan sütunlar boş kalır, kayıt yine de okunur.
    expect(entry.record.workOrderNo, '');
  });

  test('dışa aktarma tüm projeleri tek tabloda toplar', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_c);
    await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01');

    final all = await repo.exportAll();
    expect(all.count, 2);
    expect(all.rows.map((r) => r[0]), ['8835', '8840']);
    expect(all.rows[0][6], 'PLT-01');
  });

  test('dışa aktarılan kayıtlar boş klasöre geri yüklenir', () async {
    final source = newRepo();
    await source.add(_a);
    await source.add(_c);
    await source.assignPallet('8835', {'DDM261062'}, 'PLT-01');
    final exported = await exportRows(source);

    // Uygulama kaldırılmış gibi: yeni, boş bir klasör.
    dir = await newTempDir();
    final restored = repoIn(dir);
    final result = await restored.importRows(exported);

    expect(result.added, 2);
    expect(result.unchanged, 0);
    expect(result.updated, 0);
    expect(result.skipped, 0);
    expect((await restored.listProjects()).map((p) => p.projectNo),
        containsAll(['8835', '8840']));
    final entry = (await restored.entries('8835')).single;
    expect(entry.palletNo, 'PLT-01');
    expect(entry.scannedAt, DateTime(2026, 9, 22, 10, 50));
    expect(await file('8835.xlsx').exists(), isTrue);
  });

  test('içe aktarma mevcut kayıtları silmez, eksikleri ekler', () async {
    final source = newRepo();
    await source.add(_a);
    await source.add(_b);
    final exported = await exportRows(source);

    // İkinci telefon: dosyadaki iki kayıttan biri burada da var, biri yok.
    final other = repoIn(await newTempDir());
    await other.add(_a);
    now = now.add(const Duration(minutes: 10));
    await other.add(_c);

    final result = await other.importRows(exported);
    expect(result.added, 1); // yalnızca _b
    expect(result.unchanged, 1); // _a zaten vardı, tamamlanacak boş alanı yok
    expect(result.skipped, 0);

    expect((await other.entries('8835')).map((e) => e.record.serialNo),
        ['DDM261062', 'DDM261063']);
    // Dosyada olmayan kayıt korunur.
    expect(await other.entries('8840'), hasLength(1));
  });

  test('dosyadaki palet no telefondaki boş alana yazılır', () async {
    // Ofis senaryosu: indirilen Excel'de Palet No sütunu elle dolduruluyor.
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_b);

    final edited = await exportRows(repo);
    edited[1][6] = 'PLT-01'; // DDM261062
    edited[2][6] = 'PLT-02'; // DDM261063

    final result = await repo.importRows(edited);
    expect(result.added, 0);
    expect(result.updated, 2);
    expect(result.unchanged, 0);

    expect((await repo.entries('8835')).map((e) => e.palletNo),
        ['PLT-01', 'PLT-02']);
    // Diske de yazılmış olmalı.
    final rows = CsvCodec.decode(await file('8835.csv').readAsString());
    expect(rows.skip(1).map((r) => r[6]), ['PLT-01', 'PLT-02']);
  });

  test('dolu alanın üstüne yazılmaz', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.assignPallet('8835', {'DDM261062'}, 'PLT-09');

    final other = await exportRows(repo);
    other[1][6] = 'PLT-01'; // telefonda PLT-09 var
    other[1][1] = 'BASKA-IS-EMRI'; // telefonda dolu

    final result = await repo.importRows(other);
    expect(result.updated, 0);
    expect(result.unchanged, 1);

    final entry = (await repo.entries('8835')).single;
    expect(entry.palletNo, 'PLT-09');
    expect(entry.record.workOrderNo, 'P2-00180700');
  });

  test('okutma zamanı dosyadan değil kayıttan kalır', () async {
    final repo = newRepo();
    await repo.add(_a);

    final edited = await exportRows(repo);
    edited[1][6] = 'PLT-01';
    edited[1][8] = '01.01.2020 00:00:00'; // dosyadaki zaman farklı

    expect((await repo.importRows(edited)).updated, 1);
    final entry = (await repo.entries('8835')).single;
    expect(entry.palletNo, 'PLT-01');
    expect(entry.scannedAt, DateTime(2026, 9, 22, 10, 50));
  });

  test('seri no başka projede görünüyorsa dokunulmaz', () async {
    final repo = newRepo();
    await repo.add(_a); // DDM261062 → 8835

    // Dosya aynı seri numarasını 8840 projesinde gösteriyor.
    final conflicting = [
      ProjectRepository.header,
      ['8840', 'P2-9', '999', 'DDM261062', '06/2026', '', 'PLT-01',
          '22.09.2026 09:00:00'],
    ];

    final result = await repo.importRows(conflicting);
    expect(result.added, 0);
    expect(result.updated, 0);
    expect(result.unchanged, 1);

    expect((await repo.entries('8835')).single.palletNo, '');
    expect(await repo.entries('8840'), isEmpty);
  });

  test('değişiklik yoksa dosyalar yeniden yazılmaz', () async {
    final repo = newRepo();
    await repo.add(_a);
    final before = await file('8835.csv').lastModified();

    final result = await repo.importRows(await exportRows(repo));
    expect(result.unchanged, 1);
    expect(await file('8835.csv').lastModified(), before);
  });

  test('içe aktarılan kayıt tekrar okutulamaz', () async {
    final source = newRepo();
    await source.add(_a);
    final exported = await exportRows(source);

    final restored = repoIn(await newTempDir());
    await restored.importRows(exported);
    expect(await restored.add(_a), isA<Duplicate>());
  });

  test('bozuk satırlar sayılır, diğerleri yüklenir', () async {
    final csv = CsvCodec.encode([
      ProjectRepository.header,
      // Geçerli.
      ['8835', 'P2-1', '601', 'DDM1', '06/2026', '', '', '22.09.2026 09:00:00'],
      // Seri no yok.
      ['8835', 'P2-2', '602', '', '06/2026', '', '', '22.09.2026 09:00:00'],
      // Proje no 4 haneli değil.
      ['88', 'P2-3', '603', 'DDM3', '06/2026', '', '', '22.09.2026 09:00:00'],
      // Yedeğin kendi içinde tekrar eden seri no.
      ['8835', 'P2-4', '604', 'DDM1', '06/2026', '', '', '22.09.2026 09:00:00'],
    ]);

    // CSV de kabul edilir (eski dosyalar, elle düzenlenmiş dosyalar).
    final result = await newRepo().importRows(CsvCodec.decode(csv));
    expect(result.added, 1);
    expect(result.skipped, 2);
    expect(result.unchanged, 1);
  });

  test('eski sürümün dosyasında olmayan sütun boş gelir, satır kaybolmaz',
      () async {
    // Palet No (ve Poz No) sütunları eklenmeden önceki bir sürümün dosyası.
    final older = [
      ['Proje No', 'İş Emri No', 'Erp Ürün No', 'Seri No', 'Üretim Yılı',
          'Okutma Zamanı'],
      ['8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026',
          '22.09.2026 09:00:00'],
      ['8840', 'P2-00190100', '601109500', 'DDM261101', '07/2026',
          '22.09.2026 09:05:00'],
    ];

    final repo = newRepo();
    final result = await repo.importRows(older);
    expect(result.added, 2);
    expect(result.skipped, 0);

    final entry = (await repo.entries('8835')).single;
    expect(entry.record.serialNo, 'DDM261062');
    expect(entry.scannedAt, DateTime(2026, 9, 22, 9));
    // Dosyada olmayan yeni sütunlar boş; kayıt yine de tam.
    expect(entry.palletNo, '');
    expect(entry.record.positionNo, '');

    // Geri yüklenen kayıt güncel biçimde yazılır ve palet atanabilir.
    expect(await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01'), 1);
    final rows = CsvCodec.decode(await file('8835.csv').readAsString());
    expect(rows[0], ProjectRepository.header);
    expect(rows[1][6], 'PLT-01');
  });

  test('yeni sürümün dosyasındaki bilinmeyen sütun yok sayılır', () async {
    // İleride eklenecek bir sütunu olan dosya: tanımadığımız sütun atlanır,
    // bildiğimiz sütunlar ve satırın kendisi korunur.
    final newer = [
      [...ProjectRepository.header, 'FAT Sonucu'],
      [
        '8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', 'P-1',
        'PLT-09', '22.09.2026 09:00:00', '', 'Geçti',
      ],
    ];

    final repo = newRepo();
    expect((await repo.importRows(newer)).added, 1);
    final entry = (await repo.entries('8835')).single;
    expect(entry.palletNo, 'PLT-09');
    expect(entry.record.positionNo, 'P-1');
  });

  test('indirilen proje Excel dosyası olduğu gibi geri yüklenir', () async {
    final source = newRepo();
    await source.add(_a);
    await source.add(_b);
    await source.assignPallet('8835', {'DDM261062'}, 'PLT-01');

    // "Excel olarak indir"in ürettiği dosyanın baytları.
    final xlsx = await (await source.xlsxFile('8835'))!.readAsBytes();

    final target = repoIn(await newTempDir());
    final result = await target.importRows(XlsxReader.decode(xlsx));
    expect(result.added, 2);
    expect(result.skipped, 0);

    final entries = await target.entries('8835');
    expect(entries.map((e) => e.record.serialNo),
        ['DDM261062', 'DDM261063']);
    expect(entries.first.palletNo, 'PLT-01');
    expect(entries.first.scannedAt, DateTime(2026, 9, 22, 10, 50));
    expect(entries.first.record.productionDate, '06/2026');
  });

  test('FATKatalog dosyası olmayan içerik reddedilir', () async {
    final repo = newRepo();
    expect(
      () => repo.importRows(CsvCodec.decode('bir;iki;üç\r\n1;2;3\r\n')),
      throwsA(isA<FormatException>()),
    );
    // Reddedilen dosya hiçbir şey yazmamalı.
    expect(await repo.listProjects(), isEmpty);
  });

  test('xlsxFile dosyayı CSV den yeniden üretir', () async {
    final repo = newRepo();
    await repo.add(_a);
    await file('8835.xlsx').delete();
    final xlsx = await repo.xlsxFile('8835');
    expect(await xlsx!.exists(), isTrue);
    expect(await repo.xlsxFile('9999'), isNull);
  });

  group('palet ölçüsü', () {
    test('palet no ile birlikte atanır; CSV de sona, Excel de araya yazılır',
        () async {
      final repo = newRepo();
      await repo.add(_a);
      expect(
        await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01',
            palletSize: ' 800 x 1200 '),
        1,
      );

      // CSV: yeni sütun sona eklenir (eski sütunların sırası değişmez).
      final csv = CsvCodec.decode(await file('8835.csv').readAsString());
      expect(csv[0].last, 'Palet Ölçüsü (mm)');
      expect(csv[0][7], 'Okutma Zamanı');
      expect(csv[1].last, '800 x 1200');

      // Excel: Palet No ile Okutma Zamanı arasında.
      final xlsx = XlsxReader.decode(
          await (await repo.xlsxFile('8835'))!.readAsBytes());
      expect(xlsx[0].sublist(6), ['Palet No', 'Palet Ölçüsü (mm)', 'Okutma Zamanı']);
      expect(xlsx[1].sublist(6),
          ['PLT-01', '800 x 1200', '22.09.2026 10:50:00']);

      final reopened = newRepo();
      expect((await reopened.entries('8835')).single.palletSize, '800 x 1200');
    });

    test('yalnızca ölçü değişirse de kayıt değişmiş sayılır', () async {
      final repo = newRepo();
      await repo.add(_a);
      await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01',
          palletSize: '800 x 1200');
      expect(
          await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01',
              palletSize: '800 x 1200'),
          0);
      expect(
          await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01',
              palletSize: '1000 x 1200'),
          1);
      expect((await repo.entries('8835')).single.palletSize, '1000 x 1200');
    });

    test('paleti kaldırmak ölçüyü de kaldırır', () async {
      final repo = newRepo();
      await repo.add(_a);
      await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01',
          palletSize: '800 x 1200');
      expect(
          await repo.assignPallet('8835', {'DDM261062'}, '',
              palletSize: '800 x 1200'),
          1);
      final entry = (await repo.entries('8835')).single;
      expect(entry.palletNo, '');
      expect(entry.palletSize, '');
    });

    test('Excel dosyasından ölçü geri yüklenir', () async {
      final source = newRepo();
      await source.add(_a);
      await source.assignPallet('8835', {'DDM261062'}, 'PLT-01',
          palletSize: '800 x 1200');
      final xlsx = await (await source.xlsxFile('8835'))!.readAsBytes();

      final target = repoIn(await newTempDir());
      expect((await target.importRows(XlsxReader.decode(xlsx))).added, 1);
      final entry = (await target.entries('8835')).single;
      expect(entry.palletNo, 'PLT-01');
      expect(entry.palletSize, '800 x 1200');
    });

    test('tüm projeler dosyasındaki ölçü de geri yüklenir', () async {
      final source = newRepo();
      await source.add(_a);
      await source.assignPallet('8835', {'DDM261062'}, 'PLT-01',
          palletSize: '800 x 1200');

      final target = repoIn(await newTempDir());
      expect((await target.importRows(await exportRows(source))).added, 1);
      expect((await target.entries('8835')).single.palletSize, '800 x 1200');
    });

    test('1.2.0 CSV si (ölçü sütunu yok) okunur, ilk yazmada yeni biçime geçer',
        () async {
      await dir.create(recursive: true);
      await file('8835.csv').writeAsString(CsvCodec.encode([
        [
          'Proje No', 'İş Emri No', 'Erp Ürün No', 'Seri No', 'Üretim Yılı',
          'Poz No', 'Palet No', 'Okutma Zamanı',
        ],
        ['8835', 'P2-00180700', '601107999', 'DDM261062', '06/2026', '',
            'PLT-09', '22.09.2026 09:00:00'],
      ]));

      final repo = newRepo();
      final old = (await repo.entries('8835')).single;
      expect(old.palletNo, 'PLT-09');
      expect(old.palletSize, '');

      await repo.assignPallet('8835', {'DDM261062'}, 'PLT-09',
          palletSize: '1000 x 1200');
      final rows = CsvCodec.decode(await file('8835.csv').readAsString());
      expect(rows[0], ProjectRepository.header);
      expect(rows[1].last, '1000 x 1200');
    });

    test('başlığı tanınmayan 8 sütunlu eski CSV sütun sırasına göre okunur',
        () async {
      // Başlık satırı bozulmuş (Seri No yok); eski 8 sütunlu biçimde zaman
      // 8. sütundadır, ölçü sütunu yoktur.
      final decoded = [
        ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
        ['8835', 'P2-1', '601', 'DDM1', '06/2026', '', 'PLT-09',
            '22.09.2026 09:00:00'],
      ];
      // Tanınmayan başlıkta içe aktarma reddedilir; CSV yüklemesi ise sütun
      // sırasına düşer.
      await dir.create(recursive: true);
      await file('8835.csv').writeAsString(CsvCodec.encode(decoded));
      final entry = (await newRepo().entries('8835')).single;
      expect(entry.palletNo, 'PLT-09');
      expect(entry.palletSize, '');
      expect(entry.scannedAt, DateTime(2026, 9, 22, 9));
    });

    test('içe aktarma boş ölçüyü tamamlar, dolu ölçünün üstüne yazmaz',
        () async {
      final repo = newRepo();
      await repo.add(_a);
      await repo.add(_b);
      await repo.assignPallet('8835', {'DDM261062', 'DDM261063'}, 'PLT-01');
      await repo.assignPallet('8835', {'DDM261063'}, 'PLT-01',
          palletSize: '800 x 1200');

      final file = await exportRows(repo);
      final sizeCol = ProjectRepository.xlsxHeader
          .indexOf(ProjectRepository.palletSizeColumn);
      file[1][sizeCol] = '1000 x 1200'; // telefonda boş → tamamlanır
      file[2][sizeCol] = '600 x 800'; // telefonda dolu → dokunulmaz

      final result = await repo.importRows(file);
      expect(result.updated, 1);
      expect(result.unchanged, 1);
      expect((await repo.entries('8835')).map((e) => e.palletSize),
          ['1000 x 1200', '800 x 1200']);
    });

    test('ölçü başka paletin olduğu için telefondaki palete yazılmaz',
        () async {
      final repo = newRepo();
      await repo.add(_a);
      await repo.assignPallet('8835', {'DDM261062'}, 'PLT-01'); // ölçüsüz

      final file = await exportRows(repo);
      final palletCol = ProjectRepository.xlsxHeader
          .indexOf(ProjectRepository.palletNoColumn);
      final sizeCol = ProjectRepository.xlsxHeader
          .indexOf(ProjectRepository.palletSizeColumn);
      file[1][palletCol] = 'PLT-02';
      file[1][sizeCol] = '1000 x 1200';

      expect((await repo.importRows(file)).updated, 0);
      final entry = (await repo.entries('8835')).single;
      expect(entry.palletNo, 'PLT-01');
      expect(entry.palletSize, '');
    });
  });
}
