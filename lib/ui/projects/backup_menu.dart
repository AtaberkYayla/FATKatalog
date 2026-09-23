import 'package:flutter/material.dart';

import '../../export/backup_manager.dart';
import '../../storage/project_repository.dart';

enum _BackupAction { save, share, restore }

/// Üst çubuktaki yedekleme menüsü: yedek al · paylaş · geri yükle.
class BackupMenu extends StatefulWidget {
  const BackupMenu({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  State<BackupMenu> createState() => _BackupMenuState();
}

class _BackupMenuState extends State<BackupMenu> {
  late final _backup = BackupManager(widget.repository);
  var _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (e) {
      // Yanlış dosya seçilmesi beklenen bir durum; teknik ayrıntı gösterme.
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$failure: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
        final saved = await _backup.saveToDownloads();
        if (saved != null && mounted) {
          _snack('${saved.count} kayıt indirildi: ${saved.location}');
        }
      }, 'İndirilemedi');

  Future<void> _share() => _run(_backup.share, 'Paylaşılamadı');

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.file_upload_outlined),
        title: const Text('Excel dosyasından yükle'),
        content: const Text(
          'Uygulamadan indirdiğiniz bir Excel dosyasını seçin: tek bir projenin '
          'dosyası da olur, tüm projeler dosyası da.\n\n'
          'Dosyadaki kayıtlar mevcut kayıtlarla birleştirilir: eksik olanlar '
          'eklenir, zaten kayıtlı olanların yalnızca boş alanları (ör. palet '
          'no) dosyadan tamamlanır.\n\n'
          'Hiçbir kayıt silinmez, dolu bir alanın üstüne yazılmaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Dosya seç'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final result = await _backup.restore();
      if (result == null || !mounted) return; // kullanıcı vazgeçti
      _snack(_restoreMessage(result));
    }, 'Yüklenemedi');
  }

  static String _restoreMessage(ImportResult result) {
    final parts = <String>[
      if (result.added > 0) '${result.added} kayıt eklendi',
      if (result.updated > 0) '${result.updated} kayıt güncellendi',
      if (result.unchanged > 0) '${result.unchanged} kayıt zaten vardı',
      if (result.skipped > 0) '${result.skipped} satır okunamadı',
    ];
    if (parts.isEmpty) return 'Dosyada kayıt bulunamadı.';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BackupAction>(
      tooltip: 'Tüm projeler',
      icon: const Icon(Icons.folder_copy_outlined),
      enabled: !_busy,
      onSelected: (action) => switch (action) {
        _BackupAction.save => _save(),
        _BackupAction.share => _share(),
        _BackupAction.restore => _restore(),
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _BackupAction.save,
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('Tümünü Excel olarak indir'),
            subtitle: Text('Bütün projeler tek dosyada'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _BackupAction.share,
          child: ListTile(
            leading: Icon(Icons.share),
            title: Text('Tümünü paylaş'),
            subtitle: Text('WhatsApp, e-posta…'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _BackupAction.restore,
          child: ListTile(
            leading: Icon(Icons.file_upload_outlined),
            title: Text('Excel dosyasından yükle'),
            subtitle: Text('İndirdiğiniz dosyayı geri alın'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
