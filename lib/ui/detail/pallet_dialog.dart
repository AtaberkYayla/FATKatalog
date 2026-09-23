import 'package:flutter/material.dart';

import '../../model/label_record.dart';

/// Seçilen kayıtlar için palet no sorar.
///
/// Döndürür: atanacak palet no, paleti kaldırmak için boş metin, vazgeçilirse
/// `null`.
Future<String?> showPalletDialog(
  BuildContext context, {
  required List<ScanEntry> selected,
  required Set<String> projectPallets,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PalletDialog(
      selected: selected,
      projectPallets: projectPallets.toList()..sort(),
    ),
  );
}

class _PalletDialog extends StatefulWidget {
  const _PalletDialog({required this.selected, required this.projectPallets});

  final List<ScanEntry> selected;
  final List<String> projectPallets;

  @override
  State<_PalletDialog> createState() => _PalletDialogState();
}

class _PalletDialogState extends State<_PalletDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Seçilenlerin hepsi aynı paletteyse onu öner.
    final pallets = {for (final e in widget.selected) e.palletNo};
    _controller = TextEditingController(
      text: pallets.length == 1 ? pallets.single : '',
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _value => _controller.text.trim();

  void _submit() {
    if (_value.isNotEmpty) Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final count = widget.selected.length;
    final anyHasPallet = widget.selected.any((e) => e.palletNo.isNotEmpty);
    final willOverwrite = _value.isEmpty
        ? 0
        : widget.selected
            .where((e) => e.palletNo.isNotEmpty && e.palletNo != _value)
            .length;

    return AlertDialog(
      icon: const Icon(Icons.inventory_2_outlined),
      title: Text('$count kayda palet ata'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Palet No',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.projectPallets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Bu projedeki paletler', style: text.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final pallet in widget.projectPallets)
                    ChoiceChip(
                      label: Text(pallet),
                      selected: _value == pallet,
                      onSelected: (_) => _controller.value = TextEditingValue(
                        text: pallet,
                        selection:
                            TextSelection.collapsed(offset: pallet.length),
                      ),
                    ),
                ],
              ),
            ],
            if (willOverwrite > 0) ...[
              const SizedBox(height: 16),
              Text(
                '$willOverwrite kaydın mevcut paleti değişecek.',
                style: text.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (anyHasPallet)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Paleti kaldır'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _value.isEmpty ? null : _submit,
          child: const Text('Ata'),
        ),
      ],
    );
  }
}
