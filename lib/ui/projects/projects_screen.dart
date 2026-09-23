import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/label_record.dart';
import '../../storage/project_repository.dart';
import '../../storage/timestamp.dart';
import '../detail/detail_screen.dart';

/// Proje listesi: son okutmaya göre sıralı, proje no ile aranabilir.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _search = TextEditingController();
  late final StreamSubscription<void> _changes;
  List<ProjectSummary>? _projects;
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
      final projects = await widget.repository.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final projects = _projects;
    final visible = projects
        ?.where((p) => query.isEmpty || p.projectNo.contains(query))
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
                text: 'Projeler okunamadı.\n$error',
              ),
            (null, _) => const Center(child: CircularProgressIndicator()),
            (final List<ProjectSummary> list, _) when list.isEmpty =>
              projects!.isEmpty
                  ? const _Message(
                      icon: Icons.inventory_2_outlined,
                      text: 'Henüz kayıt yok.\n'
                          'Okut sekmesinden bir etiket okutun.',
                    )
                  : _Message(
                      icon: Icons.search_off,
                      text: '"$query" ile eşleşen proje yok.',
                    ),
            (final List<ProjectSummary> list, _) => ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _ProjectTile(
                  project: list[i],
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(
                      repository: widget.repository,
                      projectNo: list[i].projectNo,
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

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.onTap});

  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.folder_outlined, size: 32),
      title: Text(
        project.projectNo,
        style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${project.itemCount} ürün · son okutma '
        '${formatTimestampShort(project.lastScannedAt)}',
        style: text.bodyMedium,
      ),
      trailing: const Icon(Icons.chevron_right),
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
