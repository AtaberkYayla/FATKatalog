import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/label_record.dart';
import '../../storage/project_repository.dart';
import '../../storage/timestamp.dart';
import '../detail/detail_screen.dart';

/// Arşive alınmış proje listeleri: `8900 (13.10.2026-15:41)`; arşivleme
/// zamanına göre yeniden eskiye, proje no ile aranabilir. Listeler salt
/// okunur açılır; yalnızca silinebilir.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _search = TextEditingController();
  late final StreamSubscription<void> _changes;
  List<ArchiveSummary>? _archives;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _changes = widget.repository.changes.listen((_) => _load());
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final archives = await widget.repository.listArchives();
      if (!mounted) return;
      setState(() {
        _archives = archives;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _confirmDelete(ArchiveSummary archive) async {
    final label =
        '${archive.projectNo} (${formatArchiveLabel(archive.archivedAt)})';
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Arşiv silinsin mi?'),
        content: Text(
          '$label listesindeki ${archive.itemCount} kayıt telefondan kalıcı '
          'olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteArchive(archive.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$label arşivden silindi')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final archives = _archives;
    final visible = archives
        ?.where((a) => query.isEmpty || a.projectNo.contains(query))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Proje no ara',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.clear),
                      onPressed: _search.clear,
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: switch ((visible, _error)) {
            (_, final Object error) => _Message(
                icon: Icons.error_outline,
                text: 'Arşiv okunamadı.\n$error',
              ),
            (null, _) => const Center(child: CircularProgressIndicator()),
            (final List<ArchiveSummary> list, _) when list.isEmpty =>
              archives!.isEmpty
                  ? const _Message(
                      icon: Icons.archive_outlined,
                      text: 'Arşivde liste yok.\n'
                          'Projeler sekmesinde bir projeye uzun basarak '
                          'arşive alabilirsiniz.',
                    )
                  : _Message(
                      icon: Icons.search_off,
                      text: '"$query" ile eşleşen arşiv yok.',
                    ),
            (final List<ArchiveSummary> list, _) => ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _ArchiveTile(
                  archive: list[i],
                  onDelete: () => unawaited(_confirmDelete(list[i])),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(
                      repository: widget.repository,
                      projectNo: list[i].projectNo,
                      archive: list[i],
                    ),
                  )),
                ),
              ),
          },
        ),
      ],
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.archive,
    required this.onTap,
    required this.onDelete,
  });

  final ArchiveSummary archive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
      leading: const Icon(Icons.archive_outlined, size: 32),
      title: Text(
        '${archive.projectNo} (${formatArchiveLabel(archive.archivedAt)})',
        style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('${archive.itemCount} ürün', style: text.bodyMedium),
      trailing: IconButton(
        tooltip: 'Arşivden sil',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
