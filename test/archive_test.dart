import 'dart:io';

import 'package:fatkatalog/export/export_manager.dart';
import 'package:fatkatalog/model/label_record.dart';
import 'package:fatkatalog/model/parse_result.dart';
import 'package:fatkatalog/parser/qr_parser.dart';
import 'package:fatkatalog/storage/project_repository.dart';
import 'package:fatkatalog/storage/timestamp.dart';
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

  ProjectRepository newRepo() =>
      ProjectRepository(dir, headerStyle: _style, clock: () => now);

  String sep(String a, String b) => '$a${Platform.pathSeparator}$b';
  File projectFile(String name) => File(sep(dir.path, name));
  File archiveFile(String name) =>
      File(sep(sep(dir.path, ProjectRepository.archiveDirName), name));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fatkatalog_archive');
    now = DateTime(2026, 10, 13, 15, 41, 7);
  });

  tearDown(() => dir.delete(recursive: true));

  test('arşivleme dosyaları archive klasörüne tarih ve saatli adla taşır',
      () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_b);
    await repo.add(_c);

    final archive = (await repo.archiveProject('8835'))!;

    expect(archive.id, '8835_13-10-2026_15-41-07');
    expect(archive.projectNo, '8835');
    expect(archive.itemCount, 2);
    expect(archive.archivedAt, DateTime(2026, 10, 13, 15, 41, 7));
    expect(await projectFile('8835.csv').exists(), isFalse);
    expect(await projectFile('8835.xlsx').exists(), isFalse);
    expect(await archiveFile('8835_13-10-2026_15-41-07.csv').exists(), isTrue);
    expect(await archiveFile('8835_13-10-2026_15-41-07.xlsx').exists(), isTrue);
    // Diğer proje yerinde.
    expect(await projectFile('8840.csv').exists(), isTrue);
  });

  test('arşivlenen proje ana listeden kalkar, arşiv listesinde görünür',
      () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_c);
    await repo.archiveProject('8835');

    expect((await repo.listProjects()).map((p) => p.projectNo), ['8840']);
    expect(await repo.entries('8835'), isEmpty);
    final archives = await repo.listArchives();
    expect(archives, hasLength(1));
    expect(archives.single.projectNo, '8835');
    expect(archives.single.itemCount, 1);
    expect(formatArchiveLabel(archives.single.archivedAt), '13.10.2026-15:41');
  });

  test('arşivlenen seri no yeni listede tekrar okutulabilir', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.archiveProject('8835');

    expect(await repo.add(_a), isA<Added>());
    expect((await repo.entries('8835')).length, 1);
    // Eski liste arşivde olduğu gibi duruyor.
    final archive = (await repo.listArchives()).single;
    expect((await repo.archivedEntries(archive.id)).length, 1);
  });

  test('aynı proje birden çok kez arşivlenebilir, en yeni üstte', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.archiveProject('8835');

    now = DateTime(2026, 10, 20, 9, 5, 0);
    await repo.add(_b);
    await repo.archiveProject('8835');

    final archives = await repo.listArchives();
    expect(archives.map((a) => a.id),
        ['8835_20-10-2026_09-05-00', '8835_13-10-2026_15-41-07']);
  });

  test('aynı saniyedeki çakışmada mevcut arşivin üstüne yazılmaz', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.archiveProject('8835');
    await repo.add(_b);
    await repo.archiveProject('8835'); // aynı saniye

    final archives = await repo.listArchives();
    expect(archives, hasLength(2));
    expect({for (final a in archives) a.itemCount}, {1});
  });

  test('yeniden açılışta arşiv okunur, ana listeye ve yedeğe karışmaz',
      () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.add(_c);
    await repo.archiveProject('8835');

    final reopened = newRepo();
    expect((await reopened.listProjects()).map((p) => p.projectNo), ['8840']);
    expect((await reopened.listArchives()).single.projectNo, '8835');
    expect((await reopened.exportAll()).count, 1);
    // Arşivlenen seri no kayıtlı sayılmaz.
    expect(await reopened.add(_a), isA<Added>());
  });

  test('arşivdeki kayıtlar palet ve ölçüyle birebir okunur', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.assignPallet('8835', {_a.serialNo}, 'P7',
        palletSize: '800 x 1200');
    await repo.archiveProject('8835');

    final archive = (await repo.listArchives()).single;
    final entries = await repo.archivedEntries(archive.id);
    expect(entries.single.record, _a);
    expect(entries.single.palletNo, 'P7');
    expect(entries.single.palletSize, '800 x 1200');
  });

  test('arşiv xlsx dosyası üretilir', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.archiveProject('8835');

    final archive = (await repo.listArchives()).single;
    final xlsx = await repo.archivedXlsxFile(archive.id);
    expect(xlsx, isNotNull);
    expect(await xlsx!.exists(), isTrue);
    expect(ExportManager.archiveFileNameFor(archive),
        '8835_arsiv_13-10-2026_15-41.xlsx');
  });

  test('arşivden silme dosyaları kaldırır', () async {
    final repo = newRepo();
    await repo.add(_a);
    await repo.archiveProject('8835');
    final archive = (await repo.listArchives()).single;
    await repo.archivedXlsxFile(archive.id);

    expect(await repo.deleteArchive(archive.id), isTrue);
    expect(await repo.listArchives(), isEmpty);
    expect(await archiveFile('${archive.id}.csv').exists(), isFalse);
    expect(await archiveFile('${archive.id}.xlsx').exists(), isFalse);
    expect(await repo.deleteArchive(archive.id), isFalse);
  });

  test('olmayan proje arşivlenmez; geçersiz arşiv adı reddedilir', () async {
    final repo = newRepo();
    expect(await repo.archiveProject('9999'), isNull);
    expect(await repo.archivedEntries('../8835'), isEmpty);
    expect(await repo.archivedXlsxFile('../8835'), isNull);
    expect(await repo.deleteArchive('../8835'), isFalse);
  });
}
