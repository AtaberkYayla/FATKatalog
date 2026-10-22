import 'package:flutter/material.dart';

import '../../model/label_record.dart';
import '../../storage/project_repository.dart';

/// Projeyi arşive almak için onay ister ve arşivler; Proje Detayı ile Projeler
/// listesi ortak kullanır. Vazgeçilirse ya da hata olursa `null`.
Future<ArchiveSummary?> confirmAndArchive(
  BuildContext context,
  ProjectRepository repository,
  String projectNo,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.archive_outlined),
      title: Text('$projectNo arşive alınsın mı?'),
      content: Text(
        '$projectNo projesinin listesi ana listeden kalkar ve Arşiv '
        'sekmesinde saklanmaya devam eder. $projectNo için yeni bir liste '
        'boş başlar.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Arşive al'),
        ),
      ],
    ),
  );
  if (confirmed != true) return null;

  try {
    final archive = await repository.archiveProject(projectNo);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(archive == null
            ? '$projectNo projesi bulunamadı'
            : '$projectNo arşive alındı'),
      ));
    return archive;
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Arşive alınamadı: $e')));
    return null;
  }
}
