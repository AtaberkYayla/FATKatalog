import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/label_record.dart';
import '../../model/pallet_size.dart';

/// Palet diyaloğunun sonucu: atanacak palet no ve ölçüsü (`Genişlik x
/// Uzunluk`, mm). Paleti kaldırmak için ikisi de boş.
class PalletAssignment {
  const PalletAssignment({required this.palletNo, this.palletSize = ''});

  const PalletAssignment.remove() : this(palletNo: '');

  final String palletNo;
  final String palletSize;
}

/// Seçilen kayıtlar için palet no ve ölçüsünü sorar.
///
/// [projectPallets]: projede kullanılmış palet no → ölçüsü (ölçü girilmemişse
/// boş). Döndürür: atama, vazgeçilirse `null`.
Future<PalletAssignment?> showPalletDialog(
  BuildContext context, {
  required List<ScanEntry> selected,
  required Map<String, String> projectPallets,
}) {
  return showDialog<PalletAssignment>(
    context: context,
    builder: (_) => _PalletDialog(
      selected: selected,
      projectPallets: projectPallets,
    ),
  );
}

class _PalletDialog extends StatefulWidget {
  const _PalletDialog({required this.selected, required this.projectPallets});

  final List<ScanEntry> selected;
  final Map<String, String> projectPallets;

  @override
  State<_PalletDialog> createState() => _PalletDialogState();
}

class _PalletDialogState extends State<_PalletDialog> {
  final _palletNo = TextEditingController();
  final _width = TextEditingController();
  final _length = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Seçilenlerin hepsi aynı paletteyse onu (ve ölçüsünü) öner.
    final pallets = {for (final e in widget.selected) e.palletNo};
    if (pallets.length == 1) {
      _palletNo.text = pallets.single;
      final sizes = {for (final e in widget.selected) e.palletSize};
      if (sizes.length == 1) _setSize(sizes.single);
    }
    for (final c in [_palletNo, _width, _length]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _palletNo.dispose();
    _width.dispose();
    _length.dispose();
    super.dispose();
  }

  void _setSize(String text) {
    final size = PalletSize.tryParse(text);
    _width.text = size?.width ?? '';
    _length.text = size?.length ?? '';
  }

  String get _value => _palletNo.text.trim();

  PalletSize get _size => PalletSize(_width.text.trim(), _length.text.trim());

  /// Ölçü ya hiç girilmemeli ya da genişlik ve uzunluk birlikte girilmeli.
  bool get _canSubmit => _value.isNotEmpty && _size.isValid;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context)
        .pop(PalletAssignment(palletNo: _value, palletSize: _size.text));
  }

  void _pick(String pallet) {
    _palletNo.value = TextEditingValue(
      text: pallet,
      selection: TextSelection.collapsed(offset: pallet.length),
    );
    // Palet projede zaten ölçüsüyle biliniyorsa onu getir.
    final known = widget.projectPallets[pallet] ?? '';
    if (known.isNotEmpty) _setSize(known);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final count = widget.selected.length;
    final anyHasPallet = widget.selected.any((e) => e.palletNo.isNotEmpty);
    final willOverwrite = _value.isEmpty
        ? 0
        : widget.selected
            .where((e) => e.palletNo.isNotEmpty && e.palletNo != _value)
            .length;
    final pallets = widget.projectPallets.keys.toList()..sort();
    final sizeIncomplete = !_size.isValid;

    return AlertDialog(
      icon: const Icon(Icons.inventory_2_outlined),
      title: Text('$count kayda palet ata'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _palletNo,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Palet No',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SizeField(
                    controller: _width,
                    label: 'Genişlik',
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 16, left: 8, right: 8),
                  child: Text('x'),
                ),
                Expanded(
                  child: _SizeField(
                    controller: _length,
                    label: 'Uzunluk',
                    textInputAction: TextInputAction.done,
                    onSubmitted: _submit,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Text(
                sizeIncomplete
                    ? 'Genişlik ve uzunluğu birlikte girin.'
                    : 'Palet ölçüsü (mm): Genişlik x Uzunluk',
                style: text.bodySmall?.copyWith(
                  color: sizeIncomplete ? theme.colorScheme.error : null,
                ),
              ),
            ),
            if (pallets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Bu projedeki paletler', style: text.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final pallet in pallets)
                    ChoiceChip(
                      label: Text(pallet),
                      selected: _value == pallet,
                      onSelected: (_) => _pick(pallet),
                    ),
                ],
              ),
            ],
            if (willOverwrite > 0) ...[
              const SizedBox(height: 16),
              Text(
                '$willOverwrite kaydın mevcut paleti değişecek.',
                style: text.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (anyHasPallet)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const PalletAssignment.remove()),
            child: const Text('Paleti kaldır'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('Ata'),
        ),
      ],
    );
  }
}

class _SizeField extends StatelessWidget {
  const _SizeField({
    required this.controller,
    required this.label,
    required this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: textInputAction,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'mm',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
