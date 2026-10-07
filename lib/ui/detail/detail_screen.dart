import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../export/export_manager.dart';
import '../../model/label_record.dart';
import '../../storage/project_repository.dart';
import '../../storage/timestamp.dart';
import 'pallet_dialog.dart';

enum _SortOrder { scannedAt, serialNo, palletNo }

/// Bir projenin kayıtları; çoklu seçimle palet atama ve silme, Excel indirme
/// ve paylaşma.
///
/// Kayda uzun basınca seçim modu açılır; seçim modunda dokunmak seçimi
/// değiştirir.
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.repository,
    required this.projectNo,
  });

  final ProjectRepository repository;
  final String projectNo;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final ExportManager _export = ExportManager(widget.repository);
  late final StreamSubscription<void> _changes;
  List<ScanEntry>? _entries;
  var _sort = _SortOrder.scannedAt;
  var _busy = false;

  /// Seçili kayıtların seri numaraları; boş değilse seçim modundayız.
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _changes = widget.repository.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await widget.repository.entries(widget.projectNo);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      // Başka yerden silinen kayıtlar seçimde kalmasın.
      final serials = {for (final e in entries) e.record.serialNo};
      _selected.retainAll(serials);
    });
  }

  List<ScanEntry> _sorted(List<ScanEntry> entries) {
    final list = [...entries];
    switch (_sort) {
      case _SortOrder.scannedAt:
        list.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      case _SortOrder.serialNo:
        list.sort((a, b) => a.record.serialNo.compareTo(b.record.serialNo));
      case _SortOrder.palletNo:
        // Paletliler palet no'ya göre gruplu, paletsizler en sonda.
        list.sort((a, b) {
          if (a.palletNo.isEmpty != b.palletNo.isEmpty) {
            return a.palletNo.isEmpty ? 1 : -1;
          }
          final byPallet = a.palletNo.compareTo(b.palletNo);
          return byPallet != 0
              ? byPallet
              : a.record.serialNo.compareTo(b.record.serialNo);
        });
    }
    return list;
  }

  void _toggle(ScanEntry entry) {
    setState(() {
      final serial = entry.record.serialNo;
      if (!_selected.remove(serial)) _selected.add(serial);
    });
  }

  void _selectWhere(bool Function(ScanEntry) test) {
    setState(() {
      _selected
        ..clear()
        ..addAll([
          for (final e in _entries ?? const <ScanEntry>[])
            if (test(e)) e.record.serialNo,
        ]);
    });
    if (_selected.isEmpty) _snack('Seçilecek kayıt yok');
  }

  void _clearSelection() => setState(_selected.clear);

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
    } on PlatformException catch (e) {
      _snack('$failure: ${e.message ?? e.code}');
    } catch (e) {
      _snack('$failure: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() => _run(() async {
        final location = await _export.download(widget.projectNo);
        if (location != null && mounted) _snack('Kaydedildi: $location');
      }, 'İndirilemedi');

  Future<void> _share() =>
      _run(() => _export.share(widget.projectNo), 'Paylaşılamadı');

  Future<void> _assignPallet() async {
    final entries = _entries ?? const <ScanEntry>[];
    final selected =
        entries.where((e) => _selected.contains(e.record.serialNo)).toList();
    // Palet no → ölçüsü; aynı palette ölçü girilmiş bir kayıt varsa o alınır.
    final projectPallets = <String, String>{};
    for (final e in entries) {
      if (e.palletNo.isEmpty) continue;
      projectPallets.update(
        e.palletNo,
        (size) => size.isEmpty ? e.palletSize : size,
        ifAbsent: () => e.palletSize,
      );
    }
    final assignment = await showPalletDialog(
      context,
      selected: selected,
      projectPallets: projectPallets,
    );
    if (assignment == null || !mounted) return;
    final pallet = assignment.palletNo;

    await _run(() async {
      final serials = {..._selected};
      final changed = await widget.repository.assignPallet(
        widget.projectNo,
        serials,
        pallet,
        palletSize: assignment.palletSize,
      );
      if (!mounted) return;
      _clearSelection();
      _snack(switch ((changed, pallet.isEmpty)) {
        (0, _) => 'Değişiklik yok',
        (_, true) => '$changed kaydın paleti kaldırıldı',
        (_, false) => '$changed kayda $pallet paleti atandı',
      });
    }, 'Palet atanamadı');
  }

  Future<void> _confirmDelete() async {
    final serials = {..._selected};
    final list = serials.length <= 5 ? '\n\n${serials.join('\n')}' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(serials.length == 1
            ? 'Kayıt silinsin mi?'
            : '${serials.length} kayıt silinsin mi?'),
        content: Text(
          'Seçilen kayıtlar ${widget.projectNo} projesinden silinecek. '
          'Bu işlem geri alınamaz.$list',
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
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final removed = await widget.repository.delete(widget.projectNo, serials);
      if (!mounted) return;
      _clearSelection();
      final remaining = await widget.repository.entries(widget.projectNo);
      if (!mounted) return;
      if (remaining.isEmpty) {
        Navigator.of(context).pop();
        _snack('${widget.projectNo} projesinin tüm kayıtları silindi');
      } else {
        _snack('$removed kayıt silindi');
      }
    }, 'Silinemedi');
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final hasEntries = entries != null && entries.isNotEmpty;
    return PopScope(
      // Seçim modundayken geri tuşu önce seçimi kapatır.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionAppBar() : _normalAppBar(),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (!_selecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Excel olarak indir'),
                        onPressed: hasEntries && !_busy ? _download : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share),
                        label: const Text('Paylaş'),
                        onPressed: hasEntries && !_busy ? _share : null,
                      ),
                    ),
                  ],
                ),
              ),
            if (entries != null) _SummaryRow(entries: entries),
            const Divider(height: 1),
            Expanded(
              child: entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : !hasEntries
                      ? const Center(child: Text('Bu projede kayıt yok.'))
                      : _EntryList(
                          entries: _sorted(entries),
                          selected: _selected,
                          selecting: _selecting,
                          onToggle: _toggle,
                        ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _normalAppBar() {
    return AppBar(
      title: Text('Proje ${widget.projectNo}'),
      actions: [
        PopupMenuButton<_SortOrder>(
          tooltip: 'Sırala',
          icon: const Icon(Icons.sort),
          initialValue: _sort,
          onSelected: (order) => setState(() => _sort = order),
          itemBuilder: (_) => [
            for (final (order, label) in [
              (_SortOrder.scannedAt, 'Okutma zamanı'),
              (_SortOrder.serialNo, 'Seri No'),
              (_SortOrder.palletNo, 'Palet No'),
            ])
              CheckedPopupMenuItem(
                value: order,
                checked: _sort == order,
                child: Text(label),
              ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionAppBar() {
    return AppBar(
      leading: IconButton(
        tooltip: 'Seçimi kapat',
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} seçili'),
      actions: [
        IconButton(
          tooltip: 'Palet ata',
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed: _busy ? null : _assignPallet,
        ),
        IconButton(
          tooltip: 'Sil',
          icon: const Icon(Icons.delete_outline),
          onPressed: _busy ? null : _confirmDelete,
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Seçim',
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: () => _selectWhere((_) => true),
              child: const Text('Tümünü seç'),
            ),
            PopupMenuItem(
              value: () => _selectWhere((e) => e.palletNo.isEmpty),
              child: const Text('Paleti olmayanları seç'),
            ),
            PopupMenuItem(
              value: _clearSelection,
              child: const Text('Seçimi temizle'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.entries});

  final List<ScanEntry> entries;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final withPallet = entries.where((e) => e.palletNo.isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text(
            '${entries.length} ürün · $withPallet paletli',
            style: text.titleMedium,
          ),
          const Spacer(),
          Text('Seçmek için uzun basın', style: text.bodySmall),
        ],
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.entries,
    required this.selected,
    required this.selecting,
    required this.onToggle,
  });

  final List<ScanEntry> entries;
  final Set<String> selected;
  final bool selecting;
  final void Function(ScanEntry) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _EntryTile(
          entry: entry,
          selecting: selecting,
          selected: selected.contains(entry.record.serialNo),
          onTap: selecting ? () => onToggle(entry) : null,
          onLongPress: () => onToggle(entry),
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ScanEntry entry;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final r = entry.record;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      leading: selecting
          ? Checkbox(value: selected, onChanged: (_) => onLongPress())
          : null,
      title: Row(
        children: [
          Expanded(
            child: Text(
              r.serialNo,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (entry.palletNo.isNotEmpty)
            _PalletBadge(entry.palletNo, entry.palletSize),
        ],
      ),
      subtitle: Text(
        'İş Emri: ${r.workOrderNo} · Erp Ürün: ${r.erpProductNo}'
        '${r.positionNo.isEmpty ? '' : ' · Poz: ${r.positionNo}'}\n'
        'Üretim: ${r.productionDate} · Okutma: ${formatTimestamp(entry.scannedAt)}',
      ),
      isThreeLine: true,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _PalletBadge extends StatelessWidget {
  const _PalletBadge(this.palletNo, this.palletSize);

  final String palletNo;

  /// `Genişlik x Uzunluk` (mm); girilmemişse boş.
  final String palletSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Palet $palletNo',
            style: TextStyle(
              color: scheme.onSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (palletSize.isNotEmpty)
            Text(
              '$palletSize mm',
              style: TextStyle(color: scheme.onSecondary, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
